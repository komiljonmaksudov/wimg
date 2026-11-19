import SwiftUI
import WimgI18n

struct MoreView: View {
    @Binding var selectedAccount: String?
    var popToRoot: UUID
    @State private var path = NavigationPath()

    private let items: [(title: String, icon: String, color: Color, destination: Destination)] = [
        ("Wiederkehrend", "arrow.triangle.2.circlepath", .green, .recurring),
        ("Import", "square.and.arrow.down", .blue, .import_),
        ("Bankkonto", "building.columns", .teal, .fints),
        ("Rückblick", "calendar", .purple, .review),
        ("Einstellungen", "gearshape", .orange, .settings),
        ("Über wimg", "info.circle", .gray, .about),
    ]

    enum Destination: String, Hashable {
        case recurring, import_, fints, review, settings, about
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    Text(#L("Mehr"))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                    ], spacing: 16) {
                        ForEach(items, id: \.title) { item in
                            NavigationLink(value: item.destination) {
                                VStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(item.color.opacity(0.15))
                                        .frame(width: 48, height: 48)
                                        .overlay {
                                            Image(systemName: item.icon)
                                                .font(.title3)
                                                .foregroundStyle(item.color)
                                        }

                                    Text(L(item.title))
                                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                                        .foregroundStyle(WimgTheme.text)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .wimgCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(WimgTheme.bg)
            .navigationDestination(for: Destination.self) { dest in
                destinationView(for: dest)
            }
            .onChange(of: popToRoot) { path = NavigationPath() }
        }
    }

    @ViewBuilder
    private func destinationView(for destination: Destination) -> some View {
        switch destination {
        case .recurring:
            RecurringView()
        case .import_:
            ImportView()
        case .fints:
            FinTSView()
        case .review:
            ReviewView(selectedAccount: $selectedAccount)
        case .settings:
            SettingsView()
        case .about:
            AboutView()
        }
    }
}
