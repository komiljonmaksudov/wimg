import Foundation
import WidgetKit

/// Computes what the widgets show and hands it to them (they never touch
/// libwimg). Same rules as Android's WidgetDataWriter.kt.
enum WidgetDataWriter {
    static func writeSummary() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let dayOfMonth = cal.component(.day, from: now)
        let today = WimgDates.iso(now)
        let monthDays = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let monthStart = String(format: "%04d-%02d-01", year, month)
        let monthEnd = String(format: "%04d-%02d-%02d", year, month, monthDays)

        // Gehaltsmonat: the running salary or "Fester Tag" period instead of the month.
        let periods = LibWimg.getPeriods(count: 2)
        let period = periods.flatMap { $0.isCalendar ? nil : $0.current }
        let summary: MonthlySummary
        if let p = period, let s = LibWimg.getSummaryRange(from: p.from, to: p.to, account: nil) {
            summary = s
        } else {
            summary = LibWimg.getSummaryFiltered(year: year, month: month, account: nil)
        }
        let spent = abs(summary.expenses)
        let from = period?.from ?? monthStart
        let to = period?.to ?? monthEnd
        let daysLeft = daysBetween(today, to, cal) + 1
        let periodDays = period?.days ?? monthDays

        // by_category holds spending as positive amounts (same filter as Home).
        let categories = summary.by_category
            .filter { $0.amount > 0.004 && $0.id != WimgCategory.income.rawValue }
            .sorted { $0.amount > $1.amount }
            .map { WidgetPayload.Category(id: $0.id, amount: abs($0.amount)) }

        // Same rule as the recurring page's "Noch offen".
        let fixed = LibWimg.getRecurring().filter { $0.isActive && !$0.isHidden && $0.amount < 0 }
        func inRange(_ d: String?) -> Bool { guard let d else { return false }; return d >= from && d <= to }
        let due = fixed.filter { inRange($0.last_seen) || inRange($0.next_due) || $0.interval == "monthly" }
        let open = due.filter { !inRange($0.last_seen) }
        let next = fixed.filter { ($0.next_due ?? "") >= today }
            .sorted { ($0.next_due ?? "") < ($1.next_due ?? "") }
            .prefix(3)
            .map { WidgetPayload.Due(name: $0.displayName, date: $0.next_due ?? "", amount: $0.amount) }

        let todayTx = ((try? LibWimg.getTransactionsFiltered(account: nil)) ?? [])
            .filter { $0.date == today && !$0.isExcluded }

        var p = WidgetPayload()
        p.mode = periods?.mode ?? "calendar"
        p.startDay = periods?.day ?? 1
        p.month = month
        p.available = summary.available
        p.expenses = spent
        // Calendar: spent per day so far. Gehaltsmonat: what is left per remaining day.
        p.perDay = period != nil ? (daysLeft > 0 ? summary.available / Double(daysLeft) : 0) : spent / Double(dayOfMonth)
        p.daysLeft = max(0, daysLeft)
        p.periodDays = periodDays
        p.periodEnd = to
        p.categories = categories
        p.fixedOpen = open.reduce(0) { $0 + abs($1.amount) }
        p.fixedOpenCount = open.count
        p.fixedCount = due.count
        p.nextDue = Array(next)
        p.todaySum = todayTx.reduce(0) { $0 + $1.amount }
        p.todayCount = todayTx.count
        p.todayLast = todayTx.first?.displayTitle
        if let s = periods?.salary, periods?.isSalary == true, (s.overdue_days ?? 0) > 0 { p.overdueDay = s.day ?? 0 }
        p.updatedAt = now.timeIntervalSince1970
        p.save()

        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func daysBetween(_ a: String, _ b: String, _ cal: Calendar) -> Int {
        guard let da = WimgDates.parse(a), let db = WimgDates.parse(b) else { return 0 }
        return cal.dateComponents([.day], from: da, to: db).day ?? 0
    }
}
