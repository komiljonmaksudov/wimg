import SwiftUI
import WimgI18n

struct SyncQRSheet: View {
    let syncKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?

    var body: some View {
        VStack(spacing: 20) {
            // Drag handle
            Capsule()
                .fill(WimgTheme.textSecondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text(#L("Sync-Schlüssel teilen"))
                    .font(WimgFont.font(.manrope, .heavy, 20, relativeTo: .title3))
                    .foregroundStyle(WimgTheme.text)
                Text(#L("Scanne diesen Code auf deinem anderen Gerät, um es zu verknüpfen."))
                    .font(WimgFont.font(.inter, .regular, 15, relativeTo: .subheadline))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 280, height: 280)
                    .shadow(color: .black.opacity(0.06), radius: 16, y: 4)
                if let image = qrImage {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                } else {
                    ProgressView()
                }
            }

            Text(syncKey)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(WimgTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = syncKey
                } label: {
                    Label(#L("Kopieren"), systemImage: "doc.on.doc")
                        .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
                        .foregroundStyle(WimgTheme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WimgTheme.cardBg)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(WimgTheme.border, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    dismiss()
                } label: {
                    Text(#L("Schließen"))
                        .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
                        .foregroundStyle(WimgTheme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WimgTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 24)

            // Hint
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(#L("Nur an deine eigenen Geräte weitergeben — wer den Schlüssel hat, kann auf deine Finanzdaten zugreifen."))
                    .font(WimgFont.font(.inter, .regular, 11, relativeTo: .caption2))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(WimgTheme.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .task {
            // Render QR off the render-frame path so big sheets don't jank.
            let key = syncKey
            qrImage = await Task.detached(priority: .userInitiated) {
                QRCode.image(from: key, size: 480)
            }.value
        }
    }
}
