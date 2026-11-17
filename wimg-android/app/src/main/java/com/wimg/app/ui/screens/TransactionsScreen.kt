package com.wimg.app.ui.screens

import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import java.util.Calendar
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.produceState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.models.Account
import com.wimg.app.models.Transaction
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.Amount
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarChipSpec
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.amountText
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgMotion
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import com.wimg.app.ui.theme.categoryBar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A date range for the Umsätze filter; [to] inclusive, ISO dates. */
data class TxPeriod(val from: String, val to: String, val label: String, val key: String)

/** Filter Umsätze should open with (set by a tap on Home or Rückblick, read once). */
object TxTarget {
    var category: Int? = null
    var period: TxPeriod? = null
    /** Show only this account (from a bank page). */
    var account: String? = null
}

private fun iso(c: Calendar) = "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))

/** One calendar month as a period, labelled "Okt. 2026". */
fun monthPeriod(year: Int, month: Int): TxPeriod {
    val c = Calendar.getInstance().apply { set(year, month - 1, 1) }
    val from = iso(c)
    c.set(Calendar.DAY_OF_MONTH, c.getActualMaximum(Calendar.DAY_OF_MONTH))
    val short = java.text.DateFormatSymbols(if (com.wimg.app.ui.theme.LocaleState.locale == "en") java.util.Locale.ENGLISH else java.util.Locale.GERMAN).shortMonths[month - 1].trimEnd('.')
    return TxPeriod(from, iso(c), "$short $year", "m:$year-$month")
}

/** A Gehaltsmonat or "Fester Tag" period as an Umsätze filter. */
fun txPeriodOf(p: com.wimg.app.models.PeriodInfo, salary: Boolean): TxPeriod = TxPeriod(
    p.from, p.to,
    if (p.current && salary) __t("Seit %s").format(com.wimg.app.ui.components.PeriodLabels.dotted(p.from)) else com.wimg.app.ui.components.PeriodLabels.short(p),
    "p:${p.from}" + if (p.current && salary) ":salary" else "",
)

private fun lastDays(days: Int, label: String, key: String): TxPeriod {
    val c = Calendar.getInstance()
    val to = iso(c)
    c.add(Calendar.DAY_OF_YEAR, -days)
    return TxPeriod(iso(c), to, label, key)
}

private val CategorySetSaver = androidx.compose.runtime.saveable.Saver<Set<Int>, IntArray>(
    save = { it.toIntArray() }, restore = { it.toSet() },
)

private val PeriodSaver = androidx.compose.runtime.saveable.Saver<TxPeriod?, Any>(
    save = { p -> p?.let { arrayListOf(it.from, it.to, it.label, it.key) } ?: "" },
    restore = { v -> (v as? List<*>)?.let { TxPeriod(it[0] as String, it[1] as String, it[2] as String, it[3] as String) } },
)

enum class TxFilter(val label: String) {
    ALL("Alle"),
    EXPENSES("Ausgaben"),
    INCOME("Einnahmen"),
    /** Entered by hand ("Umsatz von Hand"). */
    MANUAL("Von Hand"),
}

/** Categories offered as filter chips, in the design's order. */
private val FILTER_CATEGORIES = listOf(
    WimgCategory.GROCERIES, WimgCategory.DINING, WimgCategory.TRANSPORT, WimgCategory.SHOPPING,
    WimgCategory.ENTERTAINMENT, WimgCategory.INSURANCE, WimgCategory.UTILITIES, WimgCategory.HOUSING,
    WimgCategory.SUBSCRIPTIONS, WimgCategory.HEALTH, WimgCategory.INCOME, WimgCategory.UNCATEGORIZED,
)

internal data class TxData(
    val transactions: List<Transaction>,
    val accounts: List<Account>,
    /** Not yet booked: shown apart, never in a total or the running balance. */
    val pending: List<Transaction> = emptyList(),
    /** The unfiltered list, grouped and summed in the background. */
    val view: TxView = TxView.of(transactions),
)

/** A list as Umsätze shows it: by day, plus each row's position and the sum before it. */
internal class TxView(val list: List<Transaction>) {
    val grouped: List<Pair<String, List<Transaction>>> = list.groupBy { it.date }.toList()
    val indexOf: Map<String, Int> = HashMap<String, Int>(list.size * 2).apply { list.forEachIndexed { i, t -> put(t.id, i) } }
    val before: DoubleArray = DoubleArray(list.size + 1).also { a -> list.forEachIndexed { i, t -> a[i + 1] = a[i] + t.amount } }

