package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.TrendingDown
import androidx.compose.material.icons.automirrored.outlined.TrendingUp
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.models.RecurringPayment
import com.wimg.app.models.RecurringPattern
import com.wimg.app.ui.components.Amount
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.amountText
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.abs

@Composable
fun RecurringDetailScreen(id: String, navController: NavController?) {
    var pattern by remember(id) {
        mutableStateOf(
            com.wimg.app.ui.components.ScreenCache.get<List<RecurringPattern>>(REC_KEY)?.firstOrNull { it.id == id }
                ?: runCatching { LibWimg.getRecurring().firstOrNull { it.id == id } }.getOrNull(),
        )
    }
    // Small query (one pattern's payments): read right away so the page is
    // complete on its first frame instead of filling in a moment later.
    var payments by remember(id) { mutableStateOf(runCatching { LibWimg.getRecurringPayments(id) }.getOrDefault(emptyList())) }

    LaunchedEffect(id, Changes.version) {
        val (p, list) = withContext(Dispatchers.IO) {
            LibWimg.getRecurring().firstOrNull { it.id == id } to LibWimg.getRecurringPayments(id)
        }
        pattern = p; payments = list
    }

    BarContribution(
        chip = null, panel = null, onPanelDismiss = {},
        detail = DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = null, actionIcon = null, onAction = {},
            backLabel = L("Wiederkehrend"),
        ),
    )

    val c = Wimg.colors
    val p = pattern
    if (p == null) {
        BandScreen(band = { Text(L("Wiederkehrend"), style = WimgType.title, color = Color.White) }) {}
        return
    }
    val income = p.amount > 0
    val amount = abs(p.amount)
    val day = p.last_seen.takeLast(2).toIntOrNull()
    // Price change from the actual payments: newest vs. the one before it.
    val newest = payments.getOrNull(0)?.let { abs(it.amount) }
    val before = payments.getOrNull(1)?.let { abs(it.amount) }
    val changed = newest != null && before != null && abs(newest - before) > 0.004

    BandScreen(
        band = {
            Text(
                listOfNotNull(L(intervalLabel(p.interval)), day?.let { L("am %d.", it) }).joinToString(" · "),
                style = WimgType.bandOver, color = c.bandSub,
            )
            Amount(amount, WimgType.amountHero, WimgType.amountHeroCents, if (income) c.bandPos else Color.White, Modifier.padding(top = 2.dp), showPlus = income)
            Text(p.merchant, style = WimgType.title.copy(fontSize = WimgType.title.fontSize * 0.92f), color = Color.White, modifier = Modifier.padding(top = 2.dp))
        },
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp, bottom = barClearance())) {
            if (changed && !income) {
                item {
                    val up = newest!! > before!!
                    val diff = newest - before // per payment
                    val perMonth = diff * monthlyFactor(p.interval)
                    Row(
                        Modifier.fillMaxWidth().clip(WimgShape.group).background(if (up) c.warnBg else c.accentSoft).padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            if (up) Icons.AutoMirrored.Outlined.TrendingUp else Icons.AutoMirrored.Outlined.TrendingDown,
                            contentDescription = null, tint = if (up) c.warn else c.accent, modifier = Modifier.size(22.dp),
                        )
                        Spacer(Modifier.width(14.dp))
                        Column {
                            Text(
                                L(if (up) "Preis gestiegen: %s → %s" else "Preis gesunken: %s → %s", amountText(before, showPlus = false), amountText(newest, showPlus = false)),
                                style = WimgType.chip.copy(fontSize = WimgType.chip.fontSize * 1.07f), color = c.text,
                            )
                            Text(
                                L("%s im Monat · %s im Jahr", amountText(perMonth), amountText(perMonth * 12)),
                                style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 2.dp),
                            )
                        }
                    }
                }
            }
            item {
                Row(Modifier.fillMaxWidth().padding(top = if (changed && !income) 18.dp else 0.dp)) {
                    val next = p.next_due
                    Stat(
                        L("Nächste"),
                        next?.let { WimgDates.short(it) } ?: "–",
                        next?.let { daysUntil(it) }?.let { d ->
                            when {
                                d > 1 -> L("in %d Tagen", d)
                                d == 1 -> L("morgen")
                                d == 0 -> L("heute")
                                else -> L("überfällig")
                            }
                        },
                        Modifier.weight(1f),
                    )
                    Stat(L("Pro Jahr"), amountText(amount * 12 * monthlyFactor(p.interval), showPlus = false), null, Modifier.weight(1f))
                    Stat(
                        L("Bisher"),
                        amountText(payments.sumOf { abs(it.amount) }, showPlus = false),
                        if (payments.size == 1) L("1 Zahlung") else L("%d Zahlungen", payments.size),
                        Modifier.weight(1f),
                    )
                }
                HorizontalDivider(Modifier.padding(top = 18.dp), thickness = 1.dp, color = c.line)
                Text(L("Verlauf"), style = WimgType.chip, color = c.text2, modifier = Modifier.padding(top = 22.dp, bottom = 6.dp))
            }
            itemsIndexed(payments, key = { _, pay -> pay.id }) { i, pay ->
                val older = payments.getOrNull(i + 1)
                val note = when {
                    older == null || abs(abs(pay.amount) - abs(older.amount)) < 0.005 -> null
                    i == 0 -> L("neuer Preis")
                    else -> L("Preis geändert")
                }
                Column {
                    Row(Modifier.fillMaxWidth().heightIn(min = 60.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(26.dp).clip(CircleShape).background(if (income) c.pos else c.ink), contentAlignment = Alignment.Center) {
                            Icon(Icons.Outlined.Check, contentDescription = L("bezahlt"), tint = c.inkText, modifier = Modifier.size(15.dp))
                        }
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(WimgDates.full(pay.date), style = WimgType.body, color = c.text)
                            if (note != null) Text(note, style = WimgType.desc, color = c.warn)
                        }
                        Text(amountText(pay.amount), style = WimgType.amountRow, color = if (income) c.pos else c.text)
                    }
                    HorizontalDivider(thickness = 1.dp, color = c.line)
                }
            }
        }
    }
}

@Composable
private fun Stat(label: String, value: String, sub: String?, modifier: Modifier) {
    val c = Wimg.colors
    Column(modifier) {
        Text(label, style = WimgType.desc, color = c.text2)
        Text(value, style = WimgType.amountStat.copy(fontSize = WimgType.amountStat.fontSize * 1.1f, fontWeight = FontWeight.ExtraBold), color = c.text, modifier = Modifier.padding(top = 2.dp))
        if (sub != null) Text(sub, style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 2.dp))
    }
}
