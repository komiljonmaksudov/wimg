import SwiftUI
import WimgI18n

/// Filter sheet (brief 22, boards 10–11; filters of brief 19 as on Android):
/// half height with six rows and their values; a row pushes its list in and
/// the sheet grows to full height. The button shows how many match.
struct TransactionFilterSheet: View {
    @Binding var filter: TxFilterState
    @Binding var selectedAccount: String?
    let accounts: [Account]
    let resultCount: Int
    let categoryTotals: () -> [(id: Int, sum: Double)]

    @Environment(\.dismiss) private var dismiss
    @State private var path: [Page] = []
    @State private var detent: PresentationDetent = .medium
    private var periods = PeriodState.shared

    init(filter: Binding<TxFilterState>, selectedAccount: Binding<String?>, accounts: [Account],
         resultCount: Int, categoryTotals: @escaping () -> [(id: Int, sum: Double)]) {
        _filter = filter
        _selectedAccount = selectedAccount
        self.accounts = accounts
        self.resultCount = resultCount
        self.categoryTotals = categoryTotals
    }

    enum Page: Hashable { case kind, account, period, months, category, amount, more }

    private var hasHidden: Bool { selectedAccount == nil && accounts.contains(where: \.isHidden) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                WimgGroup {
                    row("arrow.up.arrow.down", L("Art"), L(filter.kind.rawValue), .kind)
                    if accounts.count > 1 {
                        RowDivider()
                        row("wallet.bifold", L("Konto"),
                            accounts.first { $0.id == selectedAccount }?.name ?? L("Alle Konten"), .account)
                    }
                    RowDivider()
                    row("calendar", L("Zeitraum"), filter.period?.tag ?? L("Gesamt"), .period)
                    RowDivider()
                    row("tag", L("Kategorie"), categoryValue, .category)
                    RowDivider()
                    row("eurosign", L("Betrag"), filter.amount.tag ?? L("Beliebig"), .amount)
                    RowDivider()
                    row("ellipsis", L("Weitere"), moreValue, .more)
                }
                .padding(.horizontal, WimgDimens.sheetPadding)
                .padding(.top, 4)
            }
            .background(Wimg.sheet)
            .navigationTitle(L("Filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("Schließen"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L("Zurücksetzen")) {
                        filter = TxFilterState()
                        selectedAccount = nil
                    }
                    .disabled(!filter.isActive && selectedAccount == nil)
                }
            }
            .navigationDestination(for: Page.self) { page in
                pageView(page)
                    .background(Wimg.sheet)
                    .onAppear { detent = .large }
            }
        }
        .safeAreaInset(edge: .bottom) { showButton }
        .tint(Wimg.accent)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(Wimg.sheet)
        .presentationDragIndicator(.visible)
        .task { if periods.data == nil { await periods.reload() } }
    }

    private var categoryValue: String {
        switch filter.categories.count {
        case 0: L("Alle")
        case 1: L(WimgCategory.from(filter.categories.first!).name)
        default: L("%d Kategorien", filter.categories.count)
        }
    }

    private var moreValue: String {
        var m: [String] = []
        if filter.recurringOnly { m.append(L("Wiederkehrende")) }
        if filter.showHidden && hasHidden { m.append(L("Ausgeblendete")) }
        return m.isEmpty ? L("Aus") : m.joined(separator: ", ")
    }

    private func row(_ icon: String, _ title: String, _ value: String, _ page: Page) -> some View {
        WimgRow(title: title, chevron: true, action: { path.append(page) }) {
            IconTile(systemImage: icon, tint: Wimg.text2)
        } trailing: {
            Text(value).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).lineLimit(1)
        }
    }

    private var showButton: some View {
        Button { dismiss() } label: {
            Text(resultCount == 1 ? L("1 Umsatz anzeigen") : L("%d Umsätze anzeigen", resultCount))
                .wimgStyle(WimgType.button)
                .foregroundStyle(Wimg.onAccent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Wimg.accent, in: Capsule())
                .contentTransition(.numericText(value: Double(resultCount)))
                .animation(WimgMotion.out(0.2), value: resultCount)
        }
        .buttonStyle(.wimgPress)
        .padding(.horizontal, WimgDimens.sheetPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Wimg.sheet)
    }

    // MARK: Pages

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        switch page {
        case .kind:
            ChoiceList(title: L("Art")) {
                ForEach(TxKind.allCases) { k in
                    ChoiceRow(title: L(k.rawValue), on: filter.kind == k) { filter.kind = k; path.removeLast() }
                }
            }
        case .account:
            ChoiceList(title: L("Konto")) {
                ChoiceRow(title: L("Alle Konten"), on: selectedAccount == nil) { selectedAccount = nil; path.removeLast() }
                ForEach(accounts) { a in
                    ChoiceRow(title: a.name, detail: a.isHidden ? L("ausgeblendet") : nil, on: selectedAccount == a.id) {
                        selectedAccount = a.id; path.removeLast()
                    }
                }
            }
        case .period:
            ChoiceList(title: L("Zeitraum")) { periodRows }
        case .months:
            ChoiceList(title: L("Kalendermonat")) { monthRows }
        case .category:
            CategoryFilterPage(totals: categoryTotals(), selected: $filter.categories)
        case .amount:
            AmountFilterPage(amount: $filter.amount)
        case .more:
            ChoiceList(title: L("Weitere")) {
                CheckRow(title: L("Nur wiederkehrende"), desc: L("Miete, Strom, Abos"), on: $filter.recurringOnly)
                if hasHidden {
                    CheckRow(title: L("Ausgeblendete zeigen"), desc: L("Konten, die sonst nicht in Summen zählen"),
                             on: $filter.showHidden)
                }
            }
        }
    }

    /// Gesamt, the current and recent periods (Gehaltsmonat or calendar), then a calendar month.
    @ViewBuilder private var periodRows: some View {
        ChoiceRow(title: L("Gesamt"), detail: L("alle Umsätze"), on: filter.period == nil) { pick(nil) }
        let rows = periodChoices
        if let p = filter.period, !rows.contains(where: { $0.period.same(p) }) {
            ChoiceRow(title: p.label, on: true) { pick(p) }
        }
        ForEach(rows, id: \.period) { r in
            ChoiceRow(title: r.title, detail: r.detail, on: r.period.same(filter.period)) { pick(r.period) }
        }
        Button(L("Kalendermonat wählen …")) { path.append(.months) }
            .wimgStyle(WimgType.rowTitle)
            .foregroundStyle(Wimg.accent)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, 16)
    }

    private var periodChoices: [(title: String, detail: String?, period: TxPeriod)] {
        if let p = periods.data, !p.isCalendar {
            return p.periods.prefix(6).enumerated().map { i, info in
                let tp = TxPeriod.of(info, salary: p.isSalary)
                let range = info.isCurrent && p.isSalary ? L("seit %s", PeriodLabels.dotted(info.from)) : PeriodLabels.short(info)
                switch i {
                case 0: return (p.isSalary ? L("Aktueller Gehaltsmonat") : L("Aktueller Zeitraum"), range, tp)
                case 1: return (p.isSalary ? L("Letzter Gehaltsmonat") : L("Letzter Zeitraum"), range, tp)
                default: return (range, nil, tp)
                }
            }
        }
        let cal = Calendar(identifier: .gregorian), now = Date()
        let y = cal.component(.year, from: now), m = cal.component(.month, from: now)
        let last = cal.date(byAdding: .month, value: -1, to: now)!
        let thisMonth = TxPeriod.month(y, m)
        let lastMonth = TxPeriod.month(cal.component(.year, from: last), cal.component(.month, from: last))
        return [
            (L("Dieser Monat"), thisMonth.label, TxPeriod(from: thisMonth.from, to: thisMonth.to, label: L("Dieser Monat"), key: "this")),
            (L("Letzter Monat"), lastMonth.label, TxPeriod(from: lastMonth.from, to: lastMonth.to, label: L("Letzter Monat"), key: "last")),
            (L("3 Monate"), nil, .lastDays(91, label: L("3 Monate"), key: "3m")),
            (L("12 Monate"), nil, .lastDays(365, label: L("12 Monate"), key: "12m")),
        ]
    }

    /// The last 24 calendar months, newest first.
    @ViewBuilder private var monthRows: some View {
        let cal = Calendar(identifier: .gregorian)
        let months: [TxPeriod] = (0..<24).map { i in
            let d = cal.date(byAdding: .month, value: -i, to: Date())!
            return TxPeriod.month(cal.component(.year, from: d), cal.component(.month, from: d))
        }
        ForEach(months, id: \.key) { p in
            ChoiceRow(title: p.label, on: p.same(filter.period)) { pick(p) }
        }
    }

    private func pick(_ p: TxPeriod?) {
        filter.period = p
        path.removeAll()
    }
}

