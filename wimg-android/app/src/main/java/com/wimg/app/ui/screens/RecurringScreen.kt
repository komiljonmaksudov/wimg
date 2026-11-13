package com.wimg.app.ui.screens

import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.models.RecurringPattern
import com.wimg.app.models.RecurringPayment
import com.wimg.app.ui.components.Amount
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarChipSpec
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.amountText
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Calendar
import kotlin.math.abs

/** libwimg interval ids, in display order, with their label and per-month factor. */
internal val INTERVALS = listOf(
    Triple("weekly", "Wöchentlich", 52.0 / 12.0),
    Triple("monthly", "Monatlich", 1.0),
    Triple("quarterly", "Vierteljährlich", 1.0 / 3.0),
    Triple("annual", "Jährlich", 1.0 / 12.0),
)

internal fun monthlyFactor(interval: String) = INTERVALS.firstOrNull { it.first == interval }?.third ?: 1.0
internal fun intervalLabel(interval: String) = INTERVALS.firstOrNull { it.first == interval }?.second ?: interval

internal const val REC_KEY = "rec"

internal fun loadRecurring(): List<RecurringPattern> {
    var list = LibWimg.getRecurring()
    // Patterns saved by older libwimg builds have next_due before
    // last_seen (broken date maths). Detecting again fixes them in place.
    if (list.any { p -> p.next_due != null && p.next_due < p.last_seen }) {
        LibWimg.detectRecurring()
        list = LibWimg.getRecurring()
    }
    return list
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RecurringScreen(navController: androidx.navigation.NavController? = null) {
    var patterns by remember { mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<List<RecurringPattern>>(REC_KEY)) }
    var filterOpen by remember { mutableStateOf(false) }
    var showExpenses by remember { mutableStateOf(true) }
    var showIncome by remember { mutableStateOf(true) }
    var showInactive by remember { mutableStateOf(false) }
    var interval by remember { mutableStateOf<String?>(null) }
    var detecting by remember { mutableStateOf(false) }
    var months by remember { mutableStateOf(false) }
    var payments by remember { mutableStateOf<Map<String, List<RecurringPayment>>>(emptyMap()) }
    var pickedMonth by remember { mutableStateOf(Calendar.getInstance().get(Calendar.MONTH) + 1) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Changes.version) {
        patterns = withContext(Dispatchers.IO) { loadRecurring() }.also { com.wimg.app.ui.components.ScreenCache.put(REC_KEY, it) }
    }

    LaunchedEffect(months, patterns) {
        val list = patterns
        if (months && list != null) {
            payments = withContext(Dispatchers.IO) {
                list.filter { it.amount < 0 }.associate { it.id to LibWimg.getRecurringPayments(it.id) }
            }
        }
    }

    val month = remember { Calendar.getInstance().let { "%04d-%02d".format(it.get(Calendar.YEAR), it.get(Calendar.MONTH) + 1) } }
    val today = remember { WimgDates.todayIso() }
    // "Nicht wiederkehrend": out of the list and the sums, back via the filter.
    val all = (patterns ?: emptyList()).filter { !it.isHidden }
    val hiddenList = (patterns ?: emptyList()).filter { it.isHidden }
    var hiddenTab by remember { mutableStateOf(false) }
    val active = all.filter { it.active == 1 }
    val expenses = active.filter { it.amount < 0 }

    // Hero: fixed costs per month (quarterly/yearly spread over their months).
    val perMonth = expenses.sumOf { abs(it.amount) * monthlyFactor(it.interval) }
    // Progress: what falls into this month, paid (seen this month) vs. still open.
    val dueThisMonth = expenses.filter { it.last_seen.startsWith(month) || (it.next_due ?: "").startsWith(month) || it.interval == "monthly" }
    val paid = dueThisMonth.filter { it.last_seen.startsWith(month) }.sumOf { abs(it.amount) }
    val open = dueThisMonth.filter { !it.last_seen.startsWith(month) }.sumOf { abs(it.amount) }

    val shown = all.filter { p ->
        (showInactive || p.active == 1) &&
            ((p.amount < 0 && showExpenses) || (p.amount > 0 && showIncome)) &&
            (interval == null || p.interval == interval)
    }
    val filterActive = !showExpenses || !showIncome || showInactive || interval != null

    BarContribution(
        chip = BarChipSpec("", filterOpen || filterActive, { filterOpen = !filterOpen }, if (months) Icons.Outlined.CalendarMonth else Icons.Outlined.Tune, L("Ansicht und Filter")),
        panel = if (filterOpen) {
            {
                val c = Wimg.colors
                BarPanel {
                    if (hiddenList.isNotEmpty()) {
                        Row(Modifier.padding(bottom = 16.dp).fillMaxWidth().clip(WimgShape.segmentOuter).background(c.neutralTint).padding(4.dp)) {
                            listOf(false to L("Aktiv (%d)", all.size), true to L("Ausgeblendet (%d)", hiddenList.size)).forEach { (h, label) ->
                                Box(
                                    Modifier.weight(1f).height(38.dp).clip(WimgShape.segmentInner)
                                        .background(if (hiddenTab == h) c.card else Color.Transparent)
                                        .clickable { hiddenTab = h },
                                    contentAlignment = Alignment.Center,
                                ) { Text(label, style = WimgType.chip, color = if (hiddenTab == h) c.text else c.text2) }
                            }
                        }
                    }
                    if (hiddenTab && hiddenList.isNotEmpty()) {
                        com.wimg.app.ui.components.WimgGroup {
                            hiddenList.forEachIndexed { i, h ->
                                if (i > 0) com.wimg.app.ui.components.RowDivider()
                                com.wimg.app.ui.components.WimgRow(
                                    h.displayName,
                                    desc = L("%s · %s", L(intervalLabel(h.interval)), amountText(abs(h.amount), showPlus = false)),
                                    trailing = {
                                        Box(
                                            Modifier.clip(CircleShape).background(c.neutralTint).pressable {
                                                scope.launch {
                                                    withContext(Dispatchers.IO) { LibWimg.setRecurringHidden(h.id, false) }
                                                    Changes.bump()
                                                    if (hiddenList.size == 1) hiddenTab = false
                                                }
                                            }.padding(horizontal = 14.dp, vertical = 9.dp),
                                        ) { Text(L("Wieder anzeigen"), style = WimgType.chip, color = c.text) }
                                    },
                                )
                            }
                        }
                        com.wimg.app.ui.components.QuietLine(L("Ausgeblendete Muster erkennt wimg nicht neu. Wieder anzeigen holt sie mit allen Zahlungen zurück."))
                        return@BarPanel
                    }
                    Text(L("Ansicht"), style = WimgType.sheetTitle.copy(fontSize = WimgType.sheetTitle.fontSize * 0.86f), color = c.text)
                    Row(Modifier.padding(top = 12.dp, bottom = 18.dp).fillMaxWidth().clip(WimgShape.segmentOuter).background(c.neutralTint).padding(4.dp)) {
                        listOf(false to L("Liste"), true to L("12 Monate")).forEach { (m, label) ->
                            Box(
                                Modifier.weight(1f).height(38.dp).clip(WimgShape.segmentInner)
                                    .background(if (months == m) c.card else Color.Transparent)
                                    .clickable { months = m },
                                contentAlignment = Alignment.Center,
                            ) { Text(label, style = WimgType.chip, color = if (months == m) c.text else c.text2) }
                        }
                    }
                    Text(L("Zeigen"), style = WimgType.label, color = c.text2, modifier = Modifier.padding(bottom = 8.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ToggleChip(L("Ausgaben"), showExpenses) { showExpenses = !showExpenses }
                        ToggleChip(L("Einnahmen"), showIncome) { showIncome = !showIncome }
                        ToggleChip(L("Inaktive"), showInactive) { showInactive = !showInactive }
                    }
                    Text(L("Intervall"), style = WimgType.label, color = c.text2, modifier = Modifier.padding(top = 18.dp, bottom = 8.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ToggleChip(L("Alle"), interval == null, check = false) { interval = null }
                        INTERVALS.filter { (id, _, _) -> all.any { it.interval == id } }.forEach { (id, label, _) ->
                            ToggleChip(L(label), interval == id, check = false) { interval = if (interval == id) null else id }
                        }
                    }
                    Row(
                        Modifier
                            .padding(top = 18.dp)
                            .fillMaxWidth()
                            .height(50.dp)
                            .pressable(enabled = !detecting) {
                                detecting = true
                                scope.launch {
                                    val n = withContext(Dispatchers.IO) { LibWimg.detectRecurring() }
                                    detecting = false
                                    filterOpen = false
                                    Changes.bump()
                                    Dock.info(__t("Erneut erkannt"), __t("%d feste Zahlungen").format(n))
                                }
                            }
                            .clip(CircleShape)
                            .border(1.dp, c.line, CircleShape),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.Refresh, contentDescription = null, tint = c.text, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(10.dp))
                        Text(if (detecting) L("Suche Muster…") else L("Erneut erkennen"), style = WimgType.button, color = c.text)
                    }
                }
            }
        } else null,
        onPanelDismiss = { filterOpen = false },
    )

    val c = Wimg.colors
    BandScreen(
        band = {
            Text(L("Fixkosten pro Monat"), style = WimgType.bandOver, color = c.bandSub)
            com.wimg.app.ui.components.RollingAmount(perMonth, WimgType.amountHero, WimgType.amountHeroCents, Color.White, Changes.version, Modifier.padding(top = 2.dp), showPlus = false)
            Text(
                if (expenses.size == 1) L("1 feste Zahlung erkannt") else L("%d feste Zahlungen erkannt", expenses.size),
                style = WimgType.desc, color = c.bandSub, modifier = Modifier.padding(top = 4.dp),
            )
            if (paid + open > 0) {
                val monthName = WimgDates.shortMonths()[Calendar.getInstance().get(Calendar.MONTH)]
                Box(Modifier.padding(top = 18.dp).fillMaxWidth().height(6.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.14f))) {
                    Box(Modifier.fillMaxHeight().fillMaxWidth((paid / (paid + open)).toFloat()).clip(CircleShape).background(Color.White))
                }
                Row(Modifier.fillMaxWidth().padding(top = 8.dp)) {
                    BandFigure(L("Bezahlt im %s.", monthName), amountText(paid, showPlus = false), Modifier.weight(1f))
                    BandFigure(L("Noch offen"), amountText(open, showPlus = false))
                }
            }
        },
    ) {
        if (patterns != null && shown.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(if (all.isEmpty()) L("Noch keine festen Zahlungen") else L("Keine Treffer"), style = WimgType.section, color = c.text)
                Text(
                    if (all.isEmpty()) L("wimg erkennt Miete, Strom und Abos, sobald ein paar Monate Umsätze da sind.") else L("Ändere den Filter, um mehr zu sehen."),
                    style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 6.dp),
                )
                if (all.isEmpty()) {
                    Text(
                        if (detecting) L("Suche Muster…") else L("Jetzt erkennen"),
                        style = WimgType.button, color = c.inkText,
                        modifier = Modifier
                            .padding(top = 18.dp)
                            .pressable(enabled = !detecting) {
                                detecting = true
                                scope.launch {
                                    withContext(Dispatchers.IO) { LibWimg.detectRecurring() }
                                    detecting = false
                                    Changes.bump()
                                }
                            }
                            .clip(CircleShape)
                            .background(c.ink)
                            .padding(horizontal = 22.dp, vertical = 13.dp),
                    )
                }
            }
            return@BandScreen
        }
        if (months) {
            YearView(expenses, payments, pickedMonth, { pickedMonth = it }) { id -> navController?.navigate("rec/$id") }
            return@BandScreen
        }
        val sections = buildList {
            INTERVALS.forEach { (id, label, _) ->
                val items = shown.filter { it.amount < 0 && it.interval == id }.sortedWith(compareBy({ dueDay(it, month) ?: 99 }, { it.displayName }))
                if (items.isNotEmpty()) add(L(label) to items)
            }
            val income = shown.filter { it.amount > 0 }
            if (income.isNotEmpty()) add(L("Einnahmen") to income)
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = barClearance())) {
            sections.forEachIndexed { si, (title, items) ->
                item(key = "s_$title") {
                    val total = items.sumOf { it.amount }
                    Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = if (si == 0) 18.dp else 26.dp, bottom = 4.dp)) {
                        Text(title, style = WimgType.chip, color = c.text2, modifier = Modifier.weight(1f))
                        Text(amountText(if (total > 0) total else abs(total), showPlus = total > 0), style = WimgType.chip, color = if (total > 0) c.pos else c.text2)
                    }
                }
                items(items, key = { it.id }) { p ->
                    PatternRow(p, month, today, last = p == items.last()) { navController?.navigate("rec/${p.id}") }
                }
            }
        }
    }
}

