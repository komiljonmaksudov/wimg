package com.wimg.app.ui.screens

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.glance.appwidget.updateAll
import androidx.navigation.NavController
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.wimg.app.bridge.LibWimg
import com.wimg.app.bridge.WimgJni
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.services.BackgroundRefresh
import com.wimg.app.services.BiometricLock
import com.wimg.app.services.SyncService
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BandTitle
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.GroupLabel
import com.wimg.app.ui.components.IconTile
import com.wimg.app.ui.components.QuietLine
import com.wimg.app.ui.components.RowDivider
import com.wimg.app.ui.components.WimgGroup
import com.wimg.app.ui.components.WimgRow
import com.wimg.app.ui.components.WimgToggle
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.LocaleState
import com.wimg.app.ui.theme.ThemeState
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgMotion
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

@Composable
private fun SettingsPage(over: String?, title: String, content: @Composable ColumnScope.() -> Unit) {
    BandScreen(band = { BandTitle(over, title) }) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = barClearance()),
            content = content,
        )
    }
}

@Composable
private fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, fill: Boolean = false) {
    val c = Wimg.colors
    // fill: on its own line in a page, full width with equal segments (not a
    // label-wide pill floating in the middle). Inside a row it stays compact.
    Row((if (fill) modifier.fillMaxWidth() else modifier).clip(WimgShape.segmentOuter).background(c.neutralTint).padding(3.dp)) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            Box(
                Modifier
                    .then(if (fill) Modifier.weight(1f) else Modifier)
                    .clip(WimgShape.segmentInner)
                    .background(if (on) c.card else Color.Transparent)
                    .clickable(role = Role.RadioButton) { onSelect(i) }
                    .padding(horizontal = 14.dp, vertical = 9.dp),
                contentAlignment = Alignment.Center,
            ) { Text(label, style = WimgType.chip, color = if (on) c.text else c.text2) }
        }
    }
}

@Composable
private fun ValueText(text: String, color: Color = Wimg.colors.text2) = Text(text, style = WimgType.body, color = color, maxLines = 1)

private fun shareFile(context: Context, content: String, filename: String, mime: String) {
    val file = File(context.cacheDir, filename)
    file.writeText(content)
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mime
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, __t("Exportieren")))
}

private fun backupJson(): String? = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeGetChanges(0) }

private fun appVersion(context: Context): String =
    runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "—"

// ---------------------------------------------------------------------------
// Hub
// ---------------------------------------------------------------------------

