package com.wimg.app.ui.screens

import com.wimg.app.ui.components.QuietLine
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
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
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.WimgToggle
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import com.wimg.app.ui.theme.categoryBar
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Close
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Category picker order from the design; 0 is "Unkategorisiert", 255 "Andere". */
private val PICKER_ORDER = listOf(
    WimgCategory.GROCERIES, WimgCategory.DINING, WimgCategory.TRANSPORT, WimgCategory.HOUSING,
    WimgCategory.UTILITIES, WimgCategory.ENTERTAINMENT, WimgCategory.SHOPPING, WimgCategory.HEALTH,
    WimgCategory.INSURANCE, WimgCategory.INCOME, WimgCategory.TRANSFER, WimgCategory.CASH,
    WimgCategory.SUBSCRIPTIONS, WimgCategory.TRAVEL, WimgCategory.EDUCATION, WimgCategory.OTHER,
    WimgCategory.UNCATEGORIZED,
)

private enum class DetailPanel { None, Category, More, Delete }

@Composable
fun TransactionDetailScreen(id: String, navController: NavController?) {
    // Start from the list's cached row, so the page is complete on its first frame.
    val cached = remember(id) {
        com.wimg.app.ui.components.ScreenCache.get<TxData>(txKey(null))?.let { d ->
            (d.transactions.firstOrNull { it.id == id } ?: d.pending.firstOrNull { it.id == id })?.let { t -> t to d.accounts.firstOrNull { it.id == t.account } }
        }
    }
    var tx by remember { mutableStateOf(cached?.first) }
    var account by remember { mutableStateOf(cached?.second) }
    var panel by remember { mutableStateOf(DetailPanel.None) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current

    // Not yet booked: shown read-only (the bank may still change or drop it).
    // Known from the cached list too, or the first frame showed the booked
    // layout (switch, "Kategorie wählen") and flipped a frame later.
    var isPending by remember {
        mutableStateOf(com.wimg.app.ui.components.ScreenCache.get<TxData>(txKey(null))?.pending?.any { it.id == id } == true)
    }
    LaunchedEffect(id, Changes.version) {
        val (t, a, p) = withContext(Dispatchers.IO) {
            val booked = LibWimg.getTransactions().firstOrNull { it.id == id }
            val t = booked ?: LibWimg.getPending(null).firstOrNull { it.id == id }
            Triple(t, LibWimg.getAccounts().firstOrNull { it.id == t?.account }, booked == null && t != null)
        }
        tx = t; account = a; isPending = p
    }

    val t = tx
    BarContribution(
        chip = null,
        panel = when {
            t == null -> null
            panel == DetailPanel.Category && !isPending -> { { CategoryPanel(t.category) { cat -> applyCategory(t, cat); panel = DetailPanel.None } } }
            panel == DetailPanel.More -> {
                {
                    MorePanel(
                        onCopy = {
                            clipboard.setText(AnnotatedString(t.description))
                            panel = DetailPanel.None
                            Dock.info(__t("Text kopiert"))
                        },
                        onSearch = { panel = DetailPanel.None; navController?.navigate("search?q=" + android.net.Uri.encode(searchTerm(t.displayTitle))) },
                        onEdit = if (t.manual) ({ panel = DetailPanel.None; navController?.navigate("manual?id=" + android.net.Uri.encode(t.id)) }) else null,
                        onDelete = if (t.manual) ({ panel = DetailPanel.Delete }) else null,
                    )
                }
            }
            panel == DetailPanel.Delete -> {
                {
                    DeletePanel(t.displayTitle, onCancel = { panel = DetailPanel.None }) {
                        panel = DetailPanel.None
                        scope.launch {
                            val ok = withContext(Dispatchers.IO) { LibWimg.deleteTransaction(t.id) }
                            if (ok) {
                                Changes.bump()
                                Dock.info(__t("Umsatz gelöscht"), t.displayTitle)
                                navController?.popBackStack()
                            } else Dock.error(__t("Nicht gelöscht"), __t("Bitte versuch es noch einmal."))
                        }
                    }
                }
            }
            else -> null
        },
        onPanelDismiss = { panel = DetailPanel.None },
        detail = DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = if (isPending) null else L("Kategorie wählen"),
            actionIcon = Icons.Outlined.LocalOffer,
            onAction = { panel = if (panel == DetailPanel.Category) DetailPanel.None else DetailPanel.Category },
            onMore = { panel = if (panel == DetailPanel.More) DetailPanel.None else DetailPanel.More },
        ),
    )

    val c = Wimg.colors
    if (t == null) {
        BandScreen(band = { Text(L("Umsatz"), style = WimgType.title, color = Color.White) }) {}
        return
    }
    val wc = WimgCategory.fromId(t.category)
    val accountName = account?.let { it.bank.ifBlank { it.name } } ?: t.account.orEmpty()

    BandScreen(
        band = {
            Text(
                listOfNotNull(if (isPending) L("Vorgemerkt") else null, WimgDates.full(t.date), t.kind?.takeIf { it.isNotBlank() }?.let { L(it) }).joinToString(" · "),
                style = WimgType.bandOver, color = c.bandSub,
            )
            Amount(
                t.amount, WimgType.amountHero, WimgType.amountHeroCents,
                if (t.amount > 0) c.bandPos else Color.White, Modifier.padding(top = 2.dp),
            )
            if (accountName.isNotBlank()) Text(accountName, style = WimgType.desc, color = c.bandSub, modifier = Modifier.padding(top = 4.dp))
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, top = 6.dp, bottom = barClearance())) {
            InfoRow(L("Datum")) { Text(WimgDates.full(t.date), style = WimgType.body.copy(fontWeight = FontWeight.Medium), color = c.text) }
            InfoRow(L("Kategorie")) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clip(WimgShape.button).clickable(enabled = !isPending) { panel = DetailPanel.Category }.padding(4.dp)) {
                    Box(Modifier.size(9.dp).clip(CircleShape).background(c.categoryBar(t.category)))
                    Spacer(Modifier.width(8.dp))
                    Text(L(wc.label), style = WimgType.body.copy(fontWeight = FontWeight.Medium), color = c.text)
                }
            }
            if (accountName.isNotBlank()) {
                InfoRow(L("Konto")) { Text(accountName, style = WimgType.body.copy(fontWeight = FontWeight.Medium), color = c.text) }
            }

            Text(L("Verwendungszweck"), style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 18.dp, bottom = 10.dp))
            Column(
                Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(16.dp),
            ) {
                t.kind?.takeIf { it.isNotBlank() }?.let { kind ->
                    Text(
                        L(kind).uppercase(),
                        style = WimgType.label.copy(letterSpacing = WimgType.label.letterSpacing),
                        color = c.text,
                        modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(c.neutralTint).padding(horizontal = 10.dp, vertical = 5.dp),
                    )
                    Spacer(Modifier.height(10.dp))
                }
                // Bank text exactly as the bank sent it (copy rule: never rewritten).
                Text(t.description, style = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 1.08f, lineHeight = WimgType.mono.lineHeight * 1.12f), color = c.text)
            }

            if (isPending) {
                QuietLine(L("Noch nicht gebucht. Die Bank kann Betrag oder Text noch ändern; bis zur Buchung zählt er nirgends mit."), Modifier.padding(top = 14.dp))
                return@Column
            }
            HorizontalDivider(Modifier.padding(top = 22.dp), thickness = 1.dp, color = c.line)
            Row(Modifier.fillMaxWidth().padding(vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(L("Aus Summen ausschließen"), style = WimgType.rowTitle.copy(fontSize = WimgType.rowTitle.fontSize * 1.07f), color = c.text)
                    Text(L("Zählt dann nicht in der Übersicht"), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 2.dp))
                }
                Spacer(Modifier.width(12.dp))
                WimgToggle(t.isExcluded, { on -> setExcluded(t, on) }, label = L("Aus Summen ausschließen"))
            }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: @Composable () -> Unit) {
    val c = Wimg.colors
    Column {
        Row(Modifier.fillMaxWidth().heightIn(min = 60.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = WimgType.body, color = c.text2, modifier = Modifier.weight(1f))
            value()
        }
        HorizontalDivider(thickness = 1.dp, color = c.line)
    }
}

