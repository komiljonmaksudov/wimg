package com.wimg.app.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.TabletAndroid
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.navigation.NavController
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.models.SyncDevice
import com.wimg.app.services.SyncService
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BandTitle
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.DockKind
import com.wimg.app.ui.components.DockRow
import com.wimg.app.ui.components.GroupLabel
import com.wimg.app.ui.components.IconTile
import com.wimg.app.ui.components.QrScanner
import com.wimg.app.ui.components.QuietLine
import com.wimg.app.ui.components.RowDivider
import com.wimg.app.ui.components.WimgGroup
import com.wimg.app.ui.components.WimgRow
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Board 21: wimg Sync — devices, show the key, link a device, wrong key, new key.

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

private fun deviceIcon(kind: String) = when (kind) {
    "tablet" -> Icons.Outlined.TabletAndroid
    "laptop", "browser" -> Icons.Outlined.Laptop
    else -> Icons.Outlined.PhoneAndroid
}

@Composable
private fun OutlineButton(label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = Wimg.colors
    Box(modifier.height(50.dp).pressable(onClick = onClick).clip(CircleShape).border(1.dp, c.line, CircleShape), contentAlignment = Alignment.Center) {
        Text(label, style = WimgType.button, color = c.text)
    }
}

@Composable
private fun FilledButton(label: String, color: Color, textColor: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(modifier.height(50.dp).pressable(onClick = onClick).clip(CircleShape).background(color), contentAlignment = Alignment.Center) {
        Text(label, style = WimgType.button, color = textColor, maxLines = 1)
    }
}

// ---------------------------------------------------------------------------
// wimg Sync: devices (board 21/05) or the start when sync is off
// ---------------------------------------------------------------------------