@Composable
fun SettingsScreen(navController: NavController? = null) {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences("wimg", 0)
    var theme by remember { mutableIntStateOf(prefs.getInt("wimg_theme", -1)) }
    var languageOpen by remember { mutableStateOf(false) }
    var deleteOpen by remember { mutableStateOf(false) }
    var bgRefresh by remember { mutableStateOf(BackgroundRefresh.isEnabled(context)) }
    val hasPin = remember { BackgroundRefresh.hasCredentials(context) }
    val scope = rememberCoroutineScope()
    val c = Wimg.colors

    BarContribution(
        chip = null,
        panel = when {
            languageOpen -> { { LanguagePanel { languageOpen = false } } }
            deleteOpen -> { { DeleteAllPanel(navController) { deleteOpen = false } } }
            else -> null
        },
        onPanelDismiss = { languageOpen = false; deleteOpen = false },
    )

    SettingsPage(null, L("Einstellungen")) {
        GroupLabel(L("Darstellung"))
        WimgGroup {
            WimgRow(L("Design"), trailing = {
                val modes = listOf(1, 2, -1)
                Segmented(listOf(L("Hell"), L("Dunkel"), L("System")), modes.indexOf(theme).coerceAtLeast(2), { i ->
                    theme = modes[i]
                    prefs.edit().putInt("wimg_theme", theme).apply()
                    ThemeState.mode = theme
                })
            })
            RowDivider()
            WimgRow(L("Sprache"), chevron = true, onClick = { languageOpen = true }, trailing = {
                ValueText(if (LocaleState.locale == "en") "English" else "Deutsch")
            })
        }

        GroupLabel(L("Synchronisierung"))
        WimgGroup {
            val on = SyncService.isEnabled(context)
            WimgRow(
                L("wimg Sync"),
                desc = L("Ende-zu-Ende-verschlüsselt zwischen deinen Geräten, ohne Konto"),
                chevron = true, onClick = { navController?.navigate("settings/sync") },
                trailing = { SyncStatusValue(on) },
            )
        }

        GroupLabel(L("Bankverbindung"))
        WimgGroup {
            WimgRow(L("Bankverbindungen"), chevron = true, onClick = { navController?.navigate("fints") })
            RowDivider()
            WimgRow(
                L("Schnellabfrage im Hintergrund"),
                desc = if (hasPin) L("Einmal täglich, letzte 14 Tage · nur wenn die Bank keine TAN verlangt")
                else L("Erst verfügbar, wenn die PIN für die Schnellabfrage gespeichert ist."),
                trailing = {
                    WimgToggle(bgRefresh && hasPin, { v ->
                        if (hasPin) { bgRefresh = v; BackgroundRefresh.setEnabled(context, v) }
                    }, label = L("Schnellabfrage im Hintergrund"))
                },
            )
        }

        GroupLabel(L("Sicherheit"))
        WimgGroup {
            WimgRow(
                L("App-Sperre"), desc = L("Fingerabdruck, Gesicht oder Geräte-PIN"),
                chevron = true, onClick = { navController?.navigate("settings/lock") },
                trailing = { ValueText(if (BiometricLock.isEnabled) L("An") else L("Aus")) },
            )
        }

        GroupLabel(L("Kategorien"))
        WimgGroup {
            WimgRow(
                L("Automatisch zuordnen"), desc = L("Wendet deine Regeln auf Umsätze ohne Kategorie an"),
                onClick = {
                    scope.launch {
                        val n = withContext(Dispatchers.IO) { LibWimg.autoCategorize() }
                        Changes.bump()
                        if (n > 0) Dock.undo(__t("%d Umsätze zugeordnet").format(n)) { LibWimg.undo(); Changes.bump() }
                        else Dock.info(__t("Nichts Neues zuzuordnen"))
                    }
                },
            )
        }

        GroupLabel(L("Daten"))
        WimgGroup {
            WimgRow(L("Exportieren und sichern"), chevron = true, onClick = { navController?.navigate("settings/data") }, trailing = { ValueText(L("CSV, Backup")) })
            RowDivider()
            WimgRow(L("Importieren"), desc = L("Comdirect, Trade Republic, Scalable"), chevron = true, onClick = { navController?.navigate("import") }, trailing = { ValueText("CSV") })
        }

        GroupLabel(L("Danger Zone"), Modifier)
        Column(
            Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.danger.copy(alpha = 0.35f), WimgShape.group),
        ) {
            WimgRow(L("Alle Daten löschen"), desc = L("Fragt vorher nach Bestätigung"), chevron = true, onClick = { deleteOpen = true })
        }

        GroupLabel(L("Über wimg"))
        WimgGroup {
            WimgRow(L("Version"), chevron = true, onClick = { navController?.navigate("about") }, trailing = { ValueText(appVersion(context)) })
            RowDivider()
            WimgRow(L("FAQ und Datenschutz"), chevron = true, onClick = { navController?.navigate("about/faq") })
            // Debug builds only: every floating-bar state on one page.
            if (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                RowDivider()
                WimgRow("Leiste testen", desc = "Nur in Test-Builds", chevron = true, onClick = { navController?.navigate("dev/bar") })
            }
        }
    }
}

