import SwiftUI
import WimgI18n

struct FinTSView: View {
    var onViewTransactions: (() -> Void)?

    enum Stage {
        case bankSelect
        case credentials
        case tanMediumSelect
        case tanChallenge
        case dateRange
        case fetching
        case result
    }

    @State private var stage: Stage = .bankSelect
    @State private var banks: [BankInfo] = []
    @State private var banksLower: [String] = [] // precomputed lowercased names for fast search
    @State private var loadingBanks = false
    @State private var searchText = ""
    @State private var displayBanks: [BankInfo] = []
    @State private var selectedBank: BankInfo?
    @State private var errorMessage: String?

    // Cached keychain reads — avoid sync XPC to securityd on every body re-render.
    // Refreshed in onAppear and after writes (handleConnect, clearFintsPIN sites).
    @State private var cachedSavedBank: BankInfo?
    @State private var cachedHasPIN: Bool = false

    @State private var showAllBanks = false
    @FocusState private var searchFocused: Bool

    // Credentials
    @State private var kennung = ""
    @State private var pin = ""
    @State private var rememberPIN = false
    @State private var connecting = false
    @State private var refreshing = false

    // TAN
    @State private var challengeText = ""
    @State private var photoTanData: Data?
    @State private var showInvertedPhotoTan = false
    @State private var isDecoupledChallenge = false
    @State private var tanInput = ""
    @State private var sendingTan = false

    // TAN Medium Selection
    @State private var tanMedia: [TanMediumInfo] = []
    @State private var loadingTanMedia = false

    // Date range
    @State private var dateFrom = Calendar.current.date(byAdding: .month, value: -12, to: Date())!
    @State private var dateTo = Date()
    // Latest known transaction date for the active account (nil = first import).
    // Drives smart date defaults: incremental from latest, full history otherwise.
    @State private var latestImportDate: Date?

    // Result
    @State private var importedCount = 0
    @State private var duplicateCount = 0
    @State private var categorizing = false
    @State private var categorizedCount: Int? = nil

    private var photoTanImage: UIImage? {
        guard let data = photoTanData else { return nil }
        return UIImage(data: data)
    }

    /// The bank's accounts (balance in the band of the connected page).
    @State private var bankAccounts: [Account] = []
    @State private var connections: [BankConnection] = []
    @State private var removing: BankConnection?

    private var stepIndex: Int {
        switch stage {
        case .bankSelect: 1
        case .credentials: 2
        case .tanMediumSelect, .tanChallenge: 3
        case .dateRange: 4
        case .fetching, .result: 5
        }
    }

