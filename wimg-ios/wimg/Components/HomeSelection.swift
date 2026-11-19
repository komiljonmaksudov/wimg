import SwiftUI
import WimgI18n

/// What Übersicht and Rückblick show: a calendar month, a Gehaltsmonat /
/// "Fester Tag" period from libwimg, or a range picked by hand.
struct HomeSelection: Equatable {
    enum Kind: Equatable { case month(Int, Int), period(PeriodInfo), custom }
    let kind: Kind
    let from: String
    let to: String

    static func month(_ y: Int, _ m: Int) -> HomeSelection {
        let p = TxPeriod.month(y, m)
        return HomeSelection(kind: .month(y, m), from: p.from, to: p.to)
    }

    static func period(_ p: PeriodInfo) -> HomeSelection {
        HomeSelection(kind: .period(p), from: p.from, to: p.to)
    }

    static func custom(_ from: String, _ to: String) -> HomeSelection {
        HomeSelection(kind: .custom, from: from, to: to)
    }

    static var thisMonth: HomeSelection {
        let cal = Calendar(identifier: .gregorian), now = Date()
        return .month(cal.component(.year, from: now), cal.component(.month, from: now))
    }

    var isCurrent: Bool {
        let t = WimgDates.todayIso()
        return from <= t && t <= to
    }

    var days: Int {
        guard let a = WimgDates.parse(from), let b = WimgDates.parse(to) else { return 30 }
        return (Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: b).day ?? 29) + 1
    }

    /// Days from today to the last day, today included.
    var daysLeft: Int {
        guard let b = WimgDates.parse(to), let t = WimgDates.parse(WimgDates.todayIso()) else { return 0 }
        return max(0, (Calendar(identifier: .gregorian).dateComponents([.day], from: t, to: b).day ?? 0) + 1)
    }

    /// Days since the start, today counted (all days for a past range).
    var daysIn: Int {
        guard isCurrent, let a = WimgDates.parse(from), let t = WimgDates.parse(WimgDates.todayIso()) else { return days }
        return min(days, max(1, (Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: t).day ?? 0) + 1))
    }

    /// The same-length range just before (for "vs. davor").
    func previous(in periods: Periods?) -> HomeSelection? {
        switch kind {
        case let .month(y, m):
            return m == 1 ? .month(y - 1, 12) : .month(y, m - 1)
        case let .period(p):
            guard let ps = periods?.periods, let i = ps.firstIndex(of: p), i + 1 < ps.count else { return nil }
            return .period(ps[i + 1])
        case .custom:
            let cal = Calendar(identifier: .gregorian)
            guard let a = WimgDates.parse(from) else { return nil }
            let end = cal.date(byAdding: .day, value: -1, to: a)!
            let start = cal.date(byAdding: .day, value: -(days - 1), to: end)!
            return .custom(WimgDates.iso(start), WimgDates.iso(end))
        }
    }

    /// As an Umsätze filter (a tap on a category).
    func txPeriod(salary: Bool) -> TxPeriod {
        switch kind {
        case let .month(y, m): return .month(y, m)
        case let .period(p): return .of(p, salary: salary)
        case .custom: return TxPeriod(from: from, to: to, label: "\(PeriodLabels.dotted(from))–\(PeriodLabels.dotted(to))", key: "c:\(from)")
        }
    }

    /// Short text for the period button: "Nov.", "seit 27.10.", "27.10.–26.11.".
    func buttonText(salary: Bool) -> String {
        switch kind {
        case let .month(y, m):
            let cal = Calendar(identifier: .gregorian)
            let name = WimgDates.shortMonths()[m - 1]
            let short = UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? name : name + (name.count > 4 ? "" : ".")
            return y == cal.component(.year, from: Date()) ? short : "\(short) \(y % 100)"
        case let .period(p):
            return p.isCurrent && salary ? L("seit %s", PeriodLabels.dotted(p.from)) : PeriodLabels.short(p)
        case .custom:
            return "\(PeriodLabels.dotted(from))–\(PeriodLabels.dotted(to))"
        }
    }

    /// Ring: share of the range still ahead; full for a past one.
    var ring: Double { isCurrent ? Double(daysLeft) / Double(max(days, 1)) : 1 }
}
