package com.wimg.app.ui.screens

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.automirrored.outlined.Backspace
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
fun ManualEntryScreen(navController: NavController?) {
    val c = Wimg.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var expense by remember { mutableStateOf(true) }
    var digits by remember { mutableStateOf("") } // amount as typed, e.g. "18,4"
    var amountStep by remember { mutableStateOf(true) }
    var description by remember { mutableStateOf("") }
    var category by remember { mutableIntStateOf(-1) }
    var account by remember { mutableStateOf(CASH_ACCOUNT) }
    var dayOffset by remember { mutableIntStateOf(0) } // 0 = heute, 1 = gestern, …
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
                LibWimg.addManualTransaction(iso, description.trim(), if (expense) -cents else cents, if (category < 0) 0 else category, account)
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
            "date" -> { { ChoicePanel(L("Datum"), (0..6).map { dayLabel(it) }, dayOffset) { dayOffset = it; panel = null } } }
            else -> null
        },
        onPanelDismiss = { panel = null },
        detail = DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = if (amountStep) L("Weiter") else L("Speichern"),
            actionIcon = null,
            onAction = { if (amountStep) { if (cents > 0) amountStep = false } else save() },
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
        Text(
            (if (expense) "−" else "+") + formatTyped(digits) + " €",
            style = WimgType.amountHero, color = if (cents == 0L) c.bandSub else Color.White,
            modifier = Modifier.padding(top = 14.dp).pressable(label = L("Betrag ändern")) { amountStep = true },
        )
    }) {
        Column(Modifier.padding(16.dp)) {
            WimgGroup {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L("Beschreibung"), style = WimgType.body, color = c.text2)
                    Spacer(Modifier.width(16.dp))
                    BasicTextField(
                        value = description, onValueChange = { description = it.take(120) }, singleLine = true,
                        textStyle = WimgType.rowTitle.copy(color = c.text, textAlign = TextAlign.End),
                        cursorBrush = SolidColor(c.accent),
                        modifier = Modifier.weight(1f).pressable { amountStep = false },
                        decorationBox = { inner ->
                            Box(contentAlignment = Alignment.CenterEnd) {
                                if (description.isEmpty()) Text(L("z. B. Wochenmarkt"), style = WimgType.rowTitle, color = c.text3)
                                inner()
                            }
                        },
                    )
                }
                RowDivider()
                WimgRow(L("Kategorie"), chevron = true, onClick = { amountStep = false; panel = "category" }, trailing = {
                    if (category < 0) Text(L("Wählen"), style = WimgType.body, color = c.text2)
                    else {
                        Box(Modifier.size(9.dp).clip(CircleShape).background(c.categoryBar(category)))
                        Spacer(Modifier.width(8.dp))
                        Text(L(WimgCategory.fromId(category).label), style = WimgType.rowTitle, color = c.text)
                    }
                })
                RowDivider()
                WimgRow(L("Konto"), chevron = true, onClick = { amountStep = false; panel = "account" }, trailing = { Text(account, style = WimgType.rowTitle, color = c.text, maxLines = 1) })
                RowDivider()
                WimgRow(L("Datum"), chevron = true, onClick = { amountStep = false; panel = "date" }, trailing = { Text(dayLabel(dayOffset), style = WimgType.rowTitle, color = c.text) })
            }
            QuietLine(L("Von Hand angelegte Umsätze werden nie mit Bankdaten überschrieben. „Bargeld“ ist ein eigenes Konto ohne Bank."))
        }
        if (amountStep) {
            Spacer(Modifier.weight(1f))
            Keypad { key ->
                digits = when (key) {
                    "⌫" -> digits.dropLast(1)
                    "," -> if (digits.contains(',')) digits else (if (digits.isEmpty()) "0," else "$digits,")
                    else -> {
                        val dec = digits.substringAfter(',', "")
                        if (digits.contains(',') && dec.length >= 2) digits
                        else if (!digits.contains(',') && digits.length >= 7) digits
                        else if (digits == "0") key else digits + key
                    }
                }
            }
        }
    }
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

/** Number pad for the amount (board 22/01). */
@Composable
private fun Keypad(onKey: (String) -> Unit) {
    val c = Wimg.colors
    Column(
        Modifier.fillMaxWidth().background(c.neutralTint).padding(horizontal = 10.dp, vertical = 10.dp).padding(bottom = 96.dp).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf(",", "0", "⌫")).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { k ->
                    Box(
                        Modifier.weight(1f).height(54.dp).clip(WimgShape.button).background(c.card).pressable(label = if (k == "⌫") L("Löschen") else k) { onKey(k) },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (k == "⌫") Icon(Icons.AutoMirrored.Outlined.Backspace, contentDescription = null, tint = c.text, modifier = Modifier.size(22.dp))
                        else Text(k, style = WimgType.amountLarge, color = c.text)
                    }
                }
            }
        }
    }
}