@Composable
fun SettingsSyncScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    val scope = rememberCoroutineScope()
    var on by remember { mutableStateOf(SyncService.isEnabled(context)) }
    var syncing by remember { mutableStateOf(false) }
    var lastAt by remember { mutableStateOf(SyncService.lastSyncAt(context)) }
    var devices by remember { mutableStateOf<List<SyncDevice>>(emptyList()) }
    var removing by remember { mutableStateOf<SyncDevice?>(null) }
    var newKeyOpen by remember { mutableStateOf(false) }
    val me = remember(on) { SyncService.deviceId(context) }
    LaunchedEffect(Changes.version, on) { devices = withContext(Dispatchers.IO) { LibWimg.getDevices() } }

    fun syncNow() {
        if (syncing) return
        syncing = true
        scope.launch {
            val r = SyncService.syncNow(context)
            syncing = false
            lastAt = SyncService.lastSyncAt(context)
            on = SyncService.isEnabled(context)
            devices = withContext(Dispatchers.IO) { LibWimg.getDevices() }
            when {
                r.removed -> Unit
                r.error != null -> Dock.error(__t("Nicht synchron"), __t("Keine Verbindung zum Sync-Server. Später erneut versuchen."))
                else -> Dock.info(__t("Synchron"), if (r.pulled > 0) __t("%d Änderungen übernommen").format(r.pulled) else null)
            }
        }
    }

    BarContribution(
        null,
        when {
            removing != null -> { {
                val d = removing!!
                RemoveDevicePanel(d, onCancel = { removing = null }) {
                    removing = null
                    scope.launch {
                        withContext(Dispatchers.IO) { LibWimg.removeDevice(d.id) }
                        Changes.bump()
                        Dock.info(__t("Gerät entfernt"), __t("%s synchronisiert nicht mehr.").format(d.name))
                        SyncService.syncNow(context)
                    }
                }
            } }
            newKeyOpen -> { {
                NewKeyPanel(devices.filter { it.id != me }, onCancel = { newKeyOpen = false }) {
                    newKeyOpen = false
                    scope.launch {
                        Dock.show(DockRow(DockKind.Sync, __t("Neuer Schlüssel wird erstellt"), __t("Daten werden neu verschlüsselt")))
                        val ok = SyncService.replaceKey(context)
                        Changes.bump()
                        lastAt = SyncService.lastSyncAt(context)
                        if (ok) Dock.info(__t("Neuer Schlüssel aktiv"), __t("Verknüpfe deine anderen Geräte neu."))
                        else Dock.error(__t("Schlüssel nicht ersetzt"), __t("Keine Verbindung zum Sync-Server. Der alte Schlüssel gilt weiter."))
                    }
                }
            } }
            else -> null
        },
        { removing = null; newKeyOpen = false },
        DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")),
    )

    if (!on) {
        SettingsPage(L("Synchronisierung"), L("wimg Sync")) {
            if (SyncService.wasRemoved(context)) {
                QuietLine(L("Dieses Gerät ist nicht mehr verknüpft: es wurde entfernt oder der Schlüssel ersetzt. Deine Daten sind noch hier."), color = c.warn, icon = Icons.Outlined.Link)
            }
            QuietLine(L("Deine Umsätze gleichen sich zwischen deinen Geräten ab, Ende-zu-Ende-verschlüsselt. Es gibt kein Konto: ein Schlüssel verbindet deine Geräte."), icon = Icons.Outlined.Key)
            FilledButton(L("Sync aktivieren"), c.accent, c.onAccent, Modifier.padding(top = 12.dp).fillMaxWidth()) {
                SyncService.enableSync(context)
                on = true
                syncNow()
            }
            OutlineButton(L("Ich habe schon wimg"), Modifier.padding(top = 10.dp).fillMaxWidth()) { navController?.navigate("settings/sync/link") }
        }
        return
    }

    BandScreen(band = {
        Text(L("Synchronisierung"), style = WimgType.bandOver, color = c.bandSub)
        Text(L("Geräte"), style = WimgType.title, color = Color.White)
        Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(if (lastAt > 0) c.bandPos else c.warn))
            Spacer(Modifier.width(8.dp))
            Text(
                when {
                    syncing -> L("Synchronisiere…")
                    lastAt > 0 -> L("Synchron · %s", agoLabel(lastAt))
                    else -> L("Noch nicht synchronisiert")
                },
                style = WimgType.desc, color = c.bandSub,
            )
        }
    }) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = barClearance()),
        ) {
            WimgGroup {
                // This phone first, even before its row has synced.
                val mine = devices.firstOrNull { it.id == me } ?: SyncDevice(me, SyncService.deviceName(context), "phone", lastAt)
                val list = listOf(mine) + devices.filter { it.id != me }
                list.forEachIndexed { i, d ->
                    if (i > 0) RowDivider()
                    val isMe = d.id == me
                    val recent = System.currentTimeMillis() - d.last_seen < 7L * 24 * 3600 * 1000
                    WimgRow(
                        if (isMe) L("%s (dieses Gerät)", d.name) else d.name,
                        desc = when {
                            isMe && syncing -> L("Synchronisiere…")
                            isMe && lastAt > 0 -> L("Synchron · %s", agoLabel(lastAt))
                            isMe -> L("Tippen zum Synchronisieren")
                            recent -> L("Synchron · %s", agoLabel(d.last_seen))
                            else -> L("Zuletzt %s", agoLabel(d.last_seen))
                        },
                        leading = { IconTile(deviceIcon(d.kind), c.text) },
                        chevron = !isMe,
                        onClick = { if (isMe) syncNow() else removing = d },
                    )
                }
            }
            GroupLabel(L("Schlüssel"))
            WimgGroup {
                WimgRow(L("Sync-Schlüssel anzeigen"), leading = { IconTile(Icons.Outlined.Key, c.text) }, chevron = true, onClick = { navController?.navigate("settings/sync/key") })
                RowDivider()
                WimgRow(
                    L("Neuen Schlüssel erstellen"), desc = L("Wenn ein Gerät verloren ging oder jemand den Schlüssel kennt"),
                    leading = { IconTile(Icons.Outlined.Refresh, c.text) }, chevron = true, onClick = { newKeyOpen = true },
                )
            }
            QuietLine(L("Ein Gerät entfernst du, indem du es antippst. Wer den Schlüssel noch kennt, kommt aber wieder rein: dafür gibt es den neuen Schlüssel."))
            Spacer(Modifier.height(10.dp))
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
}

@Composable
private fun RemoveDevicePanel(d: SyncDevice, onCancel: () -> Unit, onRemove: () -> Unit) {
    val c = Wimg.colors
    BarPanel {
        Text(L("%s entfernen?", d.name), style = WimgType.sheetTitle, color = c.text)
        Text(
            L("Das Gerät synchronisiert danach nicht mehr, seine Daten bleiben darauf. Wer den Schlüssel kennt, kann es wieder verknüpfen: dagegen hilft ein neuer Schlüssel."),
            style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 8.dp),
        )
        Row(Modifier.padding(top = 16.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlineButton(L("Abbrechen"), Modifier.weight(1f), onCancel)
            FilledButton(L("Entfernen"), c.danger, Color.White, Modifier.weight(1f), onRemove)
        }
    }
}