    companion object { fun of(list: List<Transaction>) = TxView(list) }
}

internal fun txKey(account: String?) = "tx:$account"

internal fun loadTx(account: String?) = TxData(
    transactions = LibWimg.getTransactionsFiltered(account).sortedByDescending { it.date },
    // All accounts are needed for the Konto row; the band sums the shown ones.
    accounts = LibWimg.getAccounts(),
    pending = LibWimg.getPending(account).sortedByDescending { it.date },
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TransactionsScreen(selectedAccount: String?, navController: NavController? = null, onSelectAccount: (String?) -> Unit = {}) {
    var data by remember { mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<TxData>(txKey(selectedAccount))) }
    // Saveable: the filter survives opening a transaction and coming back.
    var filter by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(TxFilter.ALL) }
    var categories by androidx.compose.runtime.saveable.rememberSaveable(stateSaver = CategorySetSaver) {
        mutableStateOf(TxTarget.category?.let { setOf(it) } ?: emptySet())
    }
    var period by androidx.compose.runtime.saveable.rememberSaveable(stateSaver = PeriodSaver) { mutableStateOf(TxTarget.period) }
    LaunchedEffect(Unit) {
        TxTarget.account?.let { onSelectAccount(it) }
        TxTarget.category = null; TxTarget.period = null; TxTarget.account = null
    }
    var filterOpen by remember { mutableStateOf(false) }
    val periods = com.wimg.app.ui.components.rememberPeriods()

    LaunchedEffect(selectedAccount, Changes.version) {
        com.wimg.app.ui.components.ScreenCache.get<TxData>(txKey(selectedAccount))?.let { data = it }
        data = withContext(Dispatchers.IO) { loadTx(selectedAccount) }.also { com.wimg.app.ui.components.ScreenCache.put(txKey(selectedAccount), it) }
    }

    val all = data?.transactions ?: emptyList()
    fun matches(tx: Transaction): Boolean {
        val type = when (filter) {
            TxFilter.ALL -> true
            TxFilter.EXPENSES -> tx.isExpense
            TxFilter.INCOME -> tx.isIncome
            TxFilter.MANUAL -> tx.manual
        }
        return type && (categories.isEmpty() || tx.category in categories) &&
            (period == null || tx.date in period!!.from..period!!.to)
    }
    val filterActive = filter != TxFilter.ALL || categories.isNotEmpty() || period != null
    val pending = remember(data, filter, categories, period) { data?.pending.orEmpty().filter { matches(it) } }
    // Filtering, grouping and the running sums of 3,000+ rows ran on the main
    // thread every time the page opened (measured: the biggest part of opening
    // Umsätze). Unfiltered they come ready-made with the data; filtered they're
    // built in the background.
    // Opened already filtered (a category tapped on Übersicht, or back to a
    // filtered list): build that view before the first frame. Without it the
    // big sum started empty and rolled to its value, changing width as it went.
    val firstView = remember { data?.let { d -> if (filterActive) TxView.of(d.transactions.filter { matches(it) }) else d.view } }
    val view by produceState(firstView, data, filter, categories, period) {
        val d = data ?: return@produceState
        value = if (!filterActive) d.view else withContext(Dispatchers.Default) { TxView.of(d.transactions.filter { matches(it) }) }
    }
    val filtered = view?.list ?: emptyList()

    // The bank's closing balance, only when every shown account has one (FinTS).
    val allAccounts = data?.accounts ?: emptyList()
    val accounts = allAccounts.filter { if (selectedAccount == null) !it.isHidden else it.id == selectedAccount }
    val balance = balanceOf(accounts)
    val balanceDate = accounts.mapNotNull { it.balance_date.takeIf { d -> d.isNotEmpty() } }.maxOrNull()
    val anchored = balance != null && !filterActive

    val accountName = if (selectedAccount != null && allAccounts.size > 1) allAccounts.firstOrNull { it.id == selectedAccount }?.name else null
    val tags = filterTags(filter, categories, period, accountName)

    val listState = rememberLazyListState()
    // Running value at the topmost visible row: with a bank balance it is the
    // balance after that row (walking back through history); without one, the
    // sum of that row and everything older. Never called "Kontostand" then.
    // Computed once per list, not on every scroll frame: position of each id,
    // and before[i] = sum of rows 0 until i.
    val running by remember(view, anchored, balance, filterActive) {
        derivedStateOf {
            val v = view ?: return@derivedStateOf 0.0
            val top = listState.layoutInfo.visibleItemsInfo.firstNotNullOfOrNull { (it.key as? String)?.let(v.indexOf::get) } ?: 0
            // Filtered: the total of every match, standing still while scrolling
            // (board 36/11); it changes, and rolls once, only with the data.
            when {
                anchored -> balance!! - v.before[top]
                filterActive -> v.before[v.list.size]
                else -> v.before[v.list.size] - v.before[top]
            }
        }
    }
    val compact by remember { derivedStateOf { listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 48 } }

    BarContribution(
        chip = BarChipSpec(label = if (tags.isEmpty()) "" else "${tags.size}", active = filterOpen || filterActive, onClick = { filterOpen = !filterOpen }, icon = Icons.Outlined.Tune, contentDescription = L("Filter")),
        panel = if (filterOpen) {
            {
                FilterPanel(
                    filter = filter, onFilter = { filter = it },
                    categories = categories, onCategories = { categories = it },
                    period = period, onPeriod = { period = it },
                    resultCount = filtered.size,
                    categoryTotals = {
                        // Every filter but the category one, summed per category.
                        val d = data
                        if (d == null) emptyList() else d.transactions.asSequence()
                            .filter { tx ->
                                (when (filter) { TxFilter.ALL -> true; TxFilter.EXPENSES -> tx.isExpense; TxFilter.INCOME -> tx.isIncome; TxFilter.MANUAL -> tx.manual }) &&
                                    (period == null || tx.date in period!!.from..period!!.to) && !tx.isExcluded
                            }
                            .groupBy { it.category }.map { (k, v) -> k to v.sumOf { it.amount } }
                    },
                    accountLabel = if (allAccounts.size > 1) (allAccounts.firstOrNull { it.id == selectedAccount }?.name ?: L("Alle Konten")) else null,
                    selectedAccount = selectedAccount, onAccount = onSelectAccount,
                    periods = periods,
                    onReset = { filter = TxFilter.ALL; categories = emptySet(); period = null },
                    onDone = { filterOpen = false },
                )
            }
        } else null,
        onPanelDismiss = { filterOpen = false },
    )

    val c = Wimg.colors
    val title = when {
        anchored && allAccounts.size > 1 -> L("Kontostand · %s", accounts.singleOrNull()?.takeIf { selectedAccount != null }?.name ?: L("alle Konten"))
        anchored -> L("Kontostand")
        period?.key?.endsWith(":salary") == true && filter == TxFilter.ALL && categories.isEmpty() ->
            L("Seit dem Gehalt am %s", com.wimg.app.ui.components.PeriodLabels.dotted(period!!.from))
        filterActive -> L("Summe der Treffer")
        else -> L("Summe der Umsätze")
    }
    BandScreen(
        band = {
            Column(Modifier.animateContentSize(WimgMotion.barCompact())) {
                if (compact) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(title, style = WimgType.bandOver, color = c.bandSub, modifier = Modifier.weight(1f))
                        val small = WimgType.amountLarge.copy(fontSize = WimgType.amountLarge.fontSize * 0.9f)
                        com.wimg.app.ui.components.RollingAmount(running, small, small, Color.White, Changes.version, showPlus = !anchored, rollAlways = true)
                    }
                } else {
                    Text(title, style = WimgType.bandOver, color = c.bandSub)
                    com.wimg.app.ui.components.RollingAmount(running, WimgType.amountHero, WimgType.amountHeroCents, Color.White, Changes.version, Modifier.padding(top = 2.dp), showPlus = !anchored, rollAlways = true)
                    val parts = buildList {
                        if (anchored) {
                            accounts.singleOrNull()?.let { add(it.bank.ifBlank { it.name }) }
                            balanceDate?.let { add(L("Stand %s", WimgDates.short(it))) }
                        }
                        add(if (filtered.size == 1) L("1 Umsatz") else L("%d Umsätze", filtered.size))
                    }
                    // What's filtered, in the same quiet line as the count (the
                    // tag pills of board 36/07 looked heavy on the phone).
                    val line = parts + (if (filterActive) tags else emptyList())
                    Text(line.joinToString(" · "), style = WimgType.desc, color = c.bandSub, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
                }
            }
        },
    ) {
        if (data != null && view != null && filtered.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(if (all.isEmpty()) L("Noch keine Umsätze") else L("Keine Treffer"), style = WimgType.section, color = c.text)
                Text(
                    if (all.isEmpty()) L("Verbinde deine Bank oder importiere eine CSV.") else L("Ändere den Filter, um mehr zu sehen."),
                    style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 6.dp),
                )
            }
            return@BandScreen
        }
        val grouped = view?.grouped ?: emptyList()
        LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = barClearance())) {
            if (pending.isNotEmpty()) {
                item(key = "h_pending") { PendingHeader(pending.size, pending.sumOf { it.amount }) }
                items(pending, key = { "p_" + it.id }) { tx ->
                    TxRow(tx, last = tx == pending.last(), pending = true) { navController?.navigate("tx/${tx.id}") }
                }
            }
            grouped.forEachIndexed { gi, (date, txs) ->
                item(key = "h_$date") { DayHeader(date, txs.sumOf { it.amount }, first = gi == 0 && pending.isEmpty()) }
                items(txs, key = { it.id }) { tx ->
                    TxRow(tx, last = tx == txs.last()) { navController?.navigate("tx/${tx.id}") }
                }
            }
        }
    }
}

