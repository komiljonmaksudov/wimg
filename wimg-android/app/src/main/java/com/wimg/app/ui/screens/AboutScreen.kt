package com.wimg.app.ui.screens

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Gavel
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.wimg.app.R
import com.wimg.app.i18n.L
import com.wimg.app.i18n.__t
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.BandTitle
import com.wimg.app.ui.components.BarContribution
import com.wimg.app.ui.components.DetailBarSpec
import com.wimg.app.ui.components.Dock
import com.wimg.app.ui.components.DockKind
import com.wimg.app.ui.components.DockRow
import com.wimg.app.ui.components.GroupLabel
import com.wimg.app.ui.components.IconTile
import com.wimg.app.ui.components.QuietLine
import com.wimg.app.ui.components.RowDivider
import com.wimg.app.ui.components.WimgGroup
import com.wimg.app.ui.components.WimgRow
import com.wimg.app.ui.components.barClearance
import com.wimg.app.ui.theme.LocaleState
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

private const val REPO = "https://github.com/komiljonmaksudov/wimg"
private const val SITE = "https://wimg.komiljonmaksudov.com"

private fun open(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}

private fun shareApp(context: Context) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain")
        .putExtra(Intent.EXTRA_TEXT, __t("wimg zeigt, wo dein Geld hingeht, und deine Daten bleiben auf dem Handy: %s").format(SITE))
    runCatching { context.startActivity(Intent.createChooser(send, null)) }
}

/** The Play app's page for wimg, or the web page without the Play app. */
private fun rateApp(context: Context) {
    val pkg = context.packageName.removeSuffix(".tester")
    val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg")).setPackage("com.android.vending")
    runCatching { context.startActivity(market) }.onFailure { open(context, "https://play.google.com/store/apps/details?id=$pkg") }
}

/**
 * Installed from Google Play: Play updates the app, and Play's policy forbids an
 * app updating itself any other way. The update check is only for APKs from the
 * website or GitHub.
 */
private fun fromPlayStore(context: Context): Boolean = runCatching {
    val pm = context.packageManager
    val installer = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) pm.getInstallSourceInfo(context.packageName).installingPackageName
    else @Suppress("DEPRECATION") pm.getInstallerPackageName(context.packageName)
    installer == "com.android.vending"
}.getOrDefault(false)

private fun installedVersion(context: Context): String =
    runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "?"

// ---------------------------------------------------------------------------
// Release notes, written for people (not the commit log), shipped with the app
// so they work offline. Newest first. Keep in step with CHANGELOG.md.
// ---------------------------------------------------------------------------

private enum class NoteKind(val label: String) { New("Neu"), Better("Besser"), Fixed("Behoben") }
private class Release(val version: String, val dateIso: String, val notes: List<Pair<NoteKind, String>>)

