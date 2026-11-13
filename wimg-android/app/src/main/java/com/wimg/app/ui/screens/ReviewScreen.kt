package com.wimg.app.ui.screens

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.TrendingDown
import androidx.compose.material.icons.automirrored.outlined.TrendingUp
import androidx.compose.material.icons.outlined.AttachMoney
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.models.MonthlySummary
import com.wimg.app.models.Transaction
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarChipSpec
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.DockKind
import com.wimg.app.ui.components.DockRow
import com.wimg.app.ui.components.GroupLabel
import com.wimg.app.ui.components.IconTile
import com.wimg.app.ui.components.RowDivider
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.WimgGroup
import com.wimg.app.ui.components.WimgRow
import com.wimg.app.ui.components.amountText
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.theme.LocaleState
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.DateFormatSymbols
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** Month the Rückblick should open on (set by the month-end message on Home). */
object ReviewTarget {
    var ym by mutableStateOf<Pair<Int, Int>?>(null)
}

internal class ReviewData(
    val summary: MonthlySummary?,
    val previous: MonthlySummary?,
    val biggest: Transaction?,
    val lastDate: String?,
    val fixedPaid: List<Pair<String, Double>>,
)

private fun prevMonth(y: Int, m: Int) = if (m == 1) y - 1 to 12 else y to m - 1

internal fun reviewKey(year: Int, month: Int, account: String?) = "review:$year-$month:$account"

internal fun loadReview(year: Int, month: Int, account: String?): ReviewData {
    val summary = LibWimg.getSummaryFiltered(year, month, account)
    val (py, pm) = prevMonth(year, month)
    val previous = LibWimg.getSummaryFiltered(py, pm, account)?.takeIf { it.tx_count > 0 }
    val prefix = "%04d-%02d".format(year, month)
    // Up to today only: scheduled (and demo) bookings dated later don't count yet.
    val today = Calendar.getInstance().let { "%04d-%02d-%02d".format(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1, it.get(Calendar.DAY_OF_MONTH)) }
    val inMonth = LibWimg.getTransactionsFiltered(account).filter { it.date.startsWith(prefix) && !it.isExcluded && it.date <= today }
    // Fixed costs paid this month: active expense patterns seen in it.
    val fixed = runCatching {
        LibWimg.getRecurring().filter { it.active == 1 && it.amount < 0 && it.last_seen.startsWith(prefix) }.map { it.merchant to it.amount }
    }.getOrDefault(emptyList())
    return ReviewData(summary, previous, inMonth.filter { it.amount < 0 }.minByOrNull { it.amount }, inMonth.maxOfOrNull { it.date }, fixed)
}

/** Share of spending change vs. the previous month, in % (negative = less). */
private fun changePct(now: Double, before: Double): Int? =
    if (abs(before) < 0.01) null else ((abs(now) - abs(before)) / abs(before) * 100).roundToInt()

