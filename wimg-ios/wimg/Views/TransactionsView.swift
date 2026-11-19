import SwiftUI
import WimgI18n

// Umsätze (brief 22, boards 03 and 10–12): the sum in the band, filters as
// removable chips, bookings grouped by day. Same filters and maths as
// Android's TransactionsScreen.kt.

/// A date range for the filter; `to` inclusive, ISO dates.
struct TxPeriod: Hashable {
    let from: String
    let to: String
    let label: String
    let key: String

    /// One calendar month, labelled "Okt. 2026".
    static func month(_ year: Int, _ month: Int) -> TxPeriod {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let days = cal.range(of: .day, in: .month, for: start)!.count
        let end = cal.date(from: DateComponents(year: year, month: month, day: days))!
        return TxPeriod(from: WimgDates.iso(start), to: WimgDates.iso(end),
                        label: "\(WimgDates.shortMonths()[month - 1]) \(year)", key: "m:\(year)-\(month)")
    }

    /// A Gehaltsmonat or "Fester Tag" period.
    static func of(_ p: PeriodInfo, salary: Bool) -> TxPeriod {
        let running = p.isCurrent && salary
        return TxPeriod(from: p.from, to: p.to,
                        label: running ? L("Seit %s", PeriodLabels.dotted(p.from)) : PeriodLabels.short(p),
                        key: "p:\(p.from)" + (running ? ":salary" : ""))
    }

    static func lastDays(_ days: Int, label: String, key: String) -> TxPeriod {
        let to = Date()
        let from = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: to)!
        return TxPeriod(from: WimgDates.iso(from), to: WimgDates.iso(to), label: label, key: key)
    }

    /// "seit 27.10." for the running Gehaltsmonat, the label otherwise.
    var tag: String { key.hasSuffix(":salary") ? L("seit %s", PeriodLabels.dotted(from)) : label }
    func same(_ o: TxPeriod?) -> Bool { from == o?.from && to == o?.to }
}

/// Betrag filter: the amount without its sign, both ends inclusive; nil = open.
struct AmountRange: Equatable {
    var min: Double? = nil
    var max: Double? = nil
    var isAny: Bool { min == nil && max == nil }
    func contains(_ euros: Double) -> Bool {
        let a = abs(euros)
        return (min.map { a >= $0 - 0.004 } ?? true) && (max.map { a <= $0 + 0.004 } ?? true)
    }

    /// "20", "49,90" (German) or "49.90" (English).
    static func number(_ v: Double) -> String {
        let whole = abs(v - v.rounded()) < 0.004
        let s = whole ? String(Int(v.rounded())) : String(format: "%.2f", v)
        return UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? s : s.replacingOccurrences(of: ".", with: ",")
    }

    /// "über 20 €", "unter 10 €", "20–50 €"; nil when any amount.
    var tag: String? {
        switch (min, max) {
        case let (lo?, hi?): "\(Self.number(lo))–\(Self.number(hi)) €"
        case let (lo?, nil): L("über %s €", Self.number(lo))
        case let (nil, hi?): L("unter %s €", Self.number(hi))
        default: nil
        }
    }
}

enum TxKind: String, CaseIterable, Identifiable {
    case all = "Alle", expenses = "Ausgaben", income = "Einnahmen", manual = "Von Hand"
    var id: String { rawValue }

    func matches(_ tx: Transaction) -> Bool {
        switch self {
        case .all: true
        case .expenses: tx.isExpense
        case .income: tx.isIncome
        case .manual: tx.isManual
        }
    }
}

/// Everything the Umsätze filter holds (the account lives in the app's selection).
struct TxFilterState: Equatable {
    var kind: TxKind = .all
    var categories: Set<Int> = []
    var period: TxPeriod? = nil
    var amount = AmountRange()
    /// Weitere: only bookings of a recurring payment; hidden accounts' bookings too.
    var recurringOnly = false
    var showHidden = false
    /// Bookings containing this text (from Suche: "In Umsätzen").
    var text = ""

    var isActive: Bool {
        kind != .all || !categories.isEmpty || period != nil || !amount.isAny || recurringOnly || showHidden || !text.isEmpty
    }

    /// Every filter except the category one (the category list sums with it).
    func matchesExceptCategory(_ tx: Transaction, recurringIds: Set<String>?) -> Bool {
        guard kind.matches(tx), amount.contains(tx.amount) else { return false }
        if let p = period, !(p.from...p.to).contains(tx.date) { return false }
        if recurringOnly && !(recurringIds?.contains(tx.id) ?? false) { return false }
        if !text.isEmpty && !tx.description.localizedCaseInsensitiveContains(text)
            && !tx.displayTitle.localizedCaseInsensitiveContains(text) { return false }
        return true
    }