@Composable
private fun DayHeader(date: String, total: Double, first: Boolean) {
    val c = Wimg.colors
    Row(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = if (first) 18.dp else 26.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(WimgDates.dayHeader(date), style = WimgType.chip, color = c.text2, modifier = Modifier.weight(1f))
        Text(amountText(total), style = WimgType.chip, color = if (total > 0.004) c.pos else c.text2)
    }
}

/** "Vorgemerkt": what the bank has seen but not booked yet. */
@Composable
private fun PendingHeader(count: Int, total: Double) {
    val c = Wimg.colors
    Row(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(L("Vorgemerkt · %d", count), style = WimgType.chip, color = c.text2, modifier = Modifier.weight(1f))
        Text(amountText(total), style = WimgType.chip, color = c.text3)
    }
}

@Composable
private fun TxRow(tx: Transaction, last: Boolean, pending: Boolean = false, onClick: () -> Unit) {
    val c = Wimg.colors
    val wc = WimgCategory.fromId(tx.category)
    Column(Modifier.clickable(onClick = onClick)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 20.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    tx.displayTitle,
                    style = WimgType.rowTitle,
                    color = if (tx.isExcluded) c.text3 else c.text,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 3.dp)) {
                    Box(Modifier.size(7.dp).clip(CircleShape).background(c.categoryBar(tx.category)))
                    Spacer(Modifier.width(7.dp))
                    val sub = buildList {
                        add(L(wc.label))
                        tx.kind?.takeIf { it.isNotBlank() }?.let { add(L(it)) }
                        if (tx.isExcluded) add(L("ausgeschlossen"))
                        if (pending) add(L("vorgemerkt"))
                    }.joinToString(" · ")
                    Text(sub, style = WimgType.desc, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Spacer(Modifier.width(12.dp))
            Amount(
                tx.amount, WimgType.amountRow.copy(fontSize = WimgType.amountRow.fontSize * 1.12f), WimgType.amountRowCents,
                color = when { tx.isExcluded || pending -> c.text3; tx.amount > 0 -> c.pos; else -> c.text },
            )
        }
        if (!last) HorizontalDivider(thickness = 1.dp, color = c.line)
    }
}


