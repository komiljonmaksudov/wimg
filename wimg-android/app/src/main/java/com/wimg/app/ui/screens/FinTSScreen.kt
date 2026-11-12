package com.wimg.app.ui.screens

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.LinkOff
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.bridge.WimgJni
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.models.Account
import com.wimg.app.services.BackgroundRefresh
import com.wimg.app.services.FintsHttpCallback
import com.wimg.app.ui.components.Amount
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.DockKind
import com.wimg.app.ui.components.DockRow
import com.wimg.app.ui.components.QuietLine
import com.wimg.app.ui.components.RowDivider
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.WimgGroup
import com.wimg.app.ui.components.WimgRow
import com.wimg.app.ui.components.WimgToggle
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.Calendar

@Serializable
private data class BankInfo(val blz: String, val name: String, val url: String)

@Serializable
private data class FintsResult(
    val status: String? = null,
    val challenge: String? = null,
    val phototan: String? = null,
    val decoupled: Boolean? = null,
    val message: String? = null,
    val tan_medium_required: Boolean? = null,
    val imported: Int? = null,
    val duplicates: Int? = null,
)

@Serializable
private data class TanMedium(val name: String, val status: Int = 1)

@Serializable
private data class TanMediaResult(val status: String = "", val media: List<TanMedium>? = null, val message: String? = null)

private val json = Json { ignoreUnknownKeys = true }

/** Run a block on a thread with 2MB stack (FinTS needs large buffers for Base64/MT940). */
private suspend fun <T> withFintsThread(block: () -> T): T {
    return kotlinx.coroutines.suspendCancellableCoroutine { cont ->
        val thread = Thread(null, {
            try {
                cont.resumeWith(Result.success(block()))
            } catch (e: Throwable) {
                cont.resumeWith(Result.failure(e))
            }
        }, "fints-worker", 2 * 1024 * 1024)
        thread.start()
    }
}

private const val PREFS = "wimg_fints"
private const val KEY_BLZ = "fints_blz"
private const val KEY_KENNUNG = "fints_kennung"
private const val KEY_PIN = "fints_pin"
private const val KEY_TAN_MEDIUM = "fints_tan_medium"
private const val KEY_LAST_FETCH = "fints_last_fetch_at"
private const val KEY_LAST_NEW = "fints_last_fetch_new"
private const val PRODUCT = "F7C4049477F6136957A46EC28"

// Request bodies built as JSON objects, so a PIN or login with quotes or
// backslashes can't break the request.
private fun connectBody(blz: String, user: String, pin: String) =
    buildJsonObject { put("blz", blz); put("user", user); put("pin", pin); put("product", PRODUCT) }.toString()
private fun tanBody(tan: String) = buildJsonObject { put("tan", tan) }.toString()
private fun fetchBody(from: String, to: String) = buildJsonObject { put("from", from); put("to", to) }.toString()
private fun mediumBody(name: String) = buildJsonObject { put("name", name) }.toString()

private fun iso(c: Calendar) = "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
private fun rangeDays(days: Int): Pair<String, String> {
    val c = Calendar.getInstance()
    val to = iso(c)
    c.add(Calendar.DAY_OF_YEAR, -days)
    return iso(c) to to
}

private fun decode(r: String?): FintsResult? = r?.let { runCatching { json.decodeFromString<FintsResult>(it) }.getOrNull() }

/**
 * The statement fetch, kept outside any screen so it keeps running (and its
 * progress stays on the bar) when the user leaves the bank screens.
 */
private object FintsJob {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    var running by mutableStateOf(false)
        private set

    /** Last fetch needed a TAN: the challenge for the bank screen to pick up. */
    var pendingTan by mutableStateOf<FintsResult?>(null)
    var lastRange: Pair<String, String>? = null

