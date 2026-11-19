import SwiftUI
import WimgI18n

/// Sheet shown from onboarding (or Settings) to paste an existing sync key
/// and pull the linked device's data. Used when the user already has wimg
/// running on another device.
struct SyncLinkSheet: View {
    var onLinked: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var busy = false
    @State private var errorMessage = ""
    @State private var success = ""

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(WimgTheme.textSecondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                }
                Text(#L("Mit anderem Gerät verknüpfen"))
                    .font(WimgFont.font(.manrope, .heavy, 20, relativeTo: .title3))
                    .foregroundStyle(WimgTheme.text)
                Text(#L("Füge den Sync-Schlüssel deines anderen Geräts ein. Du findest ihn dort unter Einstellungen → Synchronisierung."))
                    .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(#L("Sync-Schlüssel"))
                    .font(.caption2)
                    .foregroundStyle(WimgTheme.textSecondary)
                HStack(spacing: 8) {
                    TextField("XXXX-XXXX-XXXX-XXXX", text: $input)
                        .font(.system(.subheadline, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(12)
                        .background(WimgTheme.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            input = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.subheadline)
                            .foregroundStyle(WimgTheme.text)
                            .padding(12)
                            .background(WimgTheme.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityLabel(L("Aus Zwischenablage einfügen"))
                }
            }
            .padding(.horizontal, 24)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }
            if !success.isEmpty {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await link() }
            } label: {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView()
                            .tint(WimgTheme.bg)
                            .scaleEffect(0.85)
                    }
                    Text(busy ? L("Verknüpfe...") : L("Verknüpfen"))
                }
                .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                .foregroundStyle(WimgTheme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(WimgTheme.text)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 24)

            Button {
                dismiss()
            } label: {
                Text(#L("Abbrechen"))
                    .font(WimgFont.font(.inter, .medium, 15, relativeTo: .subheadline))
                    .foregroundStyle(WimgTheme.textSecondary)
            }

            Spacer()
        }
        .background(WimgTheme.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func link() async {
        let key = input.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        busy = true
        errorMessage = ""
        success = ""

        SyncService.shared.setSyncKey(key)
        do {
            let pulled = try await SyncService.shared.pull()
            await SyncService.shared.connectWebSocket()
            success = String(format: L("Verknüpft — %d Einträge übernommen"), pulled)
            if pulled > 0 {
                NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
            }
            // Give the user a beat to see the success state.
            try? await Task.sleep(for: .milliseconds(500))
            onLinked?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            // Roll back — the key was bogus or pull failed; don't leave the
            // user in a half-linked state.
            SyncService.shared.clearSyncKey()
        }
        busy = false
    }
}
