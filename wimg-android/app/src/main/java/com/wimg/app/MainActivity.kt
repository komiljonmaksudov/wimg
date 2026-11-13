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
        BiometricLock.initialize(this)
        applySecureFlag()
        setContent {
            WimgTheme {
                Box(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
                    WimgNavigation()
                    if (BiometricLock.isLocked) {
                        LockScreen(activity = this@MainActivity)
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
                SyncService.syncNow(this@MainActivity)
                SyncService.connectWebSocket(this@MainActivity, lifecycleScope)
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
