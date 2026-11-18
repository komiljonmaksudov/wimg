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
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.ReceiptLong
import androidx.compose.material.icons.outlined.Autorenew
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Rule
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.NewReleases
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material.icons.automirrored.outlined.KeyboardReturn
import androidx.compose.foundation.shape.RoundedCornerShape
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

/** Quick filters from the bar's filter button (the old start-screen chips, now out of the way). */
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

/**
 * Places and actions you can type to (search is the app's command line, like ⌘K):
 * "abrufen" fetches, "gehalt" opens Gehaltsmonat, "faq" the questions. [words] are extra
 * keywords, German and English, without umlauts. [path] says where the page lives,
 * [status] its state ("aktiv", "aus"), shown as a chip; [statusOn] colours it.
 */
private class SearchAction(
    val label: String, val sub: String?, val icon: androidx.compose.ui.graphics.vector.ImageVector, val words: String,
    val run: (NavController, Context) -> Unit,
    val status: String? = null, val statusOn: Boolean = false,
)

private fun norm(t: String) = t.lowercase().replace("ä", "a").replace("ö", "o").replace("ü", "u").replace("ß", "ss")

/** Brief 21b: the word starts a page name (or one of its words) or one of its keywords. */
private fun SearchAction.matches(q: String): Boolean {
    val n = norm(q.trim())
    if (n.length < 2) return false
    val l = norm(label)
    return l.startsWith(n) || (l.split(' ', '-', '·') + words.split(' ')).any { it.startsWith(n) }
}

@Composable
private fun agoText(ms: Long): String {
    val min = ((System.currentTimeMillis() - ms) / 60_000L).toInt()
    return when {
        min < 1 -> L("gerade eben")
        min < 60 -> L("vor %d Min.", min)
        min < 60 * 24 -> L("vor %d Std.", min / 60)
        else -> L("vor %d Tagen", min / (60 * 24))
    }
}

