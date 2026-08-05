package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.ui.components.InfoTooltip
import com.wimg.app.models.CategoryBreakdown
import com.wimg.app.models.MonthlySummary
import com.wimg.app.models.WimgCategory
import com.wimg.app.services.DemoDataService
import com.wimg.app.ui.components.MonthPicker
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard
import com.wimg.app.ui.theme.wimgHero
import java.util.Calendar
import com.wimg.app.i18n.L

@Composable
fun HomeScreen(
    selectedAccount: String?,
    navController: androidx.navigation.NavController? = null,
) {
    val calendar = Calendar.getInstance()
    var year by remember { mutableIntStateOf(calendar.get(Calendar.YEAR)) }
    var month by remember { mutableIntStateOf(calendar.get(Calendar.MONTH) + 1) }
    var summary by remember { mutableStateOf<MonthlySummary?>(null) }
    val context = androidx.compose.ui.platform.LocalContext.current

    LaunchedEffect(year, month, selectedAccount) {
        summary = LibWimg.getSummaryFiltered(year, month, selectedAccount)
        com.wimg.app.services.WidgetDataWriter.writeSummary(context)
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Month picker
        item {
            MonthPicker(year = year, month = month, onChanged = { y, m -> year = y; month = m })
        }

        // Hero card — matching iOS availableCard
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .wimgHero(),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 28.dp, horizontal = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "VERFÜGBAR",
                            style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.sp),
                            fontWeight = FontWeight.Bold,
                            color = WimgColors.heroText.copy(alpha = 0.7f),
                        )
                        InfoTooltip("Einnahmen minus Ausgaben in diesem Monat. Was dir zum Sparen oder Investieren bleibt.")
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        formatAmountShort(summary?.available ?: 0.0),
                        fontSize = 40.sp,
                        fontWeight = FontWeight.Black,
                        color = WimgColors.heroText,
                        letterSpacing = (-1).sp,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "${summary?.tx_count ?: 0} Transaktionen",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.Medium,
                        color = WimgColors.heroText.copy(alpha = 0.6f),
                    )
                }
            }
        }

        // Sparquote card — matching iOS ring + label pattern
        val income = summary?.income ?: 0.0
        if (income > 0) {
            item {
                val sparquote = ((income + (summary?.expenses ?: 0.0)) / income * 100).toInt().coerceIn(-100, 100)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .wimgCard()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Ring indicator
                    Box(
                        modifier = Modifier.size(52.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(
                            progress = { (sparquote.coerceAtLeast(0) / 100f) },
                            modifier = Modifier.size(52.dp),
                            color = when {
                                sparquote >= 20 -> Color(0xFF34C759)
                                sparquote >= 0 -> Color(0xFFFF9500)
                                else -> Color(0xFFFF3B30)
                            },
                            trackColor = MaterialTheme.colorScheme.outline,
                            strokeWidth = 4.dp,
                        )
                        Text(
                            "$sparquote%",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Black,
                        )
                    }
                    Spacer(Modifier.width(16.dp))
                    Column {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(L("Sparquote"),
                                style = MaterialTheme.typography.titleSmall,
                            )
                            InfoTooltip("Prozent deines Einkommens, das du sparst: (Einnahmen − Ausgaben) ÷ Einnahmen × 100. Ab 20 % gilt als gut.")
                        }
                        Text(
                            "Du sparst ${formatAmountShort(summary?.available ?: 0.0)} von ${formatAmountShort(income)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // Income / Expenses row
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SummaryCard(
                    title = "Einnahmen",
                    amount = summary?.income ?: 0.0,
                    icon = Icons.Outlined.ArrowDownward,
                    iconColor = WimgCategory.INCOME.color,
                    modifier = Modifier.weight(1f),
                )
                SummaryCard(
                    title = "Ausgaben",
                    amount = summary?.expenses ?: 0.0,
                    icon = Icons.Outlined.ArrowUpward,
                    iconColor = MaterialTheme.colorScheme.error,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        // Category breakdown
        val categories = summary?.by_category ?: emptyList()
        if (categories.isNotEmpty()) {
            item {
                Text(L("Kategorien"),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            items(categories) { cat ->
                CategoryRow(cat)
            }
        }

        // Quick links: Rückblick + Wiederkehrend
        if (navController != null) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    QuickLinkTile(
                        label = "Rückblick",
                        icon = Icons.Outlined.CalendarMonth,
                        color = Color(0xFF5856D6),
                        onClick = { navController.navigate("review") },
                        modifier = Modifier.weight(1f),
                    )
                    QuickLinkTile(
                        label = "Wiederkehrend",
                        icon = Icons.Outlined.Refresh,
                        color = Color(0xFF30D158),
                        onClick = { navController.navigate("recurring") },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        // Empty state
        if (summary == null || (summary?.tx_count ?: 0) == 0) {
            item {
                val context = androidx.compose.ui.platform.LocalContext.current
                var loadingDemo by remember { mutableStateOf(false) }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("📋", fontSize = 48.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(L("Keine Daten"),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(L("Importiere eine CSV-Datei um loszulegen"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    Button(
                        onClick = {
                            loadingDemo = true
                            DemoDataService.loadDemoData(context)
                            summary = LibWimg.getSummaryFiltered(year, month, selectedAccount)
                            loadingDemo = false
                        },
                        enabled = !loadingDemo,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.onBackground,
                            contentColor = MaterialTheme.colorScheme.background,
                        ),
                        shape = WimgShapes.small,
                    ) {
                        Text(
                            if (loadingDemo) "Lade..." else "Beispieldaten laden",
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(vertical = 4.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun QuickLinkTile(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    color: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .wimgCard(WimgShapes.small)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(color.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(L(label), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun SummaryCard(
    title: String,
    amount: Double,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconColor: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .wimgCard(WimgShapes.small)
            .padding(16.dp),
    ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = iconColor,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    title.uppercase(),
                    style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.5.sp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                formatAmountShort(amount),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
    }
}

@Composable
private fun CategoryRow(cat: CategoryBreakdown) {
    val category = WimgCategory.fromId(cat.id)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .wimgCard(WimgShapes.small)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            category.icon,
            contentDescription = null,
            tint = category.color,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.width(12.dp))
        Text(
            category.label,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
        Text(
            formatAmountShort(cat.amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
        )
    }
}
