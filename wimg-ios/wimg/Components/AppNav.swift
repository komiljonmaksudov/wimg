import SwiftUI

/// Where the app is: the selected tab, and a page under Mehr to open next.
/// Search, Übersicht and notifications switch tabs through this.
@MainActor @Observable
final class AppNav {
    static let shared = AppNav()

    var tab: AppTab = .overview
    /// A page under Mehr to open; MoreView pushes it and clears this.
    var morePage: MorePage?

    func open(_ tab: AppTab) { self.tab = tab }

    func open(_ page: MorePage) {
        morePage = page
        tab = .more
    }
}

/// Pages reachable under Mehr (also from Suche).
enum MorePage: Hashable {
    case review, banks, import_, settings, about
    case accounts, rules, devices
}