@Composable
private fun searchActions(ctx: Context): List<SearchAction> {
    val go = { route: String -> { nav: NavController, _: Context -> nav.navigate(route) } }
    val O = androidx.compose.material.icons.Icons.Outlined
    val bank = remember { com.wimg.app.services.BankConnections.all(ctx).maxByOrNull { it.lastFetchAt } }
    val syncOn = remember { com.wimg.app.services.SyncService.isEnabled(ctx) }
    val lockOn = com.wimg.app.services.BiometricLock.isEnabled
    val on = L("aktiv"); val off = L("aus")
    return listOfNotNull(
        bank?.let { b ->
            SearchAction(
                L("Umsätze von der Bank abrufen"),
                listOfNotNull(b.name, if (b.lastFetchAt > 0) L("zuletzt %s", agoText(b.lastFetchAt)) else null).joinToString(" · "),
                O.Refresh, "abrufen aktualisieren laden schnellabfrage fetch refresh bank neu",
                { nav, c -> nav.popBackStack(); if (!fetchFromSearch(c)) nav.navigate("fints") },
            )
        },
        SearchAction(L("Umsatz von Hand"), L("Bargeld oder was die Bank nicht kennt"), O.Add, "hinzufugen neu manuell bar bargeld add manual cash umsatz von hand", go("manual")),
        SearchAction(L("Übersicht"), null, O.Home, "home start dashboard verfugbar ubersicht", go("dashboard")),
        SearchAction(L("Umsätze"), null, O.ReceiptLong, "liste transaktionen transactions buchungen umsatze", go("transactions")),
        SearchAction(L("Wiederkehrend"), L("Abos und feste Kosten"), O.Autorenew, "abo abos fixkosten vertrage recurring subscriptions miete wiederkehrend", go("recurring")),
        SearchAction(L("Rückblick"), L("Monat oder Gehaltsmonat im Rückblick"), O.CalendarMonth, "ruckblick monat review sparquote", go("review")),
        SearchAction(L("Bankverbindung"), bank?.name ?: L("Bank verbinden"), O.AccountBalance, "bank banken fints comdirect sparkasse konto verbinden pin tan bankverbindung", go("fints")),
        SearchAction(L("Import"), L("Kontoauszug oder CSV-Datei"), O.UploadFile, "csv datei import hochladen kontoauszug mt940 camt revolut", go("import")),
        SearchAction(L("Einstellungen"), L("Sync, App-Sperre, Export, Kategorien"), O.Settings, "settings optionen einstellungen", go("settings")),
        SearchAction(L("Konten"), L("Einstellungen › Konten"), O.AccountBalanceWallet, "konten accounts ausblenden umbenennen", go("settings/accounts")),
        SearchAction(L("Gehaltsmonat"), L("Wann dein Monat beginnt"), O.Event, "gehalt zeitraum monat beginnt salary period payday gehaltsmonat", go("settings/period")),
        SearchAction(L("Darstellung"), L("Hell, dunkel, Sprache"), O.Palette, "dunkel hell theme dark light sprache language farbe design darstellung", go("settings/appearance")),
        SearchAction(L("Mitteilungen"), L("Einstellungen › Mitteilungen"), O.Notifications, "benachrichtigungen mitteilungen notifications ruhezeit", go("settings/notifications")),
        SearchAction(L("App-Sperre"), L("Einstellungen › Sicherheit"), O.Lock, "sperre lock fingerabdruck biometrie face pin app", go("settings/lock"), if (lockOn) on else off, lockOn),
        SearchAction(L("Gelernte Regeln"), L("Kategorien, die wimg sich gemerkt hat"), O.Rule, "regeln kategorie rules lernen gelernte", go("settings/rules")),
        SearchAction(L("Daten"), L("Export, Zurücksetzen"), O.Storage, "daten export backup loschen zurucksetzen csv data", go("settings/data")),
        SearchAction(L("wimg Sync"), L("Einstellungen › Geräte"), O.Sync, "sync gerate schlussel verknupfen devices key wimg", go("settings/sync"), if (syncOn) on else off, syncOn),
        SearchAction(L("Über wimg"), null, O.Info, "uber about version wimg", go("about")),
        SearchAction(L("Neuigkeiten"), L("Was ist neu, Updates"), O.NewReleases, "neu update version changelog news neuigkeiten", go("about/news")),
        SearchAction(L("Häufige Fragen"), null, O.HelpOutline, "faq fragen hilfe help support haufige", go("about/faq")),
        SearchAction(L("Datenschutz"), null, O.PrivacyTip, "datenschutz privacy daten", go("about/privacy")),
    )
}

/** The typed text as an amount ("49,90", "49.90", "1.234,56"), or null. */
private fun typedAmount(q: String): Double? {
    if (q.none { it.isDigit() } || q.any { !it.isDigit() && it != ',' && it != '.' }) return null
    val t = if (q.contains(',')) q.replace(".", "").replace(',', '.') else q
    return t.toDoubleOrNull()
}

/** Amount as typed: "12,99", "12.99", "1.234,56" all find 1234,56 / 12,99. */
private fun amountMatches(tx: Transaction, q: String): Boolean {
    if (q.none { it.isDigit() } || q.any { !it.isDigit() && it != ',' && it != '.' }) return false
    val typed = if (q.contains(',')) q.replace(".", "").replace(',', '.') else q
    val cents = Math.round(abs(tx.amount) * 100)
    val plain = "%d.%02d".format(cents / 100, cents % 100)
    return plain.startsWith(typed) || plain.contains(typed)
}

private fun textMatches(tx: Transaction, q: String) =
    tx.description.contains(q, ignoreCase = true) || tx.displayTitle.contains(q, ignoreCase = true)

private const val RECENT_KEY = "wimg_search_recent"

private fun loadRecent(ctx: Context): List<String> =
    ctx.getSharedPreferences("wimg", 0).getString(RECENT_KEY, "")!!.split('\n').filter { it.isNotBlank() }

