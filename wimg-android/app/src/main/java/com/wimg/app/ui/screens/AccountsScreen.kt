package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.models.Account
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.GroupLabel
import com.wimg.app.ui.components.QuietLine
import com.wimg.app.ui.components.RowDivider
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.WimgGroup
import com.wimg.app.ui.components.WimgRow
import com.wimg.app.ui.components.WimgToggle
import com.wimg.app.ui.components.amountText
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Board 20: choose an account behind the filter button, hide accounts, rename them.

/** Sum of the bank balances of [accounts], or null unless every one has one. */
internal fun balanceOf(accounts: List<Account>): Double? =
    if (accounts.isNotEmpty() && accounts.all { it.balance != null }) accounts.sumOf { it.balance_cents } / 100.0 else null

/** "Konten" (board 20/04): Alle Konten or one account, as radio rows. */
@Composable
internal fun AccountsPanel(selected: String?, onPick: (String?) -> Unit, onDone: () -> Unit) {
    val c = Wimg.colors
    // Read before the first frame (small, skipped while a bank fetch holds libwimg).
    var accounts by remember { mutableStateOf(LibWimg.ifFree { LibWimg.getAccounts() }.orEmpty()) }
    LaunchedEffect(Changes.version) { accounts = withContext(Dispatchers.IO) { LibWimg.getAccounts() } }
    val visible = accounts.filter { !it.isHidden }
    BarPanel {
        Text(L("Konten"), style = WimgType.sheetTitle, color = c.text, modifier = Modifier.padding(start = 4.dp, bottom = 12.dp))
        Column(Modifier.heightIn(max = 460.dp).verticalScroll(rememberScrollState())) {
            WimgGroup {
                RadioRow(L("Alle Konten"), if (visible.size == 1) L("1 Konto") else L("%d Konten", visible.size), selected == null, trailing = balanceOf(visible)?.let { amountText(it, showPlus = false) }) { onPick(null) }
            }
            Spacer(Modifier.height(10.dp))
            WimgGroup {
                accounts.forEachIndexed { i, a ->
                    if (i > 0) RowDivider()
                    val sub = when {
                        a.isHidden -> L("Ausgeblendet")
                        a.balance != null -> L("Stand %s", WimgDates.short(a.balance_date))
                        else -> null
                    }
                    RadioRow(a.name, sub, selected == a.id, trailing = a.balance?.let { amountText(it, showPlus = false) }) { onPick(a.id) }
                }
            }
        }
        Box(
            Modifier.padding(top = 14.dp).fillMaxWidth().height(50.dp).pressable(onClick = onDone).clip(CircleShape).background(c.accent),
            contentAlignment = Alignment.Center,
        ) { Text(L("Fertig"), style = WimgType.button, color = c.onAccent) }
    }
}

/** One toggle per account: shown in Übersicht and sums, or hidden (board 20/05). */
@Composable
internal fun AccountToggles(accounts: List<Account>, fetched: Boolean = false) {
    val scope = rememberCoroutineScope()
    WimgGroup {
        accounts.forEachIndexed { i, a ->
            if (i > 0) RowDivider()
            WimgRow(
                a.name,
                desc = when {
                    !a.isHidden -> L("In Übersicht und Summen")
                    fetched -> L("Ausgeblendet · wird weiter abgerufen")
                    else -> L("Ausgeblendet")
                },
                trailing = {
                    WimgToggle(!a.isHidden, { on ->
                        scope.launch {
                            withContext(Dispatchers.IO) { LibWimg.setAccountHidden(a.id, !on) }
                            Changes.bump()
                        }
                    }, label = a.name)
                },
            )
        }
    }
}

@Composable
fun SettingsAccountsScreen(navController: NavController?) {
    val scope = rememberCoroutineScope()
    var accounts by remember { mutableStateOf(LibWimg.ifFree { LibWimg.getAccounts() }) }
    var renaming by remember { mutableStateOf<Account?>(null) }
    LaunchedEffect(Changes.version) { accounts = withContext(Dispatchers.IO) { LibWimg.getAccounts() } }

    BarContribution(
        null,
        renaming?.let { a ->
            {
                RenamePanel(a, onCancel = { renaming = null }) { name ->
                    renaming = null
                    scope.launch {
                        withContext(Dispatchers.IO) { LibWimg.renameAccount(a, name.ifBlank { a.id }) }
                        Changes.bump()
                        Dock.info(__t("Name geändert"))
                    }
                }
            }
        },
        { renaming = null },
        DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")),
    )

    SettingsPage(L("Einstellungen"), L("Konten")) {
        val list = accounts ?: return@SettingsPage
        if (list.isEmpty()) {
            QuietLine(L("Noch keine Konten. Sie entstehen beim ersten Abruf oder Import."))
            return@SettingsPage
        }
        GroupLabel(L("Ein- und ausblenden"))
        AccountToggles(list)
        QuietLine(L("Ausgeblendete Konten zählen nicht in „Verfügbar“ und den Kategorien. Ihre Umsätze bleiben in der Suche."))
        GroupLabel(L("Name in wimg"))
        WimgGroup {
            list.forEachIndexed { i, a ->
                if (i > 0) RowDivider()
                WimgRow(
                    a.name,
                    desc = if (a.name != a.id) L("Von der Bank: %s", a.id) else null,
                    chevron = true,
                    onClick = { renaming = a },
                )
            }
        }
    }
}

@Composable
private fun RenamePanel(account: Account, onCancel: () -> Unit, onSave: (String) -> Unit) {
    val c = Wimg.colors
    var name by remember { mutableStateOf(account.name) }
    BarPanel {
        Text(L("Name in wimg"), style = WimgType.sheetTitle, color = c.text)
        Text(L("Von der Bank: %s", account.id), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
        BasicTextField(
            value = name, onValueChange = { name = it.take(40) }, singleLine = true,
            textStyle = WimgType.body.copy(color = c.text),
            cursorBrush = SolidColor(c.accent),
            modifier = Modifier.fillMaxWidth().clip(WimgShape.group).background(c.neutralTint).padding(horizontal = 16.dp, vertical = 16.dp),
        )
        Row(Modifier.padding(top = 16.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.weight(1f).height(50.dp).pressable(onClick = onCancel).clip(CircleShape).border(1.dp, c.line, CircleShape), contentAlignment = Alignment.Center) {
                Text(L("Abbrechen"), style = WimgType.button, color = c.text)
            }
            Box(Modifier.weight(1f).height(50.dp).pressable { onSave(name.trim()) }.clip(CircleShape).background(c.accent), contentAlignment = Alignment.Center) {
                Text(L("Speichern"), style = WimgType.button, color = c.onAccent)
            }
        }
    }
}

