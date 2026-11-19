import SwiftUI
import WimgI18n

/// One fixed payment (Android RecurringDetailScreen.kt, board 26): amount and
/// rhythm in the band, a price-change card with "Einmalige Zahlung" / "Stimmt,
/// neuer Preis", next / per year / so far, the payments. Edit and "Nicht
/// wiederkehrend" are round buttons in the band.
struct RecurringDetailView: View {
    let id: String

    @State private var pattern: RecurringPattern?
    @State private var payments: [RecurringPayment] = []
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let p = pattern { page(p) } else {
                BandScreen(title: L("Wiederkehrend"), pushed: true) { EmptyView() } sheet: { EmptyView() }
            }
        }
        .task(id: id) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in Task { await load() } }
    }

    private func page(_ p: RecurringPattern) -> some View {
        let income = p.amount > 0
        let amount = abs(p.amount)
        let day = Int(p.last_seen.suffix(2))
        // Price change from the payments that count: newest vs. the one before,
        // unless the user already said "Stimmt, neuer Preis".
        let counted = payments.filter { !$0.isOneoff }
        let newestPay = counted.first
        let newest = newestPay.map { abs($0.amount) }
        let before = counted.count > 1 ? abs(counted[1].amount) : nil
        let changed: Bool = {
            guard let n = newest, let b = before else { return false }
            return abs(n - b) > 0.004 && p.price_change != nil
        }()

        return BandScreen(title: p.displayName, pushed: true) {
            BandButton(systemImage: "pencil", label: L("Bearbeiten")) { showEdit = true }
            Menu {
                Button(role: .destructive) { hide(p) } label: { Label(L("Nicht wiederkehrend"), systemImage: "nosign") }
            } label: { BandIcon(systemImage: "ellipsis") }
                .accessibilityLabel(L("Mehr"))
        } band: {
            BandOver(text: [L(intervalLabel(p.interval)), day.map { L("am %d.", $0) }].compactMap { $0 }.joined(separator: " · "))
            Amount(euros: amount, style: WimgType.amountHero, centsStyle: WimgType.amountHeroCents,
                   color: income ? Wimg.bandPos : .white, showPlus: income)
                .padding(.top, 2)
        } sheet: {
            if changed && !income, let n = newest, let b = before, let pay = newestPay {
                priceCard(p, newest: n, before: b, pay: pay)
                Spacer().frame(height: 16)
            }
            HStack(alignment: .top, spacing: 10) {
                stat(L("Nächste"), p.next_due.map { WimgDates.short($0) } ?? "–", p.next_due.flatMap(daysUntil).map { d in
                    d > 1 ? L("in %d Tagen", d) : d == 1 ? L("morgen") : d == 0 ? L("heute") : L("überfällig")
                })
                stat(L("Pro Jahr"), amountText(amount * 12 * monthlyFactor(p.interval), showPlus: false), nil)
                stat(L("Bisher"), amountText(counted.reduce(0) { $0 + abs($1.amount) }, showPlus: false),
                     counted.count == 1 ? L("1 Zahlung") : L("%d Zahlungen", counted.count))
            }
            GroupLabel(text: L("Verlauf"))
            WimgGroup {
                ForEach(Array(payments.enumerated()), id: \.element.id) { i, pay in
                    if i > 0 { RowDivider() }
                    paymentRow(p, pay, counted: counted, changed: changed, income: income)
                }
            }
        }
        .sheet(isPresented: $showEdit) { EditRecurringSheet(p: p) }
    }

    private func priceCard(_ p: RecurringPattern, newest: Double, before: Double, pay: RecurringPayment) -> some View {
        let up = newest > before
        let perMonth = (newest - before) * monthlyFactor(p.interval)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: up ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                    .font(.system(size: 20)).foregroundStyle(up ? Wimg.warn : Wimg.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(up ? "Preis gestiegen: %s → %s" : "Preis gesunken: %s → %s",
                           amountText(before, showPlus: false), amountText(newest, showPlus: false)))
                        .wimgStyle(WimgType.chip).foregroundStyle(Wimg.text)
                    Text(L("%s im Monat · %s im Jahr", amountText(perMonth), amountText(perMonth * 12)))
                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
            }
            // A jump that may be a one-off invoice, decided right here (board 26/18).
            Button {
                try? LibWimg.setRecurringOneoff(patternId: p.id, txId: pay.id, oneoff: true)
                try? LibWimg.acceptRecurringPrice(id: p.id)
                Changes.bump()
                Dock.shared.undo(L("%s einmalig", amountText(abs(pay.amount), showPlus: false)),
                                 sub: L("Preis bleibt %s", amountText(before, showPlus: false))) {
                    try? LibWimg.setRecurringOneoff(patternId: p.id, txId: pay.id, oneoff: false)
                    Changes.bump()
                }
            } label: {
                Text(L("Einmalige Zahlung, kein neuer Preis")).wimgStyle(WimgType.button).foregroundStyle(Wimg.inkText)
                    .frame(maxWidth: .infinity, minHeight: 48).background(Wimg.ink, in: Capsule())
            }
            .buttonStyle(.wimgPress)
            Button {
                try? LibWimg.acceptRecurringPrice(id: p.id)
                Changes.bump()
                Dock.shared.info(L("Neuer Preis übernommen"), sub: amountText(newest, showPlus: false))
            } label: {
                Text(L("Stimmt, neuer Preis")).wimgStyle(WimgType.button).foregroundStyle(Wimg.text)
                    .frame(maxWidth: .infinity, minHeight: 48).overlay(Capsule().stroke(Wimg.line, lineWidth: 1))
            }
            .buttonStyle(.wimgPress)
        }
        .padding(16)
        .background(up ? Wimg.warnBg : Wimg.accentSoft, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
    }

    private func stat(_ label: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
            Text(value).font(WimgFont.font(.manrope, .heavy, 16)).foregroundStyle(Wimg.text).lineLimit(1).minimumScaleFactor(0.7)
            if let sub { Text(sub).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func paymentRow(_ p: RecurringPattern, _ pay: RecurringPayment, counted: [RecurringPayment], changed: Bool, income: Bool) -> some View {
        let ci = counted.firstIndex { $0.id == pay.id }
        let older = ci.flatMap { $0 + 1 < counted.count ? counted[$0 + 1] : nil }
        let note: String? = {
            if pay.isOneoff { return L("Einzelzahlung · zählt hier nicht") }
            guard let o = older, abs(abs(pay.amount) - abs(o.amount)) >= 0.005 else { return nil }
            return ci == 0 ? (changed ? L("neuer Preis?") : L("neuer Preis")) : L("Preis geändert")
        }()
        return Button {
            // A one-off can be taken back: "zählt doch dazu".
            guard pay.isOneoff else { return }
            Dock.shared.show(DockRow(kind: .prompt, title: L("Gehört diese Zahlung dazu?"), sub: amountText(pay.amount),
                                     action: L("Ja, zählt dazu"), onAction: {
                try? LibWimg.setRecurringOneoff(patternId: p.id, txId: pay.id, oneoff: false)
                Changes.bump()
            }))
        } label: {
            HStack(spacing: 14) {
                if pay.isOneoff {
                    Circle().stroke(Wimg.text3, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])).frame(width: 26, height: 26)
                } else {
                    StatusDot(paid: true, income: income)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(WimgDates.full(pay.date)).wimgStyle(WimgType.body).foregroundStyle(pay.isOneoff ? Wimg.text2 : Wimg.text)
                    if let note { Text(note).wimgStyle(WimgType.desc).foregroundStyle(pay.isOneoff ? Wimg.text2 : Wimg.warn) }
                }
                Spacer()
                Text(amountText(pay.amount)).wimgStyle(WimgType.amountRow)
                    .strikethrough(pay.isOneoff)
                    .foregroundStyle(pay.isOneoff ? Wimg.text2 : (income ? Wimg.pos : Wimg.text))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        let id = id
        let (p, list) = await Task.detached { (LibWimg.getRecurring().first { $0.id == id }, LibWimg.getRecurringPayments(id: id)) }.value
        pattern = p
        payments = list
    }

    /// No confirmation (board 26/13): back to the list, undo in the Dock.
    private func hide(_ p: RecurringPattern) {
        try? LibWimg.setRecurringHidden(id: p.id, hidden: true)
        Changes.bump()
        dismiss()
        Dock.shared.undo(L("Nicht mehr wiederkehrend"), sub: p.displayName) {
            try? LibWimg.setRecurringHidden(id: p.id, hidden: false)
            Changes.bump()
        }
    }
}

/// Bearbeiten (board 26/15–16): name, category, rhythm, automatic or fixed amount.
private struct EditRecurringSheet: View {
    let p: RecurringPattern
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = 0
    @State private var interval = "monthly"
    @State private var fixed = false
    @State private var fixedText = ""
    @State private var path: [String] = []

    private static let rhythms = [("weekly", "Wöch."), ("monthly", "Monatl."), ("quarterly", "Viertelj."), ("annual", "Jährl.")]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("erkannt als „%s“", p.merchant)).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                    WimgGroup {
                        HStack(spacing: 16) {
                            Text(L("Name")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                            TextField(p.merchant, text: $name).multilineTextAlignment(.trailing)
                                .font(WimgType.rowTitle.font).foregroundStyle(Wimg.text)
                        }
                        .padding(.horizontal, 16).frame(minHeight: WimgDimens.rowMinHeight)
                        RowDivider()
                        NavigationLink(value: "category") {
                            HStack(spacing: 8) {
                                Text(L("Kategorie")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                                Spacer()
                                Circle().fill(Wimg.categoryBar(category)).frame(width: 9, height: 9)
                                Text(L(WimgCategory.from(category).name)).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Wimg.text3)
                            }
                            .padding(.horizontal, 16).frame(minHeight: WimgDimens.rowMinHeight).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    GroupLabel(text: L("Rhythmus"))
                    Picker("", selection: $interval) {
                        ForEach(Self.rhythms, id: \.0) { Text(L($0.1)).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                    GroupLabel(text: L("Betrag"))
                    WimgGroup {
                        radio(false, L("Automatisch"), L("Wie die letzte Zahlung: %s", amountText(abs(p.detected_amount ?? p.amount), showPlus: false)))
                        RowDivider()
                        radio(true, L("Fester Betrag"), L("z. B. wenn die Rechnung schwankt"))
                    }
                    if fixed {
                        HStack {
                            TextField("0,00", text: $fixedText).keyboardType(.decimalPad).font(WimgType.amountLarge.font)
                            Text("€").font(WimgType.amountLarge.font).foregroundStyle(Wimg.text2)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 56)
                        .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.accent, lineWidth: 1))
                    }
                    QuietLine(text: L("Vergangene Zahlungen bleiben, wie sie gebucht sind."))
                }
                .padding(.horizontal, WimgDimens.sheetPadding)
                .padding(.bottom, 24)
            }
            .background(Wimg.sheet)
            .navigationTitle(L("Bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("Sichern"), action: save).bold() }
            }
            .navigationDestination(for: String.self) { _ in categoryList }
        }
        .tint(Wimg.accent)
        .presentationBackground(Wimg.sheet)
        .onAppear {
            name = p.displayName
            category = p.category
            interval = p.interval
            fixed = (p.fixed ?? 0) != 0
            fixedText = fixed ? AmountRange.number(abs(p.amount)) : ""
        }
    }

    private func radio(_ value: Bool, _ title: String, _ desc: String) -> some View {
        WimgRow(title: title, desc: desc, action: { fixed = value }) {
            Image(systemName: fixed == value ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 20)).foregroundStyle(fixed == value ? Wimg.accent : Wimg.text3)
        }
        .accessibilityAddTraits(fixed == value ? .isSelected : [])
    }

    private var categoryList: some View {
        ScrollView {
            WimgGroup {
                let ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 255, 0]
                ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                    if i > 0 { RowDivider() }
                    WimgRow(title: L(WimgCategory.from(id).name), action: { category = id; path.removeAll() }) {
                        Circle().fill(Wimg.categoryBar(id)).frame(width: 10, height: 10)
                    } trailing: {
                        if id == category { Image(systemName: "checkmark").foregroundStyle(Wimg.accent) }
                    }
                }
            }
            .padding(WimgDimens.sheetPadding)
        }
        .background(Wimg.sheet)
        .navigationTitle(L("Kategorie"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        let euros = Double(fixedText.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        let cents = euros.map { Int64(($0 * 100).rounded()) }
        let sign: Int64 = p.amount < 0 ? -1 : 1
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            try LibWimg.editRecurring(id: p.id,
                                      name: trimmed.isEmpty || trimmed == p.merchant ? nil : trimmed,
                                      category: category, interval: interval,
                                      fixedCents: fixed && (cents ?? 0) > 0 ? sign * cents! : nil)
            Changes.bump()
            Dock.shared.info(L("Gesichert"), sub: trimmed.isEmpty ? p.merchant : trimmed)
            dismiss()
        } catch {
            Dock.shared.error(L("Nicht gespeichert"), sub: L("Bitte versuch es noch einmal."))
        }
    }
}
