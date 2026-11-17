package com.wimg.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.ArrowDropDown
import androidx.compose.material.icons.outlined.ArrowDropUp
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.models.CategoryBreakdown
import com.wimg.app.models.MonthlySummary
import com.wimg.app.models.Transaction
import com.wimg.app.models.WimgCategory
import com.wimg.app.services.DemoDataService
import com.wimg.app.ui.components.Amount
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarChipSpec
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.IconTile
import com.wimg.app.ui.components.amountText
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.components.SquirrelPose
import com.wimg.app.ui.components.endFrame
import com.wimg.app.ui.theme.WimgMotion
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.layout.layout
import com.wimg.app.ui.components.SquirrelMoment
import com.wimg.app.i18n.__t
import com.wimg.app.ui.theme.LocaleState
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import com.wimg.app.ui.theme.category
import com.wimg.app.ui.theme.categoryBar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormatSymbols
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** What Home compares this month's categories with (Zeitraum panel). */
enum class HomeCompare(val label: String) { PREV("Vormonat"), AVG3("Ø 3 Monate"), LAST_YEAR("Vorjahr") }

internal data class HomeData(
    val summary: MonthlySummary?,
    val previous: MonthlySummary?,
    /** Latest booking day in the selected month, newest first. */
    val day: List<Transaction>,
    val hasAnyData: Boolean,
    /** Not yet booked, from the last bank fetch (current month view only). */
    val pending: List<Transaction> = emptyList(),
    /** Days (ISO) with spending, for the stitches of days without (squirrel ring). */
    val spendDates: Set<String> = emptySet(),
    /** Newest unconfirmed price rise of a fixed cost in this period (the squirrel's ghost moment). */
    val priceRise: PriceRise? = null,
)

internal class PriceRise(val id: String, val name: String, val old: Double, val new: Double, val seen: String)

/** A fixed cost booked at a higher price since [fromIso] and not yet confirmed ("Stimmt, neuer Preis"). */
internal fun latestPriceRise(fromIso: String): PriceRise? =
    LibWimg.getRecurring()
        .filter { it.active == 1 && !it.isHidden && it.amount < 0 && it.price_change != null && it.prev_amount != null && abs(it.amount) - abs(it.prev_amount) > 0.5 && it.last_seen >= fromIso }
        .maxByOrNull { it.last_seen }
        ?.let { PriceRise(it.id, it.displayName, abs(it.prev_amount!!), abs(it.amount), it.last_seen) }