@Composable
fun ReviewScreen(selectedAccount: String?, navController: NavController? = null) {
    val now = remember { Calendar.getInstance() }
    val start = ReviewTarget.ym ?: (now.get(Calendar.YEAR) to now.get(Calendar.MONTH) + 1)
    var year by remember { mutableIntStateOf(start.first) }
    var month by remember { mutableIntStateOf(start.second) }
    var pickerOpen by remember { mutableStateOf(false) }
    // Last result first (loaded ahead in the background), fresh data replaces it.
    var data by remember { mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<ReviewData>(reviewKey(year, month, selectedAccount))) }
    LaunchedEffect(Unit) { ReviewTarget.ym = null }
    LaunchedEffect(year, month, selectedAccount, Changes.version) {
        com.wimg.app.ui.components.ScreenCache.get<ReviewData>(reviewKey(year, month, selectedAccount))?.let { data = it }
        data = withContext(Dispatchers.IO) { loadReview(year, month, selectedAccount) }
            .also { com.wimg.app.ui.components.ScreenCache.put(reviewKey(year, month, selectedAccount), it) }
    }

    val locale = if (LocaleState.locale == "en") Locale.ENGLISH else Locale.GERMAN
    val months = remember(locale) { DateFormatSymbols(locale).months }
    val shortMonths = remember(locale) { DateFormatSymbols(locale).shortMonths.map { it.trimEnd('.') } }
    val isCurrent = year == now.get(Calendar.YEAR) && month == now.get(Calendar.MONTH) + 1
    val (_, pm) = prevMonth(year, month)

    BarContribution(
        chip = BarChipSpec(shortMonths[month - 1] + if (year != now.get(Calendar.YEAR)) " ${year % 100}" else "", pickerOpen, { pickerOpen = !pickerOpen }),
        panel = if (pickerOpen) { { MonthPickerPanel(year, month, shortMonths, now, onPick = { y, m -> year = y; month = m; pickerOpen = false }) } } else null,
        onPanelDismiss = { pickerOpen = false },
    )

    val c = Wimg.colors
    val d = data
    val s = d?.summary
    val income = s?.income ?: 0.0
    // The summary reports spending as a positive amount.
    val expenses = abs(s?.expenses ?: 0.0)
    val net = income - expenses
    val change = d?.previous?.let { changePct(expenses, it.expenses) }

    BandScreen(
        band = {
            val over = if (isCurrent && d?.lastDate != null) L("Monatsabschluss · Vorschau mit Daten bis %s", WimgDates.short(d.lastDate)) else L("Monatsabschluss")
            Text(over, style = WimgType.bandOver, color = c.bandSub)
            val head = when {
                s == null || s.tx_count == 0 -> null
                net < 0 -> L("Dein %s: Du hast %s mehr ausgegeben als eingenommen.", months[month - 1], "\u0000")
                else -> L("Dein %s: Du hast %s mehr eingenommen als ausgegeben.", months[month - 1], "\u0000")
            }
            Text(
                if (head == null) buildAnnotatedString { append(L("Für %s gibt es noch keine Umsätze.", months[month - 1])) }
                else buildAnnotatedString {
                    val (a, b) = head.split("\u0000", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
                    append(a)
                    withStyle(SpanStyle(color = if (net < 0) c.bandNeg else c.bandPos)) { append(amountText(abs(net), showPlus = false)) }
                    append(b)
                },
                style = WimgType.title.copy(fontSize = WimgType.title.fontSize * 1.05f), color = Color.White, modifier = Modifier.padding(top = 6.dp),
            )
            if (change != null && change != 0) {
                Text(
                    if (change < 0) L("%d %% weniger Ausgaben als im %s.", -change, months[pm - 1]) else L("%d %% mehr Ausgaben als im %s.", change, months[pm - 1]),
                    style = WimgType.body, color = c.bandSub, modifier = Modifier.padding(top = 8.dp),
                )
            }
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = barClearance())) {
            if (s == null || s.tx_count == 0) return@Column
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Stat(L("Einnahmen"), amountText(income), c.pos, Modifier.weight(1f))
                Stat(L("Ausgaben"), amountText(-expenses), c.text, Modifier.weight(1.15f))
                Stat(L("Umsätze"), "${s.tx_count}", c.text, Modifier.weight(0.8f))
            }

            GroupLabel(L("Aufgefallen"))
            WimgGroup {
                var first = true
                d.biggest?.let { t ->
                    Item(Icons.Outlined.AttachMoney, Color(0xFF8B5CF6), L("Größte Einzelausgabe"),
                        "${t.title?.takeIf { it.isNotBlank() } ?: t.description} · ${WimgDates.short(t.date)}", amountText(t.amount)) { navController?.navigate("tx/${t.id}") }
                    first = false
                }
                // Category changes vs. the previous month, over categories that exist in both.
                val prevById = d.previous?.by_category?.associateBy { it.id } ?: emptyMap()
                val changes = s.by_category.filter { it.amount != 0.0 && it.id != 0 && it.id != WimgCategory.INCOME.id }.mapNotNull { cat ->
                    prevById[cat.id]?.let { p -> changePct(cat.amount, p.amount)?.let { cat to it } }
                }
                val prevShort = shortMonths[pm - 1]
                changes.filter { it.second > 0 }.maxByOrNull { it.second }?.let { (cat, pct) ->
                    if (!first) RowDivider(); first = false
                    Item(Icons.AutoMirrored.Outlined.TrendingUp, c.danger, L("Stärkster Anstieg vs. %s", prevShort),
                        "${L(WimgCategory.fromId(cat.id).label)} ▲ $pct %", amountText(abs(cat.amount), showPlus = false))
                }
                changes.filter { it.second < 0 }.minByOrNull { it.second }?.let { (cat, pct) ->
                    if (!first) RowDivider(); first = false
                    Item(Icons.AutoMirrored.Outlined.TrendingDown, c.pos, L("Stärkster Rückgang vs. %s", prevShort),
                        "${L(WimgCategory.fromId(cat.id).label)} ▼ ${-pct} %", amountText(abs(cat.amount), showPlus = false))
                }
                s.by_category.firstOrNull { it.id == 0 && it.amount != 0.0 }?.let { cat ->
                    val share = if (expenses != 0.0) (abs(cat.amount) / abs(expenses) * 100).roundToInt() else 0
                    if (!first) RowDivider(); first = false
                    Item(Icons.Outlined.LocalOffer, c.text2, L("Noch nicht zugeordnet"),
                        "${L(WimgCategory.UNCATEGORIZED.label)} · $share %", amountText(abs(cat.amount), showPlus = false)) {
                        TxTarget.category = 0
                        TxTarget.period = monthPeriod(year, month)
                        navController?.navigate("transactions") { popUpTo("dashboard") }
                    }
                }
                if (d.fixedPaid.isNotEmpty()) {
                    if (!first) RowDivider(); first = false
                    val names = d.fixedPaid.map { it.first }
                    Item(Icons.Outlined.Refresh, c.accent, L("Fixkosten bezahlt"),
                        if (names.size == 1) names[0] else L("%d Zahlungen · %s", names.size, names.take(2).joinToString(", ") + if (names.size > 2) " …" else ""),
                        amountText(d.fixedPaid.sumOf { it.second })) { navController?.navigate("recurring") }
                }
            }
        }
    }
}

