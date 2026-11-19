import SwiftUI
import WimgI18n

/// Zeitraum sheet (brief 22, boards 13–14): how a month starts (Kalendermonat,
/// Gehaltsmonat, Fester Tag — a libwimg setting, synced), then the months or
/// periods to pick from, "Eigener Zeitraum …" and the account. Half height.
struct PeriodSheet: View {
    let selection: HomeSelection
    var allowCustom = true
    @Binding var selectedAccount: String?
    let accounts: [Account]
    let onPick: (HomeSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shownYear = Calendar(identifier: .gregorian).component(.year, from: Date())
    @State private var mode = "calendar"
    @State private var path: [Page] = []
    @State private var detent: PresentationDetent = .medium
    private var periods: PeriodState { PeriodState.shared }

    init(selection: HomeSelection, allowCustom: Bool = true, selectedAccount: Binding<String?>, accounts: [Account],
         onPick: @escaping (HomeSelection) -> Void) {
        self.selection = selection
        self.allowCustom = allowCustom
        _selectedAccount = selectedAccount
        self.accounts = accounts
        self.onPick = onPick
    }

    enum Page: Hashable { case custom, payer }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("", selection: Binding(get: { mode }, set: setMode)) {
                        Text(L("Kalendermonat")).tag("calendar")
                        Text(L("Gehaltsmonat")).tag("salary")
                        Text(L("Fester Tag")).tag("day")
                    }
                    .pickerStyle(.segmented)

                    if mode == "calendar" {
                        monthGrid
                    } else {
                        periodList
                    }

                    if allowCustom {
                        WimgGroup {
                            WimgRow(title: L("Eigener Zeitraum …"), chevron: true, action: { path.append(.custom) }) {
                                IconTile(systemImage: "calendar", tint: Wimg.text2)
                            }
                        }
                    }

                    if accounts.count > 1 {
                        WimgGroup {
                            HStack {
                                Text(L("Konto")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                                Spacer()
                                Picker(L("Konto"), selection: $selectedAccount) {
                                    Text(L("Alle Konten")).tag(String?.none)
                                    ForEach(accounts) { Text($0.name).tag(String?.some($0.id)) }
                                }
                                .pickerStyle(.menu)
                                .tint(Wimg.text)
                            }
                            .padding(.leading, 16).padding(.trailing, 6)
                            .frame(minHeight: WimgDimens.rowMinHeight)
                        }
                    }
                }
                .padding(.horizontal, WimgDimens.sheetPadding)
                .padding(.bottom, 24)
            }
            .background(Wimg.sheet)
            .navigationTitle(L("Zeitraum"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(L("Schließen"))
                }
                ToolbarItem(placement: .confirmationAction) { Button(L("Fertig")) { dismiss() } }
            }
            .navigationDestination(for: Page.self) { page in
                Group {
                    switch page {
                    case .custom: CustomRangePage(selection: selection) { onPick($0); dismiss() }
                    case .payer: PayerPage { path.removeAll() }
                    }
                }
                .background(Wimg.sheet)
                .onAppear { detent = .large }
            }
        }
        .tint(Wimg.accent)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(Wimg.sheet)
        .presentationDragIndicator(.visible)
        .onAppear {
            mode = periods.data?.chosen ?? "calendar"
            if case let .month(y, _) = selection.kind { shownYear = y }
        }
        .task { if periods.data == nil { await periods.reload(); mode = periods.data?.chosen ?? mode } }
    }

    private func setMode(_ m: String) {
        guard m != mode else { return }
        mode = m
        let day = m == "day" ? max(periods.data?.day ?? 15, 2) : 0
        Task {
            await Task.detached { try? LibWimg.setPeriodMode(m, day: day) }.value
            await periods.reload()
        }
    }

    // MARK: Kalendermonat: year + 4 × 3 grid

    private var monthGrid: some View {
        let cal = Calendar(identifier: .gregorian), now = Date()
        let curY = cal.component(.year, from: now), curM = cal.component(.month, from: now)
        return VStack(spacing: 10) {
            HStack {
                Button { shownYear -= 1 } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(L("Vorheriges Jahr"))
                Spacer()
                Text(String(shownYear)).wimgStyle(WimgType.button).foregroundStyle(Wimg.text)
                Spacer()
                Button { shownYear += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(shownYear >= curY)
                    .accessibilityLabel(L("Nächstes Jahr"))
            }
            .foregroundStyle(Wimg.text2)
            .padding(.horizontal, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(1...12, id: \.self) { m in
                    let future = shownYear > curY || (shownYear == curY && m > curM)
                    let on: Bool = { if case let .month(y, mm) = selection.kind { return y == shownYear && mm == m }; return false }()
                    Button { onPick(.month(shownYear, m)); dismiss() } label: {
                        Text(WimgDates.shortMonths()[m - 1])
                            .wimgStyle(WimgType.chip)
                            .foregroundStyle(on ? Wimg.onAccent : (future ? Wimg.text3 : Wimg.text))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(on ? Wimg.accent : (future ? .clear : Wimg.card),
                                        in: RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous)
                                .stroke(on ? .clear : Wimg.line, style: StrokeStyle(lineWidth: 1, dash: future ? [4, 3] : [])))
                    }
                    .buttonStyle(.wimgPress)
                    .disabled(future)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Gehaltsmonat / Fester Tag

    @ViewBuilder private var periodList: some View {
        if let p = periods.data {
            if mode == "salary" && !p.isSalary {
                QuietLine(text: L("Gehalt noch nicht erkannt: wimg braucht zwei Gehälter vom selben Absender. Bis dahin zählt es nach Kalendermonat."))
            }
            if mode == "salary", p.isSalary, let sal = p.salary {
                salaryCard(sal)
            }
            if mode == "day" { dayStepper(p) }
            if !p.isCalendar {
                WimgGroup {
                    ForEach(Array(p.periods.prefix(6).enumerated()), id: \.element) { i, info in
                        if i > 0 { RowDivider() }
                        periodRow(info, salary: p.isSalary)
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func periodRow(_ info: PeriodInfo, salary: Bool) -> some View {
        let on: Bool = { if case let .period(p) = selection.kind { return p.from == info.from }; return false }()
        let sel = HomeSelection.period(info)
        let sub: String = {
            if info.isCurrent { return L("läuft · noch %d Tage", sel.daysLeft) }
            if salary, let s = info.salary { return L("Gehalt %s", amountText(s, showPlus: false)) }
            return info.days == 1 ? L("1 Tag") : L("%d Tage", info.days)
        }()
        return Button { onPick(sel); dismiss() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(PeriodLabels.dotted(info.from)) – \(PeriodLabels.dotted(info.to))")
                        .wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                    Text(sub).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
                Spacer()
                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Wimg.accent) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func salaryCard(_ sal: SalaryInfo) -> some View {
        WimgGroup {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Erkanntes Gehalt")).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                    Text("\(sal.name) · \(amountText(sal.amount ?? 0, showPlus: false))")
                        .wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(2)
                    Text(L("meist um den %d. · %d× gesehen", sal.day ?? 1, sal.count ?? 0))
                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
                Spacer(minLength: 0)
                Button(L("Ändern")) { path.append(.payer) }
                    .wimgStyle(WimgType.chip)
                    .foregroundStyle(Wimg.text)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .overlay(RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous).stroke(Wimg.line, lineWidth: 1))
            }
            .padding(16)
        }
    }

    private func dayStepper(_ p: Periods) -> some View {
        WimgGroup {
            Stepper(value: Binding(get: { p.day }, set: { d in
                Task {
                    await Task.detached { try? LibWimg.setPeriodMode("day", day: d) }.value
                    await periods.reload()
                }
            }), in: 1...28) {
                HStack {
                    Text(L("Monat beginnt am")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                    Spacer()
                    Text("\(p.day).").wimgStyle(WimgType.button).foregroundStyle(Wimg.text)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: WimgDimens.rowMinHeight)
        }
    }
}

/// "Eigener Zeitraum …": from / to, never after today.
private struct CustomRangePage: View {
    let selection: HomeSelection
    let onPick: (HomeSelection) -> Void
    @State private var from = Date()
    @State private var to = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WimgGroup {
                    DatePicker(L("Von"), selection: $from, in: ...to, displayedComponents: .date)
                        .padding(.horizontal, 16).frame(minHeight: WimgDimens.rowMinHeight)
                    RowDivider()
                    DatePicker(L("Bis"), selection: $to, in: from...Date(), displayedComponents: .date)
                        .padding(.horizontal, 16).frame(minHeight: WimgDimens.rowMinHeight)
                }
                .wimgStyle(WimgType.body)
                .foregroundStyle(Wimg.text)
                .environment(\.locale, Locale(identifier: UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE"))
                Button { onPick(.custom(WimgDates.iso(from), WimgDates.iso(to))) } label: {
                    Text(L("Anwenden")).wimgStyle(WimgType.button).foregroundStyle(Wimg.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52).background(Wimg.accent, in: Capsule())
                }
                .buttonStyle(.wimgPress)
            }
            .padding(WimgDimens.sheetPadding)
        }
        .navigationTitle(L("Eigener Zeitraum"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            from = WimgDates.parse(selection.from) ?? Date()
            to = min(WimgDates.parse(selection.to) ?? Date(), Date())
        }
    }
}

/// "Welche Einnahme ist dein Gehalt?": incomes of the last months.
private struct PayerPage: View {
    let onDone: () -> Void
    private var periods: PeriodState { PeriodState.shared }

    var body: some View {
        ScrollView {
            if let p = periods.data {
                if p.payers.isEmpty {
                    QuietLine(text: L("Noch keine Einnahmen in den letzten Monaten.")).padding(WimgDimens.sheetPadding)
                }
                WimgGroup {
                    ForEach(Array(p.payers.enumerated()), id: \.element.key) { i, payer in
                        if i > 0 { RowDivider() }
                        let on = p.salary?.key == payer.key && (p.salary?.confirmed ?? false)
                        WimgRow(title: payer.title ?? payer.key,
                                desc: L("%s · %d× seit %s", amountText(payer.amount ?? 0, showPlus: false), payer.count ?? 0, PeriodLabels.dotted(payer.last ?? "")),
                                action: { pick(payer.key) }) {
                            Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(on ? Wimg.accent : Wimg.text3)
                        }
                    }
                }
                .padding(WimgDimens.sheetPadding)
            }
        }
        .navigationTitle(L("Welche Einnahme ist dein Gehalt?"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pick(_ key: String) {
        Task {
            await Task.detached {
                try? LibWimg.answerSalary(key: key, .onlyThisPayer)
                try? LibWimg.setPeriodMode("salary")
            }.value
            await periods.reload()
            Changes.bump()
            onDone()
        }
    }
}
