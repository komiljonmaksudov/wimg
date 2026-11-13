package com.wimg.app.models

import kotlinx.serialization.Serializable

@Serializable
data class Account(
    val id: String,
    val name: String,
    val bank: String = "",
    val color: String = "#007AFF",
    // Closing balance from the latest FinTS statement (cents). 0 = unknown.
    val balance_cents: Long = 0,
    val balance_date: String = "",
) {
    /// Statement closing balance in major units, or null if unknown (CSV-only).
    val balance: Double? get() = if (balance_date.isEmpty()) null else balance_cents / 100.0
}

@Serializable
data class RecurringPattern(
    val id: String,
    val merchant: String,
    val amount: Double,
    val interval: String,
    val category: Int,
    val last_seen: String,
    val next_due: String? = null,
    val active: Int = 1,
    val prev_amount: Double? = null,
    val price_change: Double? = null,
)

@Serializable
data class RecurringPayment(
    val id: String,
    val date: String,
    val amount: Double,
)

/** A categorisation rule: a text that, found in a booking, assigns a category. */
@Serializable
data class Rule(
    val id: Long,
    val pattern: String,
    val category: Int,
    /** 1 = learned from a manual change; higher = shipped with wimg. */
    val priority: Int,
)
