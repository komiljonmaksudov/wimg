import Foundation
import UserNotifications
import WimgI18n

/// Every notice wimg sends goes through here: the kind must be switched on
/// (Einstellungen › Mitteilungen), it must not be the quiet time, and a tap
/// opens the right page. Same keys as Android (BackgroundRefresh.kt).
enum Notifier {
    enum Kind: String, CaseIterable {
        case newTx = "wimg_notify_new_tx"
        case tan = "wimg_notify_tan"
        case monthEnd = "wimg_notify_month_end"
        case price = "wimg_notify_price"
    }

    static let quietKey = "wimg_quiet_hours"
    private static let priceKey = "wimg_price_notified"
    static let routeKey = "wimg_route"
    private static let monthEndId = "wimg-month-end"

    static func isOn(_ kind: Kind) -> Bool {
        UserDefaults.standard.object(forKey: kind.rawValue) as? Bool ?? true
    }

    static func set(_ kind: Kind, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: kind.rawValue)
        if kind == .monthEnd { Task { await scheduleMonthEnd() } }
    }

    /// Start and end hour of the quiet time ("22-8"), nil when off.
    static var quietHours: (from: Int, to: Int)? {
        get {
            let p = (UserDefaults.standard.string(forKey: quietKey) ?? "").split(separator: "-").compactMap { Int($0) }
            return p.count == 2 ? (p[0], p[1]) : nil
        }
        set {
            UserDefaults.standard.set(newValue.map { "\($0.from)-\($0.to)" } ?? "", forKey: quietKey)
            Task { await scheduleMonthEnd() }
        }
    }

    static func inQuietHours(_ date: Date = Date()) -> Bool {
        guard let q = quietHours else { return false }
        let h = Calendar.current.component(.hour, from: date)
        return q.from <= q.to ? (q.from..<q.to).contains(h) : (h >= q.from || h < q.to)
    }

    /// Sends now. False when switched off, in the quiet time or not allowed.
    @discardableResult
    static func post(_ kind: Kind, title: String, body: String, route: String) async -> Bool {
        guard isOn(kind), !inQuietHours() else { return false }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [routeKey: route]
        try? await center.add(UNNotificationRequest(identifier: kind.rawValue + "-" + UUID().uuidString, content: content, trigger: nil))
        return true
    }

    // MARK: Month end ("Dein Oktober ist abgeschlossen")

    /// Plans the notice for the 1st of next month at 9:00 (or when the quiet
    /// time ends), naming this month. Called on every app start: it replaces
    /// the one planned before, so it always names the right month.
    static func scheduleMonthEnd() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [monthEndId])
        guard isOn(.monthEnd), await center.notificationSettings().authorizationStatus == .authorized else { return }
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let y = cal.component(.year, from: now), m = cal.component(.month, from: now)
        // Nothing booked this month: nothing to look back on.
        guard LibWimg.getSummaryFiltered(year: y, month: m, account: nil).tx_count > 0,
              let next = cal.date(byAdding: .month, value: 1, to: cal.date(from: DateComponents(year: y, month: m, day: 1))!) else { return }
        var hour = 9
        if let q = quietHours, (q.from <= q.to ? (q.from..<q.to).contains(9) : (9 >= q.from || 9 < q.to)) { hour = q.to }
        var when = cal.dateComponents([.year, .month, .day], from: next)
        when.hour = hour
        let monthName = WimgDates.months()[m - 1]
        let content = UNMutableNotificationContent()
        content.title = L("Dein %s ist abgeschlossen", monthName)
        content.body = L("Tippe für deinen Monatsabschluss.")
        content.sound = .default
        content.userInfo = [routeKey: "review"]
        try? await center.add(UNNotificationRequest(identifier: monthEndId, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
    }

    // MARK: Price rises

    /// After a fetch: one notice per fixed cost that got more expensive,
    /// once per pattern and new price.
    static func notifyPriceRises() async {
        guard isOn(.price) else { return }
        var seen = Set(UserDefaults.standard.stringArray(forKey: priceKey) ?? [])
        for p in LibWimg.getRecurring() where !p.isHidden && p.isPriceUp {
            let key = "\(p.id):\(Int((abs(p.amount) * 100).rounded()))"
            guard !seen.contains(key) else { continue }
            let hide = UserDefaults(suiteName: WidgetPayload.suite)?.bool(forKey: WidgetPayload.maskKey) ?? false
            let body = hide || p.prev_amount == nil
                ? L("Neuer Betrag bei %s.", p.displayName)
                : L("%s: %s statt %s.", p.displayName, amountText(abs(p.amount), showPlus: false), amountText(abs(p.prev_amount ?? 0), showPlus: false))
            if await post(.price, title: L("Preis gestiegen"), body: body, route: "recurring") {
                seen.insert(key)
            }
        }
        UserDefaults.standard.set(Array(seen.suffix(40)), forKey: priceKey)
    }
}

/// Opens the page a tapped notice names (wimg_route), shows notices while open.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo[Notifier.routeKey] as? String
        await MainActor.run {
            switch route {
            case "review": AppNav.shared.open(.review)
            case "recurring": AppNav.shared.open(.recurring)
            case "transactions": AppNav.shared.open(.transactions)
            case "banks": AppNav.shared.open(.banks)
            default: break
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
