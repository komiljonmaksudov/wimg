package com.wimg.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
)

@Composable
fun HomeScreen(selectedAccount: String?, navController: NavController? = null, onSelectAccount: (String?) -> Unit = {}) {
    val now = remember { Calendar.getInstance() }
    var year by remember { mutableIntStateOf(now.get(Calendar.YEAR)) }
    var month by remember { mutableIntStateOf(now.get(Calendar.MONTH) + 1) }
    var compare by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(HomeCompare.PREV) }
    var accounts by remember { mutableStateOf<List<com.wimg.app.models.Account>>(emptyList()) }
    LaunchedEffect(com.wimg.app.ui.components.Changes.version) { accounts = withContext(Dispatchers.IO) { LibWimg.getAccounts() } }
    var data by remember { mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<HomeData>(homeKey(year, month, selectedAccount, compare))) }
    var pickerOpen by remember { mutableStateOf(false) }
    var pickingAccount by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    LaunchedEffect(year, month, selectedAccount, compare, reload, com.wimg.app.ui.components.Changes.version) {
        val key = homeKey(year, month, selectedAccount, compare)
        com.wimg.app.ui.components.ScreenCache.get<HomeData>(key)?.let { data = it }
        data = withContext(Dispatchers.IO) { loadHome(year, month, selectedAccount, compare) }.also { com.wimg.app.ui.components.ScreenCache.put(key, it) }
        withContext(Dispatchers.IO) { com.wimg.app.services.WidgetDataWriter.writeSummary(context) }
    }
    // Early in a month: last month's Rückblick, once, docked on the bar.
    LaunchedEffect(selectedAccount) {
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
        chip = if (!hasData) null else run {
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
                else MonthPickerPanel(year, month, shortMonths, now, onPick = { y, m -> year = y; month = m; pickerOpen = false }) {
                    PanelLabel(L("Vergleichen mit"))
                    SegmentRow(HomeCompare.entries.map { L(it.label) }, HomeCompare.entries.indexOf(compare)) { compare = HomeCompare.entries[it] }
                    if (accounts.size > 1) {
                        PanelLabel(L("Konto"))
                        SegmentRow(listOf((accounts.firstOrNull { it.id == selectedAccount }?.name ?: L("Alle Konten")) + "  ›"), 0) { pickingAccount = true }
                    }
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

    BandScreen(
        band = {
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
                if (income > 0 && income >= spent && (prevIncome <= 0 || income >= prevIncome * 0.1)) {
                    SavingsRing(((income - spent) / income * 100).roundToInt())
                }
            }
            HorizontalDivider(Modifier.padding(top = 20.dp), thickness = 1.dp, color = Color.White.copy(alpha = 0.10f))
            Row(Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                BandStat(L("Einnahmen"), amountText(income), Wimg.colors.bandPos, Modifier.weight(1f))
                BandStat(L("Ausgaben"), amountText(-spent), Color.White, Modifier.weight(1f))
                BandStat(L("Ausgaben/Tag"), amountText(spent / daysCounted.coerceAtLeast(1), showPlus = false), Color.White, Modifier.weight(1f))
            }
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
                        L("Ausgaben nach Kategorie"),
                        if (prevById.isEmpty()) null else when (compare) {
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
                        TxTarget.period = monthPeriod(year, month)
                        navController?.navigate("transactions") { popUpTo("dashboard") }
                    }
                }
            } else if (d != null) {
                item {
                    SectionHeader(L("Ausgaben nach Kategorie"), null)
                    Text(L("Noch keine Ausgaben in diesem Monat."), style = WimgType.desc, color = Wimg.colors.text2, modifier = Modifier.padding(top = 10.dp))
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
        hasAnyData = all.isNotEmpty(),
        pending = if (today.startsWith(prefix)) LibWimg.getPending(account) else emptyList(),
    )
}

private fun daysInMonth(year: Int, month: Int): Int =
    Calendar.getInstance().apply { set(year, month - 1, 1) }.getActualMaximum(Calendar.DAY_OF_MONTH)

private fun dayMonth(day: Int, month: Int, shortMonths: List<String>) = "$day. ${shortMonths[month - 1]}."

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
            "$wd. ${dayMonth(dd, m, shortMonths)}"
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
    val label = cats.joinToString { "${WimgCategory.fromId(it.id).label} ${(abs(it.amount) / total * 100).roundToInt()} %" }
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
private fun PanelLabel(text: String) {
    Text(text, style = WimgType.label, color = Wimg.colors.text2, modifier = Modifier.padding(top = 14.dp, bottom = 8.dp))
}

/** One-line choice in a panel (Vergleich, Konto): the selected cell is ink. */
@Composable
private fun SegmentRow(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
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
