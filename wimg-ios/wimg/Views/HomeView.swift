import SwiftUI
import WimgI18n

/// Übersicht (brief 22, board 02; numbers as Android's HomeScreen.kt): what is
/// left until the salary (or in the month), the days left and per day,
/// salary / spending / Sparquote, spending by category, what is due next.
struct HomeView: View {
    @Binding var selectedAccount: String?
    @Binding var accounts: [Account]

    init(selectedAccount: Binding<String?>, accounts: Binding<[Account]>) {
        _selectedAccount = selectedAccount
        _accounts = accounts
    }

    @State private var chosen: HomeSelection?
    @State private var data: HomeData?
    @State private var showPeriod = false
    @State private var showManual = false
    @State private var path = NavigationPath()
    private var periods: PeriodState { PeriodState.shared }

    /// What is shown: the picked range, else the running period (Gehaltsmonat
    /// or "Fester Tag"), else this calendar month.
    private var selection: HomeSelection {
        if let chosen { return chosen }
        if let p = periods.data, !p.isCalendar, let cur = p.current { return .period(cur) }
        return .thisMonth
    }

    private var salaryMode: Bool { periods.data?.isSalary == true }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let d = data, !d.hasAnyData {
                    emptyHome
                } else {
                    page
                }
            }
            .navigationDestination(for: TxRoute.self) { TransactionDetailView(id: $0.id) }
            .navigationDestination(for: RecRoute.self) { RecurringDetailView(id: $0.id) }
            .navigationDestination(for: HomeDest.self) { d in
                switch d {
                case .fints: FinTSView()
                case .importFile: ImportView()
                }
            }
        }
        .task { if periods.data == nil { await periods.reload() } }
        .task(id: LoadKey(sel: selection, account: selectedAccount)) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
            Task { await periods.reload(); await load() }
        }
        // Another mode or start day makes other periods: back to the running one.
        .onChange(of: periods.data?.mode) { chosen = nil }
        .onChange(of: periods.data?.day) { chosen = nil }
        .sheet(isPresented: $showPeriod) {
            PeriodSheet(selection: selection, selectedAccount: $selectedAccount, accounts: accounts) { chosen = $0 }
        }
        .sheet(isPresented: $showManual) { ManualEntryView() }
    }

    private struct LoadKey: Equatable { let sel: HomeSelection; let account: String? }
    enum HomeDest: Hashable { case fints, importFile }

    // MARK: Page

    private var page: some View {
        BandScreen(title: L("Übersicht")) {
            if data != nil {
                BandPeriodButton(fraction: selection.ring, text: selection.buttonText(salary: salaryMode),
                                 label: periodLabel) { showPeriod = true }
            }
            BandButton(systemImage: "plus", label: L("Umsatz von Hand")) { showManual = true }
        } band: {
            band
        } sheet: {
            sheet
        }
    }

    private var periodLabel: String {
        selection.isCurrent ? L("Zeitraum: noch %d Tage", selection.daysLeft) : L("Zeitraum") + ": " + selection.buttonText(salary: salaryMode)
    }

    // MARK: Band

    private var periodInfo: PeriodInfo? { if case let .period(p) = selection.kind { return p }; return nil }
    private var overdue: Bool {
        guard let p = periodInfo, p.isCurrent, salaryMode else { return false }
        return (periods.data?.salary?.overdue_days ?? 0) > 0
    }

    private var overLine: String {
        let cur = selection.isCurrent
        switch selection.kind {
        case let .month(_, m):
            return L("Verfügbar im %s", WimgDates.months()[m - 1])
        case let .period(p):
            if !cur { return salaryMode ? L("Gehaltsmonat %s", PeriodLabels.short(p)) : PeriodLabels.short(p) }
            if overdue { return L("Verfügbar seit dem Gehalt") }
            return salaryMode ? L("Noch verfügbar bis zum Gehalt") : L("Noch verfügbar bis zum %d.", periods.data?.day ?? 1)
        case .custom:
            return "\(PeriodLabels.dotted(selection.from)) – \(PeriodLabels.dotted(selection.to))"
        }
    }

    private var subLine: String {
        let s = data?.summary
        let available = s?.available ?? 0
        let left = selection.daysLeft
        if overdue { return L("Der Zeitraum läuft weiter, bis das Gehalt da ist.") }
        if selection.isCurrent {
            if let p = periodInfo, salaryMode, selection.daysIn == 1 {
                return (p.early_days ?? 0) > 0 ? L("Gehaltsmonat beginnt heute · %d Tage früher", p.early_days ?? 0)
                    : L("Gehaltsmonat beginnt heute · bis ~%s", PeriodLabels.dotted(p.to))
            }
            if available > 0.004 && left > 0 { return L("noch %d Tage · %s pro Tag", left, amountText(available / Double(left), showPlus: false)) }
            return L("noch %d Tage", left)
        }
        let n = s?.tx_count ?? 0
        return n == 1 ? L("1 Umsatz") : L("%d Umsätze", n)
    }

    /// Sparquote, hidden while it would mislead: income must cover spending
    /// and be at least 10 % of the previous range's.
    private var quote: Int? {
        guard let s = data?.summary, !overdue else { return nil }
        let income = s.income, spent = abs(s.expenses)
        let prevIncome = data?.previous?.income ?? 0
        guard income > 0, income >= spent, prevIncome <= 0 || income >= prevIncome * 0.1 else { return nil }
        return Int(((income - spent) / income * 100).rounded())
    }

    @ViewBuilder private var band: some View {
        let s = data?.summary
        let available = s?.available ?? 0
        let income = s?.income ?? 0
        let spent = abs(s?.expenses ?? 0)
        if overdue {
            let n = periods.data?.salary?.overdue_days ?? 0
            Label(n == 1 ? L("Gehalt erwartet seit 1 Tag") : L("Gehalt erwartet seit %d Tagen", n), systemImage: "clock")
                .wimgStyle(WimgType.chip).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.10), in: Capsule())
                .padding(.vertical, 8)
        }
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                BandOver(text: overLine)
                Amount(euros: available, style: WimgType.amountHero, centsStyle: WimgType.amountHeroCents,
                       color: available > 0.004 ? Wimg.bandPos : (available < -0.004 ? Wimg.bandNeg : .white), rolls: true)
                Text(subLine).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub)
            }
            Spacer(minLength: 8)
            if !selection.isCurrent, let q = quote { SavingsRing(percent: q) }
        }
        .padding(.top, 10)
        Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.top, 20)
        HStack(alignment: .top, spacing: 8) {
            if overdue {
                BandStat(label: L("Seit Gehalt"), value: amountText(-spent), color: .white)
                BandStat(label: L("Erwartet am"), value: PeriodLabels.dotted(periods.data?.salary?.next ?? ""), color: .white)
                BandStat(label: L("Ausgaben/Tag"), value: amountText(spent / Double(max(selection.daysIn, 1)), showPlus: false), color: .white)
            } else if let p = periodInfo, p.isCurrent, salaryMode {
                BandStat(label: L("Gehalt %s", PeriodLabels.dotted(p.from)), value: amountText(p.salary ?? income), color: Wimg.bandPos)
                BandStat(label: L("Seitdem ausgegeben"), value: amountText(-spent), color: .white)
                BandStat(label: L("Sparquote"), value: quote.map { "\($0) %" } ?? "–", color: .white)
            } else {
                BandStat(label: L("Einnahmen"), value: amountText(income), color: Wimg.bandPos)
                BandStat(label: L("Ausgaben"), value: amountText(-spent), color: .white)
                if selection.isCurrent {
                    BandStat(label: L("Sparquote"), value: quote.map { "\($0) %" } ?? "–", color: .white)
                } else {
                    BandStat(label: L("Ausgaben/Tag"), value: amountText(spent / Double(max(selection.daysIn, 1)), showPlus: false), color: .white)
                }
            }
        }
        .padding(.top, 14)
    }

    // MARK: Sheet

    @ViewBuilder private var sheet: some View {
        let s = data?.summary
        // by_category holds spending per category as positive amounts.
        let cats = (s?.by_category ?? []).filter { $0.amount > 0.004 && $0.id != 10 }.sorted { $0.amount > $1.amount }
        let total = cats.reduce(0) { $0 + abs($1.amount) }
        let prevById = Dictionary((data?.previous?.by_category ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let title = periodInfo?.isCurrent == true && salaryMode ? L("Ausgaben seit dem Gehalt") : L("Ausgaben nach Kategorie")

        if !cats.isEmpty {
            SectionTitle(text: title, trailing: prevById.isEmpty ? nil : compareLabel)
            WimgGroup {
                ForEach(Array(cats.enumerated()), id: \.element.id) { i, cat in
                    if i > 0 { RowDivider() }
                    CategoryShareRow(cat: cat, total: total, previous: prevById[cat.id]) { openCategory(cat.id) }
                }
            }
        } else if data != nil {
            SectionTitle(text: title)
            Text(selection.isCurrent && salaryMode ? L("Noch keine Ausgaben seit dem Gehalt.") : L("Noch keine Ausgaben in diesem Zeitraum."))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).padding(.horizontal, 4)
        }

        if let pending = data?.pending, !pending.isEmpty {
            SectionTitle(text: L("Vorgemerkt"), trailing: amountText(pending.reduce(0) { $0 + $1.amount }))
            WimgGroup {
                ForEach(Array(pending.enumerated()), id: \.element.id) { i, tx in
                    if i > 0 { RowDivider() }
                    TxRow(tx: tx, pending: true) { path.append(TxRoute(id: tx.id)) }
                }
            }
        }

        if let due = data?.nextDue, !due.isEmpty {
            SectionTitle(text: L("Als Nächstes fällig"), trailing: L("Wiederkehrend")) { AppNav.shared.open(.recurring) }
            WimgGroup {
                ForEach(Array(due.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { RowDivider() }
                    WimgRow(title: p.displayName, desc: dueLine(p), action: { path.append(RecRoute(id: p.id)) }) {
                        IconTile(systemImage: p.interval == "monthly" ? "arrow.clockwise" : "arrow.2.squarepath", tint: Wimg.text)
                    } trailing: {
                        Amount(euros: p.amount, color: p.amount > 0 ? Wimg.pos : Wimg.text)
                    }
                }
            }
        }
    }

    private var compareLabel: String {
        if case let .month(_, m) = selection.kind { return L("vs. %s", WimgDates.months()[(m + 10) % 12]) }
        return L("vs. davor")
    }

    private func dueLine(_ p: RecurringPattern) -> String {
        let date = p.next_due.map { WimgDates.short($0) } ?? ""
        return [date, L(WimgCategory.from(p.category).name)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func openCategory(_ id: Int) {
        TxTarget.shared.category = id
        TxTarget.shared.period = selection.txPeriod(salary: salaryMode)
        AppNav.shared.open(.transactions)
    }

    // MARK: Empty

    private var emptyHome: some View {
        BandScreen(title: L("Übersicht")) {
            Text(L("Noch keine Umsätze")).wimgStyle(WimgType.title).foregroundStyle(.white).padding(.top, 8)
            Text(L("Verbinde deine Bank oder importiere eine Datei von ihr. Alles bleibt auf diesem Telefon."))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).padding(.top, 6)
        } sheet: {
            VStack(spacing: 10) {
                emptyAction("building.columns", L("Bank verbinden"), L("Umsätze direkt per FinTS holen"), accent: true) { path.append(HomeDest.fints) }
                emptyAction("square.and.arrow.down", L("Datei importieren"), L("Kontoauszug oder CSV, auch Revolut")) { path.append(HomeDest.importFile) }
                Button(L("Beispieldaten ansehen")) {
                    Task { await Task.detached { DemoDataService.loadDemoData() }.value }
                }
                .wimgStyle(WimgType.button)
                .foregroundStyle(Wimg.accent)
                .padding(12)
            }
        }
    }

    private func emptyAction(_ icon: String, _ title: String, _ desc: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20)).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).wimgStyle(WimgType.button)
                    Text(desc).wimgStyle(WimgType.desc).opacity(0.75)
                }
                Spacer()
            }
            .foregroundStyle(accent ? Wimg.inkText : Wimg.text)
            .padding(16)
            .background(accent ? Wimg.ink : Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(accent ? .clear : Wimg.line, lineWidth: 1))
        }
        .buttonStyle(.wimgPress)
    }

    // MARK: Data

    private func load() async {
        let sel = selection, account = selectedAccount
        let prev = sel.previous(in: periods.data)
        data = await Task.detached { HomeData.load(sel, prev: prev, account: account) }.value
    }
}

