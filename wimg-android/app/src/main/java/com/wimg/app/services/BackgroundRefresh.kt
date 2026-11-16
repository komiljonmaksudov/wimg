package com.wimg.app.services

import kotlinx.serialization.json.put
import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.wimg.app.MainActivity
import com.wimg.app.R
import com.wimg.app.bridge.WimgJni
import com.wimg.app.i18n.__t
import com.wimg.app.ui.theme.LocaleState
import java.util.Calendar
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Periodic silent FinTS refresh via WorkManager + local notifications.
 * The Android counterpart of iOS `BackgroundRefresh.swift`.
 *
 * Flow:
 *   1. After a successful Schnellabfrage, FinTSScreen asks for notification
 *      permission (in context, not at launch) and calls [enqueue].
 *   2. WorkManager runs [BackgroundRefreshWorker] roughly daily.
 *   3. The worker connects with the stored PIN and fetches the last 14 days,
 *      then posts a notification describing the outcome.
 *
 * Why device-driven and not server-driven: the FinTS PIN lives only in this
 * app's SharedPreferences, and there is no reason to add a trust boundary just
 * to avoid waking the app for 30 seconds a day.
 *
 * Difference from iOS worth knowing: `BGAppRefreshTask` lets iOS learn a user's
 * habits and pick its own cadence. WorkManager has no equivalent, so this asks
 * for one run per day with a 6h flex window. Doze can still defer it well past
 * that on an idle phone — that is the platform, not a bug.
 */
object BackgroundRefresh {
    const val WORK_NAME = "wimg-background-refresh"
    const val ENABLED_KEY = "wimg_bg_refresh_enabled"

    private const val CHANNEL_ID = "wimg_refresh"
    private const val NOTIFICATION_ID = 4711
    private const val MONTH_END_NOTIFICATION_ID = 4712
    private const val MONTH_END_KEY = "wimg_month_end_notified"
    private const val SALARY_NOTIFICATION_ID = 4713
    private const val SALARY_KEY = "wimg_salary_notified"
    private const val SETTINGS_PREFS = "wimg_settings"
    private const val MORNING_KEY = "wimg_bg_morning_v1"

    /** Dedupe TAN notifications so a daily run on a TAN bank doesn't produce
     *  seven "TAN erforderlich" banners in a week. Mirrors iOS. */
    private const val TAN_COOLDOWN_MS = 24L * 60 * 60 * 1000
    private const val TAN_LAST_NOTIFIED_KEY = "wimg_bg_tan_notified_at"

    /** Product registration ID for HKVVB — same value FinTSScreen sends. */
    private const val PRODUCT_ID = "F7C4049477F6136957A46EC28"

    private val json = Json { ignoreUnknownKeys = true }

    // MARK: - Settings

    /** Opt-out toggle, default on. Read straight from SharedPreferences so the
     *  worker can honour it without any Compose state being built. */
    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
            .getBoolean(ENABLED_KEY, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(ENABLED_KEY, enabled).apply()
        if (enabled) enqueue(context) else cancel(context)
    }

    /** No stored PIN means nothing to refresh — don't schedule a wake-up. */
    fun hasCredentials(context: Context): Boolean =
        BankConnections.all(context).any { PinStore.has(context, it.id) }

    // MARK: - Mitteilungen (Einstellungen › Mitteilungen, board 20)

    const val NOTIFY_MONTH_END = "wimg_notify_month_end"
    const val NOTIFY_NEW_TX = "wimg_notify_new_tx"
    const val NOTIFY_TAN = "wimg_notify_tan"
    /** "Gehalt eingegangen" (off by default). */
    const val NOTIFY_SALARY = "wimg_notify_salary"
    /** "Nicht stören": "22-8" style start and end hour, or empty for off. */
    const val QUIET_HOURS = "wimg_quiet_hours"

