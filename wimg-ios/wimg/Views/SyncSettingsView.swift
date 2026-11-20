import SwiftUI
import WidgetKit
import WimgI18n

/// Einstellungen › wimg Sync (as Android's SettingsSyncScreen): turn it on,
/// link with a key, the key, devices, sync now.
struct SyncSettingsView: View {
    @State private var syncEnabled = false
    @State private var syncKey = ""
    @State private var syncing = false
    @State private var showSyncKey = false
    @State private var showQRSheet = false
    @State private var showLinkSheet = false

    private var maskedSyncKey: String {
        guard syncKey.count > 8 else { return syncKey }
        return syncKey.prefix(4) + "••••-••••-••••-" + syncKey.suffix(4)
    }

    var body: some View {
        BandScreen(title: L("wimg Sync"), pushed: true) {
            Text(L("Ende-zu-Ende-verschlüsselt zwischen deinen Geräten, ohne Konto"))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub)
        } sheet: {
            content
        }
        .sheet(isPresented: $showQRSheet) { SyncQRSheet(syncKey: syncKey) }
        .sheet(isPresented: $showLinkSheet) { SyncLinkSheet(onLinked: { Task { await loadSync() } }) }
        .task { await loadSync() }
    }

    @ViewBuilder private var content: some View {
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
        let key = UUID().uuidString.lowercased() // lowercase: typed on Android too
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

}

/// Einstellungen › App-Sperre (as Android's SettingsLockScreen).
struct LockSettingsView: View {
    @ObservedObject private var biometricLock = BiometricLock.shared
    @AppStorage("wimg_lock_enabled") private var lockEnabled = false
    @State private var widgetMaskAmounts: Bool =
        UserDefaults(suiteName: "group.com.wimg.app")?.bool(forKey: "wimg_widget_mask_amounts") ?? false

    var body: some View {
        BandScreen(title: L("App-Sperre"), pushed: true) {
            Text(L("Einstellungen")).wimgStyle(WimgType.bandOver).foregroundStyle(Wimg.bandSub)
        } sheet: {
            WimgGroup {
                Toggle(isOn: Binding(get: { lockEnabled }, set: { v in
                    lockEnabled = v
                    biometricLock.setEnabled(v)
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("App-Sperre")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                        Text(subtitle).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                    }
                }
                .toggleStyle(.wimg)
                .disabled(biometricLock.availableMethod == .none)
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
            }
            if biometricLock.availableMethod == .none {
                QuietLine(text: L("Auf diesem Gerät ist kein Gerätecode eingerichtet. Richte ihn in den iOS-Einstellungen ein."),
                          systemImage: "exclamationmark.triangle", color: Wimg.warn)
            }
            GroupLabel(text: L("Privatsphäre"))
            WimgGroup {
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
            QuietLine(text: L("Die App-Sperre gilt nur auf diesem Gerät und wird nie synchronisiert."), systemImage: "lock")
        }
    }

    private var subtitle: String {
        switch biometricLock.availableMethod {
        case .faceID: L("Beim Öffnen mit Face ID entsperren")
        case .touchID: L("Beim Öffnen mit Touch ID entsperren")
        case .passcode: L("Beim Öffnen mit dem Gerätecode entsperren")
        case .none: L("Kein biometrischer Schutz auf diesem Gerät verfügbar.")
        }
    }
}
