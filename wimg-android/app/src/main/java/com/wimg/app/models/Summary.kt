package com.wimg.app.models

import kotlinx.serialization.Serializable

@Serializable
data class MonthlySummary(
    val year: Int,
    val month: Int,
    val income: Double,
    val expenses: Double,
    val available: Double,
    val tx_count: Int,
    val by_category: List<CategoryBreakdown> = emptyList(),
)

@Serializable
data class CategoryBreakdown(
    val id: Int,
    val name: String,
    val amount: Double,
    val count: Int,
)

/** One period: a calendar month, a salary period or a "Fester Tag" month. Dates ISO, [to] inclusive. */
@Serializable
data class PeriodInfo(
    val from: String,
    val to: String,
    val days: Int,
    val current: Boolean = false,
    /** Salary that started it (salary mode). */
    val salary: Double? = null,
    /** The salary came this many days before it was due. */
    val early_days: Int = 0,
)

@Serializable
data class SalaryInfo(
    val key: String,
    val title: String = "",
    val amount: Double = 0.0,
    /** Day of the month it usually comes. */
    val day: Int = 1,
    val count: Int = 0,
    val confirmed: Boolean = false,
    val last: String = "",
    val next: String = "",
    val overdue_days: Int = 0,
) {
    /** Short payer name ("MUSTER GMBH GEHALT"), without the month or reference. */
    val name: String get() = key.ifBlank { title }
}

@Serializable
data class OtherIncome(val id: String, val date: String, val amount: Double, val title: String = "", val key: String = "")

@Serializable
data class Payer(val key: String, val title: String = "", val amount: Double = 0.0, val count: Int = 0, val last: String = "")

/** What wimg_get_periods returns. [mode] is what applies; [chosen] what the user picked. */
@Serializable
data class Periods(
    val mode: String = "calendar",
    val chosen: String = "calendar",
    val day: Int = 1,
    val today: String = "",
    val salary: SalaryInfo? = null,
    val periods: List<PeriodInfo> = emptyList(),
    val other_income: List<OtherIncome> = emptyList(),
    val payers: List<Payer> = emptyList(),
) {
    val isSalary get() = mode == "salary"
    val isCalendar get() = mode == "calendar"
    val current: PeriodInfo? get() = periods.firstOrNull()
}
