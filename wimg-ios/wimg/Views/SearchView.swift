import SwiftUI
import WimgI18n

// Suche (brief 21, option A + 21b, as Android's SearchScreen.kt): the answer
// in the band (sum, count, average, months), page words that open a page,
// "In Umsätzen" to take the search to Umsätze as a filter. The field is the
// system search field: on iOS 26 it sits at the bottom of the search tab.

/// A page or action you can type to ("abrufen", "gehalt", "faq").
private struct SearchAction: Identifiable {
    let id: String
    let label: String
    let sub: String?
    let icon: String
    /// Extra keywords, German and English, without umlauts.
    let words: String
    let run: () -> Void

    private static func norm(_ t: String) -> String {
        t.lowercased().replacingOccurrences(of: "ä", with: "a").replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ü", with: "u").replacingOccurrences(of: "ß", with: "ss")
    }

    /// Brief 21b: the word starts the page name (or one of its words) or a keyword.
    func matches(_ q: String) -> Bool {
        let n = Self.norm(q.trimmingCharacters(in: .whitespaces))
        guard n.count >= 2 else { return false }
        let l = Self.norm(label)
        if l.hasPrefix(n) { return true }
        let parts = l.split(whereSeparator: { " -·".contains($0) }).map(String.init) + words.split(separator: " ").map(String.init)
        return parts.contains { $0.hasPrefix(n) }
    }
}

/// A page word names a page and finds fewer than this many bookings: the page wins.
private let pageWordMaxHits = 3
private let recentKey = "wimg_search_recent"

struct SearchView: View {
    @Binding var selectedAccount: String?
    var popToRoot: UUID

    @State private var all: [Transaction] = []
    @State private var accounts: [String: Account] = [:]
    @State private var recurringCount: Int?
    @State private var query = ""
    @State private var hits: [Transaction] = []
    @State private var searchedFor = ""
    @State private var biggest = false
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    @State private var path = NavigationPath()

    private var q: String { query.trimmingCharacters(in: .whitespaces) }
    private var active: Bool { !q.isEmpty || biggest }
    private var current: Bool { searchedFor == (biggest ? "\u{1}biggest" : q) }

    private var actions: [SearchAction] {
        let nav = AppNav.shared
        return [
            SearchAction(id: "manual", label: L("Umsatz von Hand"), sub: L("Bargeld oder was die Bank nicht kennt"), icon: "plus",
                         words: "hinzufugen neu manuell bar bargeld add manual cash umsatz von hand") { nav.open(.transactions) },
            SearchAction(id: "home", label: L("Übersicht"), sub: nil, icon: "house",
                         words: "home start dashboard verfugbar ubersicht") { nav.open(.overview) },
            SearchAction(id: "tx", label: L("Umsätze"), sub: nil, icon: "list.bullet",
                         words: "liste transaktionen transactions buchungen umsatze") { nav.open(.transactions) },
            SearchAction(id: "rec", label: L("Wiederkehrend"), sub: L("Abos und feste Kosten"), icon: "arrow.triangle.2.circlepath",
                         words: "abo abos fixkosten vertrage recurring subscriptions miete wiederkehrend") { nav.open(.recurring) },
            SearchAction(id: "review", label: L("Rückblick"), sub: L("Monat oder Gehaltsmonat im Rückblick"), icon: "chart.bar.xaxis",
                         words: "ruckblick monat review sparquote") { nav.open(.review) },
            SearchAction(id: "bank", label: L("Bankverbindung"), sub: L("Umsätze von der Bank abrufen"), icon: "building.columns",
                         words: "bank banken fints comdirect sparkasse konto verbinden pin tan abrufen aktualisieren fetch refresh") { nav.open(.banks) },
            SearchAction(id: "import", label: L("Import"), sub: L("Kontoauszug oder CSV-Datei"), icon: "square.and.arrow.down",
                         words: "csv datei import hochladen kontoauszug mt940 camt revolut") { nav.open(.import_) },
            SearchAction(id: "settings", label: L("Einstellungen"), sub: L("Sync, App-Sperre, Export, Kategorien"), icon: "gearshape",
                         words: "settings optionen einstellungen sperre lock dunkel hell theme sprache language export gehalt") { nav.open(.settings) },
            SearchAction(id: "accounts", label: L("Konten"), sub: L("Einstellungen › Konten"), icon: "wallet.bifold",
                         words: "konten accounts ausblenden umbenennen") { nav.open(.accounts) },
            SearchAction(id: "rules", label: L("Gelernte Regeln"), sub: L("Kategorien, die wimg sich gemerkt hat"), icon: "list.bullet.rectangle",
                         words: "regeln kategorie rules lernen gelernte") { nav.open(.rules) },
            SearchAction(id: "sync", label: L("wimg Sync"), sub: L("Einstellungen › Geräte"), icon: "arrow.triangle.2.circlepath.circle",
                         words: "sync gerate schlussel verknupfen devices key wimg") { nav.open(.devices) },
            SearchAction(id: "about", label: L("Über wimg"), sub: nil, icon: "info.circle",
                         words: "uber about version wimg faq fragen hilfe datenschutz privacy") { nav.open(.about) },
        ]
    }

