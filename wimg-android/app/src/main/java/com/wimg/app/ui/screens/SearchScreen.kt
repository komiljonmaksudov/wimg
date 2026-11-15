package com.wimg.app.ui.screens

import android.content.Context
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Tune
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.models.Account
import com.wimg.app.models.Transaction
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.Amount
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarBack
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.amountText
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgDimens
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import com.wimg.app.ui.theme.categoryBar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.abs

/** Quick filters from the design; categories first, then the special ones. */
private sealed class Quick(val label: String, val color: ((com.wimg.app.ui.theme.WimgPalette) -> Color)?) {
    class Category(val cat: WimgCategory) : Quick(cat.label, { p -> p.categoryBar(cat.id) })
    data object Uncategorized : Quick("Unkategorisiert", null)
    data object IncomeOnly : Quick("Nur Einnahmen", null)
    data object Over100 : Quick("Über 100 €", null)
    data object Excluded : Quick("Ausgeschlossene", null)

    fun matches(tx: Transaction): Boolean = when (this) {
        is Category -> tx.category == cat.id
        Uncategorized -> tx.category == WimgCategory.UNCATEGORIZED.id
        IncomeOnly -> tx.amount > 0
        Over100 -> abs(tx.amount) >= 100.0
        Excluded -> tx.isExcluded
    }
}

private val QUICK = listOf(
    Quick.Category(WimgCategory.GROCERIES), Quick.Category(WimgCategory.UTILITIES),
    Quick.Category(WimgCategory.INSURANCE), Quick.Category(WimgCategory.SHOPPING),
    Quick.Uncategorized, Quick.IncomeOnly, Quick.Over100, Quick.Excluded,
)

private const val RECENT_KEY = "wimg_search_recent"

private fun loadRecent(ctx: Context): List<String> =
    ctx.getSharedPreferences("wimg", 0).getString(RECENT_KEY, "")!!.split('\n').filter { it.isNotBlank() }