    fun notifyOn(context: Context, key: String): Boolean =
        context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE).getBoolean(key, key != NOTIFY_SALARY)

    fun setNotify(context: Context, key: String, on: Boolean) =
        context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE).edit().putBoolean(key, on).apply()

    /** Start and end hour of the quiet time, or null when it is off. */
    fun quietHours(context: Context): Pair<Int, Int>? =
        context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE).getString(QUIET_HOURS, "")
            ?.split("-")?.mapNotNull { it.toIntOrNull() }?.takeIf { it.size == 2 }?.let { it[0] to it[1] }

    fun setQuietHours(context: Context, hours: Pair<Int, Int>?) =
        context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE).edit()
            .putString(QUIET_HOURS, hours?.let { "${it.first}-${it.second}" } ?: "").apply()

    private fun inQuietHours(context: Context): Boolean {
        val (from, to) = quietHours(context) ?: return false
        val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        return if (from <= to) h in from until to else h >= from || h < to
    }

    /** "Beträge ausblenden" is on: notifications carry no amounts. */
    internal fun amountsHidden(context: Context): Boolean =
        context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE).getBoolean("wimg_secure_screen", false)

    // MARK: - Scheduling

    fun enqueue(context: Context) {
        if (!isEnabled(context) || !hasCredentials(context)) return

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()

        // Every morning: the first run at the next 06:00, then every 24 h (Doze may
        // move it a little). The first look of the day is fresh; on open the app
        // fetches too when the last fetch is over 4 h old (FinTSScreen.fetchOnOpen).
        val now = java.util.Calendar.getInstance()
        val next = (now.clone() as java.util.Calendar).apply {
            set(java.util.Calendar.HOUR_OF_DAY, 6); set(java.util.Calendar.MINUTE, 0); set(java.util.Calendar.SECOND, 0)
            if (!after(now)) add(java.util.Calendar.DAY_OF_YEAR, 1)
        }
        val request = PeriodicWorkRequestBuilder<BackgroundRefreshWorker>(1, TimeUnit.DAYS)
            .setInitialDelay(next.timeInMillis - now.timeInMillis, TimeUnit.MILLISECONDS)
            .setConstraints(constraints).build()

        // A schedule from before the morning time keeps its old start: replace it once.
        val prefs = context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
        val moved = prefs.getBoolean(MORNING_KEY, false)
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK_NAME,
            if (moved) ExistingPeriodicWorkPolicy.KEEP else ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE,
            request,
        )
        if (!moved) prefs.edit().putBoolean(MORNING_KEY, true).apply()
    }

    /** Call when the user disables the toggle or clears their stored PIN. */
    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }

    // MARK: - Notifications

    /** True once the user can actually receive notifications. Android 13+ needs
     *  an explicit runtime grant; below that the permission is implicit. */
    fun hasNotificationPermission(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            tr(context, "Hintergrund-Aktualisierung"),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = tr(context, "Neue Umsätze und TAN-Hinweise")
        }
        manager.createNotificationChannel(channel)
    }

    /**
     * The worker runs before any Compose state exists, so `LocaleState.locale`
     * still holds its "de" default. Seed it from the same SharedPreferences
     * WimgTheme reads, otherwise background notifications are always German
     * regardless of the user's setting.
     */
    private fun tr(context: Context, key: String): String {
        val stored = LocaleState.stored(context)
        if (LocaleState.locale != stored) LocaleState.locale = stored
        return __t(key)
    }

    internal fun notify(context: Context, outcome: Outcome) {
        val bank = outcome.bank?.takeIf { it.isNotBlank() } ?: tr(context, "Deine Bank")
        when (outcome) {
            is Outcome.Imported -> {
                if (outcome.count <= 0 || !notifyOn(context, NOTIFY_NEW_TX)) return
                post(
                    context,
                    if (outcome.count == 1) tr(context, "1 neuer Umsatz") else tr(context, "%d neue Umsätze").format(outcome.count),
                    tr(context, "%s · Hintergrund-Abruf der letzten 14 Tage").format(bank),
                    route = "transactions",
                )
            }
            is Outcome.TanRequired -> {
                val prefs = context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                val last = prefs.getLong(TAN_LAST_NOTIFIED_KEY, 0L)
                val now = System.currentTimeMillis()
                if (!notifyOn(context, NOTIFY_TAN) || (last > 0 && now - last < TAN_COOLDOWN_MS)) return
                val sent = post(
                    context,
                    tr(context, "TAN erforderlich"),
                    tr(context, "%s möchte für den Abruf eine TAN. Höchstens eine solche Mitteilung pro Tag.").format(bank),
                    route = "fints",
                    action = tr(context, "Jetzt abrufen"),
                )
                if (sent) prefs.edit().putLong(TAN_LAST_NOTIFIED_KEY, now).apply()
            }
            is Outcome.AuthFailed -> post(
                context,
                tr(context, "Anmeldung abgelehnt"),
                tr(context, "%s hat die gespeicherte PIN abgelehnt. Melde dich einmal neu an.").format(bank),
                route = "fints",
            )
            Outcome.Silent -> Unit
        }
    }

    /**
     * Gehaltsmonat (board 26/08): when a salary or "Fester Tag" period ended,
     * the late salary, and "Gehalt eingegangen" in calendar mode.
     * Returns true when periods aren't calendar months (the month notice is skipped then).
     */
    internal fun notifyPeriods(context: Context, force: Boolean = false): Boolean {
        val periods = runCatching { com.wimg.app.bridge.LibWimg.getPeriods(3) }.getOrNull() ?: return false
        val prefs = context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
        val hide = amountsHidden(context)
        val salary = periods.salary
        val money = { v: Double -> com.wimg.app.ui.components.amountText(v, showPlus = false) }

        // The salary is late (after 3 days, once per expected date).
        if (periods.isSalary && salary != null && salary.overdue_days >= 3 && notifyOn(context, NOTIFY_MONTH_END)) {
            val key = "late:${salary.next}"
            if (force || prefs.getString(SALARY_KEY, null) != key) {
                if (post(context, tr(context, "Noch kein Gehalt von %s").format(salary.name),
                        tr(context, "Sonst kam es um den %d. Der Gehaltsmonat bleibt offen, bis es da ist.").format(salary.day),
                        route = "dashboard", id = SALARY_NOTIFICATION_ID, force = force)) prefs.edit().putString(SALARY_KEY, key).apply()
            }
        }
        // Calendar months, but the salary just came in.
        if (periods.isCalendar || periods.mode == "day") {
            if (salary != null && salary.confirmed && notifyOn(context, NOTIFY_SALARY)) {
                val key = "in:${salary.last}"
                val recent = salary.last >= com.wimg.app.ui.components.WimgDates.todayIso().let { t ->
                    Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -3) }.let { "%04d-%02d-%02d".format(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1, it.get(Calendar.DAY_OF_MONTH)) }
                }
                if ((force || prefs.getString(SALARY_KEY, null) != key) && recent) {
                    if (post(context, tr(context, "Gehalt ist da"), if (hide) salary.name else "${salary.name} · +${money(salary.amount)}",
                            route = "dashboard", id = SALARY_NOTIFICATION_ID, force = force)) prefs.edit().putString(SALARY_KEY, key).apply()
                }
            }
            if (periods.isCalendar) return false
        }

        val cur = periods.current ?: return true
        val prev = periods.periods.getOrNull(1) ?: return true
        if (!force && com.wimg.app.ui.components.PeriodLabels.daysIn(cur) > 5) return true
        val wanted = notifyOn(context, NOTIFY_MONTH_END) || (periods.isSalary && notifyOn(context, NOTIFY_SALARY))
        if (!force && !wanted) return true
        val key = "p:${prev.from}"
        if (!force && prefs.getString(MONTH_END_KEY, null) == key) return true
        val s = com.wimg.app.bridge.LibWimg.getSummaryRange(prev.from, prev.to, null) ?: return true
        if (s.tx_count == 0) return true
        val before = periods.periods.getOrNull(2)?.let { com.wimg.app.bridge.LibWimg.getSummaryRange(it.from, it.to, null) }
        val spent = kotlin.math.abs(s.expenses)
        val prevSpent = kotlin.math.abs(before?.expenses ?: 0.0)
        val pct = if (prevSpent > 0) kotlin.math.round((spent - prevSpent) / prevSpent * 100).toInt() else null
        val net = s.income - spent
        val (title, body) = if (periods.isSalary) {
            val parts = listOfNotNull(
                if (!hide && net >= 0) tr(context, "%s sind übrig geblieben").format(money(net)) else null,
                pct?.takeIf { it != 0 }?.let { if (it < 0) tr(context, "%d %% weniger ausgegeben als davor").format(-it) else tr(context, "%d %% mehr ausgegeben als davor").format(it) },
            )
            tr(context, "Gehalt ist da, dein Gehaltsmonat ist fertig") to
                (if (parts.isEmpty()) "" else parts.joinToString(", ").replaceFirstChar { it.uppercase() } + ". ") + tr(context, "Tippe für den Rückblick.")
        } else {
            val compare = pct?.takeIf { it != 0 }?.let { if (it < 0) tr(context, "Ausgaben %d %% unter dem Monat davor.").format(-it) else tr(context, "Ausgaben %d %% über dem Monat davor.").format(it) }
            tr(context, "Dein Monat bis zum %d. ist fertig").format(prev.to.takeLast(2).toInt()) to
                listOfNotNull(compare, tr(context, "Tippe für den Rückblick.")).joinToString(" ")
        }
        if (post(context, title, body, route = "review", id = MONTH_END_NOTIFICATION_ID, period = prev.from, force = force)) {
            prefs.edit().putString(MONTH_END_KEY, key).apply()
        }
        return true
    }

    /** Month-end notice (board 13): once per month in its first days, opens Rückblick. */
    internal fun notifyMonthEnd(context: Context, force: Boolean = false) {
        if (notifyPeriods(context, force)) return
        val cal = Calendar.getInstance()
        if (!force && (cal.get(Calendar.DAY_OF_MONTH) > 5 || !notifyOn(context, NOTIFY_MONTH_END))) return
        cal.add(Calendar.MONTH, -1)
        val year = cal.get(Calendar.YEAR)
        val month = cal.get(Calendar.MONTH) + 1
        val key = "%04d-%02d".format(year, month)
        val prefs = context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
        if (!force && prefs.getString(MONTH_END_KEY, null) == key) return
        val summary = runCatching { com.wimg.app.bridge.LibWimg.getSummaryFiltered(year, month, null) }.getOrNull() ?: return
        if (summary.tx_count == 0) return

        val names = java.text.DateFormatSymbols(if (LocaleState.locale == "en") java.util.Locale.ENGLISH else java.util.Locale.GERMAN).months
        cal.add(Calendar.MONTH, -1)
        val prev = runCatching { com.wimg.app.bridge.LibWimg.getSummaryFiltered(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, null) }.getOrNull()
        val spent = kotlin.math.abs(summary.expenses)
        val prevSpent = kotlin.math.abs(prev?.expenses ?: 0.0)
        val compare = if (prevSpent > 0) {
            val pct = kotlin.math.round((spent - prevSpent) / prevSpent * 100).toInt()
            when {
                pct < 0 -> tr(context, "Ausgaben %d %% unter %s.").format(-pct, names[cal.get(Calendar.MONTH)])
                pct > 0 -> tr(context, "Ausgaben %d %% über %s.").format(pct, names[cal.get(Calendar.MONTH)])
                else -> tr(context, "Ausgaben wie im %s.").format(names[cal.get(Calendar.MONTH)])
            }
        } else ""
        val sent = post(
            context,
            tr(context, "Dein %s ist abgeschlossen").format(names[month - 1]),
            listOf(compare, tr(context, "Tippe für deinen Monatsabschluss.")).filter { it.isNotEmpty() }.joinToString(" "),
            route = "review",
            id = MONTH_END_NOTIFICATION_ID,
            month = key,
            force = force,
        )
        // Not sent in the quiet time: tomorrow's run tries again.
        if (sent) prefs.edit().putString(MONTH_END_KEY, key).apply()
    }

    private fun post(context: Context, title: String, body: String, route: String, action: String? = null, id: Int = NOTIFICATION_ID, month: String? = null, force: Boolean = false, period: String? = null): Boolean {
        if (!hasNotificationPermission(context)) return false
        if (!force && inQuietHours(context)) return false
        ensureChannel(context)
        val open = PendingIntent.getActivity(
            context,
            route.hashCode(),
            Intent(context, MainActivity::class.java)
                .putExtra(MainActivity.EXTRA_ROUTE, route)
                .apply { if (month != null) putExtra(MainActivity.EXTRA_MONTH, month) }
                .apply { if (period != null) putExtra(MainActivity.EXTRA_PERIOD, period) }
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(open)
        if (action != null) builder.addAction(0, action, open)
        return try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
            true
        } catch (_: SecurityException) {
            // Permission revoked between the check above and the post — ignore.
            false
        }
    }

    internal sealed interface Outcome {
        /** Bank the outcome is about, for the notification text. */
        val bank: String? get() = null

        data class Imported(val count: Int, override val bank: String? = null) : Outcome
        data class TanRequired(override val bank: String? = null) : Outcome
        data class AuthFailed(override val bank: String? = null) : Outcome

        /** Ran fine, nothing new (or a transient error) — don't notify. */
        data object Silent : Outcome
    }

    // MARK: - The actual refresh

    @Serializable
    private data class FintsResult(
        val status: String? = null,
        val message: String? = null,
        val tan_medium_required: Boolean? = null,
        val imported: Int? = null,
        val codes: String? = null,
        val system_id: String? = null,
    )

    /**
     * FinTS needs a big stack for Base64/MT940 buffers; the default thread
     * overflows. Same 2MB trick FinTSScreen uses (kept separate so the UI
     * layer doesn't have to be refactored to expose its private helper).
     */
    private suspend fun <T> withFintsThread(block: () -> T): T =
        suspendCancellableCoroutine { cont ->
            val thread = Thread(null, {
                try {
                    cont.resumeWith(Result.success(block()))
                } catch (e: Throwable) {
                    cont.resumeWith(Result.failure(e))
                }
            }, "fints-bg-worker", 2 * 1024 * 1024)
            thread.start()
        }

    /**
     * Every bank with a saved PIN, one after another (libwimg holds one bank
     * session at a time). New transactions are added up into one notification;
     * a TAN request or a rejected login is reported for the first bank it hit.
     */
    internal suspend fun runSilentRefresh(context: Context): Outcome {
        val outcomes = BankConnections.all(context).filter { PinStore.has(context, it.id) }.map { refreshOne(context, it) }
        val imported = outcomes.filterIsInstance<Outcome.Imported>()
        if (imported.isNotEmpty()) {
            WidgetDataWriter.writeSummary(context)
            return Outcome.Imported(imported.sumOf { it.count }, imported.singleOrNull()?.bank ?: tr(context, "Deine Banken"))
        }
        return outcomes.firstOrNull { it is Outcome.AuthFailed } ?: outcomes.firstOrNull { it is Outcome.TanRequired } ?: Outcome.Silent
    }

    private suspend fun refreshOne(context: Context, conn: BankConnection, camt: Boolean = conn.camt, retried: Boolean = false): Outcome {
        val blz = conn.blz
        val kennung = conn.kennung
        val pin = PinStore.get(context, conn.id) ?: return Outcome.Silent

        return try {
            val connect = withFintsThread {
                val input =
                    kotlinx.serialization.json.buildJsonObject { put("blz", blz); put("user", kennung); put("pin", pin); put("product", PRODUCT_ID); conn.systemId?.let { put("system_id", it) } }.toString()
                com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsConnect(input) }?.let { json.decodeFromString<FintsResult>(it) }
            } ?: return Outcome.Silent
            // Keep the bank's system id for the next sign-in.
            if (connect.status == "ok") connect.system_id?.takeIf { it.length > 1 && it != conn.systemId }?.let { BankConnections.setSystemId(context, conn.id, it) }

            when (connect.status) {
                "tan_required" -> return Outcome.TanRequired(conn.name)
                "ok" -> Unit
                else -> {
                    // Only a real rejection clears the PIN (retrying a wrong PIN daily
                    // gets the account locked). Anything else may be the bank being
                    // briefly down: try again tomorrow.
                    if (!isAuthRejected(connect)) return Outcome.Silent
                    PinStore.clear(context, conn.id)
                    if (!hasCredentials(context)) cancel(context)
                    return Outcome.AuthFailed(conn.name)
                }
            }

            // Restore the saved TAN medium; libwimg sends it whenever the bank wants names.
            run {
                conn.tanMedium?.let { medium ->
                    withFintsThread { com.wimg.app.bridge.LibWimg.native { WimgJni.nativeFintsSetTanMedium(kotlinx.serialization.json.buildJsonObject { put("name", medium) }.toString()) } }
                }
            }

            // 14-day window — just catching what's new since the last run.
            val cal = Calendar.getInstance()
            val to = isoDate(cal)
            cal.add(Calendar.DAY_OF_YEAR, -14)
            val from = isoDate(cal)

            val fetch = withFintsThread {
                com.wimg.app.bridge.LibWimg.fintsFetch(kotlinx.serialization.json.buildJsonObject { put("from", from); put("to", to); if (camt) put("format", "camt") }.toString())
                    ?.let { json.decodeFromString<FintsResult>(it) }
            } ?: return Outcome.Silent

            if (fetch.status == "tan_required") return Outcome.TanRequired(conn.name)
            if (isAuthRejected(fetch)) {
                PinStore.clear(context, conn.id)
                if (!hasCredentials(context)) cancel(context)
                return Outcome.AuthFailed(conn.name)
            }
            if (fetch.status != "ok") {
                fetch.codes?.let { android.util.Log.w("wimg-fints", "background fetch $from..$to: ${fetch.message} | $it") }
                // The bank failed on its side: once more in the other format (signs in again).
                val m = fetch.message.orEmpty()
                if (!retried && (m.startsWith("Bank asks to try again") || m.startsWith("No statement payload") || m.startsWith("Bank refused the request")))
                    return refreshOne(context, conn, camt = !camt, retried = true)
                return Outcome.Silent // don't spam on transient errors
            }
            BankConnections.setCamt(context, conn.id, camt)

            val imported = fetch.imported ?: 0
            // Same fields the bank page shows as "Letzter Abruf".
            BankConnections.recordFetch(context, conn.id, imported)
            if (imported > 0) {
                Outcome.Imported(imported, conn.name)
            } else {
                Outcome.Silent
            }
        } catch (_: Throwable) {
            Outcome.Silent
        }
    }

    /** libwimg reports a rejected login as status "error" + "Authentication failed". */
    private fun isAuthRejected(r: FintsResult) =
        r.status == "error" && r.message?.contains("Authentication", ignoreCase = true) == true

    private fun isoDate(cal: Calendar): String = String.format(
        "%04d-%02d-%02d",
        cal.get(Calendar.YEAR),
        cal.get(Calendar.MONTH) + 1,
        cal.get(Calendar.DAY_OF_MONTH),
    )
}

class BackgroundRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        // The toggle may have been flipped since this run was scheduled.
        if (!BackgroundRefresh.isEnabled(applicationContext)) {
            BackgroundRefresh.cancel(applicationContext)
            return Result.success()
        }
        if (!BackgroundRefresh.hasCredentials(applicationContext)) return Result.success()

        val outcome = BackgroundRefresh.runSilentRefresh(applicationContext)
        BackgroundRefresh.notify(applicationContext, outcome)
        return Result.success()
    }
}

/** Daily, independent of the bank: posts the month-end notice in a month's first days. */
class MonthEndWorker(appContext: Context, params: WorkerParameters) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        runCatching { BackgroundRefresh.notifyMonthEnd(applicationContext) }
        return Result.success()
    }

    companion object {
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<MonthEndWorker>(1, TimeUnit.DAYS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork("wimg-month-end", ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