    fun fetch(context: Context, range: Pair<String, String>, bankName: String, onDone: (FintsResult?) -> Unit = {}) {
        if (running) return
        running = true
        lastRange = range
        Dock.show(DockRow(DockKind.Sync, __t("Umsätze laden"), __t("%s · läuft im Hintergrund").format(bankName)))
        scope.launch {
            val result = runCatching { withFintsThread { decode(WimgJni.nativeFintsFetch(fetchBody(range.first, range.second))) } }.getOrNull()
            running = false
            when {
                result == null -> Dock.error(__t("Abruf fehlgeschlagen"), __t("%s · Bank nicht erreichbar").format(bankName), __t("Erneut")) { fetch(context, range, bankName, onDone) }
                result.status == "tan_required" -> {
                    pendingTan = result
                    Dock.show(DockRow(DockKind.Prompt, __t("TAN erforderlich"), __t("Für ältere Umsätze verlangt die Bank eine TAN.")))
                }
                result.imported != null || result.status == "ok" -> {
                    val n = result.imported ?: 0
                    context.getSharedPreferences(PREFS, 0).edit().putLong(KEY_LAST_FETCH, System.currentTimeMillis()).putInt(KEY_LAST_NEW, n).apply()
                    Changes.bump()
                    Dock.info(if (n == 1) __t("1 neuer Umsatz") else __t("%d neue Umsätze").format(n), result.duplicates?.takeIf { it > 0 }?.let { __t("%d schon vorhanden").format(it) })
                }
                else -> Dock.error(__t("Abruf fehlgeschlagen"), result.message ?: bankName)
            }
            onDone(result)
        }
    }
}

private enum class Step { Bank, Login, Medium, Tan, Range }