private fun saveRecent(ctx: Context, q: String) {
    val list = (listOf(q.trim()) + loadRecent(ctx).filter { !it.equals(q.trim(), ignoreCase = true) }).take(5)
    ctx.getSharedPreferences("wimg", 0).edit().putString(RECENT_KEY, list.joinToString("\n")).apply()
}

private fun clearRecent(ctx: Context) = ctx.getSharedPreferences("wimg", 0).edit().remove(RECENT_KEY).apply()

/** The start screen's question "Größte Ausgaben diesen Monat" shows its answer in place. */
private enum class Question { BIGGEST }

/** Brief 21b: a page word names a page and finds fewer than 3 bookings. */
private const val PAGE_WORD_MAX_HITS = 3

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SearchScreen(selectedAccount: String?, navController: NavController, initialQuery: String = "") {
    val ctx = LocalContext.current
    // The preloaded Umsätze list first (no empty frame), the full list right after.
    var all by remember { mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<TxData>(txKey(selectedAccount))?.transactions.orEmpty()) }
    var accounts by remember { mutableStateOf<Map<String, Account>>(emptyMap()) }
    var recurringCount by remember { mutableStateOf<Int?>(null) }
    var query by remember { mutableStateOf(initialQuery) }
    var quick by remember { mutableStateOf<Quick?>(null) }
    var question by remember { mutableStateOf<Question?>(null) }
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
        recurringCount = withContext(Dispatchers.IO) { LibWimg.getRecurring().count { !it.isHidden && it.active != 0 } }
    }
    LaunchedEffect(Unit) { if (initialQuery.isBlank()) runCatching { focus.requestFocus() } }

    val q = query.trim()
    val active = q.isNotEmpty() || quick != null || question != null
    // Off the main thread (3,000+ rows per keystroke). The result carries its key, so
    // "Nichts für …" never shows for an input that is still being searched.
    val searched by androidx.compose.runtime.produceState<Pair<Any?, List<Transaction>>>(null to emptyList(), all, q, quick, question) {
        val key = Triple(q, quick, question)
        value = key to withContext(Dispatchers.Default) {
            when {
                question == Question.BIGGEST -> {
                    val month = WimgDates.todayIso().substring(0, 7)
                    all.filter { it.date.startsWith(month) && it.amount < 0 && !it.isExcluded }.sortedBy { it.amount }.take(20)
                }
                !active -> emptyList()
                else -> all.filter { tx -> (q.isEmpty() || textMatches(tx, q) || amountMatches(tx, q)) && (quick?.matches(tx) ?: true) }
            }
        }
    }
    val current = searched.first == Triple(q, quick, question)
    val hits = searched.second
    val allActions = searchActions(ctx)
    val actions = if (q.isEmpty() || question != null) emptyList() else allActions.filter { it.matches(q) }
    // Page words win (brief 21b): the page row first, a quiet band, Enter opens it.
    val pageMode = current && actions.isNotEmpty() && hits.size < PAGE_WORD_MAX_HITS && quick == null
    val c = Wimg.colors
    fun keepRecent(q: String) { if (q.isNotEmpty()) { saveRecent(ctx, q); recent = loadRecent(ctx) } }
    fun openAction(a: SearchAction) { keepRecent(q); keyboard?.hide(); a.run(navController, ctx) }

    Box(Modifier.fillMaxSize()) {
        BandScreen(
            band = {
                when {
                    !active -> {
                        Text(L("Suche"), style = WimgType.bandOver, color = c.bandSub)
                        Text(L("Was willst du wissen?"), style = WimgType.title, color = Color.White, modifier = Modifier.padding(top = 4.dp))
                        Text(L("Händler, Betrag oder eine Seite. Alles bleibt auf dem Handy."), style = WimgType.desc, color = c.bandSub, modifier = Modifier.padding(top = 6.dp))
                    }
                    pageMode -> {
                        Text(searchLabel(q), style = WimgType.bandOver, color = c.bandSub)
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) {
                            Text(
                                L("Seite"), style = WimgType.chip, color = c.bandSub,
                                modifier = Modifier.border(1.dp, c.bandSub.copy(alpha = 0.5f), RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 3.dp),
                            )
                            Spacer(Modifier.width(12.dp))
                            Text(actions.first().label, style = WimgType.title, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Text(L("Enter öffnet die Seite."), style = WimgType.desc, color = c.bandSub, modifier = Modifier.padding(top = 6.dp))
                    }
                    else -> {
                        val over = when {
                            question == Question.BIGGEST -> L("Größte Ausgaben diesen Monat")
                            else -> listOfNotNull(q.takeIf { it.isNotEmpty() }?.let { searchLabel(it) }, quick?.let { L(it.label) }).joinToString(" · ")
                        }
                        Text(over, style = WimgType.bandOver, color = c.bandSub, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val sum = hits.sumOf { it.amount }
                        Amount(sum, WimgType.amountHero, WimgType.amountHeroCents, if (sum > 0) c.bandPos else Color.White, Modifier.padding(top = 2.dp))
                        val line = if (hits.isEmpty()) L("Keine Treffer") else listOf(
                            if (hits.size == 1) L("1 Umsatz") else L("%d Umsätze", hits.size),
                            "⌀ " + amountText(abs(sum) / hits.size, showPlus = false),
                            dateRange(hits),
                        ).joinToString(" · ")
                        Text(line, style = WimgType.desc, color = c.bandSub, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
                    }
                }
            },
        ) {
            when {
                !active -> StartView(
                    recent = recent, all = all, allActions = allActions, recurringCount = recurringCount,
                    onRecent = { query = it; keyboard?.hide() },
                    onClear = { clearRecent(ctx); recent = emptyList() },
                    onGo = { route -> keyboard?.hide(); navController.navigate(route) },
                    onBiggest = { keyboard?.hide(); question = Question.BIGGEST },
                )
                !current -> Box(Modifier.fillMaxSize())
                pageMode -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 140.dp)) {
                    item {
                        SectionTitle(L("Seiten"))
                        ActionCard(actions.take(3), q, firstIsEnter = true, onPick = ::openAction)
                    }
                    if (hits.isNotEmpty()) {
                        item { SectionTitle(L("Auch in Umsätzen · %d", hits.size)) }
                        item {
                            Card {
                                hits.forEachIndexed { i, tx ->
                                    if (i > 0) HorizontalDivider(thickness = 1.dp, color = c.line)
                                    CompactHit(tx, q) { keepRecent(q); navController.navigate("tx/${tx.id}") }
                                }
                            }
                        }
                    }
                }
                hits.isEmpty() -> NoHits(q, all, onSearch = { query = it }, onBack = if (question != null) ({ question = null }) else null)
                else -> HitList(
                    hits = hits, q = if (question == null) q else "", actions = actions.take(3),
                    accounts = accounts, onAction = ::openAction,
                    onHit = { tx -> keepRecent(q); navController.navigate("tx/${tx.id}") },
                )
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
                BarBack {
                    keyboard?.hide()
                    if (question != null) question = null else navController.popBackStack()
                }
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
                    val placeholder = L("Suchen: Händler, Betrag, Seite")
                    Box(Modifier.weight(1f)) {
                        if (query.isEmpty()) Text(placeholder, style = WimgType.body, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        BasicTextField(
                            value = query,
                            onValueChange = { query = it; question = null },
                            singleLine = true,
                            textStyle = WimgType.body.copy(color = c.text),
                            cursorBrush = SolidColor(c.accent),
                            // The keyboard's action key says what Enter does: open the page, or search.
                            keyboardOptions = KeyboardOptions(imeAction = if (pageMode) ImeAction.Go else ImeAction.Search),
                            keyboardActions = KeyboardActions(
                                onGo = { actions.firstOrNull()?.let(::openAction) },
                                onSearch = { keepRecent(q); keyboard?.hide() },
                            ),
                            // The placeholder is drawn beside the field: give the field the same words, or
                            // TalkBack (and Maestro) see an unlabelled text box.
                            modifier = Modifier.fillMaxWidth().focusRequester(focus).semantics { contentDescription = placeholder },
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

@Composable
private fun searchLabel(q: String) = L("Suche: %s", q)

@Composable
private fun SectionTitle(text: String, trailing: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 22.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = WimgType.section, color = Wimg.colors.text, modifier = Modifier.weight(1f))
        trailing?.invoke()
    }
}

/** A white card with a hairline, as in the boards. */
@Composable
private fun Card(modifier: Modifier = Modifier, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    val c = Wimg.colors
    Column(
        modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group),
        content = content,
    )
}

/** Start (boards 05, 15): recent searches with their totals, "Springen zu", two questions. */
@Composable
private fun StartView(
    recent: List<String>, all: List<Transaction>, allActions: List<SearchAction>, recurringCount: Int?,
    onRecent: (String) -> Unit, onClear: () -> Unit, onGo: (String) -> Unit, onBiggest: () -> Unit,
) {
    val c = Wimg.colors
    val ctx = LocalContext.current
    androidx.compose.foundation.lazy.LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 140.dp)) {
        if (recent.isNotEmpty()) item {
            SectionTitle(L("Zuletzt gesucht")) {
                Text(L("Löschen"), style = WimgType.chip, color = c.accent, modifier = Modifier.clip(WimgShape.button).clickable(onClick = onClear).padding(6.dp))
            }
            Card {
                recent.forEachIndexed { i, r ->
                    if (i > 0) HorizontalDivider(thickness = 1.dp, color = c.line, modifier = Modifier.padding(start = 64.dp))
                    val found = remember(r, all) { all.filter { textMatches(it, r) || amountMatches(it, r) } }
                    val page = allActions.firstOrNull { it.matches(r) }?.takeIf { found.size < PAGE_WORD_MAX_HITS }
                    StartRow(
                        icon = Icons.Outlined.History, tint = c.text2, title = r,
                        sub = if (page != null) L("Seite · %s", page.label) else if (found.size == 1) L("1 Umsatz") else L("%d Umsätze", found.size),
                        trailing = if (page == null && found.isNotEmpty()) amountText(found.sumOf { it.amount }) else null,
                        chevron = page != null,
                    ) { onRecent(r) }
                }
            }
        }
        item {
            SectionTitle(L("Springen zu"))
            val months = WimgDates.months()
            val lastMonth = java.util.Calendar.getInstance().apply { add(java.util.Calendar.MONTH, -1) }.get(java.util.Calendar.MONTH)
            val bank = remember { com.wimg.app.services.BankConnections.all(ctx).firstOrNull()?.name }
            val tiles = listOf(
                Tile(L("Wiederkehrend"), recurringCount?.let { if (it == 1) L("1 läuft") else L("%d laufen", it) } ?: "", Icons.Outlined.Autorenew, c.categoryBar(WimgCategory.SUBSCRIPTIONS.id), "recurring"),
                Tile(L("Rückblick"), L("%s ist fertig", months[lastMonth]), Icons.Outlined.CalendarMonth, c.categoryBar(WimgCategory.DINING.id), "review"),
                Tile(L("Banken"), bank ?: L("Bank verbinden"), Icons.Outlined.AccountBalance, c.accent, "fints"),
                Tile(L("Einstellungen"), L("Sync, Sperre, Export"), Icons.Outlined.Settings, c.text2, "settings"),
            )
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                tiles.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        pair.forEach { t -> TileView(t, Modifier.weight(1f)) { onGo(t.route) } }
                    }
                }
            }
        }
        item {
            SectionTitle(L("Fragen"))
            val month = WimgDates.todayIso().substring(0, 7)
            val biggest = remember(all) {
                all.filter { it.date.startsWith(month) && it.amount < 0 && !it.isExcluded }.sortedBy { it.amount }.take(3).map { it.displayTitle.split(' ').first() }
            }
            Card {
                StartRow(
                    icon = Icons.Outlined.ArrowUpward, tint = c.categoryBar(WimgCategory.DINING.id), title = L("Größte Ausgaben diesen Monat"),
                    sub = biggest.joinToString(", ").ifEmpty { null }, chevron = true, onClick = onBiggest,
                )
                HorizontalDivider(thickness = 1.dp, color = c.line, modifier = Modifier.padding(start = 64.dp))
                StartRow(
                    icon = Icons.Outlined.Autorenew, tint = c.categoryBar(WimgCategory.SUBSCRIPTIONS.id), title = L("Abos und feste Kosten"),
                    sub = recurringCount?.let { if (it == 1) L("1 läuft") else L("%d laufen", it) }, chevron = true,
                ) { onGo("recurring") }
            }
            Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp), verticalAlignment = Alignment.Top) {
                Icon(Icons.Outlined.Info, contentDescription = null, tint = c.text3, modifier = Modifier.padding(top = 2.dp, end = 8.dp).size(16.dp))
                Text(L("Die Suche läuft nur auf deinem Handy. Nichts wird gesendet."), style = WimgType.desc, color = c.text2)
            }
        }
    }
}

