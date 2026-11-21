import XCTest

/// Taps through wimg for App Review's screen recording (2026-11-21), on a real
/// iPhone, in English, with demo data in a separate database (WIMG_DB_FILE):
/// the phone's real data is never opened. The bank login screen is left out, so
/// no real login appears. Run by scripts/record-app-review.sh.
final class AppReviewRecording: XCTestCase {
    func testTypicalFlow() {
        let app = XCUIApplication()
        app.launchEnvironment["WIMG_DB_FILE"] = "app-review-demo.db"
        // Argument domain: overrides these settings for this launch only.
        app.launchArguments += ["-wimg_locale", "en", "-wimg_locale_choice", "en", "-wimg_lock_enabled", "NO"]
        app.launch()

        func tap(_ label: String, timeout: TimeInterval = 8) {
            // Cards read their title and description as one label: match the start.
            let exact = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
            let start = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@", label)).firstMatch
            let e = exact.waitForExistence(timeout: 2) ? exact : start
            XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing: \(label)")
            // A tap at the element's centre: tap() first asks iOS to scroll it into
            // view, which fails inside the onboarding pages (kAXErrorCannotComplete).
            e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        func pause(_ s: TimeInterval = 1.6) { Thread.sleep(forTimeInterval: s) }
        func back() {
            let b = app.navigationBars.buttons.firstMatch
            if b.waitForExistence(timeout: 4) { b.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        }

        pause(2)
        tap("Let’s go"); pause()
        tap("Start empty"); pause(1.2)
        tap("Next"); pause()
        tap("Look at demo data"); pause(4)

        // Overview
        app.swipeUp(); pause(); app.swipeDown(); pause()

        // Transactions: open a booking, change its category
        tap("Transactions"); pause()
        app.swipeUp(); pause()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'KORNFELD SUPERMARKT'")).firstMatch
        if row.waitForExistence(timeout: 4) { row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        pause()
        tap("Category"); pause()
        tap("Dining"); pause(2)
        back(); pause()

        // Recurring
        tap("Recurring"); pause()
        tap("FLIMMERKISTE STREAMING"); pause(2)
        back(); pause()

        // More › Review, Import, Settings
        tap("More"); pause()
        tap("Review"); pause(2)
        if app.buttons["Skip"].exists { tap("Skip"); pause() }
        app.swipeUp(); pause()
        back(); pause()
        tap("Import"); pause(2)
        back(); pause()
        tap("Settings"); pause()
        app.swipeUp(); pause(); app.swipeUp(); pause(2)
    }
}
