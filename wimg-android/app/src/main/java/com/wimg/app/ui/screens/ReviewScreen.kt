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
import androidx.compose.material.icons.automirrored.outlined.Undo
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
import kotlinx.coroutines.launch
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.ui.draw.clip
import java.text.DateFormatSymbols
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** Month the Rückblick should open on (set by the month-end message on Home). */
object ReviewTarget {
    var ym by mutableStateOf<Pair<Int, Int>?>(null)
    /** Gehaltsmonat: first day of the period to open. */
    var period by mutableStateOf<String?>(null)
}

internal class ReviewData(
    val summary: MonthlySummary?,
    val previous: MonthlySummary?,
    val biggest: Transaction?,
    val lastDate: String?,
    val fixedPaid: List<Pair<String, Double>>,
    /** Gehaltsmonat: the largest income that is not the salary. */
    val otherIncome: Transaction? = null,
    /** Days without spending in this period (up to today) and in the one before. */
    val noSpend: Int = 0,
    val prevNoSpend: Int? = null,
    /** A fixed cost that got dearer in this period (Rückblick opener "Abo erwischt"). */
    val priceRise: PriceRise? = null,
)

/** Days from [from] to [to] (ISO, inclusive, not after today) with no spending in [txs]. */
private fun noSpendCount(from: String, to: String, txs: List<Transaction>): Int {
    val today = WimgDates.todayIso()
    val end = if (to < today) to else today
    val spent = txs.asSequence().filter { it.amount < 0 && !it.isExcluded && it.date >= from && it.date <= end }.mapTo(HashSet()) { it.date }
    val c = WimgDates.parse(from) ?: return 0
    var n = 0
    while (true) {
        val iso = "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
        if (iso > end) break
        if (iso !in spent) n++
        c.add(Calendar.DAY_OF_YEAR, 1)
    }
    return n
}

private fun monthEnd(y: Int, m: Int) = "%04d-%02d-%02d".format(y, m, Calendar.getInstance().apply { set(y, m - 1, 1) }.getActualMaximum(Calendar.DAY_OF_MONTH))

/** The newest price rise of a fixed cost booked between [from] and [to]. */
private fun priceRiseIn(from: String, to: String): PriceRise? = runCatching {
    LibWimg.getRecurring()
        .filter { it.active == 1 && !it.isHidden && it.amount < 0 && it.price_change != null && it.prev_amount != null && abs(it.amount) - abs(it.prev_amount) > 0.5 && it.last_seen >= from && it.last_seen <= to }
        .maxByOrNull { it.last_seen }
        ?.let { PriceRise(it.id, it.displayName, abs(it.prev_amount!!), abs(it.amount), it.last_seen) }
}.getOrNull()

private fun prevMonth(y: Int, m: Int) = if (m == 1) y - 1 to 12 else y to m - 1

internal fun reviewKey(year: Int, month: Int, account: String?) = "review:$year-$month:$account"
internal fun reviewPeriodKey(from: String, account: String?) = "review:$from:$account"

internal fun loadReview(year: Int, month: Int, account: String?): ReviewData {
    val summary = LibWimg.getSummaryFiltered(year, month, account)
    val (py, pm) = prevMonth(year, month)
    val previous = LibWimg.getSummaryFiltered(py, pm, account)?.takeIf { it.tx_count > 0 }
    val prefix = "%04d-%02d".format(year, month)
    // Up to today only: scheduled (and demo) bookings dated later don't count yet.
    val today = Calendar.getInstance().let { "%04d-%02d-%02d".format(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1, it.get(Calendar.DAY_OF_MONTH)) }
    val all = LibWimg.getTransactionsFiltered(account)
    val inMonth = all.filter { it.date.startsWith(prefix) && !it.isExcluded && it.date <= today }
    // Fixed costs paid this month: active expense patterns seen in it.
    val fixed = runCatching {
        LibWimg.getRecurring().filter { it.active == 1 && !it.isHidden && it.amount < 0 && it.last_seen.startsWith(prefix) }.map { it.displayName to it.amount }
    }.getOrDefault(emptyList())
    val prevPrefix = "%04d-%02d".format(py, pm)
    return ReviewData(
        summary, previous, inMonth.filter { it.amount < 0 }.minByOrNull { it.amount }, inMonth.maxOfOrNull { it.date }, fixed,
        noSpend = noSpendCount("$prefix-01", monthEnd(year, month), all),
        prevNoSpend = previous?.let { noSpendCount("$prevPrefix-01", monthEnd(py, pm), all) },
        priceRise = priceRiseIn("$prefix-01", monthEnd(year, month)),
    )
}

