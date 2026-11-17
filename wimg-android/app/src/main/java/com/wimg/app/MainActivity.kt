package com.wimg.app

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import com.wimg.app.services.BiometricLock
import com.wimg.app.services.SyncService
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import com.wimg.app.ui.LockScreen
import com.wimg.app.ui.navigation.WimgNavigation
import com.wimg.app.ui.theme.WimgTheme

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Phones stay upright: band, sheet and bar are laid out for portrait, and in
        // landscape the band filled the screen and the places menu ran under the
        // camera. Tablets and foldables (600 dp+) still rotate; Android 16 ignores
        // the lock there anyway.
        if (resources.configuration.smallestScreenWidthDp < 600) requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        enableEdgeToEdge()
        // Belt and braces for vendor "force dark" modes (HyperOS): wimg themes itself.
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) window.decorView.isForceDarkAllowed = false
        // Hand-over from the system splash: remember how big the splash drew the
        // pocket (HyperOS draws it smaller than stock Android), so LaunchIntro can
        // start from exactly that size.
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { view ->
                val icon = view.iconView
                if (icon != null && icon.width > 0) com.wimg.app.ui.components.LaunchIntroState.splashIconPx = icon.width
                // Two frames: the intro recomposes at the splash's size, then the splash goes.
                view.postOnAnimation { view.postOnAnimation { view.remove() } }
            }
        }
        BiometricLock.initialize(this)
        FrameWatch.attach(this)
        applySecureFlag()
        openRequestedRoute(intent)
        // Language and theme before the first frame: WimgTheme read them in an
        // effect, after it. On an English phone the first frame was German, and
        // text chosen then stayed German (the squirrel's line on a cold start).
        com.wimg.app.ui.theme.LocaleState.locale = com.wimg.app.ui.theme.LocaleState.stored(this)
        com.wimg.app.ui.theme.ThemeState.mode = getSharedPreferences("wimg", 0).getInt("wimg_theme", -1)
        setContent {
            WimgTheme {
                Box(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
                    WimgNavigation()
                    if (BiometricLock.isLocked) {
                        LockScreen(activity = this@MainActivity)
                        // The lock is its own moment; no intro on top of it.
                        androidx.compose.runtime.SideEffect { com.wimg.app.ui.components.LaunchIntroState.done = true }
                    } else {
                        com.wimg.app.ui.components.LaunchIntro()
                    }
                }
                // Auto-prompt on cold start when locked.
                LaunchedEffect(BiometricLock.isLocked) {
                    if (BiometricLock.isLocked) {
                        BiometricLock.authenticate(this@MainActivity)
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        openRequestedRoute(intent)
    }

    /** Notifications and widgets name the page to open (e.g. "review", "fints"). */
    private fun openRequestedRoute(intent: android.content.Intent?) {
        val route = intent?.getStringExtra(EXTRA_ROUTE) ?: return
        intent.removeExtra(EXTRA_ROUTE)
        // Month-end notice: open Rückblick on the month it is about ("2026-10").
        intent.getStringExtra(EXTRA_MONTH)?.split("-")?.mapNotNull { it.toIntOrNull() }?.takeIf { it.size == 2 }?.let {
            com.wimg.app.ui.screens.ReviewTarget.ym = it[0] to it[1]
        }
        intent.removeExtra(EXTRA_MONTH)
        // Gehaltsmonat: the period's first day.
        intent.getStringExtra(EXTRA_PERIOD)?.let { com.wimg.app.ui.screens.ReviewTarget.period = it }
        intent.removeExtra(EXTRA_PERIOD)
        if (route in OPENABLE) com.wimg.app.ui.components.NavRequest.route = route
    }

    companion object {
        const val EXTRA_ROUTE = "wimg_route"
        const val EXTRA_MONTH = "wimg_month"
        const val EXTRA_PERIOD = "wimg_period"
        private val OPENABLE = setOf("transactions", "recurring", "review", "fints")
    }

    override fun onPause() {
        super.onPause()
        BiometricLock.onPause()
        SyncService.disconnectWebSocket()
    }

    override fun onResume() {
        super.onResume()
        applySecureFlag()
        BiometricLock.onResume()
        if (BiometricLock.isLocked) {
            BiometricLock.authenticate(this)
        }
        // Fresh transactions without a tap: when the last bank fetch is over 4 h old
        // (after the first frame, so opening stays instant).
        lifecycleScope.launch {
            kotlinx.coroutines.delay(1_500)
            if (!BiometricLock.isLocked) com.wimg.app.ui.screens.fetchOnOpen(applicationContext)
        }
        // Pull what other devices changed while we were away, then stay live.
        // Failures stay quiet here (offline is normal); Settings shows the state.
        if (SyncService.isEnabled(this)) {
            lifecycleScope.launch {
                val r = SyncService.syncNow(this@MainActivity)
                if (r.removed) {
                    com.wimg.app.ui.components.Dock.error(
                        com.wimg.app.i18n.__t("wimg Sync beendet"),
                        com.wimg.app.i18n.__t("Dieses Gerät wurde entfernt oder der Schlüssel ersetzt. Deine Daten bleiben hier."),
                    )
                } else SyncService.connectWebSocket(this@MainActivity, lifecycleScope)
            }
        }
    }

    /**
     * FLAG_SECURE: blanks the recents thumbnail (system shows a black panel
     * instead of the live UI) and prevents screenshots / screen recording.
     * Applied only when the user has opted into the app lock.
     */
    private fun applySecureFlag() {
        if (BiometricLock.secureScreen) {
            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}

/**
 * Measuring aid, off unless files/frames-on exists (see
 * .claude/rules/android-performance.md): logs every frame ≥ 25 ms with its
 * phases, the page shown and how long ago it opened (tag "wimg-frame"), and
 * main-thread libwimg calls ≥ 8 ms (tag "wimg-jank").
 */
object FrameWatch {
    @Volatile var route: String? = null
    @Volatile var changedAt: Long = 0L
    @Volatile var enabled = false

    fun attach(activity: android.app.Activity) {
        enabled = java.io.File(activity.filesDir, "frames-on").exists()
        // files/trace-on present: record a 20 s sampling trace into files/wimg.trace.
        val flag = java.io.File(activity.filesDir, "trace-on")
        if (flag.exists()) {
            flag.delete()
            android.os.Debug.startMethodTracingSampling(java.io.File(activity.filesDir, "wimg.trace").path, 64 shl 20, 1000)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ android.os.Debug.stopMethodTracing(); android.util.Log.w("wimg-frame", "trace written") }, 20_000)
        }
        if (!enabled || android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return
        val thread = android.os.HandlerThread("frame-watch").apply { start() }
        activity.window.addOnFrameMetricsAvailableListener({ _, m, _ ->
            val totalMs = m.getMetric(android.view.FrameMetrics.TOTAL_DURATION) / 1_000_000
            if (totalMs < 25) return@addOnFrameMetricsAvailableListener
            val draw = m.getMetric(android.view.FrameMetrics.DRAW_DURATION) / 1_000_000
            val sinceNav = (System.nanoTime() - changedAt) / 1_000_000
            val wait = m.getMetric(android.view.FrameMetrics.UNKNOWN_DELAY_DURATION) / 1_000_000
            val input = m.getMetric(android.view.FrameMetrics.INPUT_HANDLING_DURATION) / 1_000_000
            val anim = m.getMetric(android.view.FrameMetrics.ANIMATION_DURATION) / 1_000_000
            val layout = m.getMetric(android.view.FrameMetrics.LAYOUT_MEASURE_DURATION) / 1_000_000
            val sync = m.getMetric(android.view.FrameMetrics.SYNC_DURATION) / 1_000_000
            val gpu = (m.getMetric(android.view.FrameMetrics.COMMAND_ISSUE_DURATION) + m.getMetric(android.view.FrameMetrics.SWAP_BUFFERS_DURATION)) / 1_000_000
            android.util.Log.w("wimg-frame", "${totalMs} ms wait=$wait input=$input anim=$anim layout=$layout draw=$draw sync=$sync gpu=$gpu on $route +${sinceNav}ms")
        }, android.os.Handler(thread.looper))
    }
}
