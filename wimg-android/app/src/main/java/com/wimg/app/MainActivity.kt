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
        applySecureFlag()
        openRequestedRoute(intent)
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
        if (route in OPENABLE) com.wimg.app.ui.components.NavRequest.route = route
    }

    companion object {
        const val EXTRA_ROUTE = "wimg_route"
        const val EXTRA_MONTH = "wimg_month"
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
