import SwiftUI
import WimgI18n

/// Mehr (board 05 of brief 22): Rückblick, Banken, Import; Einstellungen, Über wimg.
struct MoreView: View {
    @Binding var selectedAccount: String?
    var popToRoot: UUID
    @State private var path = NavigationPath()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        NavigationStack(path: $path) {
            BandScreen(title: #L("Mehr"), largeTitle: true) {
                EmptyView()
            } sheet: {
                WimgGroup {
                    row(.review, #L("Rückblick"), #L("Deine Monate im Rückblick"), "chart.bar.xaxis", Wimg.category(2))
                    RowDivider()
                    row(.banks, #L("Banken"), #L("Bankverbindung und Abruf"), "building.columns", Wimg.accent)
                    RowDivider()
                    row(.import_, #L("Import"), #L("CSV oder Kontoauszug"), "square.and.arrow.down", Wimg.text2)
                }
                Spacer().frame(height: 16)
                WimgGroup {
                    row(.settings, #L("Einstellungen"), #L("Sync, App-Sperre, Export"), "gearshape", Wimg.text2)
                    RowDivider()
                    row(.about, #L("Über wimg"), "Version \(version)", "info.circle", Wimg.text2)
                }
            }
            .navigationDestination(for: MorePage.self) { destination($0) }
            .onChange(of: popToRoot) { path = NavigationPath() }
            .onChange(of: AppNav.shared.morePage, initial: true) {
                // Another tab (Suche) asked for a page under Mehr.
                guard let page = AppNav.shared.morePage else { return }
                path = NavigationPath()
                path.append(page)
                AppNav.shared.morePage = nil
            }
        }
    }

    private func row(_ d: MorePage, _ title: String, _ desc: String, _ icon: String, _ tint: Color) -> some View {
        WimgRow(title: title, desc: desc, chevron: true, action: { path.append(d) }) {
            IconTile(systemImage: icon, tint: tint)
        }
    }

    @ViewBuilder
    private func destination(_ d: MorePage) -> some View {
        switch d {
        case .review: ReviewView(selectedAccount: $selectedAccount)
        case .banks: FinTSView()
        case .import_: ImportView()
        case .settings: SettingsView()
        case .about: AboutView()
        case .accounts: AccountsView()
        case .rules: RulesView()
        case .devices: SyncDevicesView()
        case .faq: AboutFAQView()
        case .privacy: AboutPrivacyView()
        case .licenses: AboutLicensesView()
        }
    }
}