    func matches(_ tx: Transaction, recurringIds: Set<String>?) -> Bool {
        (categories.isEmpty || categories.contains(tx.category)) && matchesExceptCategory(tx, recurringIds: recurringIds)
    }
}

/// One removable chip under the band.
private struct FilterTag: Identifiable {
    enum Kind { case text, kind, account, categories, period, amount, recurring, hidden }
    let kind: Kind
    let label: String
    var id: Kind { kind }
}

/// The Umsätze tab can be opened with a filter (a tap on Übersicht or Suche).
@MainActor @Observable
final class TxTarget {
    static let shared = TxTarget()
    var category: Int?
    var period: TxPeriod?
    var query: String?
}

struct TxRoute: Hashable { let id: String }

struct TransactionsView: View {
    @Binding var selectedAccount: String?
    var popToRoot: UUID = UUID()

    @State private var transactions: [Transaction] = []
    @State private var pending: [Transaction] = []
    @State private var accounts: [Account] = []
    @State private var loaded = false

    @State private var filter = TxFilterState()
    @State private var recurringIds: Set<String>?
    @State private var withHidden: [Transaction]?

    @State private var filtered: [Transaction] = []
    @State private var groups: [(date: String, txs: [Transaction])] = []
    @State private var shownPending: [Transaction] = []

    @State private var showFilter = false
    @State private var showManual = false
    @State private var path = NavigationPath()

    private var target: TxTarget { TxTarget.shared }

