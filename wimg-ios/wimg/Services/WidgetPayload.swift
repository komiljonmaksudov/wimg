import Foundation

/// What the widgets show, written by the app (WidgetDataWriter) after every
/// change and read by the widget extension, which never calls libwimg. One JSON
/// in the App Group. Same content as Android's WidgetData.kt, plus what the iOS
/// boards add ("3 von 8", the next payments, today's last booking).
/// Compiled into both targets (project.yml).
struct WidgetPayload: Codable {
    struct Category: Codable, Hashable { let id: Int; let amount: Double }
    struct Due: Codable, Hashable { let name: String; let date: String; let amount: Double }

    /// Gehaltsmonat: "calendar", "salary" or "day" (`startDay`).
    var mode = "calendar"
    var startDay = 1
    var month = 0
    var available = 0.0
    /// Spent in the period, positive.
    var expenses = 0.0
    /// Gehaltsmonat: left per remaining day. Calendar: spent per day so far.
    var perDay = 0.0
    var daysLeft = 0
    var periodDays = 0
    /// Last day of the period, ISO.
    var periodEnd = ""
    /// Spending per category, largest first.
    var categories: [Category] = []
    var fixedOpen = 0.0
    var fixedOpenCount = 0
    var fixedCount = 0
    /// The next recurring payments from today, soonest first.
    var nextDue: [Due] = []
    var todaySum = 0.0
    var todayCount = 0
    var todayLast: String?
    /// Salary is late: the day of the month it usually comes, else 0.
    var overdueDay = 0
    /// Unix seconds; 0 = never written.
    var updatedAt = 0.0

    var hasData: Bool { updatedAt > 0 }

    static let suite = "group.com.wimg.app"
    static let key = "wimg_widget_data_v2"
    /// Einstellungen › "Beträge in Widgets ausblenden".
    static let maskKey = "wimg_widget_mask_amounts"

    static func load() -> WidgetPayload {
        guard let d = UserDefaults(suiteName: suite)?.data(forKey: key),
              let p = try? JSONDecoder().decode(WidgetPayload.self, from: d) else { return WidgetPayload() }
        return p
    }

    static var masked: Bool { UserDefaults(suiteName: suite)?.bool(forKey: maskKey) ?? false }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.suite),
              let d = try? JSONEncoder().encode(self) else { return }
        defaults.set(d, forKey: Self.key)
        defaults.removeObject(forKey: "wimg_widget_data") // the old format
    }
}
