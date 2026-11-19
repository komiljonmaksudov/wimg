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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Error banner — top of the scroll content for most stages so
                // the user sees it without scrolling. On the credentials stage
                // the form is long enough that a top banner can scroll out of
                // view, so we render the banner inline just above the CTA
                // button instead (see credentialsSection).
                if let error = errorMessage, stage != .credentials {
                    errorBanner(classify(error))
                        .padding(.horizontal, stage == .bankSelect ? 20 : 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                switch stage {
                case .bankSelect:
                    bankSelectSection
                case .credentials:
                    credentialsSection
                case .tanMediumSelect:
                    tanMediumSelectSection
                case .tanChallenge:
                    tanChallengeSection
                case .dateRange:
                    dateRangeSection
                case .fetching:
                    fetchingSection
                case .result:
                    resultSection
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
            .animation(.easeInOut(duration: 0.18), value: errorMessage)
        }
        .background(WimgTheme.bg)
        .navigationTitle(#L("Bankkonto"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let query = searchText
            let allBanks = banks
            let allLower = banksLower
            let filtered = await Task.detached(priority: .userInitiated) {
                if query.isEmpty {
                    return Array(allBanks.prefix(50))
                }
                let q = query.lowercased()
                var result: [BankInfo] = []
                for i in 0..<allBanks.count {
                    if allLower[i].contains(q) || allBanks[i].blz.contains(q) {
                        result.append(allBanks[i])
                        if result.count >= 50 { break }
                    }
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            displayBanks = filtered
        }
        .onAppear {
            // Read keychain once on appear, on a background thread so the
            // initial render doesn't block.
            Task.detached(priority: .userInitiated) {
                let savedBLZ = KeychainService.get(KeychainService.fintsBLZ)
                let savedKennung = KeychainService.get(KeychainService.fintsKennung)
                let savedPIN = KeychainService.get(KeychainService.fintsPIN)
                let hasPIN = savedPIN != nil
                let needsBankLoad = await MainActor.run { banks.isEmpty }
                let loaded: [BankInfo]
                let lower: [String]
                if needsBankLoad {
                    loaded = LibWimg.fintsGetBanks()
                    lower = loaded.map { $0.name.lowercased() }
                } else {
                    loaded = []
                    lower = []
                }
                await MainActor.run {
                    if needsBankLoad {
                        banks = loaded
                        banksLower = lower
                        displayBanks = Array(loaded.prefix(50))
                        loadingBanks = false
                    }
                    if let blz = savedBLZ,
                       let bank = (needsBankLoad ? loaded : banks).first(where: { $0.blz == blz })
                    {
                        selectedBank = bank
                        kennung = savedKennung ?? ""
                        if let pinValue = savedPIN {
                            pin = pinValue
                            rememberPIN = true
                        }
                        cachedSavedBank = bank
                    } else {
                        cachedSavedBank = nil
                    }
                    cachedHasPIN = hasPIN
                }
            }
            if banks.isEmpty {
                loadingBanks = true
            }
        }
    }

    // MARK: - Hub helpers

    private struct PopularBank: Identifiable {
        let id: String  // BLZ or filter key
        let label: String
        let badge: String
        let color: Color
        let kind: Kind
        enum Kind { case direct(blz: String); case filter(text: String) }
    }

    // Static — allocated once, never recomputed on body re-renders.
    private static let popularBanks: [PopularBank] = [
        .init(id: "20041177", label: "Comdirect", badge: "C",
              color: Color(red: 1.0, green: 0.84, blue: 0.0),
              kind: .direct(blz: "20041177")),
        .init(id: "10070000", label: "Deutsche Bank", badge: "DB",
              color: Color(red: 0.0, green: 0.094, blue: 0.659),
              kind: .direct(blz: "10070000")),
        .init(id: "Sparkasse", label: "Sparkasse", badge: "S",
              color: Color(red: 0.91, green: 0.0, blue: 0.0),
              kind: .filter(text: "Sparkasse")),
        .init(id: "50010517", label: "ING-DiBa", badge: "ING",
              color: Color(red: 1.0, green: 0.384, blue: 0.0),
              kind: .direct(blz: "50010517")),
        .init(id: "Volksbank", label: "Volksbank", badge: "VB",
              color: Color(red: 0.0, green: 0.29, blue: 0.6),
              kind: .filter(text: "Volksbank")),
    ]

    private static let sparkasseColor = Color(red: 0.91, green: 0.0, blue: 0.0)
    private static let volksbankColor = Color(red: 0.0, green: 0.29, blue: 0.6)
    private static let postbankColor = Color(red: 1.0, green: 0.8, blue: 0.0)
    private static let deutscheBankColor = Color(red: 0.0, green: 0.094, blue: 0.659)
    private static let ingColor = Color(red: 1.0, green: 0.384, blue: 0.0)
    private static let dkbColor = Color(red: 0.0, green: 0.49, blue: 0.78)

    private func brandColor(for bank: BankInfo) -> Color {
        for p in Self.popularBanks {
            if case .direct(let blz) = p.kind, blz == bank.blz { return p.color }
        }
        let lower = bank.name.lowercased()
        if lower.contains("sparkasse") { return Self.sparkasseColor }
        if lower.contains("volksbank") || lower.contains("raiffeisen") || lower.contains("vr ") {
            return Self.volksbankColor
        }
        if lower.contains("postbank") { return Self.postbankColor }
        if lower.contains("deutsche bank") { return Self.deutscheBankColor }
        if lower.contains("commerzbank") { return Self.postbankColor }
        if lower.contains("ing") { return Self.ingColor }
        if lower.contains("dkb") { return Self.dkbColor }
        return .teal
    }

    private func brandBadge(for bank: BankInfo) -> String {
        let trimmed = bank.name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier:
            UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE")
        return f.string(from: date)
    }

    /// Refresh keychain-backed cached state. Call from onAppear and after
    /// any write/clear to Keychain so the hub stays in sync. Never call this
    /// from inside `body` — keychain access is sync XPC and will stutter.
    private func refreshCachedKeychainState() {
        let blz = KeychainService.get(KeychainService.fintsBLZ)
        let hasPIN = KeychainService.hasSavedPIN
        let bank: BankInfo? = {
            guard let blz else { return nil }
            return banks.first(where: { $0.blz == blz }) ?? selectedBank
        }()
        cachedSavedBank = bank
        cachedHasPIN = hasPIN
    }

    // MARK: - Bank Select (Hub)

    private var bankSelectSection: some View {
        VStack(alignment: .leading, spacing: 32) {
            hubHeader

            if let bank = cachedSavedBank {
                linkedAccountsSection(bank: bank)
            }

            addAccountSection

            secureInfoCard
        }
        .padding(.horizontal, 20)
    }

    private var hubHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(#L("Banken & Konten"))
                .font(WimgFont.font(.manrope, .heavy, 34))
                .tracking(-0.5)
                .foregroundStyle(WimgTheme.text)
            Text(#L("Verwalte deine finanziellen Verbindungen sicher an einem Ort."))
                .font(WimgFont.font(.inter, .medium, 15, relativeTo: .subheadline))
                .foregroundStyle(WimgTheme.textSecondary)
                .frame(maxWidth: 300, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func linkedAccountsSection(bank: BankInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                Text(#L("Verknüpfte Konten"))
                    .font(WimgFont.font(.manrope, .heavy, 20, relativeTo: .title3))
                    .foregroundStyle(WimgTheme.text)
                Spacer()
                Text(#L("1 Aktiv"))
                    .font(WimgFont.font(.manrope, .heavy, 10))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(WimgTheme.textSecondary)
            }

            connectedBankCard(bank: bank)
        }
    }

    private func connectedBankCard(bank: BankInfo) -> some View {
        let badge = brandBadge(for: bank)
        let color = brandColor(for: bank)
        let hasPIN = cachedHasPIN
        let buttonEnabled = hasPIN && !refreshing && !connecting

        return VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(color)
                    Text(badge)
                        .font(WimgFont.font(.manrope, .heavy, 20, relativeTo: .title3))
                        .italic()
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bank.name)
                        .font(WimgFont.font(.manrope, .heavy, 20, relativeTo: .title3))
                        .foregroundStyle(WimgTheme.text)
                        .lineLimit(2)
                    Text("FinTS • BLZ \(bank.blz)")
                        .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                        .foregroundStyle(WimgTheme.textSecondary)
                }

                Spacer(minLength: 8)

                Text(hasPIN ? #L("Aktiv") : #L("PIN fehlt"))
                    .font(WimgFont.font(.manrope, .heavy, 10))
                    .tracking(1)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((hasPIN ? Color.green : Color.orange).opacity(0.15))
                    .foregroundStyle(hasPIN ? .green : .orange)
                    .clipShape(Capsule())
            }

            Button {
                if hasPIN {
                    Task { await handleQuickRefresh() }
                } else {
                    stage = .credentials
                }
            } label: {
                HStack(spacing: 8) {
                    if refreshing {
                        ProgressView()
                            .tint(WimgTheme.bg)
                            .scaleEffect(0.9)
                        Text(#L("Verbinde..."))
                    } else {
                        Image(systemName: hasPIN ? "arrow.clockwise" : "lock.shield")
                            .font(.system(.subheadline, weight: .bold))
                        Text(hasPIN ? #L("Schnellabfrage") : #L("Anmelden"))
                    }
                }
                .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(WimgTheme.text)
                .foregroundStyle(WimgTheme.bg)
                .clipShape(Capsule())
            }
            .disabled(!buttonEnabled && hasPIN)

            if hasPIN {
                Button {
                    KeychainService.clearFintsPIN()
                    pin = ""
                    rememberPIN = false
                    refreshCachedKeychainState()
                    BackgroundRefresh.cancel()
                } label: {
                    Text(#L("Manuell anmelden"))
                        .font(WimgFont.font(.inter, .medium, 12, relativeTo: .caption))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .disabled(refreshing)
            }
        }
        .padding(24)
        .background(
            // Static radial gradient → same visual hint as a blurred accent
            // without the GPU blur cost. Compositor-cheap.
            ZStack {
                WimgTheme.cardBg
                RadialGradient(
                    colors: [WimgTheme.accent.opacity(0.35), WimgTheme.accent.opacity(0)],
                    center: UnitPoint(x: 1.05, y: -0.15),
                    startRadius: 0,
                    endRadius: 180
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusLarge, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 20, y: 4)
    }

    private var addAccountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(#L("Neues Konto hinzufügen"))
                .font(WimgFont.font(.manrope, .heavy, 20, relativeTo: .title3))
                .foregroundStyle(WimgTheme.text)

            // Search bar (rounded full)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WimgTheme.textSecondary)
                TextField(#L("Bank suchen..."), text: $searchText)
                    .font(WimgFont.font(.inter, .medium, 15, relativeTo: .subheadline))
                    .submitLabel(.search)
                    .focused($searchFocused)
                if !searchText.isEmpty || showAllBanks {
                    Button {
                        searchText = ""
                        showAllBanks = false
                        searchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(WimgTheme.cardBg)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.03), radius: 6, y: 1)

            if !searchText.isEmpty || showAllBanks {
                searchResultsList
            } else {
                popularBanksGrid
            }
        }
    }

    private var popularBanksGrid: some View {
        let featured = Self.popularBanks.first
        let others = Array(Self.popularBanks.dropFirst())
        let rows = stride(from: 0, to: others.count, by: 2).map {
            Array(others[$0..<min($0 + 2, others.count)])
        }

        return VStack(spacing: 12) {
            if let f = featured {
                popularBankRow(p: f)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row) { p in
                        popularBankTile(p: p)
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }

            // "Browse all" CTA — toggles full bank list + focuses search
            Button {
                showAllBanks = true
                searchFocused = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(.caption, weight: .bold))
                    Text(#L("Alle Banken durchsuchen"))
                        .font(WimgFont.font(.manrope, .heavy, 12, relativeTo: .caption))
                }
                .foregroundStyle(WimgTheme.text)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(WimgTheme.cardBg)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(WimgTheme.border, lineWidth: 1)
                }
            }
            .padding(.top, 4)
        }
    }

    private func popularBankRow(p: PopularBank) -> some View {
        Button {
            handlePopularTap(p)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(p.color)
                    Text(p.badge)
                        .font(WimgFont.font(.manrope, .heavy, 20, relativeTo: .title3))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(p.label)
                        .font(WimgFont.font(.manrope, .heavy, 15, relativeTo: .subheadline))
                        .foregroundStyle(WimgTheme.text)
                    Text(#L("Häufig gewählt"))
                        .font(WimgFont.font(.inter, .regular, 11, relativeTo: .caption2))
                        .foregroundStyle(WimgTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(.title3))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(WimgTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusMedium, style: .continuous))
            .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func popularBankTile(p: PopularBank) -> some View {
        Button {
            handlePopularTap(p)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(p.color)
                    Text(p.badge)
                        .font(WimgFont.font(.manrope, .heavy, 15, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                Text(p.label)
                    .font(WimgFont.font(.manrope, .heavy, 15, relativeTo: .subheadline))
                    .foregroundStyle(WimgTheme.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(WimgTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusMedium, style: .continuous))
            .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func handlePopularTap(_ p: PopularBank) {
        switch p.kind {
        case .direct(let blz):
            if let bank = banks.first(where: { $0.blz == blz }) {
                selectedBank = bank
                errorMessage = nil
                kennung = ""
                pin = ""
                rememberPIN = false
                stage = .credentials
            } else {
                searchText = p.label
            }
        case .filter(let text):
            searchText = text
        }
    }

    private var searchResultsList: some View {
        LazyVStack(spacing: 0) {
            if loadingBanks {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(#L("Lade Banken..."))
                        .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            ForEach(displayBanks) { bank in
                Button {
                    selectedBank = bank
                    errorMessage = nil
                    kennung = ""
                    pin = ""
                    rememberPIN = false
                    stage = .credentials
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(brandColor(for: bank))
                            Text(brandBadge(for: bank))
                                .font(WimgFont.font(.manrope, .heavy, 12, relativeTo: .caption))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bank.name)
                                .font(WimgFont.font(.manrope, .heavy, 15, relativeTo: .subheadline))
                                .foregroundStyle(WimgTheme.text)
                                .lineLimit(1)
                            Text("BLZ \(bank.blz)")
                                .font(WimgFont.font(.inter, .regular, 11, relativeTo: .caption2))
                                .foregroundStyle(WimgTheme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if bank.id != displayBanks.last?.id {
                    Divider().padding(.leading, 66)
                }
            }

            if displayBanks.isEmpty && !loadingBanks {
                Text(#L("Keine Bank gefunden"))
                    .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(WimgTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusMedium, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
    }

    private var secureInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(#L("Sicher verknüpft"))
                .font(WimgFont.font(.manrope, .heavy, 20, relativeTo: .title3))
                .foregroundStyle(WimgTheme.text)
            Text(#L("FinTS 3.0 — verschlüsselt direkt mit deiner Bank. Login-Daten verlassen dein Gerät nicht."))
                .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                .foregroundStyle(WimgTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
                Text(#L("ENDE-ZU-ENDE VERSCHLÜSSELT"))
                    .font(WimgFont.font(.manrope, .heavy, 10))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(WimgTheme.textSecondary)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [WimgTheme.cardBg, WimgTheme.cardBg.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusLarge, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
    }

    // MARK: - Credentials

    private var credentialsSection: some View {
        VStack(spacing: 16) {
            if let bank = selectedBank {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(brandColor(for: bank))
                        Text(brandBadge(for: bank))
                            .font(WimgFont.font(.manrope, .heavy, 15, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(#L("Anmeldung"))
                            .font(WimgFont.font(.manrope, .heavy, 20, relativeTo: .title3))
                            .foregroundStyle(WimgTheme.text)
                        Text(bank.name)
                            .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 16) {
                // BLZ (read-only)
                VStack(alignment: .leading, spacing: 4) {
                    Text("BLZ")
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    Text(selectedBank?.blz ?? "")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(WimgTheme.text)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Kennung
                VStack(alignment: .leading, spacing: 4) {
                    Text(#L("Kennung"))
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    TextField(#L("Benutzername / Anmeldekennung"), text: $kennung)
                        .font(.subheadline)
                        .textContentType(.oneTimeCode) // suppress iCloud Keychain AutoFill scan (no user has a FinTS credential saved there)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(12)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // PIN
                VStack(alignment: .leading, spacing: 4) {
                    Text("PIN")
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    SecureField("Online-Banking PIN", text: $pin)
                        .font(.subheadline)
                        .textContentType(.oneTimeCode)
                        .padding(12)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Remember PIN toggle
            Toggle(isOn: $rememberPIN) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PIN merken")
                        .font(WimgFont.font(.inter, .medium, 15, relativeTo: .subheadline))
                        .foregroundStyle(WimgTheme.text)
                    Text("Verschlüsselt im Schlüsselbund gespeichert")
                        .font(WimgFont.font(.inter, .regular, 11, relativeTo: .caption2))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
            }
            .tint(.teal)

            // Lockout warning
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(#L("Bitte PIN sorgfältig eingeben"))
                        .font(WimgFont.font(.inter, .bold, 12, relativeTo: .caption))
                        .foregroundStyle(Color.orange.opacity(0.9))
                    Text(#L("Mehrere fehlgeschlagene Anmeldungen können dein Konto bei der Bank sperren. Die PIN wird nicht gespeichert."))
                        .font(WimgFont.font(.inter, .regular, 11, relativeTo: .caption2))
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            }

            // Inline error banner — placed right above the CTA so the user
            // doesn't miss it after the form scrolls past the top of the view.
            if let error = errorMessage {
                errorBanner(classify(error))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Connect button
            Button {
                Task { await handleConnect() }
            } label: {
                Group {
                    if connecting {
                        ProgressView()
                            .tint(WimgTheme.bg)
                    } else {
                        Text(#L("Verbinden"))
                    }
                }
                .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(WimgTheme.text)
                .foregroundStyle(WimgTheme.bg)
                .clipShape(Capsule())
            }
            .disabled(connecting || kennung.isEmpty || pin.isEmpty)

            // Back button
            Button {
                resetToBank()
            } label: {
                Text(#L("Andere Bank wählen"))
                    .font(WimgFont.font(.inter, .medium, 15, relativeTo: .subheadline))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
            .disabled(connecting)
        }
        .padding(24)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - TAN Medium Selection

    private var tanMediumSelectSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 64, height: 64)
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: 28))
                        .foregroundStyle(.purple)
                }

                Text(#L("TAN-Medium wählen"))
                    .font(WimgFont.font(.manrope, .bold, 20, relativeTo: .title3))
                    .foregroundStyle(WimgTheme.text)

                Text(#L("Ihre Bank unterstützt mehrere TAN-Verfahren. Bitte wählen Sie das gewünschte Medium."))
                    .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if loadingTanMedia {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(#L("Lade TAN-Medien..."))
                        .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(tanMedia) { medium in
                        Button {
                            Task { await handleSelectTanMedium(medium.name) }
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color.purple.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: medium.status == 1 ? "checkmark.shield.fill" : "shield")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.purple)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(medium.name)
                                        .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
                                        .foregroundStyle(WimgTheme.text)
                                    Text(medium.status == 1 ? #L("Aktiv") : #L("Inaktiv"))
                                        .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                                        .foregroundStyle(medium.status == 1 ? .green : WimgTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(WimgTheme.textSecondary)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }

                        if medium.id != tanMedia.last?.id {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
                .background(WimgTheme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if tanMedia.isEmpty && !loadingTanMedia {
                // No media found — skip selection, go straight to fetching
                Button {
                    stage = .fetching
                    Task { await handleFetch() }
                } label: {
                    Text(#L("Weiter ohne Auswahl"))
                        .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(WimgTheme.text)
                        .foregroundStyle(WimgTheme.bg)
                        .clipShape(Capsule())
                }
            }

            Button {
                stage = .credentials
            } label: {
                Text(#L("Zurück"))
                    .font(WimgFont.font(.inter, .medium, 15, relativeTo: .subheadline))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
        .padding(24)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - TAN Challenge

    private var tanChallengeSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 64, height: 64)
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                }

                Text(isDecoupledChallenge ? #L("Freigabe in Banking-App") : #L("TAN-Eingabe"))
                    .font(WimgFont.font(.manrope, .bold, 20, relativeTo: .title3))
                    .foregroundStyle(WimgTheme.text)
            }

            // photoTAN image
            if let uiImage = photoTanImage {
                VStack(spacing: 8) {
                    Text("photoTAN")
                        .font(WimgFont.font(.inter, .bold, 12, relativeTo: .caption))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Group {
                        if showInvertedPhotoTan {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .colorInvert()
                        } else {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .frame(maxWidth: 280, maxHeight: 280)
                    .padding(16)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    Button(showInvertedPhotoTan ? "Normale Ansicht" : "Invertierte Ansicht") {
                        showInvertedPhotoTan.toggle()
                    }
                    .font(WimgFont.font(.inter, .medium, 12, relativeTo: .caption))
                    .foregroundStyle(WimgTheme.textSecondary)
                    Text(#L("Scannen Sie dieses Bild mit Ihrer photoTAN-App"))
                        .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)
            }

            // Challenge text
            if !challengeText.isEmpty && photoTanImage == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(#L("Challenge"))
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    Text(challengeText)
                        .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                        .foregroundStyle(WimgTheme.text)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if photoTanImage == nil && challengeText.localizedCaseInsensitiveContains("siehe grafik") {
                Text(#L("Diese TAN-Freigabe erwartet eine scanbare Grafik. Wenn kein Bild angezeigt wird, liefert die Bank ggf. ein nicht direkt darstellbares photoTAN-Format."))
                    .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            if isDecoupledChallenge {
                VStack(spacing: 8) {
                    Text(#L("Bitte in Ihrer Banking-App bestätigen."))
                        .font(WimgFont.font(.inter, .medium, 15, relativeTo: .subheadline))
                        .foregroundStyle(WimgTheme.text)
                        .multilineTextAlignment(.center)
                    Text(#L("wimg prüft den Status automatisch. Falls nötig, können Sie manuell erneut prüfen."))
                        .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(12)
                .background(WimgTheme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                // TAN input
                VStack(alignment: .leading, spacing: 4) {
                    Text("TAN")
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    TextField(#L("TAN eingeben"), text: $tanInput)
                        .font(.system(.subheadline, design: .monospaced))
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Button {
                Task { await handleSendTan() }
            } label: {
                Group {
                    if sendingTan {
                        ProgressView()
                            .tint(WimgTheme.bg)
                    } else {
                        Text(isDecoupledChallenge ? #L("Status prüfen") : #L("TAN senden"))
                    }
                }
                .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(WimgTheme.text)
                .foregroundStyle(WimgTheme.bg)
                .clipShape(Capsule())
            }
            .disabled(sendingTan || (!isDecoupledChallenge && tanInput.isEmpty))
        }
        .padding(24)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 64, height: 64)
                    Image(systemName: "calendar")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                }

                Text(#L("Zeitraum wählen"))
                    .font(WimgFont.font(.manrope, .bold, 20, relativeTo: .title3))
                    .foregroundStyle(WimgTheme.text)

                if let bank = selectedBank {
                    Text(bank.name)
                        .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                        .foregroundStyle(WimgTheme.textSecondary)
                }

                // Smart-default hint: tell the user where the "Von" picker came
                // from so they can trust it without checking the calendar.
                if let latest = latestImportDate {
                    Text("\(#L("Letzter Umsatz")): \(formatShortDate(latest))")
                        .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                        .foregroundStyle(WimgTheme.textSecondary)
                } else {
                    Text(#L("Erstmaliger Abruf – 12 Monate Historie"))
                        .font(WimgFont.font(.inter, .regular, 12, relativeTo: .caption))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
            }

            VStack(spacing: 12) {
                // Clamp `Von` to between (today - 10 years) and the chosen `Bis`.
                DatePicker(#L("Von"), selection: $dateFrom, in: tenYearsAgo...dateTo, displayedComponents: .date)
                    .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                    .environment(\.locale, Locale(identifier: UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE"))

                // `Bis` must never be in the future — banks reject it and the
                // result screen showed "21.05.2026 – future" before this clamp.
                DatePicker(#L("Bis"), selection: $dateTo, in: dateFrom...Date(), displayedComponents: .date)
                    .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                    .environment(\.locale, Locale(identifier: UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE"))
            }
            .padding(12)
            .background(WimgTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Quick presets — bank history limits vary (Comdirect ~25 months,
            // Sparkasse 90 days, DKB 2 years). "Alle" sends a 5-year-back date
            // and lets the bank truncate; that's the closest FinTS gives us to
            // "fetch everything" since the protocol has no "account opening
            // date" call. Tap a chip → updates dateFrom (dateTo stays today).
            HStack(spacing: 8) {
                ForEach(datePresets, id: \.label) { preset in
                    Button {
                        let cal = Calendar.current
                        dateFrom = cal.date(byAdding: preset.component, value: -preset.value, to: Date()) ?? dateFrom
                        dateTo = Date()
                    } label: {
                        Text(preset.label)
                            .font(WimgFont.font(.inter, .semibold, 12, relativeTo: .caption))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .foregroundStyle(WimgTheme.text)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                // Always re-establish the dialog first — the previous one was
                // closed by HKEND on the prior successful fetch.
                Task { await handleReFetch() }
            } label: {
                Label(#L("Kontoauszüge abrufen"), systemImage: "arrow.down.doc")
                    .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(WimgTheme.text)
                    .foregroundStyle(WimgTheme.bg)
                    .clipShape(Capsule())
            }
            .disabled(connecting)
        }
        .padding(24)
        .task {
            // Refresh the smart default each time the user lands on this view —
            // they may have just completed an import that moved the latest date.
            await loadLatestImportDate(forBank: selectedBank?.name)
            applySmartDateDefaults()
        }
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - Fetching

    private var fetchingSection: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(WimgTheme.text)

            Text(#L("Lade Kontoauszüge..."))
                .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                .foregroundStyle(WimgTheme.text)

            if let bank = selectedBank {
                Text(bank.name)
                    .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                }

                Text(#L("Abruf erfolgreich!"))
                    .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                    .foregroundStyle(WimgTheme.text)

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    if let bank = selectedBank {
                        GridRow {
                            Text(#L("Bank"))
                                .foregroundStyle(WimgTheme.textSecondary)
                            Text(bank.name)
                                .fontWeight(.semibold)
                        }
                    }
                    GridRow {
                        Text(#L("Importiert"))
                            .foregroundStyle(WimgTheme.textSecondary)
                        Text("\(importedCount)")
                            .fontWeight(.semibold)
                    }
                    if duplicateCount > 0 {
                        GridRow {
                            Text(#L("Duplikate"))
                                .foregroundStyle(.orange)
                            Text("\(duplicateCount)")
                                .fontWeight(.semibold)
                        }
                    }
                    GridRow {
                        Text(#L("Zeitraum"))
                            .foregroundStyle(WimgTheme.textSecondary)
                        Text("\(formatShortDate(dateFrom)) – \(formatShortDate(dateTo))")
                            .fontWeight(.semibold)
                    }
                }
                .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
            }
            .padding(24)
            .wimgCard(radius: WimgTheme.radiusLarge)
            .padding(.horizontal)

            Button {
                resetToBank()
            } label: {
                Label(#L("Weitere Bank verbinden"), systemImage: "plus.circle")
                    .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(.systemGray5))
                    .foregroundStyle(WimgTheme.text)
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            if importedCount > 0 {
                Button {
                    guard !categorizing, categorizedCount == nil else { return }
                    categorizing = true
                    // Off-main: autoCategorize iterates all uncategorized rows
                    // and runs the rules table — synchronous SQLite work that
                    // would freeze the result screen briefly otherwise.
                    Task.detached(priority: .userInitiated) {
                        let count = LibWimg.autoCategorize()
                        await MainActor.run {
                            categorizing = false
                            categorizedCount = count
                            // Refresh dashboards/transactions even on a zero
                            // match — imported rows still need to surface
                            // somewhere when no rule fires.
                            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if categorizing {
                            ProgressView().tint(WimgTheme.heroText)
                            Text(#L("Kategorisiere..."))
                        } else if let done = categorizedCount {
                            Image(systemName: "checkmark.circle.fill")
                            Text("\(done) \(#L("kategorisiert"))")
                        } else {
                            Image(systemName: "tag")
                            Text("\(#L("Kategorisieren")) (\(importedCount))")
                        }
                    }
                    .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(categorizedCount != nil ? Color.green.opacity(0.85) : WimgTheme.accent)
                    .foregroundStyle(WimgTheme.heroText)
                    .clipShape(Capsule())
                }
                .disabled(categorizing || categorizedCount != nil)
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.18), value: categorizing)
                .animation(.easeInOut(duration: 0.18), value: categorizedCount)
            }

            if let onViewTransactions {
                Button {
                    onViewTransactions()
                } label: {
                    Label(#L("Transaktionen ansehen"), systemImage: "list.bullet")
                        .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(WimgTheme.text)
                        .foregroundStyle(WimgTheme.bg)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
            }

            // Power-user escape hatch: re-fetch with a custom date range
            Button {
                stage = .dateRange
            } label: {
                Label(#L("Anderen Zeitraum wählen"), systemImage: "calendar.badge.clock")
                    .font(WimgFont.font(.inter, .medium, 12, relativeTo: .caption))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
            .padding(.top, 4)
        }
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
                    KeychainService.clearFintsPIN()
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
                KeychainService.clearFintsPIN()
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
                        KeychainService.clearFintsPIN()
                    }
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
