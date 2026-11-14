package com.wimg.app.widget

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** What the widgets show, written by the app (WidgetDataWriter) after every change. */
@Serializable
data class WidgetData(
    val month: Int = 0,
    val available: Double = 0.0,
    val expenses: Double = 0.0,
    val perDay: Double = 0.0,
    /** Spending per category this month: (category id, amount), largest first. */
    val categories: List<Pair<Int, Double>> = emptyList(),
    val fixedOpen: Double = 0.0,
    val nextMerchant: String? = null,
    val nextDate: String? = null,
    val todaySum: Double = 0.0,
    val todayCount: Int = 0,
    val updatedAt: Long = 0,
    /** Gehaltsmonat: "calendar", "salary" or "day" ([startDay]). */
    val mode: String = "calendar",
    val startDay: Int = 1,
    val daysLeft: Int = 0,
    /** Salary is late: the day of the month it usually comes, else 0. */
    val overdueDay: Int = 0,
) {
    val hasData get() = updatedAt > 0

    companion object {
        private const val PREFS = "wimg_widget"
        private const val KEY = "wimg_widget_data_v2"
        private val json = Json { ignoreUnknownKeys = true }

        fun load(context: Context): WidgetData =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
                ?.let { runCatching { json.decodeFromString<WidgetData>(it) }.getOrNull() } ?: WidgetData()

        fun save(context: Context, data: WidgetData) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY, json.encodeToString(data)).remove("wimg_widget_data").apply()
        }

        /** Settings › "Beträge in Widgets ausblenden". */
        fun masked(context: Context) =
            context.getSharedPreferences("wimg_settings", Context.MODE_PRIVATE).getBoolean("wimg_widget_mask_amounts", false)
    }
}