@Composable
private fun SyncStatusValue(on: Boolean) {
    val c = Wimg.colors
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(if (on) c.pos else c.text3))
        Spacer(Modifier.width(7.dp))
        Text(if (on) L("Aktiv") else L("Aus"), style = WimgType.body, color = if (on) c.pos else c.text2)
    }
}

@Composable
private fun LanguagePanel(onDone: () -> Unit) {
    val context = LocalContext.current
    val c = Wimg.colors
    BarPanel {
        Text(L("Sprache"), style = WimgType.sheetTitle.copy(fontSize = WimgType.sheetTitle.fontSize * 0.86f), color = c.text, modifier = Modifier.padding(bottom = 8.dp))
        listOf("de" to "Deutsch", "en" to "English").forEach { (code, label) ->
            val on = LocaleState.locale == code
            Row(
                Modifier.fillMaxWidth().clip(WimgShape.dockAction).clickable {
                    context.getSharedPreferences("wimg", 0).edit().putString("wimg_locale", code).apply()
                    LocaleState.locale = code
                    onDone()
                }.padding(horizontal = 8.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(label, style = WimgType.rowTitle, color = c.text, modifier = Modifier.weight(1f))
                if (on) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.accent, modifier = Modifier.size(20.dp))
            }
        }
    }
}

// ---------------------------------------------------------------------------
// App-Sperre
// ---------------------------------------------------------------------------

@Composable
fun SettingsLockScreen(navController: NavController?) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val c = Wimg.colors
    val method = remember { BiometricLock.availableMethod(context) }
    val canLock = method != BiometricLock.AvailableMethod.NONE
    val hasBiometric = method == BiometricLock.AvailableMethod.BIOMETRIC_STRONG || method == BiometricLock.AvailableMethod.BIOMETRIC_WEAK
    val widgetPrefs = remember { context.getSharedPreferences("wimg_settings", Context.MODE_PRIVATE) }
    var maskWidgets by remember { mutableStateOf(widgetPrefs.getBoolean("wimg_widget_mask_amounts", false)) }

    BarContribution(null, null, {}, DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")))

    SettingsPage(L("Einstellungen"), L("App-Sperre")) {
        Spacer(Modifier.height(14.dp))
        WimgGroup {
            WimgRow(
                L("App-Sperre"),
                desc = if (hasBiometric) L("Beim Öffnen mit Fingerabdruck oder Gesicht entsperren") else L("Beim Öffnen mit der Geräte-PIN entsperren"),
                trailing = { WimgToggle(BiometricLock.isEnabled && canLock, { if (canLock) BiometricLock.setEnabled(context, it) }, label = L("App-Sperre")) },
            )
        }
        if (!canLock) QuietLine(L("Auf diesem Gerät ist keine Displaysperre eingerichtet. Richte sie in den Android-Einstellungen ein."), color = c.warn)

        if (hasBiometric) {
            GroupLabel(L("Entsperren mit"))
            WimgGroup {
                RadioRow(L("Fingerabdruck oder Gesicht"), L("Was dein Gerät eingerichtet hat"), !BiometricLock.deviceOnly) { BiometricLock.setDeviceOnly(context, false) }
                RowDivider()
                RadioRow(L("Nur Geräte-PIN"), null, BiometricLock.deviceOnly) { BiometricLock.setDeviceOnly(context, true) }
            }
        }

        GroupLabel(L("Sperren nach"))
        val steps = listOf(0L, 60_000L, 300_000L, 900_000L)
        Segmented(
            listOf(L("Sofort"), L("1 Min."), L("5 Min."), L("15 Min.")),
            steps.indexOf(BiometricLock.lockAfterMs).let { if (it < 0) 1 else it },
            { BiometricLock.setLockAfter(context, steps[it]) },
            fill = true,
        )

        GroupLabel(L("Privatsphäre"))
        WimgGroup {
            WimgRow(
                L("Beträge ausblenden"), desc = L("In der App-Übersicht des Systems und auf Screenshots"),
                trailing = {
                    WimgToggle(BiometricLock.secureScreen, { on ->
                        BiometricLock.setSecureScreen(context, on)
                        (context as? Activity)?.window?.let { w ->
                            if (on) w.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                            else w.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }, label = L("Beträge ausblenden"))
                },
            )
            RowDivider()
            WimgRow(
                L("Beträge in Widgets ausblenden"), desc = L("Zeigt •••• statt Zahlen"),
                trailing = {
                    WimgToggle(maskWidgets, { on ->
                        maskWidgets = on
                        widgetPrefs.edit().putBoolean("wimg_widget_mask_amounts", on).apply()
                        scope.launch {
                            com.wimg.app.widget.updateAllWidgets(context)
                        }
                    }, label = L("Beträge in Widgets ausblenden"))
                },
            )
        }
        QuietLine(L("Die App-Sperre gilt nur auf diesem Gerät und wird nie synchronisiert."), icon = Icons.Outlined.Lock)
    }
}

@Composable
private fun RadioRow(title: String, desc: String?, on: Boolean, onClick: () -> Unit) {
    val c = Wimg.colors
    WimgRow(title, desc = desc, onClick = onClick, leading = {
        Box(
            Modifier.size(22.dp).clip(CircleShape).background(if (on) c.accent else Color.Transparent)
                .border(1.5.dp, if (on) c.accent else c.text3, CircleShape),
            contentAlignment = Alignment.Center,
        ) { if (on) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.onAccent, modifier = Modifier.size(14.dp)) }
    })
}

