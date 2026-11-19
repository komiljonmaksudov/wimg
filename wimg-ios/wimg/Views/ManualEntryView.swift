import SwiftUI
import WimgI18n

/// Account for entries without a bank ("„Bargeld“ ist ein eigenes Konto ohne Bank").
let cashAccount = "Bargeld"

/// Umsatz von Hand (Android board 22, as ManualEntryScreen.kt): amount first,
/// then text, category, account and date. A sheet with Abbrechen / Sichern;
/// editing a manual entry opens the same form filled in.
struct ManualEntryView: View {
    var editing: Transaction? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var expense = true
    /// Amount as typed, e.g. "18,4".
    @State private var typed = ""
    @State private var desc = ""
    @State private var category = -1
    @State private var account = cashAccount
    @State private var date = Date()
    @State private var accounts: [String] = [cashAccount]
    @State private var showMissing = false
    @FocusState private var focus: Field?
    @State private var path: [String] = []

    private enum Field { case amount, desc }

    private var cents: Int64 { Self.parseCents(typed) }

    var body: some View {
        NavigationStack(path: $path) {
            BandScreen(title: editing == nil ? L("Umsatz von Hand") : L("Bearbeiten"), pushed: true) {
                band
            } sheet: {
                form
            }
            // The form is the sheet's first page: Abbrechen, not a back arrow.
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("Speichern"), action: save).bold() }
            }
            .navigationDestination(for: String.self) { _ in categoryList }
        }
        .tint(Wimg.accent)
        .presentationBackground(Wimg.sheet)
        .onAppear(perform: fill)
        .task {
            let bank = await Task.detached { LibWimg.getAccounts().map(\.id) }.value
            var list = [cashAccount] + bank
            if !list.contains(account) { list.append(account) }
            accounts = list.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
    }

    // MARK: Band: Ausgabe / Einnahme and the amount

    @ViewBuilder private var band: some View {
        Picker("", selection: $expense) {
            Text(L("Ausgabe")).tag(true)
            Text(L("Einnahme")).tag(false)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)

        ZStack(alignment: .leading) {
            // The cents not typed yet are grey ("54.543,00"), so the thousands
            // dot can't be mistaken for the comma.
            (Text((expense ? wimgMinus : "+") + Self.formatTyped(typed))
                + Text(pendingCents).foregroundStyle(Wimg.bandSub)
                + Text(" €"))
                .font(WimgType.amountHero.font)
                .tracking(WimgType.amountHero.tracking)
                .foregroundStyle(cents == 0 ? (showMissing ? Wimg.bandNeg : Wimg.bandSub) : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityHidden(true)
            // Invisible field on top: it takes the typing, the text above is what you see.
            TextField("", text: Binding(get: { typed }, set: { typed = Self.clean($0) }))
                .keyboardType(.decimalPad)
                .focused($focus, equals: .amount)
                .font(WimgType.amountHero.font)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel(L("Betrag"))
                .accessibilityValue(amountText(Double(cents) / 100 * (expense ? -1 : 1)))
        }
        .padding(.top, 14)
    }

    private var pendingCents: String {
        if typed.isEmpty { return "" }
        guard let comma = typed.firstIndex(of: ",") else { return ",00" }
        return String(repeating: "0", count: max(0, 2 - typed[typed.index(after: comma)...].count))
    }

    // MARK: Form

    @ViewBuilder private var form: some View {
        WimgGroup {
            HStack(spacing: 16) {
                Text(L("Beschreibung")).wimgStyle(WimgType.body)
                    .foregroundStyle(showMissing && desc.trimmingCharacters(in: .whitespaces).isEmpty ? Wimg.danger : Wimg.text2)
                TextField(L("z. B. Wochenmarkt"), text: $desc)
                    .multilineTextAlignment(.trailing)
                    .font(WimgType.rowTitle.font)
                    .foregroundStyle(Wimg.text)
                    .focused($focus, equals: .desc)
                    .submitLabel(.done)
                    .onChange(of: desc) { if desc.count > 120 { desc = String(desc.prefix(120)) } }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: WimgDimens.rowMinHeight)
            RowDivider()
            NavigationLink(value: "category") {
                HStack(spacing: 8) {
                    Text(L("Kategorie")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                    Spacer(minLength: 12)
                    if category < 0 {
                        Text(L("Wählen")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                    } else {
                        Circle().fill(Wimg.categoryBar(category)).frame(width: 9, height: 9)
                        Text(L(WimgCategory.from(category).name)).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Wimg.text3)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: WimgDimens.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RowDivider()
            HStack {
                Text(L("Konto")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                Spacer(minLength: 12)
                Picker(L("Konto"), selection: $account) {
                    ForEach(accounts, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Wimg.text)
            }
            .padding(.leading, 16).padding(.trailing, 6)
            .frame(minHeight: WimgDimens.rowMinHeight)
            RowDivider()
            DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) {
                Text(L("Datum")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
            }
            .environment(\.locale, Locale(identifier: UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE"))
            .padding(.horizontal, 16)
            .frame(minHeight: WimgDimens.rowMinHeight)
        }
        QuietLine(text: L("Von Hand angelegte Umsätze werden nie mit Bankdaten überschrieben. „Bargeld“ ist ein eigenes Konto ohne Bank."))
    }

    private var categoryList: some View {
        ScrollView {
            WimgGroup {
                let ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 255, 0]
                ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                    if i > 0 { RowDivider() }
                    Button { category = id; path.removeAll() } label: {
                        HStack(spacing: 12) {
                            Circle().fill(Wimg.categoryBar(id)).frame(width: 10, height: 10)
                            Text(L(WimgCategory.from(id).name)).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                            Spacer()
                            if id == category {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Wimg.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(id == category ? .isSelected : [])
                }
            }
            .padding(WimgDimens.sheetPadding)
        }
        .background(Wimg.sheet)
        .navigationTitle(L("Kategorie"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Actions

    private func fill() {
        guard let e = editing else { focus = .amount; return }
        expense = e.amount < 0
        typed = Self.typedOf(abs(e.amount))
        desc = e.description
        category = e.category
        account = (e.account?.isEmpty == false ? e.account : nil) ?? cashAccount
        date = WimgDates.parse(e.date) ?? Date()
    }

    private func save() {
        let text = desc.trimmingCharacters(in: .whitespaces)
        if cents == 0 {
            showMissing = true
            Dock.shared.error(L("Betrag fehlt"), sub: L("Tipp oben den Betrag ein."))
            focus = .amount
            return
        }
        if text.isEmpty {
            showMissing = true
            Dock.shared.error(L("Beschreibung fehlt"), sub: L("Wofür war das? Zum Beispiel „Wochenmarkt“."))
            focus = .desc
            return
        }
        let signed = expense ? -cents : cents
        let cat = UInt8(category < 0 ? 0 : category)
        let iso = WimgDates.iso(date)
        do {
            if let e = editing {
                try LibWimg.updateManualTransaction(id: e.id, date: iso, description: text, amountCents: signed, category: cat, account: account)
            } else {
                try LibWimg.addManualTransaction(date: iso, description: text, amountCents: signed, category: cat, account: account)
            }
            Changes.bump()
            Dock.shared.info(L("Umsatz gespeichert"), sub: text)
            dismiss()
        } catch {
            Dock.shared.error(L("Nicht gespeichert"), sub: L("Bitte versuch es noch einmal."))
        }
    }

    // MARK: Amount text (same rules as Android)

    /// Kept to "12345,67": one comma (a dot counts as one), at most 5 digits
    /// before it and 2 after, no leading zeros.
    static func clean(_ input: String) -> String {
        var whole = "", dec = "", comma = false
        for ch in input.replacingOccurrences(of: ".", with: ",") {
            if ch == ",", !comma { comma = true }
            else if ch.isNumber, !comma, whole.count < 5 { whole.append(ch) }
            else if ch.isNumber, comma, dec.count < 2 { dec.append(ch) }
        }
        let trimmed = String(whole.drop(while: { $0 == "0" }))
        whole = trimmed.isEmpty ? ((comma || input.hasPrefix("0")) ? "0" : "") : trimmed
        return comma ? "\(whole),\(dec)" : whole
    }

    /// "18,4" → 1840 cents.
    static func parseCents(_ t: String) -> Int64 {
        guard !t.isEmpty else { return 0 }
        let parts = t.split(separator: ",", omittingEmptySubsequences: false)
        let whole = Int64(parts[0].isEmpty ? "0" : String(parts[0])) ?? 0
        let decRaw = parts.count > 1 ? String(parts[1]) : ""
        let dec = Int64(String((decRaw + "00").prefix(2))) ?? 0
        return whole * 100 + dec
    }

    /// "1.234,5" while typing, "0,00" when empty.
    static func formatTyped(_ t: String) -> String {
        guard !t.isEmpty else { return "0,00" }
        let parts = t.split(separator: ",", omittingEmptySubsequences: false)
        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        var grouped = ""
        for (i, ch) in whole.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(".") }
            grouped.append(ch)
        }
        grouped = String(grouped.reversed())
        return parts.count > 1 ? "\(grouped),\(parts[1])" : grouped
    }

    /// 18.4 → "18,4", 20.0 → "20" (as if typed).
    static func typedOf(_ euros: Double) -> String {
        let c = Int64((euros * 100).rounded())
        if c % 100 == 0 { return "\(c / 100)" }
        var s = String(format: "%d,%02d", c / 100, c % 100)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}