@Composable
fun HomeScreen(selectedAccount: String?, navController: NavController? = null, onSelectAccount: (String?) -> Unit = {}) {
    val now = remember { Calendar.getInstance() }
    var year by remember { mutableIntStateOf(now.get(Calendar.YEAR)) }
    var month by remember { mutableIntStateOf(now.get(Calendar.MONTH) + 1) }
    var compare by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(HomeCompare.PREV) }
    var accounts by remember { mutableStateOf(LibWimg.ifFree { LibWimg.getAccounts() }.orEmpty()) }
    LaunchedEffect(com.wimg.app.ui.components.Changes.version) { accounts = withContext(Dispatchers.IO) { LibWimg.getAccounts() } }
    // Gehaltsmonat: salary or "Fester Tag" periods replace calendar months.
    val periods = com.wimg.app.ui.components.rememberPeriods()
    var periodIdx by androidx.compose.runtime.saveable.rememberSaveable { mutableIntStateOf(0) }
    // Another mode (or start day) makes other periods: back to the current one.
    val periodShape = periods?.let { it.mode + it.day }
    var lastShape by remember { mutableStateOf(periodShape) }
    if (periodShape != lastShape) { if (lastShape != null) periodIdx = 0; lastShape = periodShape }
    val period =periods?.takeIf { !it.isCalendar }?.let { it.periods.getOrNull(periodIdx) ?: it.periods.firstOrNull() }
    val prevPeriod = period?.let { p -> periods.periods.getOrNull(periods.periods.indexOf(p) + 1) }
    // The key the data is cached under, also on the first frame: with the
    // calendar key in Gehaltsmonat mode the page started empty (white) and
    // filled a frame later.
    // With nothing cached (first start, cold start) load once right away, like
    // Rückblick: the first frame drew the full layout with 0,00 € and the period
    // ring, then switched to "Noch keine Umsätze" and the bar jumped narrower.
    var data by remember {
        val key = if (period != null) homePeriodKey(period.from, selectedAccount) else homeKey(year, month, selectedAccount, compare)
        mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<HomeData>(key) ?: runCatching {
            (if (period != null) loadHomeRange(period, prevPeriod, selectedAccount) else loadHome(year, month, selectedAccount, compare))
                .also { com.wimg.app.ui.components.ScreenCache.put(key, it) }
        }.getOrNull())
    }
    var pickerOpen by remember { mutableStateOf(false) }
    var pickingAccount by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    LaunchedEffect(year, month, selectedAccount, compare, reload, period, com.wimg.app.ui.components.Changes.version) {
        val key = if (period != null) homePeriodKey(period.from, selectedAccount) else homeKey(year, month, selectedAccount, compare)
        com.wimg.app.ui.components.ScreenCache.get<HomeData>(key)?.let { data = it }
        data = withContext(Dispatchers.IO) {
            if (period != null) loadHomeRange(period, prevPeriod, selectedAccount) else loadHome(year, month, selectedAccount, compare)
        }.also { com.wimg.app.ui.components.ScreenCache.put(key, it) }
        withContext(Dispatchers.IO) { com.wimg.app.services.WidgetDataWriter.writeSummary(context) }
    }
    // Early in a month: last month's Rückblick, once, docked on the bar. With
    // Gehaltsmonat: the salary questions and the period's end instead.
    LaunchedEffect(selectedAccount, periods) {
        val p = periods ?: return@LaunchedEffect
        if (offerSalaryPrompts(context, p, selectedAccount) { from -> ReviewTarget.period = from; navController?.navigate("review") { popUpTo("dashboard") } }) return@LaunchedEffect
        if (!p.isCalendar) return@LaunchedEffect
        offerMonthEnd(context, selectedAccount) { y, m ->
            ReviewTarget.ym = y to m
            navController?.navigate("review") { popUpTo("dashboard") }
        }
    }

    val locale = if (LocaleState.locale == "en") Locale.ENGLISH else Locale.GERMAN
    val months = remember(locale) { DateFormatSymbols(locale).months }
    val shortMonths = remember(locale) { DateFormatSymbols(locale).shortMonths.map { it.trimEnd('.') } }
    val isCurrent = year == now.get(Calendar.YEAR) && month == now.get(Calendar.MONTH) + 1

    val hasData = data?.hasAnyData != false
    BarContribution(
        // Option A of the "Zeitraum-Knopf" board: a ring with the days left in
        // the month; a finished month shows a full ring with its name.
        chip = if (!hasData) null else if (period != null) {
            val left = com.wimg.app.ui.components.PeriodLabels.daysLeft(period)
            when {
                !period.current -> BarChipSpec(com.wimg.app.ui.components.PeriodLabels.short(period), pickerOpen, { pickerOpen = !pickerOpen })
                // Same ring as the calendar month: days left until the salary.
                else -> BarChipSpec(
                    "$left", pickerOpen, { pickerOpen = !pickerOpen }, ring = left.toFloat() / period.days.coerceAtLeast(1),
                    contentDescription = if (periods.isSalary) L("Zeitraum: Gehaltsmonat, noch %d Tage", left) else L("Zeitraum: noch %d Tage", left),
                )
            }
        } else run {
            val daysInMonth = Calendar.getInstance().apply { set(year, month - 1, 1) }.getActualMaximum(Calendar.DAY_OF_MONTH)
            val left = daysInMonth - now.get(Calendar.DAY_OF_MONTH)
            BarChipSpec(
                label = if (isCurrent) "$left" else shortMonths[month - 1],
                active = pickerOpen,
                onClick = { pickerOpen = !pickerOpen },
                ring = if (isCurrent) left.toFloat() / daysInMonth else 1f,
                contentDescription = if (isCurrent) L("Zeitraum: %s, noch %d Tage", months[month - 1], left) else L("Zeitraum: %s %d", months[month - 1], year),
            )
        },
        panel = if (pickerOpen) {
            {
                if (pickingAccount) AccountsPanel(selectedAccount, onPick = onSelectAccount, onDone = { pickingAccount = false; pickerOpen = false })
                else if (period != null) PeriodPanel(periods, period, onPick = { periodIdx = periods.periods.indexOf(it); pickerOpen = false }) {
                    if (accounts.size > 1) {
                        PanelLabel(L("Konto"))
                        SegmentRow(listOf((accounts.firstOrNull { it.id == selectedAccount }?.name ?: L("Alle Konten")) + "  ›"), 0) { pickingAccount = true }
                    }
                }
                else MonthPickerPanel(year, month, shortMonths, now, onPick = { y, m -> year = y; month = m; pickerOpen = false }) {
                    PanelLabel(L("Vergleichen mit"))
                    SegmentRow(HomeCompare.entries.map { L(it.label) }, HomeCompare.entries.indexOf(compare)) { compare = HomeCompare.entries[it] }
                    if (accounts.size > 1) {
                        PanelLabel(L("Konto"))
                        SegmentRow(listOf((accounts.firstOrNull { it.id == selectedAccount }?.name ?: L("Alle Konten")) + "  ›"), 0) { pickingAccount = true }
                    }
                    // Last, right above the bar: the panel grows upwards, so the
                    // switch stays under the finger whatever it changes above.
                    periods?.let { PeriodModeRow(it) }
                }
            }
        } else null,
        onPanelDismiss = { pickerOpen = false; pickingAccount = false },
    )

    val d = data
    if (d != null && !d.hasAnyData) {
        EmptyHome(
            onBank = { navController?.navigate("fints") },
            onImport = { navController?.navigate("import") },
            onDemo = {
                scope.launch {
                    withContext(Dispatchers.IO) { DemoDataService.loadDemoData(context) }
                    reload++
                }
            },
        )
        return
    }

    val s = d?.summary
    val income = s?.income ?: 0.0
    val spent = abs(s?.expenses ?: 0.0)
    val available = s?.available ?: 0.0
    val daysCounted = if (isCurrent) now.get(Calendar.DAY_OF_MONTH) else daysInMonth(year, month)
    val openRecurring: (String) -> Unit = { id -> navController?.navigate("rec/$id") }

    BandScreen(
        band = {
            if (period != null) {
                PeriodBand(periods, period, prevPeriod, s, d, openRecurring)
                if (period.current) FreshnessLine()
                return@BandScreen
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(L("Verfügbar im %s", months[month - 1]), style = WimgType.bandOver, color = Wimg.colors.bandSub)
                    com.wimg.app.ui.components.RollingAmount(
                        rollKey = com.wimg.app.ui.components.Changes.version,
                        euros = available,
                        style = WimgType.amountHero.copy(fontSize = WimgType.amountHero.fontSize * 1.05f),
                        centsStyle = WimgType.amountHeroCents,
                        color = when {
                            available > 0.004 -> Wimg.colors.bandPos
                            available < -0.004 -> Wimg.colors.bandNeg
                            else -> Color.White
                        },
                        modifier = Modifier.padding(top = 2.dp),
                    )
                    val count = s?.tx_count ?: 0
                    Text(
                        if (isCurrent) L("%d Umsätze bis %s", count, dayMonth(now.get(Calendar.DAY_OF_MONTH), month, shortMonths))
                        else L("%d Umsätze", count),
                        style = WimgType.desc,
                        color = Wimg.colors.bandSub,
                    )
                }
                // Hidden while the number would mislead (handoff §4.2): income must
                // cover spending and be at least 10 % of last month's.
                val prevIncome = d?.previous?.income ?: 0.0
                val quote = if (income > 0 && income >= spent && (prevIncome <= 0 || income >= prevIncome * 0.1)) ((income - spent) / income * 100).roundToInt() else null
                if (isCurrent) {
                    val dim = daysInMonth(year, month)
                    val (py, pm) = monthBefore(year, month, 1)
                    val usual = (d?.previous?.expenses?.let { abs(it) } ?: 0.0) / daysInMonth(py, pm)
                    // Until the numbers are loaded the squirrel just sits there (no "Leer" from an empty first frame).
                    val (pose, line) = if (d == null) SquirrelPose.NORMAL to "" else figureState(available, dim - daysCounted + 1, usual, salaryToday = false, salary = null, salaryMode = false)
                    val ym = "%04d-%02d".format(year, month)
                    val moment = if (d == null) null else pendingMoment(pose, periodKey = ym, salaryToday = false, salaryMode = false, spentToday = spentToday(d), rise = d?.priceRise, left = dim - daysCounted + 1, available = available, openRecurring = openRecurring)
                    BandFigure(pose, line, dim, daysCounted - 1, if (d == null) emptySet() else noSpendDays("$ym-01", daysCounted - 1, d.spendDates), moment)
                } else if (quote != null) SavingsRing(quote)
            }
            HorizontalDivider(Modifier.padding(top = 20.dp), thickness = 1.dp, color = Color.White.copy(alpha = 0.10f))
            Row(Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val prevIncome = d?.previous?.income ?: 0.0
                val quote = if (income > 0 && income >= spent && (prevIncome <= 0 || income >= prevIncome * 0.1)) ((income - spent) / income * 100).roundToInt() else null
                BandStat(L("Einnahmen"), amountText(income), Wimg.colors.bandPos, Modifier.weight(1f))
                BandStat(L("Ausgaben"), amountText(-spent), Color.White, Modifier.weight(1f))
                // Current month: the ring holds the squirrel, the Sparquote moves here.
                if (isCurrent) BandStat(L("Sparquote"), quote?.let { "$it %" } ?: "–", Color.White, Modifier.weight(1f))
                else BandStat(L("Ausgaben/Tag"), amountText(spent / daysCounted.coerceAtLeast(1), showPlus = false), Color.White, Modifier.weight(1f))
            }
            if (isCurrent) FreshnessLine()
        },
    ) {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp, bottom = barClearance()),
        ) {
            // by_category holds spending per category as positive amounts.
            val cats = (s?.by_category ?: emptyList()).filter { it.amount > 0.004 && it.id != WimgCategory.INCOME.id }
                .sortedByDescending { it.amount }
            val total = cats.sumOf { abs(it.amount) }
            val prevById = (d?.previous?.by_category ?: emptyList()).associateBy { it.id }
            if (cats.isNotEmpty()) {
                item {
                    SectionHeader(
                        if (period != null && period.current && periods.isSalary) L("Ausgaben seit dem Gehalt") else L("Ausgaben nach Kategorie"),
                        if (prevById.isEmpty()) null else if (period != null) L("vs. davor") else when (compare) {
                            HomeCompare.PREV -> L("vs. %s", months[(month + 10) % 12])
                            HomeCompare.AVG3 -> L("vs. Ø 3 Monate")
                            HomeCompare.LAST_YEAR -> L("vs. %s %d", shortMonths[month - 1], year - 1)
                        },
                    )
                    StackedBar(cats, total)
                }
                items(cats, key = { it.id }) { cat ->
                    CategoryRow(cat, total, prevById[cat.id]) {
                        TxTarget.category = cat.id
                        TxTarget.period = period?.let { txPeriodOf(it, periods.isSalary) } ?: monthPeriod(year, month)
                        navController?.navigate("transactions")
                    }
                }
            } else if (d != null) {
                item {
                    SectionHeader(L("Ausgaben nach Kategorie"), null)
                    Text(if (period != null && period.current && periods.isSalary) L("Noch keine Ausgaben seit dem Gehalt.") else if (period != null) L("Noch keine Ausgaben in diesem Zeitraum.") else L("Noch keine Ausgaben in diesem Monat."), style = WimgType.desc, color = Wimg.colors.text2, modifier = Modifier.padding(top = 10.dp))
                }
            }

            val pending = d?.pending ?: emptyList()
            if (pending.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(22.dp))
                    SectionHeader(L("Vorgemerkt"), amountText(pending.sumOf { it.amount }), trailingStrong = false)
                    Spacer(Modifier.height(4.dp))
                }
                items(pending, key = { "p_" + it.id }) { tx -> DayRow(tx, shortMonths, pending = true) { navController?.navigate("tx/${tx.id}") } }
            }

            val day = d?.day ?: emptyList()
            if (day.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(22.dp))
                    SectionHeader(
                        dayLabel(day.first().date, now, shortMonths, locale),
                        amountText(day.sumOf { it.amount }),
                        trailingStrong = true,
                    )
                    Spacer(Modifier.height(4.dp))
                }
                items(day, key = { it.id }) { tx -> DayRow(tx, shortMonths) { navController?.navigate("tx/${tx.id}") } }
            }
        }
    }
}