// ---------------------------------------------------------------------------
// Daten: export, backup, restore, delete
// ---------------------------------------------------------------------------

@Composable
fun SettingsDataScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    var deleteOpen by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val restore = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val applied = withContext(Dispatchers.IO) {
                runCatching {
                    val text = context.contentResolver.openInputStream(uri)!!.bufferedReader().readText()
                    com.wimg.app.bridge.LibWimg.native { WimgJni.nativeApplyChanges(text) }
                }.getOrDefault(-1)
            }
            if (applied < 0) Dock.error(__t("Datei nicht lesbar"), __t("Das ist keine wimg-Backup-Datei."))
            else { Changes.bump(); Dock.info(__t("Wiederhergestellt"), __t("%d Einträge übernommen").format(applied)) }
        }
    }

    BarContribution(
        null,
        if (deleteOpen) { { DeleteAllPanel(navController) { deleteOpen = false } } } else null,
        { deleteOpen = false },
        DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")),
    )

    SettingsPage(L("Einstellungen"), L("Daten")) {
        GroupLabel(L("Exportieren"))
        WimgGroup {
            WimgRow(
                L("Umsätze als CSV"), desc = L("Für Excel, Steuer oder eine andere App"), chevron = true,
                leading = { IconTile(Icons.Outlined.Description, c.text) },
                onClick = { com.wimg.app.bridge.LibWimg.native { WimgJni.nativeExportCsv() }?.let { shareFile(context, it, "wimg-umsaetze.csv", "text/csv") } },
            )
            RowDivider()
            WimgRow(
                L("Backup-Datei"), desc = L("Alles in einer Datei, zum Wiederherstellen"), chevron = true,
                leading = { IconTile(Icons.Outlined.FileDownload, c.text) },
                onClick = { backupJson()?.let { shareFile(context, it, "wimg-backup.json", "application/json") } },
            )
        }
        GroupLabel(L("Wiederherstellen"))
        WimgGroup {
            WimgRow(
                L("Aus Backup-Datei"), desc = L("Ergänzt, was fehlt. Neuere Daten bleiben."), chevron = true,
                leading = { IconTile(Icons.Outlined.FileUpload, c.text) },
                onClick = { restore.launch(arrayOf("application/json", "text/*", "*/*")) },
            )
        }
        GroupLabel(L("Löschen"))
        WimgGroup {
            WimgRow(
                L("Alle Daten auf diesem Gerät löschen"), chevron = true,
                leading = { IconTile(Icons.Outlined.Close, c.danger) },
                onClick = { deleteOpen = true },
            )
        }
        QuietLine(L("Die Backup-Datei ist nicht verschlüsselt: bewahre sie auf wie einen Kontoauszug. wimg Sync ist kein Backup: Gelöschtes wird auch auf deinen anderen Geräten gelöscht."))
    }
}

