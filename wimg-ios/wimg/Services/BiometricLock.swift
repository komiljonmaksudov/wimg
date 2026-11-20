import Foundation
import LocalAuthentication
import SwiftUI
import UIKit

/// Biometric (Face ID / Touch ID) app lock.
///
/// Locks the app behind `LAContext.evaluatePolicy` on cold start, when
/// returning from background, and when re-enabling the toggle. Falls back
/// to device passcode if biometrics aren't enrolled.
///
/// Toggle persisted in `@AppStorage("wimg_lock_enabled")`. Defaults off so
/// no one is surprised — opt-in from Settings.
@MainActor
final class BiometricLock: ObservableObject {
    static let shared = BiometricLock()

    /// True when the gate is up and the main UI should be hidden.
    @Published var isLocked: Bool = UserDefaults.standard.bool(forKey: "wimg_lock_enabled")

    /// True while a privacy overlay should cover the screen (e.g. app
    /// switcher preview). Independent of `isLocked` — the overlay is the
    /// short-lived blank shown when going to background, the lock is the
    /// gate shown when coming back.
    @Published var showPrivacyOverlay: Bool = false

    /// When the app was last sent to background. `nil` while foreground.
    /// Used to apply a grace period before re-locking — quick context
    /// switches (control center, glance at a notification, brief tab to
    /// password manager) don't fire the lock; only absences longer than
    /// `backgroundGrace` do. Mirrors the web build's 30-second grace.
    private var backgroundedAt: Date?

    /// "Sperren nach" (as Android): how long wimg may be away before it locks.
    static let lockAfterKey = "wimg_lock_after_ms"
    static let lockAfterSteps: [Int] = [0, 60_000, 300_000, 900_000]
    @Published var lockAfterMs: Int = UserDefaults.standard.object(forKey: "wimg_lock_after_ms") as? Int ?? 60_000

    func setLockAfter(_ ms: Int) {
        lockAfterMs = ms
        UserDefaults.standard.set(ms, forKey: Self.lockAfterKey)
    }

    /// "Beträge ausblenden" (as Android's secure screen): cover wimg in the app
    /// switcher and while the screen is recorded or mirrored. iOS lets no app
    /// block screenshots. Unset: follows the lock, as on Android.
    static let secureScreenKey = "wimg_secure_screen"
    @Published var secureScreen: Bool = UserDefaults.standard.object(forKey: "wimg_secure_screen") as? Bool
        ?? UserDefaults.standard.bool(forKey: "wimg_lock_enabled")

    func setSecureScreen(_ on: Bool) {
        secureScreen = on
        UserDefaults.standard.set(on, forKey: Self.secureScreenKey)
        updateCaptured()
    }

    /// The screen is being recorded or mirrored.
    @Published private(set) var captured = false

    func updateCaptured() {
        captured = secureScreen && UIScreen.main.isCaptured
    }

    private init() {
        NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in BiometricLock.shared.updateCaptured() }
        }
        Task { @MainActor in updateCaptured() }
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "wimg_lock_enabled")
    }

    enum AvailableMethod {
        case faceID, touchID, passcode, none
    }

    var availableMethod: AvailableMethod {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            // Fall back to device passcode if biometrics unavailable.
            if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) {
                return .passcode
            }
            return .none
        }
        switch ctx.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "wimg_lock_enabled")
        // Engage the lock screen immediately so the user sees Face ID fire
        // right after flipping the toggle — otherwise they'd have to
        // background+foreground the app first, which feels broken.
        isLocked = enabled
    }

    /// Trigger the biometric prompt. On success, unlocks. On failure, stays
    /// locked — the user can retry from the lock screen.
    func authenticate() async {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = NSLocalizedString("Code verwenden", comment: "")
        var err: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        guard ctx.canEvaluatePolicy(policy, error: &err) else { return }
        do {
            let reason = NSLocalizedString("App entsperren", comment: "")
            let ok = try await ctx.evaluatePolicy(policy, localizedReason: reason)
            if ok { isLocked = false }
        } catch {
            // Cancel / failed — leave locked.
        }
    }

    /// Called from the scene-phase observer.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            showPrivacyOverlay = secureScreen
            // Record the start of a background interval instead of locking
            // immediately. The lock is decided when we come back to .active.
            if isEnabled, backgroundedAt == nil {
                backgroundedAt = Date()
            }
        case .inactive:
            // App switcher snapshot is taken in `.inactive` — cover the UI.
            showPrivacyOverlay = secureScreen
        case .active:
            showPrivacyOverlay = false
            if isEnabled, let at = backgroundedAt {
                let elapsed = Date().timeIntervalSince(at)
                if elapsed * 1000 >= Double(lockAfterMs) {
                    isLocked = true
                }
            }
            backgroundedAt = nil
        @unknown default:
            break
        }
    }
}
