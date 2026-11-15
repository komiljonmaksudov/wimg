package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.ui.layout.layout
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.QuietLine
import com.wimg.app.ui.components.RowDivider
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.WimgGroup
import com.wimg.app.ui.components.WimgRow
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import com.wimg.app.ui.theme.categoryBar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Calendar

/** Account for entries without a bank (board 22: "„Bargeld“ ist ein eigenes Konto ohne Bank"). */
const val CASH_ACCOUNT = "Bargeld"

/**
 * Umsatz von Hand (board 22): amount first on its own keypad, then text,
 * category, account and date. Saved entries are marked as manual by their id
 * and never matched by a bank import.
 */
@Composable
fun ManualEntryScreen(navController: NavController?, editId: String? = null) {
    val c = Wimg.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // Editing a manual entry: the same form, filled in.
    val editing = remember(editId) {
        editId?.let { id ->
            (com.wimg.app.ui.components.ScreenCache.get<TxData>(txKey(null))?.transactions?.firstOrNull { it.id == id }
                ?: LibWimg.ifFree { LibWimg.getTransactions().firstOrNull { it.id == id } })
        }
    }
    var expense by remember { mutableStateOf(editing?.let { it.amount < 0 } ?: true) }
    var digits by remember { mutableStateOf(editing?.let { typedOf(kotlin.math.abs(it.amount)) } ?: "") } // amount as typed, e.g. "18,4"
    // The system keyboard (number layout), not a keypad of our own.
    val amountFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    val descFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    LaunchedEffect(Unit) { if (editing == null) runCatching { amountFocus.requestFocus() } }
    // Set after a tap on Speichern with something missing: the row turns red.
    var showMissing by remember { mutableStateOf(false) }
    var description by remember { mutableStateOf(editing?.description ?: "") }
    var category by remember { mutableIntStateOf(editing?.category ?: -1) }
    var account by remember { mutableStateOf(editing?.account?.takeIf { it.isNotBlank() } ?: CASH_ACCOUNT) }
    var dayOffset by remember { mutableIntStateOf(editing?.let { daysAgo(it.date) } ?: 0) } // days back: 0 = heute, 1 = gestern, any day in the past
    var panel by remember { mutableStateOf<String?>(null) }
    var accounts by remember { mutableStateOf(listOf(CASH_ACCOUNT)) }
    LaunchedEffect(Unit) {
        val bank = withContext(Dispatchers.IO) { LibWimg.getAccounts().map { it.id } }
        accounts = (listOf(CASH_ACCOUNT) + bank).distinct()
    }

    val cents = parseCents(digits)
    val date = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -dayOffset) }
    val iso = "%04d-%02d-%02d".format(date.get(Calendar.YEAR), date.get(Calendar.MONTH) + 1, date.get(Calendar.DAY_OF_MONTH))
    val canSave = cents > 0 && description.isNotBlank()

    fun save() {
        if (!canSave) return
        scope.launch {
            val ok = withContext(Dispatchers.IO) {
                val signed = if (expense) -cents else cents
                if (editing != null) LibWimg.updateManualTransaction(editing.id, iso, description.trim(), signed, if (category < 0) 0 else category, account)
                else LibWimg.addManualTransaction(iso, description.trim(), signed, if (category < 0) 0 else category, account)
            }
            if (ok) {
                Changes.bump()
                Dock.info(__t("Umsatz gespeichert"), description.trim())
                navController?.popBackStack()
            } else Dock.error(__t("Nicht gespeichert"), __t("Bitte versuch es noch einmal."))
        }
    }

    BarContribution(
        chip = null,
        panel = when (panel) {
            "category" -> { { CategoryPanel(if (category < 0) 0 else category) { category = it; panel = null } } }
            "account" -> { { ChoicePanel(L("Konto"), accounts, accounts.indexOf(account)) { account = accounts[it]; panel = null } } }
            "date" -> { { DatePanel(dayOffset) { dayOffset = it; panel = null } } }
            else -> null
        },
        onPanelDismiss = { panel = null },
        detail = DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = L("Speichern"),
            actionIcon = null,
            onAction = {
                when {
                    cents == 0L -> {
                        showMissing = true
                        Dock.error(__t("Betrag fehlt"), __t("Tipp oben den Betrag ein."))
                        runCatching { amountFocus.requestFocus() }
                    }
                    description.isBlank() -> {
                        showMissing = true
                        Dock.error(__t("Beschreibung fehlt"), __t("Wofür war das? Zum Beispiel „Wochenmarkt“."))
                        runCatching { descFocus.requestFocus() }
                    }
                    else -> save()
                }
            },
        ),
    )

    BandScreen(band = {
        Row(Modifier.clip(WimgShape.segmentOuter).background(Color.White.copy(alpha = 0.08f)).padding(4.dp)) {
            listOf(true to L("Ausgabe"), false to L("Einnahme")).forEach { (isExp, label) ->
                val on = expense == isExp
                Box(
                    Modifier.clip(WimgShape.segmentInner).background(if (on) Color.White else Color.Transparent).pressable { expense = isExp }.padding(horizontal = 18.dp, vertical = 8.dp),
                ) { Text(label, style = WimgType.button, color = if (on) c.ink else c.bandSub) }
            }
        }
        // The cents not typed yet are shown greyed ("54.543,00"), so the
        // thousands dot can't be mistaken for the comma.
        val typed = formatTyped(digits)
        val pending = when {
            digits.isEmpty() -> ""
            !digits.contains(',') -> ",00"
            else -> "0".repeat(2 - digits.substringAfter(',').length)
        }
        Box(Modifier.padding(top = 14.dp)) {
            Text(
                androidx.compose.ui.text.buildAnnotatedString {
                    append((if (expense) "−" else "+") + typed)
                    pushStyle(androidx.compose.ui.text.SpanStyle(color = c.bandSub)); append(pending); pop()
                    append(" €")
                },
                style = WimgType.amountHero, color = if (cents == 0L) (if (showMissing) c.danger else c.bandSub) else Color.White,
            )
            // Invisible field on top: it takes the typing (Gboard's number
            // layout), the formatted amount above is what you see.
            BasicTextField(
                value = digits,
                onValueChange = { digits = cleanAmount(it) },
                singleLine = true,
                textStyle = WimgType.amountHero.copy(color = Color.Transparent),
                cursorBrush = SolidColor(Color.Transparent),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal,
                    imeAction = androidx.compose.ui.text.input.ImeAction.Next,
                ),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onNext = { runCatching { descFocus.requestFocus() } }),
                modifier = Modifier.matchParentSize().focusRequester(amountFocus),
            )
        }
    }) {
        // Scrolls when the keyboard takes the room.
        Box(Modifier.weight(1f).fillMaxWidth()) { Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) {
            WimgGroup {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L("Beschreibung"), style = WimgType.body, color = if (showMissing && description.isBlank()) c.danger else c.text2)
                    Spacer(Modifier.width(16.dp))
                    BasicTextField(
                        value = description, onValueChange = { description = it.take(120) }, singleLine = true,
                        textStyle = WimgType.rowTitle.copy(color = c.text, textAlign = TextAlign.End),
                        cursorBrush = SolidColor(c.accent),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                        modifier = Modifier.weight(1f).focusRequester(descFocus),
                        decorationBox = { inner ->
                            Box(contentAlignment = Alignment.CenterEnd) {
                                if (description.isEmpty()) Text(L("z. B. Wochenmarkt"), style = WimgType.rowTitle, color = c.text3)
                                inner()
                            }
                        },
                    )
                }
                RowDivider()
                WimgRow(L("Kategorie"), chevron = true, onClick = { panel = "category" }, trailing = {
                    if (category < 0) Text(L("Wählen"), style = WimgType.body, color = c.text2)
                    else {
                        Box(Modifier.size(9.dp).clip(CircleShape).background(c.categoryBar(category)))
                        Spacer(Modifier.width(8.dp))
                        Text(L(WimgCategory.fromId(category).label), style = WimgType.rowTitle, color = c.text)
                    }
                })
                RowDivider()
                WimgRow(L("Konto"), chevron = true, onClick = { panel = "account" }, trailing = { Text(account, style = WimgType.rowTitle, color = c.text, maxLines = 1) })
                RowDivider()
                WimgRow(L("Datum"), chevron = true, onClick = { panel = "date" }, trailing = { Text(dayLabel(dayOffset), style = WimgType.rowTitle, color = c.text) })
            }
            QuietLine(L("Von Hand angelegte Umsätze werden nie mit Bankdaten überschrieben. „Bargeld“ ist ein eigenes Konto ohne Bank."))
        } }
    }
}

