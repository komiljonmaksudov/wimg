import SwiftUI
import WidgetKit
import WimgI18n

/// Einstellungen (as Android's SettingsScreen.kt, board 20): groups of rows,
/// sub-pages pushed in the same stack.
struct SettingsView: View {
    @State private var syncEnabled = false
    @State private var syncKey = ""
    @State private var periods: Periods?

    @State private var showExport = false
    @State private var confirmReset = false

    @AppStorage(BackgroundRefresh.enabledKey) private var bgRefreshEnabled = true
    @State private var hasSavedFintsCreds: Bool = BankConnections.anyWithPIN

    @ObservedObject private var biometricLock = BiometricLock.shared
    @AppStorage("wimg_lock_enabled") private var lockEnabled = false
    private var themeManager = ThemeManager.shared

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
            case .notifications: NotificationSettingsView()
            case .sync: SyncSettingsView()
            case .lock: LockSettingsView()
            }
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
            Text(L("Alle lokalen Daten werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.")
                 + " " + L("wimg Sync") + ": " + L("Wird beendet, die verschlüsselte Kopie auf dem Server gelöscht. Andere Geräte behalten ihre eigene."))
        }
        .task {
            await loadSync()
            hasSavedFintsCreds = BankConnections.anyWithPIN
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
            NavigationLink(value: SettingsSubpage.sync) {
                WimgRow(title: L("wimg Sync"), desc: L("Ende-zu-Ende-verschlüsselt zwischen deinen Geräten, ohne Konto"), chevron: true) {
                    EmptyView()
                } trailing: {
                    statusValue(on: syncEnabled)
                }
            }
            .buttonStyle(.plain)
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
        GroupLabel(text: L("Konten und Mitteilungen"))
        WimgGroup {
            NavigationLink(value: MorePage.accounts) {
                WimgRow(title: L("Konten"), desc: L("Ein- und ausblenden, umbenennen"), chevron: true)
            }
            .buttonStyle(.plain)
            RowDivider()
            NavigationLink(value: SettingsSubpage.notifications) {
                WimgRow(title: L("Mitteilungen"), desc: L("Monatsabschluss, neue Umsätze, Preise, TAN"), chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var security: some View {
        GroupLabel(text: L("Sicherheit"))
        WimgGroup {
            NavigationLink(value: SettingsSubpage.lock) {
                WimgRow(title: L("App-Sperre"), desc: lockSubtitle, chevron: true) {
                    EmptyView()
                } trailing: {
                    valueText(lockEnabled ? L("An") : L("Aus"))
                }
            }
            .buttonStyle(.plain)
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

    /// With sync on, the encrypted copy on the server goes too (as Android). If
    /// the server can't be reached, say so instead of leaving it there silently.
    private func handleResetData() {
        Task {
            if await SyncService.shared.deleteRemote() {
                resetLocal()
            } else {
                Dock.shared.error(L("Server nicht erreichbar"),
                                  sub: L("Die verschlüsselte Kopie auf dem Sync-Server wurde nicht gelöscht. Versuch es mit Internet noch einmal."),
                                  action: L("Nur hier löschen")) { resetLocal() }
            }
        }
    }

    private func resetLocal() {
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
enum SettingsSubpage: Hashable { case period, language, notifications, sync, lock }
