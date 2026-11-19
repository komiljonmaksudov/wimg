import SwiftUI
import WimgI18n

/// libwimg interval ids in display order, with label and per-month factor.
let recurringIntervals: [(id: String, label: String, perMonth: Double)] = [
    ("weekly", "Wöchentlich", 52.0 / 12.0),
    ("monthly", "Monatlich", 1),
    ("quarterly", "Vierteljährlich", 1.0 / 3.0),
    ("annual", "Jährlich", 1.0 / 12.0),
]

func monthlyFactor(_ interval: String) -> Double {
    recurringIntervals.first { $0.id == interval }?.perMonth ?? 1
}

func intervalLabel(_ interval: String) -> String {
    recurringIntervals.first { $0.id == interval }?.label ?? interval
}

/// Days from today to an ISO date (negative = past).
func daysUntil(_ iso: String) -> Int? {
    guard let d = WimgDates.parse(iso), let t = WimgDates.parse(WimgDates.todayIso()) else { return nil }
    return Calendar(identifier: .gregorian).dateComponents([.day], from: t, to: d).day
}

/// Wiederkehrend (Android RecurringScreen.kt): fixed costs per month in the
/// band, paid vs. still open, the payments grouped by rhythm. Filter sheet
/// with what to show, the hidden ones and "Erneut erkennen".
struct RecurringView: View {
    @State private var patterns: [RecurringPattern]?
    @State private var showFilter = false
    @State private var showExpenses = true
    @State private var showIncome = true
    @State private var showInactive = false
    @State private var interval: String?
    @State private var detecting = false
    /// "12 Monate": paid per month this year and the forecast for the rest.
    @State private var yearView = false
    @State private var payments: [String: [RecurringPayment]] = [:]
    @State private var pickedMonth = Calendar(identifier: .gregorian).component(.month, from: Date())
    private var periods: PeriodState { PeriodState.shared }

    private var period: PeriodInfo? { periods.data.flatMap { $0.isCalendar ? nil : $0.current } }
    private var range: (String, String) {
        if let p = period { return (p.from, p.to) }
        let m = HomeSelection.thisMonth
        return (m.from, m.to)
    }

    private var all: [RecurringPattern] { (patterns ?? []).filter { !$0.isHidden } }
    private var hidden: [RecurringPattern] { (patterns ?? []).filter(\.isHidden) }
    private var expenses: [RecurringPattern] { all.filter { $0.isActive && $0.amount < 0 } }

    private func inRange(_ d: String?) -> Bool { guard let d else { return false }; return d >= range.0 && d <= range.1 }