private val RELEASES = listOf(
    Release(
        "0.9.13", "2026-11-18",
        listOf(
            NoteKind.New to "Neue Suche: Sie zeigt gleich die Summe, die Anzahl und den Durchschnitt, dazu den Händler und die Umsätze nach Monaten.",
            NoteKind.New to "Seiten wie „Einstellungen“ oder „Sync“ findest du über die Suche, Enter öffnet sie.",
            NoteKind.New to "Filter nach Betrag, „Nur wiederkehrende“ und „Ausgeblendete zeigen“ in Umsätze.",
            NoteKind.Better to "„In Umsätzen“ öffnet eine Suche als Filter in Umsätze.",
            NoteKind.Fixed to "Zurück aus einem Umsatz führt wieder zur selben Suche.",
            NoteKind.Fixed to "Das Suchfeld ist für Screenreader beschriftet.",
        ),
    ),
    Release(
        "0.9.12", "2026-11-18",
        listOf(
            NoteKind.New to "Kontoauszüge (MT940, CAMT) von jeder Bank importieren.",
            NoteKind.New to "Revolut-CSV importieren.",
            NoteKind.Better to "Wer einem Umsatz eine Kategorie gibt, sortiert die unsortierten Umsätze desselben Händlers gleich mit. Ein Tippen auf Rückgängig nimmt alles zurück.",
            NoteKind.Better to "Ruhigerer Filter in Umsätze. Art, Konto, Zeitraum und Kategorie stehen als Zeilen mit ihrem Wert, und die Summe bleibt beim Scrollen stehen.",
            NoteKind.Better to "Die Bankensuche zeigt ING und andere große Banken zuerst.",
            NoteKind.Fixed to "Regeln entstehen nur noch aus dem Händler, nie aus Wörtern wie „BELASTUNG“. Falsch gelernte Regeln sind entfernt.",
            NoteKind.Fixed to "Umsätze ohne Kategorie heißen „Unkategorisiert“, nicht mehr „Sonstiges“.",
            NoteKind.Fixed to "Der Schalter Hell / Dunkel / System zeigt die gewählte Einstellung.",
        ),
    ),
    Release(
        "0.9.9 – 0.9.11", "2026-11-17",
        listOf(
            NoteKind.New to "Eine Mitteilung, wenn Fixkosten teurer werden (ab 1 € und 5 %).",
            NoteKind.New to "Das Monats-Widget passt auf 2×2.",
            NoteKind.Better to "Kartenzahlungen zeigen den Händler statt des Kartentexts.",
            NoteKind.Better to "wimg startet in der Sprache des Telefons, ohne Flackern.",
            NoteKind.Better to "Das Englisch ist überarbeitet: Datum, Wortwahl, Groß- und Kleinschreibung.",
            NoteKind.Fixed to "Zurück führt durch die zuletzt geöffneten Seiten statt direkt zur Übersicht.",
        ),
    ),
    Release(
        "0.9.8", "2026-11-16",
        listOf(
            NoteKind.New to "Neues Aussehen: eine schwebende Leiste, neue Übersicht, Umsätze und Einstellungen.",
            NoteKind.New to "Gehaltsmonat: Ein Monat kann von Gehalt zu Gehalt laufen.",
            NoteKind.New to "Umsätze von Hand eintragen, bearbeiten und löschen.",
            NoteKind.New to "Der Rückblick öffnet zum Monatsende mit Karten und lässt sich jederzeit wieder abspielen.",
            NoteKind.New to "Mehrere Bankverbindungen, vorgemerkte Umsätze und frische Umsätze beim Öffnen.",
            NoteKind.New to "Die Suche findet auch Beträge und Aktionen.",
            NoteKind.Better to "Bankabruf zuverlässiger: Klappt MT940 nicht, holt wimg die Umsätze still per CAMT.",
            NoteKind.Better to "Die gespeicherte Bank-PIN ist mit dem Android Keystore verschlüsselt.",
            NoteKind.Fixed to "Eine Störung bei der Bank löscht die gespeicherte PIN nicht mehr.",
        ),
    ),
    Release(
        "0.9.7", "2026-11-11",
        listOf(
            NoteKind.Better to "Banken mit Freigabe in der Banking-App (pushTAN) funktionieren.",
            NoteKind.Better to "Volks- und Raiffeisenbanken, die nur noch CAMT liefern, funktionieren.",
            NoteKind.Fixed to "Das TAN-Gerät wird bei der Anmeldung richtig erkannt.",
        ),
    ),
    Release(
        "0.9.6", "2026-10-22",
        listOf(
            NoteKind.New to "Claude und andere KI-Assistenten verbinden sich über das neue MCP-Protokoll.",
            NoteKind.Fixed to "Große Synchronisierungen landen nicht mehr unter einem falschen Schlüssel.",
            NoteKind.Better to "Kein Update-Banner mehr in der Android-App.",
        ),
    ),
    Release(
        "0.9.5", "2026-08-05",
        listOf(
            NoteKind.New to "Bankabruf im Hintergrund mit Mitteilungen auf Android.",
            NoteKind.New to "Eigenes App-Icon für Android.",
            NoteKind.Better to "wimg Sync läuft auf einem eigenen Server statt bei Cloudflare.",
            NoteKind.Better to "KI-Abfragen über MCP blenden IBANs und Namen aus.",
        ),
    ),
)

private fun dateLabel(iso: String) = com.wimg.app.ui.components.WimgDates.full(iso)

// ---------------------------------------------------------------------------
// Update check (Android builds from the website / GitHub only)
// ---------------------------------------------------------------------------