internal fun homeKey(year: Int, month: Int, account: String?, compare: HomeCompare = HomeCompare.PREV) = "home:$year-$month:$account:$compare"

private fun monthBefore(year: Int, month: Int, n: Int): Pair<Int, Int> {
    val idx = year * 12 + (month - 1) - n
    return idx / 12 to idx % 12 + 1
}

/** The summary to compare with: last month, the average of the last three, or last year's month. */
private fun comparison(year: Int, month: Int, account: String?, compare: HomeCompare): com.wimg.app.models.MonthlySummary? = when (compare) {
    HomeCompare.PREV -> monthBefore(year, month, 1).let { (y, m) -> LibWimg.getSummaryFiltered(y, m, account) }
    HomeCompare.LAST_YEAR -> LibWimg.getSummaryFiltered(year - 1, month, account)
    HomeCompare.AVG3 -> {
        val ms = (1..3).mapNotNull { n -> monthBefore(year, month, n).let { (y, m) -> LibWimg.getSummaryFiltered(y, m, account) } }.filter { it.tx_count > 0 }
        if (ms.isEmpty()) null else {
            val k = ms.size.toDouble()
            val cats = ms.flatMap { it.by_category }.groupBy { it.id }.map { (id, list) ->
                com.wimg.app.models.CategoryBreakdown(id, list.first().name, list.sumOf { it.amount } / k, (list.sumOf { it.count } / k).roundToInt())
            }
            com.wimg.app.models.MonthlySummary(year, month, ms.sumOf { it.income } / k, ms.sumOf { it.expenses } / k, ms.sumOf { it.available } / k, (ms.sumOf { it.tx_count } / k).roundToInt(), cats)
        }
    }
}

/**
 * "Noch keine Umsätze" is for an empty wimg, not an empty account: with an
 * account picked that has nothing (Bargeld), the page lost its chip and there
 * was no way back to "Alle Konten".
 */
private fun hasAnyData(all: List<Transaction>, account: String?): Boolean =
    all.isNotEmpty() || (account != null && LibWimg.getTransactionsFiltered(null).isNotEmpty())

internal fun loadHome(year: Int, month: Int, account: String?, compare: HomeCompare = HomeCompare.PREV): HomeData {
    val summary = LibWimg.getSummaryFiltered(year, month, account)
    val previous = comparison(year, month, account, compare)
    val all = LibWimg.getTransactionsFiltered(account)
    val prefix = "%04d-%02d".format(year, month)
    // Never show a day after today as "the latest" (scheduled or demo bookings).
    val today = Calendar.getInstance().let { "%04d-%02d-%02d".format(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1, it.get(Calendar.DAY_OF_MONTH)) }
    val inMonth = all.filter { it.date.startsWith(prefix) && !it.isExcluded && it.date <= today }
    val lastDate = inMonth.maxOfOrNull { it.date }
    return HomeData(
        summary = summary,
        previous = previous?.takeIf { it.tx_count > 0 },
        day = if (lastDate == null) emptyList() else inMonth.filter { it.date == lastDate }.take(6),
        hasAnyData = hasAnyData(all, account),
        pending = if (today.startsWith(prefix)) LibWimg.getPending(account) else emptyList(),
        spendDates = inMonth.filter { it.amount < 0 }.mapTo(HashSet()) { it.date },
        priceRise = if (today.startsWith(prefix)) latestPriceRise("$prefix-01") else null,
    )
}

private fun daysInMonth(year: Int, month: Int): Int =
    Calendar.getInstance().apply { set(year, month - 1, 1) }.getActualMaximum(Calendar.DAY_OF_MONTH)

private fun dayMonth(day: Int, month: Int, @Suppress("UNUSED_PARAMETER") shortMonths: List<String>) = com.wimg.app.ui.components.WimgDates.dayMonth(day, month)

@Composable
private fun dayLabel(date: String, now: Calendar, shortMonths: List<String>, locale: Locale): String {
    val (y, m, dd) = date.split("-").map { it.toInt() }
    val cal = Calendar.getInstance().apply { set(y, m - 1, dd, 0, 0, 0) }
    val today = now.clone() as Calendar
    val sameDay = { a: Calendar, b: Calendar -> a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR) }
    val yesterday = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -1) }
    return when {
        sameDay(cal, today) -> L("Heute")
        sameDay(cal, yesterday) -> L("Gestern")
        else -> {
            val wd = DateFormatSymbols(locale).shortWeekdays[cal.get(Calendar.DAY_OF_WEEK)].trimEnd('.')
            "$wd${if (LocaleState.locale == "en") "" else "."} ${dayMonth(dd, m, shortMonths)}"
        }
    }
}

@Composable
private fun BandStat(label: String, value: String, color: Color, modifier: Modifier) {
    Column(modifier) {
        Text(label, style = WimgType.caption.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Normal), color = Wimg.colors.bandSub, maxLines = 1)
        Text(value, style = WimgType.amountStat, color = color, maxLines = 1, modifier = Modifier.padding(top = 2.dp))
    }
}

@Composable
private fun SavingsRing(percent: Int) {
    val c = Wimg.colors
    val desc = L("Sparquote %d Prozent", percent)
    Box(Modifier.size(84.dp).semantics { contentDescription = desc }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(84.dp)) {
            val stroke = 7.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(size.width - stroke, size.height - stroke)
            drawArc(Color.White.copy(alpha = 0.12f), 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(stroke))
            drawArc(c.bandPos, -90f, 360f * percent.coerceIn(0, 100) / 100f, false, Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("$percent %", style = WimgType.chip.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.ExtraBold), color = Color.White)
            Text(L("Sparquote"), style = WimgType.caption.copy(fontSize = WimgType.caption.fontSize * 0.84f), color = c.bandSub)
        }
    }
}

@Composable
private fun SectionHeader(title: String, trailing: String?, trailingStrong: Boolean = false) {
    val c = Wimg.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Text(title, style = WimgType.section.copy(fontSize = WimgType.section.fontSize * 0.95f), color = c.text, modifier = Modifier.weight(1f))
        if (trailing != null) {
            Text(
                trailing,
                style = if (trailingStrong) WimgType.chip.copy(fontSize = WimgType.chip.fontSize * 0.93f) else WimgType.caption,
                color = c.text2,
            )
        }
    }
}

