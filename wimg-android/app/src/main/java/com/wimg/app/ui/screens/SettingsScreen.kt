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
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.theme.categoryBar
import androidx.compose.material.icons.outlined.Search
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
internal fun SettingsPage(over: String?, title: String, content: @Composable ColumnScope.() -> Unit) {
    BandScreen(band = { BandTitle(over, title) }) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = barClearance()),
            content = content,
        )
    }
}

@Composable
internal fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, fill: Boolean = false) {
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
                    .padding(horizontal = if (fill) 6.dp else 14.dp, vertical = 9.dp),
                contentAlignment = Alignment.Center,
            ) { Text(label, style = WimgType.chip, color = if (on) c.text else c.text2, maxLines = 1, softWrap = false) }
        }
    }
}

@Composable
internal fun ValueText(text: String, color: Color = Wimg.colors.text2) = Text(text, style = WimgType.body, color = color, maxLines = 1)

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
    var deleteOpen by remember { mutableStateOf(false) }
    var bgRefresh by remember { mutableStateOf(BackgroundRefresh.isEnabled(context)) }
    val hasPin = remember { BackgroundRefresh.hasCredentials(context) }
    val scope = rememberCoroutineScope()
    val c = Wimg.colors

    BarContribution(
        chip = null,
        panel = when {
            deleteOpen -> { { DeleteAllPanel(navController) { deleteOpen = false } } }
            else -> null
        },
        onPanelDismiss = { deleteOpen = false },
    )

    SettingsPage(null, L("Einstellungen")) {
        GroupLabel(L("Darstellung"))
        WimgGroup {
            WimgRow(L("Design"), trailing = {
                val modes = listOf(1, 2, -1)
                Segmented(listOf(L("Hell"), L("Dunkel"), L("System")), modes.indexOf(theme).let { if (it < 0) 2 else it }, { i ->
                    theme = modes[i]
                    prefs.edit().putInt("wimg_theme", theme).apply()
                    ThemeState.mode = theme
                })
            })
            RowDivider()
            WimgRow(L("Sprache"), chevron = true, onClick = { navController?.navigate("settings/appearance") }, trailing = {
                ValueText(languageLabel(context))
            })
        }

        GroupLabel(L("Zeitraum"))
        WimgGroup {
            val periods = com.wimg.app.ui.components.rememberPeriods()
            WimgRow(
                L("Monat beginnt"),
                desc = when {
                    periods == null -> null
                    periods.chosen == "salary" && periods.isSalary -> L("Automatisch erkannt · Kalendermonat, wenn kein Gehalt kommt")
                    periods.chosen == "salary" -> L("Gehalt noch nicht erkannt · bis dahin Kalendermonat")
                    else -> null
                },
                chevron = true, onClick = { navController?.navigate("settings/period") },
                trailing = {
                    ValueText(when (periods?.chosen) {
                        "salary" -> L("mit dem Gehalt")
                        "day" -> L("am %d.", periods.day)
                        else -> L("am 1.")
                    })
                },
            )
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
                desc = if (hasPin) L("Jeden Morgen und beim Öffnen (wenn älter als 4 Std.), letzte 14 Tage · nur ohne TAN")
                else L("Erst verfügbar, wenn die PIN für die Schnellabfrage gespeichert ist."),
                trailing = {
                    WimgToggle(bgRefresh && hasPin, { v ->
                        if (hasPin) { bgRefresh = v; BackgroundRefresh.setEnabled(context, v) }
                    }, label = L("Schnellabfrage im Hintergrund"))
                },
            )
        }

        GroupLabel(L("Konten und Mitteilungen"))
        WimgGroup {
            WimgRow(L("Konten"), desc = L("Ein- und ausblenden, umbenennen"), chevron = true, onClick = { navController?.navigate("settings/accounts") })
            RowDivider()
            WimgRow(L("Mitteilungen"), desc = L("Monatsabschluss, neue Umsätze, Preise, TAN"), chevron = true, onClick = { navController?.navigate("settings/notifications") })
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
            RowDivider()
            WimgRow(L("Gelernte Regeln"), desc = L("Ansehen und löschen"), chevron = true, onClick = { navController?.navigate("settings/rules") })
        }

        GroupLabel(L("Daten"))
        WimgGroup {
            WimgRow(L("Exportieren und sichern"), chevron = true, onClick = { navController?.navigate("settings/data") }, trailing = { ValueText(L("CSV, Backup")) })
            RowDivider()
            WimgRow(L("Importieren"), desc = L("Kontoauszug oder CSV, auch Revolut"), chevron = true, onClick = { navController?.navigate("import") })
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
            if (com.wimg.app.ui.components.devTools(context)) {
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
private fun languageLabel(context: Context): String = when (context.getSharedPreferences("wimg", 0).getString("wimg_locale", "system")) {
    "en" -> "English"
    "system" -> L("Systemsprache")
    else -> "Deutsch"
}

// ---------------------------------------------------------------------------
// Design und Sprache (board 20/03)
// ---------------------------------------------------------------------------

@Composable
fun SettingsAppearanceScreen(navController: NavController?) {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences("wimg", 0)
    var theme by remember { mutableIntStateOf(prefs.getInt("wimg_theme", -1)) }
    var choice by remember { mutableStateOf(prefs.getString("wimg_locale", "system") ?: "system") }
    BarContribution(null, null, {}, DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")))

    SettingsPage(L("Einstellungen"), L("Design und Sprache")) {
        Spacer(Modifier.height(14.dp))
        WimgGroup {
            WimgRow(L("Design"), trailing = {
                val modes = listOf(1, 2, -1)
                Segmented(listOf(L("Hell"), L("Dunkel"), L("System")), modes.indexOf(theme).let { if (it < 0) 2 else it }, { i ->
                    theme = modes[i]
                    prefs.edit().putInt("wimg_theme", theme).apply()
                    ThemeState.mode = theme
                })
            })
        }
        GroupLabel(L("Sprache"))
        WimgGroup {
            val systemName = if (java.util.Locale.getDefault().language == "de") "Deutsch" else "English"
            listOf(Triple("de", "Deutsch", null), Triple("en", "English", null), Triple("system", L("Systemsprache"), systemName)).forEachIndexed { i, (code, label, sub) ->
                if (i > 0) RowDivider()
                RadioRow(label, sub, choice == code) {
                    choice = code
                    prefs.edit().putString("wimg_locale", code).apply()
                    LocaleState.locale = LocaleState.stored(context)
                }
            }
        }
        GroupLabel(L("Zahlen und Datum"))
        WimgGroup {
            WimgRow(L("Beträge"), trailing = { ValueText(com.wimg.app.ui.components.amountText(1234.56, showPlus = false)) })
            RowDivider()
            WimgRow(L("Datum"), trailing = { ValueText(com.wimg.app.ui.components.WimgDates.dayMonth(12, 11)) })
        }
        QuietLine(L("Buchungstexte der Bank bleiben in ihrer Sprache."))
    }
}

// ---------------------------------------------------------------------------
// Zeitraum (board 26/09, 26/10)
// ---------------------------------------------------------------------------

@Composable
fun SettingsPeriodScreen(navController: NavController?) {
    val c = Wimg.colors
    val scope = rememberCoroutineScope()
    val periods = com.wimg.app.ui.components.rememberPeriods()
    var choosingPayer by remember { mutableStateOf(false) }
    BarContribution(
        null,
        if (choosingPayer && periods != null) { { PayerPanel(periods) { choosingPayer = false } } } else null,
        { choosingPayer = false },
        DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")),
    )
    SettingsPage(L("Einstellungen"), L("Zeitraum")) {
        val p = periods ?: return@SettingsPage
        GroupLabel(L("Ein Monat beginnt"))
        val modes = listOf("salary", "calendar", "day")
        var picked by remember(p.chosen) { mutableIntStateOf(modes.indexOf(p.chosen).coerceAtLeast(0)) }
        Segmented(listOf(L("mit dem Gehalt"), L("am 1."), L("Fester Tag")), picked, { i ->
            if (i != picked) {
                picked = i
                scope.launch { com.wimg.app.ui.components.PeriodState.setMode(modes[i], if (modes[i] == "day") (if (p.day > 1) p.day else 15) else 0) }
            }
        }, fill = true)
        Spacer(Modifier.height(12.dp))
        when {
            p.chosen == "day" -> WimgGroup { Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) { DayStepper(p); Spacer(Modifier.height(12.dp)) } }
            p.salary != null && p.isSalary -> SalaryCard(p.salary, Modifier.background(c.card, WimgShape.group)) { choosingPayer = true }
            p.chosen == "salary" -> Column(
                Modifier.fillMaxWidth().clip(WimgShape.group).border(1.dp, c.line, WimgShape.group).padding(16.dp),
            ) {
                Text(L("Gehalt noch nicht erkannt"), style = WimgType.rowTitle, color = c.text)
                Text(L("wimg braucht zwei Gehälter vom selben Absender. Bis dahin zählt es nach Kalendermonat."), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 4.dp))
                Text(L("Gehalt selbst auswählen"), style = WimgType.button, color = c.accent, modifier = Modifier.padding(top = 10.dp).clip(WimgShape.button).clickable { choosingPayer = true }.padding(vertical = 6.dp))
            }
            else -> Unit
        }
        GroupLabel(L("Gilt für"))
        WimgGroup {
            val on = p.chosen != "calendar"
            WimgRow(L("Übersicht und Rückblick"), trailing = { if (on) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.pos, modifier = Modifier.size(20.dp)) })
            RowDivider()
            WimgRow(L("Wiederkehrend und Widgets"), trailing = { if (on) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.pos, modifier = Modifier.size(20.dp)) })
            RowDivider()
            WimgRow(L("Umsätze-Filter"), desc = L("Dort kannst du jederzeit auf Kalendermonate umschalten"))
        }
        QuietLine(
            when {
                p.chosen == "salary" && !p.isSalary -> L("Du kannst „mit dem Gehalt“ schon wählen. wimg schaltet von selbst um, sobald es das zweite Gehalt sieht.")
                p.chosen == "day" -> L("Ein Monat läuft vom %d. bis zum Tag davor im nächsten Monat.", p.day)
                else -> L("Kommt das Gehalt früher oder später, verschiebt sich der Zeitraum mit.")
            },
        )
    }
}