/** "Alles auf diesem Gerät löschen?" with a 2-second hold button. */
@Composable
private fun DeleteAllPanel(navController: NavController?, onDone: () -> Unit) {
    val context = LocalContext.current
    val c = Wimg.colors
    val count = remember { LibWimg.getTransactions().size }
    val syncOn = remember { SyncService.isEnabled(context) }
    BarPanel {
        Text(L("Alles auf diesem Gerät löschen?"), style = WimgType.sheetTitle, color = c.text)
        Spacer(Modifier.height(14.dp))
        WimgGroup {
            WimgRow(
                L("Wird gelöscht"), desc = L("%d Umsätze, Kategorien, Regeln, Bankverbindungen mit PIN", count),
                leading = { IconTile(Icons.Outlined.Close, c.danger) },
            )
            if (syncOn) {
                RowDivider()
                WimgRow(L("wimg Sync"), desc = L("Wird beendet, die verschlüsselte Kopie auf dem Server gelöscht. Andere Geräte behalten ihre eigene."), leading = { IconTile(Icons.Outlined.Refresh, c.text) })
            }
        }
        Row(
            Modifier.padding(top = 10.dp).clip(WimgShape.dockAction).clickable {
                backupJson()?.let { shareFile(context, it, "wimg-backup.json", "application/json") }
            }.padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.FileDownload, contentDescription = null, tint = c.text2, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(10.dp))
            Text(L("Vorher sichern?"), style = WimgType.desc, color = c.text2)
            Spacer(Modifier.width(4.dp))
            Text(L("Backup-Datei erstellen"), style = WimgType.desc.copy(fontWeight = FontWeight.Bold), color = c.text)
        }
        Spacer(Modifier.height(10.dp))
        val scope = rememberCoroutineScope()
        HoldToDelete(L("Gedrückt halten zum Löschen")) {
            scope.launch {
                // With sync on, the encrypted copy on the server goes too. If the
                // server can't be reached, say so instead of leaving it silently.
                if (!SyncService.deleteRemote(context)) {
                    Dock.error(
                        __t("Server nicht erreichbar"),
                        __t("Die verschlüsselte Kopie auf dem Sync-Server wurde nicht gelöscht. Versuch es mit Internet noch einmal."),
                        __t("Nur hier löschen"),
                    ) {
                        deleteAllData(context)
                        onDone()
                        navController?.navigate("dashboard") { popUpTo(0) }
                    }
                    return@launch
                }
                deleteAllData(context)
                onDone()
                navController?.navigate("dashboard") { popUpTo(0) }
            }
        }
        Text(
            L("2 Sekunden halten · Loslassen bricht ab"), style = WimgType.caption, color = c.text2,
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp),
        )
    }
}

/** Fills linearly over 2 s while pressed; releases in 200 ms. Fires once when full. */
@Composable
private fun HoldToDelete(label: String, onComplete: () -> Unit) {
    val c = Wimg.colors
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    var done by remember { mutableStateOf(false) }
    Box(
        Modifier
            .fillMaxWidth()
            .height(54.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(c.dangerBg)
            .semantics { contentDescription = label }
            .pointerInput(Unit) {
                detectTapGestures(onPress = {
                    if (done) return@detectTapGestures
                    val job = scope.launch {
                        progress.animateTo(1f, tween(((1f - progress.value) * WimgMotion.HOLD_TO_DELETE_MS).toInt(), easing = LinearEasing))
                        done = true
                        onComplete()
                    }
                    tryAwaitRelease()
                    if (!done) {
                        job.cancel()
                        scope.launch { progress.animateTo(0f, tween(WimgMotion.HOLD_RELEASE_MS, easing = WimgMotion.EaseOut)) }
                    }
                })
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.align(Alignment.CenterStart).fillMaxHeight().fillMaxWidth(progress.value).background(c.danger))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Close, contentDescription = null, tint = if (progress.value > 0.35f) Color.White else c.danger, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
            Text(label, style = WimgType.button, color = if (progress.value > 0.5f) Color.White else c.danger)
        }
    }
}

