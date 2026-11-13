package com.wimg.app.ui.screens

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.bridge.LibWimg
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.models.ImportResult
import com.wimg.app.models.Transaction
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.GroupLabel
import com.wimg.app.ui.components.RowDivider
import com.wimg.app.ui.components.StepBand
import com.wimg.app.ui.components.WimgDates
import com.wimg.app.ui.components.WimgGroup
import com.wimg.app.ui.components.WimgRow
import com.wimg.app.ui.components.amountText
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class Source(val format: String, val name: String, val account: String, val steps: List<String>)

private val SOURCES = listOf(
    Source(
        "comdirect", "Comdirect", "Girokonto",
        listOf("Bei Comdirect im Browser anmelden.", "Umsätze des Girokontos öffnen und als CSV exportieren.", "Die Datei hier auswählen. Sie bleibt auf deinem Gerät."),
    ),
    Source(
        "trade_republic", "Trade Republic", "Verrechnungskonto",
        listOf("In der Trade-Republic-App oder im Browser das Profil öffnen.", "Unter Transaktionen den Export als CSV anfordern.", "Die Datei hier auswählen. Sie bleibt auf deinem Gerät."),
    ),
    Source(
        "scalable_capital", "Scalable", "Verrechnungskonto",
        listOf("Bei Scalable Capital im Browser anmelden.", "Unter Transaktionen die Umsätze als CSV exportieren.", "Die Datei hier auswählen. Sie bleibt auf deinem Gerät."),
    ),
)

/** A read file waiting for confirmation: nothing is written until "importieren". */
private class Picked(val name: String, val bytes: ByteArray, val format: String, val rows: List<Transaction>, val duplicates: Int)

private enum class ImportStep { Source, Preview, Done }

private fun displayName(context: Context, uri: Uri): String =
    runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }.getOrNull() ?: "Datei.csv"