private class Tile(val title: String, val sub: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val tint: Color, val route: String)

@Composable
private fun TileView(t: Tile, modifier: Modifier, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(
        modifier.heightIn(min = 64.dp).clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        com.wimg.app.ui.components.IconTile(t.icon, t.tint)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(t.title, style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (t.sub.isNotEmpty()) Text(t.sub, style = WimgType.desc, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun StartRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color, title: String, sub: String?,
    trailing: String? = null, chevron: Boolean = false, onClick: () -> Unit,
) {
    val c = Wimg.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        com.wimg.app.ui.components.IconTile(icon, tint)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = WimgType.rowTitle, color = c.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (sub != null) Text(sub, style = WimgType.desc, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (trailing != null) Text(trailing, style = WimgType.rowTitle, color = c.text, modifier = Modifier.padding(start = 10.dp))
        if (chevron) Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = c.text3, modifier = Modifier.padding(start = 6.dp).size(20.dp))
    }
}

/** Pages and actions: the first one framed with "↵ Öffnen" in page mode, states as chips. */
@Composable
private fun ActionCard(actions: List<SearchAction>, q: String, firstIsEnter: Boolean, onPick: (SearchAction) -> Unit) {
    val c = Wimg.colors
    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val first = actions.first()
        val rest = if (firstIsEnter) actions.drop(1) else actions
        if (firstIsEnter) {
            Box(Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(2.dp, c.accent, WimgShape.group)) {
                ActionRow(first, q, enter = true) { onPick(first) }
            }
        }
        if (rest.isNotEmpty()) Column(Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group)) {
            rest.forEachIndexed { i, a ->
                if (i > 0) HorizontalDivider(thickness = 1.dp, color = c.line, modifier = Modifier.padding(start = 64.dp))
                ActionRow(a, q, enter = false) { onPick(a) }
            }
        }
    }
}