/** Wipes the database, sync key, stored bank PIN and background fetch on this device. */
private fun deleteAllData(context: Context) {
    runCatching {
        LibWimg.close()
        listOf("wimg.db", "wimg.db-wal", "wimg.db-shm").forEach { File(context.filesDir, it).delete() }
        SyncService.clearSync(context)
        BackgroundRefresh.cancel(context)
        com.wimg.app.services.PinStore.clearAll(context)
        context.getSharedPreferences("wimg_fints", 0).edit().clear().apply()
        LibWimg.initialize(context)
    }
    com.wimg.app.ui.components.ScreenCache.clear()
    Changes.bump()
    Dock.info(__t("Alle Daten gelöscht"))
}

// ---------------------------------------------------------------------------
// wimg Sync
// ---------------------------------------------------------------------------

@Composable
fun SettingsSyncScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    val scope = rememberCoroutineScope()
    var on by remember { mutableStateOf(SyncService.isEnabled(context)) }
    var syncing by remember { mutableStateOf(false) }
    var lastAt by remember { mutableStateOf(SyncService.lastSyncAt(context)) }

    BarContribution(null, null, {}, DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")))

    SettingsPage(L("Synchronisierung"), L("wimg Sync")) {
        if (!on) {
            QuietLine(L("Deine Umsätze gleichen sich zwischen deinen Geräten ab, Ende-zu-Ende-verschlüsselt. Es gibt kein Konto: ein Schlüssel verbindet deine Geräte."), icon = Icons.Outlined.Key)
            Box(
                Modifier.padding(top = 12.dp).fillMaxWidth().height(52.dp).pressable {
                    SyncService.enableSync(context)
                    on = true
                    scope.launch { SyncService.syncNow(context); lastAt = SyncService.lastSyncAt(context) }
                }.clip(CircleShape).background(c.accent),
                contentAlignment = Alignment.Center,
            ) { Text(L("Sync aktivieren"), style = WimgType.button, color = c.onAccent) }
            Box(
                Modifier.padding(top = 10.dp).fillMaxWidth().height(52.dp).pressable { navController?.navigate("settings/sync/link") }.clip(CircleShape).border(1.dp, c.line, CircleShape),
                contentAlignment = Alignment.Center,
            ) { Text(L("Ich habe schon wimg"), style = WimgType.button, color = c.text) }
            return@SettingsPage
        }
        Spacer(Modifier.height(14.dp))
        WimgGroup {
            WimgRow(L("Status"), trailing = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(if (lastAt > 0) c.pos else c.warn))
                    Spacer(Modifier.width(7.dp))
                    Text(
                        if (lastAt > 0) L("Synchron · %s", agoLabel(lastAt)) else L("Noch nicht synchronisiert"),
                        style = WimgType.body, color = if (lastAt > 0) c.pos else c.warn,
                    )
                }
            })
            RowDivider()
            WimgRow(if (syncing) L("Synchronisiere…") else L("Jetzt synchronisieren"), onClick = {
                if (syncing) return@WimgRow
                syncing = true
                scope.launch {
                    val r = SyncService.syncNow(context)
                    syncing = false
                    lastAt = SyncService.lastSyncAt(context)
                    if (r.error != null) Dock.error(__t("Nicht synchron"), __t("Keine Verbindung zum Sync-Server. Später erneut versuchen."))
                    else Dock.info(__t("Synchron"), if (r.pulled > 0) __t("%d Änderungen übernommen").format(r.pulled) else null)
                }
            })
        }
        GroupLabel(L("Geräte verknüpfen"))
        WimgGroup {
            WimgRow(L("Sync-Schlüssel anzeigen"), desc = L("Auf dem neuen Gerät scannen oder abtippen"), chevron = true, onClick = { navController?.navigate("settings/sync/key") })
            RowDivider()
            WimgRow(L("Anderen Schlüssel einfügen"), desc = L("Dieses Gerät mit einem anderen wimg verbinden"), chevron = true, onClick = { navController?.navigate("settings/sync/link") })
        }
        Spacer(Modifier.height(18.dp))
        Column(Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.danger.copy(alpha = 0.35f), WimgShape.group)) {
            WimgRow(L("Sync auf diesem Gerät beenden"), desc = L("Deine Daten bleiben auf diesem Gerät."), onClick = {
                val key = SyncService.getSyncKey(context) ?: return@WimgRow
                SyncService.clearSync(context)
                on = false
                Dock.undo(__t("Sync beendet")) { SyncService.setSyncKey(context, key); on = true }
            })
        }
        QuietLine(L("Der Server speichert nur verschlüsselte Daten. Ohne den Schlüssel kann niemand sie lesen, auch wimg nicht."), icon = Icons.Outlined.Lock)
    }
}

