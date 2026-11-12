package com.wimg.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard
import com.wimg.app.i18n.L

private data class FAQ(val q: String, val a: String)

// FAQ list mirrors wimg-web/src/routes/(app)/about/+page.svelte (minus the
// web-only "DevTools" entry). Keep both in sync when adding entries.
private val faqs = listOf(
    FAQ("Sind meine Daten sicher?", "Ja. Alle Finanzdaten werden lokal in einer SQLite-Datenbank auf deinem Gerät gespeichert. Sync ist Ende-zu-Ende verschlüsselt — der Server sieht nur Chiffretext."),
    FAQ("Welche Banken werden unterstützt?", "CSV-Import von Comdirect, Trade Republic und Scalable Capital. Da wimg Open-Source ist, können weitere Formate jederzeit hinzugefügt werden."),
    FAQ("Wie funktioniert der Import?", "Lade deinen Kontoauszug im CSV-Format hoch. wimg erkennt das Format automatisch, analysiert die Transaktionen lokal und kategorisiert sie mit intelligenten Regeln."),
    FAQ("Wie funktioniert die Kategorisierung?", "wimg nutzt ein Regel-System mit Schlüsselwörtern. Bekannte Händler (REWE, LIDL, etc.) werden automatisch erkannt. Wenn du eine Transaktion manuell kategorisierst, lernt wimg das Muster und wendet es zukünftig automatisch an. Für den Rest hilft Claude per MCP."),
    FAQ("Ist wimg wirklich kostenlos?", "Ja. wimg ist ein Leidenschaftsprojekt unter Open-Source-Lizenz. Keine Abonnements, keine versteckten Kosten, kein Verkauf deiner Daten."),
    FAQ("Wo werden die Daten gespeichert?", "Im Browser: OPFS (Origin Private File System). Auf Android: lokale SQLite-Datei. Deine Daten verlassen dein Gerät nur bei aktivierter Sync — dann Ende-zu-Ende verschlüsselt."),
    FAQ("Was ist der MCP-Server?", "Mit aktivierter Synchronisierung wird dein Sync-Schlüssel zum MCP-Zugang. Claude.ai oder andere KI-Tools können Ausgaben abfragen und Kategorien setzen — Ende-zu-Ende verschlüsselt, in Echtzeit synchronisiert."),
    FAQ("Wie funktioniert Auto-Learn?", "Wenn du eine Transaktion manuell kategorisierst, lernt wimg automatisch das Schlüsselwort (z.B. \"REWE\" → Lebensmittel). Beim nächsten Import oder Auto-Kategorisieren werden ähnliche Transaktionen automatisch zugeordnet."),
    FAQ("Wie synchronisiere ich zwischen Geräten?", "Gehe zu Einstellungen → Sync aktivieren. Kopiere den Sync-Schlüssel und füge ihn auf dem zweiten Gerät ein. Änderungen werden in Echtzeit per WebSocket synchronisiert — Ende-zu-Ende verschlüsselt."),
    FAQ("Wie erkennt wimg Abos und wiederkehrende Zahlungen?", "wimg analysiert deine Transaktionen automatisch und erkennt regelmäßige Muster (monatlich, vierteljährlich, jährlich). Unter Mehr → Wiederkehrend siehst du alle erkannten Abos mit Betrag, Intervall und dem nächsten Fälligkeitsdatum."),
    FAQ("Funktioniert wimg offline?", "Ja, vollständig. Alle Daten liegen lokal in SQLite. Du brauchst kein Internet für Import, Kategorisierung, Analyse oder irgendeine Kernfunktion. Sync ist optional und funktioniert nur bei Internetverbindung."),
    FAQ("Gibt es eine iOS-App?", "Ja! wimg gibt es als native SwiftUI-App für iPhone. Tritt der TestFlight-Beta bei. Volle Feature-Parität mit der Web-App inklusive FinTS-Bankverbindung, Sync und Dark Mode."),
    FAQ("Gibt es eine Android-App?", "Ja, das ist sie! Native Kotlin/Compose-App mit voller Feature-Parität zu iOS und Web."),
    FAQ("Gibt es einen Dark Mode?", "Ja! In den Einstellungen kannst du zwischen Hell, Dunkel und System wählen. Der Dark Mode hat ein Premium-Design mit dunklem Hintergrund und dezenten Akzenten."),
    FAQ("Kann ich mehrere Konten verwalten?", "Ja. Über den Konto-Switcher oben rechts kannst du zwischen Konten wechseln oder alle anzeigen. Neue Konten werden beim CSV-Import automatisch erstellt oder können manuell angelegt werden."),
    FAQ("Kann ich Änderungen rückgängig machen?", "Ja. Nach jeder Aktion (Kategorisierung, Konto-Änderung etc.) erscheint ein Undo-Toast am unteren Bildschirmrand. Über die Suche findest du auch Rückgängig und Wiederherstellen. wimg speichert bis zu 50 Undo-Schritte."),
    FAQ("Wie lösche ich meine Daten?", "Unter Einstellungen → Danger Zone kannst du die Datenbank zurücksetzen. Diese Aktion kann nicht rückgängig gemacht werden."),
    FAQ("Wie kann ich beitragen?", "Besuche das GitHub-Repository. Code, Übersetzungen, Feedback und Bug-Reports sind willkommen."),
)