private fun applyCategory(tx: Transaction, category: Int) {
    if (category == tx.category) return
    // The merchant's other bookings without a category (or in Sonstiges) follow.
    val others = LibWimg.setCategory(tx.id, category)
    Changes.bump()
    val label = __t(WimgCategory.fromId(category).label)
    Dock.undo(__t("Kategorie geändert"), if (others > 0) "$label · " + __t("+%d weitere").format(others) else label) {
        LibWimg.undo()
        Changes.bump()
    }
}

private fun setExcluded(tx: Transaction, excluded: Boolean) {
    LibWimg.setExcluded(tx.id, excluded)
    Changes.bump()
    Dock.undo(if (excluded) __t("Aus Summen ausgeschlossen") else __t("Zählt wieder mit")) {
        LibWimg.undo()
        Changes.bump()
    }
}

/** Two-column category picker; "Übernehmen" applies the selection. */
@Composable
fun CategoryPanel(current: Int, onApply: (Int) -> Unit) {
    val c = Wimg.colors
    var selected by remember { mutableIntStateOf(current) }
    BarPanel {
        Text(L("Kategorie"), style = WimgType.sheetTitle.copy(fontSize = WimgType.sheetTitle.fontSize * 0.86f), color = c.text, modifier = Modifier.padding(start = 4.dp, bottom = 8.dp))
        PICKER_ORDER.chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                pair.forEach { cat ->
                    val on = cat.id == selected
                    val label = if (cat == WimgCategory.UNCATEGORIZED) L("Unkategorisiert") else L(cat.label)
                    Row(
                        Modifier
                            .weight(1f)
                            .height(46.dp)
                            .clip(WimgShape.dockAction)
                            .background(if (on) c.ink else Color.Transparent)
                            .clickable { selected = cat.id }
                            .padding(horizontal = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (cat == WimgCategory.UNCATEGORIZED) {
                            androidx.compose.foundation.Canvas(Modifier.size(11.dp)) {
                                drawCircle(c.text2, style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3f, 3f))))
                            }
                        } else {
                            Box(Modifier.size(11.dp).clip(CircleShape).background(c.categoryBar(cat.id)))
                        }
                        Spacer(Modifier.width(12.dp))
                        Text(
                            label,
                            style = WimgType.rowTitle.copy(fontWeight = if (on || cat.id == current) FontWeight.Bold else FontWeight.Medium),
                            color = if (on) c.inkText else c.text,
                            modifier = Modifier.weight(1f), maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                        if (on) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.inkText, modifier = Modifier.size(18.dp))
                    }
                }
                // A lone last entry ("Unkategorisiert") takes the whole row.
            }
        }
        Box(
            Modifier.padding(top = 12.dp).fillMaxWidth().height(50.dp).pressable { onApply(selected) }.clip(CircleShape).background(c.ink),
            contentAlignment = Alignment.Center,
        ) { Text(L("Übernehmen"), style = WimgType.button, color = c.inkText) }
    }
}