@Composable
fun FinTSScreen(navController: NavController? = null) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(PREFS, 0) }
    val scope = rememberCoroutineScope()

    var banks by remember { mutableStateOf<List<BankInfo>>(emptyList()) }
    var bank by remember { mutableStateOf<BankInfo?>(null) }
    var setup by remember { mutableStateOf(prefs.getString(KEY_BLZ, null) == null) }
    var step by remember { mutableStateOf(Step.Bank) }
    var kennung by remember { mutableStateOf(prefs.getString(KEY_KENNUNG, "") ?: "") }
    var pin by remember { mutableStateOf("") }
    var rememberPin by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var tan by remember { mutableStateOf<FintsResult?>(null) }
    var tanFor by remember { mutableStateOf("connect") }
    var tanInput by remember { mutableStateOf("") }
    var media by remember { mutableStateOf<List<TanMedium>>(emptyList()) }
    var rangeChoice by remember { mutableIntStateOf(365) }
    var moreOpen by remember { mutableStateOf(false) }
    var removeOpen by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }

    val notificationPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { }

    /** After a successful Schnellabfrage: schedule the daily background fetch. */
    fun armBackgroundRefresh() {
        BackgroundRefresh.enqueue(context)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU && !BackgroundRefresh.hasNotificationPermission(context)) {
            runCatching { notificationPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS) }
        }
    }

    LaunchedEffect(Unit) {
        WimgJni.nativeSetHttpCallback(FintsHttpCallback())
        banks = withFintsThread { WimgJni.nativeFintsGetBanks()?.let { runCatching { json.decodeFromString<List<BankInfo>>(it) }.getOrNull() } ?: emptyList() }
        prefs.getString(KEY_BLZ, null)?.let { blz -> bank = banks.find { it.blz == blz } }
    }
    // A fetch that ended in a TAN request continues here.
    LaunchedEffect(FintsJob.pendingTan) {
        FintsJob.pendingTan?.let { tan = it; tanFor = "fetch"; tanInput = ""; setup = true; step = Step.Tan; FintsJob.pendingTan = null }
    }

    fun goTan(r: FintsResult, forWhat: String) { tan = r; tanFor = forWhat; tanInput = ""; step = Step.Tan }

    fun startFetch(range: Pair<String, String>) {
        val name = bank?.name ?: "Bank"
        setup = false
        FintsJob.fetch(context, range, name) { r -> if (r?.imported != null) armBackgroundRefresh() }
    }

    /** After login or TAN: pick the TAN medium first if the bank wants one. */
    fun afterLogin(r: FintsResult, quick: Boolean) {
        if (r.tan_medium_required == true) {
            val saved = prefs.getString(KEY_TAN_MEDIUM, null)
            if (saved != null) {
                scope.launch {
                    withFintsThread { WimgJni.nativeFintsSetTanMedium(mediumBody(saved)) }
                    if (quick) startFetch(rangeDays(90)) else step = Step.Range
                }
                return
            }
            setup = true; step = Step.Medium; busy = true
            scope.launch {
                val m = withFintsThread { WimgJni.nativeFintsGetTanMedia()?.let { runCatching { json.decodeFromString<TanMediaResult>(it) }.getOrNull() } }
                busy = false
                when {
                    m == null || m.status != "ok" -> error = m?.message ?: __t("TAN-Geräte konnten nicht geladen werden")
                    m.media.isNullOrEmpty() -> step = if (quick) { startFetch(rangeDays(90)); Step.Range } else Step.Range
                    else -> media = m.media
                }
            }
            return
        }
        if (quick) startFetch(rangeDays(90)) else step = Step.Range
    }

    fun quickRefresh() {
        val b = bank ?: return
        val saved = prefs.getString(KEY_PIN, null)
        if (saved == null) { setup = true; step = Step.Login; return }
        if (FintsJob.running) return
        busy = true; error = null
        Dock.show(DockRow(DockKind.Sync, __t("Anmelden"), b.name))
        scope.launch {
            val r = runCatching { withFintsThread { decode(WimgJni.nativeFintsConnect(connectBody(b.blz, kennung, saved))) } }.getOrNull()
            busy = false
            when (r?.status) {
                "ok" -> afterLogin(r, quick = true)
                "tan_required" -> { Dock.dismiss(); setup = true; goTan(r, "connect-quick") }
                else -> {
                    // Wrong stored PIN: forget it so nothing retries it in the background.
                    prefs.edit().remove(KEY_PIN).apply()
                    BackgroundRefresh.cancel(context)
                    Dock.error(__t("Anmeldung fehlgeschlagen"), r?.message ?: __t("Bank nicht erreichbar"))
                    setup = true; step = Step.Login; pin = ""
                    error = r?.message ?: __t("Anmeldung fehlgeschlagen")
                }
            }
        }
    }

    fun login() {
        val b = bank ?: return
        busy = true; error = null
        scope.launch {
            val r = runCatching { withFintsThread { decode(WimgJni.nativeFintsConnect(connectBody(b.blz, kennung.trim(), pin))) } }.getOrNull()
            busy = false
            when (r?.status) {
                "ok" -> {
                    prefs.edit().putString(KEY_BLZ, b.blz).putString(KEY_KENNUNG, kennung.trim()).apply()
                    if (rememberPin) prefs.edit().putString(KEY_PIN, pin).apply() else prefs.edit().remove(KEY_PIN).apply()
                    afterLogin(r, quick = false)
                }
                "tan_required" -> {
                    prefs.edit().putString(KEY_BLZ, b.blz).putString(KEY_KENNUNG, kennung.trim()).apply()
                    if (rememberPin) prefs.edit().putString(KEY_PIN, pin).apply()
                    goTan(r, "connect")
                }
                null -> error = __t("Bank nicht erreichbar. Prüfe die Internetverbindung.")
                else -> error = r.message ?: __t("Anmeldung fehlgeschlagen")
            }
        }
    }

    fun sendTan() {
        val t = tan ?: return
        val decoupled = t.decoupled == true
        busy = true; error = null
        scope.launch {
            val r = runCatching { withFintsThread { decode(WimgJni.nativeFintsSendTan(tanBody(if (decoupled) "" else tanInput.trim()))) } }.getOrNull()
            busy = false
            when {
                r == null -> error = __t("Bank nicht erreichbar. Prüfe die Internetverbindung.")
                r.status == "tan_required" -> { tan = r; tanInput = ""; if (!decoupled) error = r.message }
                r.imported != null -> {
                    setup = false
                    prefs.edit().putLong(KEY_LAST_FETCH, System.currentTimeMillis()).putInt(KEY_LAST_NEW, r.imported).apply()
                    Changes.bump()
                    Dock.info(__t("%d neue Umsätze").format(r.imported))
                    armBackgroundRefresh()
                }
                r.status == "ok" -> when (tanFor) {
                    "fetch" -> startFetch(FintsJob.lastRange ?: rangeDays(90))
                    "connect-quick" -> afterLogin(r, quick = true)
                    else -> afterLogin(r, quick = false)
                }
                else -> error = r.message ?: __t("TAN abgelehnt")
            }
        }
    }

    // ---- bar ----
    val back: () -> Unit = {
        if (!setup) navController?.popBackStack()
        else when (step) {
            Step.Bank -> if (prefs.getString(KEY_BLZ, null) != null) setup = false else navController?.popBackStack()
            Step.Login -> step = Step.Bank
            else -> step = Step.Login
        }
        error = null
    }
    // System back walks the setup steps like the bar's ← does.
    androidx.activity.compose.BackHandler(enabled = setup && !(step == Step.Bank && prefs.getString(KEY_BLZ, null) == null)) { back() }
    val action: Pair<String, () -> Unit>? = if (!setup) {
        (if (busy || FintsJob.running) L("Läuft…") else L("Schnellabfrage")) to { quickRefresh() }
    } else when (step) {
        Step.Bank -> null
        Step.Login -> (if (busy) L("Anmelden…") else L("Anmelden")) to { if (!busy && kennung.isNotBlank() && pin.isNotBlank()) login() }
        Step.Medium -> null
        Step.Tan -> if (tan?.decoupled == true) (if (busy) L("Prüfe…") else L("Status prüfen")) to { if (!busy) sendTan() }
        else (if (busy) L("Sende…") else L("TAN senden")) to { if (!busy && tanInput.isNotBlank()) sendTan() }
        Step.Range -> L("Abrufen") to { startFetch(rangeDays(rangeChoice)) }
    }
    BarContribution(
        chip = null,
        panel = when {
            removeOpen -> { { RemovePanel(bank?.name ?: "", onCancel = { removeOpen = false }) { removeConnection(context); removeOpen = false; reload++; setup = true; step = Step.Bank; pin = "" } } }
            moreOpen -> { {
                BarPanel {
                    Row(
                        Modifier.fillMaxWidth().clip(WimgShape.dockAction).clickable { moreOpen = false; removeOpen = true }.padding(horizontal = 8.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.LinkOff, contentDescription = null, tint = Wimg.colors.danger, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(14.dp))
                        Text(L("Verbindung entfernen"), style = WimgType.button, color = Wimg.colors.danger)
                    }
                    Row(
                        Modifier.fillMaxWidth().clip(WimgShape.dockAction).clickable { moreOpen = false; setup = true; step = Step.Login; pin = "" }.padding(horizontal = 8.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.Lock, contentDescription = null, tint = Wimg.colors.text, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(14.dp))
                        Text(L("Neu anmelden"), style = WimgType.button, color = Wimg.colors.text)
                    }
                }
            } }
            else -> null
        },
        onPanelDismiss = { moreOpen = false; removeOpen = false },
        detail = DetailBarSpec(
            onBack = back,
            actionLabel = action?.first,
            actionIcon = if (!setup) Icons.Outlined.Refresh else null,
            onAction = action?.second ?: {},
            backLabel = if (setup) L("Zurück") else L("Einstellungen"),
            onMore = if (!setup) ({ moreOpen = !moreOpen }) else null,
        ),
    )

    if (!setup && bank != null) {
        BankDetail(bank!!, prefs, reload)
        return
    }
    if (!setup && bank == null && prefs.getString(KEY_BLZ, null) != null) {
        // Catalog still loading.
        BandScreen(band = { Text(L("Bankverbindung"), style = WimgType.title, color = Color.White) }) {}
        return
    }

    val stepIndex = when (step) { Step.Bank -> 1; Step.Login -> 2; Step.Medium, Step.Tan -> 3; Step.Range -> 4 }
    val title = when (step) {
        Step.Bank -> L("Bank wählen")
        Step.Login -> L("Anmeldung")
        Step.Medium -> L("TAN-Gerät")
        Step.Tan -> if (tan?.decoupled == true) L("Freigabe") else L("TAN")
        Step.Range -> L("Zeitraum")
    }
    val c = Wimg.colors
    BandScreen(
        band = {
            Text(L("Bank verbinden · Schritt %d von %d", stepIndex, 5), style = WimgType.bandOver, color = c.bandSub)
            Row(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (i in 1..5) Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(if (i <= stepIndex) Color.White else Color.White.copy(alpha = 0.18f)))
            }
            Text(title, style = WimgType.title.copy(fontSize = WimgType.title.fontSize * 1.15f), color = Color.White)
        },
    ) {
        when (step) {
            Step.Bank -> BankPicker(banks) { bank = it; step = Step.Login; error = null }
            Step.Login -> FormPage {
                bank?.let { BankChip(it) { step = Step.Bank } }
                Field(L("Kennung"), kennung, { kennung = it })
                Field(L("PIN"), pin, { pin = it }, secret = true)
                Row(Modifier.fillMaxWidth().padding(top = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(L("PIN merken"), style = WimgType.rowTitle.copy(fontSize = WimgType.rowTitle.fontSize * 1.07f), color = c.text)
                        Text(L("Verschlüsselt auf diesem Gerät · nötig für Schnellabfrage und Hintergrund-Abruf"), style = WimgType.desc, color = c.text2)
                    }
                    Spacer(Modifier.width(12.dp))
                    WimgToggle(rememberPin, { rememberPin = it }, label = L("PIN merken"))
                }
                if (error != null) ErrorBox(error!!)
                else Notice(L("Mehrere falsche PIN-Eingaben können dein Bankkonto sperren."))
            }
            Step.Medium -> FormPage {
                Text(L("Deine Bank möchte wissen, auf welches Gerät die TAN kommt."), style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 4.dp, bottom = 14.dp))
                if (busy) CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally).padding(20.dp), color = c.accent)
                WimgGroup {
                    media.forEachIndexed { i, m ->
                        if (i > 0) RowDivider()
                        WimgRow(m.name, desc = if (m.status == 1) null else L("inaktiv"), chevron = true, onClick = {
                            busy = true
                            scope.launch {
                                val r = withFintsThread { decode(WimgJni.nativeFintsSetTanMedium(mediumBody(m.name))) }
                                busy = false
                                if (r?.status == "ok") {
                                    prefs.edit().putString(KEY_TAN_MEDIUM, m.name).apply()
                                    if (tanFor == "connect-quick") startFetch(rangeDays(90)) else step = Step.Range
                                } else error = r?.message ?: __t("TAN-Gerät konnte nicht gesetzt werden")
                            }
                        })
                    }
                }
                if (error != null) ErrorBox(error!!)
            }
            Step.Tan -> TanPage(bank?.name ?: "", tan, tanInput, { tanInput = it }, busy, error, onAutoCheck = { if (!busy) sendTan() })
            Step.Range -> FormPage {
                Text(L("Wie weit zurück soll wimg beim ersten Abruf holen?"), style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 4.dp, bottom = 14.dp))
                WimgGroup {
                    listOf(90 to L("3 Monate"), 182 to L("6 Monate"), 365 to L("1 Jahr"), 730 to L("2 Jahre")).forEachIndexed { i, (days, label) ->
                        if (i > 0) RowDivider()
                        val on = rangeChoice == days
                        WimgRow(label, onClick = { rangeChoice = days }, leading = {
                            Box(Modifier.size(22.dp).clip(CircleShape).border(2.dp, if (on) c.ink else c.text3, CircleShape), contentAlignment = Alignment.Center) {
                                if (on) Box(Modifier.size(11.dp).clip(CircleShape).background(c.ink))
                            }
                        }, trailing = { if (days == 365) Text(L("empfohlen"), style = WimgType.desc, color = c.text2) })
                    }
                }
                QuietLine(L("Für Umsätze älter als 90 Tage verlangt die Bank oft eine zweite TAN. Dann erscheint der TAN-Schritt noch einmal."))
            }
        }
    }
}