    var body: some View {
        content
            .animation(WimgMotion.out(0.18), value: errorMessage)
            .task(id: searchText) {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let query = searchText
                let allBanks = banks
                let allLower = banksLower
                let filtered = await Task.detached(priority: .userInitiated) {
                    if query.isEmpty { return Array(allBanks.prefix(50)) }
                    let q = query.lowercased()
                    var result: [BankInfo] = []
                    for i in 0..<allBanks.count where allLower[i].contains(q) || allBanks[i].blz.contains(q) {
                        result.append(allBanks[i])
                        if result.count >= 50 { break }
                    }
                    return result
                }.value
                guard !Task.isCancelled else { return }
                displayBanks = filtered
            }
            .onAppear(perform: loadSaved)
            .confirmationDialog(L("%s entfernen?", removing?.name ?? ""),
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button(L("Entfernen"), role: .destructive) { if let c = removing { removeConnection(c) }; removing = nil }
                Button(L("Abbrechen"), role: .cancel) { removing = nil }
            } message: {
                Text(L("Anmeldung und PIN werden von diesem Gerät gelöscht. Die Umsätze bleiben."))
            }
            .task { bankAccounts = await Task.detached { LibWimg.getAccounts() }.value }
            .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
                Task { bankAccounts = await Task.detached { LibWimg.getAccounts() }.value }
            }
    }

    @ViewBuilder private var content: some View {
        if stage == .bankSelect, let bank = cachedSavedBank, searchText.isEmpty, !showAllBanks {
            connectedPage(bank)
        } else {
            BandScreen(title: L("Bank verbinden"), pushed: true) {
                stepBand
            } sheet: {
                if let error = errorMessage {
                    errorBanner(classify(error)).padding(.bottom, 12)
                }
                switch stage {
                case .bankSelect: bankPicker
                case .credentials: credentialsSection
                case .tanMediumSelect: tanMediumSelectSection
                case .tanChallenge: tanChallengeSection
                case .dateRange: dateRangeSection
                case .fetching: fetchingSection
                case .result: resultSection
                }
            }
        }
    }

    /// "Bank verbinden · Schritt n von 5", a segmented line, the step's title.
    @ViewBuilder private var stepBand: some View {
        Text(L("Schritt %d von %d", stepIndex, 5)).wimgStyle(WimgType.bandOver).foregroundStyle(Wimg.bandSub)
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Capsule().fill(i <= stepIndex ? Color.white : Color.white.opacity(0.18)).frame(height: 4)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
        .accessibilityHidden(true)
        Text(stepTitle).wimgStyle(WimgType.title).foregroundStyle(.white)
    }

    private var stepTitle: String {
        switch stage {
        case .bankSelect: L("Welche Bank?")
        case .credentials: selectedBank?.name ?? L("Anmelden")
        case .tanMediumSelect: L("TAN-Medium wählen")
        case .tanChallenge: isDecoupledChallenge ? L("Freigabe in der Banking-App") : L("TAN eingeben")
        case .dateRange: L("Zeitraum wählen")
        case .fetching: L("Umsätze werden abgerufen")
        case .result: L("Abruf fertig")
        }
    }

    // MARK: - Connected bank (Android board 7/03)

    private func connectedPage(_ bank: BankInfo) -> some View {
        let withBalance = bankAccounts.filter { $0.balance != nil }
        let balance = withBalance.isEmpty ? nil : withBalance.reduce(0) { $0 + ($1.balance ?? 0) }
        return BandScreen(title: L("Bankverbindung"), pushed: true) {
            BandOver(text: bank.name)
            if let balance {
                Amount(euros: balance, style: WimgType.amountHero, centsStyle: WimgType.amountHeroCents,
                       color: .white, showPlus: false)
                    .padding(.top, 2)
                if let d = withBalance.map(\.balanceDate).max() {
                    Text(L("Stand %s · gebuchter Saldo, nicht live", WimgDates.full(d)))
                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).padding(.top, 4)
                }
            } else {
                Text(L("Kontostand nach dem ersten Abruf")).wimgStyle(WimgType.title).foregroundStyle(.white).padding(.top, 4)
            }
        } sheet: {
            if let error = errorMessage {
                errorBanner(classify(error)).padding(.bottom, 12)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    bankBadge(bank, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bank.name).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(1)
                        Text(L("BLZ %s", bank.blz)).wimgStyle(WimgType.mono).foregroundStyle(Wimg.text2)
                    }
                }
                HStack(spacing: 8) {
                    chip(cachedHasPIN ? L("PIN gespeichert") : L("PIN nicht gespeichert"), systemImage: cachedHasPIN ? "lock" : nil,
                         dashed: !cachedHasPIN)
                    if let medium = KeychainService.get(KeychainService.fintsTanMedium), !medium.isEmpty { chip(medium) }
                }
                Rectangle().fill(Wimg.line).frame(height: 1)
                Text(cachedHasPIN ? L("Schnellabfrage holt die letzten 90 Tage und geht direkt zur TAN, falls die Bank eine verlangt.")
                                  : L("Abruf nur mit Anmeldung"))
                    .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
            }
            .padding(18)
            .background(Wimg.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Wimg.line, lineWidth: 1))

            primaryButton(cachedHasPIN ? L("Schnellabfrage") : L("Anmelden"),
                          systemImage: cachedHasPIN ? "arrow.clockwise" : "lock.shield",
                          busy: refreshing, disabled: refreshing || connecting) {
                if cachedHasPIN { Task { await handleQuickRefresh() } } else { stage = .credentials }
            }
            .padding(.top, 16)

            Spacer().frame(height: 12)
            WimgGroup {
                WimgRow(title: L("Anderen Zeitraum abrufen"), desc: L("Älteres nachholen oder eine Lücke füllen"), chevron: true,
                        action: { stage = cachedHasPIN ? .dateRange : .credentials }) {
                    IconTile(systemImage: "calendar", tint: Wimg.text2)
                }
                if cachedHasPIN {
                    RowDivider()
                    WimgRow(title: L("PIN vergessen"), desc: L("Beim nächsten Abruf neu anmelden"), action: forgetPIN) {
                        IconTile(systemImage: "lock.open", tint: Wimg.text2)
                    }
                }
                RowDivider()
                WimgRow(title: L("Andere Bank verbinden"), chevron: true, action: { showAllBanks = true; searchFocused = true }) {
                    IconTile(systemImage: "plus", tint: Wimg.text2)
                }
            }
            otherBanks(current: bank)
            QuietLine(text: L("FinTS 3.0, direkt mit deiner Bank. Kein Dienst dazwischen; Anmeldedaten verlassen dein Gerät nicht."),
                      systemImage: "checkmark.shield")
        }
    }

    /// The other bank logins: tap to switch, swipe the row's menu to remove.
    @ViewBuilder private func otherBanks(current: BankInfo) -> some View {
        let others = connections.filter { $0.id != BankConnections.activeId }
        if !others.isEmpty {
            GroupLabel(text: L("Weitere Banken"))
            WimgGroup {
                ForEach(Array(others.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { RowDivider() }
                    let info = banks.first { $0.blz == c.blz }
                    WimgRow(title: info?.name ?? c.name,
                            desc: [BankConnections.hasPIN(c) ? L("PIN gespeichert") : L("PIN nicht gespeichert"),
                                   c.lastFetchAt > 0 ? L("zuletzt abgerufen %s", SyncDevicesView.ago(Int64(c.lastFetchAt * 1000))) : L("noch nicht abgerufen")]
                                .joined(separator: " · "),
                            chevron: true, action: { switchTo(c) }) {
                        if let info { bankBadge(info, size: 36) }
                    }
                    .contextMenu {
                        Button(role: .destructive) { removing = c } label: { Label(L("Entfernen"), systemImage: "trash") }
                    }
                }
            }
        }
        if let active = BankConnections.active {
            Button(role: .destructive) { removing = active } label: {
                Text(L("%s entfernen", current.name)).wimgStyle(WimgType.chip).foregroundStyle(Wimg.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.top, 8)
        }
    }

    private func switchTo(_ c: BankConnection) {
        BankConnections.activate(c.id)
        errorMessage = nil
        selectedBank = nil
        loadSaved()
    }

    private func removeConnection(_ c: BankConnection) {
        BankConnections.remove(c.id)
        if !BankConnections.anyWithPIN { BackgroundRefresh.cancel() }
        connections = BankConnections.all()
        selectedBank = nil
        pin = ""; kennung = ""; rememberPIN = false
        loadSaved()
        Dock.shared.info(L("Bank entfernt"), sub: L("Ihre Umsätze bleiben in wimg."))
    }

    private func forgetPIN() {
        KeychainService.clearFintsPIN(); BankConnections.storeActiveSlots(name: selectedBank?.name ?? "")
        pin = ""
        rememberPIN = false
        refreshCachedKeychainState()
        BackgroundRefresh.cancel()
        Dock.shared.info(L("PIN vergessen"))
    }

    // MARK: - Pieces

    private func bankBadge(_ bank: BankInfo, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(brandColor(for: bank))
            .frame(width: size, height: size)
            .overlay(Text(brandBadge(for: bank)).font(WimgFont.font(.manrope, .heavy, size * 0.4)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }

    private func chip(_ text: String, systemImage: String? = nil, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)) }
            Text(text).wimgStyle(WimgType.desc).lineLimit(1)
        }
        .foregroundStyle(dashed ? Wimg.text2 : Wimg.text)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(dashed ? Color.clear : Wimg.neutralTint, in: Capsule())
        .overlay { if dashed { Capsule().stroke(Wimg.text3, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) } }
    }

    private func primaryButton(_ title: String, systemImage: String? = nil, busy: Bool = false, disabled: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(Wimg.onAccent)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).wimgStyle(WimgType.button)
            }
            .foregroundStyle(Wimg.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Wimg.accent.opacity(disabled && !busy ? 0.45 : 1), in: Capsule())
        }
        .buttonStyle(.wimgPress)
        .disabled(disabled)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .wimgStyle(WimgType.chip)
            .foregroundStyle(Wimg.text2)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func field(_ label: String, _ text: Binding<String>, prompt: String, secure: Bool = false, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
            Group {
                if secure {
                    SecureField(prompt, text: text)
                } else {
                    TextField(prompt, text: text)
                        .keyboardType(numeric ? .numberPad : .default)
                }
            }
            .font(WimgType.rowTitle.font)
            .foregroundStyle(Wimg.text)
            // No iCloud Keychain AutoFill scan: nobody has a FinTS login saved there.
            .textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous).stroke(Wimg.line, lineWidth: 1))
        }
    }

    // MARK: - Step 1: bank picker

    @ViewBuilder private var bankPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Wimg.text2)
            TextField(L("Bank oder BLZ suchen"), text: $searchText)
                .font(WimgType.body.font)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Wimg.text3) }
                    .accessibilityLabel(L("Leeren"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Wimg.neutralTint, in: RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous))

        if searchText.isEmpty {
            GroupLabel(text: L("Häufig gewählt"))
            WimgGroup {
                ForEach(Array(Self.popularBanks.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { RowDivider() }
                    WimgRow(title: p.label, chevron: true, action: { handlePopularTap(p) }) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(p.color).frame(width: 36, height: 36)
                            .overlay(Text(p.badge).font(WimgFont.font(.manrope, .heavy, 13)).foregroundStyle(.white))
                    }
                }
            }
        }
        GroupLabel(text: searchText.isEmpty ? L("Alle Banken") : L("Treffer"))
        WimgGroup {
            if loadingBanks {
                WimgRow(title: L("Lade Banken…"))
            }
            ForEach(Array(displayBanks.enumerated()), id: \.element.id) { i, bank in
                if i > 0 { RowDivider() }
                WimgRow(title: bank.name, desc: L("BLZ %s", bank.blz), chevron: true, action: { pick(bank) }) {
                    bankBadge(bank, size: 36)
                }
            }
            if displayBanks.isEmpty && !loadingBanks {
                WimgRow(title: L("Keine Bank gefunden"))
            }
        }
        QuietLine(text: L("FinTS 3.0, direkt mit deiner Bank. Kein Dienst dazwischen; Anmeldedaten verlassen dein Gerät nicht."),
                  systemImage: "checkmark.shield")
        if cachedSavedBank != nil {
            secondaryButton(L("Zurück zur verbundenen Bank")) { showAllBanks = false; searchText = ""; searchFocused = false }
        }
    }

    private func pick(_ bank: BankInfo) {
        selectedBank = bank
        errorMessage = nil
        kennung = ""
        pin = ""
        rememberPIN = false
        searchFocused = false
        stage = .credentials
    }

    // MARK: - Step 2: login

    @ViewBuilder private var credentialsSection: some View {
        if let bank = selectedBank {
            HStack(spacing: 12) {
                bankBadge(bank, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bank.name).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(1)
                    Text(L("BLZ %s", bank.blz)).wimgStyle(WimgType.mono).foregroundStyle(Wimg.text2)
                }
                Spacer()
                Button(L("Ändern")) { resetToBank() }
                    .wimgStyle(WimgType.chip).foregroundStyle(Wimg.accent)
                    .disabled(connecting)
            }
            .padding(.bottom, 16)
        }
        VStack(spacing: 14) {
            field(L("Kennung"), $kennung, prompt: L("Benutzername / Anmeldekennung"))
            field("PIN", $pin, prompt: L("Online-Banking PIN"), secure: true)
        }
        Spacer().frame(height: 14)
        WimgGroup {
            Toggle(isOn: $rememberPIN) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("PIN merken")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                    Text(L("Verschlüsselt, nur auf diesem Gerät · nötig für Schnellabfrage und Hintergrund-Abruf"))
                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
            }
            .toggleStyle(.wimg)
            .padding(.horizontal, 16)
            .frame(minHeight: 68)
        }
        QuietLine(text: L("Mehrere fehlgeschlagene Anmeldungen können dein Konto bei der Bank sperren. Bitte PIN sorgfältig eingeben."),
                  systemImage: "exclamationmark.triangle", color: Wimg.warn)
        primaryButton(L("Verbinden"), busy: connecting, disabled: connecting || kennung.isEmpty || pin.isEmpty) {
            Task { await handleConnect() }
        }
        .padding(.top, 8)
    }

    // MARK: - Step 3: TAN medium

    @ViewBuilder private var tanMediumSelectSection: some View {
        Text(L("Deine Bank möchte wissen, auf welches Gerät die TAN kommt."))
            .wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).padding(.bottom, 12)
        WimgGroup {
            if loadingTanMedia {
                WimgRow(title: L("Lade TAN-Medien…"))
            }
            ForEach(Array(tanMedia.enumerated()), id: \.element.id) { i, medium in
                if i > 0 { RowDivider() }
                WimgRow(title: medium.name, desc: medium.status == 1 ? L("Aktiv") : L("Inaktiv"), chevron: true,
                        action: { Task { await handleSelectTanMedium(medium.name) } }) {
                    IconTile(systemImage: "iphone", tint: medium.status == 1 ? Wimg.accent : Wimg.text2)
                }
            }
        }
        if tanMedia.isEmpty && !loadingTanMedia {
            primaryButton(L("Weiter ohne Auswahl")) {
                stage = .fetching
                Task { await handleFetch() }
            }
            .padding(.top, 14)
        }
        secondaryButton(L("Zurück")) { stage = .credentials }
    }

    // MARK: - Step 3: TAN

    @ViewBuilder private var tanChallengeSection: some View {
        if isDecoupledChallenge {
            VStack(spacing: 10) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 40, weight: .light)).foregroundStyle(Wimg.accent)
                Text(L("Bitte in deiner Banking-App bestätigen")).wimgStyle(WimgType.section).foregroundStyle(Wimg.text)
                    .multilineTextAlignment(.center)
                Text(L("Öffne die App deiner Bank und gib den Abruf frei. Danach hier auf „Status prüfen“ tippen."))
                    .wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        if let uiImage = photoTanImage {
            VStack(spacing: 10) {
                Group {
                    if showInvertedPhotoTan {
                        Image(uiImage: uiImage).resizable().scaledToFit().colorInvert()
                    } else {
                        Image(uiImage: uiImage).resizable().scaledToFit()
                    }
                }
                .frame(maxWidth: 260, maxHeight: 260)
                .padding(14)
                .background(Color.black, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
                .accessibilityLabel("photoTAN")
                Button(showInvertedPhotoTan ? L("Normale Ansicht") : L("Invertierte Ansicht")) { showInvertedPhotoTan.toggle() }
                    .wimgStyle(WimgType.chip).foregroundStyle(Wimg.accent)
                Text(L("Mit der photoTAN-App scannen und die TAN eingeben."))
                    .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
        }
        if !challengeText.isEmpty && photoTanImage == nil {
            GroupLabel(text: L("Meldung der Bank"))
            Text(challengeText).wimgStyle(WimgType.body).foregroundStyle(Wimg.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))
        }
        if photoTanImage == nil && challengeText.localizedCaseInsensitiveContains("siehe grafik") {
            QuietLine(text: L("Diese TAN-Freigabe erwartet eine scanbare Grafik. Wenn kein Bild angezeigt wird, liefert die Bank ggf. ein nicht direkt darstellbares photoTAN-Format."))
        }
        if !isDecoupledChallenge {
            field("TAN", $tanInput, prompt: L("TAN eingeben"), numeric: true).padding(.top, 12)
        }
        primaryButton(isDecoupledChallenge ? L("Status prüfen") : L("TAN senden"), busy: sendingTan,
                      disabled: sendingTan || (!isDecoupledChallenge && tanInput.isEmpty)) {
            Task { await handleSendTan() }
        }
        .padding(.top, 16)
    }

    // MARK: - Step 4: date range

    @ViewBuilder private var dateRangeSection: some View {
        Text(latestImportDate.map { L("Letzter Umsatz: %s", formatShortDate($0)) } ?? L("Erstmaliger Abruf – 12 Monate Historie"))
            .wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).padding(.bottom, 12)
        WimgGroup {
            DatePicker(selection: $dateFrom, in: tenYearsAgo...dateTo, displayedComponents: .date) {
                Text(L("Von")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
            }
            .padding(.horizontal, 16).frame(minHeight: WimgDimens.rowMinHeight)
            RowDivider()
            // `Bis` never in the future: banks reject it.
            DatePicker(selection: $dateTo, in: dateFrom...Date(), displayedComponents: .date) {
                Text(L("Bis")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
            }
            .padding(.horizontal, 16).frame(minHeight: WimgDimens.rowMinHeight)
        }
        .environment(\.locale, Locale(identifier: UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE"))
        // Bank history limits vary (Comdirect ~25 months, Sparkasse 90 days); "Alle" lets the bank cut.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(datePresets, id: \.label) { preset in
                    Button {
                        dateFrom = Calendar.current.date(byAdding: preset.component, value: -preset.value, to: Date()) ?? dateFrom
                        dateTo = Date()
                    } label: {
                        Text(preset.label).wimgStyle(WimgType.chip).foregroundStyle(Wimg.text)
                            .padding(.horizontal, 14).frame(height: 38)
                            .background(Wimg.neutralTint, in: Capsule())
                    }
                    .buttonStyle(.wimgPress)
                }
            }
        }
        .padding(.top, 12)
        primaryButton(L("Umsätze abrufen"), systemImage: "arrow.down", busy: connecting, disabled: connecting) {
            // Always a new dialog: the last fetch closed the previous one (HKEND).
            Task { await handleReFetch() }
        }
        .padding(.top, 16)
        .task {
            await loadLatestImportDate(forBank: selectedBank?.name)
            applySmartDateDefaults()
        }
    }

    // MARK: - Step 5: fetching and result

    private var fetchingSection: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Wimg.accent)
            Text(selectedBank?.name ?? "").wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
            Text(L("Das dauert meist ein paar Sekunden.")).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder private var resultSection: some View {
        WimgGroup {
            if let bank = selectedBank { resultRow(L("Bank"), bank.name) }
            RowDivider()
            resultRow(L("Neu"), importedCount == 1 ? L("1 Umsatz") : L("%d Umsätze", importedCount))
            if duplicateCount > 0 {
                RowDivider()
                resultRow(L("Schon da"), "\(duplicateCount)")
            }
            RowDivider()
            resultRow(L("Zeitraum"), "\(formatShortDate(dateFrom)) – \(formatShortDate(dateTo))")
        }
        if importedCount > 0 {
            primaryButton(categorizedCount.map { L("%d kategorisiert", $0) } ?? L("Kategorisieren"),
                          systemImage: categorizedCount == nil ? "tag" : "checkmark", busy: categorizing,
                          disabled: categorizing || categorizedCount != nil) {
                categorizing = true
                // Off-main: rules over every uncategorised row.
                Task.detached(priority: .userInitiated) {
                    let count = LibWimg.autoCategorize()
                    await MainActor.run {
                        categorizing = false
                        categorizedCount = count
                        Changes.bump()
                    }
                }
            }
            .padding(.top, 16)
        }
        Spacer().frame(height: 12)
        WimgGroup {
            WimgRow(title: L("Umsätze ansehen"), chevron: true, action: {
                if let onViewTransactions { onViewTransactions() } else { AppNav.shared.open(.transactions) }
            }) { IconTile(systemImage: "list.bullet", tint: Wimg.accent) }
            RowDivider()
            WimgRow(title: L("Anderen Zeitraum abrufen"), chevron: true, action: { stage = .dateRange }) {
                IconTile(systemImage: "calendar", tint: Wimg.text2)
            }
            RowDivider()
            WimgRow(title: L("Fertig"), action: { stage = .bankSelect; refreshCachedKeychainState() }) {
                IconTile(systemImage: "checkmark", tint: Wimg.pos)
            }
        }
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
            Spacer(minLength: 12)
            Text(value).wimgStyle(WimgType.body).foregroundStyle(Wimg.text).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: WimgDimens.rowMinHeight)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Saved login

    private func loadSaved() {
        if banks.isEmpty { loadingBanks = true }
        connections = BankConnections.all()
        // Keychain reads are sync XPC: off the main thread.
        Task.detached(priority: .userInitiated) {
            let savedBLZ = KeychainService.get(KeychainService.fintsBLZ)
            let savedKennung = KeychainService.get(KeychainService.fintsKennung)
            let savedPIN = KeychainService.get(KeychainService.fintsPIN)
            let needsBankLoad = await MainActor.run { banks.isEmpty }
            let loaded = needsBankLoad ? LibWimg.fintsGetBanks() : []
            let lower = loaded.map { $0.name.lowercased() }
            await MainActor.run {
                if needsBankLoad {
                    banks = loaded
                    banksLower = lower
                    displayBanks = Array(loaded.prefix(50))
                    loadingBanks = false
                }
                if let blz = savedBLZ, let bank = banks.first(where: { $0.blz == blz }) {
                    if stage == .bankSelect {
                        pin = ""; rememberPIN = false
                        selectedBank = bank
                        kennung = savedKennung ?? ""
                        if let p = savedPIN { pin = p; rememberPIN = true }
                    }
                    cachedSavedBank = bank
                } else {
                    cachedSavedBank = nil
                }
                cachedHasPIN = savedPIN != nil
            }
        }
    }

    // MARK: - Bank catalogue helpers

    private struct PopularBank: Identifiable {
        let id: String
        let label: String
        let badge: String
        let color: Color
        let kind: Kind
        enum Kind { case direct(blz: String); case filter(text: String) }
    }

    private static let popularBanks: [PopularBank] = [
        .init(id: "20041177", label: "Comdirect", badge: "C", color: Color(red: 1.0, green: 0.84, blue: 0.0), kind: .direct(blz: "20041177")),
        .init(id: "Sparkasse", label: "Sparkasse", badge: "S", color: Color(red: 0.91, green: 0.0, blue: 0.0), kind: .filter(text: "Sparkasse")),
        .init(id: "Volksbank", label: "Volksbank", badge: "VB", color: Color(red: 0.0, green: 0.29, blue: 0.6), kind: .filter(text: "Volksbank")),
        .init(id: "50010517", label: "ING", badge: "ING", color: Color(red: 1.0, green: 0.384, blue: 0.0), kind: .direct(blz: "50010517")),
        .init(id: "10070000", label: "Deutsche Bank", badge: "DB", color: Color(red: 0.0, green: 0.094, blue: 0.659), kind: .direct(blz: "10070000")),
    ]

    private func brandColor(for bank: BankInfo) -> Color {
        for p in Self.popularBanks {
            if case .direct(let blz) = p.kind, blz == bank.blz { return p.color }
        }
        let lower = bank.name.lowercased()
        if lower.contains("sparkasse") { return Color(red: 0.91, green: 0.0, blue: 0.0) }
        if lower.contains("volksbank") || lower.contains("raiffeisen") || lower.contains("vr ") { return Color(red: 0.0, green: 0.29, blue: 0.6) }
        if lower.contains("postbank") || lower.contains("commerzbank") { return Color(red: 1.0, green: 0.8, blue: 0.0) }
        if lower.contains("deutsche bank") { return Color(red: 0.0, green: 0.094, blue: 0.659) }
        if lower.contains("ing") { return Color(red: 1.0, green: 0.384, blue: 0.0) }
        if lower.contains("dkb") { return Color(red: 0.0, green: 0.49, blue: 0.78) }
        return Wimg.accent
    }

    private func brandBadge(for bank: BankInfo) -> String {
        bank.name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    private func handlePopularTap(_ p: PopularBank) {
        switch p.kind {
        case .direct(let blz):
            if let bank = banks.first(where: { $0.blz == blz }) { pick(bank) } else { searchText = p.label }
        case .filter(let text):
            searchText = text
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE")
        return f.string(from: date)
    }

    /// Keychain-backed state for the connected page. Call after any Keychain write.
    private func refreshCachedKeychainState() {
        let blz = KeychainService.get(KeychainService.fintsBLZ)
        cachedHasPIN = KeychainService.hasSavedPIN
        cachedSavedBank = blz.flatMap { b in banks.first(where: { $0.blz == b }) ?? selectedBank }
    }

    // MARK: - Error Banner

    private enum ErrorKind {
        case network, auth, tan, bank, validation, internalError

        var icon: String {
            switch self {
            case .network: return "wifi.exclamationmark"
            case .auth: return "person.crop.circle.badge.exclamationmark"
            case .tan: return "key.slash"
            case .bank: return "building.columns"
            case .validation: return "exclamationmark.bubble"
            case .internalError: return "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .network, .tan, .validation: return .orange
            case .auth, .bank, .internalError: return .red
            }
        }

        var defaultTitle: String {
            switch self {
            case .network: return "Verbindungsproblem"
            case .auth: return "Anmeldung fehlgeschlagen"
            case .tan: return "TAN-Verfahren fehlgeschlagen"
            case .bank: return "Bank-Fehler"
            case .validation: return "Eingabe prüfen"
            case .internalError: return "Etwas ist schiefgelaufen"
            }
        }
    }

    private struct ClassifiedError {
        let kind: ErrorKind
        let title: String
        let detail: String
        let retryLabel: String?
    }

    private func classify(_ raw: String) -> ClassifiedError {
        let lower = raw.lowercased()
        // Order matters — most specific first.
        if lower.contains("http request failed")
            || lower.contains("connection refused")
            || lower.contains("network connection was lost")
            || lower.contains("timed out")
            || lower.contains("internet connection")
        {
            return ClassifiedError(
                kind: .network,
                title: ErrorKind.network.defaultTitle,
                detail: "Die Bank ist gerade nicht erreichbar. Bitte prüfe deine Internetverbindung und versuche es erneut.",
                retryLabel: "Erneut versuchen"
            )
        }
        if lower.contains("unknown blz") {
            return ClassifiedError(
                kind: .validation,
                title: "Bank nicht unterstützt",
                detail: "Diese Bankleitzahl ist nicht in unserer FinTS-Liste. Bitte eine andere Bank wählen.",
                retryLabel: "Andere Bank wählen"
            )
        }
        if lower.contains("tan") && (lower.contains("falsch") || lower.contains("fehlgeschlagen") || lower.contains("invalid")) {
            return ClassifiedError(
                kind: .tan,
                title: ErrorKind.tan.defaultTitle,
                detail: raw,
                retryLabel: "Neu versuchen"
            )
        }
        if lower.contains("anmeldung fehlgeschlagen")
            || lower.contains("pin")
            || lower.contains("9050") // ING-style permission denied
            || lower.contains("9400")
        {
            return ClassifiedError(
                kind: .auth,
                title: ErrorKind.auth.defaultTitle,
                detail: "Kennung oder PIN passt nicht. Bitte sorgfältig eingeben — mehrere Fehlversuche können dein Online-Banking sperren.",
                retryLabel: "Daten prüfen"
            )
        }
        if lower.contains("9110") || lower.contains("9120") || lower.contains("9800") || lower.contains("hbci") {
            return ClassifiedError(
                kind: .bank,
                title: "Bank lehnt Anfrage ab",
                detail: raw,
                retryLabel: nil
            )
        }
        if lower.contains("failed to build") || lower.contains("decode") || lower.contains("parse") {
            return ClassifiedError(
                kind: .internalError,
                title: ErrorKind.internalError.defaultTitle,
                detail: raw,
                retryLabel: "Erneut versuchen"
            )
        }
        return ClassifiedError(
            kind: .internalError,
            title: ErrorKind.internalError.defaultTitle,
            detail: raw,
            retryLabel: nil
        )
    }

    private func errorBanner(_ err: ClassifiedError) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(err.kind.color.opacity(0.18))
                    Image(systemName: err.kind.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(err.kind.color)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(err.title)
                        .font(WimgFont.font(.manrope, .heavy, 15, relativeTo: .subheadline))
                        .foregroundStyle(err.kind.color)
                    Text(err.detail)
                        .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                        .foregroundStyle(WimgTheme.text.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button {
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .padding(6)
                        .background(WimgTheme.bg.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let retry = err.retryLabel {
                Button {
                    handleRetry(for: err.kind)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: err.kind == .auth || err.kind == .validation
                              ? "arrow.uturn.backward" : "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text(retry)
                            .font(WimgFont.font(.manrope, .heavy, 12, relativeTo: .caption))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(err.kind.color)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(err.kind.color.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(err.kind.color.opacity(0.25), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func handleRetry(for kind: ErrorKind) {
        errorMessage = nil
        switch kind {
        case .network, .internalError:
            // Retry whatever the user was last attempting based on current stage
            switch stage {
            case .credentials: Task { await handleConnect() }
            case .tanChallenge: Task { await handleSendTan() }
            case .dateRange, .fetching: Task { await handleFetch() }
            case .tanMediumSelect: Task { await handleFetchTanMedia() }
            default: break
            }
        case .auth, .validation:
            // Send user back to fix their input
            stage = .credentials
        case .tan:
            // Stay on TAN stage, just clear input so they re-type
            tanInput = ""
        case .bank:
            // No automatic recovery — let user choose
            stage = .bankSelect
        }
    }

    // MARK: - Actions

    private func handleQuickRefresh() async {
        guard let bank = selectedBank else { return }
        guard let savedPIN = KeychainService.get(KeychainService.fintsPIN) else { return }
        refreshing = true
        errorMessage = nil

        do {
            let result: FintsStatusResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try LibWimg.fintsConnect(blz: bank.blz, user: kennung, pin: savedPIN)
                        continuation.resume(returning: r)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            await MainActor.run {
                if result.isOk {
                    // Restore saved TAN medium if bank requires it
                    if result.tan_medium_required == true {
                        if let savedMedium = KeychainService.get(KeychainService.fintsTanMedium) {
                            Task {
                                let _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<FintsStatusResult, Error>) in
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        do {
                                            let r = try LibWimg.fintsSetTanMedium(name: savedMedium)
                                            continuation.resume(returning: r)
                                        } catch {
                                            continuation.resume(throwing: error)
                                        }
                                    }
                                }
                                await handleQuickFetch()
                            }
                        } else {
                            // No saved TAN medium — fall through to manual selection
                            refreshing = false
                            stage = .tanMediumSelect
                            Task { await handleFetchTanMedia() }
                        }
                    } else {
                        Task { await handleQuickFetch() }
                    }
                } else if result.needsTan {
                    // TAN required during connect — show TAN screen
                    refreshing = false
                    isDecoupledChallenge = result.decoupled ?? false
                    challengeText = result.challenge ?? "TAN erforderlich"
                    if let b64 = result.phototan, let data = Data(base64Encoded: b64) {
                        photoTanData = data
                        showInvertedPhotoTan = false
                    } else {
                        photoTanData = nil
                    }
                    tanInput = ""
                    stage = .tanChallenge
                    if isDecoupledChallenge {
                        Task { await handleSendTan() }
                    }
                } else {
                    // Auth failed — clear stored PIN, fall back to manual
                    refreshing = false
                    KeychainService.clearFintsPIN(); BankConnections.storeActiveSlots(name: selectedBank?.name ?? "")
                    pin = ""
                    rememberPIN = false
                    refreshCachedKeychainState()
                    BackgroundRefresh.cancel()
                    errorMessage = result.message ?? "Anmeldung fehlgeschlagen. Bitte erneut manuell anmelden."
                }
            }
        } catch {
            await MainActor.run {
                refreshing = false
                KeychainService.clearFintsPIN(); BankConnections.storeActiveSlots(name: selectedBank?.name ?? "")
                pin = ""
                rememberPIN = false
                refreshCachedKeychainState()
                BackgroundRefresh.cancel()
                errorMessage = friendlyError(error)
            }
        }
    }

    private func handleQuickFetch() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fromStr = formatter.string(from: Calendar.current.date(byAdding: .day, value: -90, to: Date())!)
        let toStr = formatter.string(from: Date())

        do {
            let result: FintsFetchResult = try await LibWimg.onLargeStack { try LibWimg.fintsFetch(from: fromStr, to: toStr) }
            await MainActor.run {
                refreshing = false
                if result.needsTan {
                    // TAN required for fetch — show TAN screen
                    isDecoupledChallenge = result.decoupled ?? false
                    challengeText = result.challenge ?? "TAN erforderlich"
                    if let b64 = result.phototan, let data = Data(base64Encoded: b64) {
                        photoTanData = data
                        showInvertedPhotoTan = false
                    } else {
                        photoTanData = nil
                    }
                    tanInput = ""
                    stage = .tanChallenge
                    if isDecoupledChallenge {
                        Task { await handleSendTan() }
                    }
                } else if result.isError {
                    errorMessage = result.message ?? "Abruf fehlgeschlagen"
                } else {
                    importedCount = result.imported ?? 0
                    duplicateCount = result.duplicates ?? 0
                    BankConnections.recordFetch(nil, new: result.imported ?? 0)
                    categorizing = false
                    categorizedCount = nil
                    stage = .result
                    if importedCount > 0 {
                        NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                    }
                    if cachedHasPIN {
                        Task {
                            await BackgroundRefresh.requestNotificationAuthIfNeeded()
                            BackgroundRefresh.schedule()
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                refreshing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleConnect() async {
        guard let bank = selectedBank else { return }
        connecting = true
        errorMessage = nil

        do {
            // Run blocking FinTS/HTTP work on a dedicated queue to avoid
            // deadlocking the Swift cooperative thread pool (semaphore.wait
            // inside the HTTP callback blocks the current thread).
            let result: FintsStatusResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try LibWimg.fintsConnect(blz: bank.blz, user: kennung, pin: pin)
                        continuation.resume(returning: r)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            await MainActor.run {
                connecting = false
                if result.isOk {
                    // Save credentials for next time
                    KeychainService.set(KeychainService.fintsBLZ, value: bank.blz)
                    KeychainService.set(KeychainService.fintsKennung, value: kennung)
                    if rememberPIN {
                        KeychainService.set(KeychainService.fintsPIN, value: pin)
                    } else {
                        KeychainService.clearFintsPIN(); BankConnections.storeActiveSlots(name: selectedBank?.name ?? "")
                    }
                    // Kept in the list of logins (several banks).
                    BankConnections.storeActiveSlots(name: bank.name)
                    refreshCachedKeychainState()
                    if result.tan_medium_required == true {
                        // Bank requires TAN medium selection — fetch media list
                        stage = .tanMediumSelect
                        Task { await handleFetchTanMedia() }
                    } else {
                        // Manual sign-in: show dateRange so the user picks how
                        // far back to fetch UP FRONT (previously this jumped
                        // straight to a 90-day fetch and forced the user to
                        // re-fetch via "Anderen Zeitraum wählen" if they
                        // wanted more history). Schnellabfrage stays silent —
                        // it has its own flow that fetches immediately.
                        stage = .dateRange
                    }
                } else if result.needsTan {
                    isDecoupledChallenge = result.decoupled ?? false
                    challengeText = result.challenge ?? "TAN erforderlich"
                    if let b64 = result.phototan, let data = Data(base64Encoded: b64) {
                        photoTanData = data
                        showInvertedPhotoTan = false
                    } else {
                        photoTanData = nil
                        showInvertedPhotoTan = false
                    }
                    tanInput = ""
                    stage = .tanChallenge
                    if isDecoupledChallenge {
                        Task { await handleSendTan() }
                    }
                } else {
                    errorMessage = result.message ?? "Verbindung fehlgeschlagen"
                }
            }
        } catch {
            await MainActor.run {
                connecting = false
                errorMessage = friendlyError(error)
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription
        print("[FinTS] Error: \(msg)")
        if msg.contains("HTTP request failed") || msg.contains("auth HTTP request failed") {
            return "Verbindung zur Bank fehlgeschlagen. Bitte prüfe deine Internetverbindung und versuche es erneut.\n\n(\(msg))"
        }
        if msg.contains("failed to build") {
            return "FinTS-Nachricht konnte nicht erstellt werden.\n\n(\(msg))"
        }
        if msg.contains("unknown BLZ") {
            return "Diese Bankleitzahl wird nicht unterstützt."
        }
        if msg.contains("auth") || msg.contains("Auth") {
            return "Anmeldung fehlgeschlagen. Bitte überprüfe Kennung und PIN."
        }
        return msg
    }

    private func handleSendTan() async {
        // One TAN message at a time: a second one in flight (double tap, retry)
        // reuses the message number and Comdirect aborts the whole dialog (9120, 9800).
        guard !sendingTan else { return }
        sendingTan = true
        errorMessage = nil

        do {
            let result: FintsStatusResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let outgoingTan = isDecoupledChallenge ? "" : tanInput
                        let r = try LibWimg.fintsSendTan(tan: outgoingTan)
                        continuation.resume(returning: r)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            await MainActor.run {
                sendingTan = false
                if result.isOk {
                    // TAN accepted — dialog is active, fetch statements now
                    stage = .fetching
                    Task { await handleFetch() }
                } else if result.needsTan {
                    isDecoupledChallenge = result.decoupled ?? isDecoupledChallenge
                    challengeText = result.challenge ?? "TAN erforderlich"
                    if let b64 = result.phototan, let data = Data(base64Encoded: b64) {
                        photoTanData = data
                        showInvertedPhotoTan = false
                    } else {
                        photoTanData = nil
                        showInvertedPhotoTan = false
                    }
                    tanInput = ""
                    stage = .tanChallenge
                } else {
                    errorMessage = result.message ?? "TAN fehlgeschlagen"
                }
            }
        } catch {
            await MainActor.run {
                sendingTan = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleFetchTanMedia() async {
        loadingTanMedia = true
        errorMessage = nil

        do {
            let result: FintsTanMediaResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try LibWimg.fintsGetTanMedia()
                        continuation.resume(returning: r)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            await MainActor.run {
                loadingTanMedia = false
                if result.isOk {
                    let media = result.media ?? []
                    tanMedia = media
                    if media.isEmpty {
                        // Bank returned no selectable media — continue.
                        stage = .dateRange
                    }
                } else {
                    // Keep user on medium-selection stage and surface backend error.
                    tanMedia = []
                    errorMessage = result.message ?? "TAN-Medien konnten nicht geladen werden"
                }
            }
        } catch {
            await MainActor.run {
                loadingTanMedia = false
                tanMedia = []
                // Keep user on medium-selection stage and surface transport/decode error.
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleSelectTanMedium(_ name: String) async {
        errorMessage = nil

        do {
            let result: FintsStatusResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try LibWimg.fintsSetTanMedium(name: name)
                        continuation.resume(returning: r)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            await MainActor.run {
                if result.isOk {
                    KeychainService.set(KeychainService.fintsTanMedium, value: name)
                    BankConnections.storeActiveSlots(name: selectedBank?.name ?? "")
                    // Skip dateRange — fetch last 90d immediately
                    stage = .fetching
                    Task { await handleFetch() }
                } else {
                    errorMessage = result.message ?? "TAN-Medium konnte nicht gesetzt werden"
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleFetch() async {
        errorMessage = nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fromStr = formatter.string(from: dateFrom)
        let toStr = formatter.string(from: dateTo)

        do {
            let result: FintsFetchResult = try await LibWimg.onLargeStack { try LibWimg.fintsFetch(from: fromStr, to: toStr) }
            await MainActor.run {
                if result.needsTan {
                    isDecoupledChallenge = result.decoupled ?? false
                    challengeText = result.challenge ?? "TAN erforderlich"
                    if let b64 = result.phototan, let data = Data(base64Encoded: b64) {
                        photoTanData = data
                        showInvertedPhotoTan = false
                    } else {
                        photoTanData = nil
                        showInvertedPhotoTan = false
                    }
                    tanInput = ""
                    stage = .tanChallenge
                    if isDecoupledChallenge {
                        Task { await handleSendTan() }
                    }
                } else if result.isError {
                    errorMessage = result.message ?? "Abruf fehlgeschlagen"
                    stage = .bankSelect
                } else {
                    importedCount = result.imported ?? 0
                    duplicateCount = result.duplicates ?? 0
                    BankConnections.recordFetch(nil, new: result.imported ?? 0)
                    categorizing = false
                    categorizedCount = nil
                    stage = .result
                    if importedCount > 0 {
                        NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                    }
                    // Schnellabfrage worked → opt user into weekly background
                    // refresh. Ask for notification permission in this gesture
                    // context (much higher accept rate than at app launch).
                    if cachedHasPIN {
                        Task {
                            await BackgroundRefresh.requestNotificationAuthIfNeeded()
                            BackgroundRefresh.schedule()
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                stage = .bankSelect
            }
        }
    }

    // Lower bound for the DatePicker. 10 years is well beyond any bank's
    // history retention — keeps the picker usable without letting the user
    // accidentally roll back to 1970.
    private var tenYearsAgo: Date {
        Calendar.current.date(byAdding: .year, value: -10, to: Date()) ?? Date()
    }

    // Quick-pick chips on the dateRange screen. `value` is a positive number
    // of units to subtract from today. "Alle" subtracts 5 years and lets the
    // bank truncate — closest FinTS gives us to "fetch everything".
    private struct DatePreset {
        let label: String
        let value: Int
        let component: Calendar.Component
    }
    private var datePresets: [DatePreset] {
        [
            .init(label: #L("3 Monate"), value: 3, component: .month),
            .init(label: #L("6 Monate"), value: 6, component: .month),
            .init(label: #L("1 Jahr"), value: 1, component: .year),
            .init(label: #L("2 Jahre"), value: 2, component: .year),
            .init(label: #L("Alle"), value: 5, component: .year),
        ]
    }

    private func resetToBank() {
        stage = .bankSelect
        selectedBank = nil
        kennung = ""
        pin = ""
        rememberPIN = false
        tanInput = ""
        challengeText = ""
        isDecoupledChallenge = false
        showInvertedPhotoTan = false
        errorMessage = nil
        importedCount = 0
        duplicateCount = 0
        categorizing = false
        categorizedCount = nil
        refreshing = false
        tanMedia = []
        loadingTanMedia = false
        latestImportDate = nil
        dateFrom = Calendar.current.date(byAdding: .month, value: -12, to: Date())!
        dateTo = Date()
        refreshCachedKeychainState()
    }

    /// Scan existing transactions for the active bank and pick the most recent
    /// posting date. Used to default the "Von" picker to right after the last
    /// known transaction instead of always going back 90 days.
    private func loadLatestImportDate(forBank bankName: String?) async {
        // Off-main: scanning 200+ rows + JSON decode is too heavy for the
        // SwiftUI render path (decisions.md: "iOS reload() via Task.detached").
        let latest = await Task.detached(priority: .userInitiated) { () -> Date? in
            let txns = (try? LibWimg.getTransactions()) ?? []
            let pool: [Transaction] = if let name = bankName?.lowercased(), !name.isEmpty {
                txns.filter { ($0.account ?? "").lowercased().contains(name) }
            } else {
                txns
            }
            return pool.compactMap { $0.parsedDate }.max()
        }.value
        await MainActor.run { latestImportDate = latest }
    }

    /// Pick a sane "Von" date based on what's already imported:
    ///   - first import (no rows for this bank) → 12 months back (matches
    ///     what most German banks still return; user can extend manually)
    ///   - incremental fetch → latest known date minus 7 days for overlap
    ///     (catches late-posting transactions without flooding the request)
    private func applySmartDateDefaults() {
        let cal = Calendar.current
        if let latest = latestImportDate {
            dateFrom = cal.date(byAdding: .day, value: -7, to: latest) ?? latest
        } else {
            dateFrom = cal.date(byAdding: .month, value: -12, to: Date()) ?? Date()
        }
        dateTo = Date()
    }

    /// Re-establish FinTS dialog and refetch with the user-chosen range.
    /// The previous dialog ended with HKEND after the successful first fetch,
    /// so a bare fintsFetch returns "Authentication failed". This path silently
    /// reconnects with the saved PIN, then fetches. Without a saved PIN we drop
    /// the user back into the credentials form so they can re-enter manually.
    private func handleReFetch() async {
        guard let bank = selectedBank else {
            await MainActor.run {
                errorMessage = "Bank nicht ausgewählt"
                stage = .bankSelect
            }
            return
        }
        let savedKennung = KeychainService.get(KeychainService.fintsKennung) ?? kennung
        guard let savedPIN = KeychainService.get(KeychainService.fintsPIN), !savedPIN.isEmpty else {
            await MainActor.run {
                kennung = savedKennung
                errorMessage = #L("PIN nicht gespeichert. Bitte erneut anmelden.")
                stage = .credentials
            }
            return
        }

        await MainActor.run {
            connecting = true
            errorMessage = nil
        }

        do {
            let connectResult: FintsStatusResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try LibWimg.fintsConnect(blz: bank.blz, user: savedKennung, pin: savedPIN)
                        continuation.resume(returning: r)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            await MainActor.run {
                connecting = false
                if connectResult.isOk {
                    stage = .fetching
                    Task { await handleFetch() }
                } else if connectResult.needsTan {
                    isDecoupledChallenge = connectResult.decoupled ?? false
                    challengeText = connectResult.challenge ?? #L("TAN erforderlich")
                    if let b64 = connectResult.phototan, let data = Data(base64Encoded: b64) {
                        photoTanData = data
                        showInvertedPhotoTan = false
                    }
                    tanInput = ""
                    stage = .tanChallenge
                    if isDecoupledChallenge {
                        Task { await handleSendTan() }
                    }
                } else {
                    errorMessage = connectResult.message ?? #L("Anmeldung fehlgeschlagen")
                    stage = .credentials
                }
            }
        } catch {
            await MainActor.run {
                connecting = false
                errorMessage = error.localizedDescription
                stage = .credentials
            }
        }
    }
}
