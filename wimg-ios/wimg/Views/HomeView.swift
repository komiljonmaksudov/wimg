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

    /// The squirrel: pose from what is left per day vs. the usual daily spending
    /// of the previous range; one moment per period (or per day for "kein Euro raus").
    private func squirrel(available: Double, spent: Double) -> some View {
        let prevSpent = abs(data?.previous?.expenses ?? 0)
        let prevDays = max(Double(Calendar(identifier: .gregorian).dateComponents([.day], from: WimgDates.parse(selection.from) ?? Date(), to: WimgDates.parse(selection.to) ?? Date()).day ?? 30) + 1, 1)
        let usual = prevSpent / prevDays
        let salaryToday = data?.salaryToday ?? false
        let (pose, line) = SquirrelState.of(available: available, daysLeft: selection.daysLeft, usualPerDay: usual,
                                           salaryToday: salaryToday, salary: periodInfo?.salary, salaryMode: salaryMode)
        let periodKey = selection.from
        let days = max(selection.daysLeft, 1)
        let hour = Calendar.current.component(.hour, from: Date())
        var moment: (key: String, from: SquirrelPose, text: String)?
        switch pose {
        case .gehalt: moment = ("gehalt:\(periodKey)", .leer, L("Gehalt ist da. Neuer Gehaltsmonat."))
        case .leer: moment = ("leer:\(periodKey)", .knapp, salaryMode
            ? L("Leer. Die Motte findet's gemütlich. Gehalt kommt in ~%d Tagen.", days)
            : L("Leer. Die Motte findet's gemütlich. Neuer Monat in %d Tagen.", days))
        case .knapp: moment = ("knapp:\(periodKey)", .normal,
            L("%s für %d Tage. Das sind %s am Tag. Geht.", amountText(available, showPlus: false), days, amountText(available / Double(days), showPlus: false)))
        default:
            if hour >= 20 && !(data?.spentToday ?? true) {
                moment = ("nospend:\(WimgDates.todayIso())", .yawn, L("Heute kein Euro raus."))
            }
        }
        let shownPose: SquirrelPose = (moment?.key.hasPrefix("nospend") ?? false) ? .sleep : pose
        let past = max(selection.daysIn - 1, 0)
        let ring = SquirrelRingDays(total: selection.daysIn + selection.daysLeft - 1, past: past,
                                    noSpend: noSpendDays(past: past))
        let narrow = UIScreen.main.bounds.width < 380
        return SquirrelView(pose: shownPose, line: line, moment: moment, size: narrow ? 99 : 112, ring: ring)
    }

    /// Past days (1-based) of the range without any spending (Android noSpendDays).
    private func noSpendDays(past: Int) -> Set<Int> {
        guard past > 0, let start = WimgDates.parse(selection.from), let spent = data?.spendDates else { return [] }
        let cal = Calendar(identifier: .gregorian)
        return Set((1...past).filter { i in
            !spent.contains(WimgDates.iso(cal.date(byAdding: .day, value: i - 1, to: start)!))
        })
    }

    /// "Stand heute, 06:12 · comdirect": the newest bank fetch. Nothing without a bank.
    private var freshness: String? {
        guard selection.isCurrent,
              let c = BankConnections.all().filter({ $0.lastFetchAt > 0 }).max(by: { $0.lastFetchAt < $1.lastFetchAt })
        else { return nil }
        let at = Date(timeIntervalSince1970: c.lastFetchAt)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let time = f.string(from: at)
        switch WimgDates.daysAgo(at) {
        case 0: return L("Stand heute, %s · %s", time, c.name)
        case 1: return L("Stand gestern, %s · %s", time, c.name)
        default: return L("Stand %s · %s", WimgDates.short(WimgDates.iso(at)), c.name)
        }
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
            if selection.isCurrent, s != nil { squirrel(available: available, spent: spent) }
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
        if let freshness {
            Text(freshness).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).lineLimit(1).padding(.top, 12)
        }
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
            HomeSectionHeader(title: title, trailing: prevById.isEmpty ? nil : compareLabel)
            StackedBar(cats: cats, total: total)
            ForEach(cats, id: \.id) { cat in
                CategoryShareRow(cat: cat, total: total, previous: prevById[cat.id]) { openCategory(cat.id) }
                FlatDivider()
            }
        } else if data != nil {
            HomeSectionHeader(title: title, trailing: nil)
            Text(selection.isCurrent && salaryMode ? L("Noch keine Ausgaben seit dem Gehalt.") : L("Noch keine Ausgaben in diesem Zeitraum."))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).padding(.top, 10)
        }

        if let pending = data?.pending, !pending.isEmpty {
            HomeSectionHeader(title: L("Vorgemerkt"), trailing: amountText(pending.reduce(0) { $0 + $1.amount }))
                .padding(.top, 22).padding(.bottom, 4)
            ForEach(pending, id: \.id) { tx in
                DayRow(tx: tx, pending: true) { path.append(TxRoute(id: tx.id)) }
                FlatDivider()
            }
        }

        if let day = data?.day, let first = day.first {
            HomeSectionHeader(title: dayLabel(first.date), trailing: amountText(day.reduce(0) { $0 + $1.amount }), strong: true)
                .padding(.top, 22).padding(.bottom, 4)
            ForEach(day, id: \.id) { tx in
                DayRow(tx: tx) { path.append(TxRoute(id: tx.id)) }
                FlatDivider()
            }
        }
    }

    /// "Heute", "Gestern" or "Do. 19. Nov." (Android dayLabel).
    private func dayLabel(_ iso: String) -> String {
        guard let d = WimgDates.parse(iso) else { return iso }
        switch WimgDates.daysAgo(d) {
        case 0: return L("Heute")
        case 1: return L("Gestern")
        default: return "\(WimgDates.weekday(d)) \(WimgDates.short(iso))"
        }
    }

    private var compareLabel: String {
        if case let .month(_, m) = selection.kind { return L("vs. %s", WimgDates.months()[(m + 10) % 12]) }
        return L("vs. davor")
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
    /// The newest day in the range with bookings (up to six).
    var day: [Transaction] = []
    var spendDates: Set<String> = []
    var hasAnyData = true
    /// For the squirrel: something was spent today; a salary came today.
    var spentToday = false
    var salaryToday = false

    nonisolated static func load(_ sel: HomeSelection, prev: HomeSelection?, account: String?) -> HomeData {
        let summary = LibWimg.getSummaryRange(from: sel.from, to: sel.to, account: account)
        let previous = prev.flatMap { LibWimg.getSummaryRange(from: $0.from, to: $0.to, account: account) }
        let all = (try? LibWimg.getTransactionsFiltered(account: account)) ?? []
        // "Noch keine Umsätze" is for an empty wimg, not an empty account.
        let any = !all.isEmpty || (account != nil && !((try? LibWimg.getTransactions()) ?? []).isEmpty)
        let today = WimgDates.todayIso()
        let inRange = all.filter { $0.date >= sel.from && $0.date <= sel.to && $0.date <= today && !$0.isExcluded }
        let last = inRange.map(\.date).max()
        return HomeData(
            summary: summary,
            previous: (previous?.tx_count ?? 0) > 0 ? previous : nil,
            pending: sel.isCurrent ? LibWimg.getPending(account: account) : [],
            day: last.map { d in Array(inRange.filter { $0.date == d }.prefix(6)) } ?? [],
            spendDates: Set(inRange.filter { $0.amount < 0 }.map(\.date)),
            hasAnyData: any,
            spentToday: all.contains { $0.date == today && $0.amount < 0 && !$0.isExcluded },
            salaryToday: all.contains { $0.date == today && $0.category == 10 && $0.amount > 0 }
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

/// Section title on Übersicht (Android SectionHeader).
private struct HomeSectionHeader: View {
    let title: String
    let trailing: String?
    var strong = false

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(WimgFont.font(.manrope, .bold, 19, relativeTo: .title3)).foregroundStyle(Wimg.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if let trailing {
                Text(trailing).wimgStyle(strong ? WimgType.chip : WimgType.caption).foregroundStyle(Wimg.text2)
            }
        }
    }
}

/// The month's spending as one bar, a piece per category.
private struct StackedBar: View {
    let cats: [CategoryBreakdown]
    let total: Double

    var body: some View {
        GeometryReader { g in
            let gaps = CGFloat(max(cats.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(cats, id: \.id) { cat in
                    Rectangle().fill(Wimg.categoryBar(cat.id))
                        .frame(width: max(1.5, (g.size.width - gaps) * CGFloat(abs(cat.amount) / max(total, 0.01))))
                }
            }
        }
        .frame(height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.top, 14).padding(.bottom, 6)
        .accessibilityElement()
        .accessibilityLabel(cats.map { "\(L(WimgCategory.from($0.id).name)) \(Int((abs($0.amount) / max(total, 0.01) * 100).rounded())) %" }.joined(separator: ", "))
    }
}

/// A booking on Übersicht: title, dot + date · category, amount (Android DayRow).
private struct DayRow: View {
    let tx: Transaction
    var pending = false
    let action: () -> Void

    var body: some View {
        let sub = [WimgDates.short(tx.date), L(WimgCategory.from(tx.category).name), tx.kind.flatMap { $0.isEmpty ? nil : L($0) },
                   pending ? L("vorgemerkt") : nil].compactMap { $0 }.joined(separator: " · ")
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.displayTitle).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(Wimg.categoryBar(tx.category)).frame(width: 6, height: 6)
                        Text(sub).wimgStyle(WimgType.caption).foregroundStyle(Wimg.text2).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Amount(euros: tx.amount, color: pending ? Wimg.text3 : (tx.amount > 0 ? Wimg.pos : Wimg.text))
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// A category on Übersicht (Android CategoryRow): icon tile, name and amount,
/// its share as a short bar with the percent, the change against before.
private struct CategoryShareRow: View {
    let cat: CategoryBreakdown
    let total: Double
    let previous: CategoryBreakdown?
    let action: () -> Void

    var body: some View {
        let pct = total > 0 ? Int((abs(cat.amount) / total * 100).rounded()) : 0
        let change: Int? = {
            guard let p = previous, p.amount > 0.004 else { return nil }
            let c = Int(((abs(cat.amount) - p.amount) / p.amount * 100).rounded())
            return c == 0 ? nil : c
        }()
        Button(action: action) {
            HStack(spacing: 12) {
                CategoryTile(category: cat.id, size: 34)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .lastTextBaseline) {
                        Text(L(WimgCategory.from(cat.id).name)).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(1)
                        Spacer(minLength: 8)
                        Amount(euros: abs(cat.amount), color: Wimg.text, showPlus: false)
                    }
                    HStack(spacing: 8) {
                        Capsule().fill(Wimg.categoryBar(cat.id)).frame(width: CGFloat(min(max(pct * 2, 4), 180)), height: 4)
                        Text("\(pct) %").wimgStyle(WimgType.caption).foregroundStyle(Wimg.text2)
                        Spacer(minLength: 0)
                        if let change {
                            HStack(spacing: 2) {
                                Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 9))
                                Text("\(min(abs(change), 999)) %").font(WimgFont.font(.manrope, .bold, 12))
                            }
                            .foregroundStyle(change > 0 ? Wimg.danger : Wimg.pos)
                            .fixedSize()
                        }
                    }
                }
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("In Umsätzen zeigen"))
    }
}
