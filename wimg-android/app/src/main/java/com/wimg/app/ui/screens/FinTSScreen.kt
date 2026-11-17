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
import com.wimg.app.services.BankConnection
import com.wimg.app.services.BankConnections
import com.wimg.app.services.FintsHttpCallback
import com.wimg.app.services.PinStore
import com.wimg.app.ui.components.Amount
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.DockError
import com.wimg.app.ui.components.DockKind
import com.wimg.app.ui.components.DockRow
import com.wimg.app.ui.components.QuietLine
import com.wimg.app.ui.components.GroupLabel
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
    /** Every bank code of a fetch that got no statement (for the log, never shown). */
    val codes: String? = null,
    /** Connect: the bank's system id for this login, to keep. */
    val system_id: String? = null,
)

@Serializable
private data class TanMedium(val name: String, val status: Int = 1)

@Serializable
private data class TanMediaResult(val status: String = "", val media: List<TanMedium>? = null, val message: String? = null)

private val json = Json { ignoreUnknownKeys = true }

/** Run a block on a thread with 2MB stack (FinTS needs large buffers for Base64/MT940). */
internal suspend fun <T> withFintsThread(block: () -> T): T {
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

private const val PRODUCT = "F7C4049477F6136957A46EC28"

// Request bodies built as JSON objects, so a PIN or login with quotes or
// backslashes can't break the request.
private fun connectBody(blz: String, user: String, pin: String, systemId: String? = null) =
    buildJsonObject { put("blz", blz); put("user", user); put("pin", pin); put("product", PRODUCT); if (systemId != null) put("system_id", systemId) }.toString()

/**
 * Sign in with the system id kept for this login, and keep the one the bank
 * answers with (a new one only on the first sign-in or when the bank refused
 * the old one). Call on the FinTS thread, inside LibWimg.native.
 */
private fun connectKeepingId(context: Context, blz: String, user: String, pin: String): FintsResult? {
    val id = BankConnections.idFor(blz, user.trim())
    val kept = BankConnections.get(context, id)?.systemId
    val r = decode(WimgJni.nativeFintsConnect(connectBody(blz, user, pin, kept)))
    if (r?.status == "ok") r.system_id?.takeIf { it.length > 1 && it != kept }?.let { BankConnections.setSystemId(context, id, it) }
    return r
}
private fun tanBody(tan: String) = buildJsonObject { put("tan", tan) }.toString()
private fun fetchBody(from: String, to: String, camt: Boolean = false) = buildJsonObject { put("from", from); put("to", to); if (camt) put("format", "camt") }.toString()

/**
 * The bank answered, but not with statements, for reasons of its own (server
 * error, "send again", no statement part): worth one more try in the other
 * format. Never a refused login, a TAN or a missing PIN.
 */
private fun formatMayHelp(r: FintsResult?): Boolean {
    val m = r?.message ?: return false
    return r.status == "error" && !isAuthRejected(r) &&
        (m.startsWith("Bank asks to try again") || m.startsWith("No statement payload") || m.startsWith("Bank refused the request"))
}
private fun mediumBody(name: String) = buildJsonObject { put("name", name) }.toString()

private fun iso(c: Calendar) = "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
private fun rangeDays(days: Int): Pair<String, String> {
    val c = Calendar.getInstance()
    val to = iso(c)
    c.add(Calendar.DAY_OF_YEAR, -days)
    return iso(c) to to
}

/** The bank rejected the login (wrong Kennung/PIN, or blocked). libwimg reports it in English. */
private fun isAuthRejected(r: FintsResult?) = r?.status == "error" && r.message?.contains("Authentication", ignoreCase = true) == true

/** User-facing text for a libwimg/bank error; the bank's own (German) texts pass through. */
private fun bankText(r: FintsResult?): String = when {
    r == null -> __t("Bank nicht erreichbar. Prüfe die Internetverbindung und versuche es später noch einmal.")
    isAuthRejected(r) -> __t("Die Bank hat die Anmeldung abgelehnt. Bitte Kennung und PIN neu eingeben.")
    r.message.isNullOrBlank() -> __t("Die Bank hat den Auftrag nicht ausgeführt.")
    r.message.all { it.code < 128 } && r.message.contains(" failed") -> __t("Die Bank hat den Auftrag nicht ausgeführt.")
    else -> r.message
}

private fun forgetPin(context: Context, id: String) {
    // A wrong stored PIN must not be retried (daily background fetch), or the
    // bank locks the account after a few attempts.
    PinStore.clear(context, id)
    if (!BackgroundRefresh.hasCredentials(context)) BackgroundRefresh.cancel(context)
}

/** Route of one connection's page; the id holds the Kennung, so it is encoded. */
fun bankRoute(id: String, quick: Boolean = false) = "fints/" + android.net.Uri.encode(id) + if (quick) "?quick=1" else ""

private fun decode(r: String?): FintsResult? = r?.let { runCatching { json.decodeFromString<FintsResult>(it) }.getOrNull() }
    // Every bank error with all its codes (no PIN, no data): `adb logcat -s wimg-fints`.
    ?.also { if (it.status == "error") android.util.Log.w("wimg-fints", "${it.message} | ${it.codes ?: "-"}") }

/**
 * The statement fetch, kept outside any screen so it keeps running (and its
 * progress stays on the bar) when the user leaves the bank screens.
 */
private object FintsJob {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    var running by mutableStateOf(false)
        private set

    /** Connection whose login the bank rejected during a fetch: its page opens the login form. */
    var loginRequested by mutableStateOf<String?>(null)

    /** Last fetch needed a TAN: the challenge for that connection's page to pick up. */
    var pendingTan by mutableStateOf<FintsResult?>(null)
    var pendingTanFor: String? = null
    /** What the TAN is for: "fetch" (statements) or "connect-quick" (the login of a Schnellabfrage). */
    var pendingTanKind: String = "fetch"

    /**
     * Schnellabfrage from the list (↻ on a card): signs in with the saved PIN and
     * fetches the last 90 days without leaving the page. The bank's page opens
     * only when the bank wants something from the user (TAN, TAN device, login).
     */
    fun quick(context: Context, conn: com.wimg.app.services.BankConnection, range: Pair<String, String> = rangeDays(90), retried: Boolean = false, camt: Boolean? = null) {
        if (running) return
        val saved = PinStore.get(context, conn.id) ?: run { openPage(conn.id, quick = true); return }
        Dock.show(DockRow(DockKind.Sync, __t("Anmelden"), conn.name))
        scope.launch {
            val r = runCatching {
                withFintsThread {
                    com.wimg.app.bridge.LibWimg.native {
                        WimgJni.nativeSetHttpCallback(FintsHttpCallback())
                        connectKeepingId(context, conn.blz, conn.kennung, saved)
                    }
                }
            }.getOrNull()
            when {
                r == null -> Dock.error(__t("Schnellabfrage fehlgeschlagen"), bankText(null), __t("Erneut")) { quick(context, conn, range) }
                r.status == "ok" -> {
                    if (r.tan_medium_required == true) {
                        // No saved TAN device: the page asks for one.
                        val medium = conn.tanMedium ?: run { Dock.dismiss(); openPage(conn.id, quick = true); return@launch }
                        withFintsThread { com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsSetTanMedium(mediumBody(medium)) } }
                    } else conn.tanMedium?.let { m ->
                        // Known device: libwimg sends it whenever the bank wants names.
                        withFintsThread { com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsSetTanMedium(mediumBody(m)) } }
                    }
                    BackgroundRefresh.enqueue(context)
                    fetch(context, conn.id, range, conn.name, retried = retried, camt = camt)
                }
                r.status == "tan_required" -> {
                    Dock.dismiss()
                    pendingTanKind = "connect-quick"; pendingTanFor = conn.id; pendingTan = r
                    openPage(conn.id)
                }
                isAuthRejected(r) -> {
                    forgetPin(context, conn.id)
                    Dock.error(__t("Anmeldung abgelehnt"), bankText(r))
                    loginRequested = conn.id
                    openPage(conn.id)
                }
                else -> Dock.error(__t("Schnellabfrage fehlgeschlagen"), bankText(r))
            }
        }
    }

    /**
     * Fetch on open: when the newest fetch of a bank with a saved PIN is over 4 h
     * old, sign in and load the last 14 days without opening anything. The bar
     * shows "Umsätze laden" and then the new ones; a TAN becomes one quiet row
     * ("Bank will eine TAN · Abrufen"), other errors stay in the log. Tried at
     * most every 4 h, and only while "Im Hintergrund abrufen" is on.
     */
    fun onOpen(context: Context) {
        if (running || !BackgroundRefresh.isEnabled(context)) return
        val prefs = context.getSharedPreferences(OPEN_PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong(OPEN_TRIED_KEY, 0) < OPEN_STALE_MS) return
        val conn = BankConnections.all(context)
            .filter { now - it.lastFetchAt > OPEN_STALE_MS && PinStore.get(context, it.id) != null }
            .minByOrNull { it.lastFetchAt } ?: return
        val saved = PinStore.get(context, conn.id) ?: return
        prefs.edit().putLong(OPEN_TRIED_KEY, now).apply()
        running = true
        Dock.show(DockRow(DockKind.Sync, __t("Umsätze laden"), conn.name))
        val tanRow = { Dock.show(DockRow(DockKind.Prompt, __t("Bank will eine TAN"), conn.name, __t("Abrufen"), { quick(context, conn) }, timeoutMs = 10_000)) }
        scope.launch {
            val r = runCatching {
                withFintsThread {
                    com.wimg.app.bridge.LibWimg.native {
                        WimgJni.nativeSetHttpCallback(FintsHttpCallback())
                        connectKeepingId(context, conn.blz, conn.kennung, saved)
                    }
                }
            }.getOrNull()
            val medium = conn.tanMedium
            val f = if (r?.status == "ok" && (r.tan_medium_required != true || medium != null)) runCatching {
                withFintsThread {
                    if (medium != null) com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsSetTanMedium(mediumBody(medium)) }
                    val (from, to) = rangeDays(14)
                    decode(com.wimg.app.bridge.LibWimg.fintsFetch(fetchBody(from, to, conn.camt)))
                }
            }.getOrNull() else null
            running = false
            when {
                r?.status == "tan_required" || f?.status == "tan_required" -> tanRow()
                isAuthRejected(r) || isAuthRejected(f) -> {
                    forgetPin(context, conn.id)
                    Dock.error(__t("Anmeldung abgelehnt"), bankText(if (isAuthRejected(r)) r else f), __t("Neu anmelden")) {
                        loginRequested = conn.id
                        com.wimg.app.ui.components.NavRequest.route = bankRoute(conn.id)
                    }
                }
                // The bank failed on its side: the other format, quietly (signs in again).
                formatMayHelp(f) -> again(context, conn.id, rangeDays(14), conn.name, retried = true, camt = !conn.camt)
                f != null && (f.imported != null || f.status == "ok") -> {
                    val n = f.imported ?: 0
                    BankConnections.recordFetch(context, conn.id, n)
                    Changes.bump()
                    if (n > 0) fetchedDock(n, null, conn.name) else Dock.dismiss()
                }
                // Not reachable, bank hiccup, no TAN device yet: quiet (the error is in the log).
                else -> Dock.dismiss()
            }
        }
    }

    /**
     * Try a fetch again. libwimg forgets the PIN after every fetch, so a retry
     * signs in again with the saved PIN (like ↻); without one, the bank's page
     * opens for the login.
     */
    private fun again(context: Context, connId: String, range: Pair<String, String>, bankName: String, retried: Boolean = false, camt: Boolean? = null) {
        val conn = BankConnections.get(context, connId)
        if (conn != null && PinStore.get(context, connId) != null) quick(context, conn, range, retried, camt)
        else { Dock.dismiss(); openPage(connId) }
    }

    private fun openPage(id: String, quick: Boolean = false) {
        com.wimg.app.ui.components.NavRequest.onTop = true
        com.wimg.app.ui.components.NavRequest.route = bankRoute(id, quick)
    }
    var lastRange: Pair<String, String>? = null

    fun fetch(context: Context, connId: String, range: Pair<String, String>, bankName: String, retried: Boolean = false, camt: Boolean? = null, onDone: (FintsResult?) -> Unit = {}) {
        val useCamt = camt ?: (BankConnections.get(context, connId)?.camt ?: false)
        if (running) return
        running = true
        lastRange = range
        Dock.show(DockRow(DockKind.Sync, __t("Umsätze laden"), __t("%s · läuft im Hintergrund").format(bankName)))
        scope.launch {
            val result = runCatching { withFintsThread { decode(com.wimg.app.bridge.LibWimg.fintsFetch(fetchBody(range.first, range.second, useCamt))) } }.getOrNull()
            running = false
            // The bank failed on its side: once more, quietly, in the other format
            // (signing in again, the PIN is gone after a fetch). The bar keeps
            // saying "Umsätze laden"; which format works is remembered per bank.
            val formatTrouble = formatMayHelp(result)
            if (formatTrouble && !retried) {
                Dock.show(DockRow(DockKind.Sync, __t("Umsätze laden"), __t("%s · läuft im Hintergrund").format(bankName)))
                again(context, connId, range, bankName, retried = true, camt = !useCamt)
                return@launch
            }
            if (result != null && (result.imported != null || result.status == "ok")) BankConnections.setCamt(context, connId, useCamt)
            when {
                result == null -> Dock.error(__t("Abruf fehlgeschlagen"), bankText(null), __t("Erneut")) { again(context, connId, range, bankName) }
                formatTrouble -> Dock.error(__t("Abruf hat gerade nicht geklappt"), __t("%s antwortet gerade nicht richtig. Versuch es später noch einmal.").format(bankName), __t("Erneut")) { again(context, connId, range, bankName) }
                isAuthRejected(result) -> {
                    forgetPin(context, connId)
                    Dock.error(__t("Anmeldung abgelehnt"), bankText(result), __t("Neu anmelden")) {
                        loginRequested = connId
                        com.wimg.app.ui.components.NavRequest.route = bankRoute(connId)
                    }
                }
                result.status == "tan_required" -> {
                    pendingTan = result
                    pendingTanFor = connId
                    Dock.show(DockRow(DockKind.Prompt, __t("TAN erforderlich"), __t("Für ältere Umsätze verlangt die Bank eine TAN.")))
                }
                result.imported != null || result.status == "ok" -> {
                    val n = result.imported ?: 0
                    BankConnections.recordFetch(context, connId, n)
                    Changes.bump()
                    fetchedDock(n, result.duplicates?.takeIf { it > 0 }?.let { __t("%d schon vorhanden").format(it) }, BankConnections.get(context, connId)?.name)
                }
                else -> Dock.error(__t("Abruf fehlgeschlagen"), bankText(result))
            }
            onDone(result)
        }
    }
}

