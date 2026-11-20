import SwiftUI
import UniformTypeIdentifiers
import WimgI18n

/// Import in three steps, as Android's ImportScreen: choose a file (with how to
/// get it from each bank), preview what is new, done. Nothing is written
/// before "importieren".
struct ImportView: View {
    var onViewTransactions: (() -> Void)?

    private enum Step { case source, preview, done }

    private struct Source {
        let format, name, account: String
        let steps: [String]
    }

    private static let sources: [Source] = [
        Source(format: "comdirect", name: "Comdirect", account: "Girokonto",
               steps: ["Bei Comdirect im Browser anmelden.", "Umsätze des Girokontos öffnen und als CSV exportieren.", "Die Datei hier auswählen. Sie bleibt auf deinem Gerät."]),
        Source(format: "trade_republic", name: "Trade Republic", account: "Verrechnungskonto",
               steps: ["In der Trade-Republic-App oder im Browser das Profil öffnen.", "Unter Transaktionen den Export als CSV anfordern.", "Die Datei hier auswählen. Sie bleibt auf deinem Gerät."]),
        Source(format: "scalable_capital", name: "Scalable", account: "Verrechnungskonto",
               steps: ["Bei Scalable Capital im Browser anmelden.", "Unter Transaktionen die Umsätze als CSV exportieren.", "Die Datei hier auswählen. Sie bleibt auf deinem Gerät."]),
        Source(format: "revolut", name: "Revolut", account: "Konto (CSV)",
               steps: ["In der Revolut-App das Konto öffnen, dann ⋯ und „Kontoauszug“.", "„Excel“ wählen (das ist eine CSV-Datei) und den Zeitraum.", "Die Datei hier auswählen. Sie bleibt auf deinem Gerät."]),
        Source(format: "statement", name: "Andere Bank", account: "Kontoauszug als MT940 oder CAMT",
               steps: ["Im Online-Banking deiner Bank die Umsätze oder Kontoauszüge öffnen.", "Als MT940 (.sta) oder CAMT (.xml) exportieren. Oft heißt das „Export für Finanzsoftware“.", "Die Datei hier auswählen. Sie bleibt auf deinem Gerät."]),
    ]

    /// A read file waiting for confirmation.
    private struct Picked {
        let name: String
        let data: Data
        let format: String
        let rows: [Transaction]
        let duplicates: Int
        let statement: Bool
        let account: String
    }