@Composable
private fun Stat(label: String, value: String, color: Color, modifier: Modifier) {
    val c = Wimg.colors
    Column(modifier.background(c.card, WimgShape.group).border(1.dp, c.line, WimgShape.group).padding(14.dp)) {
        Text(label, style = WimgType.desc, color = c.text2, maxLines = 1)
        Text(value, style = WimgType.amountStat, color = color, maxLines = 1, modifier = Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun Item(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color, over: String, title: String, amount: String, onClick: (() -> Unit)? = null) {
    val c = Wimg.colors
    Row(
        Modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
    ) {
        IconTile(icon, tint)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(over, style = WimgType.desc, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(title, style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.width(10.dp))
        Text(amount, style = WimgType.amountRow, color = c.text, maxLines = 1)
    }
}

// ---------------------------------------------------------------------------
// Month-end message on Home
// ---------------------------------------------------------------------------

private const val SEEN_KEY = "wimg_review_seen"

/**
 * In the first 10 days of a month, Home offers last month's Rückblick once,
 * docked on the bar. Dismissed or opened, it doesn't come back for that month.
 */
suspend fun offerMonthEnd(context: Context, account: String?, onOpen: (Int, Int) -> Unit) {
    val now = Calendar.getInstance()
    if (now.get(Calendar.DAY_OF_MONTH) > 10) return
    val (y, m) = prevMonth(now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1)
    val key = "%04d-%02d".format(y, m)
    val prefs = context.getSharedPreferences("wimg", 0)
    if (prefs.getString(SEEN_KEY, null) == key || Dock.row != null) return
    val d = withContext(Dispatchers.IO) { runCatching { loadReview(y, m, account) }.getOrNull() } ?: return
    val s = d.summary ?: return
    if (s.tx_count == 0) return
    prefs.edit().putString(SEEN_KEY, key).apply()
    val locale = if (LocaleState.locale == "en") Locale.ENGLISH else Locale.GERMAN
    val names = DateFormatSymbols(locale).months
    val net = s.income - abs(s.expenses)
    val change = d.previous?.let { changePct(s.expenses, it.expenses) }
    val sub = listOfNotNull(
        amountText(net),
        change?.takeIf { it != 0 }?.let { (if (it < 0) __t("Ausgaben ▼ %d %%") else __t("Ausgaben ▲ %d %%")).format(abs(it)) },
    ).joinToString(" · ")
    Dock.show(DockRow(DockKind.Prompt, __t("Dein %s ist abgeschlossen").format(names[m - 1]), sub, __t("Ansehen"), { onOpen(y, m) }))
}