// ---------------------------------------------------------------------------
// Filter panel, option A of brief 19 (boards 36/02–04, 07–09): four rows with
// their current value; a row opens a short list in the same panel.
// ---------------------------------------------------------------------------

private enum class FilterPage { MAIN, TYPE, ACCOUNT, PERIOD, CATEGORY }

/** What the closed panel shows as tags under the sum, and counts on the button. */
internal fun filterTags(filter: TxFilter, categories: Set<Int>, period: TxPeriod?, accountName: String?): List<String> = buildList {
    if (filter != TxFilter.ALL) add(__t(filter.label))
    accountName?.let { add(it) }
    when (categories.size) {
        0 -> {}
        1 -> add(__t(WimgCategory.fromId(categories.first()).label))
        else -> add(__t("%d Kategorien").format(categories.size))
    }
    period?.let { add(periodTag(it)) }
}

/** "seit 27.10." for the running Gehaltsmonat, the label otherwise. */
private fun periodTag(p: TxPeriod) =
    if (p.key.endsWith(":salary")) __t("seit %s").format(com.wimg.app.ui.components.PeriodLabels.dotted(p.from)) else p.label

@Composable
private fun FilterPanel(
    filter: TxFilter,
    onFilter: (TxFilter) -> Unit,
    categories: Set<Int>,
    onCategories: (Set<Int>) -> Unit,
    period: TxPeriod?,
    onPeriod: (TxPeriod?) -> Unit,
    resultCount: Int,
    /** Category → sum of the rows that pass every filter but the category one. */
    categoryTotals: () -> List<Pair<Int, Double>>,
    onReset: () -> Unit,
    onDone: () -> Unit,
    accountLabel: String? = null,
    selectedAccount: String? = null,
    onAccount: (String?) -> Unit = {},
    periods: com.wimg.app.models.Periods? = null,
) {
    val c = Wimg.colors
    var page by remember { mutableStateOf(FilterPage.MAIN) }
    var pickingMonth by remember { mutableStateOf(false) }
    val now = remember { Calendar.getInstance() }
    if (page == FilterPage.ACCOUNT) {
        AccountsPanel(selectedAccount, onPick = onAccount, onDone = { page = FilterPage.MAIN })
        return
    }
    if (pickingMonth) {
        val shortMonths = remember { java.text.DateFormatSymbols(if (com.wimg.app.ui.theme.LocaleState.locale == "en") java.util.Locale.ENGLISH else java.util.Locale.GERMAN).shortMonths.map { it.trimEnd('.') } }
        val (py, pm) = period?.key?.removePrefix("m:")?.split("-")?.mapNotNull { it.toIntOrNull() }?.takeIf { it.size == 2 }?.let { it[0] to it[1] }
            ?: (now.get(Calendar.YEAR) to now.get(Calendar.MONTH) + 1)
        MonthPickerPanel(py, pm, shortMonths, now, onPick = { y, m -> onPeriod(monthPeriod(y, m)); pickingMonth = false; page = FilterPage.MAIN })
        return
    }
    BarPanel {
        when (page) {
            FilterPage.MAIN -> {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 4.dp, bottom = 6.dp)) {
                    Text(L("Filter"), style = WimgType.sheetTitle.copy(fontSize = WimgType.sheetTitle.fontSize * 0.86f), color = c.text, modifier = Modifier.weight(1f))
                    Text(L("Zurücksetzen"), style = WimgType.chip, color = c.accent, modifier = Modifier.pressable(onClick = onReset).clip(WimgShape.button).padding(8.dp))
                }
                FilterRow(Icons.Outlined.SwapVert, L("Art"), L(filter.label), filter != TxFilter.ALL) { page = FilterPage.TYPE }
                if (accountLabel != null) {
                    HorizontalDivider(thickness = 1.dp, color = c.line)
                    FilterRow(Icons.Outlined.AccountBalanceWallet, L("Konto"), accountLabel, selectedAccount != null) { page = FilterPage.ACCOUNT }
                }
                HorizontalDivider(thickness = 1.dp, color = c.line)
                FilterRow(Icons.Outlined.CalendarToday, L("Zeitraum"), period?.let { periodTag(it) } ?: L("Gesamt"), period != null) { page = FilterPage.PERIOD }
                HorizontalDivider(thickness = 1.dp, color = c.line)
                val catValue = when (categories.size) {
                    0 -> L("Alle")
                    1 -> L(WimgCategory.fromId(categories.first()).label)
                    else -> L("%d Kategorien", categories.size)
                }
                FilterRow(Icons.Outlined.LocalOffer, L("Kategorie"), catValue, categories.isNotEmpty()) { page = FilterPage.CATEGORY }
            }
            FilterPage.TYPE -> {
                SubHeader(L("Art")) { page = FilterPage.MAIN }
                TxFilter.entries.forEach { f ->
                    ChoiceRow(L(f.label), null, f == filter) { onFilter(f); page = FilterPage.MAIN }
                }
            }
            FilterPage.PERIOD -> {
                SubHeader(L("Zeitraum")) { page = FilterPage.MAIN }
                PeriodList(period, periods, now, onPick = { onPeriod(it); page = FilterPage.MAIN }, onPickMonth = { pickingMonth = true })
            }
            FilterPage.CATEGORY -> {
                SubHeader(L("Kategorie")) { page = FilterPage.MAIN }
                Text(L("Nur was in diesem Zeitraum vorkommt, nach Ausgaben sortiert"), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(start = 4.dp, bottom = 6.dp))
                CategoryList(remember(filter, period, selectedAccount) { categoryTotals() }, categories, onCategories)
            }
            FilterPage.ACCOUNT -> {}
        }
        Box(
            Modifier.padding(top = 14.dp).fillMaxWidth().height(50.dp).pressable(onClick = onDone).clip(CircleShape).background(c.ink),
            contentAlignment = Alignment.Center,
        ) {
            Text(if (resultCount == 1) L("1 Umsatz anzeigen") else L("%d Umsätze anzeigen", resultCount), style = WimgType.button, color = c.inkText)
        }
    }
}