private fun saveRecent(ctx: Context, q: String) {
    val list = (listOf(q.trim()) + loadRecent(ctx).filter { !it.equals(q.trim(), ignoreCase = true) }).take(5)
    ctx.getSharedPreferences("wimg", 0).edit().putString(RECENT_KEY, list.joinToString("\n")).apply()
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SearchScreen(selectedAccount: String?, navController: NavController, initialQuery: String = "") {
    val ctx = LocalContext.current
    // The preloaded Umsätze list first (no empty frame), the full list right after.
    var all by remember { mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<TxData>(txKey(selectedAccount))?.transactions.orEmpty()) }
    var accounts by remember { mutableStateOf<Map<String, Account>>(emptyMap()) }
    var query by remember { mutableStateOf(initialQuery) }
    var quick by remember { mutableStateOf<Quick?>(null) }
    var recent by remember { mutableStateOf(loadRecent(ctx)) }
    var filtersOpen by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current

    LaunchedEffect(selectedAccount, Changes.version) {
        val (t, a) = withContext(Dispatchers.IO) {
            // Search keeps hidden accounts ("Ihre Umsätze bleiben in der Suche").
            (if (selectedAccount == null) LibWimg.getTransactions() else LibWimg.getTransactionsFiltered(selectedAccount)).sortedByDescending { it.date } to LibWimg.getAccounts().associateBy { it.id }
        }
        all = t; accounts = a
    }
    LaunchedEffect(Unit) { if (initialQuery.isBlank()) runCatching { focus.requestFocus() } }

    val q = query.trim()
    val active = q.isNotEmpty() || quick != null
    val hits = remember(all, q, quick) {
        if (!active) emptyList() else all.filter { tx ->
            (q.isEmpty() || tx.description.contains(q, ignoreCase = true)) && (quick?.matches(tx) ?: true)
        }
    }
    val c = Wimg.colors

    Box(Modifier.fillMaxSize()) {
        BandScreen(
            band = {
                if (!active || hits.isEmpty()) {
                    Text(L("Suche"), style = WimgType.title.copy(fontSize = WimgType.title.fontSize * 1.25f), color = Color.White)
                } else {
                    val label = listOfNotNull(q.takeIf { it.isNotEmpty() }?.let { "„$it“" }, quick?.let { L(it.label) }).joinToString(" · ")
                    Text(
                        listOf(label, if (hits.size == 1) L("1 Treffer") else L("%d Treffer", hits.size), dateRange(hits)).joinToString(" · "),
                        style = WimgType.bandOver, color = c.bandSub, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                    val sum = hits.sumOf { it.amount }
                    Amount(sum, WimgType.amountHero, WimgType.amountHeroCents, if (sum > 0) c.bandPos else Color.White, Modifier.padding(top = 2.dp))
                    Text(L("Ø %s pro Umsatz", amountText(abs(sum) / hits.size, showPlus = false)), style = WimgType.desc, color = c.bandSub, modifier = Modifier.padding(top = 4.dp))
                }
            },
        ) {
            when {
                !active -> StartView(recent, all, onRecent = { query = it; keyboard?.hide() }, quick = quick, onQuick = { quick = it; keyboard?.hide() })
                hits.isEmpty() -> Column(Modifier.padding(start = 24.dp, end = 24.dp, top = 24.dp)) {
                    Text(
                        if (q.isNotEmpty()) L("Keine Treffer für „%s“", q) else L("Keine Treffer"),
                        style = WimgType.section.copy(fontSize = WimgType.section.fontSize * 1.15f), color = c.text,
                    )
                    Text(
                        L("Gesucht wird im Verwendungszweck aller Umsätze. Banken kürzen Namen oft ab, versuch einen Teil des Namens oder eine Kundennummer."),
                        style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 8.dp),
                    )
                }
                else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 140.dp)) {
                    item {
                        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 6.dp)) {
                            Text(L("Neueste zuerst"), style = WimgType.chip, color = c.text2, modifier = Modifier.weight(1f))
                            if (q.isNotEmpty()) Text(L("Treffer im Verwendungszweck"), style = WimgType.desc, color = c.text2)
                        }
                    }
                    items(hits, key = { it.id }) { tx ->
                        HitRow(tx, q, accounts[tx.account]?.let { it.bank.ifBlank { it.name } }) {
                            if (q.isNotEmpty()) { saveRecent(ctx, q); recent = loadRecent(ctx) }
                            navController.navigate("tx/${tx.id}")
                        }
                    }
                }
            }
        }

        // [←] [field] [filters] in the shared floating bar, which morphs into it.
        BarContribution(
            chip = null,
            panel = if (filtersOpen) {
                {
                    BarPanel {
                        Text(L("Schnell filtern"), style = WimgType.label, color = c.text2, modifier = Modifier.padding(bottom = 8.dp))
                        QuickChips(quick) { quick = it; filtersOpen = false }
                    }
                }
            } else null,
            onPanelDismiss = { filtersOpen = false },
            search = {
                BarBack { keyboard?.hide(); navController.popBackStack() }
                Row(
                    Modifier
                        .weight(1f)
                        .height(WimgDimens.touchTarget)
                        .clip(WimgShape.button)
                        .background(c.neutralTint)
                        .padding(start = 12.dp, end = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Outlined.Search, contentDescription = null, tint = c.text2, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Box(Modifier.weight(1f)) {
                        if (query.isEmpty()) Text(L("Umsätze durchsuchen"), style = WimgType.body, color = c.text2, maxLines = 1)
                        BasicTextField(
                            value = query,
                            onValueChange = { query = it },
                            singleLine = true,
                            textStyle = WimgType.body.copy(color = c.text),
                            cursorBrush = SolidColor(c.accent),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions(onSearch = {
                                if (q.isNotEmpty()) { saveRecent(ctx, q); recent = loadRecent(ctx) }
                                keyboard?.hide()
                            }),
                            modifier = Modifier.fillMaxWidth().focusRequester(focus),
                        )
                    }
                    if (query.isNotEmpty()) {
                        Box(
                            Modifier.size(36.dp).clip(CircleShape).clickable(onClickLabel = L("Leeren")) { query = ""; focus.requestFocus() },
                            contentAlignment = Alignment.Center,
                        ) { Icon(Icons.Outlined.Close, contentDescription = L("Leeren"), tint = c.text, modifier = Modifier.size(18.dp)) }
                    }
                }
                Box(
                    Modifier
                        .size(WimgDimens.touchTarget)
                        .clip(WimgShape.button)
                        .background(if (filtersOpen || quick != null) c.ink else Color.Transparent)
                        .clickable(onClickLabel = L("Schnell filtern")) { filtersOpen = !filtersOpen },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Outlined.Tune, contentDescription = L("Schnell filtern"),
                        tint = if (filtersOpen || quick != null) c.inkText else c.text, modifier = Modifier.size(21.dp),
                    )
                }
            },
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StartView(recent: List<String>, all: List<Transaction>, onRecent: (String) -> Unit, quick: Quick?, onQuick: (Quick?) -> Unit) {
    val c = Wimg.colors
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        if (recent.isNotEmpty()) {
            Text(L("Zuletzt gesucht"), style = WimgType.chip, color = c.text2, modifier = Modifier.padding(top = 22.dp, bottom = 4.dp))
            recent.forEach { r ->
                val n = all.count { it.description.contains(r, ignoreCase = true) }
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(WimgShape.dockAction).clickable { onRecent(r) },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Outlined.History, contentDescription = null, tint = c.text2, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(16.dp))
                    Text(r, style = WimgType.body.copy(fontSize = WimgType.body.fontSize * 1.07f), color = c.text, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(if (n == 1) L("1 Treffer") else L("%d Treffer", n), style = WimgType.desc, color = c.text2)
                }
            }
        }
        Text(L("Schnell filtern"), style = WimgType.chip, color = c.text2, modifier = Modifier.padding(top = 22.dp, bottom = 10.dp))
        QuickChips(quick, onQuick)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun QuickChips(selected: Quick?, onPick: (Quick?) -> Unit) {
    val c = Wimg.colors
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        QUICK.forEach { qk ->
            val on = selected == qk || (selected is Quick.Category && qk is Quick.Category && selected.cat == qk.cat)
            Row(
                Modifier
                    .height(40.dp)
                    .clip(CircleShape)
                    .background(if (on) c.ink else Color.Transparent)
                    .border(1.dp, if (on) c.ink else c.line, CircleShape)
                    .clickable { onPick(if (on) null else qk) }
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val dot = qk.color?.invoke(c)
                if (dot != null) Box(Modifier.size(9.dp).clip(CircleShape).background(dot))
                else Box(Modifier.size(9.dp).clip(CircleShape).border(1.5.dp, if (on) c.inkText else c.text2, CircleShape))
                Spacer(Modifier.width(8.dp))
                Text(L(qk.label), style = WimgType.rowTitle, color = if (on) c.inkText else c.text)
            }
        }
    }
}