/** Typed amount kept to "12345,67": one comma (a dot counts as one), at most
 *  5 digits before it and 2 after, no leading zeros. */
private fun cleanAmount(input: String): String {
    var whole = ""; var dec = ""; var comma = false
    for (ch in input.replace('.', ',')) {
        when {
            ch == ',' && !comma -> comma = true
            ch.isDigit() && !comma && whole.length < 5 -> whole += ch
            ch.isDigit() && comma && dec.length < 2 -> dec += ch
        }
    }
    whole = whole.trimStart('0').ifEmpty { if (comma || input.startsWith("0")) "0" else "" }
    return if (comma) "$whole,$dec" else whole
}

/** 18.4 → "18,4", 20.0 → "20" (as if typed). */
private fun typedOf(euros: Double): String {
    val cents = Math.round(euros * 100)
    return if (cents % 100 == 0L) "${cents / 100}" else "%d,%02d".format(cents / 100, cents % 100).trimEnd('0')
}

/** Whole days from "YYYY-MM-DD" to today (0 = today). */
private fun daysAgo(iso: String): Int {
    val d = com.wimg.app.ui.components.WimgDates.parse(iso) ?: return 0
    val today = com.wimg.app.ui.components.WimgDates.parse(com.wimg.app.ui.components.WimgDates.todayIso()) ?: return 0
    return ((today.timeInMillis - d.timeInMillis) / 86_400_000L).toInt().coerceAtLeast(0)
}