    var body: some View {
        NavigationStack(path: $path) {
            BandScreen(title: L("Umsätze"), compact: AnyView(compactBand)) {
                BandButton(systemImage: "slider.horizontal.3", label: L("Filter"), badge: tags.count) {
                    showFilter = true
                }
                BandButton(systemImage: "plus", label: L("Umsatz von Hand")) { showManual = true }
            } band: {
                band
            } sheet: {
                sheet
            }
            .navigationDestination(for: TxRoute.self) { TransactionDetailView(id: $0.id) }
            .sheet(isPresented: $showManual) { ManualEntryView() }
            .sheet(isPresented: $showFilter) {
                TransactionFilterSheet(
                    filter: $filter,
                    selectedAccount: $selectedAccount,
                    accounts: accounts,
                    resultCount: filtered.count,
                    categoryTotals: categoryTotals
                )
            }
        }
        .onAppear(perform: takeTarget)
        .onChange(of: target.category) { takeTarget() }
        .onChange(of: target.period) { takeTarget() }
        .onChange(of: target.query) { takeTarget() }
        .onChange(of: popToRoot) { path = NavigationPath() }
        .task(id: selectedAccount) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
            Task { await reload() }
        }
        .onChange(of: filter) { Task { await refilter() } }
    }

    // MARK: Band

    /// Hidden accounts count only with "Ausgeblendete zeigen" and all accounts.
    private var hiddenOn: Bool { filter.showHidden && selectedAccount == nil }

    private var shownAccounts: [Account] {
        accounts.filter { selectedAccount == nil ? !$0.isHidden : $0.id == selectedAccount }
    }

    /// The bank's closing balance, only when every shown account has one (FinTS).
    private var balance: Double? {
        let a = shownAccounts
        guard !a.isEmpty, a.allSatisfy({ $0.balance != nil }) else { return nil }
        return a.reduce(0) { $0 + ($1.balance ?? 0) }
    }

    private var anchored: Bool { balance != nil && !filter.isActive }

    private var title: String {
        if anchored {
            if accounts.count > 1 {
                let name = selectedAccount != nil ? (shownAccounts.first?.name ?? "") : L("alle Konten")
                return L("Kontostand · %s", name)
            }
            return L("Kontostand")
        }
        if let p = filter.period, p.key.hasSuffix(":salary"),
           filter == TxFilterState(period: p) {
            return L("Seit dem Gehalt am %s", PeriodLabels.dotted(p.from))
        }
        return filter.isActive ? L("Summe der Treffer") : L("Summe der Umsätze")
    }

    private var total: Double {
        anchored ? (balance ?? 0) : filtered.reduce(0) { $0 + $1.amount }
    }

    private var countLine: String {
        var parts: [String] = []
        if anchored {
            if let a = shownAccounts.first, shownAccounts.count == 1 { parts.append(a.bank.isEmpty ? a.name : a.bank) }
            if let d = shownAccounts.map(\.balanceDate).filter({ !$0.isEmpty }).max() {
                parts.append(L("Stand %s", WimgDates.short(d)))
            }
        }
        parts.append(filtered.count == 1 ? L("1 Umsatz") : L("%d Umsätze", filtered.count))
        return parts.joined(separator: " · ")
    }

    /// Pinned at the top while scrolling: what the sum is, and the sum.
    private var compactBand: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).wimgStyle(WimgType.caption).foregroundStyle(Wimg.bandSub).lineLimit(1)
            Amount(euros: total, style: WimgType.amountStat.size(18), centsStyle: WimgType.amountStat.size(12),
                   color: .white, showPlus: !anchored)
        }
    }

    @ViewBuilder private var band: some View {
        BandOver(text: title).padding(.top, 10)
        Amount(euros: total, style: WimgType.amountHero, centsStyle: WimgType.amountHeroCents,
               color: .white, showPlus: !anchored, rolls: true)
            .padding(.top, 2)
        Text(countLine).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).padding(.top, 4)
    }

    // MARK: Sheet

    private var tags: [FilterTag] {
        var t: [FilterTag] = []
        if !filter.text.isEmpty {
            let q = UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "“\(filter.text)”" : "„\(filter.text)“"
            t.append(FilterTag(kind: .text, label: q))
        }
        if let p = filter.period { t.append(FilterTag(kind: .period, label: p.tag)) }
        if let id = selectedAccount, accounts.count > 1, let a = accounts.first(where: { $0.id == id }) {
            t.append(FilterTag(kind: .account, label: a.name))
        }
        if filter.kind != .all { t.append(FilterTag(kind: .kind, label: L(filter.kind.rawValue))) }
        switch filter.categories.count {
        case 0: break
        case 1: t.append(FilterTag(kind: .categories, label: L(WimgCategory.from(filter.categories.first!).name)))
        default: t.append(FilterTag(kind: .categories, label: L("%d Kategorien", filter.categories.count)))
        }
        if let a = filter.amount.tag { t.append(FilterTag(kind: .amount, label: a)) }
        if filter.recurringOnly { t.append(FilterTag(kind: .recurring, label: L("nur wiederkehrende"))) }
        if hiddenOn { t.append(FilterTag(kind: .hidden, label: L("mit ausgeblendeten"))) }
        return t
    }

    private func remove(_ k: FilterTag.Kind) {
        switch k {
        case .text: filter.text = ""
        case .kind: filter.kind = .all
        case .account: selectedAccount = nil
        case .categories: filter.categories = []
        case .period: filter.period = nil
        case .amount: filter.amount = AmountRange()
        case .recurring: filter.recurringOnly = false
        case .hidden: filter.showHidden = false
        }
    }

    @ViewBuilder private var sheet: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags) { tag in
                        Button { withAnimation(WimgMotion.out(0.2)) { remove(tag.kind) } } label: {
                            HStack(spacing: 6) {
                                Text(tag.label).wimgStyle(WimgType.chip)
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(Wimg.accent)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Wimg.accentSoft, in: Capsule())
                        }
                        .buttonStyle(.wimgPress)
                        .accessibilityLabel(L("%s entfernen", tag.label))
                    }
                }
            }
            .padding(.bottom, 4)
        }

        if loaded && filtered.isEmpty && shownPending.isEmpty {
            VStack(spacing: 6) {
                Text(transactions.isEmpty ? L("Noch keine Umsätze") : L("Keine Treffer"))
                    .wimgStyle(WimgType.section).foregroundStyle(Wimg.text)
                Text(transactions.isEmpty ? L("Verbinde deine Bank oder importiere eine CSV.") : L("Ändere den Filter, um mehr zu sehen."))
                    .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }

        if !shownPending.isEmpty {
            GroupLabel(text: L("Vorgemerkt · %d", shownPending.count),
                       trailing: amountText(shownPending.reduce(0) { $0 + $1.amount }))
            ForEach(Array(shownPending.enumerated()), id: \.element.id) { i, tx in
                if i > 0 { FlatDivider() }
                TxRow(tx: tx, pending: true) { path.append(TxRoute(id: tx.id)) }
            }
        }

        ForEach(groups, id: \.date) { group in
            DayHeader(date: group.date, total: group.txs.reduce(0) { $0 + $1.amount })
            ForEach(Array(group.txs.enumerated()), id: \.element.id) { i, tx in
                if i > 0 { FlatDivider() }
                TxRow(tx: tx) { path.append(TxRoute(id: tx.id)) }
            }
        }
    }

    // MARK: Data

    private func takeTarget() {
        guard target.category != nil || target.period != nil || target.query != nil else { return }
        var f = TxFilterState()
        if let c = target.category { f.categories = [c] }
        f.period = target.period
        f.text = target.query ?? ""
        filter = f
        target.category = nil; target.period = nil; target.query = nil
        path = NavigationPath()
    }

    private func reload() async {
        let account = selectedAccount
        let (txs, pend, accs) = await Task.detached {
            let txs = ((try? LibWimg.getTransactionsFiltered(account: account)) ?? []).sorted { $0.date > $1.date }
            let pend = LibWimg.getPending(account: account).sorted { $0.date > $1.date }
            return (txs, pend, LibWimg.getAccounts())
        }.value
        transactions = txs
        pending = pend
        accounts = accs
        recurringIds = nil
        withHidden = nil
        await refilter()
        loaded = true
    }

    /// Filtering and grouping off the main thread: thousands of rows.
    private func refilter() async {
        let f = filter
        if f.recurringOnly && recurringIds == nil {
            recurringIds = await Task.detached {
                Set(LibWimg.getRecurring().filter { !$0.isHidden }.flatMap { p in
                    LibWimg.getRecurringPayments(id: p.id).filter { !$0.isOneoff }.map(\.id)
                })
            }.value
        }
        if hiddenOn && withHidden == nil {
            withHidden = await Task.detached {
                ((try? LibWimg.getTransactions()) ?? []).sorted { $0.date > $1.date }
            }.value
        }
        let base = hiddenOn ? (withHidden ?? transactions) : transactions
        let ids = recurringIds
        let pend = pending
        let (list, grouped, p) = await Task.detached {
            let list = f.isActive ? base.filter { f.matches($0, recurringIds: ids) } : base
            var grouped: [(date: String, txs: [Transaction])] = []
            for tx in list {
                if grouped.last?.date == tx.date { grouped[grouped.count - 1].txs.append(tx) }
                else { grouped.append((tx.date, [tx])) }
            }
            return (list, grouped, pend.filter { f.matches($0, recurringIds: ids) })
        }.value
        filtered = list
        groups = grouped
        shownPending = p
    }

    /// Category → sum of the rows that pass every filter but the category one.
    private func categoryTotals() -> [(id: Int, sum: Double)] {
        let f = filter, ids = recurringIds
        var sums: [Int: Double] = [:]
        for tx in (hiddenOn ? (withHidden ?? transactions) : transactions)
        where !tx.isExcluded && f.matchesExceptCategory(tx, recurringIds: ids) {
            sums[tx.category, default: 0] += tx.amount
        }
        return sums.map { ($0.key, $0.value) }
    }
}

