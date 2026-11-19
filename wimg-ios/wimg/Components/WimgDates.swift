import Foundation
import WimgI18n

/// Date labels for the redesign, as Android's `WimgDates`. Copy rule: "Heute" /
/// "Gestern" for the last two days, otherwise "12. Nov."; the year only when
/// it isn't the current one. libwimg dates are "YYYY-MM-DD" (no time).
enum WimgDates {
    private static var en: Bool { UserDefaults.standard.string(forKey: "wimg_locale") == "en" }
    private static var locale: Locale { Locale(identifier: en ? "en_US" : "de_DE") }
    private static let cal = Calendar(identifier: .gregorian)

    static func shortMonths() -> [String] {
        let f = DateFormatter(); f.locale = locale
        return f.shortStandaloneMonthSymbols.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
    }

    static func months() -> [String] {
        let f = DateFormatter(); f.locale = locale
        return f.standaloneMonthSymbols
    }

    static func parse(_ iso: String) -> Date? {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func iso(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func todayIso() -> String { iso(Date()) }

    /// "12. Nov." (German), "12 Nov" (English). No-break space: never splits.
    static func dayMonth(_ day: Int, _ month: Int) -> String {
        let m = shortMonths()[month - 1]
        return en ? "\(day)\u{00A0}\(m)" : "\(day).\u{00A0}\(m)."
    }

    /// "27.10." (German), "27 Oct" (English): for compact ranges.
    static func numeric(_ day: Int, _ month: Int) -> String {
        en ? "\(day)\u{00A0}\(shortMonths()[month - 1])" : String(format: "%02d.%02d.", day, month)
    }

    /// "12. Nov." or "12. Nov. 2025" when not this year.
    static func short(_ iso: String) -> String {
        guard let d = parse(iso) else { return iso }
        let c = cal.dateComponents([.year, .month, .day], from: d)
        let s = dayMonth(c.day!, c.month!)
        return c.year == cal.component(.year, from: Date()) ? s : "\(s) \(c.year!)"
    }

    /// "1. Nov. 2026"
    static func full(_ iso: String) -> String {
        guard let d = parse(iso) else { return iso }
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return "\(dayMonth(c.day!, c.month!)) \(c.year!)"
    }

    /// "Do." (German), "Thu" (English).
    static func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = locale
        let w = f.shortWeekdaySymbols[cal.component(.weekday, from: d) - 1]
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return en ? w : w + "."
    }

    /// Day header: "Heute, Do. 12. Nov.", "Gestern, Mi. 11. Nov.", "Di. 10. Nov."
    static func dayHeader(_ iso: String) -> String {
        guard let d = parse(iso) else { return iso }
        let base = "\(weekday(d)) \(short(iso))"
        switch daysAgo(d) {
        case 0: return "\(L("Heute")), \(base)"
        case 1: return "\(L("Gestern")), \(base)"
        default: return base
        }
    }

    static func daysAgo(_ d: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
    }
}

/// Period labels (Gehaltsmonat), as Android's `PeriodLabels`.
enum PeriodLabels {
    private static func parts(_ iso: String) -> [Int] { iso.split(separator: "-").compactMap { Int($0) } }

    /// "27.10." (German), "27 Oct" (English).
    static func dotted(_ iso: String) -> String {
        let p = parts(iso)
        return p.count == 3 ? WimgDates.numeric(p[2], p[1]) : iso
    }

    /// "27.10.–26.11."; "27 Oct – 26 Nov" in English.
    static func short(_ p: PeriodInfo) -> String {
        UserDefaults.standard.string(forKey: "wimg_locale") == "en"
            ? "\(dotted(p.from)) – \(dotted(p.to))" : "\(dotted(p.from))–\(dotted(p.to))"
    }
}

/// Tells every screen that data changed (category, exclude, undo, sync).
enum Changes {
    static func bump() {
        NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
    }
}

/// What libwimg says "a month" is right now (calendar, salary, fixed day).
/// Shared by every screen, reloaded after each data change.
@MainActor @Observable
final class PeriodState {
    static let shared = PeriodState()
    private(set) var data: Periods?

    func reload() async {
        let p = await Task.detached { LibWimg.getPeriods(count: 12) }.value
        data = p
    }
}