/** Art · Konto · Zeitraum · Kategorie: the value sits on a light accent when it isn't "all". */
@Composable
private fun FilterRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, value: String, set: Boolean, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 60.dp).clip(WimgShape.button).clickable(onClick = onClick).padding(horizontal = 4.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(36.dp).clip(WimgShape.iconTile).background(c.neutralTint), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = c.text2, modifier = Modifier.size(19.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(title, style = WimgType.rowTitle, color = c.text, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(10.dp))
        Text(
            value, style = if (set) WimgType.chip else WimgType.body, color = if (set) c.text else c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.widthIn(max = 180.dp).then(if (set) Modifier.clip(RoundedCornerShape(10.dp)).background(c.accentSoft).padding(horizontal = 10.dp, vertical = 4.dp) else Modifier),
        )
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = c.text3, modifier = Modifier.padding(start = 4.dp).size(20.dp))
    }
}

@Composable
private fun SubHeader(title: String, onBack: () -> Unit) {
    val c = Wimg.colors
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 6.dp)) {
        Icon(
            Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = L("Zurück"), tint = c.text,
            modifier = Modifier.size(36.dp).clip(CircleShape).pressable(onClick = onBack).padding(7.dp),
        )
        Spacer(Modifier.width(6.dp))
        Text(title, style = WimgType.sheetTitle.copy(fontSize = WimgType.sheetTitle.fontSize * 0.86f), color = c.text)
    }
}