private enum class Step { Bank, Login, Medium, Tan, Range }

/** Umsätze, showing only [account] (a bank's statements land in the account named after it). */
private fun openTransactions(account: String?) {
    TxTarget.account = account
    com.wimg.app.ui.components.NavRequest.onTop = true
    com.wimg.app.ui.components.NavRequest.route = "transactions"
}

/** Result of a fetch on the bar; with new transactions, "Ansehen" opens them. */
private fun fetchedDock(n: Int, sub: String?, account: String?) {
    val title = if (n == 1) __t("1 neuer Umsatz") else __t("%d neue Umsätze").format(n)
    if (n <= 0) Dock.info(title, sub)
    else Dock.show(DockRow(DockKind.Info, title, sub, action = "Ansehen", onAction = { openTransactions(account) }, timeoutMs = 8_000))
}

@Composable
fun FinTSScreen(navController: NavController? = null, connectionId: String? = null, quickOnOpen: Boolean = false) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // null while adding a bank; set once its login worked.
    var connId by remember { mutableStateOf(connectionId?.takeIf { BankConnections.get(context, it) != null }) }
    var reload by remember { mutableIntStateOf(0) }
    val conn = remember(connId, reload, FintsJob.running) { connId?.let { BankConnections.get(context, it) } }
    // The catalog is loaded once per app run: with it in memory the bank's page
    // is there on the first frame (it used to open empty and fill in).
    var banks by remember { mutableStateOf(BankCatalog.banks.orEmpty()) }
    var bank by remember { mutableStateOf(BankCatalog.banks?.let { all -> connId?.let { id -> BankConnections.get(context, id) }?.let { c -> all.find { it.blz == c.blz } } }) }
    var setup by remember { mutableStateOf(connId == null) }
    var step by remember { mutableStateOf(Step.Bank) }
    var kennung by remember { mutableStateOf(conn?.kennung ?: "") }
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
    // "Ältere Umsätze holen": signed in with the saved PIN, then the Zeitraum step.
    var older by remember { mutableStateOf(false) }
    var removeOpen by remember { mutableStateOf(false) }

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
        com.wimg.app.bridge.LibWimg.native { WimgJni.nativeSetHttpCallback(FintsHttpCallback()) }
        banks = BankCatalog.load()
        if (bank == null) conn?.let { c -> bank = banks.find { it.blz == c.blz } }
    }
    LaunchedEffect(FintsJob.loginRequested) {
        if (FintsJob.loginRequested != null && FintsJob.loginRequested == connId) { FintsJob.loginRequested = null; setup = true; step = Step.Login; pin = ""; error = null }
    }
    // A fetch that ended in a TAN request continues on that bank's page.
    LaunchedEffect(FintsJob.pendingTan) {
        if (FintsJob.pendingTanFor != connId) return@LaunchedEffect
        FintsJob.pendingTan?.let { tan = it; tanFor = FintsJob.pendingTanKind; tanInput = ""; setup = true; step = Step.Tan; FintsJob.pendingTan = null; FintsJob.pendingTanKind = "fetch"; Dock.dismiss() }
    }

    fun goTan(r: FintsResult, forWhat: String) { tan = r; tanFor = forWhat; tanInput = ""; step = Step.Tan; Dock.dismiss() }

    fun startFetch(range: Pair<String, String>) {
        val id = connId ?: return
        val name = bank?.name ?: "Bank"
        setup = false; older = false
        FintsJob.fetch(context, id, range, name) { r -> if (r?.imported != null) armBackgroundRefresh() }
    }

    /** After login or TAN: pick the TAN medium first if the bank wants one. */
    fun afterLogin(r: FintsResult, quick: Boolean) {
        if (r.tan_medium_required != true) connId?.let { BankConnections.get(context, it)?.tanMedium }?.let { m ->
            // Known device: libwimg sends it whenever the bank wants names.
            scope.launch { withFintsThread { com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsSetTanMedium(mediumBody(m)) } } }
        }
        if (r.tan_medium_required == true) {
            val saved = connId?.let { BankConnections.get(context, it)?.tanMedium }
            if (saved != null) {
                scope.launch {
                    withFintsThread { com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsSetTanMedium(mediumBody(saved)) } }
                    if (quick) startFetch(rangeDays(90)) else step = Step.Range
                }
                return
            }
            setup = true; step = Step.Medium; busy = true
            scope.launch {
                val m = withFintsThread { com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsGetTanMedia() }?.let { runCatching { json.decodeFromString<TanMediaResult>(it) }.getOrNull() } }
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
        val id = connId ?: return
        val saved = PinStore.get(context, id)
        if (saved == null) { setup = true; step = Step.Login; return }
        if (FintsJob.running) return
        busy = true; error = null
        Dock.show(DockRow(DockKind.Sync, __t("Anmelden"), b.name))
        scope.launch {
            val r = runCatching { withFintsThread { com.wimg.app.bridge.LibWimg.native { connectKeepingId(context, b.blz, kennung, saved) } } }.getOrNull()
            busy = false
            when (r?.status) {
                "ok" -> afterLogin(r, quick = true)
                "tan_required" -> { Dock.dismiss(); setup = true; goTan(r, "connect-quick") }
                null -> {
                    // Not reached / no answer: nothing is wrong with the PIN. Keep it.
                    Dock.error(__t("Schnellabfrage fehlgeschlagen"), bankText(null), __t("Erneut")) { quickRefresh() }
                }
                else -> if (isAuthRejected(r)) {
                    forgetPin(context, id)
                    Dock.error(__t("Anmeldung abgelehnt"), bankText(r))
                    setup = true; step = Step.Login; pin = ""
                    error = bankText(r)
                } else {
                    Dock.error(__t("Schnellabfrage fehlgeschlagen"), bankText(r))
                }
            }
        }
    }

    // ↻ on a card in Bankverbindungen: run the Schnellabfrage once the catalog is in.
    // Saveable: coming back to this page (e.g. from "Ansehen") must not fetch again.
    var quickDone by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(bank) {
        if (quickOnOpen && !quickDone && bank != null && conn != null) { quickDone = true; quickRefresh() }
    }

    fun fetchOlder() {
        val b = bank ?: return
        val id = connId ?: return
        val saved = PinStore.get(context, id)
        if (FintsJob.running || busy) return
        older = true; rangeChoice = 365; error = null
        if (saved == null) { setup = true; step = Step.Login; return }
        busy = true
        Dock.show(DockRow(DockKind.Sync, __t("Anmelden"), b.name))
        scope.launch {
            val r = runCatching { withFintsThread { com.wimg.app.bridge.LibWimg.native { connectKeepingId(context, b.blz, kennung, saved) } } }.getOrNull()
            busy = false
            Dock.dismiss()
            when {
                r?.status == "ok" -> { setup = true; afterLogin(r, quick = false) }
                r?.status == "tan_required" -> { setup = true; goTan(r, "connect") }
                isAuthRejected(r) -> {
                    forgetPin(context, id)
                    setup = true; step = Step.Login; pin = ""
                    error = bankText(r)
                }
                else -> { older = false; Dock.error(__t("Anmeldung fehlgeschlagen"), bankText(r), __t("Erneut")) { fetchOlder() } }
            }
        }
    }

    /** The login worked: keep it as a connection (a changed Kennung replaces the old one). */
    fun saveLogin(b: BankInfo) {
        val id = BankConnections.idFor(b.blz, kennung.trim())
        val old = connId?.let { BankConnections.get(context, it) }
        if (old != null && old.id != id) BankConnections.remove(context, old.id)
        val existing = BankConnections.get(context, id)
        BankConnections.put(context, BankConnection(id, b.blz, kennung.trim(), b.name, existing?.tanMedium ?: old?.tanMedium, existing?.lastFetchAt ?: 0, existing?.lastFetchNew ?: 0, camt = existing?.camt ?: false, systemId = existing?.systemId))
        if (rememberPin) PinStore.set(context, id, pin) else PinStore.clear(context, id)
        connId = id
    }

    fun login() {
        val b = bank ?: return
        busy = true; error = null
        scope.launch {
            val r = runCatching { withFintsThread { com.wimg.app.bridge.LibWimg.native { connectKeepingId(context, b.blz, kennung.trim(), pin) } } }.getOrNull()
            busy = false
            when (r?.status) {
                "ok" -> {
                    saveLogin(b)
                    afterLogin(r, quick = false)
                }
                "tan_required" -> {
                    saveLogin(b)
                    goTan(r, "connect")
                }
                else -> error = bankText(r)
            }
        }
    }

    fun sendTan() {
        val t = tan ?: return
        val decoupled = t.decoupled == true
        busy = true; error = null
        // Waiting is shown on the bar (spinner on the button + this row), not on the page.
        Dock.show(DockRow(DockKind.Sync, __t("Warte auf die Bank…"), bank?.name))
        scope.launch {
            val r = runCatching { withFintsThread { decode(com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsSendTan(tanBody(if (decoupled) "" else tanInput.trim())) }) } }.getOrNull()
            busy = false
            Dock.dismiss()
            when {
                r == null -> error = bankText(null)
                r.status == "tan_required" -> { tan = r; tanInput = ""; if (!decoupled) error = r.message }
                r.imported != null -> {
                    setup = false
                    connId?.let { BankConnections.recordFetch(context, it, r.imported) }
                    Changes.bump()
                    fetchedDock(r.imported, null, connId?.let { BankConnections.get(context, it)?.name })
                    armBackgroundRefresh()
                }
                r.status == "ok" -> when (tanFor) {
                    "fetch" -> startFetch(FintsJob.lastRange ?: rangeDays(90))
                    "connect-quick" -> afterLogin(r, quick = true)
                    else -> afterLogin(r, quick = false)
                }
                else -> error = if (r.message.isNullOrBlank()) __t("TAN abgelehnt") else bankText(r)
            }
        }
    }

    // ---- bar ----
    val back: () -> Unit = {
        if (!setup) navController?.popBackStack()
        else if (older && step != Step.Login) { setup = false; older = false }
        else when (step) {
            Step.Bank -> if (conn != null) setup = false else navController?.popBackStack()
            Step.Login -> step = Step.Bank
            else -> step = Step.Login
        }
        error = null
    }
    // System back walks the setup steps like the bar's ← does.
    androidx.activity.compose.BackHandler(enabled = setup && !(step == Step.Bank && conn == null)) { back() }
    val action: Pair<String, () -> Unit>? = if (!setup) {
        L("Schnellabfrage") to { quickRefresh() }
    } else when (step) {
        Step.Bank -> null
        Step.Login -> L("Anmelden") to { if (!busy && kennung.isNotBlank() && pin.isNotBlank()) login() }
        Step.Medium -> null
        Step.Tan -> if (tan?.decoupled == true) L("Status prüfen") to { if (!busy) sendTan() }
        else L("TAN senden") to { if (!busy && tanInput.isNotBlank()) sendTan() }
        Step.Range -> L("Abrufen") to { startFetch(rangeDays(rangeChoice)) }
    }
    BarContribution(
        chip = null,
        panel = when {
            removeOpen -> { { RemovePanel(bank?.name ?: "", onCancel = { removeOpen = false }) { connId?.let { removeConnection(context, it) }; removeOpen = false; navController?.popBackStack() } } }
            moreOpen -> { {
                com.wimg.app.ui.components.BarMenu {
                    com.wimg.app.ui.components.MenuRow(Icons.Outlined.Lock, L("Neu anmelden")) { moreOpen = false; setup = true; step = Step.Login; pin = "" }
                    com.wimg.app.ui.components.MenuRow(Icons.Outlined.LinkOff, L("Verbindung entfernen"), danger = true) { moreOpen = false; removeOpen = true }
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
            backLabel = if (setup) L("Zurück") else L("Banken"),
            onMore = if (!setup) ({ moreOpen = !moreOpen }) else null,
            actionBusy = busy || FintsJob.running,
        ),
    )

    if (!setup && bank != null && conn != null) {
        BankDetail(bank!!, conn, reload, onOlder = { fetchOlder() }, onRename = { navController?.navigate("settings/accounts") })
        return
    }
    if (!setup && conn != null) {
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
            if (older) {
                Text(bank?.name ?: "", style = WimgType.bandOver, color = c.bandSub, modifier = Modifier.padding(bottom = 6.dp))
            } else {
                Text(L("Bank verbinden · Schritt %d von %d", stepIndex, 5), style = WimgType.bandOver, color = c.bandSub)
                Row(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (i in 1..5) Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(if (i <= stepIndex) Color.White else Color.White.copy(alpha = 0.18f)))
                }
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
                        Text(L("Verschlüsselt, nur auf diesem Gerät · nötig für Schnellabfrage und Hintergrund-Abruf"), style = WimgType.desc, color = c.text2)
                    }
                    Spacer(Modifier.width(12.dp))
                    WimgToggle(rememberPin, { rememberPin = it }, label = L("PIN merken"))
                }
                DockError(error, L("Meldung der Bank"))
                // Says where the login goes: an unknown app asking for a bank PIN
                // has to (testers, Play review).
                QuietLine(L("Kennung und PIN gehen direkt an deine Bank, nie an wimg."), Modifier.padding(top = 18.dp), icon = Icons.Outlined.Lock)
                QuietLine(L("Mehrere falsche PIN-Eingaben können dein Bankkonto sperren."), Modifier.padding(top = 8.dp), icon = Icons.Outlined.WarningAmber)
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
                                val r = withFintsThread { decode(com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsSetTanMedium(mediumBody(m.name)) }) }
                                busy = false
                                if (r?.status == "ok") {
                                    connId?.let { id -> BankConnections.update(context, id) { it.copy(tanMedium = m.name) } }
                                    if (tanFor == "connect-quick") startFetch(rangeDays(90)) else step = Step.Range
                                } else error = r?.message ?: __t("TAN-Gerät konnte nicht gesetzt werden")
                            }
                        })
                    }
                }
                DockError(error, L("Meldung der Bank"))
            }
            Step.Tan -> TanPage(bank?.name ?: "", tan, tanInput, { tanInput = it }, busy, error, onAutoCheck = { if (!busy) sendTan() })
            Step.Range -> FormPage {
                Text((if (older) L("Wie weit zurück soll wimg holen? Schon vorhandene Umsätze werden übersprungen.") else L("Wie weit zurück soll wimg beim ersten Abruf holen?")), style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 4.dp, bottom = 14.dp))
                WimgGroup {
                    listOf(90 to L("3 Monate"), 182 to L("6 Monate"), 365 to L("1 Jahr"), 730 to L("2 Jahre"), 3650 to L("So weit wie möglich")).forEachIndexed { i, (days, label) ->
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
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = barClearance()), content = content)
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
private fun Field(label: String, value: String, onChange: (String) -> Unit, secret: Boolean = false, numeric: Boolean = false) {
    val c = Wimg.colors
    Text(label, style = WimgType.label.copy(fontSize = WimgType.label.fontSize * 1.1f), color = c.text, modifier = Modifier.padding(top = 18.dp, bottom = 8.dp))
    BasicTextField(
        value = value, onValueChange = onChange, singleLine = true,
        textStyle = WimgType.body.copy(fontSize = WimgType.body.fontSize * 1.1f, color = c.text),
        cursorBrush = SolidColor(c.accent),
        visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = when {
            secret -> KeyboardOptions(keyboardType = KeyboardType.Password)
            numeric -> KeyboardOptions(keyboardType = KeyboardType.NumberPassword)
            else -> KeyboardOptions.Default
        },
        modifier = Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(horizontal = 16.dp, vertical = 18.dp),
    )
}

