import SwiftUI
import WimgI18n

/// Tiny "i" icon that pops a one-sentence explanation when tapped.
/// Replaces the dedicated About FAQ for first-encounter inline help.
struct InfoTooltip: View {
    let text: String
    @State private var show = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.6))
            // Stay at icon size — never push neighbors into truncation.
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onTapGesture { show.toggle() }
            .popover(isPresented: $show, arrowEdge: .top) {
                Text(L(text))
                    .font(WimgFont.font(.inter, .regular, 13, relativeTo: .footnote))
                    .foregroundStyle(WimgTheme.text)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(width: 280, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
            }
    }
}
