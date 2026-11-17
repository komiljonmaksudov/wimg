package com.wimg.app.ui.screens

import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BandTitle
import com.wimg.app.ui.components.BarChipSpec
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.BarPanel
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.DockKind
import com.wimg.app.ui.components.DockRow
import com.wimg.app.ui.components.GroupLabel
import com.wimg.app.ui.components.RowDivider
import com.wimg.app.ui.components.WimgGroup
import com.wimg.app.ui.components.WimgRow
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgType

/**
 * Debug only (Einstellungen › Leiste testen): every state of the floating bar
 * on one page, one tap each, so transitions can be compared without a page
 * change around them. Texts are deliberately not translated.
 */
@Composable
fun BarPlaygroundScreen(navController: NavController?) {
    val context = androidx.compose.ui.platform.LocalContext.current
    // 0 = place bar, 1 = detail: back label only, 2 = back + short action,
    // 3 = back + long action, 4 = back + action + more
    var mode by remember { mutableIntStateOf(0) }
    var chip by remember { mutableIntStateOf(1) } // 0 none, 1 "Nov", 2 long label, 3 icon only
    var chipActive by remember { mutableStateOf(false) }
    var panel by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    DisposableEffect(Unit) { onDispose { Dock.dismiss() } }

    val chipSpec = when (chip) {
        1 -> BarChipSpec("Nov", chipActive, { chipActive = !chipActive }, Icons.Outlined.CalendarMonth.takeIf { false })
        2 -> BarChipSpec("Okt. – Dez. 2026", chipActive, { chipActive = !chipActive })
        3 -> BarChipSpec("", chipActive, { chipActive = !chipActive }, Icons.Outlined.Tune, "Filter")
        else -> null
    }
    val back = { if (mode != 0) mode = 0 else navController?.popBackStack(); Unit }
    BarContribution(
        chip = if (mode == 0) chipSpec else null,
        panel = if (panel) { { BarPanel { Text("Beispiel-Panel", style = WimgType.sheetTitle, color = Wimg.colors.text); Text("Tippe daneben zum Schließen.", style = WimgType.body, color = Wimg.colors.text2) } } } else null,
        onPanelDismiss = { panel = false },
        detail = when (mode) {
            1 -> DetailBarSpec(onBack = back, actionLabel = null, actionIcon = null, onAction = {}, backLabel = "Einstellungen")
            2 -> DetailBarSpec(onBack = back, actionLabel = "Abrufen", actionIcon = null, onAction = { busy = !busy }, actionBusy = busy)
            3 -> DetailBarSpec(onBack = back, actionLabel = "584 Umsätze importieren", actionIcon = null, onAction = { busy = !busy }, actionBusy = busy)
            4 -> DetailBarSpec(onBack = back, actionLabel = "Schnellabfrage", actionIcon = Icons.Outlined.Refresh, onAction = { busy = !busy }, actionBusy = busy, onMore = { panel = !panel })
            else -> null
        },
    )

    BandScreen(band = { BandTitle("Entwicklung", "Leiste testen") }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, bottom = barClearance())) {
            GroupLabel("Art der Leiste")
            WimgGroup {
                listOf("Ort (Übersicht-Chip + Suche + Plus)", "Detail: nur Zurück", "Detail: Zurück + kurze Aktion", "Detail: Zurück + lange Aktion", "Detail: Zurück + Aktion + Mehr").forEachIndexed { i, t ->
                    if (i > 0) RowDivider()
                    WimgRow(t, onClick = { mode = i }, trailing = { if (mode == i) Text("●", color = Wimg.colors.accent) })
                }
            }
            GroupLabel("Chip neben dem Ort")
            WimgGroup {
                listOf("Kein Chip", "Kurz: „Nov“", "Lang: „Okt. – Dez. 2026“", "Nur Icon (Filter)").forEachIndexed { i, t ->
                    if (i > 0) RowDivider()
                    WimgRow(t, onClick = { mode = 0; chip = i }, trailing = { if (chip == i) Text("●", color = Wimg.colors.accent) })
                }
                RowDivider()
                WimgRow("Chip aktiv (schwarz) umschalten", onClick = { chipActive = !chipActive })
            }
            GroupLabel("Angedockte Zeile")
            WimgGroup {
                WimgRow("Mitteilung: neue Umsätze", onClick = { com.wimg.app.services.BackgroundRefresh.notify(context, com.wimg.app.services.BackgroundRefresh.Outcome.Imported(3, "Musterbank")) })
                RowDivider()
                WimgRow("Mitteilung: TAN erforderlich", desc = "Höchstens einmal pro Tag", onClick = { com.wimg.app.services.BackgroundRefresh.notify(context, com.wimg.app.services.BackgroundRefresh.Outcome.TanRequired("Musterbank")) })
                RowDivider()
                WimgRow("Mitteilung: Monatsabschluss", onClick = { com.wimg.app.services.BackgroundRefresh.notifyMonthEnd(context, force = true) })
                RowDivider()
                WimgRow("Mitteilung: Preis gestiegen", desc = "Einmal pro Preis", onClick = { kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch { com.wimg.app.services.BackgroundRefresh.notifyPriceRise(context) } })
                RowDivider()
                WimgRow("Läuft (Sync)", onClick = { Dock.show(DockRow(DockKind.Sync, "Umsätze laden", "comdirect · läuft im Hintergrund")) })
                RowDivider()
                WimgRow("Info (4 s)", onClick = { Dock.info("3 neue Umsätze", "12 schon vorhanden") })
                RowDivider()
                WimgRow("Fehler mit Aktion (8 s)", onClick = { Dock.error("Abruf fehlgeschlagen", "Bank nicht erreichbar.", "Erneut") {} })
                RowDivider()
                WimgRow("Rückgängig", onClick = { Dock.undo("Kategorie geändert") {} })
                RowDivider()
                WimgRow("Hinweis (TAN)", onClick = { Dock.show(DockRow(DockKind.Prompt, "TAN erforderlich", "Für ältere Umsätze verlangt die Bank eine TAN.")) })
                RowDivider()
                WimgRow("Zeile durch andere ersetzen", desc = "Läuft → nach 1,2 s Info", onClick = {
                    Dock.show(DockRow(DockKind.Sync, "Anmelden", "comdirect"))
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ Dock.info("Synchron", "2 Änderungen übernommen") }, 1200)
                })
                RowDivider()
                WimgRow("Andocken beenden", onClick = { Dock.dismiss() })
            }
            GroupLabel("Sonstiges")
            WimgGroup {
                WimgRow("Panel öffnen", onClick = { panel = true })
                RowDivider()
                WimgRow("Aktion „läuft“ umschalten", onClick = { busy = !busy })
            }
        }
    }
}
