import SwiftUI
import WidgetKit
import WimgI18n

/// Einstellungen (as Android's SettingsScreen.kt, board 20): groups of rows,
/// sub-pages pushed in the same stack.
struct SettingsView: View {
    @State private var syncEnabled = false
    @State private var syncKey = ""
    @State private var syncing = false
    @State private var showSyncKey = false
    @State private var showQRSheet = false
    @State private var showLinkSheet = false
    @State private var periods: Periods?

    @State private var showExport = false
    @State private var confirmReset = false

    @AppStorage(BackgroundRefresh.enabledKey) private var bgRefreshEnabled = true
    @State private var hasSavedFintsCreds: Bool = KeychainService.hasFintsCredentials

    @ObservedObject private var biometricLock = BiometricLock.shared
    @AppStorage("wimg_lock_enabled") private var lockEnabled = false
    /// Mirrored in the App Group so the widget process sees the same value.
    @State private var widgetMaskAmounts: Bool =
        UserDefaults(suiteName: "group.com.wimg.app")?.bool(forKey: "wimg_widget_mask_amounts") ?? false

    private var themeManager = ThemeManager.shared

    /// Matches the web mask: first 4 + middle hyphenated dots + last 4.
    private var maskedSyncKey: String {
        guard syncKey.count > 8 else { return syncKey }
        return syncKey.prefix(4) + "••••-••••-••••-" + syncKey.suffix(4)
    }