internal fun loadReviewRange(p: com.wimg.app.models.PeriodInfo, prev: com.wimg.app.models.PeriodInfo?, account: String?, salaryMode: Boolean): ReviewData {
    val summary = LibWimg.getSummaryRange(p.from, p.to, account)
    val previous = prev?.let { LibWimg.getSummaryRange(it.from, it.to, account) }?.takeIf { it.tx_count > 0 }
    val today = com.wimg.app.ui.components.WimgDates.todayIso()
    val all = LibWimg.getTransactionsFiltered(account)
    val inRange = all.filter { it.date >= p.from && it.date <= p.to && !it.isExcluded && it.date <= today }
    val fixed = runCatching {
        LibWimg.getRecurring().filter { it.active == 1 && !it.isHidden && it.amount < 0 && it.last_seen >= p.from && it.last_seen <= p.to }.map { it.displayName to it.amount }
    }.getOrDefault(emptyList())
    // The salary is booked on the period's first day; any other income is "weitere".
    val other = if (salaryMode) inRange.filter { it.amount > 0 && it.date != p.from }.maxByOrNull { it.amount } else null
    return ReviewData(
        summary, previous, inRange.filter { it.amount < 0 }.minByOrNull { it.amount }, inRange.maxOfOrNull { it.date }, fixed, other,
        noSpend = noSpendCount(p.from, p.to, all),
        prevNoSpend = if (previous != null && prev != null) noSpendCount(prev.from, prev.to, all) else null,
        priceRise = priceRiseIn(p.from, p.to),
    )
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
    // Gehaltsmonat: periods from salary to salary (or from a fixed day) instead of months.
    val periods = com.wimg.app.ui.components.rememberPeriods()
    var periodFrom by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(ReviewTarget.period) }
    val period = periods?.takeIf { !it.isCalendar }?.let { ps -> ps.periods.firstOrNull { it.from == periodFrom } ?: ps.periods.firstOrNull() }
    val prevPeriod = period?.let { p -> periods.periods.getOrNull(periods.periods.indexOf(p) + 1) }
    val cacheKey = if (period != null) reviewPeriodKey(period.from, selectedAccount) else reviewKey(year, month, selectedAccount)
    // Last result first (loaded ahead in the background), fresh data replaces it.
    var data by remember { mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<ReviewData>(cacheKey)) }
    // Opened from the month-end notice (read before it is cleared below).
    val fromNotice = remember { ReviewTarget.ym != null || ReviewTarget.period != null }
    var loadedKey by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { ReviewTarget.ym = null; ReviewTarget.period = null }
    LaunchedEffect(year, month, selectedAccount, period, Changes.version) {
        com.wimg.app.ui.components.ScreenCache.get<ReviewData>(cacheKey)?.let { data = it }
        data = withContext(Dispatchers.IO) {
            if (period != null) loadReviewRange(period, prevPeriod, selectedAccount, periods.isSalary) else loadReview(year, month, selectedAccount)
        }.also { com.wimg.app.ui.components.ScreenCache.put(cacheKey, it) }
        loadedKey = cacheKey
    }

    val locale = if (LocaleState.locale == "en") Locale.ENGLISH else Locale.GERMAN
    val months = remember(locale) { DateFormatSymbols(locale).months }
    val shortMonths = remember(locale) { DateFormatSymbols(locale).shortMonths.map { it.trimEnd('.') } }
    val isCurrent = year == now.get(Calendar.YEAR) && month == now.get(Calendar.MONTH) + 1
    val (_, pm) = prevMonth(year, month)

    BarContribution(
        chip = if (period != null) BarChipSpec(com.wimg.app.ui.components.PeriodLabels.short(period), pickerOpen, { pickerOpen = !pickerOpen })
        else BarChipSpec(shortMonths[month - 1] + if (year != now.get(Calendar.YEAR)) " ${year % 100}" else "", pickerOpen, { pickerOpen = !pickerOpen }),
        panel = if (!pickerOpen) null else if (period != null) { { ReviewPeriodPanel(periods, period, selectedAccount) { periodFrom = it.from; pickerOpen = false } } }
        else { { MonthPickerPanel(year, month, shortMonths, now, onPick = { y, m -> year = y; month = m; pickerOpen = false }) } },
        onPanelDismiss = { pickerOpen = false },
    )

    // Rückblick opener: once per closed period, from the month-end notice or when
    // the Sparquote is at least the one before; never without something true to say.
    val context = androidx.compose.ui.platform.LocalContext.current
    val openerLabel = if (period != null) com.wimg.app.ui.components.PeriodLabels.short(period) else months[month - 1]
    val cards = data?.takeIf { loadedKey == cacheKey }?.let { openerCards(it, openerLabel, if (period != null) null else months[pm - 1], periods?.isSalary == true) }.orEmpty()
    var openerFor by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(loadedKey) {
        if (loadedKey != cacheKey || cards.isEmpty()) return@LaunchedEffect
        val prefs = context.getSharedPreferences("wimg_moments", 0)
        val forced = context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
            java.io.File(context.filesDir, "opener").let { f -> f.exists().also { f.delete() } }
        val closed = if (period != null) !period.current else !isCurrent
        val sd = data?.summary; val pv = data?.previous
        val rate = sd?.let { if (it.income > 0) (it.income - abs(it.expenses)) / it.income else null }
        val prevRate = pv?.let { if (it.income > 0) (it.income - abs(it.expenses)) / it.income else null }
        val good = rate != null && (prevRate == null || rate >= prevRate)
        val key = "opener:$cacheKey"
        if (forced || (closed && (fromNotice || good) && !prefs.getBoolean(key, false))) {
            prefs.edit().putBoolean(key, true).apply()
            openerFor = cacheKey
        }
    }
    if (openerFor == cacheKey && cards.isNotEmpty()) ReviewOpener(L("Rückblick %s", openerLabel), cards) { openerFor = null }

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
            if (period != null) {
                ReviewPeriodBand(periods, period, prevPeriod, s, change)
                return@BandScreen
            }
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
                if (period != null) Stat(L("Tage"), "${period.days}", c.text, Modifier.weight(0.8f))
                else Stat(L("Umsätze"), "${s.tx_count}", c.text, Modifier.weight(0.8f))
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
                val prevShort = if (period != null) null else shortMonths[pm - 1]
                changes.filter { it.second > 0 }.maxByOrNull { it.second }?.let { (cat, pct) ->
                    if (!first) RowDivider(); first = false
                    Item(Icons.AutoMirrored.Outlined.TrendingUp, c.danger, if (prevShort == null) L("Stärkster Anstieg") else L("Stärkster Anstieg vs. %s", prevShort),
                        "${L(WimgCategory.fromId(cat.id).label)} ▲ $pct %", amountText(abs(cat.amount), showPlus = false))
                }
                changes.filter { it.second < 0 }.minByOrNull { it.second }?.let { (cat, pct) ->
                    if (!first) RowDivider(); first = false
                    Item(Icons.AutoMirrored.Outlined.TrendingDown, c.pos, if (prevShort == null) L("Stärkster Rückgang") else L("Stärkster Rückgang vs. %s", prevShort),
                        "${L(WimgCategory.fromId(cat.id).label)} ▼ ${-pct} %", amountText(abs(cat.amount), showPlus = false))
                }
                s.by_category.firstOrNull { it.id == 0 && it.amount != 0.0 }?.let { cat ->
                    val share = if (expenses != 0.0) (abs(cat.amount) / abs(expenses) * 100).roundToInt() else 0
                    if (!first) RowDivider(); first = false
                    Item(Icons.Outlined.LocalOffer, c.text2, L("Noch nicht zugeordnet"),
                        "${L(WimgCategory.UNCATEGORIZED.label)} · $share %", amountText(abs(cat.amount), showPlus = false)) {
                        TxTarget.category = 0
                        TxTarget.period = period?.let { txPeriodOf(it, periods.isSalary) } ?: monthPeriod(year, month)
                        // On top, so back returns here (not to Übersicht).
                        navController?.navigate("transactions")
                    }
                }
                d.otherIncome?.let { t ->
                    if (!first) RowDivider(); first = false
                    Item(Icons.AutoMirrored.Outlined.Undo, c.text2, L("Weitere Einnahme"), t.displayTitle, amountText(t.amount)) { navController?.navigate("tx/${t.id}") }
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

// ---------------------------------------------------------------------------
// Gehaltsmonat (board 26A)
// ---------------------------------------------------------------------------

@Composable
private fun ReviewPeriodBand(
    periods: com.wimg.app.models.Periods,
    p: com.wimg.app.models.PeriodInfo,
    prev: com.wimg.app.models.PeriodInfo?,
    s: MonthlySummary?,
    change: Int?,
) {
    val c = Wimg.colors
    val lbl = com.wimg.app.ui.components.PeriodLabels
    val salary = periods.isSalary
    val over = when {
        salary && p.current -> L("Gehaltsmonat %s · läuft noch", lbl.long(p))
        salary -> L("Gehaltsmonat %s", lbl.long(p))
        p.current -> L("%s · läuft noch", lbl.long(p))
        else -> lbl.long(p)
    }
    Text(over, style = WimgType.bandOver, color = c.bandSub)
    val net = (s?.income ?: 0.0) - abs(s?.expenses ?: 0.0)
    val head = when {
        s == null || s.tx_count == 0 -> null
        salary && net >= 0 && p.current -> L("Vom Gehalt sind noch %s übrig.", "\u0000")
        salary && net >= 0 -> L("Vom Gehalt sind %s übrig geblieben.", "\u0000")
        net < 0 -> L("Du hast %s mehr ausgegeben als eingenommen.", "\u0000")
        else -> L("Du hast %s mehr eingenommen als ausgegeben.", "\u0000")
    }
    Text(
        if (head == null) buildAnnotatedString { append(L("In diesem Zeitraum gibt es noch keine Umsätze.")) }
        else buildAnnotatedString {
            val (a, b) = head.split("\u0000", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            append(a)
            withStyle(SpanStyle(color = if (net < 0) c.bandNeg else c.bandPos)) { append(amountText(abs(net), showPlus = false)) }
            append(b)
        },
        style = WimgType.title.copy(fontSize = WimgType.title.fontSize * 1.05f), color = Color.White, modifier = Modifier.padding(top = 6.dp),
    )
    if (change != null && change != 0 && prev != null) {
        val range = lbl.long(prev)
        Text(
            when {
                salary && change < 0 -> L("%d %% weniger ausgegeben als im Gehaltsmonat davor (%s).", -change, range)
                salary -> L("%d %% mehr ausgegeben als im Gehaltsmonat davor (%s).", change, range)
                change < 0 -> L("%d %% weniger ausgegeben als im Monat davor (%s).", -change, range)
                else -> L("%d %% mehr ausgegeben als im Monat davor (%s).", change, range)
            },
            style = WimgType.body, color = c.bandSub, modifier = Modifier.padding(top = 8.dp),
        )
    }
}

/** "Gehaltsmonat wählen" (board 26/03): periods with their length and what was left. */
@Composable
private fun ReviewPeriodPanel(periods: com.wimg.app.models.Periods, selected: com.wimg.app.models.PeriodInfo, account: String?, onPick: (com.wimg.app.models.PeriodInfo) -> Unit) {
    val c = Wimg.colors
    val lbl = com.wimg.app.ui.components.PeriodLabels
    val shown = periods.periods.take(6)
    var nets by remember { mutableStateOf<Map<String, Double>>(emptyMap()) }
    LaunchedEffect(shown) {
        nets = withContext(Dispatchers.IO) { shown.associate { p -> p.from to (LibWimg.getSummaryRange(p.from, p.to, account)?.let { it.income - abs(it.expenses) } ?: 0.0) } }
    }
    com.wimg.app.ui.components.BarPanel {
        Text(if (periods.isSalary) L("Gehaltsmonat wählen") else L("Zeitraum wählen"), style = WimgType.sheetTitle, color = c.text, modifier = Modifier.padding(start = 4.dp, bottom = 12.dp))
        shown.forEachIndexed { i, p ->
            val on = p == selected
            Row(
                Modifier.fillMaxWidth().clip(WimgShape.segmentOuter).background(if (on) c.neutralTint else Color.Transparent)
                    .clickable { onPick(p) }.padding(horizontal = 14.dp, vertical = 11.dp),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(lbl.long(p), style = WimgType.rowTitle, color = c.text)
                    val net = nets[p.from]
                    val sub = when {
                        p.early_days > 0 -> if (p.early_days == 1) L("%d Tage · Gehalt 1 Tag früher", p.days) else L("%d Tage · Gehalt %d Tage früher", p.days, p.early_days)
                        net == null -> L("%d Tage", p.days)
                        net >= 0 -> L("%d Tage · %s übrig", p.days, amountText(net, showPlus = false))
                        else -> L("%d Tage · %s", p.days, amountText(net))
                    }
                    Text(sub, style = WimgType.desc, color = c.text2)
                }
                val badge = when {
                    p.current -> L("läuft")
                    i == 1 && shown.first().current && com.wimg.app.ui.components.PeriodLabels.daysIn(shown.first()) <= 10 -> L("gerade fertig")
                    else -> null
                }
                if (badge != null) {
                    Text(badge, style = WimgType.caption.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = c.pos,
                        modifier = Modifier.clip(androidx.compose.foundation.shape.CircleShape).background(c.pos.copy(alpha = 0.12f)).padding(horizontal = 10.dp, vertical = 4.dp))
                }
            }
        }
        if (periods.isSalary) com.wimg.app.ui.components.QuietLine(L("Ein Gehaltsmonat läuft von Gehalt zu Gehalt, deshalb sind die Längen verschieden."))
    }
}

private val askedThisSession = mutableSetOf<String>()
private const val PERIOD_SEEN_KEY = "wimg_period_seen"
private const val INCOME_SEEN_KEY = "wimg_income_seen"

/**
 * Gehaltsmonat prompts on Übersicht, docked on the bar, at most one:
 * "Ist das dein Gehalt?" for a salary wimg found (board 3/01), the end of a
 * period when the new salary is there (26/04, 26/11), and an extra income that
 * doesn't start a period (26/12). True when one was shown.
 */
suspend fun offerSalaryPrompts(context: Context, p: com.wimg.app.models.Periods, account: String?, onOpen: (String) -> Unit): Boolean {
    if (Dock.row != null) return true
    val prefs = context.getSharedPreferences("wimg", 0)
    val io = kotlinx.coroutines.CoroutineScope(Dispatchers.IO)
    val wallet = androidx.compose.material.icons.Icons.Outlined.AccountBalanceWallet
    val sal = p.salary
    if (sal != null && !sal.confirmed && askedThisSession.add(sal.key)) {
        Dock.show(DockRow(
            DockKind.Prompt, __t("Ist das dein Gehalt?"), __t("%s · %d× um den %d.").format(sal.name, sal.count, sal.day),
            action = "Ja", onAction = {
                io.launch {
                    LibWimg.answerSalary(sal.key, 1)
                    if (p.chosen == "calendar") LibWimg.setPeriodMode("salary")
                    Changes.bump()
                }
            },
            action2 = "Nein", onAction2 = { io.launch { LibWimg.answerSalary(sal.key, 0); Changes.bump() } },
            icon = wallet,
        ))
        return true
    }
    if (p.isCalendar) return false
    val cur = p.current ?: return false
    val prev = p.periods.getOrNull(1)
    val daysIn = com.wimg.app.ui.components.PeriodLabels.daysIn(cur)
    if (prev != null && daysIn <= 10 && prefs.getString(PERIOD_SEEN_KEY, null) != prev.from) {
        prefs.edit().putString(PERIOD_SEEN_KEY, prev.from).apply()
        val s = withContext(Dispatchers.IO) { LibWimg.getSummaryRange(prev.from, prev.to, account) }
        val net = (s?.income ?: 0.0) - abs(s?.expenses ?: 0.0)
        val range = com.wimg.app.ui.components.PeriodLabels.long(prev)
        val netText = if (net >= 0) __t("%s übrig").format(amountText(net, showPlus = false)) else __t("%s zu viel").format(amountText(-net, showPlus = false))
        val (title, sub) = when {
            p.isSalary && daysIn <= 1 && cur.early_days > 0 -> __t("Gehalt schon heute da") to __t("Zeitraum davor: %d Tage").format(prev.days)
            p.isSalary -> __t("Gehalt ist da: Rückblick fertig") to "$range · $netText"
            else -> __t("Dein Monat bis zum %d. ist fertig").format(prev.to.takeLast(2).toInt()) to "$range · $netText"
        }
        Dock.show(DockRow(DockKind.Prompt, title, sub, action = "Ansehen", onAction = { onOpen(prev.from) }, icon = if (p.isSalary) wallet else null))
        return true
    }
    if (p.isSalary) {
        val seen = prefs.getStringSet(INCOME_SEEN_KEY, emptySet()) ?: emptySet()
        val weekAgo = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -7) }.let { "%04d-%02d-%02d".format(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1, it.get(Calendar.DAY_OF_MONTH)) }
        val inc = p.other_income.firstOrNull { it.id !in seen && it.date >= weekAgo } ?: return false
        prefs.edit().putStringSet(INCOME_SEEN_KEY, (seen.toList().takeLast(40) + inc.id).toSet()).apply()
        Dock.show(DockRow(
            DockKind.Prompt, __t("%s von %s").format(amountText(inc.amount), inc.title), __t("Einnahme, kein neuer Zeitraum"),
            action = "Ist Gehalt", onAction = { io.launch { LibWimg.answerSalary(inc.key, 1); Changes.bump() } },
            icon = androidx.compose.material.icons.Icons.AutoMirrored.Outlined.Undo, timeoutMs = 10_000,
        ))
        return true
    }
    return false
}
