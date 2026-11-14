package com.wimg.app.services

import android.content.Context
import com.wimg.app.bridge.LibWimg
import com.wimg.app.widget.WidgetData
import com.wimg.app.widget.updateAllWidgets
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.Calendar
import kotlin.math.abs

/** Computes what the widgets show and hands it to them (they never touch libwimg). */
object WidgetDataWriter {
    fun writeSummary(context: Context) {
        val cal = Calendar.getInstance()
        val year = cal.get(Calendar.YEAR)
        val month = cal.get(Calendar.MONTH) + 1
        val monthKey = "%04d-%02d".format(year, month)
        val today = "%s-%02d".format(monthKey, cal.get(Calendar.DAY_OF_MONTH))

        // Gehaltsmonat: the running salary or "Fester Tag" period instead of the month.
        val periods = LibWimg.getPeriods(2)
        val period = periods?.takeIf { !it.isCalendar }?.current
        val summary = (if (period != null) LibWimg.getSummaryRange(period.from, period.to, null) else LibWimg.getSummaryFiltered(year, month, null)) ?: return
        val spent = abs(summary.expenses)
        val daysLeft = period?.let { com.wimg.app.ui.components.PeriodLabels.daysLeft(it) } ?: 0
        // by_category holds spending as positive amounts (same filter as Home).
        val byCategory = summary.by_category.filter { it.amount > 0.004 && it.id != com.wimg.app.models.WimgCategory.INCOME.id }.sortedByDescending { it.amount }

        // Same rule as the recurring page's "Noch offen".
        val fixed = LibWimg.getRecurring().filter { it.active == 1 && !it.isHidden && it.amount < 0 }
        val (from, to) = period?.let { it.from to it.to } ?: ("$monthKey-01" to "$monthKey-31")
        fun inRange(d: String?) = d != null && d >= from && d <= to
        val due = fixed.filter { inRange(it.last_seen) || inRange(it.next_due) || it.interval == "monthly" }
        val open = due.filter { !inRange(it.last_seen) }.sumOf { abs(it.amount) }
        val next = fixed.filter { (it.next_due ?: "") >= today }.minByOrNull { it.next_due!! }

        val todayTx = LibWimg.getTransactionsFiltered(null).filter { it.date == today && !it.isExcluded }

        val data = WidgetData(
            month = month,
            available = summary.available,
            expenses = spent,
            // Calendar: spent per day so far. Gehaltsmonat: what is left per remaining day.
            perDay = if (period != null) (if (daysLeft > 0) summary.available / daysLeft else 0.0) else spent / cal.get(Calendar.DAY_OF_MONTH),
            categories = byCategory.map { it.id to abs(it.amount) },
            fixedOpen = open,
            nextMerchant = next?.displayName,
            nextDate = next?.next_due,
            todaySum = todayTx.sumOf { it.amount },
            todayCount = todayTx.size,
            updatedAt = System.currentTimeMillis(),
            mode = periods?.mode ?: "calendar",
            startDay = periods?.day ?: 1,
            daysLeft = daysLeft,
            overdueDay = periods?.salary?.takeIf { periods.isSalary && it.overdue_days > 0 }?.day ?: 0,
        )
        WidgetData.save(context, data)
        CoroutineScope(Dispatchers.IO).launch {
            try { updateAllWidgets(context) } catch (e: Exception) { android.util.Log.w("wimg", "widget update failed", e) }
        }
    }
}