/** "Neuen Schlüssel erstellen?" (board 21/06). */
@Composable
private fun NewKeyPanel(others: List<SyncDevice>, onCancel: () -> Unit, onCreate: () -> Unit) {
    val context = LocalContext.current
    val c = Wimg.colors
    BarPanel {
        Text(L("Neuen Schlüssel erstellen?"), style = WimgType.sheetTitle, color = c.text)
        Text(
            L("Der alte Schlüssel funktioniert danach nicht mehr. Wer ihn kennt, kommt nicht mehr an deine Daten."),
            style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 8.dp, bottom = 14.dp),
        )
        WimgGroup {
            WimgRow(L("Dieses %s", SyncService.deviceName(context)), desc = L("Bekommt den neuen Schlüssel sofort"), leading = { IconTile(Icons.Outlined.Check, c.pos) })
            if (others.isNotEmpty()) {
                RowDivider()
                WimgRow(others.joinToString(", ") { it.name }, desc = if (others.size == 1) L("Muss neu verknüpft werden") else L("Müssen neu verknüpft werden"), leading = { IconTile(Icons.Outlined.Link, c.warn) })
            }
        }
        QuietLine(L("Kein Gerät mehr verknüpft? Dann gibt es den Schlüssel nirgends. Deine Daten liegen nur noch verschlüsselt auf wimgs Server und sind ohne Schlüssel nicht lesbar."))
        Row(Modifier.padding(top = 6.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlineButton(L("Abbrechen"), Modifier.weight(0.8f), onCancel)
            FilledButton(L("Neuen Schlüssel erstellen"), c.ink, c.inkText, Modifier.weight(1.4f), onCreate)
        }
    }
}

// ---------------------------------------------------------------------------
// Show the key (board 21/01)
// ---------------------------------------------------------------------------

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
            groups.chunked(4).forEachIndexed { r, row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEachIndexed { i, g ->
                        val idx = r * 4 + i
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

// ---------------------------------------------------------------------------
// Link a device: scan or paste (board 21/02), wrong key (21/03)
// ---------------------------------------------------------------------------

/**
 * Normalizes a pasted or typed key (spaces, groups of 4, any case) to the UUID
 * form, or null. Letters that look like digits (O, I, l) count as those digits:
 * a key only has 0–9 and a–f.
 */
internal fun normalizeKey(raw: String): String? {
    val hex = raw.filter { it.isLetterOrDigit() }.lowercase().map { ch ->
        when (ch) { 'o' -> '0'; 'i', 'l' -> '1'; else -> ch }
    }.joinToString("")
    if (hex.length != 32 || !hex.all { it in "0123456789abcdef" }) return null
    return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}"
}

@Composable
fun SettingsSyncLinkScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf("") }
    var linking by remember { mutableStateOf(false) }
    var noMatch by remember { mutableStateOf(false) }
    val key = normalizeKey(input)
    var camera by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    val askCamera = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { camera = it }

    fun link(k: String) {
        if (linking) return
        linking = true
        noMatch = false
        scope.launch {
            when (SyncService.probe(k)) {
                SyncService.Probe.NoMatch -> noMatch = true
                SyncService.Probe.Offline -> Dock.error(__t("Server nicht erreichbar"), __t("Prüfe die Internetverbindung und versuch es noch einmal."))
                is SyncService.Probe.Found -> {
                    SyncService.setSyncKey(context, k)
                    navController?.navigate("settings/sync/linked") { popUpTo("settings/sync/link") { inclusive = true } }
                }
            }
            linking = false
        }
    }

    BarContribution(
        null, null, {},
        DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = if (key != null) L("Verbinden") else L("Einfügen"),
            actionIcon = if (key != null) Icons.Outlined.Check else Icons.Outlined.ContentPaste,
            actionBusy = linking,
            onAction = {
                if (key != null) link(key)
                else { input = clipboard.getText()?.text.orEmpty().trim(); noMatch = false }
            },
        ),
    )

    SettingsPage(L("Ich habe schon wimg"), L("Mit deinem wimg verbinden")) {
        Spacer(Modifier.height(14.dp))
        // The viewfinder: camera once allowed, otherwise a tap asks for it.
        Box(
            Modifier.fillMaxWidth().height(300.dp).clip(RoundedCornerShape(22.dp)).background(c.band)
                .then(if (!camera) Modifier.clickable { askCamera.launch(Manifest.permission.CAMERA) } else Modifier),
            contentAlignment = Alignment.Center,
        ) {
            if (camera) QrScanner(Modifier.fillMaxSize()) { code -> normalizeKey(code)?.let { input = it; link(it) } }
            ScanCorners(Modifier.size(170.dp))
            Text(
                if (camera) L("QR-Code vom anderen Gerät ins Feld halten") else L("Tippen, um die Kamera einzuschalten"),
                style = WimgType.body, color = Color.White, textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 18.dp, start = 16.dp, end = 16.dp),
            )
        }
        Row(Modifier.fillMaxWidth().padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            HorizontalDivider(Modifier.weight(1f), thickness = 1.dp, color = c.line)
            Text(L("oder einfügen"), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(horizontal = 12.dp))
            HorizontalDivider(Modifier.weight(1f), thickness = 1.dp, color = c.line)
        }
        val bad = noMatch || (input.isNotEmpty() && key == null)
        Column(Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, if (bad) c.danger else c.line, WimgShape.group).padding(16.dp)) {
            Text(L("Sync-Schlüssel"), style = WimgType.desc, color = c.text2)
            Box(Modifier.padding(top = 4.dp)) {
                if (input.isEmpty()) Text("XXXX-XXXX-XXXX-XXXX-…", style = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 1.25f), color = c.text3)
                BasicTextField(
                    value = input, onValueChange = { input = it; noMatch = false }, singleLine = true,
                    textStyle = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 1.25f, color = c.text),
                    cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        when {
            noMatch -> QuietLine(L("Dieser Schlüssel passt zu keinem wimg Sync. Prüfe die Zeichen: 0 und O, 1 und l sehen sich ähnlich."), color = c.danger, icon = Icons.Outlined.ErrorOutline)
            input.isNotEmpty() && key == null -> QuietLine(L("Das sieht nicht wie ein Sync-Schlüssel aus. Er hat 32 Zeichen aus 0–9 und a–f."), color = c.danger, icon = Icons.Outlined.ErrorOutline)
            else -> QuietLine(L("Der Schlüssel verlässt dieses Gerät nicht. wimgs Server bekommt nur verschlüsselte Daten."), icon = Icons.Outlined.Lock)
        }
        QuietLine(L("Auf dem anderen Gerät: Einstellungen › wimg Sync › Sync-Schlüssel anzeigen."), icon = Icons.Outlined.Info)
    }
}