@Composable
private fun ActionRow(a: SearchAction, q: String, enter: Boolean, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(36.dp).clip(WimgShape.iconTile).background(if (enter) c.accentSoft else c.neutralTint), contentAlignment = Alignment.Center) {
            Icon(a.icon, contentDescription = null, tint = if (enter) c.accent else c.text, modifier = Modifier.size(19.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(highlight(a.label, q, c.accentSoft), style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (a.sub != null) Text(a.sub, style = WimgType.desc, color = c.text2, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        when {
            enter -> Row(
                Modifier.padding(start = 8.dp).clip(RoundedCornerShape(10.dp)).background(c.accent).padding(horizontal = 10.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Outlined.KeyboardReturn, contentDescription = null, tint = c.onAccent, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(5.dp))
                Text(L("Öffnen"), style = WimgType.chip, color = c.onAccent)
            }
            a.status != null -> Row(
                Modifier.padding(start = 8.dp).clip(CircleShape).background(if (a.statusOn) c.pos.copy(alpha = 0.12f) else c.neutralTint).padding(horizontal = 10.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(if (a.statusOn) c.pos else c.text3))
                Spacer(Modifier.width(6.dp))
                Text(a.status, style = WimgType.chip, color = if (a.statusOn) c.pos else c.text2)
            }
            else -> Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = c.text3, modifier = Modifier.size(20.dp))
        }
    }
}

/** Results (board 03): pages first when the word matches one, the merchant, then bookings by month. */
@Composable
private fun HitList(
    hits: List<Transaction>, q: String, actions: List<SearchAction>, accounts: Map<String, Account>,
    onAction: (SearchAction) -> Unit, onHit: (Transaction) -> Unit,
) {
    val c = Wimg.colors
    val typed = typedAmount(q)
    // "49,90": the exact amount first, then within ± 1 € (board 07).
    val exact = remember(hits, q) { if (typed == null) emptyList() else hits.filter { abs(abs(it.amount) - typed) < 0.005 } }
    val merchant = remember(hits, q) { if (typed != null || q.isEmpty()) null else dominantMerchant(hits, q) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 140.dp)) {
        if (actions.isNotEmpty()) item {
            SectionTitle(L("Seiten und Aktionen"))
            ActionCard(actions, q, firstIsEnter = false, onPick = onAction)
        }
        if (merchant != null) item {
            SectionTitle(L("Händler"))
            Card {
                StartRow(
                    icon = Icons.Outlined.Storefront, tint = c.text2, title = merchant.name,
                    sub = listOf(if (merchant.count == 1) L("1 Umsatz") else L("%d Umsätze", merchant.count)).plus(merchant.categories.map { L(WimgCategory.fromId(it).label) }).joinToString(" · "),
                    trailing = amountText(merchant.sum),
                ) {}
            }
        }
        if (typed != null && exact.isNotEmpty()) {
            item { SectionTitle(L("Genau %s", amountText(typed, showPlus = false))) }
            item { HitCard(exact, q, accounts, onHit) }
            val near = hits.filter { abs(abs(it.amount) - typed) <= 1.0 && it !in exact }
            if (near.isNotEmpty()) {
                item { SectionTitle(L("Ungefähr (± 1 €)")) }
                item { HitCard(near, q, accounts, onHit) }
            }
        } else {
            item { SectionTitle(L("Umsätze")) }
            val byMonth = hits.groupBy { it.date.substring(0, 7) }.toList()
            byMonth.forEach { (ym, txs) ->
                item(key = "m_$ym") {
                    Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 8.dp)) {
                        Text(monthLabel(ym), style = WimgType.chip, color = c.text2, modifier = Modifier.weight(1f))
                        Text(amountText(txs.sumOf { it.amount }), style = WimgType.chip, color = c.text2)
                    }
                }
                item(key = "c_$ym") { HitCard(txs, q, accounts, onHit); Spacer(Modifier.height(10.dp)) }
            }
        }
    }
}

