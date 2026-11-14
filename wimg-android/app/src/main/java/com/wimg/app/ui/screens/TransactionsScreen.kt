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
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
)

internal fun txKey(account: String?) = "tx:$account"

internal fun loadTx(account: String?) = TxData(
    transactions = LibWimg.getTransactionsFiltered(account).sortedByDescending { it.date },
    // All accounts are needed for the Konto row; the band sums the shown ones.
    accounts = LibWimg.getAccounts(),
    pending = LibWimg.getPending(account).sortedByDescending { it.date },
)

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
        }
        return type && (categories.isEmpty() || tx.category in categories) &&
            (period == null || tx.date in period!!.from..period!!.to)
    }
    val pending = remember(data, filter, categories, period) { data?.pending.orEmpty().filter { matches(it) } }
    val filtered = remember(all, filter, categories, period) { all.filter { matches(it) } }
    val filterActive = filter != TxFilter.ALL || categories.isNotEmpty() || period != null

    // The bank's closing balance, only when every shown account has one (FinTS).
    val allAccounts = data?.accounts ?: emptyList()
    val accounts = allAccounts.filter { if (selectedAccount == null) !it.isHidden else it.id == selectedAccount }
    val balance = balanceOf(accounts)
    val balanceDate = accounts.mapNotNull { it.balance_date.takeIf { d -> d.isNotEmpty() } }.maxOrNull()
    val anchored = balance != null && !filterActive

    val listState = rememberLazyListState()
    // Running value at the topmost visible row: with a bank balance it is the
    // balance after that row (walking back through history); without one, the
    // sum of that row and everything older. Never called "Kontostand" then.
    val running by remember(filtered, anchored, balance) {
        derivedStateOf {
            val visible = listState.layoutInfo.visibleItemsInfo.mapNotNull { it.key as? String }.toSet()
            val top = filtered.indexOfFirst { it.id in visible }.coerceAtLeast(0)
            if (anchored) balance!! - filtered.take(top).sumOf { it.amount }
            else filtered.drop(top).sumOf { it.amount }
        }
    }
    val compact by remember { derivedStateOf { listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 48 } }

    BarContribution(
        chip = BarChipSpec(label = "", active = filterOpen || filterActive, onClick = { filterOpen = !filterOpen }, icon = Icons.Outlined.Tune, contentDescription = L("Filter")),
        panel = if (filterOpen) {
            {
                FilterPanel(
                    filter = filter, onFilter = { filter = it },
                    categories = categories, onCategories = { categories = it },
                    period = period, onPeriod = { period = it },
                    resultCount = filtered.size,
                    accountLabel = if (allAccounts.size > 1) (allAccounts.firstOrNull { it.id == selectedAccount }?.name ?: L("Alle Konten")) else null,
                    selectedAccount = selectedAccount, onAccount = onSelectAccount,
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
        filterActive -> L("Summe der Treffer")
        else -> L("Summe der Umsätze")
    }
    BandScreen(
        band = {
            Column(Modifier.animateContentSize(WimgMotion.barCompact())) {
                if (compact) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(title, style = WimgType.bandOver, color = c.bandSub, modifier = Modifier.weight(1f))
                        Text(amountText(running, showPlus = !anchored), style = WimgType.amountLarge.copy(fontSize = WimgType.amountLarge.fontSize * 0.9f), color = Color.White)
                    }
                } else {
                    Text(title, style = WimgType.bandOver, color = c.bandSub)
                    com.wimg.app.ui.components.RollingAmount(running, WimgType.amountHero, WimgType.amountHeroCents, Color.White, Changes.version, Modifier.padding(top = 2.dp), showPlus = !anchored)
                    val parts = buildList {
                        if (anchored) {
                            accounts.singleOrNull()?.let { add(it.bank.ifBlank { it.name }) }
                            balanceDate?.let { add(L("Stand %s", WimgDates.short(it))) }
                        }
                        add(L("%d Umsätze", filtered.size))
                    }
                    Text(parts.joinToString(" · "), style = WimgType.desc, color = c.bandSub, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
                }
            }
        },
    ) {
        if (data != null && filtered.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(if (all.isEmpty()) L("Noch keine Umsätze") else L("Keine Treffer"), style = WimgType.section, color = c.text)
                Text(
                    if (all.isEmpty()) L("Verbinde deine Bank oder importiere eine CSV.") else L("Ändere den Filter, um mehr zu sehen."),
                    style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 6.dp),
                )
            }
            return@BandScreen
        }
        val grouped = remember(filtered) { filtered.groupBy { it.date }.toList() }
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

@Composable
private fun PeriodChip(label: String, on: Boolean, onClick: () -> Unit) {
    val c = Wimg.colors
    Box(
        Modifier.height(38.dp).clip(CircleShape).background(if (on) c.ink else Color.Transparent)
            .border(1.dp, if (on) c.ink else c.line, CircleShape).clickable(onClick = onClick).padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) { Text(label, style = WimgType.rowTitle.copy(fontSize = WimgType.rowTitle.fontSize * 0.95f), color = if (on) c.inkText else c.text) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilterPanel(
    filter: TxFilter,
    onFilter: (TxFilter) -> Unit,
    categories: Set<Int>,
    onCategories: (Set<Int>) -> Unit,
    period: TxPeriod?,
    onPeriod: (TxPeriod?) -> Unit,
    resultCount: Int,
    onReset: () -> Unit,
    onDone: () -> Unit,
    accountLabel: String? = null,
    selectedAccount: String? = null,
    onAccount: (String?) -> Unit = {},
) {
    val c = Wimg.colors
    var picking by remember { mutableStateOf(false) }
    var pickingAccount by remember { mutableStateOf(false) }
    if (pickingAccount) {
        AccountsPanel(selectedAccount, onPick = onAccount, onDone = { pickingAccount = false })
        return
    }
    val now = remember { Calendar.getInstance() }
    if (picking) {
        // The same month grid as Home's period chip, in place of the filter panel.
        val shortMonths = remember { java.text.DateFormatSymbols(if (com.wimg.app.ui.theme.LocaleState.locale == "en") java.util.Locale.ENGLISH else java.util.Locale.GERMAN).shortMonths.map { it.trimEnd('.') } }
        val (py, pm) = period?.key?.removePrefix("m:")?.split("-")?.mapNotNull { it.toIntOrNull() }?.takeIf { it.size == 2 }?.let { it[0] to it[1] }
            ?: (now.get(Calendar.YEAR) to now.get(Calendar.MONTH) + 1)
        MonthPickerPanel(py, pm, shortMonths, now, onPick = { y, m -> onPeriod(monthPeriod(y, m)); picking = false })
        return
    }
    BarPanel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L("Filter"), style = WimgType.sheetTitle.copy(fontSize = WimgType.sheetTitle.fontSize * 0.86f), color = c.text, modifier = Modifier.weight(1f))
            Text(L("Zurücksetzen"), style = WimgType.chip, color = c.text2, modifier = Modifier.pressable(onClick = onReset).clip(WimgShape.button).padding(8.dp))
        }
        // Segmented control: Alle / Ausgaben / Einnahmen
        Row(
            Modifier.padding(top = 14.dp).fillMaxWidth().clip(WimgShape.segmentOuter).background(c.neutralTint).padding(4.dp),
        ) {
            TxFilter.entries.forEach { f ->
                val on = f == filter
                Box(
                    Modifier
                        .weight(1f)
                        .height(38.dp)
                        .clip(WimgShape.segmentInner)
                        .background(if (on) c.card else Color.Transparent)
                        .clickable { onFilter(f) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(L(f.label), style = WimgType.chip, color = if (on) c.text else c.text2)
                }
            }
        }
        if (accountLabel != null) {
            Text(L("Konto"), style = WimgType.label, color = c.text2, modifier = Modifier.padding(top = 18.dp, bottom = 8.dp))
            PeriodChip(accountLabel + "  ›", selectedAccount != null) { pickingAccount = true }
        }
        Text(L("Zeitraum"), style = WimgType.label, color = c.text2, modifier = Modifier.padding(top = 18.dp, bottom = 8.dp))
        run {
            val thisMonth = monthPeriod(now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1).copy(label = L("Dieser Monat"), key = "this")
            val lastMonth = (now.clone() as Calendar).apply { add(Calendar.MONTH, -1) }.let { monthPeriod(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1) }.copy(label = L("Letzter Monat"), key = "last")
            val options = listOf<TxPeriod?>(null, thisMonth, lastMonth, lastDays(91, L("3 Monate"), "3m"), lastDays(365, L("12 Monate"), "12m"))
            // One scrollable line: the panel stays as tall as before the period filter.
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                options.forEach { o ->
                    PeriodChip(o?.label ?: L("Immer"), period?.key == o?.key) { onPeriod(o) }
                }
                // A specific month (from Home, or picked) shows as its own chip.
                val custom = period?.takeIf { it.key.startsWith("m:") }
                PeriodChip(custom?.label ?: L("Monat wählen…"), custom != null) { picking = true }
            }
        }
        Text(L("Kategorien"), style = WimgType.label, color = c.text2, modifier = Modifier.padding(top = 18.dp, bottom = 8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FILTER_CATEGORIES.forEach { cat ->
                val on = cat.id in categories
                Row(
                    Modifier
                        .height(38.dp)
                        .clip(CircleShape)
                        .background(if (on) c.ink else Color.Transparent)
                        .border(1.dp, if (on) c.ink else c.line, CircleShape)
                        .clickable { onCategories(if (on) categories - cat.id else categories + cat.id) }
                        .padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(c.categoryBar(cat.id)))
                    Spacer(Modifier.width(8.dp))
                    Text(L(cat.label), style = WimgType.rowTitle.copy(fontSize = WimgType.rowTitle.fontSize * 0.95f), color = if (on) c.inkText else c.text)
                }
            }
        }
        Box(
            Modifier
                .padding(top = 18.dp)
                .fillMaxWidth()
                .height(50.dp)
                .pressable(onClick = onDone)
                .clip(CircleShape)
                .background(c.ink),
            contentAlignment = Alignment.Center,
        ) {
            Text(L("%d Umsätze anzeigen", resultCount), style = WimgType.button, color = c.inkText)
        }
    }
}
