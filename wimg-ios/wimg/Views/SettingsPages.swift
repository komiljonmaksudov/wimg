import SwiftUI
import WimgI18n

// Settings pages iOS gained in the catch-up, as on Android:
// Konten (board 20), Gelernte Regeln (board 22), Geräte / wimg Sync (board 21).

// MARK: - Konten

struct AccountsView: View {
    @State private var accounts: [Account]?
    @State private var renaming: Account?
    @State private var newName = ""

    var body: some View {
        BandScreen(title: L("Konten"), pushed: true) {
            Text(L("Welche Konten in Übersicht und Summen zählen, und wie sie heißen."))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub)
        } sheet: {
            if let list = accounts {
                if list.isEmpty {
                    QuietLine(text: L("Noch keine Konten. Sie entstehen beim ersten Abruf oder Import."))
                } else {
                    GroupLabel(text: L("Ein- und ausblenden"))
                    WimgGroup {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                            if i > 0 { RowDivider() }
                            Toggle(isOn: Binding(get: { !a.isHidden }, set: { setShown(a, $0) })) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.name).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                                    Text(a.isHidden ? L("Ausgeblendet") : L("In Übersicht und Summen"))
                                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                                }
                            }
                            .toggleStyle(.wimg)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                        }
                    }
                    QuietLine(text: L("Ausgeblendete Konten zählen nicht in „Verfügbar“ und den Kategorien. Ihre Umsätze bleiben in der Suche."))
                    GroupLabel(text: L("Name in wimg"))
                    WimgGroup {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                            if i > 0 { RowDivider() }
                            WimgRow(title: a.name, desc: a.name != a.id ? L("Von der Bank: %s", a.id) : nil, chevron: true,
                                    action: { newName = a.name; renaming = a })
                        }
                    }
                }
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in Task { await load() } }
        .alert(L("Name in wimg"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Name"), text: $newName)
            Button(L("Abbrechen"), role: .cancel) { renaming = nil }
            Button(L("Speichern")) { rename() }
        } message: {
            if let a = renaming { Text(L("Von der Bank: %s", a.id)) }
        }
    }

    private func load() async {
        accounts = await Task.detached { LibWimg.getAccounts() }.value
    }

    private func setShown(_ a: Account, _ shown: Bool) {
        try? LibWimg.setAccountHidden(id: a.id, hidden: !shown)
        Changes.bump()
    }

    /// "Name in wimg": the bank's id stays, only the shown name changes.
    private func rename() {
        guard let a = renaming else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        try? LibWimg.updateAccount(id: a.id, name: name.isEmpty ? a.id : String(name.prefix(40)), color: a.color)
        renaming = nil
        Changes.bump()
        Dock.shared.info(L("Name geändert"))
    }
}

// MARK: - Gelernte Regeln

struct RulesView: View {
    private struct Row: Identifiable {
        let rule: Rule
        let count: Int
        var id: Int64 { rule.id }
    }

    @State private var rows: [Row]?
    @State private var query = ""
    @State private var open: Row?

