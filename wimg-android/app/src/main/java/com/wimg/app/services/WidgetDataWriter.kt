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

        val summary = LibWimg.getSummaryFiltered(year, month, null) ?: return
        val spent = abs(summary.expenses)
        // by_category holds spending as positive amounts (same filter as Home).
        val byCategory = summary.by_category.filter { it.amount > 0.004 && it.id != com.wimg.app.models.WimgCategory.INCOME.id }.sortedByDescending { it.amount }

        // Same rule as the recurring page's "Noch offen".
        val fixed = LibWimg.getRecurring().filter { it.active == 1 && it.amount < 0 }
        val due = fixed.filter { it.last_seen.startsWith(monthKey) || (it.next_due ?: "").startsWith(monthKey) || it.interval == "monthly" }
        val open = due.filter { !it.last_seen.startsWith(monthKey) }.sumOf { abs(it.amount) }
        val next = fixed.filter { (it.next_due ?: "") >= today }.minByOrNull { it.next_due!! }

        val todayTx = LibWimg.getTransactions().filter { it.date == today && !it.isExcluded }

        val data = WidgetData(
            month = month,
            available = summary.available,
            expenses = spent,
            perDay = spent / cal.get(Calendar.DAY_OF_MONTH),
            categories = byCategory.map { it.id to abs(it.amount) },
            fixedOpen = open,
            nextMerchant = next?.merchant,
            nextDate = next?.next_due,
            todaySum = todayTx.sumOf { it.amount },
            todayCount = todayTx.size,
            updatedAt = System.currentTimeMillis(),
        )
        WidgetData.save(context, data)
        CoroutineScope(Dispatchers.IO).launch {
            try { updateAllWidgets(context) } catch (e: Exception) { android.util.Log.w("wimg", "widget update failed", e) }
        }
    }
}
