package com.wimg.app.ui.screens

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.launch
import com.wimg.app.bridge.LibWimg
import com.wimg.app.ui.theme.WimgShapes
import java.io.File
import com.wimg.app.i18n.L

private enum class ThemeMode(val label: String, val value: Int) {
    SYSTEM("System", -1),
    LIGHT("Hell", 1),
    DARK("Dunkel", 2),
}

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences("wimg", 0)
    var theme by remember { mutableStateOf(ThemeMode.entries.find { it.value == prefs.getInt("wimg_theme", -1) } ?: ThemeMode.SYSTEM) }
    var locale by remember { mutableStateOf(prefs.getString("wimg_locale", "de") ?: "de") }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Appearance
        item {
            Text(L("Darstellung"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        item {
            Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(L("Design"), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    ThemeMode.entries.forEach { mode ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(
                                selected = theme == mode,
                                onClick = {
                                    theme = mode
                                    prefs.edit().putInt("wimg_theme", mode.value).apply()
                                    com.wimg.app.ui.theme.ThemeState.mode = mode.value
                                },
                            )
                            Text(L(mode.label), style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }

        item {
            Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(L("Sprache"), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    listOf("de" to "Deutsch", "en" to "English").forEach { (code, label) ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(
                                selected = locale == code,
                                onClick = {
                                    locale = code
                                    prefs.edit().putString("wimg_locale", code).apply()
                                    com.wimg.app.ui.theme.LocaleState.locale = code
                                },
                            )
                            Text(L(label), style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }

        // Security section (Face ID / Fingerprint / device credential)
        item { SecuritySection() }

        // Sync section
        item {
            Spacer(Modifier.height(8.dp))
            Text(L("Synchronisierung"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        item {
            val syncEnabled = com.wimg.app.services.SyncService.isEnabled(context)
            val syncKey = com.wimg.app.services.SyncService.getSyncKey(context)
            var linkInput by remember { mutableStateOf("") }
            var syncing by remember { mutableStateOf(false) }
            val scope = rememberCoroutineScope()

            Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(modifier = Modifier.padding(16.dp)) {
                    if (!syncEnabled) {
                        Button(
                            onClick = {
                                com.wimg.app.services.SyncService.enableSync(context)
                            },
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
                        ) {
                            Text(L("Sync aktivieren"), fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.height(8.dp))
                        OutlinedTextField(
                            value = linkInput,
                            onValueChange = { linkInput = it },
                            label = { Text(L("Sync-Schlüssel einfügen")) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        if (linkInput.isNotBlank()) {
                            Spacer(Modifier.height(8.dp))
                            OutlinedButton(onClick = {
                                com.wimg.app.services.SyncService.setSyncKey(context, linkInput.trim())
                                linkInput = ""
                            }, modifier = Modifier.fillMaxWidth()) {
                                Text(L("Verknüpfen"))
                            }
                        }
                    } else {
                        Text(L("Sync aktiv"), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(4.dp))
                        Text(syncKey ?: "", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(
                                onClick = {
                                    syncing = true
                                    scope.launch {
                                        com.wimg.app.services.SyncService.push(context)
                                        com.wimg.app.services.SyncService.pull(context)
                                        syncing = false
                                    }
                                },
                                enabled = !syncing,
                                modifier = Modifier.weight(1f),
                                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onBackground, contentColor = MaterialTheme.colorScheme.background),
                            ) {
                                Text(L(if (syncing) "Synchronisiere..." else "Jetzt synchronisieren"), fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }
        }

        // Data section
        item {
            Spacer(Modifier.height(8.dp))
            Text(L("Daten"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        item {
            Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column {
                    SettingsRow(icon = Icons.Outlined.FileUpload, title = "CSV exportieren") {
                        val csv = com.wimg.app.bridge.WimgJni.nativeExportCsv() ?: return@SettingsRow
                        shareText(context, csv, "wimg-export.csv")
                    }
                    HorizontalDivider(modifier = Modifier.padding(start = 56.dp))
                    SettingsRow(icon = Icons.Outlined.Storage, title = "Datenbank exportieren") {
                        val json = com.wimg.app.bridge.WimgJni.nativeExportDb() ?: return@SettingsRow
                        shareText(context, json, "wimg-backup.json")
                    }
                }
            }
        }

        // Danger zone
        item {
            Spacer(Modifier.height(8.dp))
            Text(L("Danger Zone"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error)
        }

        item {
            Card(shape = WimgShapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                var showConfirm by remember { mutableStateOf(false) }

                SettingsRow(icon = Icons.Outlined.DeleteForever, title = "Alle Daten löschen", isDestructive = true) {
                    showConfirm = true
                }

                if (showConfirm) {
                    AlertDialog(
                        onDismissRequest = { showConfirm = false },
                        title = { Text(L("Alle Daten löschen?")) },
                        text = { Text(L("Diese Aktion kann nicht rückgängig gemacht werden.")) },
                        confirmButton = {
                            TextButton(onClick = {
                                showConfirm = false
                                try {
                                    LibWimg.close()
                                    val dbFile = File(context.filesDir, "wimg.db")
                                    val walFile = File(context.filesDir, "wimg.db-wal")
                                    val shmFile = File(context.filesDir, "wimg.db-shm")
                                    dbFile.delete()
                                    walFile.delete()
                                    shmFile.delete()
                                    LibWimg.initialize(context)
                                } catch (_: Exception) {}
                            }) {
                                Text(L("Löschen"), color = MaterialTheme.colorScheme.error)
                            }
                        },
                        dismissButton = {
                            TextButton(onClick = { showConfirm = false }) {
                                Text(L("Abbrechen"), color = MaterialTheme.colorScheme.onSurface)
                            }
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    isDestructive: Boolean = false,
    onClick: () -> Unit,
) {
    TextButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = WimgShapes.small,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                icon, contentDescription = null,
                tint = if (isDestructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
            Spacer(Modifier.width(16.dp))
            Text(
                L(title),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = if (isDestructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

private fun shareText(context: android.content.Context, content: String, filename: String) {
    val file = File(context.cacheDir, filename)
    file.writeText(content)
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/*"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Exportieren"))
}

@Composable
private fun SecuritySection() {
    val context = LocalContext.current
    val lock = com.wimg.app.services.BiometricLock
    val method = remember { lock.availableMethod(context) }
    val canUseLock = method != com.wimg.app.services.BiometricLock.AvailableMethod.NONE

    Spacer(Modifier.height(8.dp))
    Text(
        L("Sicherheit"),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(8.dp))
    Card(
        shape = WimgShapes.small,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Outlined.Fingerprint,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(L("App-Sperre"), fontWeight = FontWeight.Bold)
                    Text(
                        when (method) {
                            com.wimg.app.services.BiometricLock.AvailableMethod.BIOMETRIC_STRONG -> L("Mit Fingerabdruck oder Gesicht schützen")
                            com.wimg.app.services.BiometricLock.AvailableMethod.BIOMETRIC_WEAK -> L("Mit Fingerabdruck oder Gesicht schützen")
                            com.wimg.app.services.BiometricLock.AvailableMethod.DEVICE_CREDENTIAL -> L("Mit Gerätecode schützen")
                            com.wimg.app.services.BiometricLock.AvailableMethod.NONE -> L("Nicht verfügbar")
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(
                    checked = lock.isEnabled,
                    enabled = canUseLock,
                    onCheckedChange = { lock.setEnabled(context, it) },
                )
            }
            if (!canUseLock) {
                Spacer(Modifier.height(8.dp))
                Text(
                    L("Kein biometrischer Schutz auf diesem Gerät verfügbar."),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(Modifier.height(12.dp))
            HorizontalDivider()
            Spacer(Modifier.height(12.dp))

            // Widget masking — mirrors iOS "Beträge in Widgets ausblenden".
            val maskPrefs = remember {
                context.getSharedPreferences("wimg_settings", android.content.Context.MODE_PRIVATE)
            }
            var maskAmounts by remember {
                mutableStateOf(maskPrefs.getBoolean("wimg_widget_mask_amounts", false))
            }
            val scope = rememberCoroutineScope()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(L("Beträge in Widgets ausblenden"), fontWeight = FontWeight.Bold)
                    Text(
                        L("Zeigt ••• € statt echter Beträge."),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(
                    checked = maskAmounts,
                    onCheckedChange = { newValue ->
                        maskAmounts = newValue
                        maskPrefs.edit().putBoolean("wimg_widget_mask_amounts", newValue).apply()
                        // Force every widget instance to re-read SharedPreferences.
                        scope.launch {
                            com.wimg.app.widget.WimgSmallWidget().updateAll(context)
                            com.wimg.app.widget.WimgMediumWidget().updateAll(context)
                            com.wimg.app.widget.WimgLargeWidget().updateAll(context)
                        }
                    },
                )
            }

            Spacer(Modifier.height(12.dp))
            HorizontalDivider()
            Spacer(Modifier.height(12.dp))

            // Background FinTS refresh — mirrors iOS "Schnellabfrage im Hintergrund".
            var bgRefresh by remember {
                mutableStateOf(com.wimg.app.services.BackgroundRefresh.isEnabled(context))
            }
            val hasFintsPin = remember {
                com.wimg.app.services.BackgroundRefresh.hasCredentials(context)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(L("Schnellabfrage im Hintergrund"), fontWeight = FontWeight.Bold)
                    Text(
                        L("Holt im Hintergrund neue Umsätze"),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(
                    checked = bgRefresh,
                    enabled = hasFintsPin,
                    onCheckedChange = { newValue ->
                        bgRefresh = newValue
                        com.wimg.app.services.BackgroundRefresh.setEnabled(context, newValue)
                    },
                )
            }
            if (!hasFintsPin) {
                Spacer(Modifier.height(8.dp))
                Text(
                    L("Erst verfügbar, wenn die PIN für die Schnellabfrage gespeichert ist."),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