@Composable
private fun StackedBar(cats: List<CategoryBreakdown>, total: Double) {
    val c = Wimg.colors
    val label = cats.joinToString { "${__t(WimgCategory.fromId(it.id).label)} ${(abs(it.amount) / total * 100).roundToInt()} %" }
    Row(
        Modifier
            .padding(top = 14.dp, bottom = 6.dp)
            .fillMaxWidth()
            .height(12.dp)
            .clip(RoundedCornerShape(6.dp))
            .semantics { contentDescription = label },
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        cats.forEach { cat ->
            Box(Modifier.weight((abs(cat.amount) / total).toFloat().coerceAtLeast(0.004f)).fillMaxSize().background(c.categoryBar(cat.id)))
        }
    }
}

@Composable
private fun CategoryRow(cat: CategoryBreakdown, total: Double, previous: CategoryBreakdown?, onClick: () -> Unit) {
    val c = Wimg.colors
    val wc = WimgCategory.fromId(cat.id)
    val isOther = cat.id == WimgCategory.UNCATEGORIZED.id || cat.id == WimgCategory.OTHER.id
    val pct = (abs(cat.amount) / total * 100).roundToInt()
    Column(Modifier.clickable(onClick = onClick)) {
        Row(Modifier.fillMaxWidth().height(60.dp), verticalAlignment = Alignment.CenterVertically) {
            IconTile(if (isOther) Icons.Outlined.LocalOffer else wc.icon, c.category(cat.id), Modifier.size(34.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(L(wc.label), style = WimgType.rowTitle, color = c.text, modifier = Modifier.weight(1f), maxLines = 1)
                    Text(amountText(abs(cat.amount), showPlus = false), style = WimgType.amountRow.copy(fontSize = WimgType.amountRow.fontSize * 0.94f), color = c.text)
                }
                Row(Modifier.padding(top = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width((pct * 2).coerceIn(4, 180).dp).height(4.dp).clip(CircleShape).background(c.categoryBar(cat.id)))
                    Spacer(Modifier.width(8.dp))
                    Text("$pct %", style = WimgType.caption.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Normal), color = c.text2, modifier = Modifier.weight(1f))
                    if (previous != null && previous.amount > 0.004) {
                        val prev = previous.amount
                        val change = ((abs(cat.amount) - prev) / prev * 100).roundToInt()
                        if (change != 0) {
                            val up = change > 0
                            val color = if (up) c.danger else c.pos
                            Icon(if (up) Icons.Outlined.ArrowDropUp else Icons.Outlined.ArrowDropDown, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
                            Text("${abs(change).coerceAtMost(999)} %", style = WimgType.caption.copy(fontFamily = WimgType.chip.fontFamily, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = color)
                        }
                    }
                }
            }
        }
        HorizontalDivider(thickness = 1.dp, color = c.line)
    }
}

@Composable
private fun DayRow(tx: Transaction, shortMonths: List<String>, pending: Boolean = false, onClick: () -> Unit) {
    val c = Wimg.colors
    val wc = WimgCategory.fromId(tx.category)
    val (_, m, d) = tx.date.split("-").map { it.toInt() }
    val sub = listOfNotNull(dayMonth(d, m, shortMonths), L(wc.label), tx.kind?.takeIf { it.isNotBlank() }?.let { L(it) }, if (pending) L("vorgemerkt") else null).joinToString(" · ")
    Column(Modifier.clickable(onClick = onClick)) {
        Row(Modifier.fillMaxWidth().height(58.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(tx.displayTitle, style = WimgType.rowTitle.copy(fontSize = WimgType.rowTitle.fontSize * 0.94f), color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
                    Box(Modifier.size(6.dp).clip(CircleShape).background(c.categoryBar(tx.category)))
                    Spacer(Modifier.width(6.dp))
                    Text(sub, style = WimgType.caption.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Normal), color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Spacer(Modifier.width(12.dp))
            Text(
                amountText(tx.amount),
                style = WimgType.amountRow.copy(fontSize = WimgType.amountRow.fontSize * 0.94f),
                color = when { pending -> c.text3; tx.amount > 0 -> c.pos; else -> c.text },
            )
        }
        HorizontalDivider(thickness = 1.dp, color = c.line)
    }
}

@Composable
internal fun MonthPickerPanel(
    year: Int, month: Int, shortMonths: List<String>, now: Calendar, onPick: (Int, Int) -> Unit,
    extra: (@Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit)? = null,
) {
    val c = Wimg.colors
    var shownYear by remember { mutableIntStateOf(year) }
    val curYear = now.get(Calendar.YEAR)
    val curMonth = now.get(Calendar.MONTH) + 1
    BarPanel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L("Zeitraum"), style = WimgType.button.copy(fontSize = WimgType.button.fontSize * 1.07f), color = c.text, modifier = Modifier.weight(1f))
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowLeft, contentDescription = L("Vorheriges Jahr"), tint = c.text,
                modifier = Modifier.size(36.dp).pressable { shownYear-- }.clip(CircleShape).padding(6.dp),
            )
            Text("$shownYear", style = WimgType.chip, color = c.text, modifier = Modifier.padding(horizontal = 6.dp))
            val canNext = shownYear < curYear
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = L("Nächstes Jahr"), tint = if (canNext) c.text else c.text3,
                modifier = Modifier.size(36.dp).pressable(enabled = canNext) { shownYear++ }.clip(CircleShape).padding(6.dp),
            )
        }
        Spacer(Modifier.height(12.dp))
        for (row in 0 until 3) {
            Row(Modifier.fillMaxWidth().padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (col in 0 until 4) {
                    val m = row * 4 + col + 1
                    val selected = shownYear == year && m == month
                    val future = shownYear > curYear || (shownYear == curYear && m > curMonth)
                    Box(
                        Modifier
                            .weight(1f)
                            .height(42.dp)
                            .pressable(enabled = !future) { onPick(shownYear, m) }
                            .clip(WimgShape.segmentOuter)
                            .background(if (selected) c.ink else c.neutralTint),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            shortMonths[m - 1],
                            style = WimgType.chip,
                            color = when { selected -> c.inkText; future -> c.text3; else -> c.text },
                        )
                    }
                }
            }
        }
        extra?.invoke(this)
    }
}

@Composable
private fun EmptyHome(onBank: () -> Unit, onImport: () -> Unit, onDemo: () -> Unit) {
    val c = Wimg.colors
    BandScreen(
        band = {
            Text(L("Noch keine Umsätze"), style = WimgType.title, color = Color.White)
            Text(
                L("Verbinde deine Bank oder lade eine CSV deiner Bank. Alles bleibt auf diesem Telefon."),
                style = WimgType.desc, color = c.bandSub, modifier = Modifier.padding(top = 6.dp),
            )
        },
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            EmptyAction(Icons.Outlined.AccountBalance, L("Bank verbinden"), L("Umsätze direkt per FinTS holen"), accent = true, onClick = onBank)
            EmptyAction(Icons.Outlined.FileUpload, L("CSV importieren"), L("Comdirect, Trade Republic, Scalable"), onClick = onImport)
            Text(
                L("Beispieldaten ansehen"),
                style = WimgType.button, color = c.accent,
                modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp).pressable(onClick = onDemo).clip(WimgShape.button).padding(12.dp),
            )
        }
    }
}