    @State private var step: Step = .source
    @State private var openHelp: Int?
    @State private var picked: Picked?
    @State private var result: ImportResult?
    @State private var busy = false
    @State private var error: String?
    @State private var showPicker = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BandScreen(title: L("Import"), pushed: true) {
            stepBand
        } sheet: {
            switch step {
            case .source: sourceStep
            case .preview: previewStep
            case .done: doneStep
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.commaSeparatedText, .xml, .plainText, .data]) { read($0) }
        .navigationBarBackButtonHidden(step == .preview)
        .toolbar {
            if step == .preview {
                ToolbarItem(placement: .topBarLeading) {
                    Button { back() } label: { Image(systemName: "chevron.left") }.accessibilityLabel(L("Zurück"))
                }
            }
        }
    }

    // MARK: Band

    private var stepIndex: Int { step == .source ? 1 : step == .preview ? 2 : 3 }

    @ViewBuilder private var stepBand: some View {
        Text(L("Schritt %d von %d", stepIndex, 3)).wimgStyle(WimgType.bandOver).foregroundStyle(Wimg.bandSub)
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { i in
                Capsule().fill(i <= stepIndex ? Color.white : Color.white.opacity(0.18)).frame(height: 4)
            }
        }
        .padding(.top, 10).padding(.bottom, 14)
        .accessibilityHidden(true)
        Text(step == .source ? L("Datei wählen") : step == .preview ? L("Vorschau") : L("Fertig"))
            .wimgStyle(WimgType.title).foregroundStyle(.white)
    }

    // MARK: Step 1

    @ViewBuilder private var sourceStep: some View {
        Text(L("Wähle einen Kontoauszug (MT940, CAMT) oder eine CSV-Datei deiner Bank. wimg erkennt selbst, was es ist; die Datei bleibt auf deinem Gerät."))
            .wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).padding(.horizontal, 4).padding(.top, 4)
        GroupLabel(text: L("So kommst du an die Datei"))
        WimgGroup {
            ForEach(Array(Self.sources.enumerated()), id: \.offset) { i, src in
                if i > 0 { FlatDivider() }
                helpRow(i, src)
            }
        }
        errorLine
        primaryButton(L("Datei wählen")) { showPicker = true }
            .padding(.top, 20)
    }

    private func helpRow(_ i: Int, _ src: Source) -> some View {
        let open = openHelp == i
        return Button {
            withAnimation(WimgMotion.out(0.2)) { openHelp = open ? nil : i }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L(src.name)).font(WimgFont.font(.inter, .bold, 16)).foregroundStyle(Wimg.text)
                        Text(L(src.account)).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                    }
                    Spacer()
                    Image(systemName: open ? "minus" : "plus").foregroundStyle(open ? Wimg.accent : Wimg.text2)
                }
                if open {
                    ForEach(Array(src.steps.enumerated()), id: \.offset) { n, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text("\(n + 1).").frame(width: 22, alignment: .leading)
                            Text(L(line)).fixedSize(horizontal: false, vertical: true)
                        }
                        .wimgStyle(WimgType.body).foregroundStyle(Wimg.text)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(open ? Wimg.accentSoft : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(open ? .isSelected : [])
    }

    // MARK: Step 2

    @ViewBuilder private var previewStep: some View {
        if let p = picked {
            let src = Self.sources.first { $0.format == p.format }
            HStack(spacing: 14) {
                Text(p.statement ? (p.format == "camt" ? "XML" : "STA") : "CSV")
                    .wimgStyle(WimgType.mono).foregroundStyle(Wimg.text)
                    .frame(width: 44, height: 44)
                    .background(Wimg.neutralTint, in: RoundedRectangle(cornerRadius: WimgShape.iconTile, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).wimgStyle(WimgType.mono).foregroundStyle(Wimg.text).lineLimit(1).truncationMode(.middle)
                    Text(p.statement ? "\(p.account) · \(L("Kontoauszug")) \(p.format.uppercased())"
                         : src.map { "\($0.name) · \(L($0.account))" } ?? L("Format erkannt"))
                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))

            let dates = p.rows.map(\.date).sorted()
            HStack(spacing: 10) {
                statCard(L("Neu"), "\(p.rows.count - p.duplicates)")
                statCard(L("Schon da"), "\(p.duplicates)")
                statCard(L("Zeitraum"), "\(WimgDates.short(dates.first ?? "")) – \(WimgDates.short(dates.last ?? ""))", small: true)
                    .layoutPriority(1)
            }
            .padding(.top, 12)
            if p.rows.count == p.duplicates {
                Text(L("Alle Umsätze dieser Datei sind schon in wimg.")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).padding(.top, 14)
            }
            GroupLabel(text: L("Neueste Umsätze"))
            ForEach(p.rows.sorted { $0.date > $1.date }.prefix(5), id: \.id) { t in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title.flatMap { $0.isEmpty ? nil : $0 } ?? t.description)
                            .wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(1)
                        Text(WimgDates.full(t.date)).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                    }
                    Spacer(minLength: 0)
                    Text(amountText(t.amount)).wimgStyle(WimgType.amountRow).foregroundStyle(t.amount > 0 ? Wimg.pos : Wimg.text)
                }
                .frame(minHeight: 60)
                FlatDivider()
            }
            errorLine
            let n = p.rows.count - p.duplicates
            primaryButton(n == 0 ? L("Nichts zu importieren") : n == 1 ? L("1 Umsatz importieren") : L("%d Umsätze importieren", n),
                          busy: busy) {
                if n > 0 { doImport() } else { AppNav.shared.open(.overview) }
            }
            .padding(.top, 20)
        }
    }

    // MARK: Step 3

    @ViewBuilder private var doneStep: some View {
        let r = result
        VStack(spacing: 0) {
            Image(systemName: "checkmark").font(.system(size: 32, weight: .semibold)).foregroundStyle(Wimg.inkText)
                .frame(width: 76, height: 76).background(Wimg.ink, in: Circle())
                .padding(.top, 16)
            Text(L("Import fertig")).wimgStyle(WimgType.title).foregroundStyle(Wimg.text).padding(.top, 18)
            Text(L("wimg hat die Umsätze schon nach Kategorien sortiert, so weit es ging."))
                .wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).multilineTextAlignment(.center).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        HStack(spacing: 10) {
            statCard(L("Importiert"), "\(r?.imported ?? 0)")
            statCard(L("Schon da, übersprungen"), "\(r?.skipped_duplicates ?? 0)")
        }
        .padding(.top, 20)
        if let e = r?.errors, e > 0 {
            Text(L("%d Zeilen konnte wimg nicht lesen.", e)).wimgStyle(WimgType.body).foregroundStyle(Wimg.warn).padding(.top, 12)
        }
        QuietLine(text: L("Ein Import ist eine Momentaufnahme. Für neue Umsätze: Bank verbinden oder später wieder importieren."))
        primaryButton(L("Umsätze ansehen")) {
            if let onViewTransactions { onViewTransactions() } else { AppNav.shared.open(.transactions) }
        }
        .padding(.top, 20)
    }

    // MARK: Pieces

    @ViewBuilder private var errorLine: some View {
        if let error {
            QuietLine(text: error, systemImage: "exclamationmark.triangle", color: Wimg.warn)
        }
    }

    private func statCard(_ label: String, _ value: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).lineLimit(1)
            Text(value).font(small ? WimgType.chip.font : WimgFont.font(.manrope, .heavy, 22))
                .foregroundStyle(Wimg.text).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))
    }

    private func primaryButton(_ title: String, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(Wimg.onAccent) }
                Text(title).wimgStyle(WimgType.button)
            }
            .foregroundStyle(Wimg.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Wimg.accent, in: Capsule())
        }
        .buttonStyle(.wimgPress)
        .disabled(busy)
    }

    // MARK: Actions

    private func back() {
        step = .source; picked = nil; error = nil
    }

    private func read(_ res: Result<URL, Error>) {
        error = nil
        guard case let .success(url) = res else { return }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            error = L("Import fehlgeschlagen. Es wurde nichts gespeichert."); return
        }
        busy = true
        Task {
            let p: Picked? = await Task.detached {
                // A statement file (MT940, CAMT) first; anything else is tried as CSV.
                if let st = LibWimg.parseStatement(data) {
                    return st.transactions.isEmpty ? nil : Picked(name: url.lastPathComponent, data: data, format: st.format, rows: st.transactions,
                                                                  duplicates: st.duplicates ?? 0, statement: true, account: st.account ?? "")
                }
                guard let parsed = try? LibWimg.parseCSV(data), !parsed.transactions.isEmpty else { return nil }
                // Same id scheme as the database, so this matches what import will skip.
                let existing = Set(((try? LibWimg.getTransactions()) ?? []).map(\.id))
                return Picked(name: url.lastPathComponent, data: data, format: parsed.format, rows: parsed.transactions,
                              duplicates: parsed.transactions.filter { existing.contains($0.id) }.count, statement: false, account: "")
            }.value
            busy = false
            if let p { picked = p; step = .preview }
            else { error = L("wimg erkennt diese Datei nicht. Unterstützt sind Kontoauszüge als MT940 oder CAMT und CSV-Exporte von Comdirect, Trade Republic, Scalable und Revolut.") }
        }
    }

    private func doImport() {
        guard let p = picked else { return }
        busy = true
        Task {
            let r: ImportResult? = await Task.detached {
                guard let r = try? (p.statement ? LibWimg.importStatement(p.data) : LibWimg.importCSV(p.data)) else { return nil }
                if r.imported > 0 { _ = LibWimg.detectRecurring() }
                return r
            }.value
            busy = false
            guard let r else { error = L("Import fehlgeschlagen. Es wurde nichts gespeichert."); return }
            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
            result = r; step = .done
        }
    }
}