@Composable
private fun HitCard(txs: List<Transaction>, q: String, accounts: Map<String, Account>, onHit: (Transaction) -> Unit) {
    val c = Wimg.colors
    Card {
        txs.forEachIndexed { i, tx ->
            if (i > 0) HorizontalDivider(thickness = 1.dp, color = c.line, modifier = Modifier.padding(start = 16.dp))
            HitRow(tx, q, accounts[tx.account]?.let { it.bank.ifBlank { it.name } }.takeIf { accounts.size > 1 }) { onHit(tx) }
        }
    }
}

private class Merchant(val name: String, val count: Int, val sum: Double, val categories: List<Int>)

/** The merchant most hits share (its first word), when it holds at least half of them. */
private fun dominantMerchant(hits: List<Transaction>, q: String): Merchant? {
    if (hits.size < 2) return null
    val groups = hits.groupBy { it.displayTitle.trim().split(' ', '*', '/').firstOrNull { w -> w.length >= 2 }?.uppercase() ?: "" }
    val (key, txs) = groups.maxByOrNull { it.value.size } ?: return null
    if (key.isEmpty() || txs.size < 2 || txs.size * 2 < hits.size || !key.contains(q.trim().uppercase())) return null
    val cats = txs.groupBy { it.category }.entries.sortedByDescending { it.value.size }.take(2).map { it.key }
    return Merchant(key, txs.size, txs.sumOf { it.amount }, cats)
}

