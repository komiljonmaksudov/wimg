package com.wimg.app.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import com.wimg.app.i18n.L
import com.wimg.app.ui.theme.LocaleState
import java.text.DateFormatSymbols
import java.util.Calendar
import java.util.Locale

/**
 * Date labels for the redesign. Copy rule: "Heute" / "Gestern" for the last two
 * days, otherwise "12. Nov."; the year only when it isn't the current one.
 * Dates come from libwimg as "YYYY-MM-DD" (no time).
 */
object WimgDates {
    private val locale: Locale get() = if (LocaleState.locale == "en") Locale.ENGLISH else Locale.GERMAN

    fun months(): Array<String> = DateFormatSymbols(locale).months
    fun shortMonths(): List<String> = DateFormatSymbols(locale).shortMonths.map { it.trimEnd('.') }

    fun parse(date: String): Calendar? {
        val p = date.split("-").mapNotNull { it.toIntOrNull() }
        if (p.size != 3) return null
        return Calendar.getInstance().apply { clear(); set(p[0], p[1] - 1, p[2]) }
    }

    fun todayIso(): String = Calendar.getInstance().let {
        "%04d-%02d-%02d".format(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1, it.get(Calendar.DAY_OF_MONTH))
    }

    private val en: Boolean get() = LocaleState.locale == "en"

    /** "12. Nov." (German), "12 Nov" (English). */
    // A no-break space: "26 Aug" never splits across lines.
    fun dayMonth(day: Int, month: Int): String =
        if (en) "$day\u00A0${shortMonths()[month - 1]}" else "$day.\u00A0${shortMonths()[month - 1]}."

    /** "27.10." (German), "27 Oct" (English): for compact ranges like "27.10.–26.11.". */
    fun numeric(day: Int, month: Int): String =
        if (en) "$day\u00A0${shortMonths()[month - 1]}" else "%02d.%02d.".format(day, month)

    /** "12. Nov." or "12. Nov. 2025" when not this year. */
    fun short(date: String): String {
        val c = parse(date) ?: return date
        val s = dayMonth(c.get(Calendar.DAY_OF_MONTH), c.get(Calendar.MONTH) + 1)
        return if (c.get(Calendar.YEAR) == Calendar.getInstance().get(Calendar.YEAR)) s else "$s ${c.get(Calendar.YEAR)}"
    }

    /** "1. Nov. 2026" */
    fun full(date: String): String {
        val c = parse(date) ?: return date
        return "${dayMonth(c.get(Calendar.DAY_OF_MONTH), c.get(Calendar.MONTH) + 1)} ${c.get(Calendar.YEAR)}"
    }

    /** "Do." (German), "Thu" (English). */
    private fun weekday(c: Calendar): String =
        DateFormatSymbols(locale).shortWeekdays[c.get(Calendar.DAY_OF_WEEK)].trimEnd('.') + (if (en) "" else ".")

    /** Day header: "Heute, Do. 12. Nov.", "Gestern, Mi. 11. Nov.", "Di. 10. Nov." */
    @Composable
    fun dayHeader(date: String): String {
        val c = parse(date) ?: return date
        val base = "${weekday(c)} ${short(date)}"
        return when (daysAgo(c)) {
            0 -> "${L("Heute")}, $base"
            1 -> "${L("Gestern")}, $base"
            else -> base
        }
    }

    /** Short day label: "Heute", "Gestern" or "Di. 10. Nov." */
    @Composable
    fun dayLabel(date: String): String {
        val c = parse(date) ?: return date
        return when (daysAgo(c)) {
            0 -> L("Heute")
            1 -> L("Gestern")
            else -> "${weekday(c)} ${short(date)}"
        }
    }

    private fun daysAgo(c: Calendar): Int {
        val today = Calendar.getInstance().apply { set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        return ((today.timeInMillis - c.timeInMillis) / 86_400_000L).toInt()
    }
}

/**
 * Bumped after any local change (category, exclude, undo) or a sync pull that
 * applied rows. Screens key their loading effect on [version].
 */
object Changes {
    var version by mutableIntStateOf(0)
        private set

    fun bump() { version++ }
}
