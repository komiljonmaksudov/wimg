package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.TrendingDown
import androidx.compose.material.icons.automirrored.outlined.TrendingUp
import androidx.compose.material.icons.outlined.Check
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.models.RecurringPayment
import com.wimg.app.models.RecurringPattern
import com.wimg.app.ui.components.Amount
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.amountText
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.DockRow
import com.wimg.app.ui.components.DockKind
import com.wimg.app.ui.components.pressable
import com.wimg.app.i18n.__t
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.height
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.theme.categoryBar
import kotlin.math.abs

@Composable
fun RecurringDetailScreen(id: String, navController: NavController?) {
    var pattern by remember(id) {
        mutableStateOf(
            com.wimg.app.ui.components.ScreenCache.get<List<RecurringPattern>>(REC_KEY)?.firstOrNull { it.id == id }
                ?: runCatching { LibWimg.ifFree { LibWimg.getRecurring() }?.firstOrNull { it.id == id } }.getOrNull(),
        )
    }
    // Small query (one pattern's payments): read right away so the page is
    // complete on its first frame instead of filling in a moment later.
    var payments by remember(id) { mutableStateOf(runCatching { LibWimg.ifFree { LibWimg.getRecurringPayments(id) } }.getOrNull() ?: emptyList()) }

    LaunchedEffect(id, Changes.version) {
        val (p, list) = withContext(Dispatchers.IO) {
            LibWimg.getRecurring().firstOrNull { it.id == id } to LibWimg.getRecurringPayments(id)
        }
        pattern = p; payments = list
    }

    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var editOpen by remember { mutableStateOf(false) }
    val p0 = pattern
    BarContribution(
        chip = null,
        panel = if (editOpen && p0 != null) { { EditPatternPanel(p0, onCancel = { editOpen = false }) { name, cat, interval, fixed ->
            editOpen = false
            scope.launch {
                withContext(Dispatchers.IO) { LibWimg.editRecurring(p0.id, name, cat, interval, fixed) }
                Changes.bump()
                Dock.info(__t("Gesichert"), name ?: p0.merchant)
            }
        } } } else null,
        onPanelDismiss = { editOpen = false },
        detail = DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = if (p0 != null) L("Nicht wiederkehrend") else null,
            actionIcon = Icons.Outlined.Block,
            actionDanger = true,
            onAction = {
                val p = p0 ?: return@DetailBarSpec
                // No confirmation (board 26/13): back to the list, undo on the bar.
                scope.launch {
                    withContext(Dispatchers.IO) { LibWimg.setRecurringHidden(p.id, true) }
                    Changes.bump()
                    navController?.popBackStack()
                    Dock.undo(__t("Nicht mehr wiederkehrend"), p.displayName) {
                        scope.launch { withContext(Dispatchers.IO) { LibWimg.setRecurringHidden(p.id, false) }; Changes.bump() }
                    }
                }
            },
            backLabel = L("Wiederkehrend"),
            extraIcon = if (p0 != null) Icons.Outlined.Edit else null,
            extraLabel = L("Bearbeiten"),
            onExtra = { editOpen = !editOpen },
        ),
    )

    val c = Wimg.colors
    val p = pattern
    if (p == null) {
        BandScreen(band = { Text(L("Wiederkehrend"), style = WimgType.title, color = Color.White) }) {}
        return
    }
    val income = p.amount > 0
    val amount = abs(p.amount)
    val day = p.last_seen.takeLast(2).toIntOrNull()
    // Price change from the payments that count (one-offs set aside): newest
    // vs. the one before it, unless the user already said "Stimmt, neuer Preis".
    val counted = payments.filter { !it.oneoff }
    val newestPay = counted.getOrNull(0)
    val newest = newestPay?.let { abs(it.amount) }
    val before = counted.getOrNull(1)?.let { abs(it.amount) }
    val changed = newest != null && before != null && abs(newest - before) > 0.004 && p.price_change != null

    BandScreen(
        band = {
            Text(
                listOfNotNull(L(intervalLabel(p.interval)), day?.let { L("am %d.", it) }).joinToString(" · "),
                style = WimgType.bandOver, color = c.bandSub,
            )
            Amount(amount, WimgType.amountHero, WimgType.amountHeroCents, if (income) c.bandPos else Color.White, Modifier.padding(top = 2.dp), showPlus = income)
            Text(p.displayName, style = WimgType.title.copy(fontSize = WimgType.title.fontSize * 0.92f), color = Color.White, modifier = Modifier.padding(top = 2.dp))
        },
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp, bottom = barClearance())) {
            if (changed && !income) {
                item {
                    val up = newest!! > before!!
                    val diff = newest - before // per payment
                    val perMonth = diff * monthlyFactor(p.interval)
                    Column(Modifier.fillMaxWidth().clip(WimgShape.group).background(if (up) c.warnBg else c.accentSoft).padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            if (up) Icons.AutoMirrored.Outlined.TrendingUp else Icons.AutoMirrored.Outlined.TrendingDown,
                            contentDescription = null, tint = if (up) c.warn else c.accent, modifier = Modifier.size(22.dp),
                        )
                        Spacer(Modifier.width(14.dp))
                        Column {
                            Text(
                                L(if (up) "Preis gestiegen: %s → %s" else "Preis gesunken: %s → %s", amountText(before, showPlus = false), amountText(newest, showPlus = false)),
                                style = WimgType.chip.copy(fontSize = WimgType.chip.fontSize * 1.07f), color = c.text,
                            )
                            Text(
                                L("%s im Monat · %s im Jahr", amountText(perMonth), amountText(perMonth * 12)),
                                style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 2.dp),
                            )
                        }
                    }
                    // Board 26/18: a jump that may be a one-off invoice, decided right here.
                    val pay = newestPay!!
                    Box(
                        Modifier.padding(top = 14.dp).fillMaxWidth().heightIn(min = 48.dp).clip(CircleShape).background(c.ink).pressable {
                            scope.launch {
                                // "Preis bleibt …": the price before it is settled, so the
                                // card doesn't move on to an older change.
                                withContext(Dispatchers.IO) { LibWimg.setRecurringOneoff(p.id, pay.id, true); LibWimg.acceptRecurringPrice(p.id) }
                                Changes.bump()
                                Dock.undo(__t("%s einmalig").format(amountText(abs(pay.amount), showPlus = false)), __t("Preis bleibt %s").format(amountText(before, showPlus = false))) {
                                    scope.launch { withContext(Dispatchers.IO) { LibWimg.setRecurringOneoff(p.id, pay.id, false) }; Changes.bump() }
                                }
                            }
                        },
                        contentAlignment = Alignment.Center,
                    ) { Text(L("Einmalige Zahlung, kein neuer Preis"), style = WimgType.button, color = c.inkText) }
                    Box(
                        Modifier.padding(top = 8.dp).fillMaxWidth().heightIn(min = 48.dp).clip(CircleShape).border(1.dp, c.line, CircleShape).pressable {
                            scope.launch {
                                withContext(Dispatchers.IO) { LibWimg.acceptRecurringPrice(p.id) }
                                Changes.bump()
                                Dock.info(__t("Neuer Preis übernommen"), amountText(newest, showPlus = false))
                            }
                        },
                        contentAlignment = Alignment.Center,
                    ) { Text(L("Stimmt, neuer Preis"), style = WimgType.button, color = c.text) }
                    }
                }
            }
            item {
                Row(Modifier.fillMaxWidth().padding(top = if (changed && !income) 18.dp else 0.dp)) {
                    val next = p.next_due
                    Stat(
                        L("Nächste"),
                        next?.let { WimgDates.short(it) } ?: "–",
                        next?.let { daysUntil(it) }?.let { d ->
                            when {
                                d > 1 -> L("in %d Tagen", d)
                                d == 1 -> L("morgen")
                                d == 0 -> L("heute")
                                else -> L("überfällig")
                            }
                        },
                        Modifier.weight(1f),
                    )
                    Stat(L("Pro Jahr"), amountText(amount * 12 * monthlyFactor(p.interval), showPlus = false), null, Modifier.weight(1f))
                    Stat(
                        L("Bisher"),
                        amountText(counted.sumOf { abs(it.amount) }, showPlus = false),
                        if (counted.size == 1) L("1 Zahlung") else L("%d Zahlungen", counted.size),
                        Modifier.weight(1f),
                    )
                }
                HorizontalDivider(Modifier.padding(top = 18.dp), thickness = 1.dp, color = c.line)
                Text(L("Verlauf"), style = WimgType.chip, color = c.text2, modifier = Modifier.padding(top = 22.dp, bottom = 6.dp))
            }
            itemsIndexed(payments, key = { _, pay -> pay.id }) { _, pay ->
                val ci = counted.indexOf(pay)
                val older = if (ci >= 0) counted.getOrNull(ci + 1) else null
                val note = when {
                    pay.oneoff -> L("Einzelzahlung · zählt hier nicht")
                    older == null || abs(abs(pay.amount) - abs(older.amount)) < 0.005 -> null
                    ci == 0 -> if (changed) L("neuer Preis?") else L("neuer Preis")
                    else -> L("Preis geändert")
                }
                Column {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 60.dp).then(
                            // A one-off can be taken back: "zählt doch dazu".
                            if (pay.oneoff) Modifier.pressable {
                                Dock.show(DockRow(DockKind.Prompt, __t("Gehört diese Zahlung dazu?"), amountText(pay.amount), __t("Ja, zählt dazu"), {
                                    scope.launch { withContext(Dispatchers.IO) { LibWimg.setRecurringOneoff(p.id, pay.id, false) }; Changes.bump() }
                                }))
                            } else Modifier,
                        ),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (pay.oneoff) {
                            androidx.compose.foundation.Canvas(Modifier.size(26.dp)) {
                                drawCircle(c.text3, style = androidx.compose.ui.graphics.drawscope.Stroke(1.5.dp.toPx(), pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(5f, 5f))))
                            }
                        } else Box(Modifier.size(26.dp).clip(CircleShape).background(if (income) c.pos else c.ink), contentAlignment = Alignment.Center) {
                            Icon(Icons.Outlined.Check, contentDescription = L("bezahlt"), tint = c.inkText, modifier = Modifier.size(15.dp))
                        }
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(WimgDates.full(pay.date), style = WimgType.body, color = if (pay.oneoff) c.text2 else c.text)
                            if (note != null) Text(note, style = WimgType.desc, color = if (pay.oneoff) c.text2 else c.warn)
                        }
                        Text(
                            amountText(pay.amount),
                            style = WimgType.amountRow.copy(textDecoration = if (pay.oneoff) androidx.compose.ui.text.style.TextDecoration.LineThrough else null),
                            color = if (pay.oneoff) c.text2 else if (income) c.pos else c.text,
                        )
                    }
                    HorizontalDivider(thickness = 1.dp, color = c.line)
                }
            }
        }
    }
}