/** "November", or "November 2025" for another year. */
private fun monthLabel(ym: String): String {
    val (y, m) = ym.split("-").let { it[0] to it[1].toInt() }
    val name = WimgDates.months()[m - 1]
    return if (y == WimgDates.todayIso().substring(0, 4)) name else "$name $y"
}

/** Board 08: say why, and offer the search that does find something. */
@Composable
private fun NoHits(q: String, all: List<Transaction>, onSearch: (String) -> Unit, onBack: (() -> Unit)?) {
    val c = Wimg.colors
    val shorter = remember(q, all) {
        // Drop words from the end (and numbers) until something matches.
        var words = q.split(' ').filter { it.isNotBlank() }
        var found: Pair<String, List<Transaction>>? = null
        while (words.size > 1 && found == null) {
            words = words.dropLast(1)
            val t = words.joinToString(" ")
            val h = all.filter { textMatches(it, t) }
            if (h.isNotEmpty()) found = t to h
        }
        found
    }
    val oldest = all.minOfOrNull { it.date }
    Column(Modifier.padding(start = 24.dp, end = 24.dp, top = 24.dp)) {
        Text(if (q.isEmpty()) L("Nichts gefunden.") else L("Nichts für „%s“.", q), style = WimgType.section.copy(fontSize = WimgType.section.fontSize * 1.15f), color = c.text)
        val why = listOfNotNull(
            oldest?.let { L("Deine Umsätze reichen bis %s zurück.", monthLabel(it.substring(0, 7)).let { m -> if (m.contains(' ')) m else "$m ${it.substring(0, 4)}" }) },
            if (shorter == null) L("Banken kürzen Namen oft ab: versuch einen Teil des Namens.") else null,
        ).joinToString(" ")
        if (why.isNotEmpty()) Text(why, style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 8.dp))
    }
    if (shorter != null) Box(Modifier.padding(top = 16.dp)) {
        Card {
            StartRow(
                icon = Icons.Outlined.Search, tint = c.accent, title = L("Nach „%s“ suchen", shorter.first),
                sub = if (shorter.second.size == 1) L("1 Umsatz") else L("%d Umsätze", shorter.second.size),
                trailing = amountText(shorter.second.sumOf { it.amount }),
            ) { onSearch(shorter.first) }
        }
    }
    Row(Modifier.padding(start = 24.dp, end = 24.dp, top = 16.dp), verticalAlignment = Alignment.Top) {
        Icon(Icons.Outlined.Info, contentDescription = null, tint = c.text3, modifier = Modifier.padding(top = 2.dp, end = 8.dp).size(16.dp))
        Text(L("Die Suche läuft nur auf deinem Handy. Nichts wird gesendet."), style = WimgType.desc, color = c.text2)
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

/** "Auch in Umsätzen": one line per booking, smaller (board 18). */
@Composable
private fun CompactHit(tx: Transaction, q: String, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            buildAnnotatedString { append(highlight(snippet(tx, q), q, c.accentSoft)); withStyle(SpanStyle(color = c.text2)) { append(" · " + WimgDates.short(tx.date)) } },
            style = WimgType.body, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
        Text(amountText(tx.amount), style = WimgType.body, color = if (tx.amount > 0) c.pos else c.text, modifier = Modifier.padding(start = 10.dp))
    }
}

@Composable
private fun HitRow(tx: Transaction, q: String, account: String?, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).heightIn(min = 64.dp).padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(highlight(snippet(tx, q), q, c.accentSoft), style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                listOfNotNull(WimgDates.short(tx.date), account, L(WimgCategory.fromId(tx.category).label)).joinToString(" · "),
                style = WimgType.desc, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Amount(tx.amount, WimgType.amountRow.copy(fontSize = WimgType.amountRow.fontSize * 1.12f), WimgType.amountRowCents, if (tx.amount > 0) c.pos else c.text)
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
