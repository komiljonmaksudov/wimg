import SwiftUI
import WimgI18n

struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(WimgFont.font(.inter, .medium, 15, relativeTo: .subheadline))
                .foregroundStyle(.white)

            Spacer()

            Button(#L("Rückgängig")) {
                onUndo()
            }
            .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
            .foregroundStyle(WimgTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(red: 0.102, green: 0.102, blue: 0.102).opacity(0.92)) // always dark
        .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusSmall, style: .continuous))
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