    var body: some View {
        BandScreen(title: L("Gelernte Regeln"), pushed: true) {
            Text(L("Stichwörter, nach denen wimg Umsätze einer Kategorie zuordnet."))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub)
        } sheet: {
            SearchField(text: $query, prompt: L("Stichwort oder Kategorie"))
            if let rows {
                let q = query.trimmingCharacters(in: .whitespaces)
                let shown = rows.filter {
                    q.isEmpty || $0.rule.pattern.localizedCaseInsensitiveContains(q)
                        || L(WimgCategory.from($0.rule.category).name).localizedCaseInsensitiveContains(q)
                }
                // Learned (priority 1) first, newest first; then the ones wimg ships with.
                let learned = shown.filter(\.rule.isLearned).sorted { $0.rule.id > $1.rule.id }
                let shipped = shown.filter { !$0.rule.isLearned }.sorted { $0.count > $1.count }
                if !learned.isEmpty {
                    GroupLabel(text: L("%d gelernt · zuletzt gelernt zuerst", learned.count))
                    group(learned)
                }
                if !shipped.isEmpty {
                    GroupLabel(text: L("%d mitgeliefert", shipped.count))
                    group(shipped)
                }
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in Task { await load() } }
        .confirmationDialog(open.map { "„\($0.rule.pattern)“" } ?? "", isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } }),
                            titleVisibility: .visible) {
            if let r = open {
                Button(L("Regel löschen"), role: .destructive) { delete(r, reset: false) }
                if r.count > 0 {
                    Button(L("Löschen und %d Umsätze zurücksetzen", r.count), role: .destructive) { delete(r, reset: true) }
                }
                Button(L("Abbrechen"), role: .cancel) { open = nil }
            }
        } message: {
            if let r = open {
                Text(L("Ordnet Umsätze mit diesem Wort %s zu.", L(WimgCategory.from(r.rule.category).name)))
            }
        }
    }

    private func group(_ list: [Row]) -> some View {
        WimgGroup {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                if i > 0 { RowDivider() }
                WimgRow(title: r.rule.pattern,
                        desc: L(WimgCategory.from(r.rule.category).name) + " · " + (r.count == 1 ? L("1 Umsatz") : L("%d Umsätze", r.count)),
                        chevron: true, action: { open = r }) {
                    CategoryTile(category: r.rule.category)
                }
            }
        }
    }

    /// Rules with how many bookings each one sorted (same category, text found).
    private func load() async {
        rows = await Task.detached {
            let txs = (try? LibWimg.getTransactions()) ?? []
            return LibWimg.getRules().map { r in
                Row(rule: r, count: txs.filter { $0.category == r.category && $0.description.localizedCaseInsensitiveContains(r.pattern) }.count)
            }
        }.value
    }

    private func delete(_ r: Row, reset: Bool) {
        open = nil
        try? LibWimg.deleteRule(id: r.rule.id, reset: reset)
        Changes.bump()
        Dock.shared.info(L("Regel gelöscht"), sub: reset ? L("%d Umsätze wieder ohne Kategorie", r.count) : nil)
    }
}

// MARK: - Geräte (wimg Sync)

struct SyncDevicesView: View {
    @State private var on = false
    @State private var devices: [SyncDevice] = []
    @State private var syncing = false
    @State private var lastAt = SyncService.lastSyncAt
    @State private var removing: SyncDevice?
    @State private var confirmNewKey = false

    private let me = SyncService.deviceId

