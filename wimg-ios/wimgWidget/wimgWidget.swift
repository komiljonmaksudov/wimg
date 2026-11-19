import SwiftUI
import WidgetKit
import WimgI18n

// Widgets of brief 22, option A (boards 18–24, 26): one per purpose.

/// Monat: Bis zum Gehalt (small), Monat (medium), Monat + Kategorien +
/// Fälliges (large), and the lock screen (inline, rectangular, days ring).
/// Keeps the old kind, so widgets already placed stay.
struct WimgWidget: Widget {
    let kind = "WimgWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WimgTimelineProvider()) { entry in
            MonthWidgetView(entry: entry)
        }
        .configurationDisplayName(L("Monat"))
        .description(L("Was bis zum Gehalt oder Monatsende bleibt"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryInline, .accessoryRectangular, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

/// Fixkosten offen (small) and "3 offen" on the lock screen.
struct WimgFixedWidget: Widget {
    let kind = "WimgFixedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WimgTimelineProvider()) { entry in
            FixedWidgetView(entry: entry)
        }
        .configurationDisplayName(L("Fixkosten offen"))
        .description(L("Feste Zahlungen, die in diesem Zeitraum noch kommen"))
        .supportedFamilies([.systemSmall, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

/// Heute (small): what was booked today.
struct WimgTodayWidget: Widget {
    let kind = "WimgTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WimgTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName(L("Heute"))
        .description(L("Was heute gebucht wurde"))
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct wimgWidgetBundle: WidgetBundle {
    var body: some Widget {
        WimgWidget()
        WimgFixedWidget()
        WimgTodayWidget()
    }
}