/**
 * Banks people use most, by the start of their name: listed first when the
 * search is empty and ahead of others in each match group. A tester looking
 * for "ing" found ING-DiBa below every bank in Solingen and Recklinghausen.
 */
private val POPULAR_BANKS = listOf(
    "ing", "dkb", "deutsche kreditbank", "comdirect", "sparkasse", "stadtsparkasse", "kreissparkasse",
    "volksbank", "commerzbank", "deutsche bank", "postbank", "consorsbank", "hypovereinsbank",
    "unicredit", "targobank", "1822direkt", "sparda", "psd bank", "norisbank", "santander",
)

private fun popularity(name: String): Int {
    val n = name.lowercase()
    val i = POPULAR_BANKS.indexOfFirst { n.startsWith(it) }
    return if (i < 0) POPULAR_BANKS.size else i
}

/**
 * Search order: name starts with the query, then a word in the name does
 * ("Deutsche Kreditbank" for "kre"), then the BLZ starts with it, then the
 * name contains it anywhere ("Solingen" for "ing"). Popular banks first within
 * each group, then the shorter name.
 */
private fun rankBanks(banks: List<BankInfo>, query: String): List<BankInfo> {
    val q = query.trim().lowercase()
    val digits = q.replace(" ", "")
    if (q.isEmpty()) return banks.sortedWith(compareBy({ popularity(it.name) }, { it.name.length }))
    fun group(b: BankInfo): Int {
        val n = b.name.lowercase()
        return when {
            n.startsWith(q) -> 0
            n.split(' ', '-', '(', '/', '.').any { it.startsWith(q) } -> 1
            digits.isNotEmpty() && b.blz.startsWith(digits) -> 2
            n.contains(q) || (digits.isNotEmpty() && b.blz.contains(digits)) -> 3
            else -> -1
        }
    }
    return banks.map { it to group(it) }.filter { it.second >= 0 }
        .sortedWith(compareBy({ it.second }, { popularity(it.first.name) }, { it.first.name.length }))
        .map { it.first }
}

