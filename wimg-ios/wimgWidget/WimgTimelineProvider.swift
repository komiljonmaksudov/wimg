import WidgetKit

struct WimgEntry: TimelineEntry {
    let date: Date
    let data: WidgetPayload
    let masked: Bool
}

/// Reads what the app wrote; refreshes at midnight (days left change) and
/// whenever the app calls `reloadAllTimelines`.
struct WimgTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WimgEntry {
        WimgEntry(date: .now, data: .sample, masked: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WimgEntry) -> Void) {
        let d = WidgetPayload.load()
        // The widget gallery shows sample numbers until the app has written once.
        completion(WimgEntry(date: .now, data: d.hasData ? d : .sample, masked: WidgetPayload.masked))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WimgEntry>) -> Void) {
        let entry = WimgEntry(date: .now, data: WidgetPayload.load(), masked: WidgetPayload.masked)
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

extension WidgetPayload {
    /// Invented demo numbers (Musterbank style) for the gallery and previews.
    static var sample: WidgetPayload {
        var p = WidgetPayload()
        p.mode = "salary"
        p.available = 927.60
        p.expenses = 1912.40
        p.perDay = 54.56
        p.daysLeft = 17
        p.periodDays = 31
        p.periodEnd = "2026-11-27"
        p.categories = [.init(id: 4, amount: 950), .init(id: 1, amount: 412.80), .init(id: 2, amount: 148.20), .init(id: 5, amount: 95.70)]
        p.fixedOpen = 212.40
        p.fixedOpenCount = 3
        p.fixedCount = 8
        p.nextDue = [.init(name: "Grünstrom AG", date: "2026-12-01", amount: -88), .init(name: "Klangwelle", date: "2026-12-04", amount: -9.99)]
        p.todaySum = -28.25
        p.todayCount = 2
        p.todayLast = "Bäckerei Kornfeld"
        p.updatedAt = 1
        return p
    }
}