    var body: some View {
        BandScreen(title: L("Einstellungen"), pushed: true) {
            Text(L("Darstellung, Sync, Bank, Sicherheit und Daten."))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub)
        } sheet: {
            appearance
            period
            sync
            bank
            accounts
            security
            categories
            data
            about
        }
        .navigationDestination(for: SettingsSubpage.self) { page in
            switch page {
            case .period: SettingsPeriodView()
            case .language: SettingsLanguageView()
            }
        }
        .sheet(isPresented: $showQRSheet) { SyncQRSheet(syncKey: syncKey) }
        .sheet(isPresented: $showLinkSheet) {
            SyncLinkSheet(onLinked: { Task { await loadSync() } })
        }
        .confirmationDialog(L("Daten exportieren"), isPresented: $showExport) {
            Button(L("Transaktionen (CSV)")) { exportData(format: "csv") }
            Button(L("Backup (JSON)")) { exportData(format: "json") }
            Button(L("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L("Wähle ein Export-Format"))
        }
        .confirmationDialog(L("Alle Daten löschen?"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Ja, alles löschen"), role: .destructive) { handleResetData() }
            Button(L("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L("Alle lokalen Daten werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden."))
        }
        .task {
            await loadSync()
            hasSavedFintsCreds = KeychainService.hasFintsCredentials
            periods = await Task.detached { LibWimg.getPeriods(count: 12) }.value
        }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
            Task { periods = await Task.detached { LibWimg.getPeriods(count: 12) }.value }
        }
    }

    // MARK: Groups

    @ViewBuilder private var appearance: some View {
        GroupLabel(text: L("Darstellung"))
        WimgGroup {
            HStack(spacing: 12) {
                Text(L("Design")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                Spacer(minLength: 8)
                Picker(L("Design"), selection: Binding(get: { themeManager.mode }, set: { themeManager.mode = $0 })) {
                    Text(L("Hell")).tag(ThemeMode.light)
                    Text(L("Dunkel")).tag(ThemeMode.dark)
                    Text(L("System")).tag(ThemeMode.system)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: WimgDimens.rowMinHeight)
            RowDivider()
            link(.language, title: L("Sprache"), value: SettingsLanguageView.label)
        }
    }

    @ViewBuilder private var period: some View {
        GroupLabel(text: L("Zeitraum"))
        WimgGroup {
            NavigationLink(value: SettingsSubpage.period) {
                WimgRow(title: L("Monat beginnt"), desc: periodDesc, chevron: true) {
                    EmptyView()
                } trailing: {
                    valueText(periodValue)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var periodValue: String {
        switch periods?.chosen {
        case "salary": L("mit dem Gehalt")
        case "day": L("am %d.", periods?.day ?? 1)
        default: L("am 1.")
        }
    }

    private var periodDesc: String? {
        guard let p = periods, p.chosen == "salary" else { return nil }
        return p.isSalary ? L("Automatisch erkannt · Kalendermonat, wenn kein Gehalt kommt")
            : L("Gehalt noch nicht erkannt · bis dahin Kalendermonat")
    }

    @ViewBuilder private var sync: some View {
        GroupLabel(text: L("Synchronisierung"))
        WimgGroup {
            if syncEnabled {
                NavigationLink(value: MorePage.devices) {
                    WimgRow(title: L("wimg Sync"), desc: L("Ende-zu-Ende-verschlüsselt zwischen deinen Geräten, ohne Konto"), chevron: true) {
                        EmptyView()
                    } trailing: {
                        statusValue(on: true)
                    }
                }
                .buttonStyle(.plain)
                RowDivider()
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Sync-Schlüssel")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                        Text(showSyncKey ? syncKey : maskedSyncKey)
                            .wimgStyle(WimgType.mono).foregroundStyle(Wimg.text2)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 4)
                    iconButton(showSyncKey ? "eye.slash" : "eye",
                               showSyncKey ? L("Sync-Schlüssel verbergen") : L("Sync-Schlüssel anzeigen")) { showSyncKey.toggle() }
                    iconButton("doc.on.doc", L("Sync-Schlüssel kopieren")) {
                        UIPasteboard.general.string = syncKey
                        Dock.shared.info(L("Schlüssel kopiert"))
                    }
                    iconButton("qrcode", L("QR-Code anzeigen")) { showQRSheet = true }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
                RowDivider()
                WimgRow(title: syncing ? L("Synchronisiere…") : L("Jetzt synchronisieren"), action: syncing ? nil : { Task { await handleSyncNow() } }) {
                    IconTile(systemImage: "arrow.triangle.2.circlepath", tint: Wimg.accent)
                }
            } else {
                WimgRow(title: L("Sync aktivieren"), desc: L("Erstellt einen Schlüssel und lädt deine Daten verschlüsselt hoch"),
                        action: syncing ? nil : { Task { await handleEnableSync() } }) {
                    IconTile(systemImage: "sparkles", tint: Wimg.accent)
                } trailing: {
                    statusValue(on: false)
                }
                RowDivider()
                WimgRow(title: L("Ich nutze wimg schon"), desc: L("Sync-Schlüssel eines anderen Geräts eingeben"), chevron: true,
                        action: { showLinkSheet = true }) {
                    IconTile(systemImage: "link", tint: Wimg.text2)
                }
            }
        }
        if !syncEnabled && SyncService.wasRemoved {
            QuietLine(text: L("Dieses Gerät ist nicht mehr verknüpft: es wurde entfernt oder der Schlüssel ersetzt. Deine Daten sind noch hier."),
                      systemImage: "link", color: Wimg.warn)
        }
    }

    @ViewBuilder private var bank: some View {
        GroupLabel(text: L("Bankverbindung"))
        WimgGroup {
            NavigationLink(value: MorePage.banks) {
                WimgRow(title: L("Bankverbindungen"), chevron: true)
            }
            .buttonStyle(.plain)
            RowDivider()
            Toggle(isOn: Binding(get: { bgRefreshEnabled && hasSavedFintsCreds }, set: { v in
                guard hasSavedFintsCreds else { return }
                bgRefreshEnabled = v
                if v { BackgroundRefresh.schedule() } else { BackgroundRefresh.cancel() }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Schnellabfrage im Hintergrund")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                    Text(hasSavedFintsCreds
                         ? L("iOS weckt wimg meist einmal am Tag, letzte 14 Tage · nur ohne TAN")
                         : L("Erst verfügbar, wenn die PIN für die Schnellabfrage gespeichert ist."))
                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
            }
            .toggleStyle(.wimg)
            .disabled(!hasSavedFintsCreds)
            .opacity(hasSavedFintsCreds ? 1 : 0.6)
            .padding(.horizontal, 16)
            .frame(minHeight: 72)
        }
    }

    @ViewBuilder private var accounts: some View {
        GroupLabel(text: L("Konten"))
        WimgGroup {
            NavigationLink(value: MorePage.accounts) {
                WimgRow(title: L("Konten"), desc: L("Ein- und ausblenden, umbenennen"), chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var security: some View {
        GroupLabel(text: L("Sicherheit"))
        WimgGroup {
            Toggle(isOn: Binding(get: { lockEnabled }, set: { v in
                lockEnabled = v
                biometricLock.setEnabled(v)
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("App-Sperre")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                    Text(lockSubtitle).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
            }
            .toggleStyle(.wimg)
            .disabled(biometricLock.availableMethod == .none)
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            RowDivider()
            Toggle(isOn: Binding(get: { widgetMaskAmounts }, set: { v in
                widgetMaskAmounts = v
                UserDefaults(suiteName: "group.com.wimg.app")?.set(v, forKey: "wimg_widget_mask_amounts")
                WidgetCenter.shared.reloadAllTimelines()
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Beträge in Widgets ausblenden")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                    Text(L("Zeigt ••• € statt echter Beträge. Sperrbildschirm-Widget wird zusätzlich von iOS verdeckt, wenn das Gerät gesperrt ist."))
                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
            }
            .toggleStyle(.wimg)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder private var categories: some View {
        GroupLabel(text: L("Kategorien"))
        WimgGroup {
            WimgRow(title: L("Automatisch zuordnen"), desc: L("Wendet deine Regeln auf Umsätze ohne Kategorie an"),
                    action: autoCategorize)
            RowDivider()
            NavigationLink(value: MorePage.rules) {
                WimgRow(title: L("Gelernte Regeln"), desc: L("Ansehen und löschen"), chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var data: some View {
        GroupLabel(text: L("Daten"))
        WimgGroup {
            WimgRow(title: L("Exportieren und sichern"), chevron: true, action: { showExport = true }) {
                EmptyView()
            } trailing: {
                valueText(L("CSV, Backup"))
            }
            RowDivider()
            NavigationLink(value: MorePage.import_) {
                WimgRow(title: L("Importieren"), desc: L("Kontoauszug oder CSV"), chevron: true)
            }
            .buttonStyle(.plain)
            if DemoDataService.isDemoLoaded {
                RowDivider()
                WimgRow(title: L("Demo-Daten löschen"), desc: L("Beispieldaten sind geladen"), action: handleResetData)
            }
        }

        GroupLabel(text: L("Danger Zone"))
        VStack(spacing: 0) {
            WimgRow(title: L("Alle Daten löschen"), desc: L("Fragt vorher nach Bestätigung"), chevron: true,
                    action: { confirmReset = true })
        }
        .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.danger.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
    }

    @ViewBuilder private var about: some View {
        GroupLabel(text: L("Über wimg"))
        WimgGroup {
            NavigationLink(value: MorePage.about) {
                WimgRow(title: L("Version"), chevron: true) {
                    EmptyView()
                } trailing: {
                    valueText(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                }
            }
            .buttonStyle(.plain)
            RowDivider()
            Link(destination: URL(string: WimgConfig.releasesURL)!) {
                WimgRow(title: "GitHub", desc: L("Code und Versionen"), chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Pieces

    private func link(_ page: SettingsSubpage, title: String, value: String) -> some View {
        NavigationLink(value: page) {
            WimgRow(title: title, chevron: true) {
                EmptyView()
            } trailing: {
                valueText(value)
            }
        }
        .buttonStyle(.plain)
    }

    private func valueText(_ s: String) -> some View {
        Text(s).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).lineLimit(1)
    }

    private func statusValue(on: Bool) -> some View {
        HStack(spacing: 7) {
            Circle().fill(on ? Wimg.pos : Wimg.text3).frame(width: 8, height: 8)
            Text(on ? L("Aktiv") : L("Aus")).wimgStyle(WimgType.body).foregroundStyle(on ? Wimg.pos : Wimg.text2)
        }
    }

    private func iconButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Wimg.text2)
                .frame(width: 36, height: 36)
                .background(Wimg.neutralTint, in: RoundedRectangle(cornerRadius: WimgShape.iconTile, style: .continuous))
        }
        .buttonStyle(.wimgPress)
        .accessibilityLabel(label)
    }

    private var lockSubtitle: String {
        switch biometricLock.availableMethod {
        case .faceID: L("Mit Face ID schützen")
        case .touchID: L("Mit Touch ID schützen")
        case .passcode: L("Mit Gerätecode schützen")
        case .none: L("Kein biometrischer Schutz auf diesem Gerät verfügbar.")
        }
    }

    // MARK: Actions

    private func loadSync() async {
        if let key = await SyncService.shared.syncKey {
            syncEnabled = true
            syncKey = key
        } else {
            syncEnabled = false
            syncKey = ""
        }
    }

    private func handleEnableSync() async {
        let key = UUID().uuidString
        SyncService.shared.setSyncKey(key)
        syncKey = key
        syncEnabled = true
        syncing = true
        do {
            _ = try await SyncService.shared.push()
            await SyncService.shared.connectWebSocket()
            Dock.shared.info(L("Sync aktiv"), sub: L("Deine Daten sind verschlüsselt hochgeladen."))
        } catch {
            Dock.shared.error(L("Nicht synchron"), sub: L("Keine Verbindung zum Sync-Server. Später erneut versuchen."))
        }
        syncing = false
    }

    private func handleSyncNow() async {
        guard !syncKey.isEmpty else { return }
        syncing = true
        do {
            let r = try await SyncService.shared.syncFull()
            Dock.shared.info(L("Synchron"), sub: r.pulled > 0 ? L("%d Änderungen übernommen", r.pulled) : nil)
            if r.pulled > 0 { Changes.bump() }
        } catch {
            Dock.shared.error(L("Nicht synchron"), sub: L("Keine Verbindung zum Sync-Server. Später erneut versuchen."))
        }
        await loadSync()
        syncing = false
    }

    private func autoCategorize() {
        let n = LibWimg.autoCategorize()
        Changes.bump()
        if n > 0 {
            Dock.shared.undo(L("%d Umsätze zugeordnet", n)) {
                _ = LibWimg.undo()
                Changes.bump()
            }
        } else {
            Dock.shared.info(L("Nichts Neues zuzuordnen"))
        }
    }

    private func handleResetData() {
        LibWimg.isResetting = true
        // Defer close to the next runloop tick so in-flight SwiftUI body
        // evaluations see isResetting=true and bail out before the DB goes.
        DispatchQueue.main.async {
            LibWimg.close()
            let dbPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("wimg.db").path
            try? FileManager.default.removeItem(atPath: dbPath)

            Task { await SyncService.shared.disconnectWebSocket() }
            SyncService.shared.clearSyncKey()
            KeychainService.deleteAll()
            UserDefaults.standard.removeObject(forKey: "wimg_sync_last_ts")
            DemoDataService.clearDemoFlag()
            UserDefaults.standard.removeObject(forKey: "wimg_onboarding_completed")

            try? LibWimg.initialize()
            LibWimg.isResetting = false
            syncEnabled = false
            syncKey = ""
            confirmReset = false
            Changes.bump()
        }
    }

    private func exportData(format: String) {
        let date = WimgDates.todayIso()
        let content = format == "csv" ? LibWimg.exportCsv() : LibWimg.exportDb()
        let filename = format == "csv" ? "wimg-transaktionen-\(date).csv" : "wimg-backup-\(date).json"
        guard let content, let data = content.data(using: .utf8) else { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        guard let top = UIApplication.shared.topViewController else { return }
        // iPad: anchor the popover or UIKit raises an exception.
        if let pop = activityVC.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(activityVC, animated: true)
    }
}

/// Pages pushed from Einstellungen (the rest are MorePage values).
enum SettingsSubpage: Hashable { case period, language }
