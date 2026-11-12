package com.wimg.app.services

import android.content.Context
import android.content.SharedPreferences
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * Biometric (Fingerprint / Face / device credential) app lock.
 *
 * Mirrors iOS `BiometricLock`: opt-in via Settings, gates the app on cold
 * start and when returning from background. Settings toggle persisted in
 * SharedPreferences under `wimg_lock_enabled`.
 *
 * Combined with `Window.FLAG_SECURE` in MainActivity, the recents thumbnail
 * is blanked while the toggle is on (also prevents screenshots).
 */
object BiometricLock {
    private const val PREFS = "wimg_settings"
    private const val KEY_ENABLED = "wimg_lock_enabled"
    /**
     * Quick context switches (notification shade, control center, hop to a
     * password manager) shouldn't fire the biometric prompt every time.
     * Only background spans longer than this trigger re-lock. Mirrors the
     * iOS BiometricLock + web LockScreen grace.
     */
    private const val DEFAULT_LOCK_AFTER_MS = 60_000L
    private const val KEY_LOCK_AFTER = "wimg_lock_after_ms"
    private const val KEY_DEVICE_ONLY = "wimg_lock_device_only"
    private const val KEY_SECURE_SCREEN = "wimg_secure_screen"

    /** How long the app may be in the background before it locks again ("Sperren nach"). */
    var lockAfterMs by mutableStateOf(DEFAULT_LOCK_AFTER_MS)
        private set

    /** Unlock with the device PIN only, never biometrics ("Nur Geräte-PIN"). */
    var deviceOnly by mutableStateOf(false)
        private set

    /**
     * Hide amounts in the system's app overview and block screenshots
     * (FLAG_SECURE). Older installs tied this to the lock, so it defaults to
     * the lock's state until the user sets it.
     */
    var secureScreen by mutableStateOf(false)
        private set

    /** True when the gate is up and the main UI should be hidden. */
    var isLocked by mutableStateOf(false)
        private set

    /** Loaded once at process start by [initialize]. */
    var isEnabled by mutableStateOf(false)
        private set

    /** Unix-millis when the activity last went to background. 0 = foreground. */
    private var backgroundedAt: Long = 0L

    enum class AvailableMethod { BIOMETRIC_STRONG, BIOMETRIC_WEAK, DEVICE_CREDENTIAL, NONE }

    fun initialize(context: Context) {
        val prefs = prefs(context)
        isEnabled = prefs.getBoolean(KEY_ENABLED, false)
        lockAfterMs = prefs.getLong(KEY_LOCK_AFTER, DEFAULT_LOCK_AFTER_MS)
        deviceOnly = prefs.getBoolean(KEY_DEVICE_ONLY, false)
        secureScreen = prefs.getBoolean(KEY_SECURE_SCREEN, isEnabled)
        // Start locked if the user enabled it — first authenticate() unlocks.
        isLocked = isEnabled
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        isEnabled = enabled
        // Engage the lock immediately so the user sees it work right after
        // flipping the toggle — otherwise they'd have to background the app
        // first, which feels broken.
        isLocked = enabled
    }

    fun setLockAfter(context: Context, ms: Long) {
        prefs(context).edit().putLong(KEY_LOCK_AFTER, ms).apply()
        lockAfterMs = ms
    }

    fun setDeviceOnly(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean(KEY_DEVICE_ONLY, on).apply()
        deviceOnly = on
    }

    fun setSecureScreen(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean(KEY_SECURE_SCREEN, on).apply()
        secureScreen = on
    }

    fun availableMethod(context: Context): AvailableMethod {
        val mgr = BiometricManager.from(context)
        if (mgr.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            == BiometricManager.BIOMETRIC_SUCCESS) return AvailableMethod.BIOMETRIC_STRONG
        // Most Android emulators (and some real devices) only report class 2
        // fingerprint = BIOMETRIC_WEAK. Without this branch the prompt would
        // ignore the enrolled fingerprint and accept only the device PIN.
        if (mgr.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
            == BiometricManager.BIOMETRIC_SUCCESS) return AvailableMethod.BIOMETRIC_WEAK
        if (mgr.canAuthenticate(BiometricManager.Authenticators.DEVICE_CREDENTIAL)
            == BiometricManager.BIOMETRIC_SUCCESS) return AvailableMethod.DEVICE_CREDENTIAL
        return AvailableMethod.NONE
    }

    /** Called when the activity is in foreground — show prompt if locked. */
    fun authenticate(activity: FragmentActivity) {
        if (!isLocked) return
        val detected = availableMethod(activity)
        val credentialOk = BiometricManager.from(activity)
            .canAuthenticate(BiometricManager.Authenticators.DEVICE_CREDENTIAL) == BiometricManager.BIOMETRIC_SUCCESS
        val method = if (deviceOnly && credentialOk) AvailableMethod.DEVICE_CREDENTIAL else detected
        if (method == AvailableMethod.NONE) {
            // Nothing enrolled. Don't auto-unlock — that would silently
            // disable security. Instead leave the LockScreen up so the user
            // sees the "Set up screen lock" message + button.
            return
        }

        val executor = ContextCompat.getMainExecutor(activity)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                isLocked = false
            }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                // User cancelled / negative button — leave locked. Lock screen
                // gives them an Entsperren button to retry.
            }
        }

        val prompt = BiometricPrompt(activity, executor, callback)
        // BIOMETRIC_STRONG combines with DEVICE_CREDENTIAL natively.
        // BIOMETRIC_WEAK cannot — pairing them throws IllegalArgumentException.
        // So WEAK runs alone; if the user wants PIN fallback they re-tap.
        val authenticators = when (method) {
            AvailableMethod.BIOMETRIC_STRONG -> BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
            AvailableMethod.BIOMETRIC_WEAK -> BiometricManager.Authenticators.BIOMETRIC_WEAK
            AvailableMethod.DEVICE_CREDENTIAL -> BiometricManager.Authenticators.DEVICE_CREDENTIAL
            AvailableMethod.NONE -> return
        }

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("wimg")
            .setSubtitle("App entsperren")
            .apply {
                // BIOMETRIC_WEAK alone can't use setAllowedAuthenticators with
                // DEVICE_CREDENTIAL → need a negative button instead.
                if (method == AvailableMethod.BIOMETRIC_WEAK) {
                    setNegativeButtonText("Abbrechen")
                }
            }
            .setAllowedAuthenticators(authenticators)
            .build()

        prompt.authenticate(info)
    }

    /** Called from Activity.onPause — record when we leave the foreground. */
    fun onPause() {
        if (isEnabled && backgroundedAt == 0L) {
            backgroundedAt = System.currentTimeMillis()
        }
    }

    /** Called from Activity.onResume — re-lock only after a real absence. */
    fun onResume() {
        if (!isEnabled) {
            backgroundedAt = 0L
            return
        }
        val at = backgroundedAt
        backgroundedAt = 0L
        if (at == 0L) return
        if (System.currentTimeMillis() - at >= lockAfterMs) {
            isLocked = true
        }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