private sealed interface UpdateState {
    data object Idle : UpdateState
    data object Checking : UpdateState
    data object Current : UpdateState
    data class Available(val version: String, val apkUrl: String, val sizeBytes: Long?) : UpdateState
    data object Failed : UpdateState
}

private object UpdateCheck {
    var state by mutableStateOf<UpdateState>(UpdateState.Idle)
}

private fun newer(a: String, b: String): Boolean {
    val x = a.split('.').map { it.toIntOrNull() ?: 0 }
    val y = b.split('.').map { it.toIntOrNull() ?: 0 }
    for (i in 0 until maxOf(x.size, y.size)) {
        val d = x.getOrElse(i) { 0 } - y.getOrElse(i) { 0 }
        if (d != 0) return d > 0
    }
    return false
}

/** Asks GitHub for the latest release. Only when tapped: it tells GitHub your IP. */
private suspend fun checkForUpdate(installed: String): UpdateState = withContext(Dispatchers.IO) {
    runCatching {
        val client = okhttp3.OkHttpClient.Builder().callTimeout(15, java.util.concurrent.TimeUnit.SECONDS).build()
        val req = okhttp3.Request.Builder()
            .url("https://api.github.com/repos/komiljonmaksudov/wimg/releases/latest")
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "wimg-android")
            .build()
        client.newCall(req).execute().use { res ->
            if (!res.isSuccessful) return@runCatching UpdateState.Failed
            val obj = Json.parseToJsonElement(res.body!!.string()).jsonObject
            val tag = obj["tag_name"]!!.jsonPrimitive.content.removePrefix("v")
            if (!newer(tag, installed)) return@runCatching UpdateState.Current
            val apk = obj["assets"]?.jsonArray?.map { it.jsonObject }?.firstOrNull { it["name"]?.jsonPrimitive?.content == "wimg.apk" }
            UpdateState.Available(
                tag,
                apk?.get("browser_download_url")?.jsonPrimitive?.content ?: "$REPO/releases/latest",
                apk?.get("size")?.jsonPrimitive?.longOrNull,
            )
        }
    }.getOrDefault(UpdateState.Failed)
}

private fun sizeLabel(bytes: Long?): String? = bytes?.let { "%.1f MB".format(java.util.Locale.GERMANY, it / 1_000_000.0) }

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

@Composable
private fun AboutPage(over: String, title: String, back: String, navController: NavController?, content: @Composable ColumnScope.() -> Unit) {
    BarContribution(null, null, {}, DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = back))
    BandScreen(band = { BandTitle(over, title) }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = barClearance()), content = content)
    }
}

@Composable
private fun ExternalArrow() = Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = L("Öffnet im Browser"), tint = Wimg.colors.text2, modifier = Modifier.size(20.dp))

@Composable
private fun Pill(text: String, fg: Color, bg: Color) {
    Text(text, style = WimgType.caption.copy(fontWeight = FontWeight.Bold), color = fg, modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(bg).padding(horizontal = 9.dp, vertical = 3.dp))
}