@Composable
private fun Stat(label: String, value: String, sub: String?, modifier: Modifier) {
    val c = Wimg.colors
    Column(modifier) {
        Text(label, style = WimgType.desc, color = c.text2)
        Text(value, style = WimgType.amountStat.copy(fontSize = WimgType.amountStat.fontSize * 1.1f, fontWeight = FontWeight.ExtraBold), color = c.text, modifier = Modifier.padding(top = 2.dp))
        if (sub != null) Text(sub, style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 2.dp))
    }
}

private val EDIT_INTERVALS = listOf("weekly" to "Wöch.", "monthly" to "Monatl.", "quarterly" to "Viertelj.", "annual" to "Jährl.")

/** Board 26/15–16: name, category, rhythm, automatic or fixed amount. */
@Composable
private fun EditPatternPanel(p: RecurringPattern, onCancel: () -> Unit, onSave: (name: String?, category: Int?, interval: String?, fixedCents: Long?) -> Unit) {
    val c = Wimg.colors
    var name by remember { mutableStateOf(p.displayName) }
    var category by remember { mutableStateOf(p.category) }
    var interval by remember { mutableStateOf(p.interval) }
    var fixed by remember { mutableStateOf(p.fixed != 0) }
    var fixedText by remember { mutableStateOf(if (p.fixed != 0) "%.2f".format(java.util.Locale.GERMANY, abs(p.amount)) else "") }
    var pickCategory by remember { mutableStateOf(false) }
    if (pickCategory) {
        CategoryPanel(category) { category = it; pickCategory = false }
        return
    }
    val detected = abs(p.detected_amount ?: p.amount)
    com.wimg.app.ui.components.BarPanel {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(L("Bearbeiten"), style = WimgType.sheetTitle, color = c.text)
            Spacer(Modifier.width(10.dp))
            Text(L("erkannt als „%s“", p.merchant), style = WimgType.desc, color = c.text2, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
        }
        Spacer(Modifier.height(12.dp))
        Column(Modifier.fillMaxWidth().clip(WimgShape.group).border(1.dp, c.line, WimgShape.group).padding(horizontal = 16.dp, vertical = 10.dp)) {
            Text(L("Name"), style = WimgType.desc, color = c.text2)
            androidx.compose.foundation.text.BasicTextField(
                value = name, onValueChange = { name = it.take(60) }, singleLine = true,
                textStyle = WimgType.rowTitle.copy(color = c.text), cursorBrush = androidx.compose.ui.graphics.SolidColor(c.accent),
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
            )
        }
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier.fillMaxWidth().clip(WimgShape.group).border(1.dp, c.line, WimgShape.group).pressable { pickCategory = true }.padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(L("Kategorie"), style = WimgType.desc, color = c.text2)
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
                    Box(Modifier.size(9.dp).clip(CircleShape).background(c.categoryBar(category)))
                    Spacer(Modifier.width(8.dp))
                    Text(L(WimgCategory.fromId(category).label), style = WimgType.rowTitle, color = c.text)
                }
            }
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = c.text3)
        }
        Text(L("Rhythmus"), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 12.dp, bottom = 6.dp))
        Row(Modifier.fillMaxWidth().clip(WimgShape.segmentOuter).background(c.neutralTint).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            EDIT_INTERVALS.forEach { (key, label) ->
                val on = interval == key
                Box(
                    Modifier.weight(1f).height(38.dp).clip(WimgShape.segmentInner).background(if (on) c.card else Color.Transparent).pressable { interval = key },
                    contentAlignment = Alignment.Center,
                ) { Text(L(label), style = WimgType.chip, color = if (on) c.text else c.text2) }
            }
        }
        Spacer(Modifier.height(10.dp))
        com.wimg.app.ui.components.WimgGroup {
            listOf(false, true).forEachIndexed { i, isFixed ->
                if (i > 0) com.wimg.app.ui.components.RowDivider()
                com.wimg.app.ui.components.WimgRow(
                    if (isFixed) L("Fester Betrag") else L("Automatisch"),
                    desc = if (isFixed) L("z. B. wenn die Rechnung schwankt") else L("Wie die letzte Zahlung: %s", amountText(detected, showPlus = false)),
                    onClick = { fixed = isFixed },
                    leading = {
                        Box(Modifier.size(22.dp).clip(CircleShape).border(2.dp, if (fixed == isFixed) c.accent else c.text3, CircleShape), contentAlignment = Alignment.Center) {
                            if (fixed == isFixed) Box(Modifier.size(10.dp).clip(CircleShape).background(c.accent))
                        }
                    },
                )
            }
        }
        if (fixed) {
            androidx.compose.foundation.text.BasicTextField(
                value = fixedText, onValueChange = { fixedText = it.filter { ch -> ch.isDigit() || ch == ',' || ch == '.' }.take(10) }, singleLine = true,
                textStyle = WimgType.amountLarge.copy(color = c.text),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(c.accent),
                modifier = Modifier.padding(top = 10.dp).fillMaxWidth().clip(WimgShape.group).border(1.dp, c.accent, WimgShape.group).padding(horizontal = 16.dp, vertical = 12.dp),
                decorationBox = { inner -> Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.weight(1f)) { if (fixedText.isEmpty()) Text("0,00", style = WimgType.amountLarge, color = c.text3); inner() }; Text("€", style = WimgType.amountLarge, color = c.text2) } },
            )
        }
        com.wimg.app.ui.components.QuietLine(L("Vergangene Zahlungen bleiben, wie sie gebucht sind."))
        Row(Modifier.padding(top = 12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.weight(1f).height(50.dp).pressable(onClick = onCancel).clip(CircleShape).border(1.dp, c.line, CircleShape), contentAlignment = Alignment.Center) {
                Text(L("Abbrechen"), style = WimgType.button, color = c.text)
            }
            Box(
                Modifier.weight(1f).height(50.dp).pressable {
                    val cents = fixedText.replace(".", "").replace(',', '.').toDoubleOrNull()?.let { kotlin.math.round(it * 100).toLong() }
                    val sign = if (p.amount < 0) -1 else 1
                    onSave(
                        name.trim().takeIf { it.isNotEmpty() && it != p.merchant },
                        category.takeIf { it != (p.category) || true },
                        interval,
                        if (fixed && cents != null && cents > 0) sign * cents else null,
                    )
                }.clip(CircleShape).background(c.ink),
                contentAlignment = Alignment.Center,
            ) { Text(L("Sichern"), style = WimgType.button, color = c.inkText) }
        }
    }
}