@Composable
fun ImportScreen(navController: NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var step by remember { mutableStateOf(ImportStep.Source) }
    var source by remember { mutableIntStateOf(0) }
    var picked by remember { mutableStateOf<Picked?>(null) }
    var result by remember { mutableStateOf<ImportResult?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        busy = true; error = null
        scope.launch {
            val p = withContext(Dispatchers.IO) {
                runCatching {
                    val bytes = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                    val parsed = LibWimg.parseCsv(bytes) ?: return@runCatching null
                    if (parsed.transactions.isEmpty()) return@runCatching null
                    // Same id scheme as the database, so this matches what import will skip.
                    val existing = LibWimg.getTransactions().mapTo(HashSet()) { it.id }
                    Picked(displayName(context, uri), bytes, parsed.format, parsed.transactions, parsed.transactions.count { it.id in existing })
                }.getOrNull()
            }
            busy = false
            if (p == null) error = __t("wimg erkennt diese Datei nicht. Unterstützt sind CSV-Exporte von Comdirect, Trade Republic und Scalable.")
            else { picked = p; step = ImportStep.Preview }
        }
    }

    fun doImport() {
        val p = picked ?: return
        busy = true
        scope.launch {
            val r = withContext(Dispatchers.IO) { runCatching { LibWimg.importCsv(p.bytes) }.getOrNull() }
            busy = false
            if (r == null) { error = __t("Import fehlgeschlagen. Es wurde nichts gespeichert."); return@launch }
            Changes.bump()
            result = r; step = ImportStep.Done
        }
    }

    BackHandler(enabled = step == ImportStep.Preview) { step = ImportStep.Source; picked = null; error = null }

    val p = picked
    BarContribution(
        chip = null, panel = null, onPanelDismiss = {},
        detail = when (step) {
            ImportStep.Source -> DetailBarSpec(
                onBack = { navController.popBackStack() },
                actionLabel = L("Datei wählen"), actionIcon = null, actionBusy = busy,
                onAction = { if (!busy) picker.launch(arrayOf("text/*", "application/csv", "application/vnd.ms-excel", "application/octet-stream")) },
            )
            ImportStep.Preview -> {
                val n = (p?.rows?.size ?: 0) - (p?.duplicates ?: 0)
                DetailBarSpec(
                    onBack = { step = ImportStep.Source; picked = null; error = null },
                    actionLabel = if (n == 1) L("1 Umsatz importieren") else L("%d Umsätze importieren", n), actionIcon = null, actionBusy = busy,
                    onAction = { if (!busy && n > 0) doImport() },
                )
            }
            ImportStep.Done -> DetailBarSpec(
                onBack = { navController.navigate("dashboard") { popUpTo(0) } },
                actionLabel = L("Umsätze ansehen"), actionIcon = null,
                onAction = { navController.navigate("transactions") { popUpTo("dashboard") } },
            )
        },
    )

    val c = Wimg.colors
    BandScreen(
        band = {
            when (step) {
                ImportStep.Source -> StepBand(L("CSV-Import"), 1, 3, L("CSV-Datei wählen"))
                ImportStep.Preview -> StepBand(L("CSV-Import"), 2, 3, L("Vorschau"))
                ImportStep.Done -> StepBand(L("CSV-Import"), 3, 3, L("Fertig"))
            }
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = BarClearance)) {
            when (step) {
                ImportStep.Source -> {
                    GroupLabel(L("Von welcher Bank oder welchem Broker?"))
                    WimgGroup {
                        SOURCES.forEachIndexed { i, s ->
                            if (i > 0) RowDivider()
                            WimgRow(s.name, onClick = { source = i }, leading = { Radio(source == i) }, trailing = { Text(L(s.account), style = WimgType.desc, color = c.text2) })
                        }
                    }
                    val s = SOURCES[source]
                    Column(Modifier.padding(top = 16.dp).fillMaxWidth().clip(WimgShape.group).background(c.neutralTint).padding(18.dp)) {
                        Text(L("So kommst du an die Datei"), style = WimgType.button, color = c.text)
                        s.steps.forEachIndexed { i, line ->
                            Row(Modifier.padding(top = 8.dp)) {
                                Text("${i + 1}.", style = WimgType.body, color = c.text, modifier = Modifier.width(22.dp))
                                Text(L(line), style = WimgType.body, color = c.text)
                            }
                        }
                    }
                    if (error != null) ImportError(error!!)
                }
                ImportStep.Preview -> if (p != null) {
                    val src = SOURCES.firstOrNull { it.format == p.format }
                    Row(
                        Modifier.padding(top = 14.dp).fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.size(44.dp).clip(WimgShape.iconTile).background(c.neutralTint), contentAlignment = Alignment.Center) {
                            Text("CSV", style = WimgType.mono, color = c.text)
                        }
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(p.name, style = WimgType.mono.copy(fontSize = WimgType.mono.fontSize * 1.1f), color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(src?.let { "${it.name} · ${L(it.account)}" } ?: L("Format erkannt"), style = WimgType.desc, color = c.text2)
                        }
                    }
                    val dates = p.rows.map { it.date }.sorted()
                    Row(Modifier.padding(top = 12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatCard(L("Neu"), "${p.rows.size - p.duplicates}", Modifier.weight(1f))
                        StatCard(L("Schon da"), "${p.duplicates}", Modifier.weight(1f))
                        StatCard(L("Zeitraum"), "${WimgDates.short(dates.first())} – ${WimgDates.short(dates.last())}", Modifier.weight(1.3f), small = true)
                    }
                    if (p.rows.size == p.duplicates) {
                        Text(L("Alle Umsätze dieser Datei sind schon in wimg."), style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 14.dp))
                    }
                    GroupLabel(L("Neueste Umsätze"))
                    p.rows.sortedByDescending { it.date }.take(5).forEach { t ->
                        Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(t.title?.takeIf { it.isNotBlank() } ?: t.description, style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(WimgDates.full(t.date), style = WimgType.desc, color = c.text2)
                            }
                            Spacer(Modifier.width(12.dp))
                            Text(amountText(t.amount), style = WimgType.amountRow, color = if (t.amount > 0) c.pos else c.text)
                        }
                        HorizontalDivider(thickness = 1.dp, color = c.line)
                    }
                    if (error != null) ImportError(error!!)
                }
                ImportStep.Done -> {
                    val r = result
                    Box(Modifier.padding(top = 28.dp).align(Alignment.CenterHorizontally).size(76.dp).clip(CircleShape).background(c.ink), contentAlignment = Alignment.Center) {
                        Icon(Icons.Outlined.Check, contentDescription = null, tint = c.inkText, modifier = Modifier.size(36.dp))
                    }
                    Text(L("Import fertig"), style = WimgType.title.copy(color = c.text), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 18.dp))
                    Text(
                        L("wimg hat die Umsätze schon nach Kategorien sortiert, so weit es ging."),
                        style = WimgType.body, color = c.text2, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                    )
                    Row(Modifier.padding(top = 20.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatCard(L("Importiert"), "${r?.imported ?: 0}", Modifier.weight(1f))
                        StatCard(L("Schon da, übersprungen"), "${r?.skipped_duplicates ?: 0}", Modifier.weight(1f))
                    }
                    if ((r?.errors ?: 0) > 0) {
                        Text(L("%d Zeilen konnte wimg nicht lesen.", r!!.errors), style = WimgType.body, color = c.warn, modifier = Modifier.padding(top = 12.dp))
                    }
                    Row(Modifier.padding(top = 14.dp).fillMaxWidth().clip(WimgShape.group).background(c.neutralTint).padding(16.dp)) {
                        Icon(Icons.Outlined.Info, contentDescription = null, tint = c.text2, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(12.dp))
                        Text(L("Ein Import ist eine Momentaufnahme. Für neue Umsätze: Bank verbinden oder später wieder importieren."), style = WimgType.body, color = c.text)
                    }
                }
            }
        }
    }
}

@Composable
private fun Radio(on: Boolean) {
    val c = Wimg.colors
    Box(Modifier.size(22.dp).clip(CircleShape).border(2.dp, if (on) c.ink else c.text3, CircleShape), contentAlignment = Alignment.Center) {
        if (on) Box(Modifier.size(11.dp).clip(CircleShape).background(c.ink))
    }
}

@Composable
private fun StatCard(label: String, value: String, modifier: Modifier, small: Boolean = false) {
    val c = Wimg.colors
    Column(modifier.clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(14.dp)) {
        Text(label, style = WimgType.desc, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(
            value,
            style = if (small) WimgType.chip else WimgType.amountStat.copy(fontSize = WimgType.amountStat.fontSize * 1.2f),
            color = c.text, maxLines = 1, modifier = Modifier.padding(top = 4.dp),
        )
    }
}

@Composable
private fun ImportError(text: String) {
    val c = Wimg.colors
    Row(Modifier.padding(top = 16.dp).fillMaxWidth().clip(WimgShape.group).background(c.dangerBg).padding(16.dp)) {
        Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = c.danger, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(text, style = WimgType.body, color = c.text)
    }
}