/** A row in a sub-list: the chosen one on a soft background with a check. */
@Composable
private fun ChoiceRow(title: String, detail: String?, on: Boolean, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 50.dp).clip(RoundedCornerShape(14.dp)).background(if (on) c.neutralTint else Color.Transparent)
            .clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = if (on) WimgType.rowTitle.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) else WimgType.rowTitle, color = c.text, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        detail?.let { Text(it, style = WimgType.body, color = c.text2, maxLines = 1, modifier = Modifier.padding(start = 10.dp)) }
        if (on) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.accent, modifier = Modifier.padding(start = 10.dp).size(20.dp))
    }
}

/** Zeitraum stacked: Gesamt, the current and recent periods, then older ones or a calendar month. */
@Composable
private fun PeriodList(period: TxPeriod?, periods: com.wimg.app.models.Periods?, now: Calendar, onPick: (TxPeriod?) -> Unit, onPickMonth: () -> Unit) {
    val c = Wimg.colors
    var more by remember { mutableStateOf(false) }
    fun same(a: TxPeriod?, b: TxPeriod?) = a?.from == b?.from && a?.to == b?.to
    Column(Modifier.heightIn(max = 400.dp).verticalScroll(rememberScrollState())) {
        ChoiceRow(L("Gesamt"), L("alle Umsätze"), period == null) { onPick(null) }
        val rows = mutableListOf<Triple<String, String?, TxPeriod>>()
        if (periods != null && !periods.isCalendar) {
            periods.periods.forEachIndexed { i, p ->
                val tp = txPeriodOf(p, periods.isSalary)
                val range = if (p.current && periods.isSalary) __t("seit %s").format(com.wimg.app.ui.components.PeriodLabels.dotted(p.from)) else com.wimg.app.ui.components.PeriodLabels.short(p)
                when (i) {
                    0 -> rows += Triple(if (periods.isSalary) L("Aktueller Gehaltsmonat") else L("Aktueller Zeitraum"), range, tp)
                    1 -> rows += Triple(if (periods.isSalary) L("Letzter Gehaltsmonat") else L("Letzter Zeitraum"), range, tp)
                    else -> rows += Triple(range, null, tp)
                }
            }
        } else {
            val thisMonth = monthPeriod(now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1)
            val lastMonth = (now.clone() as Calendar).apply { add(Calendar.MONTH, -1) }.let { monthPeriod(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1) }
            rows += Triple(L("Dieser Monat"), thisMonth.label, thisMonth.copy(label = L("Dieser Monat"), key = "this"))
            rows += Triple(L("Letzter Monat"), lastMonth.label, lastMonth.copy(label = L("Letzter Monat"), key = "last"))
            rows += Triple(L("3 Monate"), null, lastDays(91, L("3 Monate"), "3m"))
            rows += Triple(L("12 Monate"), null, lastDays(365, L("12 Monate"), "12m"))
        }
        val shown = if (more) rows else rows.take(4)
        // A month picked earlier (from Home or the picker) stays visible as a choice.
        val custom = period?.takeIf { p -> rows.none { same(it.third, p) } }
        custom?.let { ChoiceRow(it.label, null, true) { onPick(it) } }
        shown.forEach { (title, detail, tp) -> ChoiceRow(title, detail, same(tp, period)) { onPick(tp) } }
        if (!more && rows.size > 4) {
            Text(
                L("Ältere und eigener Zeitraum …"), style = WimgType.rowTitle, color = c.accent,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable { more = true }.padding(horizontal = 14.dp, vertical = 12.dp),
            )
        } else {
            Text(
                L("Kalendermonat wählen …"), style = WimgType.rowTitle, color = c.accent,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onPickMonth).padding(horizontal = 14.dp, vertical = 12.dp),
            )
        }
    }
}