/** "18,4" → 1840 cents. */
private fun parseCents(typed: String): Long {
    if (typed.isEmpty()) return 0
    val whole = typed.substringBefore(',').ifEmpty { "0" }.toLongOrNull() ?: 0
    val dec = typed.substringAfter(',', "").padEnd(2, '0').take(2).toLongOrNull() ?: 0
    return whole * 100 + dec
}

/** What the user typed, shown German-style ("1.234,5" while typing, "0,00" when empty). */
private fun formatTyped(typed: String): String {
    if (typed.isEmpty()) return "0,00"
    val whole = typed.substringBefore(',').ifEmpty { "0" }
    val grouped = whole.reversed().chunked(3).joinToString(".").reversed()
    return if (typed.contains(',')) "$grouped,${typed.substringAfter(',')}" else grouped
}

@Composable
private fun dayLabel(offset: Int): String {
    val cal = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -offset) }
    val iso = "%04d-%02d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))
    return when (offset) {
        0 -> L("Heute, %s", WimgDates.short(iso))
        1 -> L("Gestern, %s", WimgDates.short(iso))
        else -> WimgDates.short(iso)
    }
}

@Composable
private fun ChoicePanel(title: String, options: List<String>, selected: Int, onPick: (Int) -> Unit) {
    val c = Wimg.colors
    BarPanel {
        Text(title, style = WimgType.sheetTitle, color = c.text, modifier = Modifier.padding(bottom = 10.dp))
        WimgGroup {
            options.forEachIndexed { i, o ->
                if (i > 0) RowDivider()
                WimgRow(o, onClick = { onPick(i) }, trailing = {
                    if (i == selected) Box(Modifier.size(10.dp).clip(CircleShape).background(c.accent))
                })
            }
        }
    }
}

/** Midnight UTC of the local day [daysBack] days ago (what DatePicker works in). */
private fun utcDay(daysBack: Int): Long {
    val local = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -daysBack) }
    return Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC")).apply {
        clear(); set(local.get(Calendar.YEAR), local.get(Calendar.MONTH), local.get(Calendar.DAY_OF_MONTH))
    }.timeInMillis
}

/** Datum: Heute / Gestern at hand, any earlier day in the calendar below. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun DatePanel(daysBack: Int, onPick: (Int) -> Unit) {
    val c = Wimg.colors
    val today = remember { utcDay(0) }
    val thisYear = remember { Calendar.getInstance().get(Calendar.YEAR) }
    val state = androidx.compose.material3.rememberDatePickerState(
        initialSelectedDateMillis = utcDay(daysBack),
        selectableDates = object : androidx.compose.material3.SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= today
            override fun isSelectableYear(year: Int) = year <= thisYear
        },
    )
    LaunchedEffect(state.selectedDateMillis) {
        val sel = state.selectedDateMillis ?: return@LaunchedEffect
        val back = ((today - sel) / 86_400_000L).toInt()
        if (back != daysBack) onPick(back)
    }
    BarPanel {
        Text(L("Datum"), style = WimgType.sheetTitle, color = c.text, modifier = Modifier.padding(bottom = 10.dp))
        androidx.compose.material3.DatePicker(
            // The calendar needs ~360 dp: it takes the panel's side padding too,
            // or its last column (Sunday) gets squeezed.
            modifier = Modifier.layout { m, cs ->
                val extra = 16.dp.roundToPx()
                val p = m.measure(cs.copy(minWidth = 0, maxWidth = cs.maxWidth + 2 * extra))
                layout(cs.maxWidth, p.height) { p.place((cs.maxWidth - p.width) / 2, 0) }
            },
            state = state,
            title = null,
            headline = null,
            showModeToggle = false,
            colors = androidx.compose.material3.DatePickerDefaults.colors(
                containerColor = c.card,
                weekdayContentColor = c.text2,
                subheadContentColor = c.text2,
                navigationContentColor = c.text,
                yearContentColor = c.text,
                currentYearContentColor = c.text,
                selectedYearContentColor = c.inkText,
                selectedYearContainerColor = c.ink,
                dayContentColor = c.text,
                disabledDayContentColor = c.text3,
                selectedDayContentColor = c.inkText,
                selectedDayContainerColor = c.ink,
                todayContentColor = c.text,
                todayDateBorderColor = c.accent,
            ),
        )
        SegmentRow(listOf(L("Heute"), L("Gestern")), daysBack) { onPick(it) }
    }
}