@Composable
private fun agoLabel(ms: Long): String {
    val min = ((System.currentTimeMillis() - ms) / 60_000L).toInt()
    return when {
        min < 1 -> L("gerade eben")
        min < 60 -> L("vor %d Min.", min)
        min < 60 * 24 -> L("vor %d Std.", min / 60)
        else -> L("vor %d Tagen", min / (60 * 24))
    }
}

@Composable
fun SettingsSyncKeyScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    val clipboard = LocalClipboardManager.current
    val key = remember { SyncService.getSyncKey(context).orEmpty() }
    var reveal by remember { mutableStateOf(false) }

    BarContribution(
        null, null, {},
        DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = L("Kopieren"), actionIcon = Icons.Outlined.ContentCopy,
            onAction = { clipboard.setText(AnnotatedString(key)); Dock.info(__t("Schlüssel kopiert"), __t("Wie ein Passwort behandeln.")) },
        ),
    )

    SettingsPage(L("Synchronisierung"), L("Sync-Schlüssel")) {
        Spacer(Modifier.height(14.dp))
        Box(
            Modifier.align(Alignment.CenterHorizontally).size(232.dp).clip(RoundedCornerShape(22.dp)).background(Color.White)
                .border(1.dp, c.line, RoundedCornerShape(22.dp)).padding(18.dp)
                .semantics { contentDescription = __t("QR-Code mit dem Sync-Schlüssel") },
        ) { QrCode(key) }
        Text(L("Auf dem neuen Gerät scannen oder abtippen"), style = WimgType.body, color = c.text2, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 16.dp, bottom = 12.dp))
        val groups = key.replace("-", "").uppercase().chunked(4)
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            groups.chunked(4).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { g ->
                        val idx = groups.indexOf(g)
                        val visible = reveal || idx == 0 || idx == groups.lastIndex
                        Box(Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).background(c.neutralTint).padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                            Text(if (visible) g else "••••", style = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 1.3f), color = c.text)
                        }
                    }
                }
            }
        }
        Row(
            Modifier.align(Alignment.CenterHorizontally).padding(top = 10.dp).clip(WimgShape.dockAction).clickable { reveal = !reveal }.padding(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(if (reveal) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility, contentDescription = null, tint = c.accent, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(if (reveal) L("Wieder verbergen") else L("Ganz anzeigen"), style = WimgType.button, color = c.accent)
        }
        QuietLine(L("Wer diesen Schlüssel hat, kann alle deine Umsätze lesen. Bewahre ihn wie ein Passwort auf, z. B. im Passwort-Manager."), icon = Icons.Outlined.Key)
        QuietLine(L("Es gibt kein Konto und kein „Passwort vergessen“. Solange ein Gerät verknüpft ist, findest du den Schlüssel hier."))
    }
}