@Composable
private fun EmptyAction(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, desc: String, accent: Boolean = false, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(
        Modifier
            .fillMaxWidth()
            .pressable(onClick = onClick)
            .clip(WimgShape.group)
            .background(if (accent) c.ink else c.card)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = if (accent) c.inkText else c.text, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, style = WimgType.button, color = if (accent) c.inkText else c.text)
            Text(desc, style = WimgType.desc, color = if (accent) c.inkText.copy(alpha = 0.75f) else c.text2)
        }
    }
}

@Composable
internal fun PanelLabel(text: String) {
    Text(text, style = WimgType.label, color = Wimg.colors.text2, modifier = Modifier.padding(top = 14.dp, bottom = 8.dp))
}

/** One-line choice in a panel (Vergleich, Konto): the selected cell is ink. */
@Composable
internal fun SegmentRow(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val c = Wimg.colors
    Row(
        Modifier.fillMaxWidth().clip(WimgShape.segmentOuter).background(c.neutralTint).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        options.forEachIndexed { i, o ->
            val on = i == selected
            Box(
                Modifier.weight(1f).height(38.dp).clip(WimgShape.segmentInner).background(if (on) c.card else Color.Transparent).pressable { onSelect(i) },
                contentAlignment = Alignment.Center,
            ) { Text(o, style = WimgType.chip, color = if (on) c.text else c.text2, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) }
        }
    }
}

// ---------------------------------------------------------------------------
// Gehaltsmonat (boards 3 and 26A)
// ---------------------------------------------------------------------------

internal fun homePeriodKey(from: String, account: String?) = "home:$from:$account"

internal fun loadHomeRange(p: com.wimg.app.models.PeriodInfo, prev: com.wimg.app.models.PeriodInfo?, account: String?): HomeData {
    val summary = LibWimg.getSummaryRange(p.from, p.to, account)
    val previous = prev?.let { LibWimg.getSummaryRange(it.from, it.to, account) }
    val all = LibWimg.getTransactionsFiltered(account)
    val today = com.wimg.app.ui.components.WimgDates.todayIso()
    val inRange = all.filter { it.date >= p.from && it.date <= p.to && !it.isExcluded && it.date <= today }
    val lastDate = inRange.maxOfOrNull { it.date }
    return HomeData(
        summary = summary,
        previous = previous?.takeIf { it.tx_count > 0 },
        day = if (lastDate == null) emptyList() else inRange.filter { it.date == lastDate }.take(6),
        hasAnyData = hasAnyData(all, account),
        pending = if (p.current) LibWimg.getPending(account) else emptyList(),
        spendDates = inRange.filter { it.amount < 0 }.mapTo(HashSet()) { it.date },
        priceRise = if (p.current) latestPriceRise(p.from) else null,
    )
}

/** Band for a salary or "Fester Tag" period (board 3/01, 3/03, 26/04, 26/11). */
@Composable
private fun PeriodBand(
    periods: com.wimg.app.models.Periods,
    p: com.wimg.app.models.PeriodInfo,
    prevPeriod: com.wimg.app.models.PeriodInfo?,
    s: MonthlySummary?,
    d: HomeData?,
    openRecurring: (String) -> Unit,
) {
    val previous = d?.previous
    val c = Wimg.colors
    val L2 = com.wimg.app.ui.components.PeriodLabels
    val income = s?.income ?: 0.0
    val spent = abs(s?.expenses ?: 0.0)
    val available = s?.available ?: 0.0
    val salary = periods.salary
    val overdue = p.current && periods.isSalary && (salary?.overdue_days ?: 0) > 0
    val daysIn = if (p.current) L2.daysIn(p) else p.days
    val left = L2.daysLeft(p)
    val amountColor = when {
        available > 0.004 -> c.bandPos
        available < -0.004 -> c.bandNeg
        else -> Color.White
    }
    val prevIncome = previous?.income ?: 0.0
    val quote = if (!overdue && income > 0 && income >= spent && (prevIncome <= 0 || income >= prevIncome * 0.1)) ((income - spent) / income * 100).roundToInt() else null

    if (overdue) {
        val n = salary!!.overdue_days
        Row(
            Modifier.padding(bottom = 12.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.10f)).padding(horizontal = 12.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(androidx.compose.material.icons.Icons.Outlined.Schedule, contentDescription = null, tint = Color.White, modifier = Modifier.size(17.dp))
            Spacer(Modifier.width(8.dp))
            Text(if (n == 1) L("Gehalt erwartet seit 1 Tag") else L("Gehalt erwartet seit %d Tagen", n), style = WimgType.chip, color = Color.White)
        }
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            val over = when {
                !p.current && periods.isSalary -> L("Gehaltsmonat %s", L2.long(p))
                !p.current -> L2.long(p)
                overdue -> L("Verfügbar seit dem Gehalt")
                periods.isSalary -> L("Noch verfügbar bis zum Gehalt")
                else -> L("Noch verfügbar bis zum %d.", periods.day)
            }
            Text(over, style = WimgType.bandOver, color = c.bandSub)
            com.wimg.app.ui.components.RollingAmount(
                rollKey = com.wimg.app.ui.components.Changes.version, euros = available,
                style = WimgType.amountHero.copy(fontSize = WimgType.amountHero.fontSize * 1.05f), centsStyle = WimgType.amountHeroCents,
                color = amountColor, modifier = Modifier.padding(top = 2.dp),
            )
            val sub = when {
                !p.current -> L("%d Umsätze", s?.tx_count ?: 0)
                overdue -> L("Der Zeitraum läuft weiter, bis das Gehalt da ist.")
                periods.isSalary && daysIn == 1 && p.early_days > 0 -> L("Gehaltsmonat beginnt heute · %d Tage früher", p.early_days)
                periods.isSalary && daysIn == 1 -> L("Gehaltsmonat beginnt heute · bis ~%s", L2.dotted(p.to))
                available > 0.004 && left > 0 -> L("noch %d Tage · %s pro Tag", left, amountText(available / left, showPlus = false))
                else -> L("noch %d Tage", left)
            }
            Text(sub, style = WimgType.desc, color = c.bandSub)
        }
        if (p.current) {
            val usual = (previous?.expenses?.let { abs(it) } ?: 0.0) / (prevPeriod?.days ?: 30).coerceAtLeast(1)
            val (pose, line) = if (d == null) SquirrelPose.NORMAL to "" else figureState(available, left, usual, salaryToday = periods.isSalary && daysIn == 1 && !overdue, salary = p.salary ?: income, salaryMode = periods.isSalary)
            val salaryToday = periods.isSalary && daysIn == 1 && !overdue
            val moment = if (d == null) null else pendingMoment(pose, periodKey = p.from, salaryToday = salaryToday, salaryMode = periods.isSalary, spentToday = spentToday(d), rise = d?.priceRise, left = left, available = available, openRecurring = openRecurring)
            BandFigure(pose, line, p.days, daysIn - 1, if (d == null) emptySet() else noSpendDays(p.from, daysIn - 1, d.spendDates), moment)
        } else if (quote != null) SavingsRing(quote)
    }
    HorizontalDivider(Modifier.padding(top = 20.dp), thickness = 1.dp, color = Color.White.copy(alpha = 0.10f))
    Row(Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        when {
            overdue -> {
                BandStat(L("Seit Gehalt"), amountText(-spent), Color.White, Modifier.weight(1f))
                BandStat(L("Erwartet am"), L2.dotted(salary!!.next), Color.White, Modifier.weight(1f))
                BandStat(L("Ausgaben/Tag"), amountText(spent / daysIn.coerceAtLeast(1), showPlus = false), Color.White, Modifier.weight(1f))
            }
            p.current && periods.isSalary -> {
                BandStat(L("Gehalt %s", L2.dotted(p.from)), amountText(p.salary ?: income), c.bandPos, Modifier.weight(1f))
                BandStat(L("Seitdem ausgegeben"), amountText(-spent), Color.White, Modifier.weight(1f))
                // The ring holds the squirrel; the Sparquote moves into this row.
                BandStat(L("Sparquote"), quote?.let { "$it %" } ?: "–", Color.White, Modifier.weight(1f))
            }
            else -> {
                BandStat(L("Einnahmen"), amountText(income), c.bandPos, Modifier.weight(1f))
                BandStat(L("Ausgaben"), amountText(-spent), Color.White, Modifier.weight(1f))
                if (p.current) BandStat(L("Sparquote"), quote?.let { "$it %" } ?: "–", Color.White, Modifier.weight(1f))
                else BandStat(L("Ausgaben/Tag"), amountText(spent / daysIn.coerceAtLeast(1), showPlus = false), Color.White, Modifier.weight(1f))
            }
        }
    }
}