// ---------------------------------------------------------------------------
// Mitteilungen (board 20/02)
// ---------------------------------------------------------------------------

@Composable
fun SettingsNotificationsScreen(navController: NavController?) {
    val context = LocalContext.current
    var version by remember { mutableIntStateOf(0) }
    var quietOpen by remember { mutableStateOf(false) }
    val quiet = remember(version) { BackgroundRefresh.quietHours(context) }
    BarContribution(
        null,
        if (quietOpen) { {
            QuietHoursPanel(quiet) { h -> BackgroundRefresh.setQuietHours(context, h); version++; quietOpen = false }
        } } else null,
        { quietOpen = false },
        DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")),
    )

    @Composable
    fun toggle(key: String, title: String, desc: String) {
        val on = remember(version) { BackgroundRefresh.notifyOn(context, key) }
        WimgRow(title, desc = desc, trailing = {
            WimgToggle(on, { BackgroundRefresh.setNotify(context, key, it); version++ }, label = title)
        })
    }

    SettingsPage(L("Einstellungen"), L("Mitteilungen")) {
        Spacer(Modifier.height(14.dp))
        WimgGroup {
            toggle(BackgroundRefresh.NOTIFY_MONTH_END, L("Monatsabschluss"), L("Einmal am Monats- bzw. Gehaltsende"))
            RowDivider()
            toggle(BackgroundRefresh.NOTIFY_NEW_TX, L("Neue Umsätze"), L("Nach dem Hintergrund-Abruf, gesammelt"))
            RowDivider()
            toggle(BackgroundRefresh.NOTIFY_TAN, L("TAN nötig"), L("Wenn die Bank eine TAN will · höchstens 1× am Tag"))
            RowDivider()
            toggle(BackgroundRefresh.NOTIFY_SALARY, L("Gehalt eingegangen"), L("Mit neuem Zeitraum"))
            RowDivider()
            toggle(BackgroundRefresh.NOTIFY_PRICE, L("Preis gestiegen"), L("Wenn eine feste Zahlung teurer wird"))
        }
        GroupLabel(L("Ruhezeit"))
        WimgGroup {
            WimgRow(
                L("Nicht stören"), desc = L("Keine Mitteilungen in dieser Zeit"), chevron = true, onClick = { quietOpen = true },
                trailing = { ValueText(quiet?.let { "%d:00 – %d:00".format(it.first, it.second) } ?: L("Aus")) },
            )
        }
        if (!BackgroundRefresh.hasNotificationPermission(context)) {
            QuietLine(
                L("Mitteilungen sind für wimg in den Android-Einstellungen aus. Tippe, um sie einzuschalten."), color = Wimg.colors.warn,
                modifier = Modifier.clickable {
                    context.startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName))
                },
            )
        }
        QuietLine(L("Mitteilungen zeigen keine Beträge, wenn „Beträge ausblenden“ an ist."))
    }
}