/** Day of this month the payment was made or is due, or null. */
private fun dueDay(p: RecurringPattern, month: String): Int? = when {
    p.last_seen.startsWith(month) -> p.last_seen.takeLast(2).toIntOrNull()
    (p.next_due ?: "").startsWith(month) -> p.next_due!!.takeLast(2).toIntOrNull()
    else -> null
}

internal fun daysUntil(date: String): Int? {
    val d = WimgDates.parse(date) ?: return null
    val t = WimgDates.parse(WimgDates.todayIso()) ?: return null
    return ((d.timeInMillis - t.timeInMillis) / 86_400_000L).toInt()
}

@Composable
private fun BandFigure(label: String, value: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.Bottom) {
        Text(label, style = WimgType.desc, color = Wimg.colors.bandSub)
        Spacer(Modifier.width(6.dp))
        Text(value, style = WimgType.amountStat, color = Color.White)
    }
}

@Composable
private fun PatternRow(p: RecurringPattern, month: String, today: String, last: Boolean, onClick: () -> Unit) {
    val c = Wimg.colors
    val paidNow = p.last_seen.startsWith(month)
    val income = p.amount > 0
    val day = dueDay(p, month)
    val shortMonth = WimgDates.shortMonths()[month.takeLast(2).toInt() - 1]
    val inactive = p.active != 1
    // Compare what was actually paid (not a fixed amount the user set), and
    // only while libwimg reports a change (gone after "Stimmt, neuer Preis").
    val paid = p.detected_amount ?: p.amount
    val sub = when {
        inactive -> L("inaktiv · zuletzt %s", WimgDates.short(p.last_seen))
        // price_change is signed (amount − prev), so compare sizes: an expense
        // going from −16,99 to −21,99 is a rise even though the diff is negative.
        !income && p.price_change != null && p.prev_amount != null && abs(paid) - abs(p.prev_amount) > 0.5 ->
            L("Preis gestiegen · vorher %s", amountText(abs(p.prev_amount), showPlus = false))
        !income && p.price_change != null && p.prev_amount != null && abs(p.prev_amount) - abs(paid) > 0.5 ->
            L("Preis gesunken · vorher %s", amountText(abs(p.prev_amount), showPlus = false))
        else -> {
            val next = p.next_due?.let { daysUntil(it) }
            val label = L(intervalLabel(p.interval))
            when {
                income && !paidNow && next != null && next >= 0 -> L("%s · erwartet in %d Tagen", label, next)
                next != null && next > 0 && paidNow -> L("%s · nächste in %d Tagen", label, next)
                next != null && next > 0 -> L("%s · in %d Tagen", label, next)
                next != null && next == 0 -> L("%s · heute fällig", label)
                next != null && next < 0 && !paidNow -> L("%s · überfällig seit %s", label, WimgDates.short(p.next_due!!))
                else -> label
            }
        }
    }
    Column(Modifier.clickable(onClick = onClick)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 66.dp).padding(start = 12.dp, end = 20.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.width(52.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                if (day != null) {
                    Text("$day.", style = WimgType.amountRow, color = if (inactive) c.text3 else c.text)
                    Text("$shortMonth.", style = WimgType.caption.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Normal), color = c.text2)
                } else {
                    Text("–", style = WimgType.amountRow, color = c.text3)
                }
            }
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f)) {
                Text(p.displayName, style = WimgType.rowTitle, color = if (inactive) c.text3 else c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(sub, style = WimgType.desc, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
            }
            Spacer(Modifier.width(10.dp))
            Text(
                amountText(if (income) p.amount else abs(p.amount), showPlus = income),
                style = WimgType.amountRow, color = when { inactive -> c.text3; income -> c.pos; else -> c.text },
            )
            Spacer(Modifier.width(12.dp))
            StatusDot(paid = paidNow, income = income)
        }
        if (!last) HorizontalDivider(thickness = 1.dp, color = c.line)
    }
}