/** Four white corner brackets of the viewfinder. */
@Composable
private fun ScanCorners(modifier: Modifier) {
    Canvas(modifier) {
        val l = size.minDimension * 0.22f
        val w = 3.dp.toPx()
        val s = Stroke(w, cap = StrokeCap.Round)
        val r = size.width
        val b = size.height
        listOf(
            Offset(0f, l) to Offset(0f, 0f), Offset(0f, 0f) to Offset(l, 0f),
            Offset(r - l, 0f) to Offset(r, 0f), Offset(r, 0f) to Offset(r, l),
            Offset(0f, b - l) to Offset(0f, b), Offset(0f, b) to Offset(l, b),
            Offset(r - l, b) to Offset(r, b), Offset(r, b) to Offset(r, b - l),
        ).forEach { (a, z) -> drawLine(Color.White, a, z, strokeWidth = s.width, cap = StrokeCap.Round) }
    }
}

// ---------------------------------------------------------------------------
// Linked: the data comes in (board 21/04)
// ---------------------------------------------------------------------------

@Composable
fun SettingsSyncLinkedScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    var others by remember { mutableStateOf<List<SyncDevice>>(emptyList()) }
    LaunchedEffect(Unit) {
        // Keeps running when the user goes on to Übersicht.
        SyncService.firstPull(context)
    }
    LaunchedEffect(Changes.version) {
        val me = SyncService.deviceId(context)
        others = withContext(Dispatchers.IO) { LibWimg.getDevices() }.filter { it.id != me }
    }

    BarContribution(
        null, null, {},
        DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = L("Zur Übersicht"), actionIcon = null,
            onAction = { navController?.navigate("dashboard") { popUpTo(0) } },
        ),
    )

    BandScreen(band = { BandTitle(L("Ich habe schon wimg"), L("Verbunden")) }) {
        Column(Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(72.dp).clip(CircleShape).background(c.pos.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Check, contentDescription = null, tint = c.pos, modifier = Modifier.size(34.dp))
            }
            Text(L("Dein wimg ist gefunden"), style = WimgType.section.copy(fontSize = WimgType.section.fontSize * 1.25f), color = c.text, modifier = Modifier.padding(top = 18.dp))
            val names = others.map { it.name }
            val text = if (names.isEmpty()) L("Du kannst schon loslegen, der Rest kommt im Hintergrund.")
            else L("Verknüpft mit %s. Du kannst schon loslegen, der Rest kommt im Hintergrund.", if (names.size == 1) names[0] else names.dropLast(1).joinToString(", ") + " " + L("und") + " " + names.last())
            Text(text, style = WimgType.body, color = c.text2, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
            Spacer(Modifier.height(16.dp))
            QuietLine(L("Bank-PIN und TAN-Verfahren kommen nicht mit. Gib sie auf diesem Gerät neu ein, wenn du hier abrufen willst."), icon = Icons.Outlined.Lock)
        }
    }
}