/** The adaptive icon's two layers, cropped like a launcher shows them. */
@Composable
private fun AppIcon(modifier: Modifier) {
    Box(modifier.shadow(10.dp, RoundedCornerShape(18.dp)).clip(RoundedCornerShape(18.dp))) {
        listOf(R.mipmap.ic_launcher_background, R.mipmap.ic_launcher_foreground).forEach { res ->
            Image(
                painterResource(res), contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = 1.5f; scaleY = 1.5f },
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Hub
// ---------------------------------------------------------------------------

@Composable
fun AboutScreen(navController: NavController? = null) {
    val context = LocalContext.current
    val c = Wimg.colors
    val scope = rememberCoroutineScope()
    val version = remember { installedVersion(context) }
    val release = RELEASES.firstOrNull { it.version == version }
    val update = UpdateCheck.state
    val canSelfUpdate = remember { !fromPlayStore(context) }

    fun check() {
        if (UpdateCheck.state == UpdateState.Checking) return
        UpdateCheck.state = UpdateState.Checking
        Dock.show(DockRow(DockKind.Sync, __t("Suche nach Updates"), "GitHub"))
        scope.launch {
            val r = checkForUpdate(version)
            UpdateCheck.state = r
            when (r) {
                is UpdateState.Available -> Dock.show(
                    DockRow(
                        DockKind.Prompt, __t("wimg %s ist da").format(r.version),
                        listOfNotNull(sizeLabel(r.sizeBytes), __t("Lädt die APK im Browser")).joinToString(" · "),
                        __t("Laden"), { open(context, r.apkUrl) },
                    ),
                )
                UpdateState.Current -> Dock.info(__t("wimg ist aktuell"), version)
                else -> Dock.error(__t("Keine Verbindung zu GitHub"), __t("Später erneut versuchen."))
            }
        }
    }

    BarContribution(null, null, {}, DetailBarSpec(onBack = { navController?.popBackStack() }, actionLabel = null, actionIcon = null, onAction = {}, backLabel = L("Einstellungen")))
    BandScreen(
        band = {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 4.dp)) {
                AppIcon(Modifier.size(60.dp))
                Spacer(Modifier.width(16.dp))
                Column {
                    Text(L("Einstellungen"), style = WimgType.bandOver, color = c.bandSub)
                    Text(L("Über wimg"), style = WimgType.title, color = Color.White)
                    Text(L("Wo ist mein Geld?"), style = WimgType.body, color = c.bandSub)
                }
            }
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = barClearance())) {
            GroupLabel(L("App"))
            WimgGroup {
                WimgRow(L("Version"), leading = { IconTile(Icons.Outlined.Info, c.text) }, trailing = {
                    Text(listOfNotNull(version, release?.let { dateLabel(it.dateIso) }).joinToString(" · "), style = WimgType.body, color = c.text2)
                })
                RowDivider()
                WimgRow(L("Neuigkeiten"), leading = { IconTile(Icons.Outlined.CardGiftcard, c.text) }, chevron = true, onClick = { navController?.navigate("about/news") }, trailing = {
                    if (release != null) Pill(L("NEU IN %s", version), c.accent, c.accentSoft)
                })
                if (canSelfUpdate) RowDivider()
                if (canSelfUpdate) WimgRow(
                    L("Auf Updates prüfen"), desc = L("Nur für die Android-Version von der Website"),
                    leading = { IconTile(Icons.Outlined.Refresh, c.text) }, onClick = { check() },
                    trailing = {
                        when (update) {
                            UpdateState.Current -> Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Outlined.Check, contentDescription = null, tint = c.pos, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text(L("Aktuell"), style = WimgType.body, color = c.pos)
                            }
                            is UpdateState.Available -> Pill(L("%s verfügbar", update.version), c.accent, c.accentSoft)
                            UpdateState.Failed -> Text(L("Nicht erreichbar"), style = WimgType.body, color = c.text2)
                            else -> {}
                        }
                    },
                )
            }

            GroupLabel(L("Hilfe"))
            WimgGroup {
                WimgRow(L("Häufige Fragen"), leading = { IconTile(Icons.AutoMirrored.Outlined.HelpOutline, c.text) }, chevron = true, onClick = { navController?.navigate("about/faq") })
                RowDivider()
                WimgRow(
                    L("Problem melden"), desc = L("Öffnet GitHub. Was du dort schreibst, ist öffentlich."),
                    leading = { IconTile(Icons.Outlined.BugReport, c.text) }, trailing = { ExternalArrow() },
                    onClick = { open(context, "$REPO/issues/new") },
                )
            }

            GroupLabel(L("Datenschutz"))
            WimgGroup {
                WimgRow(L("So bleiben deine Daten bei dir"), leading = { IconTile(Icons.Outlined.Shield, c.accent) }, chevron = true, onClick = { navController?.navigate("about/privacy") })
                RowDivider()
                WimgRow(
                    L("Datenschutzerklärung"), desc = L("Auf der Website"),
                    leading = { IconTile(Icons.Outlined.Description, c.text) }, trailing = { ExternalArrow() },
                    onClick = { open(context, "$SITE/datenschutz.html") },
                )
            }

            // Tester feedback (closed test, 2026-11): a way to recommend and rate wimg.
            // Plain system share sheet and a Play link: no Google library, nothing tracked.
            GroupLabel(L("Weitersagen"))
            WimgGroup {
                WimgRow(L("wimg empfehlen"), desc = L("Den Link mit jemandem teilen"), leading = { IconTile(Icons.Outlined.Share, c.text) }, onClick = { shareApp(context) })
                RowDivider()
                WimgRow(L("Bei Google Play bewerten"), leading = { IconTile(Icons.Outlined.StarOutline, c.text) }, trailing = { ExternalArrow() }, onClick = { rateApp(context) })
            }

            GroupLabel(L("Projekt"))
            WimgGroup {
                WimgRow(L("Quellcode auf GitHub"), leading = { IconTile(Icons.Outlined.Code, c.text) }, trailing = { ExternalArrow() }, onClick = { open(context, REPO) })
                RowDivider()
                WimgRow(L("Lizenzen"), desc = L("Offene Bibliotheken, die wimg nutzt"), leading = { IconTile(Icons.Outlined.Gavel, c.text) }, chevron = true, onClick = { navController?.navigate("about/licenses") })
                RowDivider()
                WimgRow(L("Website"), leading = { IconTile(Icons.Outlined.Language, c.text) }, trailing = { ExternalArrow() }, onClick = { open(context, SITE) })
            }
            QuietLine(L("Kein Tracking, keine Werbung."))
        }
    }
}

