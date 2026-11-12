package com.wimg.app.ui.screens

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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Category picker order from the design; 0 is "Unkategorisiert", 255 "Andere". */
private val PICKER_ORDER = listOf(
    WimgCategory.GROCERIES, WimgCategory.DINING, WimgCategory.TRANSPORT, WimgCategory.HOUSING,
    WimgCategory.UTILITIES, WimgCategory.ENTERTAINMENT, WimgCategory.SHOPPING, WimgCategory.HEALTH,
    WimgCategory.INSURANCE, WimgCategory.INCOME, WimgCategory.TRANSFER, WimgCategory.CASH,
    WimgCategory.SUBSCRIPTIONS, WimgCategory.TRAVEL, WimgCategory.EDUCATION, WimgCategory.OTHER,
    WimgCategory.UNCATEGORIZED,
)

private enum class DetailPanel { None, Category, More }

@Composable
fun TransactionDetailScreen(id: String, navController: NavController?) {
    var tx by remember { mutableStateOf<Transaction?>(null) }
    var account by remember { mutableStateOf<Account?>(null) }
    var panel by remember { mutableStateOf(DetailPanel.None) }
    val clipboard = LocalClipboardManager.current

    LaunchedEffect(id, Changes.version) {
        val (t, a) = withContext(Dispatchers.IO) {
            val t = LibWimg.getTransactions().firstOrNull { it.id == id }
            t to LibWimg.getAccounts().firstOrNull { it.id == t?.account }
        }
        tx = t; account = a
    }

    val t = tx
    BarContribution(
        chip = null,
        panel = when {
            t == null -> null
            panel == DetailPanel.Category -> { { CategoryPanel(t.category) { cat -> applyCategory(t, cat); panel = DetailPanel.None } } }
            panel == DetailPanel.More -> {
                {
                    MorePanel(
                        onCopy = {
                            clipboard.setText(AnnotatedString(t.description))
                            panel = DetailPanel.None
                            Dock.info(__t("Text kopiert"))
                        },
                        onSearch = { panel = DetailPanel.None; navController?.navigate("search") },
                    )
                }
            }
            else -> null
        },
        onPanelDismiss = { panel = DetailPanel.None },
        detail = DetailBarSpec(
            onBack = { navController?.popBackStack() },
            actionLabel = L("Kategorie wählen"),
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
                listOfNotNull(WimgDates.full(t.date), t.kind?.takeIf { it.isNotBlank() }?.let { L(it) }).joinToString(" · "),
                style = WimgType.bandOver, color = c.bandSub,
            )
            Amount(
                t.amount, WimgType.amountHero, WimgType.amountHeroCents,
                if (t.amount > 0) c.bandPos else Color.White, Modifier.padding(top = 2.dp),
            )
            if (accountName.isNotBlank()) Text(accountName, style = WimgType.desc, color = c.bandSub, modifier = Modifier.padding(top = 4.dp))
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, top = 6.dp, bottom = BarClearance)) {
            InfoRow(L("Datum")) { Text(WimgDates.full(t.date), style = WimgType.body.copy(fontWeight = FontWeight.Medium), color = c.text) }
            InfoRow(L("Kategorie")) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clip(WimgShape.button).clickable { panel = DetailPanel.Category }.padding(4.dp)) {
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

            HorizontalDivider(Modifier.padding(top = 22.dp), thickness = 1.dp, color = c.line)
            Row(Modifier.fillMaxWidth().padding(vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(L("Aus Summen ausschließen"), style = WimgType.rowTitle.copy(fontSize = WimgType.rowTitle.fontSize * 1.07f), color = c.text)
                    Text(L("Zählt dann nicht in Übersicht und Analyse"), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 2.dp))
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
    LibWimg.setCategory(tx.id, category)
    Changes.bump()
    Dock.undo(__t("Kategorie geändert"), __t(WimgCategory.fromId(category).label)) {
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
                        )
                        if (on) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.inkText, modifier = Modifier.size(18.dp))
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
        Box(
            Modifier.padding(top = 12.dp).fillMaxWidth().height(50.dp).clip(CircleShape).background(c.ink).pressable { onApply(selected) },
            contentAlignment = Alignment.Center,
        ) { Text(L("Übernehmen"), style = WimgType.button, color = c.inkText) }
    }
}

@Composable
private fun MorePanel(onCopy: () -> Unit, onSearch: () -> Unit) {
    val c = Wimg.colors
    BarPanel {
        listOf(
            Triple(Icons.Outlined.ContentCopy, L("Text kopieren"), onCopy),
            Triple(Icons.Outlined.Search, L("In Suche öffnen"), onSearch),
        ).forEach { (icon, label, action) ->
            Row(
                Modifier.fillMaxWidth().clip(WimgShape.dockAction).clickable(onClick = action).padding(horizontal = 8.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(icon, contentDescription = null, tint = c.text, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(14.dp))
                Text(label, style = WimgType.button, color = c.text)
            }
        }
    }
}
