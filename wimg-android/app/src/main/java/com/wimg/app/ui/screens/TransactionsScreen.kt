package com.wimg.app.ui.screens

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

internal data class TxData(val transactions: List<Transaction>, val accounts: List<Account>)

internal fun txKey(account: String?) = "tx:$account"

internal fun loadTx(account: String?) = TxData(
    transactions = LibWimg.getTransactionsFiltered(account).sortedByDescending { it.date },
    accounts = LibWimg.getAccounts().filter { account == null || it.id == account },
)

@Composable
fun TransactionsScreen(selectedAccount: String?, navController: NavController? = null) {
    var data by remember { mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<TxData>(txKey(selectedAccount))) }
    var filter by remember { mutableStateOf(TxFilter.ALL) }
    var categories by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var filterOpen by remember { mutableStateOf(false) }

    LaunchedEffect(selectedAccount, Changes.version) {
        com.wimg.app.ui.components.ScreenCache.get<TxData>(txKey(selectedAccount))?.let { data = it }
        data = withContext(Dispatchers.IO) { loadTx(selectedAccount) }.also { com.wimg.app.ui.components.ScreenCache.put(txKey(selectedAccount), it) }
    }

    val all = data?.transactions ?: emptyList()
    val filtered = remember(all, filter, categories) {
        all.filter { tx ->
            val type = when (filter) {
                TxFilter.ALL -> true
                TxFilter.EXPENSES -> tx.isExpense
                TxFilter.INCOME -> tx.isIncome
            }
            type && (categories.isEmpty() || tx.category in categories)
        }
    }
    val filterActive = filter != TxFilter.ALL || categories.isNotEmpty()

    // The bank's closing balance, only when every shown account has one (FinTS).
    val accounts = data?.accounts ?: emptyList()
    val knownBalance = accounts.isNotEmpty() && accounts.all { it.balance != null }
    val balance = if (knownBalance) accounts.sumOf { it.balance_cents } / 100.0 else null
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
                    resultCount = filtered.size,
                    onReset = { filter = TxFilter.ALL; categories = emptySet() },
                    onDone = { filterOpen = false },
                )
            }
        } else null,
        onPanelDismiss = { filterOpen = false },
    )

    val c = Wimg.colors
    val title = when {
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
                    Amount(running, WimgType.amountHero, WimgType.amountHeroCents, Color.White, Modifier.padding(top = 2.dp), showPlus = !anchored)
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
        LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = BarClearance)) {
            grouped.forEachIndexed { gi, (date, txs) ->
                item(key = "h_$date") { DayHeader(date, txs.sumOf { it.amount }, first = gi == 0) }
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

@Composable
private fun TxRow(tx: Transaction, last: Boolean, onClick: () -> Unit) {
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
                    }.joinToString(" · ")
                    Text(sub, style = WimgType.desc, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Spacer(Modifier.width(12.dp))
            Amount(
                tx.amount, WimgType.amountRow.copy(fontSize = WimgType.amountRow.fontSize * 1.12f), WimgType.amountRowCents,
                color = when { tx.isExcluded -> c.text3; tx.amount > 0 -> c.pos; else -> c.text },
            )
        }
        if (!last) HorizontalDivider(thickness = 1.dp, color = c.line)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilterPanel(
    filter: TxFilter,
    onFilter: (TxFilter) -> Unit,
    categories: Set<Int>,
    onCategories: (Set<Int>) -> Unit,
    resultCount: Int,
    onReset: () -> Unit,
    onDone: () -> Unit,
) {
    val c = Wimg.colors
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