    var body: some View {
        let perMonth = expenses.reduce(0) { $0 + abs($1.amount) * monthlyFactor($1.interval) }
        let due = expenses.filter { inRange($0.last_seen) || inRange($0.next_due) || $0.interval == "monthly" }
        let paid = due.filter { inRange($0.last_seen) }.reduce(0) { $0 + abs($1.amount) }
        let open = due.filter { !inRange($0.last_seen) }.reduce(0) { $0 + abs($1.amount) }
        let filterActive = !showExpenses || !showIncome || showInactive || interval != nil

        BandScreen(title: L("Wiederkehrend")) {
            BandButton(systemImage: "slider.horizontal.3", label: L("Ansicht und Filter"), badge: filterActive ? 1 : 0) { showFilter = true }
        } band: {
            BandOver(text: periods.data?.isSalary == true ? L("Fixkosten pro Gehaltsmonat") : L("Fixkosten pro Monat"))
                .padding(.top, 10)
            Amount(euros: perMonth, style: WimgType.amountHero, centsStyle: WimgType.amountHeroCents,
                   color: .white, showPlus: false, rolls: true)
                .padding(.top, 2)
            Text(expenses.count == 1 ? L("1 feste Zahlung erkannt") : L("%d feste Zahlungen erkannt", expenses.count))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).padding(.top, 4)
            if paid + open > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(.white).frame(width: g.size.width * paid / (paid + open))
                    }
                }
                .frame(height: 6)
                .padding(.top, 18)
                .accessibilityHidden(true)
                HStack(alignment: .top) {
                    figure(paidLabel, amountText(paid, showPlus: false))
                    Spacer()
                    figure(periods.data?.isSalary == true ? L("Bis zum Gehalt offen") : L("Noch offen"), amountText(open, showPlus: false), end: true)
                }
                .padding(.top, 8)
            }
        } sheet: {
            if yearView {
                RecurringYearView(expenses: expenses, payments: payments, picked: $pickedMonth)
            } else {
                list
            }
        }
        .navigationDestination(for: RecRoute.self) { RecurringDetailView(id: $0.id) }
        .sheet(isPresented: $showFilter) {
            RecurringFilterSheet(all: all, hidden: hidden, showExpenses: $showExpenses, showIncome: $showIncome,
                                 showInactive: $showInactive, interval: $interval, detecting: $detecting, yearView: $yearView)
        }
        .task { await load() }
        .task(id: yearView) { if yearView { await loadPayments() } }
        .task { if periods.data == nil { await periods.reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in Task { await load() } }
    }

    private var paidLabel: String {
        if periods.data?.isSalary == true { return L("Seit dem Gehalt bezahlt") }
        if period != nil { return L("Bezahlt seit dem %d.", periods.data?.day ?? 1) }
        let m = Calendar(identifier: .gregorian).component(.month, from: Date())
        return L("Bezahlt im %s.", WimgDates.shortMonths()[m - 1])
    }

    private func figure(_ label: String, _ value: String, end: Bool = false) -> some View {
        VStack(alignment: end ? .trailing : .leading, spacing: 2) {
            Text(label).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).lineLimit(1)
            Text(value).wimgStyle(WimgType.amountStat).foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var list: some View {
        let shown = all.filter { p in
            (showInactive || p.isActive) && ((p.amount < 0 && showExpenses) || (p.amount > 0 && showIncome))
                && (interval == nil || p.interval == interval)
        }
        if patterns != nil && shown.isEmpty {
            VStack(spacing: 6) {
                Text(all.isEmpty ? L("Noch keine festen Zahlungen") : L("Keine Treffer"))
                    .wimgStyle(WimgType.section).foregroundStyle(Wimg.text)
                Text(all.isEmpty ? L("wimg erkennt Miete, Strom und Abos, sobald ein paar Monate Umsätze da sind.") : L("Ändere den Filter, um mehr zu sehen."))
                    .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).multilineTextAlignment(.center)
                if all.isEmpty {
                    Button(detecting ? L("Suche Muster…") : L("Jetzt erkennen")) { detect() }
                        .wimgStyle(WimgType.button).foregroundStyle(Wimg.inkText)
                        .padding(.horizontal, 22).padding(.vertical, 13)
                        .background(Wimg.ink, in: Capsule())
                        .padding(.top, 12)
                        .disabled(detecting)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        if let p = period {
            Text(PeriodLabels.short(p)).wimgStyle(WimgType.chip).foregroundStyle(Wimg.text2).padding(.horizontal, 4)
        }
        ForEach(sections(shown), id: \.title) { section in
            let total = section.items.reduce(0) { $0 + $1.amount }
            GroupLabel(text: section.title, trailing: amountText(total > 0 ? total : abs(total), showPlus: total > 0))
            WimgGroup {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { RowDivider() }
                    PatternRow(p: p, paidNow: inRange(p.last_seen), due: dueDate(p))
                }
            }
        }
    }

    private func dueDate(_ p: RecurringPattern) -> String? {
        if inRange(p.last_seen) { return p.last_seen }
        if inRange(p.next_due) { return p.next_due }
        return nil
    }

    private func sections(_ shown: [RecurringPattern]) -> [(title: String, items: [RecurringPattern])] {
        var out: [(String, [RecurringPattern])] = []
        for iv in recurringIntervals {
            let items = shown.filter { $0.amount < 0 && $0.interval == iv.id }
                .sorted { (dueDate($0) ?? "9", $0.displayName) < (dueDate($1) ?? "9", $1.displayName) }
            if !items.isEmpty { out.append((L(iv.label), items)) }
        }
        let income = shown.filter { $0.amount > 0 }
        if !income.isEmpty { out.append((L("Einnahmen"), income)) }
        return out
    }

    private func load() async {
        patterns = await Task.detached { () -> [RecurringPattern] in
            var list = LibWimg.getRecurring()
            // Patterns from older libwimg builds can have next_due before last_seen: detect again.
            if list.contains(where: { ($0.next_due ?? "9") < $0.last_seen }) {
                LibWimg.detectRecurring()
                list = LibWimg.getRecurring()
            }
            return list
        }.value
    }

    /// Each fixed cost's real payments, for the 12-month view.
    private func loadPayments() async {
        let ids = expenses.map(\.id)
        payments = await Task.detached {
            Dictionary(uniqueKeysWithValues: ids.map { ($0, LibWimg.getRecurringPayments(id: $0).filter { !$0.isOneoff }) })
        }.value
    }

    private func detect() {
        detecting = true
        Task {
            await Task.detached { LibWimg.detectRecurring() }.value
            detecting = false
            Changes.bump()
        }
    }
}

/// One fixed payment: day of this period's payment, name, state, amount, paid/open.
private struct PatternRow: View {
    let p: RecurringPattern
    let paidNow: Bool
    let due: String?

    private var sub: String {
        let income = p.amount > 0
        if !p.isActive { return L("inaktiv · zuletzt %s", WimgDates.short(p.last_seen)) }
        // Compare what was actually paid, only while libwimg reports a change.
        let paid = p.detected_amount ?? p.amount
        if !income, p.price_change != nil, let prev = p.prev_amount {
            if abs(paid) - abs(prev) > 0.5 { return L("Preis gestiegen · vorher %s", amountText(abs(prev), showPlus: false)) }
            if abs(prev) - abs(paid) > 0.5 { return L("Preis gesunken · vorher %s", amountText(abs(prev), showPlus: false)) }
        }
        let label = L(intervalLabel(p.interval))
        guard let next = p.next_due.flatMap(daysUntil) else { return label }
        if income && !paidNow && next >= 0 { return L("%s · erwartet in %d Tagen", label, next) }
        if next > 0 && paidNow { return L("%s · nächste in %d Tagen", label, next) }
        if next > 0 { return L("%s · in %d Tagen", label, next) }
        if next == 0 { return L("%s · heute fällig", label) }
        if !paidNow, let d = p.next_due { return L("%s · überfällig seit %s", label, WimgDates.short(d)) }
        return label
    }

    var body: some View {
        let income = p.amount > 0
        let parts = due?.split(separator: "-").compactMap { Int($0) } ?? []
        NavigationLink(value: RecRoute(id: p.id)) {
            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    if parts.count == 3 {
                        Text("\(parts[2]).").wimgStyle(WimgType.amountRow).foregroundStyle(p.isActive ? Wimg.text : Wimg.text3)
                        Text(WimgDates.shortMonths()[parts[1] - 1]).wimgStyle(WimgType.caption).foregroundStyle(Wimg.text2)
                    } else {
                        Text("–").wimgStyle(WimgType.amountRow).foregroundStyle(Wimg.text3)
                    }
                }
                .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName).wimgStyle(WimgType.rowTitle).foregroundStyle(p.isActive ? Wimg.text : Wimg.text3).lineLimit(1)
                    Text(sub).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Amount(euros: income ? p.amount : abs(p.amount),
                       color: !p.isActive ? Wimg.text3 : (income ? Wimg.pos : Wimg.text), showPlus: income)
                StatusDot(paid: paidNow, income: income)
            }
            .padding(.leading, 8).padding(.trailing, 16).padding(.vertical, 10)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Paid (filled check) or still open (dashed ring).
struct StatusDot: View {
    let paid: Bool
    var income = false

    var body: some View {
        Group {
            if paid {
                Circle().fill(income ? Wimg.pos : Wimg.ink)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Wimg.inkText))
            } else {
                Circle().stroke(Wimg.text3, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityLabel(paid ? L("bezahlt") : L("offen"))
    }
}

/// Ansicht und Filter: what to show, the interval, the hidden ones, "Erneut erkennen".
private struct RecurringFilterSheet: View {
    let all: [RecurringPattern]
    let hidden: [RecurringPattern]
    @Binding var showExpenses: Bool
    @Binding var showIncome: Bool
    @Binding var showInactive: Bool
    @Binding var interval: String?
    @Binding var detecting: Bool
    @Binding var yearView: Bool
    @State private var hiddenTab = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !hidden.isEmpty {
                        Picker("", selection: $hiddenTab) {
                            Text(L("Aktiv (%d)", all.count)).tag(false)
                            Text(L("Ausgeblendet (%d)", hidden.count)).tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    if hiddenTab && !hidden.isEmpty {
                        WimgGroup {
                            ForEach(Array(hidden.enumerated()), id: \.element.id) { i, h in
                                if i > 0 { RowDivider() }
                                WimgRow(title: h.displayName,
                                        desc: L(intervalLabel(h.interval)) + " · " + amountText(abs(h.amount), showPlus: false)) {
                                    EmptyView()
                                } trailing: {
                                    Button(L("Wieder anzeigen")) {
                                        try? LibWimg.setRecurringHidden(id: h.id, hidden: false)
                                        Changes.bump()
                                        if hidden.count == 1 { hiddenTab = false }
                                    }
                                    .wimgStyle(WimgType.chip).foregroundStyle(Wimg.text)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(Wimg.neutralTint, in: Capsule())
                                }
                            }
                        }
                        QuietLine(text: L("Ausgeblendete Muster erkennt wimg nicht neu. Wieder anzeigen holt sie mit allen Zahlungen zurück."))
                    } else {
                        GroupLabel(text: L("Ansicht"))
                        Picker("", selection: $yearView) {
                            Text(L("Liste")).tag(false)
                            Text(L("12 Monate")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        GroupLabel(text: L("Zeigen"))
                        HStack(spacing: 8) {
                            chip(L("Ausgaben"), showExpenses) { showExpenses.toggle() }
                            chip(L("Einnahmen"), showIncome) { showIncome.toggle() }
                            chip(L("Inaktive"), showInactive) { showInactive.toggle() }
                        }
                        GroupLabel(text: L("Intervall"))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip(L("Alle"), interval == nil, check: false) { interval = nil }
                                ForEach(recurringIntervals.filter { iv in all.contains { $0.interval == iv.id } }, id: \.id) { iv in
                                    chip(L(iv.label), interval == iv.id, check: false) { interval = interval == iv.id ? nil : iv.id }
                                }
                            }
                        }
                        Button {
                            detecting = true
                            Task {
                                let n = await Task.detached { LibWimg.detectRecurring() }.value
                                detecting = false
                                Changes.bump()
                                dismiss()
                                Dock.shared.info(L("Erneut erkannt"), sub: L("%d feste Zahlungen", n))
                            }
                        } label: {
                            Label(detecting ? L("Suche Muster…") : L("Erneut erkennen"), systemImage: "arrow.clockwise")
                                .wimgStyle(WimgType.button).foregroundStyle(Wimg.text)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .overlay(Capsule().stroke(Wimg.line, lineWidth: 1))
                        }
                        .buttonStyle(.wimgPress)
                        .disabled(detecting)
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, WimgDimens.sheetPadding)
                .padding(.bottom, 24)
            }
            .background(Wimg.sheet)
            .navigationTitle(L("Ansicht"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Fertig")) { dismiss() } }
            }
        }
        .tint(Wimg.accent)
        .presentationDetents([.medium, .large])
        .presentationBackground(Wimg.sheet)
        .presentationDragIndicator(.visible)
    }

    private func chip(_ label: String, _ on: Bool, check: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if on && check { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                Text(label).wimgStyle(WimgType.rowTitle)
            }
            .foregroundStyle(on ? Wimg.inkText : Wimg.text)
            .padding(.horizontal, 16).frame(height: 40)
            .background(on ? Wimg.ink : .clear, in: Capsule())
            .overlay(Capsule().stroke(on ? Wimg.ink : Wimg.line, lineWidth: 1))
        }
        .buttonStyle(.wimgPress)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Whether a pattern falls due in a month (from its next due date and interval).
private func dueInMonth(_ p: RecurringPattern, year: Int, month: Int) -> Bool {
    guard let next = p.next_due, let d = WimgDates.parse(next) else { return p.interval == "monthly" || p.interval == "weekly" }
    let cal = Calendar(identifier: .gregorian)
    let diff = (year - cal.component(.year, from: d)) * 12 + (month - cal.component(.month, from: d))
    if diff < 0 { return false }
    switch p.interval {
    case "quarterly": return diff % 3 == 0
    case "annual": return diff % 12 == 0
    default: return true
    }
}

/// "12 Monate" (as Android's YearView): what was paid per month this year,
/// the forecast for the months still to come (greyed), a month's payments below.
private struct RecurringYearView: View {
    let expenses: [RecurringPattern]
    let payments: [String: [RecurringPayment]]
    @Binding var picked: Int

    private let cal = Calendar(identifier: .gregorian)
    private var year: Int { cal.component(.year, from: Date()) }
    private var current: Int { cal.component(.month, from: Date()) }
    private func prefix(_ m: Int) -> String { String(format: "%04d-%02d", year, m) }

    private func paidIn(_ m: Int) -> [(p: RecurringPattern, pay: RecurringPayment)] {
        expenses.flatMap { p in (payments[p.id] ?? []).filter { $0.date.hasPrefix(prefix(m)) }.map { (p, $0) } }
    }

    private func expectedIn(_ m: Int) -> [RecurringPattern] {
        expenses.filter { p in
            p.isActive && dueInMonth(p, year: year, month: m)
                && (m > current || !(payments[p.id] ?? []).contains { $0.date.hasPrefix(prefix(m)) })
        }
    }

    private func sum(_ m: Int) -> Double {
        m > current ? expectedIn(m).reduce(0) { $0 + abs($1.amount) } : paidIn(m).reduce(0) { $0 + abs($1.pay.amount) }
    }

    var body: some View {
        let names = WimgDates.shortMonths()
        let paidTotal = (1...current).reduce(0) { $0 + paidIn($1).reduce(0) { $0 + abs($1.pay.amount) } }
        let expectedTotal = (current...12).reduce(0) { $0 + expectedIn($1).reduce(0) { $0 + abs($1.amount) } }
        HStack(alignment: .lastTextBaseline) {
            Text(verbatim: "\(year)").wimgStyle(WimgType.section).foregroundStyle(Wimg.text)
            Spacer()
            Text(L("%s bezahlt · %s erwartet", amountText(paidTotal, showPlus: false), amountText(expectedTotal, showPlus: false)))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { col in
                        let m = row * 3 + col
                        let future = m > current
                        let sel = m == picked
                        let total = sum(m)
                        Button { picked = m } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(names[m - 1]).wimgStyle(WimgType.desc).foregroundStyle(sel ? Wimg.inkText : Wimg.text2)
                                Text(total > 0.004 ? amountText(total, showPlus: false) : "–")
                                    .wimgStyle(WimgType.amountRow).lineLimit(1).minimumScaleFactor(0.7)
                                    .foregroundStyle(sel ? Wimg.inkText : future ? Wimg.text3 : Wimg.text)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 12)
                            .background(sel ? Wimg.ink : future ? Color.clear : Wimg.card,
                                        in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous)
                                .stroke(sel ? .clear : Wimg.line, style: StrokeStyle(lineWidth: 1, dash: future ? [4, 3] : [])))
                        }
                        .buttonStyle(.wimgPress)
                        .accessibilityAddTraits(sel ? .isSelected : [])
                    }
                }
            }
        }
        let paid = paidIn(picked).sorted { $0.pay.date < $1.pay.date }
        let expected = picked >= current ? expectedIn(picked) : []
        let monthTotal = paid.reduce(0) { $0 + abs($1.pay.amount) } + expected.reduce(0) { $0 + abs($1.amount) }
        GroupLabel(text: WimgDates.months()[picked - 1], trailing: amountText(monthTotal, showPlus: false))
        if !paid.isEmpty || !expected.isEmpty {
            WimgGroup {
                ForEach(Array(paid.enumerated()), id: \.element.pay.id) { i, item in
                    if i > 0 { RowDivider() }
                    row(day: Int(item.pay.date.suffix(2)), name: item.p.displayName,
                        sub: L("%s · bezahlt", L(intervalLabel(item.p.interval))), amount: abs(item.pay.amount), future: false, id: item.p.id)
                }
                ForEach(Array(expected.enumerated()), id: \.element.id) { i, p in
                    if i > 0 || !paid.isEmpty { RowDivider() }
                    row(day: p.next_due.flatMap { Int($0.suffix(2)) }, name: p.displayName,
                        sub: L("%s · erwartet", L(intervalLabel(p.interval))), amount: abs(p.amount), future: true, id: p.id)
                }
            }
        }
    }

    private func row(day: Int?, name: String, sub: String, amount: Double, future: Bool, id: String) -> some View {
        NavigationLink(value: RecRoute(id: id)) {
            HStack(spacing: 12) {
                Text(day.map { "\($0)." } ?? "–").wimgStyle(WimgType.amountRow)
                    .foregroundStyle(future ? Wimg.text3 : Wimg.text).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(1)
                    Text(sub).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(amountText(amount, showPlus: false)).wimgStyle(WimgType.amountRow)
                    .foregroundStyle(future ? Wimg.text2 : Wimg.text)
            }
            .padding(.horizontal, 16).frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