    private var matchingActions: [SearchAction] { q.isEmpty || biggest ? [] : actions.filter { $0.matches(q) } }
    private var pageMode: Bool { current && !matchingActions.isEmpty && hits.count < pageWordMaxHits }

    var body: some View {
        NavigationStack(path: $path) {
            BandScreen(title: L("Suche"), pushed: true) {
                EmptyView()
            } band: {
                band
            } sheet: {
                sheet
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Händler, Betrag, Seite"))
            .onSubmit(of: .search) {
                if pageMode, let a = matchingActions.first { open(a) } else { keepRecent() }
            }
            .onChange(of: query) { biggest = false }
            .navigationDestination(for: TxRoute.self) { TransactionDetailView(id: $0.id) }
        }
        .onChange(of: popToRoot) { path = NavigationPath(); query = ""; biggest = false }
        .task(id: selectedAccount) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in Task { await load() } }
        .task(id: "\(q)|\(biggest)|\(all.count)") { await search() }
    }

    // MARK: Band

    @ViewBuilder private var band: some View {
        if !active {
            Text(L("Was willst du wissen?")).wimgStyle(WimgType.title).foregroundStyle(.white)
            Text(L("Händler, Betrag oder eine Seite. Alles bleibt auf dem Handy."))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).padding(.top, 6)
        } else if pageMode, let page = matchingActions.first {
            BandOver(text: L("Suche: %s", q))
            HStack(spacing: 12) {
                Text(L("Seite")).wimgStyle(WimgType.chip).foregroundStyle(Wimg.bandSub)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Wimg.bandSub.opacity(0.5), lineWidth: 1))
                Text(page.label).wimgStyle(WimgType.title).foregroundStyle(.white).lineLimit(1)
            }
            .padding(.top, 6)
            Text(L("Enter öffnet die Seite.")).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).padding(.top, 6)
        } else {
            HStack {
                BandOver(text: biggest ? L("Größte Ausgaben diesen Monat") : L("Suche: %s", q)).lineLimit(1)
                Spacer(minLength: 8)
                // The same search as a filter on Umsätze.
                if !biggest && !hits.isEmpty {
                    Button(L("In Umsätzen →")) {
                        keepRecent()
                        TxTarget.shared.query = q
                        AppNav.shared.open(.transactions)
                    }
                    .wimgStyle(WimgType.chip)
                    .foregroundStyle(Wimg.accentLight)
                }
            }
            let sum = hits.reduce(0) { $0 + $1.amount }
            Amount(euros: sum, style: WimgType.amountHero, centsStyle: WimgType.amountHeroCents,
                   color: sum > 0 ? Wimg.bandPos : .white, rolls: true)
                .padding(.top, 2)
            Text(summaryLine(sum)).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).lineLimit(2).padding(.top, 4)
        }
    }

    private func summaryLine(_ sum: Double) -> String {
        guard !hits.isEmpty else { return L("Keine Treffer") }
        return [hits.count == 1 ? L("1 Umsatz") : L("%d Umsätze", hits.count),
                "⌀ " + amountText(abs(sum) / Double(hits.count), showPlus: false),
                Self.dateRange(hits)].joined(separator: " · ")
    }

    // MARK: Sheet

    @ViewBuilder private var sheet: some View {
        if !active {
            start
        } else if !current {
            EmptyView()
        } else if pageMode {
            SectionTitle(text: L("Seiten"))
            actionGroup(Array(matchingActions.prefix(3)))
            if !hits.isEmpty {
                SectionTitle(text: L("Auch in Umsätzen · %d", hits.count))
                hitGroup(hits)
            }
        } else if hits.isEmpty {
            noHits
        } else {
            if !matchingActions.isEmpty {
                SectionTitle(text: L("Seiten und Aktionen"))
                actionGroup(Array(matchingActions.prefix(3)))
            }
            SectionTitle(text: L("Umsätze"))
            ForEach(Self.byMonth(hits), id: \.ym) { month in
                GroupLabel(text: Self.monthLabel(month.ym), trailing: amountText(month.txs.reduce(0) { $0 + $1.amount }))
                hitGroup(month.txs)
            }
        }
    }

    @ViewBuilder private var start: some View {
        if !recent.isEmpty {
            SectionTitle(text: L("Zuletzt gesucht"), trailing: L("Löschen")) {
                recent = []
                UserDefaults.standard.removeObject(forKey: recentKey)
            }
            WimgGroup {
                ForEach(Array(recent.enumerated()), id: \.element) { i, r in
                    if i > 0 { RowDivider() }
                    let found = all.filter { Self.textMatches($0, r) || Self.amountMatches($0, r) }
                    WimgRow(title: r, desc: found.count == 1 ? L("1 Umsatz") : L("%d Umsätze", found.count),
                            action: { query = r }) {
                        IconTile(systemImage: "clock.arrow.circlepath", tint: Wimg.text2)
                    } trailing: {
                        if !found.isEmpty {
                            Text(amountText(found.reduce(0) { $0 + $1.amount })).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                        }
                    }
                }
            }
        }
        SectionTitle(text: L("Springen zu"))
        let lastMonth = Calendar(identifier: .gregorian).component(.month, from: Calendar(identifier: .gregorian).date(byAdding: .month, value: -1, to: Date())!)
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                tile(L("Wiederkehrend"), recurringCount.map { $0 == 1 ? L("1 läuft") : L("%d laufen", $0) } ?? "",
                     "arrow.triangle.2.circlepath", Wimg.category(13)) { AppNav.shared.open(.recurring) }
                tile(L("Rückblick"), L("%s ist fertig", WimgDates.months()[lastMonth - 1]),
                     "chart.bar.xaxis", Wimg.category(2)) { AppNav.shared.open(.review) }
            }
            GridRow {
                tile(L("Banken"), L("Bankverbindung"), "building.columns", Wimg.accent) { AppNav.shared.open(.banks) }
                tile(L("Einstellungen"), L("Sync, Sperre, Export"), "gearshape", Wimg.text2) { AppNav.shared.open(.settings) }
            }
        }
        SectionTitle(text: L("Fragen"))
        WimgGroup {
            let month = String(WimgDates.todayIso().prefix(7))
            let top = all.filter { $0.date.hasPrefix(month) && $0.amount < 0 && !$0.isExcluded }
                .sorted { $0.amount < $1.amount }.prefix(3).map { $0.displayTitle.split(separator: " ").first.map(String.init) ?? "" }
            WimgRow(title: L("Größte Ausgaben diesen Monat"), desc: top.isEmpty ? nil : top.joined(separator: ", "),
                    chevron: true, action: { biggest = true }) {
                IconTile(systemImage: "arrow.up", tint: Wimg.category(2))
            }
            RowDivider()
            WimgRow(title: L("Abos und feste Kosten"),
                    desc: recurringCount.map { $0 == 1 ? L("1 läuft") : L("%d laufen", $0) },
                    chevron: true, action: { AppNav.shared.open(.recurring) }) {
                IconTile(systemImage: "arrow.triangle.2.circlepath", tint: Wimg.category(13))
            }
        }
        QuietLine(text: L("Die Suche läuft nur auf deinem Handy. Nichts wird gesendet.")).padding(.top, 8)
    }

    private func tile(_ title: String, _ sub: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Icon above the text: the text gets the tile's whole width (side by
            // side, "Bankverbindung" broke inside the word).
            VStack(alignment: .leading, spacing: 8) {
                IconTile(systemImage: icon, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(1).minimumScaleFactor(0.85)
                    if !sub.isEmpty {
                        Text(sub).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))
        }
        .buttonStyle(.wimgPress)
    }

    private func actionGroup(_ list: [SearchAction]) -> some View {
        WimgGroup {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                if i > 0 { RowDivider() }
                WimgRow(title: a.label, desc: a.sub, chevron: true, action: { open(a) }) {
                    IconTile(systemImage: a.icon, tint: i == 0 && pageMode ? Wimg.accent : Wimg.text2)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous)
            .stroke(pageMode ? Wimg.accent : .clear, lineWidth: 2))
    }

    private func hitGroup(_ txs: [Transaction]) -> some View {
        WimgGroup {
            ForEach(Array(txs.enumerated()), id: \.element.id) { i, tx in
                if i > 0 { RowDivider() }
                let account = accounts.count > 1 ? accounts[tx.account ?? ""].map { $0.bank.isEmpty ? $0.name : $0.bank } : nil
                WimgRow(title: Self.snippet(tx, q),
                        desc: [WimgDates.short(tx.date), account, L(WimgCategory.from(tx.category).name)].compactMap { $0 }.joined(separator: " · "),
                        action: { keepRecent(); path.append(TxRoute(id: tx.id)) }) {
                    EmptyView()
                } trailing: {
                    Amount(euros: tx.amount, color: tx.amount > 0 ? Wimg.pos : Wimg.text)
                }
            }
        }
    }

    /// Say why, and offer the shorter search that does find something.
    @ViewBuilder private var noHits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Nichts für „%s“.", q)).wimgStyle(WimgType.section).foregroundStyle(Wimg.text)
            if let oldest = all.map(\.date).min() {
                Text(L("Deine Umsätze reichen bis %s zurück.", Self.monthLabel(String(oldest.prefix(7)), withYear: true)))
                    .wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        if let shorter = shorterSearch {
            WimgGroup {
                WimgRow(title: L("Nach „%s“ suchen", shorter.text),
                        desc: shorter.count == 1 ? L("1 Umsatz") : L("%d Umsätze", shorter.count),
                        action: { query = shorter.text }) {
                    IconTile(systemImage: "magnifyingglass", tint: Wimg.accent)
                }
            }
            .padding(.top, 12)
        } else {
            QuietLine(text: L("Banken kürzen Namen oft ab: versuch einen Teil des Namens."))
        }
    }

    private var shorterSearch: (text: String, count: Int)? {
        var words = q.split(separator: " ").map(String.init)
        while words.count > 1 {
            words.removeLast()
            let t = words.joined(separator: " ")
            let n = all.filter { Self.textMatches($0, t) }.count
            if n > 0 { return (t, n) }
        }
        return nil
    }

    // MARK: Data

    private func open(_ a: SearchAction) {
        keepRecent()
        a.run()
    }

    private func keepRecent() {
        guard !q.isEmpty else { return }
        recent = Array(([q] + recent.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(5))
        UserDefaults.standard.set(recent, forKey: recentKey)
    }

    private func load() async {
        let account = selectedAccount
        let (txs, accs, rec) = await Task.detached {
            // Search keeps hidden accounts ("Ihre Umsätze bleiben in der Suche").
            let t = ((account == nil ? try? LibWimg.getTransactions() : try? LibWimg.getTransactionsFiltered(account: account)) ?? [])
                .sorted { $0.date > $1.date }
            let a = Dictionary(LibWimg.getAccounts().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return (t, a, LibWimg.getRecurring().filter { !$0.isHidden && $0.isActive }.count)
        }.value
        all = txs; accounts = accs; recurringCount = rec
    }

    /// Off the main thread: thousands of rows per keystroke.
    private func search() async {
        let q = q, biggest = biggest, all = all
        let key = biggest ? "\u{1}biggest" : q
        let result: [Transaction] = await Task.detached {
            if biggest {
                let month = String(WimgDates.todayIso().prefix(7))
                return Array(all.filter { $0.date.hasPrefix(month) && $0.amount < 0 && !$0.isExcluded }
                    .sorted { $0.amount < $1.amount }.prefix(20))
            }
            guard !q.isEmpty else { return [] }
            return all.filter { Self.textMatches($0, q) || Self.amountMatches($0, q) }
        }.value
        guard !Task.isCancelled else { return }
        hits = result
        searchedFor = key
    }

    // MARK: Matching and labels (as Android)

    nonisolated private static func textMatches(_ tx: Transaction, _ q: String) -> Bool {
        tx.description.localizedCaseInsensitiveContains(q) || tx.displayTitle.localizedCaseInsensitiveContains(q)
    }

    /// "12,99", "12.99", "1.234,56" all find 1234,56 / 12,99.
    nonisolated private static func amountMatches(_ tx: Transaction, _ q: String) -> Bool {
        guard q.contains(where: \.isNumber), q.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }) else { return false }
        let typed = q.contains(",") ? q.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : q
        let cents = Int64((abs(tx.amount) * 100).rounded())
        let plain = String(format: "%lld.%02lld", cents / 100, cents % 100)
        return plain.contains(typed)
    }

    /// The row title, or the part of the bank text around a deeper match.
    private static func snippet(_ tx: Transaction, _ q: String) -> String {
        let title = tx.displayTitle
        guard !q.isEmpty, !title.localizedCaseInsensitiveContains(q),
              let r = tx.description.range(of: q, options: .caseInsensitive) else { return title }
        let start = tx.description.index(r.lowerBound, offsetBy: -14, limitedBy: tx.description.startIndex) ?? tx.description.startIndex
        let rest = tx.description[start...].trimmingCharacters(in: .whitespaces)
        return (start > tx.description.startIndex ? "… " : "") + rest
    }

    private static func byMonth(_ txs: [Transaction]) -> [(ym: String, txs: [Transaction])] {
        var out: [(ym: String, txs: [Transaction])] = []
        for tx in txs {
            let ym = String(tx.date.prefix(7))
            if out.last?.ym == ym { out[out.count - 1].txs.append(tx) } else { out.append((ym, [tx])) }
        }
        return out
    }

    /// "November", or "November 2025" for another year.
    private static func monthLabel(_ ym: String, withYear: Bool = false) -> String {
        let p = ym.split(separator: "-")
        guard p.count == 2, let m = Int(p[1]) else { return ym }
        let name = WimgDates.months()[m - 1]
        return withYear || !WimgDates.todayIso().hasPrefix(String(p[0])) ? "\(name) \(p[0])" : name
    }

    /// "Feb. – Nov. 2026", or "Nov. 2025 – Feb. 2026" across years.
    private static func dateRange(_ txs: [Transaction]) -> String {
        guard let first = txs.map(\.date).min(), let last = txs.map(\.date).max() else { return "" }
        let m = WimgDates.shortMonths()
        let a = first.split(separator: "-"), b = last.split(separator: "-")
        let y1 = String(a[0]), y2 = String(b[0]), m1 = Int(a[1])!, m2 = Int(b[1])!
        if y1 == y2 && m1 == m2 { return "\(m[m2 - 1]). \(y2)" }
        if y1 == y2 { return "\(m[m1 - 1]). – \(m[m2 - 1]). \(y2)" }
        return "\(m[m1 - 1]). \(y1) – \(m[m2 - 1]). \(y2)"
    }
}