/** "Monat beginnt" (Gehalt / Kalender / Fester Tag), shared by the panels and Einstellungen › Zeitraum. */
@Composable
internal fun PeriodModeRow(periods: com.wimg.app.models.Periods) {
    val scope = rememberCoroutineScope()
    val modes = listOf("salary", "calendar", "day")
    // The segment moves on the tap itself; the periods follow a moment later.
    var picked by remember(periods.chosen) { mutableIntStateOf(modes.indexOf(periods.chosen).coerceAtLeast(0)) }
    if (periods.chosen == "salary" && !periods.isSalary) {
        Text(
            L("Gehalt noch nicht erkannt: wimg braucht zwei Gehälter vom selben Absender. Bis dahin zählt es nach Kalendermonat."),
            style = WimgType.desc, color = Wimg.colors.text2, modifier = Modifier.padding(top = 12.dp, start = 4.dp),
        )
    }
    PanelLabel(L("Monat beginnt"))
    SegmentRow(listOf(L("Gehalt"), L("Kalender"), L("Fester Tag")), picked) { i ->
        if (i == picked) return@SegmentRow
        picked = i
        scope.launch { com.wimg.app.ui.components.PeriodState.setMode(modes[i], if (modes[i] == "day") (if (periods.day > 1) periods.day else 15) else 0) }
    }
}

/** Zeitraum panel with salary or "Fester Tag" periods (board 3/02). */
@Composable
internal fun PeriodPanel(
    periods: com.wimg.app.models.Periods,
    selected: com.wimg.app.models.PeriodInfo,
    onPick: (com.wimg.app.models.PeriodInfo) -> Unit,
    extra: (@Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit)? = null,
) {
    val c = Wimg.colors
    var choosingPayer by remember { mutableStateOf(false) }
    if (choosingPayer) {
        PayerPanel(periods) { choosingPayer = false }
        return
    }
    BarPanel {
        Text(L("Zeitraum"), style = WimgType.button.copy(fontSize = WimgType.button.fontSize * 1.07f), color = c.text)
        if (periods.isSalary) periods.salary?.let { sal ->
            SalaryCard(sal, Modifier.padding(top = 12.dp)) { choosingPayer = true }
        }
        if (periods.mode == "day") DayStepper(periods)
        Spacer(Modifier.height(10.dp))
        periods.periods.take(5).forEach { p ->
            val on = p == selected
            Row(
                Modifier.fillMaxWidth().clip(WimgShape.segmentOuter).background(if (on) c.neutralTint else Color.Transparent)
                    .clickable { onPick(p) }.padding(horizontal = 14.dp, vertical = 13.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    if (p.current) "${com.wimg.app.ui.components.PeriodLabels.dotted(p.from)} – ${L("heute")}" else com.wimg.app.ui.components.PeriodLabels.short(p),
                    style = WimgType.rowTitle, color = c.text, modifier = Modifier.weight(1f),
                )
                if (p.current) Text(L("aktuell"), style = WimgType.desc, color = c.text2)
            }
        }
        extra?.invoke(this)
        // Last, right above the bar (see MonthPickerPanel's extra).
        PeriodModeRow(periods)
    }
}

/** "Erkanntes Gehalt" with Ändern (board 3/02, 26/09). */
@Composable
internal fun SalaryCard(sal: com.wimg.app.models.SalaryInfo, modifier: Modifier = Modifier, onChange: () -> Unit) {
    val c = Wimg.colors
    Row(
        modifier.fillMaxWidth().clip(WimgShape.group).border(1.dp, c.line, WimgShape.group).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(L("Erkanntes Gehalt"), style = WimgType.desc, color = c.text2)
            Text("${sal.name} · ${amountText(sal.amount, showPlus = false)}", style = WimgType.rowTitle, color = c.text, maxLines = 2)
            Text(L("meist um den %d. · %d× gesehen", sal.day, sal.count), style = WimgType.desc, color = c.text2)
        }
        Spacer(Modifier.width(10.dp))
        Box(
            Modifier.height(40.dp).pressable(onClick = onChange).clip(WimgShape.button).border(1.dp, c.line, WimgShape.button).padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) { Text(L("Ändern"), style = WimgType.chip, color = c.text) }
    }
}