@Composable
private fun HitRow(tx: Transaction, q: String, account: String?, onClick: () -> Unit) {
    val c = Wimg.colors
    Column(Modifier.clickable(onClick = onClick)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 20.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(highlight(snippet(tx, q), q, c.accentSoft), style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    listOfNotNull(WimgDates.full(tx.date), account, L(WimgCategory.fromId(tx.category).label)).joinToString(" · "),
                    style = WimgType.desc, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Amount(tx.amount, WimgType.amountRow.copy(fontSize = WimgType.amountRow.fontSize * 1.12f), WimgType.amountRowCents, if (tx.amount > 0) c.pos else c.text)
        }
        HorizontalDivider(thickness = 1.dp, color = c.line)
    }
}

/** The row title, or — when the match is deeper in the bank text — the part around it. */
private fun snippet(tx: Transaction, q: String): String {
    val title = tx.displayTitle
    if (q.isEmpty() || title.contains(q, ignoreCase = true)) return title
    val d = tx.description
    val i = d.indexOf(q, ignoreCase = true)
    if (i < 0) return title
    val start = (i - 14).coerceAtLeast(0)
    return (if (start > 0) "… " else "") + d.substring(start).trimStart()
}

private fun highlight(text: String, q: String, bg: Color): AnnotatedString = buildAnnotatedString {
    if (q.isEmpty()) { append(text); return@buildAnnotatedString }
    var from = 0
    while (true) {
        val i = text.indexOf(q, from, ignoreCase = true)
        if (i < 0) { append(text.substring(from)); break }
        append(text.substring(from, i))
        withStyle(SpanStyle(background = bg)) { append(text.substring(i, i + q.length)) }
        from = i + q.length
    }
}

/** "Feb. – Nov. 2026", or "Nov. 2025 – Feb. 2026" across years. */
private fun dateRange(hits: List<Transaction>): String {
    val first = hits.minOf { it.date }
    val last = hits.maxOf { it.date }
    val m = WimgDates.shortMonths()
    val (y1, m1) = first.split("-").let { it[0] to it[1].toInt() }
    val (y2, m2) = last.split("-").let { it[0] to it[1].toInt() }
    return when {
        y1 == y2 && m1 == m2 -> "${m[m2 - 1]}. $y2"
        y1 == y2 -> "${m[m1 - 1]}. – ${m[m2 - 1]}. $y2"
        else -> "${m[m1 - 1]}. $y1 – ${m[m2 - 1]}. $y2"
    }
}
