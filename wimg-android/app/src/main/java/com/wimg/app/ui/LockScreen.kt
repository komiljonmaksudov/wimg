package com.wimg.app.ui

import com.wimg.app.ui.theme.Wimg
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import com.wimg.app.i18n.L
import com.wimg.app.services.BiometricLock

/**
 * Full-screen gate shown while the app is locked. Single Entsperren button
 * re-triggers the biometric prompt — useful if the user dismissed it.
 */
@Composable
fun LockScreen(activity: FragmentActivity) {
    val context = LocalContext.current
    val method = BiometricLock.availableMethod(context)
    val hasMethod = method != BiometricLock.AvailableMethod.NONE

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            modifier = Modifier
                .size(112.dp)
                .clip(CircleShape)
                .background(Wimg.colors.accentSoft.copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (hasMethod) Icons.Outlined.Fingerprint else Icons.Outlined.Lock,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f),
                modifier = Modifier.size(44.dp),
            )
        }
        Spacer(Modifier.height(20.dp))
        Text(
            "wimg",
            fontSize = 34.sp,
            fontWeight = FontWeight.Black,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            if (hasMethod) L("App ist gesperrt") else L("Gerätesperre nicht eingerichtet"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        if (!hasMethod) {
            Spacer(Modifier.height(8.dp))
            Text(
                L("Richte in den Geräte-Einstellungen eine PIN, ein Muster oder einen Fingerabdruck ein."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(40.dp))
        if (hasMethod) {
            Button(
                onClick = { BiometricLock.authenticate(activity) },
                colors = ButtonDefaults.buttonColors(
                    containerColor = Wimg.colors.accentSoft,
                    contentColor = Wimg.colors.text,
                ),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Outlined.Lock, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(L("Entsperren"), fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
            }
        } else {
            Button(
                onClick = {
                    context.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                },
                colors = ButtonDefaults.buttonColors(
                    containerColor = Wimg.colors.accentSoft,
                    contentColor = Wimg.colors.text,
                ),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(L("Geräte-Einstellungen öffnen"), fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 4.dp))
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { BiometricLock.setEnabled(context, false) },
                shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(L("App-Sperre deaktivieren"), modifier = Modifier.padding(vertical = 4.dp))
            }
        }
    }
}