/** "Fester Tag": which day a month starts on (1–28). */
@Composable
internal fun DayStepper(periods: com.wimg.app.models.Periods) {
    val c = Wimg.colors
    val scope = rememberCoroutineScope()
    fun set(d: Int) = scope.launch { com.wimg.app.ui.components.PeriodState.setMode("day", d) }
    Row(Modifier.padding(top = 12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(L("Monat beginnt am"), style = WimgType.rowTitle, color = c.text, modifier = Modifier.weight(1f))
        Icon(
            Icons.AutoMirrored.Outlined.KeyboardArrowLeft, contentDescription = L("Früher"), tint = if (periods.day > 1) c.text else c.text3,
            modifier = Modifier.size(40.dp).pressable(enabled = periods.day > 1) { set(periods.day - 1) }.clip(CircleShape).background(c.neutralTint).padding(8.dp),
        )
        Text("${periods.day}.", style = WimgType.button, color = c.text, modifier = Modifier.width(48.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Icon(
            Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = L("Später"), tint = if (periods.day < 28) c.text else c.text3,
            modifier = Modifier.size(40.dp).pressable(enabled = periods.day < 28) { set(periods.day + 1) }.clip(CircleShape).background(c.neutralTint).padding(8.dp),
        )
    }
}

/** "Gehalt selbst auswählen": incomes of the last months, largest first. */
@Composable
internal fun PayerPanel(periods: com.wimg.app.models.Periods, onDone: () -> Unit) {
    val c = Wimg.colors
    val scope = rememberCoroutineScope()
    BarPanel {
        Text(L("Welche Einnahme ist dein Gehalt?"), style = WimgType.sheetTitle, color = c.text, modifier = Modifier.padding(start = 4.dp, bottom = 12.dp))
        if (periods.payers.isEmpty()) Text(L("Noch keine Einnahmen in den letzten Monaten."), style = WimgType.desc, color = c.text2)
        com.wimg.app.ui.components.WimgGroup {
            periods.payers.forEachIndexed { i, p ->
                if (i > 0) com.wimg.app.ui.components.RowDivider()
                RadioRow(
                    p.title, L("%s · %d× seit %s", amountText(p.amount, showPlus = false), p.count, com.wimg.app.ui.components.PeriodLabels.dotted(p.last)),
                    periods.salary?.key == p.key && periods.salary.confirmed,
                ) {
                    scope.launch {
                        withContext(Dispatchers.IO) {
                            LibWimg.answerSalary(p.key, 2)
                            LibWimg.setPeriodMode("salary")
                        }
                        com.wimg.app.ui.components.Changes.bump()
                        onDone()
                    }
                }
            }
        }
    }
}


// ---------------------------------------------------------------------------
// Spielgefühl: the squirrel in the band (board "Eichhörnchen im Band")
// ---------------------------------------------------------------------------

/**
 * The squirrel's state and the one line its tap shows. Gehalt da on the day the
 * salary arrived; Leer at or below zero; Knapp when what is left per day is less
 * than the usual daily spending (last period); Voll when it is clearly more.
 */
internal fun figureState(available: Double, left: Int, usualPerDay: Double, salaryToday: Boolean, salary: Double?, salaryMode: Boolean): Pair<com.wimg.app.ui.components.SquirrelPose, String> {
    val days = left.coerceAtLeast(1)
    val perDay = available / days
    fun eur(v: Double) = amountText(v, showPlus = false)
    return when {
        salaryToday -> SquirrelPose.GEHALT to __t("Gehalt da: %s. Neuer Gehaltsmonat.").format(eur(salary ?: available))
        available <= 0.004 -> SquirrelPose.LEER to (if (salaryMode) __t("Leer: %s im Minus. Gehalt kommt in ~%d Tagen.") else __t("Leer: %s im Minus. Neuer Monat in %d Tagen.")).format(eur(-available), days)
        usualPerDay > 0.5 && perDay < usualPerDay -> SquirrelPose.KNAPP to __t("Knapp: noch %s für %d Tage, sonst gibst du ~%s am Tag aus.").format(eur(available), days, eur(usualPerDay))
        usualPerDay > 0.5 && perDay > usualPerDay * 1.5 -> SquirrelPose.VOLL to __t("Voll: noch %s für %d Tage. Du brauchst sonst ~%s am Tag. Viel Luft.").format(eur(available), days, eur(usualPerDay))
        usualPerDay > 0.5 -> SquirrelPose.NORMAL to __t("Normal: %s für %d Tage, das sind %s am Tag. Sonst gibst du ~%s aus.").format(eur(available), days, eur(perDay), eur(usualPerDay))
        else -> SquirrelPose.NORMAL to __t("Normal: %s für %d Tage, das sind %s am Tag.").format(eur(available), days, eur(perDay))
    }
}

/** Days (1-based) among the first [daysPast] of a period starting at [fromIso] without any spending. */
internal fun noSpendDays(fromIso: String, daysPast: Int, spendDates: Set<String>): Set<Int> {
    val start = com.wimg.app.ui.components.WimgDates.parse(fromIso) ?: return emptySet()
    val out = HashSet<Int>()
    for (i in 1..daysPast.coerceAtLeast(0)) {
        val c = (start.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, i - 1) }
        val iso = "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
        if (iso !in spendDates) out += i
    }
    return out
}

/**
 * How fresh the numbers are: "Stand heute, 06:12 · comdirect" from the newest
 * bank fetch, "Umsätze werden geladen …" while one runs. Nothing without a bank.
 */
@Composable
private fun FreshnessLine() {
    val context = LocalContext.current
    val fetching = fintsFetching
    val conn = remember(com.wimg.app.ui.components.Changes.version, fetching) {
        com.wimg.app.services.BankConnections.all(context).filter { it.lastFetchAt > 0 }.maxByOrNull { it.lastFetchAt }
    }
    val text = when {
        fetching -> L("Umsätze werden geladen …")
        conn == null -> return
        else -> {
            val at = Calendar.getInstance().apply { timeInMillis = conn.lastFetchAt }
            val time = "%02d:%02d".format(at.get(Calendar.HOUR_OF_DAY), at.get(Calendar.MINUTE))
            val day = com.wimg.app.ui.components.WimgDates.todayIso()
            val iso = "%04d-%02d-%02d".format(at.get(Calendar.YEAR), at.get(Calendar.MONTH) + 1, at.get(Calendar.DAY_OF_MONTH))
            val yesterday = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }.let { "%04d-%02d-%02d".format(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1, it.get(Calendar.DAY_OF_MONTH)) }
            when (iso) {
                day -> L("Stand heute, %s · %s", time, conn.name)
                yesterday -> L("Stand gestern, %s · %s", time, conn.name)
                else -> L("Stand %s · %s", com.wimg.app.ui.components.WimgDates.short(iso), conn.name)
            }
        }
    }
    Text(text, style = WimgType.desc, color = Wimg.colors.bandSub, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.padding(top = 12.dp))
}

/** A moment the squirrel plays once (prototype MOMENTS), with the line its bubble shows after. */
internal class PendingMoment(
    val key: String,
    val moment: SquirrelMoment,
    val line: String,
    val action: String? = null,
    val onAction: (() -> Unit)? = null,
    val prices: Pair<String, String> = "" to "",
)

private const val MOMENTS_PREFS = "wimg_moments"

internal fun spentToday(d: HomeData?): Boolean {
    val today = com.wimg.app.ui.components.WimgDates.todayIso()
    return d == null || today in d.spendDates || d.pending.any { it.amount < 0 && it.date == today }
}

/**
 * Which moment to play now, if any, once each (remembered on this device):
 * Gehalt ist da (first open of a new pay period) > Leer > Knapp (first time
 * in a period) > Preiserhöhung (a new unconfirmed price) > Tag ohne Ausgaben
 * (after 20:00, nothing spent today).
 */
@Composable
internal fun pendingMoment(
    pose: SquirrelPose, periodKey: String, salaryToday: Boolean, salaryMode: Boolean, spentToday: Boolean,
    rise: PriceRise?, left: Int, available: Double, openRecurring: (String) -> Unit,
): PendingMoment? {
    val prefs = LocalContext.current.getSharedPreferences(MOMENTS_PREFS, 0)
    fun eur(v: Double) = amountText(v, showPlus = false)
    val days = left.coerceAtLeast(1)
    val hour = remember { Calendar.getInstance().get(Calendar.HOUR_OF_DAY) }
    val today = com.wimg.app.ui.components.WimgDates.todayIso()
    val candidates = buildList {
        if (salaryToday) add(PendingMoment("gehalt:$periodKey", SquirrelMoment.GEHALT, L("Gehalt ist da. Neuer Gehaltsmonat.")))
        if (pose == SquirrelPose.LEER) add(PendingMoment("leer:$periodKey", SquirrelMoment.LEER,
            if (salaryMode) L("Leer. Die Motte findet's gemütlich. Gehalt kommt in ~%d Tagen.", days) else L("Leer. Die Motte findet's gemütlich. Neuer Monat in %d Tagen.", days)))
        if (pose == SquirrelPose.KNAPP) add(PendingMoment("knapp:$periodKey", SquirrelMoment.KNAPP,
            L("%s für %d Tage. Das sind %s am Tag. Geht.", eur(available), days, eur(available / days))))
        if (rise != null) add(PendingMoment("price:${rise.id}:${Math.round(rise.new * 100)}", SquirrelMoment.PRICE,
            L("Hab dich. %s kostet jetzt %s statt %s.", rise.name, eur(rise.new), eur(rise.old)), L("Ansehen"), { openRecurring(rise.id) }, eur(rise.old) to eur(rise.new)))
        if (hour >= 20 && !spentToday && pose != SquirrelPose.LEER) add(PendingMoment("nospend:$today", SquirrelMoment.NO_SPEND, L("Heute kein Euro raus.")))
    }
    // Debug builds: `files/moment` holding gehalt|leer|knapp|price|nospend plays that one once (for checking).
    val forced = if (LocalContext.current.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) java.io.File(LocalContext.current.filesDir, "moment").takeIf { it.exists() }?.let { f ->
        val name = f.readText().trim(); f.delete()
        when (name) {
            "gehalt" -> PendingMoment("dbg", SquirrelMoment.GEHALT, L("Gehalt ist da. Neuer Gehaltsmonat."))
            "leer" -> PendingMoment("dbg", SquirrelMoment.LEER, L("Leer. Die Motte findet's gemütlich. Gehalt kommt in ~%d Tagen.", days))
            "knapp" -> PendingMoment("dbg", SquirrelMoment.KNAPP, L("%s für %d Tage. Das sind %s am Tag. Geht.", eur(available), days, eur(available / days)))
            "price" -> PendingMoment("dbg", SquirrelMoment.PRICE, L("Hab dich. %s kostet jetzt %s statt %s.", "Klangwelle", eur(11.99), eur(9.99)), L("Ansehen"), {}, eur(9.99) to eur(11.99))
            "nospend" -> PendingMoment("dbg", SquirrelMoment.NO_SPEND, L("Heute kein Euro raus."))
            else -> null
        }
    } else null
    return forced ?: candidates.firstOrNull { !prefs.getBoolean(it.key, false) }
}

/** Plays [m] frame by frame (prototype timings); with animations off it shows the end at once. */
private suspend fun playMoment(m: PendingMoment, set: (com.wimg.app.ui.components.SquirrelFrame) -> Unit) {
    if (android.animation.ValueAnimator.getDurationScale() == 0f) { set(m.moment.endFrame()); return }
    var cur = com.wimg.app.ui.components.SquirrelFrame(m.moment.from)
    set(cur)
    kotlinx.coroutines.delay(500) // let the page settle first
    for (st in m.moment.steps) {
        val target = st.to(cur)
        val start = cur
        val t0 = androidx.compose.runtime.withFrameMillis { it }
        while (true) {
            val u = ((androidx.compose.runtime.withFrameMillis { it } - t0) / st.ms.toFloat()).coerceIn(0f, 1f)
            set(com.wimg.app.ui.components.lerp(start, target, st.ease.transform(u)))
            if (u >= 1f) break
        }
        cur = target
    }
    // The bubble takes the ghost's place: it fades out as the line comes in.
    if (cur.gop > 0f) {
        val t0 = androidx.compose.runtime.withFrameMillis { it }
        while (true) {
            val u = ((androidx.compose.runtime.withFrameMillis { it } - t0) / 160f).coerceIn(0f, 1f)
            set(cur.copy(gop = 1f - u))
            if (u >= 1f) break
        }
    }
}

private class Bubble(val text: String, val action: String? = null, val onAction: (() -> Unit)? = null)

/**
 * The ring with the squirrel: blinks every 4–8 s, plays a pending moment once,
 * and a tap shows its line in a bubble beside it (nothing on the page moves).
 */
@Composable
private fun BandFigure(pose: SquirrelPose, line: String, periodDays: Int, dayIndex: Int, noSpend: Set<Int>, moment: PendingMoment?) {
    val context = LocalContext.current
    var blink by remember { mutableStateOf(false) }
    var frame by remember { mutableStateOf(com.wimg.app.ui.components.SquirrelFrame(pose)) }
    var playing by remember { mutableStateOf(false) }
    var bubble by remember { mutableStateOf<Bubble?>(null) }
    var prices by remember { mutableStateOf("" to "") }
    val currentPose by androidx.compose.runtime.rememberUpdatedState(pose)
    LaunchedEffect(pose) { if (!playing && frame.z == 0f) frame = com.wimg.app.ui.components.SquirrelFrame(pose) }
    LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.delay(kotlin.random.Random.nextLong(4_000, 8_000))
            if (!playing && frame.pose != SquirrelPose.SLEEP) { blink = true; kotlinx.coroutines.delay(140); blink = false }
        }
    }
    // One moment per visit, fixed once chosen: marking it played changes what
    // pendingMoment() answers next, and that must not cancel it halfway.
    var chosen by remember { mutableStateOf<PendingMoment?>(null) }
    if (chosen == null && moment != null) chosen = moment
    LaunchedEffect(chosen) {
        val m = chosen ?: return@LaunchedEffect
        context.getSharedPreferences(MOMENTS_PREFS, 0).edit().putBoolean(m.key, true).apply()
        prices = m.prices
        playing = true
        try { playMoment(m) { frame = it } } finally { playing = false }
        bubble = Bubble(m.line, m.action, m.onAction)
    }
    LaunchedEffect(bubble) {
        if (bubble == null) return@LaunchedEffect
        kotlinx.coroutines.delay(if (bubble?.action != null) 7_000 else 5_000)
        bubble = null
        // Back to the real state (the ghost leaves with the bubble); asleep stays asleep.
        if (!playing && frame.pose != SquirrelPose.SLEEP) frame = com.wimg.app.ui.components.SquirrelFrame(currentPose)
    }
    // Below 380 dp of width the figure shrinks to 88 % (board).
    val narrow = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp < 380
    val size = if (narrow) 99.dp else 112.dp
    Box(Modifier.size(size)) {
        com.wimg.app.ui.components.SquirrelRing(
            frame = frame, periodDays = periodDays, dayIndex = dayIndex, noSpendDays = noSpend,
            size = size, blink = blink, ghostPrices = prices,
        )
        // Tap target on its own layer: clipping the ring itself would cut off the price ghost beside it.
        Box(Modifier.matchParentSize().clip(CircleShape).pressable(label = L("Eichhörnchen: Zustand erklären")) {
            if (line.isNotEmpty()) bubble = if (bubble?.text == line) null else Bubble(line)
        })
        SquirrelBubble(bubble, Modifier.align(Alignment.CenterStart))
    }
}