@Composable
private fun MorePanel(onCopy: () -> Unit, onSearch: () -> Unit, onEdit: (() -> Unit)? = null, onDelete: (() -> Unit)? = null) {
    com.wimg.app.ui.components.BarMenu {
        onEdit?.let { com.wimg.app.ui.components.MenuRow(Icons.Outlined.Edit, L("Bearbeiten"), onClick = it) }
        com.wimg.app.ui.components.MenuRow(Icons.Outlined.ContentCopy, L("Text kopieren"), onClick = onCopy)
        com.wimg.app.ui.components.MenuRow(Icons.Outlined.Search, L("In Suche öffnen"), onClick = onSearch)
        onDelete?.let { com.wimg.app.ui.components.MenuRow(Icons.Outlined.Delete, L("Löschen"), danger = true, onClick = it) }
    }
}

/** Deleting a manual entry: it's gone on every device, so ask once. */
@Composable
private fun DeletePanel(title: String, onCancel: () -> Unit, onDelete: () -> Unit) {
    val c = Wimg.colors
    com.wimg.app.ui.components.BarMenu {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            Text(L("„%s“ löschen?", title), style = WimgType.button, color = c.text, maxLines = 2)
            Text(L("Auch auf deinen anderen Geräten. Das lässt sich nicht rückgängig machen."), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 4.dp))
        }
        com.wimg.app.ui.components.MenuRow(Icons.Outlined.Delete, L("Löschen"), danger = true, onClick = onDelete)
        com.wimg.app.ui.components.MenuRow(Icons.Outlined.Close, L("Abbrechen"), onClick = onCancel)
    }
}

/** What to search for a booking: its first words, without dates and numbers
 *  (the raw text of a pending card payment ends in "2026-11-14T13:00:26"). */
internal fun searchTerm(title: String): String =
    title.split(' ', '/', ',', '*').filter { w -> w.length >= 3 && w.none { it.isDigit() } }.take(2).joinToString(" ").ifBlank { title.take(30) }