@Composable
private fun FormPage(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = BarClearance), content = content)
}

@Composable
private fun BankChip(b: BankInfo, onChange: () -> Unit) {
    val c = Wimg.colors
    Row(Modifier.fillMaxWidth().clip(WimgShape.group).background(c.neutralTint).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(b.name, style = WimgType.button.copy(fontSize = WimgType.button.fontSize * 1.1f), color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(L("BLZ %s", b.blz.chunked(3).joinToString(" ")), style = WimgType.mono, color = c.text2)
        }
        Text(L("Ändern"), style = WimgType.chip, color = c.text, modifier = Modifier.clip(WimgShape.dockAction).background(c.card).clickable(onClick = onChange).padding(horizontal = 14.dp, vertical = 10.dp))
    }
}

@Composable
private fun Field(label: String, value: String, onChange: (String) -> Unit, secret: Boolean = false) {
    val c = Wimg.colors
    Text(label, style = WimgType.label.copy(fontSize = WimgType.label.fontSize * 1.1f), color = c.text, modifier = Modifier.padding(top = 18.dp, bottom = 8.dp))
    BasicTextField(
        value = value, onValueChange = onChange, singleLine = true,
        textStyle = WimgType.body.copy(fontSize = WimgType.body.fontSize * 1.1f, color = c.text),
        cursorBrush = SolidColor(c.accent),
        visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = if (secret) KeyboardOptions(keyboardType = KeyboardType.Password) else KeyboardOptions.Default,
        modifier = Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(horizontal = 16.dp, vertical = 18.dp),
    )
}