/** The squirrel's speech bubble, left of the ring and pointing at it; grows from its tail. */
@Composable
private fun SquirrelBubble(bubble: Bubble?, modifier: Modifier = Modifier) {
    var last by remember { mutableStateOf(bubble) }
    if (bubble != null) last = bubble
    androidx.compose.animation.AnimatedVisibility(
        visible = bubble != null,
        enter = androidx.compose.animation.fadeIn(tween(160, easing = WimgMotion.EaseOut)) +
            androidx.compose.animation.scaleIn(tween(200, easing = WimgMotion.EaseOut), initialScale = 0.9f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(1f, 0.5f)),
        exit = androidx.compose.animation.fadeOut(tween(150, easing = WimgMotion.EaseOut)),
        modifier = modifier
            // Hangs out to the left of the ring, over the amount, without taking room.
            .layout { m, cs ->
                val p = m.measure(cs.copy(minWidth = 0, maxWidth = 236.dp.roundToPx()))
                layout(0, 0) { p.place(-p.width + 10.dp.roundToPx(), -p.height / 2) }
            },
    ) {
        val b = last ?: return@AnimatedVisibility
        val c = Wimg.colors
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
                Modifier.widthIn(max = 220.dp)
                    .shadow(10.dp, RoundedCornerShape(16.dp), ambientColor = Color.Black.copy(alpha = 0.3f), spotColor = Color.Black.copy(alpha = 0.3f))
                    .clip(RoundedCornerShape(16.dp)).background(Color.White).padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                Text(b.text, style = WimgType.desc, color = Color(0xFF1A1A1A))
                if (b.action != null) Text(
                    b.action, style = WimgType.chip, color = c.accent,
                    modifier = Modifier.padding(top = 6.dp).clip(RoundedCornerShape(8.dp)).pressable { b.onAction?.invoke() }.padding(vertical = 2.dp),
                )
            }
            // Tail towards the squirrel.
            androidx.compose.foundation.Canvas(Modifier.size(8.dp, 14.dp)) {
                drawPath(androidx.compose.ui.graphics.Path().apply { moveTo(0f, 0f); lineTo(size.width, size.height / 2); lineTo(0f, size.height); close() }, Color.White)
            }
        }
    }
}
