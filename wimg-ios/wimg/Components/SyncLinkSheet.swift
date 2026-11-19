import SwiftUI
import VisionKit
import WimgI18n

/// "Ich nutze wimg schon" (board 21, as Android's SettingsSyncLinkScreen):
/// scan the other device's QR code or paste its key. The key is checked
/// against the server first (can it open the data?); only then is it saved
/// and the data pulled. A wrong key never gets anything pushed under it.
struct SyncLinkSheet: View {
    var onLinked: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var busy = false
    @State private var noMatch = false
    @State private var offline = false
    @State private var scanning = false

    private var key: String? { SyncService.normalizeKey(input) }
    private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // The viewfinder: the camera when this device has one that can read codes.
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Wimg.band)
                        if scanning && canScan {
                            QRScanner { code in
                                guard !busy else { return }
                                input = code
                                Task { await link() }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        Image(systemName: "viewfinder").font(.system(size: 120, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.8)).frame(maxHeight: .infinity)
                            .accessibilityHidden(true)
                        Text(canScan ? (scanning ? L("QR-Code vom anderen Gerät ins Feld halten") : L("Tippen, um die Kamera einzuschalten"))
                                     : L("Auf diesem Gerät geht kein QR-Scan: füge den Schlüssel unten ein."))
                            .wimgStyle(WimgType.body).foregroundStyle(.white).multilineTextAlignment(.center)
                            .padding(.horizontal, 16).padding(.bottom, 18)
                    }
                    .frame(height: 280)
                    .contentShape(Rectangle())
                    .onTapGesture { if canScan { scanning = true } }

                    HStack(spacing: 12) {
                        Rectangle().fill(Wimg.line).frame(height: 1)
                        Text(L("oder einfügen")).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).fixedSize()
                        Rectangle().fill(Wimg.line).frame(height: 1)
                    }

                    let bad = noMatch || (!input.isEmpty && key == nil)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Sync-Schlüssel")).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                        HStack {
                            TextField("XXXX-XXXX-XXXX-XXXX-…", text: $input)
                                .font(WimgFont.font(.mono, .medium, 16))
                                .foregroundStyle(Wimg.text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: input) { noMatch = false; offline = false }
                                .submitLabel(.go)
                                .onSubmit { if key != nil { Task { await link() } } }
                            Button {
                                input = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            } label: { Image(systemName: "doc.on.clipboard").foregroundStyle(Wimg.text) }
                                .accessibilityLabel(L("Aus Zwischenablage einfügen"))
                        }
                    }
                    .padding(16)
                    .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous)
                        .stroke(bad ? Wimg.danger : Wimg.line, lineWidth: 1))

                    if offline {
                        QuietLine(text: L("Server nicht erreichbar. Prüfe die Internetverbindung und versuch es noch einmal."),
                                  systemImage: "wifi.exclamationmark", color: Wimg.warn)
                    } else if noMatch {
                        QuietLine(text: L("Dieser Schlüssel passt zu keinem wimg Sync. Prüfe die Zeichen: 0 und O, 1 und l sehen sich ähnlich."),
                                  systemImage: "exclamationmark.circle", color: Wimg.danger)
                    } else if !input.isEmpty && key == nil {
                        QuietLine(text: L("Das sieht nicht wie ein Sync-Schlüssel aus. Er hat 32 Zeichen aus 0–9 und a–f."),
                                  systemImage: "exclamationmark.circle", color: Wimg.danger)
                    } else {
                        QuietLine(text: L("Der Schlüssel verlässt dieses Gerät nicht. wimgs Server bekommt nur verschlüsselte Daten."),
                                  systemImage: "lock")
                    }
                    QuietLine(text: L("Auf dem anderen Gerät: Einstellungen › wimg Sync › Sync-Schlüssel anzeigen."))

                    Button { Task { await link() } } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(Wimg.onAccent) }
                            Text(busy ? L("Verknüpfe…") : L("Verbinden")).wimgStyle(WimgType.button)
                        }
                        .foregroundStyle(Wimg.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Wimg.accent.opacity(key == nil ? 0.45 : 1), in: Capsule())
                    }
                    .buttonStyle(.wimgPress)
                    .disabled(busy || key == nil)
                }
                .padding(WimgDimens.sheetPadding)
            }
            .background(Wimg.sheet)
            .navigationTitle(L("Mit deinem wimg verbinden"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen")) { dismiss() } }
            }
        }
        .tint(Wimg.accent)
        .presentationDetents([.large])
    }

    private func link() async {
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = SyncService.normalizeKey(typed) else { return }
        busy = true
        noMatch = false
        offline = false
        // Older iOS builds made uppercase keys: try the key as typed first, then the normal form.
        var found: String?
        var wasOffline = false
        for candidate in (typed == normalized ? [typed] : [typed, normalized]) {
            switch await SyncService.shared.probe(candidate) {
            case .found: found = candidate
            case .offline: wasOffline = true
            case .noMatch: break
            }
            if found != nil { break }
        }
        guard let key = found else {
            busy = false
            // Said in the sheet: the Dock sits behind it.
            if wasOffline { offline = true } else { noMatch = true }
            return
        }
        SyncService.shared.setSyncKey(key)
        do {
            let r = try await SyncService.shared.syncFull()
            await SyncService.shared.connectWebSocket()
            Changes.bump()
            Dock.shared.info(L("Verknüpft"), sub: L("%d Änderungen übernommen", r.pulled))
            onLinked?()
            dismiss()
        } catch {
            Dock.shared.error(L("Nicht synchron"), sub: L("Keine Verbindung zum Sync-Server. Später erneut versuchen."))
        }
        busy = false
    }
}

/// Apple's live QR reader (VisionKit). Calls back once per code it sees.
private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .fast, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items {
                if case .barcode(let code) = item, let text = code.payloadStringValue, SyncService.normalizeKey(text) != nil {
                    onCode(text)
                    return
                }
            }
        }
    }
}