@Composable
private fun Notice(text: String) {
    val c = Wimg.colors
    Row(Modifier.padding(top = 18.dp).fillMaxWidth().clip(WimgShape.group).background(c.warnBg).padding(16.dp)) {
        Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = c.warn, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(text, style = WimgType.body, color = c.text)
    }
}

@Composable
private fun ErrorBox(text: String) {
    val c = Wimg.colors
    Row(Modifier.padding(top = 18.dp).fillMaxWidth().clip(WimgShape.group).background(c.dangerBg).padding(16.dp)) {
        Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = c.danger, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Column {
            Text(L("Meldung der Bank"), style = WimgType.desc, color = c.text2)
            Text(text, style = WimgType.body, color = c.text)
        }
    }
}

@Composable
private fun BankPicker(banks: List<BankInfo>, onPick: (BankInfo) -> Unit) {
    val c = Wimg.colors
    var q by remember { mutableStateOf("") }
    val shown = remember(banks, q) {
        val t = q.trim().lowercase().replace(" ", "")
        (if (t.isEmpty()) banks else banks.filter { it.name.lowercase().contains(q.trim().lowercase()) || it.blz.contains(t) }).take(60)
    }
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.padding(16.dp).fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(horizontal = 14.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Search, contentDescription = null, tint = c.text2, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
            Box(Modifier.weight(1f)) {
                if (q.isEmpty()) Text(L("Bank oder BLZ suchen"), style = WimgType.body, color = c.text2)
                BasicTextField(q, { q = it }, singleLine = true, textStyle = WimgType.body.copy(color = c.text), cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth())
            }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = BarClearance)) {
            items(shown, key = { it.blz + it.name }) { b ->
                Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).clip(WimgShape.dockAction).clickable { onPick(b) }.padding(horizontal = 4.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(36.dp).clip(WimgShape.iconTile).background(c.neutralTint), contentAlignment = Alignment.Center) {
                        Icon(Icons.Outlined.AccountBalance, contentDescription = null, tint = c.text, modifier = Modifier.size(19.dp))
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(b.name, style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(L("BLZ %s", b.blz.chunked(3).joinToString(" ")), style = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 0.92f), color = c.text2)
                    }
                }
            }
        }
    }
}