@Composable
private fun BankPicker(banks: List<BankInfo>, onPick: (BankInfo) -> Unit) {
    val c = Wimg.colors
    var q by remember { mutableStateOf("") }
    val shown = remember(banks, q) { rankBanks(banks, q).take(60) }
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
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = barClearance())) {
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
            // TANs are digits (photoTAN, chipTAN, smsTAN): number pad.
            Field(L("TAN"), input, onInput, numeric = true)
        }
        val challenge = tan?.challenge?.takeIf { it.isNotBlank() }
        if (challenge != null) {
            Column(Modifier.padding(top = 20.dp).fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(16.dp)) {
                Text(L("Meldung der Bank"), style = WimgType.desc, color = c.text2)
                Text(challenge, style = WimgType.mono, color = c.text, modifier = Modifier.padding(top = 4.dp))
            }
        }
        DockError(error, L("Meldung der Bank"))
    }
}

/** Last known "Umsätze" count per bank, so the row doesn't flash 0 on the next visit. */
private object BankTxCount { val last = HashMap<String, Int>() }

@Composable
private fun BankDetail(b: BankInfo, conn: BankConnection, reload: Int, onOlder: () -> Unit, onRename: () -> Unit) {
    val context = LocalContext.current
    val c = Wimg.colors
    // Read before the first frame: loading it a frame later made the band switch
    // from "Bankverbindung" to the balance and pushed the whole page down.
    // A bank's statements land in the account named after it.
    var accounts by remember { mutableStateOf(LibWimg.ifFree { LibWimg.getAccounts() }.orEmpty().filter { it.id == conn.name }) }
    var count by remember { mutableIntStateOf(BankTxCount.last[conn.name] ?: 0) }
    var bg by remember { mutableStateOf(BackgroundRefresh.isEnabled(context)) }
    val hasPin = PinStore.has(context, conn.id)
    LaunchedEffect(Changes.version, reload) {
        val (a, n) = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            LibWimg.getAccounts().filter { it.id == conn.name } to LibWimg.getTransactionsFiltered(conn.name).size
        }
        accounts = a; count = n; BankTxCount.last[conn.name] = n
    }
    val withBalance = accounts.filter { it.balance != null }
    val lastAt = conn.lastFetchAt
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
                WimgRow(L("Kennung"), trailing = { Text(conn.kennung, style = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 1.15f), color = c.text) })
                RowDivider()
                WimgRow(L("PIN"), trailing = { Text(if (hasPin) L("verschlüsselt gespeichert · nur hier") else L("nicht gespeichert"), style = WimgType.body, color = c.text) })
                conn.tanMedium?.let { m ->
                    RowDivider()
                    WimgRow(L("TAN-Gerät"), trailing = { Text(m, style = WimgType.body, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis) })
                }
                RowDivider()
                WimgRow(L("Letzter Abruf"), trailing = {
                    Text(
                        (if (lastAt == 0L) L("noch keiner") else L("%s · %d neue", WimgDates.short(iso(Calendar.getInstance().apply { timeInMillis = lastAt })), conn.lastFetchNew)) + if (conn.camt) " · CAMT" else "",
                        style = WimgType.body, color = c.text,
                    )
                })
                RowDivider()
                WimgRow(L("Umsätze"), chevron = true, onClick = { openTransactions(conn.name) }, trailing = { Text("$count", style = WimgType.body, color = c.text) })
            }
            if (accounts.isNotEmpty()) {
                GroupLabel(L("Konten bei dieser Anmeldung"))
                AccountToggles(accounts, fetched = true)
                QuietLine(L("Ausgeblendete Konten zählen nicht in „Verfügbar“ und den Kategorien. Ihre Umsätze bleiben in der Suche."))
                WimgGroup {
                    accounts.forEach { a ->
                        WimgRow(L("Name in wimg"), desc = if (a.name != a.id) L("Von der Bank: %s", a.id) else L("Von der Bank"), chevron = true, onClick = onRename, trailing = { Text(a.name, style = WimgType.body, color = c.text2, maxLines = 1) })
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            WimgGroup {
                WimgRow(
                    L("Hintergrund-Abruf"),
                    desc = if (hasPin) L("Jeden Morgen und beim Öffnen, letzte 14 Tage · Mitteilung bei neuen Umsätzen oder „TAN erforderlich“") else L("Braucht die gespeicherte PIN"),
                    trailing = { WimgToggle(bg && hasPin, { v -> if (hasPin) { bg = v; BackgroundRefresh.setEnabled(context, v) } }, label = L("Hintergrund-Abruf")) },
                )
            }
            Spacer(Modifier.height(14.dp))
            WimgGroup {
                WimgRow(
                    L("Ältere Umsätze holen"),
                    desc = L("So weit zurück, wie deine Bank erlaubt · meist mit TAN"),
                    chevron = true, onClick = onOlder,
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
            Box(Modifier.weight(1f).height(50.dp).pressable(onClick = onCancel).clip(CircleShape).border(1.dp, c.line, CircleShape), contentAlignment = Alignment.Center) {
                Text(L("Abbrechen"), style = WimgType.button, color = c.text)
            }
            Box(Modifier.weight(1f).height(50.dp).pressable(onClick = onRemove).clip(CircleShape).background(c.danger), contentAlignment = Alignment.Center) {
                Text(L("Entfernen"), style = WimgType.button, color = Color.White)
            }
        }
    }
}

/** Forgets one bank login on this device; transactions stay. Undo puts it back. */
private fun removeConnection(context: Context, id: String) {
    val conn = BankConnections.get(context, id) ?: return
    val pin = PinStore.get(context, id)
    BankConnections.remove(context, id)
    if (!BackgroundRefresh.hasCredentials(context)) BackgroundRefresh.cancel(context)
    Dock.undo(__t("Verbindung entfernt"), __t("Umsätze bleiben")) {
        BankConnections.put(context, conn)
        pin?.let { PinStore.set(context, id, it) }
        BackgroundRefresh.enqueue(context)
        Changes.bump()
    }
}

/** The FinTS bank catalog (~1,750 banks), read from libwimg once per app run. */
private object BankCatalog {
    @Volatile var banks: List<BankInfo>? = null
        private set

    suspend fun load(): List<BankInfo> = banks ?: withFintsThread {
        com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsGetBanks() }?.let { runCatching { json.decodeFromString<List<BankInfo>>(it) }.getOrNull() } ?: emptyList()
    }.also { if (it.isNotEmpty()) banks = it }
}

/** Load the bank catalog ahead (WimgNavigation's background preload). */
internal suspend fun preloadBankCatalog() { BankCatalog.load() }

/** ↻ on a bank card: Schnellabfrage without leaving Bankverbindungen. */
internal fun quickRefreshFromList(context: Context, conn: com.wimg.app.services.BankConnection) = FintsJob.quick(context, conn)

/** Fetch on open (MainActivity.onResume); see [FintsJob.onOpen]. */
internal fun fetchOnOpen(context: Context) = FintsJob.onOpen(context)

/** A bank fetch is running (the Übersicht's freshness line says so). */
internal val fintsFetching: Boolean get() = FintsJob.running

/** Search › "Umsätze abrufen": the bank fetched longest ago, quick with its saved PIN (or its page). */
internal fun fetchFromSearch(context: Context): Boolean {
    val conn = BankConnections.all(context).minByOrNull { it.lastFetchAt } ?: return false
    FintsJob.quick(context, conn)
    return true
}

private const val OPEN_PREFS = "wimg_settings"
private const val OPEN_TRIED_KEY = "wimg_open_fetch_tried_at"
private const val OPEN_STALE_MS = 4L * 60 * 60 * 1000