// ---------------------------------------------------------------------------
// Neuigkeiten
// ---------------------------------------------------------------------------

@Composable
fun AboutNewsScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    val installed = remember { installedVersion(context) }
    AboutPage(L("Über wimg"), L("Neuigkeiten"), L("Über wimg"), navController) {
        RELEASES.forEach { r ->
            Column(Modifier.padding(bottom = 14.dp).fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(horizontal = 16.dp, vertical = 14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(r.version, style = WimgType.chip, color = c.inkText, modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(c.ink).padding(horizontal = 11.dp, vertical = 5.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(dateLabel(r.dateIso), style = WimgType.body, color = c.text2, modifier = Modifier.weight(1f))
                    if (r.version == installed) Pill(L("Installiert"), c.pos, c.pos.copy(alpha = 0.12f))
                }
                r.notes.forEach { (kind, text) ->
                    Box(Modifier.padding(top = 12.dp).fillMaxWidth().height(1.dp).background(c.line))
                    Row(Modifier.padding(top = 12.dp)) {
                        val (fg, bg) = when (kind) {
                            NoteKind.New -> c.accent to c.accentSoft
                            NoteKind.Better -> c.pos to c.pos.copy(alpha = 0.12f)
                            NoteKind.Fixed -> c.text2 to c.neutralTint
                        }
                        Box(Modifier.width(84.dp)) { Pill(L(kind.label), fg, bg) }
                        Text(L(text), style = WimgType.body, color = c.text, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        Text(L("Ältere Versionen stehen auf GitHub."), style = WimgType.desc, color = c.accent, modifier = Modifier.padding(start = 4.dp, top = 2.dp).clickable { open(context, "$REPO/releases") })
    }
}

// ---------------------------------------------------------------------------
// Häufige Fragen
// ---------------------------------------------------------------------------

private class Faq(val q: String, val a: String)
private class FaqGroup(val title: String, val items: List<Faq>)

private val FAQ = listOf(
    FaqGroup(
        "Grundlagen",
        listOf(
            Faq("Was ist wimg?", "Eine App, die zeigt, wohin dein Geld geht. Deine Umsätze liegen auf deinem Gerät, nicht in einer Cloud. wimg heißt „Wo ist mein Geld?“."),
            Faq("Kostet wimg etwas?", "Nein. wimg ist kostenlos, ohne Werbung, und der Quellcode ist offen auf GitHub."),
            Faq("Funktioniert wimg ohne Internet?", "Ja. Übersicht, Umsätze, Kategorien und CSV-Import gehen offline. Internet brauchst du nur für den Bankabruf und für wimg Sync."),
        ),
    ),
    FaqGroup(
        "Bank & TAN",
        listOf(
            Faq("Welche Banken gehen?", "Fast alle deutschen Banken mit FinTS, rund 1.700. Am meisten getestet ist comdirect. Ohne FinTS kannst du CSV-Dateien von Comdirect, Trade Republic und Scalable importieren."),
            Faq("Warum verlangt meine Bank eine TAN?", "Banken verlangen eine TAN beim ersten Anmelden und für Umsätze, die älter als 90 Tage sind. Die Schnellabfrage holt deshalb nur die letzten 90 Tage, meist ohne TAN."),
            Faq("Warum fehlen ältere Umsätze?", "Beim ersten Abruf holt wimg so weit zurück, wie du gewählt hast und deine Bank erlaubt. Danach nur noch die letzten 90 Tage. Ältere Umsätze kannst du per CSV ergänzen."),
            Faq("Wo liegt meine Bank-PIN?", "Nur auf diesem Telefon, und nur, wenn du „PIN merken“ einschaltest. wimg verschlüsselt sie mit einem Schlüssel, der den sicheren Speicher deines Telefons (Android Keystore) nie verlässt. Sie wird nie synchronisiert und landet in keinem Backup."),
        ),
    ),
    FaqGroup(
        "Sync",
        listOf(
            Faq("Sieht der Server meine Umsätze?", "Nein. wimg verschlüsselt alles auf deinem Gerät, bevor es zum Server geht. Ohne deinen Sync-Schlüssel sind die Daten dort unlesbar. Ausnahme: Verbindest du Claude oder einen anderen KI-Assistenten per MCP, entschlüsselt der Server deine Daten für diese Anfrage mit deinem Schlüssel."),
            Faq("Ich habe den Sync-Schlüssel verloren", "Solange ein Gerät verknüpft ist, findest du ihn dort unter Einstellungen › wimg Sync › Sync-Schlüssel anzeigen. Ist kein Gerät mehr verknüpft, kann niemand die Daten wiederherstellen, auch wimg nicht."),
            Faq("Wie verbinde ich ein zweites Gerät?", "Auf dem ersten Gerät den Sync-Schlüssel anzeigen. Auf dem zweiten „Ich nutze wimg schon“ wählen und den Schlüssel einfügen."),
        ),
    ),
    FaqGroup(
        "Daten & Sicherheit",
        listOf(
            Faq("Was passiert, wenn ich mein Handy verliere?", "Mit der App-Sperre kommt ohne Fingerabdruck oder Geräte-PIN niemand in wimg. Mit wimg Sync holst du deine Daten auf ein neues Gerät, wenn du den Sync-Schlüssel hast. Ohne Sync und ohne Backup-Datei sind sie weg, denn es gibt sonst keine Kopie."),
            Faq("Wie sichere ich meine Daten?", "Einstellungen › Daten › Backup-Datei. Die Datei ist nicht verschlüsselt, bewahre sie auf wie einen Kontoauszug."),
            Faq("Wie lösche ich alles?", "Einstellungen › Alle Daten löschen. Das löscht alles auf diesem Gerät und beendet wimg Sync hier. Andere verknüpfte Geräte behalten ihre Kopie."),
        ),
    ),
)

/** Bold + tinted matches of the query (case-insensitive) inside text. */
private fun highlight(text: String, query: String, bg: Color): AnnotatedString = buildAnnotatedString {
    if (query.isBlank()) { append(text); return@buildAnnotatedString }
    var i = 0
    val lower = text.lowercase(); val q = query.lowercase()
    while (i < text.length) {
        val j = lower.indexOf(q, i)
        if (j < 0) { append(text.substring(i)); break }
        append(text.substring(i, j))
        withStyle(SpanStyle(background = bg)) { append(text.substring(j, j + q.length)) }
        i = j + q.length
    }
}

@Composable
fun AboutFaqScreen(navController: NavController?) {
    val c = Wimg.colors
    var query by remember { mutableStateOf("") }
    var open by remember { mutableStateOf<String?>(null) }
    val q = query.trim()
    val groups = FAQ.map { g -> g to g.items.filter { q.isEmpty() || L(it.q).contains(q, true) || L(it.a).contains(q, true) } }.filter { it.second.isNotEmpty() }
    val count = groups.sumOf { it.second.size }
    val mark = Color(0xFFF2C14E).copy(alpha = 0.32f)

    AboutPage(L("Über wimg"), L("Häufige Fragen"), L("Über wimg"), navController) {
        Row(
            Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, if (q.isEmpty()) c.line else c.accent, WimgShape.group).padding(horizontal = 14.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Search, contentDescription = null, tint = c.text2, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) Text(L("Frage suchen"), style = WimgType.body, color = c.text2)
                BasicTextField(query, { query = it }, singleLine = true, textStyle = WimgType.body.copy(color = c.text), cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth())
            }
            if (query.isNotEmpty()) Icon(Icons.Outlined.Close, contentDescription = L("Suche leeren"), tint = c.text2, modifier = Modifier.size(20.dp).clickable { query = "" })
        }
        if (q.isNotEmpty()) Text(if (count == 1) L("1 Frage") else L("%d Fragen", count), style = WimgType.desc, color = c.text2, modifier = Modifier.padding(start = 4.dp, top = 12.dp))
        groups.forEach { (g, items) ->
            if (q.isEmpty()) GroupLabel(L(g.title))
            Column(Modifier.padding(top = if (q.isEmpty()) 0.dp else 10.dp).fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group)) {
                items.forEachIndexed { i, f ->
                    // While searching, the best (first) match opens by itself.
                    val expanded = open == f.q || (q.isNotEmpty() && open == null && g == groups.first().first && i == 0)
                    if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(c.line))
                    Column(
                        Modifier.fillMaxWidth().background(if (expanded) c.accentSoft else Color.Transparent)
                            .clickable { open = if (expanded) "" else f.q }.padding(horizontal = 16.dp, vertical = 14.dp),
                    ) {
                        Row(verticalAlignment = Alignment.Top) {
                            Text(highlight(L(f.q), q, mark), style = WimgType.rowTitle.copy(fontWeight = FontWeight.Bold), color = c.text, modifier = Modifier.weight(1f))
                            Spacer(Modifier.width(10.dp))
                            Icon(if (expanded) Icons.Outlined.Remove else Icons.Outlined.Add, contentDescription = null, tint = if (expanded) c.accent else c.text2, modifier = Modifier.size(22.dp))
                        }
                        if (expanded) Text(highlight(L(f.a), q, mark), style = WimgType.body, color = c.text, modifier = Modifier.padding(top = 8.dp))
                    }
                }
            }
        }
        if (q.isNotEmpty() && count == 0) Text(L("Keine Frage gefunden."), style = WimgType.body, color = c.text2, modifier = Modifier.padding(start = 4.dp, top = 14.dp))
        QuietLine(L("Nicht dabei? Unter „Problem melden“ kannst du fragen. Das ist öffentlich auf GitHub, schreib also keine Kontodaten hinein."), icon = Icons.AutoMirrored.Outlined.HelpOutline)
    }
}

// ---------------------------------------------------------------------------
// So bleiben deine Daten bei dir
// ---------------------------------------------------------------------------

@Composable
fun AboutPrivacyScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    val places = listOf(
        Triple(Icons.Outlined.PhoneAndroid, L("Auf diesem Telefon"), L("Alles: Umsätze, Kategorien, Regeln und, wenn du sie merkst, deine Bank-PIN, zusätzlich verschlüsselt. Nichts davon geht in ein Google-Backup.")),
        Triple(Icons.Outlined.Cloud, L("Auf dem Sync-Server"), L("Nur wenn du Sync nutzt, und nur verschlüsselt. Ohne deinen Schlüssel unlesbar. Verbindest du Claude per MCP, entschlüsselt der Server deine Daten für diese Anfrage.")),
        Triple(Icons.Outlined.AccountBalance, L("Bei deiner Bank"), L("Was sie ohnehin hat. wimg fragt direkt bei ihr an, ohne Dienst dazwischen.")),
        Triple(Icons.Outlined.Close, L("Sonst nirgends"), L("Keine Kopie bei Dritten, kein Konto, das man hacken könnte.")),
    )
    AboutPage(L("Über wimg"), L("So bleiben deine Daten bei dir"), L("Über wimg"), navController) {
        Column(Modifier.fillMaxWidth().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(16.dp)) {
            places.forEachIndexed { i, (icon, title, desc) ->
                Row(Modifier.height(androidx.compose.foundation.layout.IntrinsicSize.Min)) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        val last = i == places.lastIndex
                        val (bg, fg) = when (i) { 0 -> c.accentSoft to c.accent; places.lastIndex -> c.dangerBg to c.danger; else -> c.neutralTint to c.text }
                        Box(Modifier.size(42.dp).clip(RoundedCornerShape(12.dp)).background(bg), contentAlignment = Alignment.Center) {
                            Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(21.dp))
                        }
                        if (!last) Box(Modifier.width(2.dp).weight(1f).background(c.line))
                    }
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.padding(bottom = if (i == places.lastIndex) 0.dp else 18.dp)) {
                        Text(title, style = WimgType.rowTitle.copy(fontWeight = FontWeight.Bold), color = c.text)
                        Text(desc, style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 2.dp))
                    }
                }
            }
        }
        GroupLabel(L("Was wimg nie macht"))
        listOf(L("Kein Konto") to L("Keine Werbung"), L("Kein Tracking") to L("Keine Daten an Dritte")).forEach { (a, b) ->
            Row(Modifier.padding(bottom = 10.dp).fillMaxWidth().height(androidx.compose.foundation.layout.IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                listOf(a, b).forEach { t ->
                    Row(
                        Modifier.weight(1f).fillMaxHeight().clip(WimgShape.group).background(c.card).border(1.dp, c.line, WimgShape.group).padding(horizontal = 14.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.Close, contentDescription = null, tint = c.danger, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(10.dp))
                        Text(t, style = WimgType.rowTitle.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                    }
                }
            }
        }
        Row(
            Modifier.padding(top = 6.dp).clip(WimgShape.dockAction).clickable { open(context, "$SITE/datenschutz.html") }.padding(horizontal = 4.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(L("Ganze Datenschutzerklärung lesen"), style = WimgType.button, color = c.accent)
            Spacer(Modifier.width(8.dp))
            Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null, tint = c.accent, modifier = Modifier.size(18.dp))
        }
    }
}