// MARK: - Pieces

/// A sub-page: a white group of choice rows.
private struct ChoiceList<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            WimgGroup { content() }
                .padding(.horizontal, WimgDimens.sheetPadding)
                .padding(.top, 4)
                .padding(.bottom, 80)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A row in a sub-list: the chosen one in bold with a check.
private struct ChoiceRow: View {
    let title: String
    var detail: String? = nil
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(on ? WimgFont.font(.inter, .bold, 15) : WimgType.rowTitle.font)
                    .foregroundStyle(Wimg.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail { Text(detail).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).lineLimit(1) }
                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Wimg.accent) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Square check box (board 11).
private struct CheckBox: View {
    let on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(on ? Wimg.accent : .clear)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(on ? Wimg.accent : Wimg.text3, lineWidth: 1.5))
            .overlay { if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Wimg.onAccent) } }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

private struct CheckRow: View {
    let title: String
    let desc: String
    @Binding var on: Bool

    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                    Text(desc).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
                Spacer(minLength: 8)
                CheckBox(on: on)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Kategorie (board 11): only what occurs, spending first, with a search field.
private struct CategoryFilterPage: View {
    let totals: [(id: Int, sum: Double)]
    @Binding var selected: Set<Int>
    @State private var query = ""

    private var sorted: [(id: Int, sum: Double)] {
        let spend = totals.filter { $0.sum < 0 }.sorted { $0.sum < $1.sum }
        let income = totals.filter { $0.sum >= 0 }.sorted { $0.sum > $1.sum }
        let all = spend + income
        guard !query.isEmpty else { return all }
        return all.filter { L(WimgCategory.from($0.id).name).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SearchField(text: $query, prompt: L("Kategorie suchen"))
                WimgGroup {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { RowDivider() }
                        let on = selected.contains(item.id)
                        Button {
                            if on { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            HStack(spacing: 12) {
                                CategoryTile(category: item.id)
                                Text(L(WimgCategory.from(item.id).name)).wimgStyle(WimgType.rowTitle)
                                    .foregroundStyle(Wimg.text).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(amountText(abs(item.sum), showPlus: false)).wimgStyle(WimgType.body)
                                    .foregroundStyle(Wimg.text2)
                                CheckBox(on: on)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, WimgDimens.sheetPadding)
            .padding(.top, 4)
            .padding(.bottom, 80)
        }
        .navigationTitle(L("Kategorie"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Keine")) { selected = [] }.disabled(selected.isEmpty)
            }
        }
    }
}

/// Betrag: four presets, then Von / Bis for anything else.
private struct AmountFilterPage: View {
    @Binding var amount: AmountRange
    @State private var from = ""
    @State private var to = ""

    private static func parse(_ t: String) -> Double? {
        Double(t.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")).flatMap { $0 >= 0 ? $0 : nil }
    }

    private var presets: [(String, AmountRange)] {
        [(L("Beliebig"), AmountRange()),
         (L("unter %s €", AmountRange.number(10)), AmountRange(max: 10)),
         (L("über %s €", AmountRange.number(20)), AmountRange(min: 20)),
         (L("über %s €", AmountRange.number(100)), AmountRange(min: 100))]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlowChips(presets: presets, amount: $amount) { r in
                    from = r.min.map(AmountRange.number) ?? ""
                    to = r.max.map(AmountRange.number) ?? ""
                }
                HStack(spacing: 10) {
                    field(L("Von"), $from)
                    field(L("Bis"), $to)
                }
                QuietLine(text: L("Gilt für den Betrag ohne Vorzeichen. Einen genauen Betrag findest du schneller über die Suche."))
            }
            .padding(.horizontal, WimgDimens.sheetPadding)
            .padding(.top, 4)
            .padding(.bottom, 80)
        }
        .navigationTitle(L("Betrag"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            from = amount.min.map(AmountRange.number) ?? ""
            to = amount.max.map(AmountRange.number) ?? ""
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
            HStack {
                TextField(L("beliebig"), text: text)
                    .keyboardType(.decimalPad)
                    .font(WimgType.rowTitle.font)
                    .onChange(of: text.wrappedValue) {
                        amount = AmountRange(min: Self.parse(from), max: Self.parse(to))
                    }
                Text("€").wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text2)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous)
                .stroke(text.wrappedValue.isEmpty ? Wimg.line : Wimg.accent, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FlowChips: View {
    let presets: [(String, AmountRange)]
    @Binding var amount: AmountRange
    let onPick: (AmountRange) -> Void

    var body: some View {
        ViewThatFits {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { chip(0); chip(1) }
                HStack(spacing: 8) { chip(2); chip(3) }
            }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(presets.indices, id: \.self) { chip($0) }
    }

    private func chip(_ i: Int) -> some View {
        let (label, r) = presets[i]
        let on = r == amount
        return Button { amount = r; onPick(r) } label: {
            Text(label).wimgStyle(WimgType.chip)
                .foregroundStyle(on ? Wimg.inkText : Wimg.text)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(on ? Wimg.ink : Wimg.neutralTint, in: Capsule())
        }
        .buttonStyle(.wimgPress)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Search field in a soft rounded box (boards 11, 12).
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    var focused: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Wimg.text2)
            field
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Wimg.text3) }
                    .accessibilityLabel(L("Löschen"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Wimg.neutralTint, in: RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous))
    }

    @ViewBuilder private var field: some View {
        let tf = TextField(prompt, text: $text)
            .font(WimgType.body.font)
            .foregroundStyle(Wimg.text)
            .autocorrectionDisabled()
        if let focused { tf.focused(focused) } else { tf }
    }
}
