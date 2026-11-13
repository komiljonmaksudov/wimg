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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Refresh
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.models.Account
import com.wimg.app.services.BankConnection
import com.wimg.app.services.BankConnections
import com.wimg.app.services.PinStore
import com.wimg.app.ui.components.Amount
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.QuietLine
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgType
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Bankverbindungen (board 7/03): one card per bank login with its balance, PIN
 * state and last fetch. "+" on the bar adds a bank; ↻ is that bank's
 * Schnellabfrage. Without any bank, the page is the add flow itself.
 */
@Composable
fun BanksScreen(navController: NavController?) {
    val context = LocalContext.current
    val connections = remember(Changes.version) { BankConnections.all(context) }
    if (connections.isEmpty()) {
        FinTSScreen(navController)
        return
    }
    var accounts by remember { mutableStateOf<List<Account>>(emptyList()) }
    LaunchedEffect(Changes.version) { accounts = LibWimg.getAccounts() }
    // Logins from older builds have no bank name: take it from the catalog once.
    LaunchedEffect(connections) {
        if (connections.none { it.name.isBlank() }) return@LaunchedEffect
        val catalog = withFintsThread { com.wimg.app.bridge.LibWimg.native { com.wimg.app.bridge.WimgJni.nativeFintsGetBanks() } } ?: return@LaunchedEffect
        val names = runCatching {
            kotlinx.serialization.json.Json.parseToJsonElement(catalog).jsonArray.associate { e ->
                e.jsonObject["blz"]!!.jsonPrimitive.content to e.jsonObject["name"]!!.jsonPrimitive.content
            }
        }.getOrNull() ?: return@LaunchedEffect
        connections.filter { it.name.isBlank() }.forEach { c ->
            names[c.blz]?.let { n -> BankConnections.update(context, c.id) { it.copy(name = n) } }
        }
        Changes.bump()
    }

    BarContribution(
        chip = null, panel = null, onPanelDismiss = {},
        onAdd = { navController?.navigate("fints/add") }, addLabel = L("Bank hinzufügen"),
    )
    BandScreen(band = { Text(L("Bankverbindungen"), style = WimgType.title, color = Color.White) }) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            connections.forEach { conn ->
                BankCard(
                    conn,
                    accounts.firstOrNull { it.id == conn.name },
                    hasPin = PinStore.has(context, conn.id),
                    onOpen = { navController?.navigate(bankRoute(conn.id)) },
                    onRefresh = { navController?.navigate(bankRoute(conn.id, quick = true)) },
                )
            }
            QuietLine(L("Schnellabfrage (↻) holt die letzten 90 Tage und geht direkt zur TAN, falls die Bank eine verlangt. Nur mit gespeicherter PIN."))
        }
    }
}

@Composable
private fun BankCard(conn: BankConnection, account: Account?, hasPin: Boolean, onOpen: () -> Unit, onRefresh: () -> Unit) {
    val c = Wimg.colors
    val shape = RoundedCornerShape(20.dp)
    Column(Modifier.fillMaxWidth().clip(shape).background(c.card).border(1.dp, c.line, shape).pressable(onClick = onOpen).padding(18.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(conn.name.ifBlank { conn.blz }, style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val balance = account?.balance
                if (balance != null) {
                    Amount(balance, WimgType.amountLarge, WimgType.amountStat, c.text, Modifier.padding(top = 4.dp), showPlus = false)
                    Text(L("Kontostand · Stand %s", WimgDates.short(account.balance_date)), style = WimgType.desc, color = c.text2)
                } else {
                    Text(L("Kontostand nach dem ersten Abruf"), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(top = 4.dp))
                }
            }
            if (hasPin) {
                Box(
                    Modifier.size(48.dp).clip(RoundedCornerShape(14.dp)).background(c.neutralTint).pressable(label = L("Schnellabfrage"), onClick = onRefresh),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Outlined.Refresh, contentDescription = L("Schnellabfrage"), tint = c.text, modifier = Modifier.size(22.dp)) }
            }
        }
        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (hasPin) Chip(L("PIN gespeichert"), lock = true) else Chip(L("PIN nicht gespeichert"), dashed = true)
            conn.tanMedium?.let { Chip(it) }
        }
        HorizontalDivider(Modifier.padding(vertical = 12.dp), thickness = 1.dp, color = c.line)
        val last = if (conn.lastFetchAt == 0L) L("noch nicht abgerufen") else L("zuletzt abgerufen %s", ago(conn.lastFetchAt))
        val tail = when {
            !hasPin -> L("Abruf nur mit Anmeldung")
            conn.lastFetchAt == 0L -> null
            conn.lastFetchNew == 1 -> L("1 neuer Umsatz")
            else -> L("%d neue Umsätze", conn.lastFetchNew)
        }
        Text(listOfNotNull(last, tail).joinToString(" · "), style = WimgType.desc, color = c.text2)
    }
}

@Composable
private fun Chip(text: String, lock: Boolean = false, dashed: Boolean = false) {
    val c = Wimg.colors
    val base = Modifier.height(30.dp).clip(CircleShape)
    val styled = if (dashed) {
        base.drawBehind {
            drawRoundRect(c.text3, style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f))), cornerRadius = CornerRadius(size.height / 2))
        }
    } else base.background(c.neutralTint)
    Row(styled.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        if (lock) {
            Icon(Icons.Outlined.Lock, contentDescription = null, tint = c.text, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(text, style = WimgType.desc, color = if (dashed) c.text2 else c.text, maxLines = 1)
    }
}

/** "vor 2 Std.", "vor 9 Tagen", "gerade eben". */
@Composable
private fun ago(at: Long): String {
    val min = ((System.currentTimeMillis() - at) / 60_000).coerceAtLeast(0)
    return when {
        min < 2 -> L("gerade eben")
        min < 60 -> L("vor %d Min.", min.toInt())
        min < 48 * 60 -> L("vor %d Std.", (min / 60).toInt())
        else -> L("vor %d Tagen", (min / 1440).toInt())
    }
}