@Composable
private fun QuietHoursPanel(current: Pair<Int, Int>?, onPick: (Pair<Int, Int>?) -> Unit) {
    val c = Wimg.colors
    BarPanel {
        Text(L("Nicht stören"), style = WimgType.sheetTitle, color = c.text, modifier = Modifier.padding(start = 4.dp, bottom = 12.dp))
        WimgGroup {
            listOf(null, 22 to 8, 23 to 7, 21 to 7).forEachIndexed { i, h ->
                if (i > 0) RowDivider()
                RadioRow(h?.let { "%d:00 – %d:00".format(it.first, it.second) } ?: L("Aus"), null, h == current) { onPick(h) }
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
internal fun RadioRow(title: String, desc: String?, on: Boolean, trailing: String? = null, onClick: () -> Unit) {
    val c = Wimg.colors
    WimgRow(title, desc = desc, onClick = onClick, trailing = trailing?.let { t -> { ValueText(t) } }, leading = {
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
// Gelernte Regeln (board 22)
// ---------------------------------------------------------------------------

private data class RuleRow(val rule: com.wimg.app.models.Rule, val count: Int)

/** Rules with how many transactions each one sorted (same category, text found). */
private fun loadRules(): List<RuleRow> {
    val txs = LibWimg.getTransactions()
    return LibWimg.getRules().map { r ->
        RuleRow(r, txs.count { it.category == r.category && it.description.contains(r.pattern, ignoreCase = true) })
    }
}

@Composable
fun SettingsRulesScreen(navController: NavController?) {
    val c = Wimg.colors
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<List<RuleRow>>("rules")) }
    var query by remember { mutableStateOf("") }
    var open by remember { mutableStateOf<RuleRow?>(null) }
    LaunchedEffect(Changes.version) { rows = withContext(Dispatchers.IO) { loadRules() }.also { com.wimg.app.ui.components.ScreenCache.put("rules", it) } }

    BarContribution(
        null,
        open?.let { r -> { RulePanel(r, onCancel = { open = null }) { reset ->
            open = null
            scope.launch {
                withContext(Dispatchers.IO) { LibWimg.deleteRule(r.rule.id, reset) }
                Changes.bump()
                Dock.info(__t("Regel gelöscht"), if (reset) __t("%d Umsätze wieder ohne Kategorie").format(r.count) else null)
            }
        } } },
        { open = null },
        DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")),
    )

    SettingsPage(L("Einstellungen · Kategorien"), L("Gelernte Regeln")) {
        Spacer(Modifier.height(14.dp))
        androidx.compose.foundation.text.BasicTextField(
            value = query, onValueChange = { query = it }, singleLine = true,
            textStyle = WimgType.body.copy(color = c.text),
            cursorBrush = androidx.compose.ui.graphics.SolidColor(c.accent),
            modifier = Modifier.fillMaxWidth().clip(WimgShape.group).background(c.neutralTint).padding(horizontal = 16.dp, vertical = 16.dp),
            decorationBox = { inner ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Search, contentDescription = null, tint = c.text2, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(12.dp))
                    Box { if (query.isEmpty()) Text(L("Stichwort oder Kategorie"), style = WimgType.body, color = c.text2); inner() }
                }
            },
        )
        val all = rows ?: return@SettingsPage
        val q = query.trim()
        val shown = all.filter { q.isEmpty() || it.rule.pattern.contains(q, true) || L(WimgCategory.fromId(it.rule.category).label).contains(q, true) }
        // Learned (priority 1) first, newest first; then the ones wimg ships with.
        val learned = shown.filter { it.rule.priority == 1 }.sortedByDescending { it.rule.id }
        val shipped = shown.filter { it.rule.priority != 1 }.sortedByDescending { it.count }
        listOf(L("Gelernt") to learned, L("Mitgeliefert") to shipped).forEach { (label, list) ->
            if (list.isEmpty()) return@forEach
            GroupLabel(if (label == L("Gelernt")) L("%d gelernt · zuletzt gelernt zuerst", list.size) else L("%d mitgeliefert", list.size))
            WimgGroup {
                list.forEachIndexed { i, r ->
                    if (i > 0) RowDivider()
                    val cat = WimgCategory.fromId(r.rule.category)
                    WimgRow(
                        "„${r.rule.pattern}“",
                        desc = "→ ${L(cat.label)} · " + if (r.count == 1) L("1 Umsatz") else L("%d Umsätze", r.count),
                        chevron = true,
                        onClick = { open = r },
                    )
                }
            }
        }
        if (shown.isEmpty()) QuietLine(L("Keine Regel passt zu „%s“.", q))
        QuietLine(L("wimg lernt eine Regel, wenn du einem Umsatz von Hand eine Kategorie gibst. Regeln gelten nur für neue und noch nicht zugeordnete Umsätze."))
    }
}

@Composable
private fun RulePanel(r: RuleRow, onCancel: () -> Unit, onDelete: (reset: Boolean) -> Unit) {
    val c = Wimg.colors
    var reset by remember { mutableStateOf(false) }
    val cat = WimgCategory.fromId(r.rule.category)
    BarPanel {
        Text("„${r.rule.pattern}“", style = WimgType.sheetTitle, color = c.text, maxLines = 2)
        Spacer(Modifier.height(12.dp))
        WimgGroup {
            WimgRow(L("Wenn der Text enthält"), trailing = { ValueText(r.rule.pattern) })
            RowDivider()
            WimgRow(L("dann Kategorie"), trailing = {
                Box(Modifier.size(9.dp).clip(CircleShape).background(c.categoryBar(cat.id)))
                Spacer(Modifier.width(8.dp))
                ValueText(L(cat.label))
            })
            RowDivider()
            WimgRow(L("Betrifft"), trailing = { ValueText(if (r.count == 1) L("1 Umsatz") else L("%d Umsätze", r.count)) })
        }
        Text(L("Regel löschen"), style = WimgType.label, color = c.danger, modifier = Modifier.padding(top = 16.dp, bottom = 8.dp))
        WimgGroup {
            RadioRow(L("Kategorien behalten"), L("Die Umsätze bleiben %s. Nur neue werden nicht mehr zugeordnet.", L(cat.label)), !reset) { reset = false }
            RowDivider()
            RadioRow(L("Auch zurücksetzen"), L("Die Umsätze sind danach wieder ohne Kategorie."), reset) { reset = true }
        }
        Row(Modifier.padding(top = 16.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.weight(1f).height(50.dp).pressable(onClick = onCancel).clip(CircleShape).border(1.dp, c.line, CircleShape), contentAlignment = Alignment.Center) {
                Text(L("Abbrechen"), style = WimgType.button, color = c.text)
            }
            Box(Modifier.weight(1f).height(50.dp).pressable { onDelete(reset) }.clip(CircleShape).border(1.5.dp, c.danger, CircleShape), contentAlignment = Alignment.Center) {
                Text(L("Löschen"), style = WimgType.button, color = c.danger)
            }
        }
    }
}
