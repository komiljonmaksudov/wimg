import BackgroundTasks
import UserNotifications
import WimgI18n

/// Weekly silent FinTS refresh via BGAppRefreshTask + local notifications.
///
/// Flow:
///   1. App.init() calls `register()` — sets the system task handler.
///   2. After every successful manual Schnellabfrage, the FinTS view calls
///      `requestNotificationAuthIfNeeded()` (asks for permission in context)
///      and `schedule()` (books the next run ~7 days out).
///   3. iOS wakes us in its own window. The handler runs fintsConnect +
///      fintsFetch using stored credentials. Posts a local notification
///      with the result, then completes the task.
///
/// Why device-driven and not server-driven: FinTS PIN lives in Keychain only,
/// and there's no need to add a new trust boundary just to skip waking the app
/// for 30 seconds once a week. (See decisions.md → Phase 6.9 v2.)
enum BackgroundRefresh {
    static let taskIdentifier = "com.wimg.app.digest"
    /// Floor for next BG run. iOS treats this as a minimum, not the actual
    /// fire time — engaged users will see ~daily delivery, casual users
    /// settle to ~2-3×/week, dormant users get throttled to zero. 24h is the
    /// sweet spot: it lets iOS pick the optimal weekday cadence for each
    /// user instead of us guessing.
    static let intervalSeconds: TimeInterval = 24 * 60 * 60  // 24 hours

    /// Dedupe TAN-required notifications inside this window so a daily BG
    /// run on a TAN-bank doesn't generate seven "TAN erforderlich" banners.
    private static let tanNotifyCooldown: TimeInterval = 24 * 60 * 60
    private static let tanLastNotifiedKey = "wimg_bg_tan_notified_at"

    /// User-controlled opt-out. Default true — the toggle lives in Settings.
    /// Read directly from UserDefaults so the BG handler (running before any
    /// SwiftUI state is built) can honor it.
    static let enabledKey = "wimg_bg_refresh_enabled"
    static var isEnabled: Bool {
        // Default true if the key has never been written.
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Register the BGAppRefreshTask handler. Must be called from App.init()
    /// before the scene is created.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Schedule the next refresh. No-op if credentials aren't stored —
    /// nothing to refresh, no point waking up. Also no-op if the user
    /// has flipped the Settings toggle off.
    static func schedule() {
        guard isEnabled, KeychainService.hasFintsCredentials else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: intervalSeconds)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundRefresh] schedule failed: \(error)")
        }
    }

    /// Cancel any pending refresh. Call when user disables Schnellabfrage or
    /// clears their PIN.
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    /// Ask for notification authorization, but only the first time and only
    /// after a user gesture (e.g. tapping Schnellabfrage). The system prompt
    /// shown at app launch out of nowhere is annoying and gets denied.
    static func requestNotificationAuthIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    // MARK: - Handler

    private enum Outcome {
        case imported(count: Int)
        case tanRequired
        case authFailed
        case silent  // ran fine, nothing new — don't notify

        var completed: Bool { true }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Always schedule the next run first — even if this one fails or is
        // killed, the chain keeps going.
        schedule()

        guard let blz = KeychainService.get(KeychainService.fintsBLZ),
              let user = KeychainService.get(KeychainService.fintsKennung),
              let pin = KeychainService.get(KeychainService.fintsPIN) else {
            task.setTaskCompleted(success: true)
            return
        }

        // FinTS parsing needs a 2MB stack — the default GCD thread (~512KB)
        // overflows on iOS. Same trick as FinTSView.handleFetch.
        let workThread = Thread {
            let outcome = runSilentRefresh(blz: blz, user: user, pin: pin)
            DispatchQueue.main.async {
                postNotification(for: outcome)
                task.setTaskCompleted(success: outcome.completed)
            }
        }
        workThread.stackSize = 2 * 1024 * 1024
        workThread.qualityOfService = .background

        task.expirationHandler = {
            // Best-effort — Thread.cancel() doesn't actually stop the thread,
            // but the system will kill us anyway. Mark task complete so iOS
            // doesn't penalize our scheduling priority next time.
            workThread.cancel()
            task.setTaskCompleted(success: false)
        }

        workThread.start()
    }

    private static func runSilentRefresh(blz: String, user: String, pin: String) -> Outcome {
        do {
            let connect = try LibWimg.fintsConnect(blz: blz, user: user, pin: pin)
            if connect.needsTan { return .tanRequired }
            if !connect.isOk { return .authFailed }

            // Restore TAN medium silently if the bank needs one.
            if connect.tan_medium_required == true,
               let medium = KeychainService.get(KeychainService.fintsTanMedium)
            {
                _ = try? LibWimg.fintsSetTanMedium(name: medium)
            }

            // Background fetches use a tighter 14-day window — we're just
            // catching what's new since the last run.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let to = Date()
            let from = Calendar.current.date(byAdding: .day, value: -14, to: to) ?? to

            let result = try LibWimg.fintsFetch(
                from: formatter.string(from: from),
                to: formatter.string(from: to)
            )

            if result.needsTan { return .tanRequired }
            if result.isError { return .silent }  // don't spam on transient errors

            let imported = result.imported ?? 0
            if imported > 0 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                }
                WidgetDataWriter.writeSummary()
                return .imported(count: imported)
            }
            return .silent
        } catch {
            return .silent
        }
    }

    private static func postNotification(for outcome: Outcome) {
        Task {
            switch outcome {
            case .imported(let count):
                guard count > 0 else { return }
                await Notifier.post(.newTx, title: "wimg",
                                    body: count == 1 ? L("1 neuer Umsatz") : L("%d neue Umsätze", count), route: "transactions")
                await Notifier.notifyPriceRises()
                await Notifier.scheduleMonthEnd()
            case .tanRequired:
                // Once per cooldown, not on every wake-up.
                let last = UserDefaults.standard.double(forKey: tanLastNotifiedKey)
                if last > 0, Date().timeIntervalSince1970 - last < tanNotifyCooldown { return }
                if await Notifier.post(.tan, title: L("TAN erforderlich"), body: L("Öffne wimg, um den Abruf freizugeben."), route: "banks") {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: tanLastNotifiedKey)
                }
            case .authFailed:
                await Notifier.post(.tan, title: "wimg", body: L("Anmeldung abgelaufen — bitte erneut anmelden"), route: "banks")
            case .silent:
                return
            }
        }
    }
}