@Composable
private fun StatusDot(paid: Boolean, income: Boolean) {
    val c = Wimg.colors
    val desc = if (paid) L("bezahlt") else L("offen")
    if (paid) {
        Box(
            Modifier.size(26.dp).clip(CircleShape).background(if (income) c.pos else c.ink),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Outlined.Check, contentDescription = desc, tint = c.inkText, modifier = Modifier.size(15.dp)) }
    } else {
        Canvas(Modifier.size(26.dp)) {
            drawCircle(c.text3, radius = size.minDimension / 2 - 1.dp.toPx(), style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f, 4f))))
        }
    }
}

@Composable
private fun ToggleChip(label: String, on: Boolean, check: Boolean = true, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(
        Modifier
            .height(40.dp)
            .clip(CircleShape)
            .background(if (on) c.ink else Color.Transparent)
            .border(1.dp, if (on) c.ink else c.line, CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (on && check) {
            Icon(Icons.Outlined.Check, contentDescription = null, tint = c.inkText, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(label, style = WimgType.rowTitle, color = if (on) c.inkText else c.text)
    }
}

/** Does a pattern fall into [month] (1–12) of a future month, judged from its next due date? */
private fun dueInMonth(p: RecurringPattern, year: Int, month: Int): Boolean {
    val next = p.next_due?.let { WimgDates.parse(it) } ?: return p.interval == "monthly" || p.interval == "weekly"
    val diff = (year - next.get(Calendar.YEAR)) * 12 + (month - (next.get(Calendar.MONTH) + 1))
    if (diff < 0) return false
    return when (p.interval) {
        "weekly", "monthly" -> true
        "quarterly" -> diff % 3 == 0
        "annual" -> diff % 12 == 0
        else -> true
    }
}

/**
 * 12-month view: what was actually paid per month this year (from the
 * patterns' real payments), and the forecast for the months still to come
 * (dashed). Tapping a month lists its payments below.
 */
@Composable
private fun YearView(
    expenses: List<RecurringPattern>,
    payments: Map<String, List<RecurringPayment>>,
    picked: Int,
    onPick: (Int) -> Unit,
    onOpen: (String) -> Unit,
) {
    val c = Wimg.colors
    val now = Calendar.getInstance()
    val year = now.get(Calendar.YEAR)
    val curMonth = now.get(Calendar.MONTH) + 1
    val names = WimgDates.shortMonths()
    val prefix = { m: Int -> "%04d-%02d".format(year, m) }
    val paidIn = { m: Int ->
        expenses.flatMap { p -> payments[p.id].orEmpty().filter { it.date.startsWith(prefix(m)) }.map { p to it } }
    }
    val expectedIn = { m: Int ->
        expenses.filter { it.active == 1 && dueInMonth(it, year, m) && (m > curMonth || payments[it.id].orEmpty().none { pay -> pay.date.startsWith(prefix(m)) }) }
    }
    val paidTotal = (1..curMonth).sumOf { m -> paidIn(m).sumOf { abs(it.second.amount) } }
    val expectedTotal = (curMonth..12).sumOf { m -> expectedIn(m).sumOf { abs(it.amount) } }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 18.dp, bottom = barClearance())) {
        item {
            Row(verticalAlignment = Alignment.Bottom) {
                Text("$year", style = WimgType.section.copy(fontSize = WimgType.section.fontSize * 1.2f), color = c.text, modifier = Modifier.weight(1f))
                Text(L("%s bezahlt · %s erwartet", amountText(paidTotal, showPlus = false), amountText(expectedTotal, showPlus = false)), style = WimgType.desc, color = c.text2)
            }
            Spacer(Modifier.height(14.dp))
            for (row in 0 until 4) {
                Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (col in 0 until 3) {
                        val m = row * 3 + col + 1
                        val future = m > curMonth
                        val sum = if (future) expectedIn(m).sumOf { abs(it.amount) } else paidIn(m).sumOf { abs(it.second.amount) }
                        val sel = m == picked
                        Column(
                            Modifier
                                .weight(1f)
                                .clip(WimgShape.group)
                                .background(if (sel) c.ink else if (future) Color.Transparent else c.card)
                                .then(
                                    if (sel) Modifier
                                    else Modifier.border(1.dp, c.line, WimgShape.group),
                                )
                                .clickable { onPick(m) }
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                        ) {
                            Text(names[m - 1], style = WimgType.desc.copy(fontWeight = FontWeight.Medium), color = if (sel) c.inkText else c.text2)
                            Text(
                                if (sum > 0.004) amountText(sum, showPlus = false) else "–",
                                style = WimgType.amountRow,
                                color = when { sel -> c.inkText; future -> c.text3; else -> c.text },
                                modifier = Modifier.padding(top = 2.dp), maxLines = 1,
                            )
                        }
                    }
                }
            }
        }
        val paid = paidIn(picked).sortedBy { it.second.date }
        val expected = expectedIn(picked).filter { picked >= curMonth }
            .sortedBy { p -> p.next_due?.let { WimgDates.parse(it) }?.get(Calendar.DAY_OF_MONTH) ?: 99 }
        val monthTotal = paid.sumOf { abs(it.second.amount) } + expected.sumOf { abs(it.amount) }
        item {
            Row(Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 4.dp)) {
                Text(WimgDates.months()[picked - 1], style = WimgType.chip, color = c.text2, modifier = Modifier.weight(1f))
                Text(amountText(monthTotal, showPlus = false), style = WimgType.chip, color = c.text2)
            }
        }
        items(paid, key = { it.second.id }) { (p, pay) ->
            YearRow(pay.date.takeLast(2).toIntOrNull(), names[picked - 1], p.displayName, L("%s · bezahlt", L(intervalLabel(p.interval))), abs(pay.amount), future = false) { onOpen(p.id) }
        }
        items(expected, key = { "e_" + it.id }) { p ->
            val day = p.next_due?.let { WimgDates.parse(it) }?.get(Calendar.DAY_OF_MONTH)
            YearRow(day, names[picked - 1], p.displayName, L("%s · erwartet", L(intervalLabel(p.interval))), abs(p.amount), future = true) { onOpen(p.id) }
        }
    }
}

@Composable
private fun YearRow(day: Int?, monthName: String, name: String, sub: String, amount: Double, future: Boolean, onClick: () -> Unit) {
    val c = Wimg.colors
    Column(Modifier.clickable(onClick = onClick)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 62.dp).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.width(44.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(day?.let { "$it." } ?: "–", style = WimgType.amountRow, color = if (future) c.text3 else c.text)
                Text("$monthName.", style = WimgType.caption.copy(fontWeight = FontWeight.Normal), color = c.text2)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(name, style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(sub, style = WimgType.desc, color = c.text2)
            }
            Text(amountText(amount, showPlus = false), style = WimgType.amountRow, color = if (future) c.text2 else c.text)
        }
        HorizontalDivider(thickness = 1.dp, color = c.line)
    }
}
