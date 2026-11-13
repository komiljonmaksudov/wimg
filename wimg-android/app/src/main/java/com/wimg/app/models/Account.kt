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
    /** Name the user gave it (edit panel); null = the detected merchant. */
    val name: String? = null,
    /** "Nicht wiederkehrend": listed only under Ausgeblendet. */
    val hidden: Int = 0,
    /** What detection found, before a fixed amount. */
    val detected_amount: Double? = null,
    /** 1 when the user set a fixed amount. */
    val fixed: Int = 0,
) {
    val displayName: String get() = name ?: merchant
    val isHidden: Boolean get() = hidden != 0
}

@Serializable
data class RecurringPayment(
    val id: String,
    val date: String,
    val amount: Double,
    /** Set aside as a one-off: shown crossed out, doesn't count for the pattern. */
    val oneoff: Boolean = false,
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