// ---------------------------------------------------------------------------
// Lizenzen
// ---------------------------------------------------------------------------

private class Lib(val name: String, val licence: String, val url: String)

private const val APACHE = "https://www.apache.org/licenses/LICENSE-2.0"
private const val OFL = "https://openfontlicense.org/open-font-license-official-text/"

/** What the Android app actually ships (app/build.gradle.kts, libwimg, res/font). */
private val LIBS = listOf(
    Lib("wimg", "MIT", "$REPO/blob/main/LICENSE"),
    Lib("SQLite", "Public Domain", "https://sqlite.org/copyright.html"),
    Lib("Zig Standardbibliothek", "MIT", "https://github.com/ziglang/zig/blob/master/LICENSE"),
    Lib("Kotlin", "Apache-2.0", APACHE),
    Lib("Jetpack Compose, AndroidX", "Apache-2.0", APACHE),
    Lib("Material Icons", "Apache-2.0", APACHE),
    Lib("kotlinx.serialization", "Apache-2.0", APACHE),
    Lib("OkHttp, Okio", "Apache-2.0", APACHE),
    Lib("ZXing", "Apache-2.0", APACHE),
    Lib("Manrope", "SIL OFL 1.1", OFL),
    Lib("Inter", "SIL OFL 1.1", OFL),
    Lib("JetBrains Mono", "SIL OFL 1.1", OFL),
)

@Composable
fun AboutLicensesScreen(navController: NavController?) {
    val context = LocalContext.current
    val c = Wimg.colors
    AboutPage(L("Über wimg"), L("Lizenzen"), L("Über wimg"), navController) {
        WimgGroup {
            LIBS.forEachIndexed { i, lib ->
                if (i > 0) RowDivider()
                WimgRow(L(lib.name), desc = lib.licence, trailing = { ExternalArrow() }, onClick = { open(context, lib.url) })
            }
        }
        QuietLine(L("Danke an alle, die diese Bibliotheken bauen. Die Lizenztexte öffnen sich im Browser."))
    }
}
