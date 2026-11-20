import SwiftUI
import WimgI18n

/// One booking (as Android's TransactionDetailScreen): amount in the band,
/// date / category / account, the bank's text as sent, "Aus Summen
/// ausschließen". Category and the menu are round buttons in the band.
struct TransactionDetailView: View {
    let id: String

    @State private var tx: Transaction?
    @State private var account: Account?
    @State private var isPending = false
    @State private var suggestions: [Int] = []
    @State private var showCategory = false
    @State private var confirmDelete = false
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let tx {
                page(tx)
            } else {
                BandScreen(title: L("Umsatz"), pushed: true) { EmptyView() } sheet: { EmptyView() }
            }
        }
        .task(id: id) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in Task { await load() } }
    }

    private func page(_ tx: Transaction) -> some View {
        let accountName = account.map { $0.bank.isEmpty ? $0.name : $0.bank } ?? (tx.account ?? "")
        return BandScreen(title: tx.displayTitle, pushed: true) {
            if !isPending {
                BandButton(systemImage: "tag", label: L("Kategorie wählen")) { showCategory = true }
            }
            Menu {
                Button { copy(tx) } label: { Label(L("Text kopieren"), systemImage: "doc.on.doc") }
                if tx.isManual {
                    Button { showEdit = true } label: { Label(L("Bearbeiten"), systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label(L("Löschen"), systemImage: "trash") }
                }
            } label: {
                BandIcon(systemImage: "ellipsis")
            }
            .accessibilityLabel(L("Mehr"))
        } band: {
            BandOver(text: overLine(tx))
            Amount(euros: tx.amount, style: WimgType.amountHero, centsStyle: WimgType.amountHeroCents,
                   color: tx.amount > 0 ? Wimg.bandPos : .white)
                .padding(.top, 2)
            if !accountName.isEmpty {
                Text(accountName).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).padding(.top, 4)
            }
        } sheet: {
            VStack(spacing: 0) {
                infoRow(L("Datum"), WimgDates.full(tx.date))
                FlatDivider()
                Button { showCategory = true } label: {
                    HStack(spacing: 8) {
                        Text(L("Kategorie")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                        Spacer(minLength: 12)
                        Circle().fill(Wimg.categoryBar(tx.category)).frame(width: 9, height: 9)
                        Text(L(WimgCategory.from(tx.category).name)).wimgStyle(WimgType.body).foregroundStyle(Wimg.text)
                        if !isPending {
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Wimg.text3)
                        }
                    }
                    .frame(minHeight: WimgDimens.rowMinHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isPending)
                .accessibilityElement(children: .combine)
                FlatDivider()
                if !accountName.isEmpty {
                    infoRow(L("Konto"), accountName)
                    FlatDivider()
                }
            }

            GroupLabel(text: L("Verwendungszweck"))
            VStack(alignment: .leading, spacing: 10) {
                if let kind = tx.kind, !kind.isEmpty {
                    Text(L(kind).uppercased())
                        .wimgStyle(WimgType.label).foregroundStyle(Wimg.text)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Wimg.neutralTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                // The bank's text exactly as sent (copy rule: never rewritten).
                Text(tx.description).wimgStyle(WimgType.mono).foregroundStyle(Wimg.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))

            if isPending {
                QuietLine(text: L("Noch nicht gebucht. Die Bank kann Betrag oder Text noch ändern; bis zur Buchung zählt er nirgends mit."))
                    .padding(.top, 10)
            } else {
                FlatDivider().padding(.top, 20)
                Toggle(isOn: Binding(get: { tx.isExcluded }, set: { setExcluded(tx, $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Aus Summen ausschließen")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                        Text(L("Zählt dann nicht in der Übersicht")).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                    }
                }
                .toggleStyle(.wimg)
                .frame(minHeight: 72)
            }
        }
        .sheet(isPresented: $showCategory) {
            CategorySheet(tx: tx, suggestions: suggestions) { cat in
                showCategory = false
                applyCategory(tx, cat)
            }
        }
        .sheet(isPresented: $showEdit) { ManualEntryView(editing: tx) }
        .confirmationDialog(L("„%s“ löschen?", tx.displayTitle), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Löschen"), role: .destructive) { delete(tx) }
            Button(L("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L("Auch auf deinen anderen Geräten. Das lässt sich nicht rückgängig machen."))
        }
    }

    private func overLine(_ tx: Transaction) -> String {
        var parts: [String] = []
        if isPending { parts.append(L("Vorgemerkt")) }
        parts.append(WimgDates.full(tx.date))
        if let k = tx.kind, !k.isEmpty { parts.append(L(k)) }
        return parts.joined(separator: " · ")
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
            Spacer(minLength: 12)
            Text(value).wimgStyle(WimgType.body).foregroundStyle(Wimg.text).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: WimgDimens.rowMinHeight)
        .accessibilityElement(children: .combine)
    }

    // MARK: Data and actions

    private func load() async {
        let id = id
        let (t, a, pending, sugg) = await Task.detached { () -> (Transaction?, Account?, Bool, [Int]) in
            let all = (try? LibWimg.getTransactions()) ?? []
            let booked = all.first { $0.id == id }
            let t = booked ?? LibWimg.getPending(account: nil).first { $0.id == id }
            let a = LibWimg.getAccounts().first { $0.id == t?.account }
            return (t, a, booked == nil && t != nil, Self.suggest(for: t, in: all))
        }.value
        tx = t; account = a; isPending = pending; suggestions = sugg
    }

    /// Three suggestions: the current category (if it is a real one), then the
    /// categories used most for bookings with the same sign.
    nonisolated private static func suggest(for tx: Transaction?, in all: [Transaction]) -> [Int] {
        guard let tx else { return [] }
        var counts: [Int: Int] = [:]
        for t in all where (t.amount < 0) == (tx.amount < 0) && t.category != 0 && t.category != 255 {
            counts[t.category, default: 0] += 1
        }
        var out: [Int] = []
        if tx.category != 0 && tx.category != 255 { out.append(tx.category) }
        for (c, _) in counts.sorted(by: { $0.value > $1.value }) where !out.contains(c) {
            out.append(c)
            if out.count == 3 { break }
        }
        return out
    }

    private func applyCategory(_ tx: Transaction, _ category: Int) {
        guard category != tx.category else { return }
        // The merchant's other bookings that are uncategorised or in Sonstiges follow.
        let others = (try? LibWimg.setCategory(id: tx.id, category: UInt8(category))) ?? 0
        Changes.bump()
        let label = L(WimgCategory.from(category).name)
        Dock.shared.undo(L("Kategorie geändert"), sub: others > 0 ? "\(label) · " + L("+%d weitere", others) : label) {
            _ = LibWimg.undo()
            Changes.bump()
        }
    }

    private func setExcluded(_ tx: Transaction, _ excluded: Bool) {
        try? LibWimg.setExcluded(id: tx.id, excluded: excluded)
        Changes.bump()
        Dock.shared.undo(excluded ? L("Aus Summen ausgeschlossen") : L("Zählt wieder mit")) {
            _ = LibWimg.undo()
            Changes.bump()
        }
    }

    private func copy(_ tx: Transaction) {
        UIPasteboard.general.string = tx.description
        Dock.shared.info(L("Text kopiert"))
    }

    private func delete(_ tx: Transaction) {
        do {
            try LibWimg.deleteTransaction(id: tx.id)
            Changes.bump()
            Dock.shared.info(L("Umsatz gelöscht"), sub: tx.displayTitle)
            dismiss()
        } catch {
            Dock.shared.error(L("Nicht gelöscht"), sub: L("Bitte versuch es noch einmal."))
        }
    }
}

/// Category sheet (board 12): the booking, a search field, three suggestions,
/// then every category. Half height; grows when searching. A tap applies.
struct CategorySheet: View {
    let tx: Transaction
    let suggestions: [Int]
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var detent: PresentationDetent = .medium
    @FocusState private var searching: Bool

    /// Picker order of the design; 0 is "Unkategorisiert", 255 "Sonstiges".
    private static let order: [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 255, 0]

    private var matches: [Int] {
        guard !query.isEmpty else { return Self.order }
        return Self.order.filter { L(WimgCategory.from($0).name).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        (Text(tx.displayTitle).font(WimgType.rowTitle.font.bold())
                            + Text(" · " + WimgDates.short(tx.date)).font(WimgType.body.font))
                            .foregroundStyle(Wimg.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Amount(euros: tx.amount, color: tx.amount > 0 ? Wimg.pos : Wimg.text)
                    }
                    SearchField(text: $query, prompt: L("Kategorie suchen"), focused: $searching)

                    if query.isEmpty && !suggestions.isEmpty {
                        Text(L("Vorschläge")).wimgStyle(WimgType.label).foregroundStyle(Wimg.text2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { chip($0) }
                            }
                        }
                    }

                    WimgGroup {
                        ForEach(Array(matches.enumerated()), id: \.element) { i, id in
                            if i > 0 { RowDivider() }
                            categoryRow(id)
                        }
                    }

                    QuietLine(text: L("Andere Umsätze dieses Händlers ohne Kategorie ziehen mit, und wimg merkt sich die Wahl für neue."))
                }
                .padding(.horizontal, WimgDimens.sheetPadding)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Wimg.sheet)
            .navigationTitle(L("Kategorie"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("Schließen"))
                }
            }
        }
        .tint(Wimg.accent)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(Wimg.sheet)
        .presentationDragIndicator(.visible)
        .onChange(of: searching) { if searching { detent = .large } }
    }

    private func chip(_ id: Int) -> some View {
        let on = id == tx.category
        return Button { onPick(id) } label: {
            HStack(spacing: 8) {
                Circle().fill(on ? Wimg.onAccent : Wimg.categoryBar(id)).frame(width: 9, height: 9)
                Text(L(WimgCategory.from(id).name)).wimgStyle(WimgType.chip)
            }
            .foregroundStyle(on ? Wimg.onAccent : Wimg.text)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(on ? Wimg.accent : Wimg.card, in: Capsule())
            .overlay(Capsule().stroke(on ? .clear : Wimg.line, lineWidth: 1))
        }
        .buttonStyle(.wimgPress)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func categoryRow(_ id: Int) -> some View {
        let on = id == tx.category
        return Button { onPick(id) } label: {
            HStack(spacing: 12) {
                if id == 0 {
                    Circle().stroke(Wimg.text2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(width: 10, height: 10)
                } else {
                    Circle().fill(Wimg.categoryBar(id)).frame(width: 10, height: 10)
                }
                Text(L(WimgCategory.from(id).name))
                    .font(on ? WimgFont.font(.inter, .bold, 15) : WimgType.rowTitle.font)
                    .foregroundStyle(Wimg.text)
                Spacer()
                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Wimg.accent) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