private data class PrivacyRow(val icon: ImageVector, val title: String, val desc: String)

private val privacyRows = listOf(
    PrivacyRow(Icons.Outlined.Lock, "Lokal gespeichert", "SQLite-Datenbank auf deinem Gerät. Kein Cloud-Konto nötig."),
    PrivacyRow(Icons.Outlined.Key, "Ende-zu-Ende verschlüsselt", "Sync nutzt XChaCha20-Poly1305. Der Server sieht nur Chiffretext."),
    PrivacyRow(Icons.Outlined.AccountBalance, "FinTS direkt zur Bank", "Kein Drittanbieter zwischen dir und deiner Bank."),
    PrivacyRow(Icons.Outlined.VisibilityOff, "Kein Tracking", "Keine Analytics, kein Sentry, kein Google. Null Telemetrie."),
    PrivacyRow(Icons.Outlined.PersonOff, "Kein Account", "Kein Passwort, keine E-Mail. Dein Sync-Schlüssel ist deine Identität."),
    PrivacyRow(Icons.Outlined.Psychology, "KI sieht keine Klarnamen", "MCP-Antworten werden von IBANs, BICs und Namen bereinigt."),
)

@Composable
fun AboutScreen() {
    val context = LocalContext.current
    val version = try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "—"
    } catch (_: Exception) { "—" }
    var expandedFaq by remember { mutableStateOf<String?>(null) }

    fun openUrl(url: String) {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Hero
        item {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp),
            ) {
                Box {
                    Box(
                        modifier = Modifier.size(80.dp).clip(CircleShape).background(WimgColors.heroText),
                        contentAlignment = Alignment.Center,
                    ) { Text("💰", fontSize = 32.sp) }
                    Box(
                        modifier = Modifier.size(28.dp).clip(CircleShape).background(WimgCategory.INCOME.color).align(Alignment.BottomEnd),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Outlined.CheckCircle, null, tint = Color.White, modifier = Modifier.size(16.dp)) }
                }
                Spacer(Modifier.height(12.dp))
                Text("wimg", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                Text(
                    L("Persönliche Finanzverwaltung.\nLokal. Privat. Offen."),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    L("Von Komiljon Maksudov · Zig + Kotlin + SQLite"),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                )
            }
        }

        // Quick info grid: Privatsphäre + Open Source
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                QuickInfoCard(
                    modifier = Modifier.weight(1f),
                    icon = Icons.Outlined.Shield,
                    iconTint = WimgCategory.INCOME.color,
                    title = L("Privatsphäre"),
                    body = L("Keine Werbung. Kein Tracking. Niemals."),
                )
                QuickInfoCard(
                    modifier = Modifier.weight(1f),
                    icon = Icons.Outlined.Code,
                    iconTint = WimgCategory.SUBSCRIPTIONS.color,
                    title = L("Open Source"),
                    body = L("Quellcode offen auf GitHub verfügbar."),
                )
            }
        }

        // Privacy details
        item {
            Column(
                modifier = Modifier.fillMaxWidth().wimgCard().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(L("Datenschutz im Detail"),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                )
                privacyRows.forEach { row ->
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(
                            row.icon,
                            contentDescription = null,
                            tint = WimgCategory.INCOME.color,
                            modifier = Modifier.size(18.dp).padding(top = 2.dp),
                        )
                        Column {
                            Text(L(row.title), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                            Text(
                                L(row.desc),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }

        // GitHub button (filled, primary action)
        item {
            Button(
                onClick = { openUrl("https://github.com/milimyname/wimg") },
                modifier = Modifier.fillMaxWidth(),
                shape = WimgShapes.small,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.onSurface,
                    contentColor = MaterialTheme.colorScheme.surface,
                ),
            ) {
                Icon(Icons.Outlined.Code, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(L("Auf GitHub ansehen"), fontWeight = FontWeight.Bold)
            }
        }

        // MCP-Verbindung
        item {
            Column(
                modifier = Modifier.fillMaxWidth().wimgCard().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Outlined.Link, null, tint = WimgCategory.SUBSCRIPTIONS.color, modifier = Modifier.size(18.dp))
                    Text(L("MCP-Verbindung"), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                }
                Text(
                    L("Verbinde Claude.ai mit deinem wimg, um Finanzfragen mit deinen echten Daten zu beantworten. Aktiviere zuerst Sync unter Einstellungen, dann nutze:"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                MonoLine(label = "URL:", value = "https://wimg-sync.komiljonmaksudov.com/mcp")
                MonoLine(label = L("Auth:"), value = L("Bearer <dein Sync-Schlüssel>"))
                Spacer(Modifier.height(4.dp))
                Bullet(L("Sync-Schlüssel = MCP-Zugang, kein extra Setup"))
                Bullet(L("Ende-zu-Ende verschlüsselt, Echtzeit-Synchronisierung"))
                Bullet(L("PII wird automatisch aus MCP-Antworten entfernt"))
            }
        }

        // FAQ header
        item {
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Outlined.HelpOutline, null, tint = WimgColors.accent, modifier = Modifier.size(18.dp))
                Text(L("Häufig gestellte Fragen"),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                )
            }
        }

        items(faqs) { faq ->
            val isExpanded = expandedFaq == faq.q
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .wimgCard(WimgShapes.small)
                    .clickable { expandedFaq = if (isExpanded) null else faq.q }
                    .padding(16.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        L(faq.q),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f),
                    )
                    Icon(
                        if (isExpanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp),
                    )
                }
                AnimatedVisibility(visible = isExpanded) {
                    Text(
                        L(faq.a),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
            }
        }

        // Footer
        item {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                TextButton(
                    onClick = { openUrl("https://github.com/milimyname/wimg/releases") },
                ) {
                    Text(L("Was ist neu?"),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = WimgColors.accent,
                    )
                }
                Text(
                    "v$version",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                )
            }
        }
    }
}

@Composable
private fun QuickInfoCard(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    iconTint: Color,
    title: String,
    body: String,
) {
    Column(
        modifier = modifier.wimgCard(WimgShapes.small).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(iconTint.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = iconTint, modifier = Modifier.size(18.dp))
        }
        Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
        Text(
            body,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun MonoLine(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            value,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun Bullet(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("✓", color = WimgCategory.INCOME.color, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelSmall)
        Text(
            text,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