/** Kategorie: only what occurs, by spending, with the amount; the rest behind "Mehr (n)". */
@Composable
private fun CategoryList(totals: List<Pair<Int, Double>>, selected: Set<Int>, onChange: (Set<Int>) -> Unit) {
    val c = Wimg.colors
    // Spending first, biggest on top; income after (it would always lead otherwise).
    val sorted = remember(totals) { totals.filter { it.second < 0 }.sortedBy { it.second } + totals.filter { it.second >= 0 }.sortedByDescending { it.second } }
    val spent = totals.filter { it.second < 0 }.sumOf { it.second }
    val allTotal = kotlin.math.abs(if (spent != 0.0) spent else totals.sumOf { it.second })
    var more by remember { mutableStateOf(sorted.drop(5).any { it.first in selected }) }
    Column(Modifier.heightIn(max = 400.dp).verticalScroll(rememberScrollState())) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 50.dp).clip(RoundedCornerShape(14.dp)).background(if (selected.isEmpty()) c.neutralTint else Color.Transparent)
                .clickable { onChange(emptySet()) }.padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(L("Alle Kategorien"), style = WimgType.rowTitle, color = c.text, modifier = Modifier.weight(1f))
            Text(amountText(allTotal, showPlus = false), style = WimgType.body, color = c.text2)
        }
        (if (more) sorted else sorted.take(5)).forEach { (id, sum) ->
            val on = id in selected
            Row(
                Modifier.fillMaxWidth().heightIn(min = 50.dp).clip(RoundedCornerShape(14.dp)).background(if (on) c.neutralTint else Color.Transparent)
                    .clickable { onChange(if (on) selected - id else selected + id) }.padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(if (on) c.accent else Color.Transparent)
                        .border(1.5.dp, if (on) c.accent else c.text3, RoundedCornerShape(6.dp)),
                    contentAlignment = Alignment.Center,
                ) { if (on) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.onAccent, modifier = Modifier.size(16.dp)) }
                Spacer(Modifier.width(14.dp))
                Box(Modifier.size(8.dp).clip(CircleShape).background(c.categoryBar(id)))
                Spacer(Modifier.width(10.dp))
                Text(L(WimgCategory.fromId(id).label), style = if (on) WimgType.rowTitle.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) else WimgType.rowTitle, color = c.text, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(amountText(kotlin.math.abs(sum), showPlus = false), style = WimgType.body, color = c.text2)
            }
        }
        if (!more && sorted.size > 5) {
            Text(
                L("Mehr (%d)", sorted.size - 5), style = WimgType.rowTitle, color = c.accent,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable { more = true }.padding(horizontal = 14.dp, vertical = 12.dp),
            )
        }
    }
}
