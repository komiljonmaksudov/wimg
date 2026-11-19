import SwiftUI
import WimgI18n

/// Rückblick (Android ReviewScreen.kt): one sentence on the month or
/// Gehaltsmonat in the band, income / spending / count, and what stood out.
/// The squirrel opener cards are not on iOS yet.
struct ReviewView: View {
    @Binding var selectedAccount: String?

    init(selectedAccount: Binding<String?>) {
        _selectedAccount = selectedAccount
    }

    @State private var chosen: HomeSelection?
    @State private var data: ReviewData?
    @State private var accounts: [Account] = []
    @State private var showPeriod = false
    @State private var showOpener = false
    private var periods: PeriodState { PeriodState.shared }

    private var selection: HomeSelection {
        if let chosen { return chosen }
        if let p = periods.data, !p.isCalendar, let cur = p.current { return .period(cur) }
        return .thisMonth
    }

    private var salaryMode: Bool { periods.data?.isSalary == true }
    private var periodInfo: PeriodInfo? { if case let .period(p) = selection.kind { return p }; return nil }

    private struct LoadKey: Equatable { let sel: HomeSelection; let account: String? }

    var body: some View {
        BandScreen(title: L("Rückblick"), pushed: true) {
            BandPeriodButton(fraction: selection.ring, text: selection.buttonText(salary: salaryMode),
                             label: L("Zeitraum") + ": " + selection.buttonText(salary: salaryMode)) { showPeriod = true }
        } band: {
            band
        } sheet: {
            sheet
        }
        .fullScreenCover(isPresented: $showOpener) {
            ReviewOpenerView(title: L("Rückblick %s", openerLabel), cards: openerCards) { showOpener = false }
        }
        .sheet(isPresented: $showPeriod) {
            PeriodSheet(selection: selection, allowCustom: false, selectedAccount: $selectedAccount, accounts: accounts) { chosen = $0 }
        }
        .task { if periods.data == nil { await periods.reload() } }
        .task { accounts = await Task.detached { LibWimg.getAccounts() }.value }
        .task(id: LoadKey(sel: selection, account: selectedAccount)) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in Task { await load() } }
    }

    // MARK: Opener

    private var openerLabel: String {
        if case let .month(_, m) = selection.kind { return WimgDates.months()[m - 1] }
        return PeriodLabels.short(.init(from: selection.from, to: selection.to, days: 0))
    }

    private var openerCards: [OpenerCard] {
        guard let d = data else { return [] }
        var prev: String?
        if case let .month(_, m) = selection.kind { prev = WimgDates.months()[(m + 10) % 12] }
        return ReviewOpenerCards.cards(d, label: openerLabel, prevLabel: prev, salaryMode: salaryMode)
    }

    /// Once per finished period, when it went at least as well as the one before.
    private func maybeOpen() {
        guard !selection.isCurrent, !openerCards.isEmpty, let s = data?.summary, s.income > 0 else { return }
        let rate = (s.income - abs(s.expenses)) / s.income
        if let p = data?.previous, p.income > 0, rate < (p.income - abs(p.expenses)) / p.income { return }
        let key = "opener:\(selection.from):\(selectedAccount ?? "")"
        var played = Set(UserDefaults.standard.stringArray(forKey: "wimg_moments") ?? [])
        guard !played.contains(key) else { return }
        played.insert(key)
        UserDefaults.standard.set(Array(played.suffix(60)), forKey: "wimg_moments")
        showOpener = true
    }

    // MARK: Band

    private var overLine: String {
        let cur = selection.isCurrent
        switch selection.kind {
        case .month:
            if cur, let last = data?.lastDate { return L("Monatsabschluss · Vorschau mit Daten bis %s", WimgDates.short(last)) }
            return L("Monatsabschluss")
        case let .period(p):
            let range = PeriodLabels.short(p)
            if salaryMode { return cur ? L("Gehaltsmonat %s · läuft noch", range) : L("Gehaltsmonat %s", range) }
            return cur ? L("%s · läuft noch", range) : range
        case .custom:
            return "\(PeriodLabels.dotted(selection.from)) – \(PeriodLabels.dotted(selection.to))"
        }
    }

    /// The sentence with the net amount coloured: (before, amount, after).
    private var headline: (String, String, String)? {
        guard let s = data?.summary, s.tx_count > 0 else { return nil }
        let net = s.income - abs(s.expenses)
        let template: String
        if case let .month(_, m) = selection.kind {
            let month = WimgDates.months()[m - 1]
            template = net < 0 ? L("Dein %s: Du hast %s mehr ausgegeben als eingenommen.", month, "\u{0}")
                : L("Dein %s: Du hast %s mehr eingenommen als ausgegeben.", month, "\u{0}")
        } else if salaryMode && net >= 0 {
            template = selection.isCurrent ? L("Vom Gehalt sind noch %s übrig.", "\u{0}") : L("Vom Gehalt sind %s übrig geblieben.", "\u{0}")
        } else {
            template = net < 0 ? L("Du hast %s mehr ausgegeben als eingenommen.", "\u{0}") : L("Du hast %s mehr eingenommen als ausgegeben.", "\u{0}")
        }
        let parts = template.components(separatedBy: "\u{0}")
        return (parts.first ?? "", amountText(abs(net), showPlus: false), parts.count > 1 ? parts[1] : "")
    }

    private var change: Int? {
        guard let s = data?.summary, let p = data?.previous, abs(p.expenses) >= 0.01 else { return nil }
        let c = Int(((abs(s.expenses) - abs(p.expenses)) / abs(p.expenses) * 100).rounded())
        return c == 0 ? nil : c
    }

    @ViewBuilder private var band: some View {
        BandOver(text: overLine)
        if let (a, amount, b) = headline {
            let net = (data?.summary?.income ?? 0) - abs(data?.summary?.expenses ?? 0)
            (Text(a) + Text(amount).foregroundStyle(net < 0 ? Wimg.bandNeg : Wimg.bandPos) + Text(b))
                .font(WimgType.title.font).tracking(WimgType.title.tracking)
                .foregroundStyle(.white)
                .padding(.top, 6)
        } else {
            Text(L("In diesem Zeitraum gibt es noch keine Umsätze."))
                .wimgStyle(WimgType.title).foregroundStyle(.white).padding(.top, 6)
        }
        if let c = change {
            Text(changeLine(c)).wimgStyle(WimgType.body).foregroundStyle(Wimg.bandSub).padding(.top, 8)
        }
    }

    private func changeLine(_ c: Int) -> String {
        switch selection.kind {
        case let .month(_, m):
            let prev = WimgDates.months()[(m + 10) % 12]
            return c < 0 ? L("%d %% weniger Ausgaben als im %s.", -c, prev) : L("%d %% mehr Ausgaben als im %s.", c, prev)
        default:
            let range = selection.previous(in: periods.data).map { "\(PeriodLabels.dotted($0.from)) – \(PeriodLabels.dotted($0.to))" } ?? ""
            if salaryMode {
                return c < 0 ? L("%d %% weniger ausgegeben als im Gehaltsmonat davor (%s).", -c, range)
                    : L("%d %% mehr ausgegeben als im Gehaltsmonat davor (%s).", c, range)
            }
            return c < 0 ? L("%d %% weniger ausgegeben als im Monat davor (%s).", -c, range)
                : L("%d %% mehr ausgegeben als im Monat davor (%s).", c, range)
        }
    }

    // MARK: Sheet

    @ViewBuilder private var sheet: some View {
        if let d = data, let s = d.summary, s.tx_count > 0 {
            let expenses = abs(s.expenses)
            if !selection.isCurrent && !openerCards.isEmpty {
                WimgGroup {
                    WimgRow(title: L("Rückblick als Karten ansehen"), chevron: true, action: { showOpener = true }) {
                        Image(SquirrelPose.voll.image).resizable().scaledToFit().frame(width: 40, height: 40)
                    }
                }
                .padding(.bottom, 12)
            }
            HStack(spacing: 10) {
                tile(L("Einnahmen"), amountText(s.income), Wimg.pos)
                tile(L("Ausgaben"), amountText(-expenses), Wimg.text)
                if let p = periodInfo { tile(L("Tage"), "\(p.days)", Wimg.text) } else { tile(L("Umsätze"), "\(s.tx_count)", Wimg.text) }
            }
            GroupLabel(text: L("Aufgefallen"))
            WimgGroup {
                ForEach(Array(items(d, s).enumerated()), id: \.offset) { i, item in
                    if i > 0 { RowDivider() }
                    item
                }
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).lineLimit(1)
            Text(value).wimgStyle(WimgType.amountStat).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func items(_ d: ReviewData, _ s: MonthlySummary) -> [AnyView] {
        var out: [AnyView] = []
        let expenses = abs(s.expenses)
        if let t = d.biggest {
            out.append(AnyView(item("dollarsign.circle", Wimg.category(13), L("Größte Einzelausgabe"),
                                    "\(t.displayTitle) · \(WimgDates.short(t.date))", amountText(t.amount))))
        }
        // Category changes vs. the range before, over categories in both.
        let prevById = Dictionary((d.previous?.by_category ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let changes: [(CategoryBreakdown, Int)] = s.by_category.filter { $0.amount != 0 && $0.id != 0 && $0.id != 10 }.compactMap { cat in
            guard let p = prevById[cat.id], abs(p.amount) >= 0.01 else { return nil }
            return (cat, Int(((abs(cat.amount) - abs(p.amount)) / abs(p.amount) * 100).rounded()))
        }
        let prevShort: String? = { if case let .month(_, m) = selection.kind { return WimgDates.shortMonths()[(m + 10) % 12] }; return nil }()
        if let (cat, pct) = changes.filter({ $0.1 > 0 }).max(by: { $0.1 < $1.1 }) {
            out.append(AnyView(item("chart.line.uptrend.xyaxis", Wimg.danger,
                                    prevShort.map { L("Stärkster Anstieg vs. %s", $0) } ?? L("Stärkster Anstieg"),
                                    "\(L(WimgCategory.from(cat.id).name)) ▲ \(pct) %", amountText(abs(cat.amount), showPlus: false))))
        }
        if let (cat, pct) = changes.filter({ $0.1 < 0 }).min(by: { $0.1 < $1.1 }) {
            out.append(AnyView(item("chart.line.downtrend.xyaxis", Wimg.pos,
                                    prevShort.map { L("Stärkster Rückgang vs. %s", $0) } ?? L("Stärkster Rückgang"),
                                    "\(L(WimgCategory.from(cat.id).name)) ▼ \(-pct) %", amountText(abs(cat.amount), showPlus: false))))
        }
        if let cat = s.by_category.first(where: { $0.id == 0 && $0.amount != 0 }) {
            let share = expenses != 0 ? Int((abs(cat.amount) / expenses * 100).rounded()) : 0
            out.append(AnyView(item("tag", Wimg.text2, L("Noch nicht zugeordnet"), "\(L("Unkategorisiert")) · \(share) %",
                                    amountText(abs(cat.amount), showPlus: false)) {
                TxTarget.shared.category = 0
                TxTarget.shared.period = selection.txPeriod(salary: salaryMode)
                AppNav.shared.open(.transactions)
            }))
        }
        if let t = d.otherIncome {
            out.append(AnyView(item("arrow.uturn.backward", Wimg.text2, L("Weitere Einnahme"), t.displayTitle, amountText(t.amount))))
        }
        if !d.fixedPaid.isEmpty {
            let names = d.fixedPaid.map(\.0)
            let title = names.count == 1 ? names[0]
                : L("%d Zahlungen · %s", names.count, names.prefix(2).joined(separator: ", ") + (names.count > 2 ? " …" : ""))
            out.append(AnyView(item("arrow.clockwise", Wimg.accent, L("Fixkosten bezahlt"), title,
                                    amountText(d.fixedPaid.reduce(0) { $0 + $1.1 })) { AppNav.shared.open(.recurring) }))
        }
        return out
    }

    private func item(_ icon: String, _ tint: Color, _ over: String, _ title: String, _ amount: String, action: (() -> Void)? = nil) -> some View {
        WimgRow(title: title, desc: over, chevron: action != nil, action: action) {
            IconTile(systemImage: icon, tint: tint)
        } trailing: {
            Text(amount).wimgStyle(WimgType.amountRow).foregroundStyle(Wimg.text).lineLimit(1)
        }
    }

    // MARK: Data

    private func load() async {
        let sel = selection, account = selectedAccount, salary = salaryMode
        let prev = sel.previous(in: periods.data)
        data = await Task.detached { ReviewData.load(sel, prev: prev, account: account, salaryMode: salary) }.value
        maybeOpen()
    }
}

struct ReviewData {
    var summary: MonthlySummary?
    var previous: MonthlySummary?
    var biggest: Transaction?
    var lastDate: String?
    var fixedPaid: [(String, Double)] = []
    /// Gehaltsmonat: the largest income that is not the salary.
    var otherIncome: Transaction?
    /// For the opener: days without spending (this and the range before), a price rise.
    var noSpend = 0
    var prevNoSpend: Int?
    var priceRise: PriceRise?

    nonisolated static func load(_ sel: HomeSelection, prev: HomeSelection?, account: String?, salaryMode: Bool) -> ReviewData {
        let summary = LibWimg.getSummaryRange(from: sel.from, to: sel.to, account: account)
        let previous = prev.flatMap { LibWimg.getSummaryRange(from: $0.from, to: $0.to, account: account) }
        let today = WimgDates.todayIso()
        // Up to today only: scheduled (and demo) bookings dated later don't count yet.
        let all = (try? LibWimg.getTransactionsFiltered(account: account)) ?? []
        let inRange = all
            .filter { $0.date >= sel.from && $0.date <= sel.to && !$0.isExcluded && $0.date <= today }
        let fixed = LibWimg.getRecurring()
            .filter { $0.isActive && !$0.isHidden && $0.amount < 0 && $0.last_seen >= sel.from && $0.last_seen <= sel.to }
            .map { ($0.displayName, $0.amount) }
        var other: Transaction?
        if salaryMode, case .period = sel.kind {
            other = inRange.filter { $0.amount > 0 && $0.date != sel.from }.max { $0.amount < $1.amount }
        }
        return ReviewData(
            summary: summary,
            previous: (previous?.tx_count ?? 0) > 0 ? previous : nil,
            biggest: inRange.filter { $0.amount < 0 }.min { $0.amount < $1.amount },
            lastDate: inRange.map(\.date).max(),
            fixedPaid: fixed,
            otherIncome: other,
            noSpend: ReviewOpenerCards.noSpendCount(from: sel.from, to: sel.to, txs: all),
            prevNoSpend: prev.map { ReviewOpenerCards.noSpendCount(from: $0.from, to: $0.to, txs: all) },
            priceRise: ReviewOpenerCards.priceRise(from: sel.from, to: sel.to)
        )
    }
}