// MARK: - Rows

private struct DayHeader: View {
    let date: String
    let total: Double

    var body: some View {
        HStack {
            Text(WimgDates.dayHeader(date))
            Spacer()
            Text(amountText(total)).foregroundStyle(total > 0.004 ? Wimg.pos : Wimg.text2)
        }
        .wimgStyle(WimgType.chip)
        .foregroundStyle(Wimg.text2)
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One booking: category tile, title, "Kategorie · Lastschrift", amount.
struct TxRow: View {
    let tx: Transaction
    var pending = false
    let action: () -> Void

    private var sub: String {
        var parts = [L(WimgCategory.from(tx.category).name)]
        if let k = tx.kind, !k.isEmpty { parts.append(L(k)) }
        if tx.isExcluded { parts.append(L("ausgeschlossen")) }
        if pending { parts.append(L("vorgemerkt")) }
        return parts.joined(separator: " · ")
    }

    private var amountColor: Color {
        if tx.isExcluded || pending { return Wimg.text3 }
        return tx.amount > 0 ? Wimg.pos : Wimg.text
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tx.displayTitle).wimgStyle(WimgType.rowTitle)
                        .foregroundStyle(tx.isExcluded ? Wimg.text3 : Wimg.text).lineLimit(1)
                    HStack(spacing: 7) {
                        Circle().fill(Wimg.categoryBar(tx.category)).frame(width: 7, height: 7)
                        Text(sub).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Amount(euros: tx.amount, color: amountColor)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
    }
}
