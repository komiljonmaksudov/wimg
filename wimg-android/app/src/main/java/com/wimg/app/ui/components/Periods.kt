package com.wimg.app.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.PeriodInfo
import com.wimg.app.models.Periods
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Gehaltsmonat: what libwimg says "a month" is right now (calendar, salary to
 * salary, or a fixed start day). Loaded once per data change and shared by
 * every screen; libwimg does the detection and the maths.
 */
object PeriodState {
    var data by mutableStateOf<Periods?>(null)
        private set

    fun reload() { data = LibWimg.getPeriods(12) }

    /**
     * Gehalt / Kalender / Fester Tag. Only the periods reload: screens follow
     * [data]. A global Changes.bump here reloaded every list in the app on each
     * tap and made the switch feel stuck (sync pushes on resume anyway).
     */
    suspend fun setMode(mode: String, day: Int) = withContext(Dispatchers.IO) {
        LibWimg.setPeriodMode(mode, day)
        runCatching { reload() }
    }
}

/** The current periods, reloaded after every change. */
@Composable
fun rememberPeriods(): Periods? {
    // First use after a cold start: load once right away, so a screen opened
    // directly (notification, widget) doesn't draw a calendar month first.
    if (PeriodState.data == null) androidx.compose.runtime.remember { runCatching { PeriodState.reload() } }
    LaunchedEffect(Changes.version) { withContext(Dispatchers.IO) { runCatching { PeriodState.reload() } } }
    return PeriodState.data
}

object PeriodLabels {
    private fun parts(iso: String) = iso.split("-").mapNotNull { it.toIntOrNull() }

    /** "27.10." */
    fun dotted(iso: String): String = parts(iso).let { if (it.size == 3) "%02d.%02d.".format(it[2], it[1]) else iso }

    /** "27.10.–26.11." for chips. */
    fun short(p: PeriodInfo) = "${dotted(p.from)}–${dotted(p.to)}"

    /** "27. Okt. – 26. Nov." */
    fun long(p: PeriodInfo): String {
        val a = parts(p.from); val b = parts(p.to)
        if (a.size != 3 || b.size != 3) return short(p)
        return "${WimgDates.dayMonth(a[2], a[1])} – ${WimgDates.dayMonth(b[2], b[1])}"
    }

    /** Days from today to the period's last day, today included. */
    fun daysLeft(p: PeriodInfo): Int {
        val end = WimgDates.parse(p.to) ?: return 0
        val today = WimgDates.parse(WimgDates.todayIso()) ?: return 0
        return (((end.timeInMillis - today.timeInMillis) / 86_400_000L).toInt() + 1).coerceAtLeast(0)
    }

    /** Days since the period started, today counted. */
    fun daysIn(p: PeriodInfo): Int {
        val start = WimgDates.parse(p.from) ?: return 1
        val today = WimgDates.parse(WimgDates.todayIso()) ?: return 1
        return (((today.timeInMillis - start.timeInMillis) / 86_400_000L).toInt() + 1).coerceIn(1, p.days)
    }
}