/** QR code drawn as squares (ZXing encoder, no bitmap). */
@Composable
private fun QrCode(text: String) {
    val matrix = remember(text) { runCatching { QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, mapOf(com.google.zxing.EncodeHintType.MARGIN to 0)) }.getOrNull() }
    Canvas(Modifier.fillMaxSize()) {
        val m = matrix ?: return@Canvas
        val cell = size.minDimension / m.width
        for (y in 0 until m.height) for (x in 0 until m.width) {
            if (m.get(x, y)) drawRect(Color(0xFF1A1A1A), Offset(x * cell, y * cell), Size(cell + 0.5f, cell + 0.5f))
        }
    }
}

private val KEY_PATTERN = Regex("^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$")

/** Normalizes a pasted key (spaces, groups of 4, any case) to the UUID form, or null. */
private fun normalizeKey(raw: String): String? {
    val hex = raw.filter { it.isLetterOrDigit() }.lowercase()
    if (hex.length != 32 || !hex.all { it in "0123456789abcdef" }) return null
    val uuid = "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}"
    return uuid.takeIf { KEY_PATTERN.matches(it) }
}

@Composable
fun SettingsSyncLinkScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf("") }
    var linking by remember { mutableStateOf(false) }
    val key = normalizeKey(input)

    fun link(k: String) {
        linking = true
        scope.launch {
            SyncService.setSyncKey(context, k)
            val r = SyncService.syncNow(context)
            linking = false
            if (r.error != null) {
                Dock.error(__t("Noch nicht synchron"), __t("Schlüssel gespeichert, aber der Server ist nicht erreichbar. wimg versucht es beim nächsten Öffnen."))
            } else {
                Changes.bump()
                Dock.info(__t("Verbunden"), __t("%d Einträge geholt").format(r.pulled))
            }
            navController?.popBackStack()
        }
    }

    BarContribution(
        null, null, {},
        DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = if (key != null) (if (linking) L("Verbinde…") else L("Verbinden")) else L("Einfügen"),
            actionIcon = if (key != null) Icons.Outlined.Check else Icons.Outlined.ContentPaste,
            onAction = {
                if (key != null) { if (!linking) link(key) }
                else input = clipboard.getText()?.text.orEmpty().trim()
            },
        ),
    )

    SettingsPage(L("Ich habe schon wimg"), L("Mit deinem wimg verbinden")) {
        Spacer(Modifier.height(14.dp))
        Column(Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, if (input.isNotEmpty() && key == null) c.danger else c.line, WimgShape.group).padding(16.dp)) {
            Text(L("Sync-Schlüssel"), style = WimgType.desc, color = c.text2)
            Box(Modifier.padding(top = 4.dp)) {
                if (input.isEmpty()) Text("XXXX-XXXX-XXXX-XXXX-…", style = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 1.25f), color = c.text3)
                BasicTextField(
                    value = input, onValueChange = { input = it }, singleLine = true,
                    textStyle = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 1.25f, color = c.text),
                    cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        if (input.isNotEmpty() && key == null) QuietLine(L("Das sieht nicht wie ein Sync-Schlüssel aus. Er hat 32 Zeichen aus 0–9 und a–f."), color = c.danger)
        QuietLine(L("Der Schlüssel verlässt dieses Gerät nicht. wimgs Server bekommt nur verschlüsselte Daten."), icon = Icons.Outlined.Lock)
        QuietLine(L("Auf dem anderen Gerät: Einstellungen › wimg Sync › Sync-Schlüssel anzeigen."), icon = Icons.Outlined.Info)
    }
}