@Composable
private fun TanPage(bankName: String, tan: FintsResult?, input: String, onInput: (String) -> Unit, busy: Boolean, error: String?, onAutoCheck: () -> Unit) {
    val c = Wimg.colors
    val decoupled = tan?.decoupled == true
    // Check the app approval once automatically; the bar's "Status prüfen" retries.
    if (decoupled) LaunchedEffect(tan) { kotlinx.coroutines.delay(4000); onAutoCheck() }
    FormPage {
        Row(Modifier.fillMaxWidth().clip(WimgShape.group).background(c.neutralTint).padding(16.dp)) {
            Text(bankName, style = WimgType.button, color = c.text, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(if (decoupled) L("App-Freigabe") else if (tan?.phototan != null) "photoTAN" else "TAN", style = WimgType.body, color = c.text2)
        }
        if (decoupled) {
            Box(Modifier.padding(top = 28.dp).align(Alignment.CenterHorizontally).size(110.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.size(110.dp), color = c.ink, trackColor = c.neutralTint, strokeWidth = 5.dp)
                Icon(Icons.Outlined.PhoneAndroid, contentDescription = null, tint = c.text, modifier = Modifier.size(38.dp))
            }
            Text(L("Bitte in deiner Banking-App bestätigen"), style = WimgType.section.copy(fontSize = WimgType.section.fontSize * 1.15f), color = c.text, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 22.dp))
            Text(L("Öffne die App deiner Bank und gib den Abruf frei. Danach hier auf „Status prüfen“ tippen."), style = WimgType.body, color = c.text2, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
        } else {
            val bitmap = remember(tan?.phototan) {
                tan?.phototan?.let { b64 -> runCatching { Base64.decode(b64, Base64.DEFAULT).let { BitmapFactory.decodeByteArray(it, 0, it.size) } }.getOrNull() }
            }
            if (bitmap != null) {
                Image(
                    bitmap.asImageBitmap(), contentDescription = "photoTAN",
                    modifier = Modifier.padding(top = 20.dp).align(Alignment.CenterHorizontally).size(250.dp).clip(RoundedCornerShape(16.dp)).background(Color.White),
                )
                Text(L("Mit der photoTAN-App scannen und die TAN eingeben."), style = WimgType.body, color = c.text2, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
            }
            Field(L("TAN"), input, onInput)
        }
        val challenge = tan?.challenge?.takeIf { it.isNotBlank() }
        if (challenge != null) {
            Column(Modifier.padding(top = 20.dp).fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(16.dp)) {
                Text(L("Meldung der Bank"), style = WimgType.desc, color = c.text2)
                Text(challenge, style = WimgType.mono, color = c.text, modifier = Modifier.padding(top = 4.dp))
            }
        }
        if (error != null) ErrorBox(error)
        if (busy) Text(L("Warte auf die Bank…"), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 14.dp))
    }
}

@Composable
private fun BankDetail(b: BankInfo, prefs: android.content.SharedPreferences, reload: Int) {
    val context = LocalContext.current
    val c = Wimg.colors
    var accounts by remember { mutableStateOf<List<Account>>(emptyList()) }
    var count by remember { mutableIntStateOf(0) }
    var bg by remember { mutableStateOf(BackgroundRefresh.isEnabled(context)) }
    val hasPin = prefs.getString(KEY_PIN, null) != null
    LaunchedEffect(Changes.version, reload) {
        accounts = LibWimg.getAccounts()
        count = LibWimg.getTransactions().size
    }
    val withBalance = accounts.filter { it.balance != null }
    val lastAt = prefs.getLong(KEY_LAST_FETCH, 0)
    BandScreen(
        band = {
            if (withBalance.isNotEmpty()) {
                Text(L("%s · Kontostand", b.name), style = WimgType.bandOver, color = c.bandSub, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Amount(withBalance.sumOf { it.balance!! }, WimgType.amountHero, WimgType.amountHeroCents, Color.White, Modifier.padding(top = 2.dp), showPlus = false)
                Text(L("Stand %s · gebuchter Saldo, nicht live", WimgDates.full(withBalance.maxOf { it.balance_date })), style = WimgType.desc, color = c.bandSub, modifier = Modifier.padding(top = 4.dp))
            } else {
                Text(L("Bankverbindung"), style = WimgType.bandOver, color = c.bandSub)
                Text(b.name, style = WimgType.title, color = Color.White)
            }
        },
    ) {
        FormPage {
            WimgGroup {
                WimgRow(L("Kennung"), trailing = { Text(prefs.getString(KEY_KENNUNG, "") ?: "", style = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 1.15f), color = c.text) })
                RowDivider()
                WimgRow(L("PIN"), trailing = { Text(if (hasPin) L("gespeichert · nur auf diesem Gerät") else L("nicht gespeichert"), style = WimgType.body, color = c.text) })
                prefs.getString(KEY_TAN_MEDIUM, null)?.let { m ->
                    RowDivider()
                    WimgRow(L("TAN-Gerät"), trailing = { Text(m, style = WimgType.body, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis) })
                }
                RowDivider()
                WimgRow(L("Letzter Abruf"), trailing = {
                    Text(
                        if (lastAt == 0L) L("noch keiner") else L("%s · %d neue", WimgDates.short(iso(Calendar.getInstance().apply { timeInMillis = lastAt })), prefs.getInt(KEY_LAST_NEW, 0)),
                        style = WimgType.body, color = c.text,
                    )
                })
                RowDivider()
                WimgRow(L("Umsätze"), trailing = { Text("$count", style = WimgType.body, color = c.text) })
            }
            Spacer(Modifier.height(14.dp))
            WimgGroup {
                WimgRow(
                    L("Hintergrund-Abruf"),
                    desc = if (hasPin) L("Täglich, letzte 14 Tage · Mitteilung bei neuen Umsätzen oder „TAN erforderlich“") else L("Braucht die gespeicherte PIN"),
                    trailing = { WimgToggle(bg && hasPin, { v -> if (hasPin) { bg = v; BackgroundRefresh.setEnabled(context, v) } }, label = L("Hintergrund-Abruf")) },
                )
            }
            QuietLine(L("PIN und TAN-Gerät bleiben auf diesem Telefon. Sie werden nie synchronisiert."), icon = Icons.Outlined.Lock)
        }
    }
}

@Composable
private fun RemovePanel(bankName: String, onCancel: () -> Unit, onRemove: () -> Unit) {
    val c = Wimg.colors
    BarPanel {
        Text(L("%s entfernen?", bankName), style = WimgType.sheetTitle, color = c.text)
        Spacer(Modifier.height(12.dp))
        WimgGroup {
            WimgRow(L("Bleibt"), desc = L("Alle Umsätze und Kategorien"), leading = { Icon(Icons.Outlined.Check, contentDescription = null, tint = c.pos, modifier = Modifier.size(22.dp)) })
            RowDivider()
            WimgRow(L("Wird entfernt"), desc = L("Kennung, gespeicherte PIN, TAN-Gerät, Hintergrund-Abruf"), leading = { Icon(Icons.Outlined.LinkOff, contentDescription = null, tint = c.danger, modifier = Modifier.size(22.dp)) })
        }
        Row(Modifier.padding(top = 16.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.weight(1f).height(50.dp).clip(CircleShape).border(1.dp, c.line, CircleShape).pressable(onClick = onCancel), contentAlignment = Alignment.Center) {
                Text(L("Abbrechen"), style = WimgType.button, color = c.text)
            }
            Box(Modifier.weight(1f).height(50.dp).clip(CircleShape).background(c.danger).pressable(onClick = onRemove), contentAlignment = Alignment.Center) {
                Text(L("Entfernen"), style = WimgType.button, color = Color.White)
            }
        }
    }
}

/** Forgets the bank login on this device; transactions stay. Undo puts it back. */
private fun removeConnection(context: Context) {
    val p = context.getSharedPreferences(PREFS, 0)
    val saved = p.all.toMap()
    p.edit().remove(KEY_BLZ).remove(KEY_KENNUNG).remove(KEY_PIN).remove(KEY_TAN_MEDIUM).apply()
    val bgWasOn = BackgroundRefresh.isEnabled(context)
    BackgroundRefresh.cancel(context)
    Dock.undo(__t("Verbindung entfernt"), __t("Umsätze bleiben")) {
        p.edit().apply { saved.forEach { (k, v) -> when (v) { is String -> putString(k, v); is Int -> putInt(k, v); is Long -> putLong(k, v); is Boolean -> putBoolean(k, v) } } }.apply()
        if (bgWasOn) BackgroundRefresh.enqueue(context)
    }
}
