package com.wimg.app.services

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
    private const val SETTINGS_PREFS = "wimg_settings"
    private const val FINTS_PREFS = "wimg_fints"
    private const val KEY_BLZ = "fints_blz"
    private const val KEY_KENNUNG = "fints_kennung"
    private const val KEY_PIN = "fints_pin"
    private const val KEY_TAN_MEDIUM = "fints_tan_medium"

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
    fun hasCredentials(context: Context): Boolean {
        val prefs = context.getSharedPreferences(FINTS_PREFS, Context.MODE_PRIVATE)
        return prefs.getString(KEY_BLZ, null) != null &&
            prefs.getString(KEY_KENNUNG, null) != null &&
            prefs.getString(KEY_PIN, null) != null
    }

    // MARK: - Scheduling

    fun enqueue(context: Context) {
        if (!isEnabled(context) || !hasCredentials(context)) return

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()

        val request = PeriodicWorkRequestBuilder<BackgroundRefreshWorker>(
            1, TimeUnit.DAYS,
            6, TimeUnit.HOURS, // flex: run in the last 6h of each interval
        ).setConstraints(constraints).build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK_NAME,
            // UPDATE so a changed interval or constraint takes effect without
            // losing the existing schedule.
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
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
        val stored = context.getSharedPreferences("wimg", Context.MODE_PRIVATE)
            .getString("wimg_locale", "de") ?: "de"
        if (LocaleState.locale != stored) LocaleState.locale = stored
        return __t(key)
    }

    internal fun notify(context: Context, outcome: Outcome) {
        val body = when (outcome) {
            is Outcome.Imported -> {
                if (outcome.count <= 0) return
                if (outcome.count == 1) {
                    tr(context, "1 neuer Umsatz")
                } else {
                    tr(context, "%d neue Umsätze").format(outcome.count)
                }
            }
            Outcome.TanRequired -> {
                val prefs = context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                val last = prefs.getLong(TAN_LAST_NOTIFIED_KEY, 0L)
                val now = System.currentTimeMillis()
                if (last > 0 && now - last < TAN_COOLDOWN_MS) return
                prefs.edit().putLong(TAN_LAST_NOTIFIED_KEY, now).apply()
                tr(context, "TAN erforderlich — App öffnen")
            }
            Outcome.AuthFailed -> tr(context, "Anmeldung abgelaufen — bitte erneut anmelden")
            Outcome.Silent -> return
        }

        if (!hasNotificationPermission(context)) return
        ensureChannel(context)

        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("wimg")
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Permission revoked between the check above and the post — ignore.
        }
    }

    internal sealed interface Outcome {
        data class Imported(val count: Int) : Outcome
        data object TanRequired : Outcome
        data object AuthFailed : Outcome

        /** Ran fine, nothing new (or a transient error) — don't notify. */
        data object Silent : Outcome
    }

    // MARK: - The actual refresh

    @Serializable
    private data class FintsResult(
        val status: String? = null,
        val tan_medium_required: Boolean? = null,
        val imported: Int? = null,
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

    internal suspend fun runSilentRefresh(context: Context): Outcome {
        val prefs = context.getSharedPreferences(FINTS_PREFS, Context.MODE_PRIVATE)
        val blz = prefs.getString(KEY_BLZ, null) ?: return Outcome.Silent
        val kennung = prefs.getString(KEY_KENNUNG, null) ?: return Outcome.Silent
        val pin = prefs.getString(KEY_PIN, null) ?: return Outcome.Silent

        return try {
            val connect = withFintsThread {
                val input =
                    """{"blz":"$blz","user":"$kennung","pin":"$pin","product":"$PRODUCT_ID"}"""
                WimgJni.nativeFintsConnect(input)?.let { json.decodeFromString<FintsResult>(it) }
            } ?: return Outcome.Silent

            when (connect.status) {
                "tan_required" -> return Outcome.TanRequired
                "ok" -> Unit
                else -> {
                    // Same handling as the manual Schnellabfrage: a rejected PIN
                    // is worth clearing so the user is asked to re-enter it.
                    prefs.edit().remove(KEY_PIN).apply()
                    cancel(context)
                    return Outcome.AuthFailed
                }
            }

            // Restore the saved TAN medium if the bank insists on one.
            if (connect.tan_medium_required == true) {
                prefs.getString(KEY_TAN_MEDIUM, null)?.let { medium ->
                    withFintsThread { WimgJni.nativeFintsSetTanMedium("""{"name":"$medium"}""") }
                }
            }

            // 14-day window — just catching what's new since the last run.
            val cal = Calendar.getInstance()
            val to = isoDate(cal)
            cal.add(Calendar.DAY_OF_YEAR, -14)
            val from = isoDate(cal)

            val fetch = withFintsThread {
                WimgJni.nativeFintsFetch("""{"from":"$from","to":"$to"}""")
                    ?.let { json.decodeFromString<FintsResult>(it) }
            } ?: return Outcome.Silent

            if (fetch.status == "tan_required") return Outcome.TanRequired
            if (fetch.status != "ok") return Outcome.Silent // don't spam on transient errors

            val imported = fetch.imported ?: 0
            if (imported > 0) {
                WidgetDataWriter.writeSummary(context)
                Outcome.Imported(imported)
            } else {
                Outcome.Silent
            }
        } catch (_: Throwable) {
            Outcome.Silent
        }
    }

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