    var body: some View {
        BandScreen(title: L("wimg Sync"), pushed: true) {
            HStack(spacing: 8) {
                Circle().fill(on && lastAt > 0 ? Wimg.bandPos : Wimg.warn).frame(width: 8, height: 8)
                Text(status).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub)
            }
        } sheet: {
            if !on {
                if SyncService.wasRemoved {
                    QuietLine(text: L("Dieses Gerät ist nicht mehr verknüpft: es wurde entfernt oder der Schlüssel ersetzt. Deine Daten sind noch hier."),
                              systemImage: "link", color: Wimg.warn)
                }
                QuietLine(text: L("Deine Umsätze gleichen sich zwischen deinen Geräten ab, Ende-zu-Ende-verschlüsselt. Es gibt kein Konto: ein Schlüssel verbindet deine Geräte."),
                          systemImage: "key")
                WimgGroup {
                    WimgRow(title: L("Sync einrichten"), desc: L("Einstellungen › Synchronisierung"), chevron: true,
                            action: { AppNav.shared.open(.settings) })
                }
            } else {
                GroupLabel(text: L("Geräte"))
                WimgGroup {
                    ForEach(Array(deviceList.enumerated()), id: \.element.id) { i, d in
                        if i > 0 { RowDivider() }
                        let isMe = d.id == me
                        WimgRow(title: isMe ? L("%s (dieses Gerät)", d.name ?? "") : (d.name ?? ""),
                                desc: deviceLine(d, isMe: isMe), chevron: !isMe,
                                action: { if isMe { syncNow() } else { removing = d } }) {
                            IconTile(systemImage: d.kind == "tablet" ? "ipad" : d.kind == "laptop" ? "laptopcomputer" : "iphone",
                                     tint: Wimg.text)
                        }
                    }
                }
                GroupLabel(text: L("Schlüssel"))
                WimgGroup {
                    WimgRow(title: L("Neuen Schlüssel erstellen"),
                            desc: L("Wenn ein Gerät verloren ging oder jemand den Schlüssel kennt"), chevron: true,
                            action: { confirmNewKey = true }) {
                        IconTile(systemImage: "arrow.clockwise", tint: Wimg.text)
                    }
                }
                QuietLine(text: L("Ein Gerät entfernst du, indem du es antippst. Wer den Schlüssel noch kennt, kommt aber wieder rein: dafür gibt es den neuen Schlüssel."))
                QuietLine(text: L("Der Server speichert nur verschlüsselte Daten. Ohne den Schlüssel kann niemand sie lesen, auch wimg nicht."),
                          systemImage: "lock")
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in Task { await load() } }
        .confirmationDialog(L("%s entfernen?", removing?.name ?? ""), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button(L("Entfernen"), role: .destructive) { remove() }
            Button(L("Abbrechen"), role: .cancel) { removing = nil }
        } message: {
            Text(L("Das Gerät synchronisiert danach nicht mehr, seine Daten bleiben darauf. Wer den Schlüssel kennt, kann es wieder verknüpfen: dagegen hilft ein neuer Schlüssel."))
        }
        .confirmationDialog(L("Neuen Schlüssel erstellen?"), isPresented: $confirmNewKey, titleVisibility: .visible) {
            Button(L("Neuen Schlüssel erstellen"), role: .destructive) { newKey() }
            Button(L("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L("Der alte Schlüssel funktioniert danach nicht mehr. Wer ihn kennt, kommt nicht mehr an deine Daten."))
        }
    }

    /// This device first, even before its row has synced.
    private var deviceList: [SyncDevice] {
        let mine = devices.first { $0.id == me } ?? SyncDevice(id: me, name: SyncService.deviceName, kind: SyncService.deviceKind, last_seen: Int64(lastAt))
        return [mine] + devices.filter { $0.id != me }
    }

    private var status: String {
        if !on { return L("Aus") }
        if syncing { return L("Synchronisiere…") }
        return lastAt > 0 ? L("Synchron · %s", Self.ago(Int64(lastAt))) : L("Noch nicht synchronisiert")
    }

    private func deviceLine(_ d: SyncDevice, isMe: Bool) -> String {
        if isMe {
            if syncing { return L("Synchronisiere…") }
            return lastAt > 0 ? L("Synchron · %s", Self.ago(Int64(lastAt))) : L("Tippen zum Synchronisieren")
        }
        let seen = d.last_seen ?? 0
        let recent = Int64(Date().timeIntervalSince1970 * 1000) - seen < 7 * 24 * 3600 * 1000
        return recent ? L("Synchron · %s", Self.ago(seen)) : L("Zuletzt %s", Self.ago(seen))
    }

    static func ago(_ ms: Int64) -> String {
        let min = Int((Int64(Date().timeIntervalSince1970 * 1000) - ms) / 60_000)
        if min < 1 { return L("gerade eben") }
        if min < 60 { return L("vor %d Min.", min) }
        if min < 60 * 24 { return L("vor %d Std.", min / 60) }
        return L("vor %d Tagen", min / (60 * 24))
    }

    private func load() async {
        on = await SyncService.shared.isEnabled
        devices = await Task.detached { LibWimg.getDevices() }.value
        lastAt = SyncService.lastSyncAt
    }

    private func syncNow() {
        guard !syncing else { return }
        syncing = true
        Task {
            do {
                let r = try await SyncService.shared.syncFull()
                Dock.shared.info(L("Synchron"), sub: r.pulled > 0 ? L("%d Änderungen übernommen", r.pulled) : nil)
            } catch {
                Dock.shared.error(L("Nicht synchron"), sub: L("Keine Verbindung zum Sync-Server. Später erneut versuchen."))
            }
            syncing = false
            Changes.bump()
        }
    }

    private func remove() {
        guard let d = removing else { return }
        removing = nil
        try? LibWimg.removeDevice(id: d.id)
        Changes.bump()
        Dock.shared.info(L("Gerät entfernt"), sub: L("%s synchronisiert nicht mehr.", d.name ?? ""))
        syncNow()
    }

    private func newKey() {
        let id = Dock.shared.progress(L("Neuer Schlüssel wird erstellt"))
        Task {
            let ok = await SyncService.shared.replaceKey()
            Dock.shared.dismiss(id)
            if ok {
                Dock.shared.info(L("Neuer Schlüssel aktiv"), sub: L("Verknüpfe deine anderen Geräte neu."))
            } else {
                Dock.shared.error(L("Schlüssel nicht ersetzt"), sub: L("Keine Verbindung zum Sync-Server. Der alte Schlüssel gilt weiter."))
            }
            Changes.bump()
        }
    }
}
