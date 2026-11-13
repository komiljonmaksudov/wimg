package com.wimg.app.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import com.wimg.app.R
import com.wimg.app.i18n.L
import com.wimg.app.services.BiometricLock
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType

/**
 * Full-screen gate while the app is locked (board 13): dark, the app icon, one
 * line on what's hidden, the fingerprint as a second way in, and the main
 * action where the bar always is.
 */
@Composable
fun LockScreen(activity: FragmentActivity) {
    val context = LocalContext.current
    val c = Wimg.colors
    val hasMethod = BiometricLock.availableMethod(context) != BiometricLock.AvailableMethod.NONE
    val unlock = { BiometricLock.authenticate(activity) }

    Box(Modifier.fillMaxSize().background(c.band).systemBarsPadding().padding(horizontal = 16.dp)) {
        Column(
            Modifier.fillMaxWidth().align(Alignment.TopCenter).padding(top = 140.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // The launcher's two layers; painterResource can't draw an adaptive icon.
            // Adaptive layers are 108dp canvases with a 72dp visible middle: draw them
            // at 108/72 of the tile and crop.
            Box(Modifier.size(80.dp).clip(RoundedCornerShape(20.dp)), contentAlignment = Alignment.Center) {
                Image(painterResource(R.mipmap.ic_launcher_background), null, Modifier.requiredSize(120.dp))
                Image(painterResource(R.mipmap.ic_launcher_foreground), null, Modifier.requiredSize(120.dp))
            }
            Spacer(Modifier.height(28.dp))
            Text(
                if (hasMethod) L("wimg ist gesperrt") else L("Gerätesperre nicht eingerichtet"),
                style = WimgType.title, color = Color.White, textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                if (hasMethod) L("Beträge sind ausgeblendet, bis du entsperrst.")
                else L("Richte in den Geräte-Einstellungen eine PIN, ein Muster oder einen Fingerabdruck ein."),
                style = WimgType.desc, color = c.bandSub, textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 24.dp),
            )
        }

        if (hasMethod) {
            Column(Modifier.align(Alignment.Center).padding(top = 120.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier.size(88.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.05f))
                        .border(1.dp, Color.White.copy(alpha = 0.14f), CircleShape).pressable(onClick = unlock),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Outlined.Fingerprint, contentDescription = L("Entsperren"), tint = Color.White, modifier = Modifier.size(36.dp))
                }
                Spacer(Modifier.height(14.dp))
                Text(L("Fingerabdruck oder Gesicht"), style = WimgType.desc, color = c.bandSub)
            }
        }

        // Same place and shape as the floating bar.
        Column(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(bottom = 12.dp)
                .clip(WimgShape.bar).background(Color.White.copy(alpha = 0.04f))
                .border(1.dp, Color.White.copy(alpha = 0.10f), WimgShape.bar).padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (hasMethod) {
                LockButton(L("Entsperren"), primary = true, onClick = unlock)
            } else {
                LockButton(L("Geräte-Einstellungen öffnen"), primary = true) { context.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS)) }
                LockButton(L("App-Sperre ausschalten"), primary = false, icon = true) { BiometricLock.setEnabled(context, false) }
            }
        }
    }
}

@Composable
private fun LockButton(label: String, primary: Boolean, icon: Boolean = false, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(
        Modifier.fillMaxWidth().height(52.dp).clip(WimgShape.button)
            .background(if (primary) c.accent else Color.White.copy(alpha = 0.08f)).pressable(onClick = onClick),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon) {
            Icon(Icons.Outlined.Lock, null, tint = Color.White, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(label, style = WimgType.button, color = if (primary) c.onAccent else Color.White)
    }
}