/// Everything Übersicht shows for one range.
struct HomeData {
    var summary: MonthlySummary?
    var previous: MonthlySummary?
    var pending: [Transaction] = []
    var nextDue: [RecurringPattern] = []
    var hasAnyData = true

    nonisolated static func load(_ sel: HomeSelection, prev: HomeSelection?, account: String?) -> HomeData {
        let summary = LibWimg.getSummaryRange(from: sel.from, to: sel.to, account: account)
        let previous = prev.flatMap { LibWimg.getSummaryRange(from: $0.from, to: $0.to, account: account) }
        let all = (try? LibWimg.getTransactionsFiltered(account: account)) ?? []
        // "Noch keine Umsätze" is for an empty wimg, not an empty account.
        let any = !all.isEmpty || (account != nil && !((try? LibWimg.getTransactions()) ?? []).isEmpty)
        let today = WimgDates.todayIso()
        let due = LibWimg.getRecurring()
            .filter { $0.isActive && !$0.isHidden && $0.amount < 0 && ($0.next_due ?? "") >= today }
            .sorted { ($0.next_due ?? "") < ($1.next_due ?? "") }
        return HomeData(
            summary: summary,
            previous: (previous?.tx_count ?? 0) > 0 ? previous : nil,
            pending: sel.isCurrent ? LibWimg.getPending(account: account) : [],
            nextDue: Array(due.prefix(3)),
            hasAnyData: any
        )
    }
}

