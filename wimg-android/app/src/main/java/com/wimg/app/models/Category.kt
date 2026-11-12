package com.wimg.app.models

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

enum class WimgCategory(
    val id: Int,
    val label: String,
    val color: Color,
    val icon: ImageVector,
) {
    UNCATEGORIZED(0, "Sonstiges", Color(0xFF8E8E93), Icons.Outlined.HelpCenter),
    GROCERIES(1, "Lebensmittel", Color(0xFF34C759), Icons.Outlined.ShoppingCart),
    DINING(2, "Essen gehen", Color(0xFFFF9500), Icons.Outlined.Restaurant),
    TRANSPORT(3, "Transport", Color(0xFF007AFF), Icons.Outlined.DirectionsCar),
    HOUSING(4, "Wohnen", Color(0xFFAF52DE), Icons.Outlined.Home),
    UTILITIES(5, "Nebenkosten", Color(0xFF5AC8FA), Icons.Outlined.Bolt),
    ENTERTAINMENT(6, "Unterhaltung", Color(0xFFFF2D55), Icons.Outlined.SportsEsports),
    SHOPPING(7, "Shopping", Color(0xFFFF6482), Icons.Outlined.ShoppingBag),
    HEALTH(8, "Gesundheit", Color(0xFFFF3B30), Icons.Outlined.FavoriteBorder),
    INSURANCE(9, "Versicherung", Color(0xFF64D2FF), Icons.Outlined.Shield),
    INCOME(10, "Einkommen", Color(0xFF30D158), Icons.Outlined.NorthEast),
    TRANSFER(11, "Umbuchung", Color(0xFF8E8E93), Icons.Outlined.SwapHoriz),
    CASH(12, "Bargeld", Color(0xFFFFD60A), Icons.Outlined.Payments),
    SUBSCRIPTIONS(13, "Abonnements", Color(0xFFBF5AF2), Icons.Outlined.Subscriptions),
    TRAVEL(14, "Reisen", Color(0xFF30B0C7), Icons.Outlined.Flight),
    EDUCATION(15, "Bildung", Color(0xFF5856D6), Icons.Outlined.School),
    OTHER(255, "Andere", Color(0xFF8E8E93), Icons.Outlined.MoreHoriz);

    companion object {
        fun fromId(id: Int): WimgCategory = entries.find { it.id == id } ?: UNCATEGORIZED
    }
}
