package com.wimg.app.models

import kotlinx.serialization.Serializable
import kotlin.math.abs

@Serializable
data class Transaction(
    val id: String,
    val date: String,
    val description: String,
    val amount: Double,
    val currency: String = "EUR",
    val category: Int = 0,
    val account: String? = null,
    val excluded: Int? = null,
    /** Row title: the description without its booking type (libwimg booking.zig). */
    val title: String? = null,
    /** Booking type ("Lastschrift", "Karte", …) or "" when the bank sent none. */
    val kind: String? = null,
    /** Entered by hand (Umsatz von Hand): can be edited and deleted. */
    val manual: Boolean = false,
) {
    val displayTitle: String get() = title?.takeIf { it.isNotBlank() } ?: description
    val isExpense: Boolean get() = amount < 0
    val isIncome: Boolean get() = amount > 0
    val isExcluded: Boolean get() = (excluded ?: 0) != 0
}

@Serializable
data class ImportResult(
    val total_rows: Int,
    val imported: Int,
    val skipped_duplicates: Int,
    val errors: Int,
    val format: String,
    val categorized: Int,
)

@Serializable
data class ParseResult(
    val format: String,
    val total_rows: Int,
    val transactions: List<Transaction>,
    /** Statement files: the bank's account they go to, and what is already here. */
    val account: String = "",
    val duplicates: Int = 0,
)

@Serializable
data class UndoResult(
    val op: String,
    val table: String,
    val row_id: String,
    val column: String? = null,
)