struct RecRoute: Hashable { let id: String }

// MARK: - Pieces

/// Label over a figure in the band's stat row.
struct BandStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).wimgStyle(WimgType.caption).foregroundStyle(Wimg.bandSub).lineLimit(1)
            Text(value).wimgStyle(WimgType.amountStat).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Sparquote of a closed range as a ring.
struct SavingsRing: View {
    let percent: Int

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(Wimg.bandPos, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent) %").font(WimgFont.font(.manrope, .heavy, 14)).foregroundStyle(.white)
                Text(L("Sparquote")).font(WimgType.caption.font).foregroundStyle(Wimg.bandSub)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Sparquote %d Prozent", percent))
    }
}

/// A category on Übersicht: tile, name, its share as a bar, amount (board 02).
private struct CategoryShareRow: View {
    let cat: CategoryBreakdown
    let total: Double
    let previous: CategoryBreakdown?
    let action: () -> Void

    var body: some View {
        let share = total > 0 ? abs(cat.amount) / total : 0
        let change: Int? = {
            guard let p = previous, p.amount > 0.004 else { return nil }
            let c = Int(((abs(cat.amount) - p.amount) / p.amount * 100).rounded())
            return c == 0 ? nil : c
        }()
        Button(action: action) {
            HStack(spacing: 12) {
                CategoryTile(category: cat.id)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L(WimgCategory.from(cat.id).name)).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(1)
                        Spacer(minLength: 8)
                        Amount(euros: abs(cat.amount), color: Wimg.text, showPlus: false)
                    }
                    HStack(spacing: 8) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Wimg.neutralTint)
                                Capsule().fill(Wimg.categoryBar(cat.id)).frame(width: max(4, g.size.width * share))
                            }
                        }
                        .frame(height: 4)
                        if let change {
                            Text("\(change > 0 ? "▲" : "▼") \(min(abs(change), 999)) %")
                                .font(WimgFont.font(.manrope, .bold, 12))
                                .foregroundStyle(change > 0 ? Wimg.danger : Wimg.pos)
                                .fixedSize()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("In Umsätzen zeigen"))
    }
}
