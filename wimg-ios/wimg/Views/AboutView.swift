import SwiftUI
import WimgI18n

struct AboutView: View {
    var scrollToFAQ: String?

    // To be replaced by Android's FAQ (AboutScreen.kt) in the iOS catch-up.
    private let faqs: [(q: String, a: String)] = [
        ("Sind meine Daten sicher?",
         "Ja. Alle Finanzdaten werden lokal in einer SQLite-Datenbank auf deinem Gerät gespeichert. Sync ist Ende-zu-Ende verschlüsselt — der Server sieht nur Chiffretext."),
        ("Welche Banken werden unterstützt?",
         "Rund 1.700 deutsche Banken direkt per FinTS. Dazu Kontoauszüge (MT940, CAMT) von jeder Bank und CSV-Dateien von Comdirect, Trade Republic, Scalable und Revolut."),
        ("Wie funktioniert der Import?",
         "Lade deinen Kontoauszug im CSV-Format hoch. wimg erkennt das Format automatisch, analysiert die Transaktionen lokal und kategorisiert sie mit intelligenten Regeln."),
        ("Wie funktioniert die Kategorisierung?",
         "wimg nutzt ein Regel-System mit Schlüsselwörtern. Bekannte Händler (REWE, LIDL, etc.) werden automatisch erkannt. Wenn du eine Transaktion manuell kategorisierst, lernt wimg das Muster und wendet es zukünftig automatisch an. Für den Rest hilft Claude per MCP."),
        ("Ist wimg wirklich kostenlos?",
         "Ja. wimg ist ein Leidenschaftsprojekt unter Open-Source-Lizenz. Keine Abonnements, keine versteckten Kosten, kein Verkauf deiner Daten."),
        ("Wo werden die Daten gespeichert?",
         "In einer SQLite-Datei auf deinem Gerät. Deine Daten verlassen es nur bei aktivierter Sync, dann Ende-zu-Ende verschlüsselt."),
        ("Was ist der MCP-Server?",
         "Mit aktivierter Synchronisierung wird dein Sync-Schlüssel zum MCP-Zugang. Claude.ai oder andere KI-Tools können Ausgaben abfragen und Kategorien setzen — Ende-zu-Ende verschlüsselt, in Echtzeit synchronisiert."),
        ("Wie funktioniert Auto-Learn?",
         "Wenn du eine Transaktion manuell kategorisierst, lernt wimg automatisch das Schlüsselwort (z.B. \"REWE\" → Lebensmittel). Beim nächsten Import oder Auto-Kategorisieren werden ähnliche Transaktionen automatisch zugeordnet. Alle gelernten Regeln findest du unter Einstellungen → Regeln."),
        ("Wie synchronisiere ich zwischen Geräten?",
         "Gehe zu Einstellungen → Sync aktivieren. Dadurch wird ein einzigartiger Sync-Schlüssel erstellt. Kopiere diesen Schlüssel und füge ihn auf dem zweiten Gerät ein. Änderungen werden in Echtzeit per WebSocket synchronisiert — Ende-zu-Ende verschlüsselt."),
        ("Wie erkennt wimg Abos und wiederkehrende Zahlungen?",
         "wimg analysiert deine Transaktionen automatisch und erkennt regelmäßige Muster (monatlich, vierteljährlich, jährlich). Unter Mehr → Wiederkehrend siehst du alle erkannten Abos mit Betrag, Intervall und dem nächsten Fälligkeitsdatum."),
        ("Funktioniert wimg offline?",
         "Ja, vollständig. Alle Daten liegen lokal in SQLite. Import, Kategorien und Übersicht brauchen kein Internet. Nur Bankabruf und Sync brauchen eine Verbindung."),
        ("Gibt es eine iOS-App?",
         "Ja, du nutzt sie gerade. Neue Versionen kommen über TestFlight."),
        ("Gibt es eine Android-App?",
         "Ja, über Google Play (gerade im geschlossenen Test) oder als APK von wimg.komiljonmaksudov.com. Sync verbindet beide."),
        ("Gibt es einen Dark Mode?",
         "Ja! In den Einstellungen kannst du zwischen Hell, Dunkel und System wählen. Der Dark Mode hat ein Premium-Design mit dunklem Hintergrund und dezenten Akzenten."),
        ("Kann ich mehrere Konten verwalten?",
         "Ja. Über den Konto-Switcher oben rechts kannst du zwischen Konten wechseln oder alle anzeigen. Neue Konten werden beim CSV-Import automatisch erstellt oder können manuell in den Einstellungen angelegt werden."),
        ("Kann ich Änderungen rückgängig machen?",
         "Ja. Nach jeder Aktion (Kategorisierung, Konto-Änderung etc.) erscheint ein Undo-Toast am unteren Bildschirmrand. Über die Suche findest du auch \"Rückgängig\" und \"Wiederherstellen\". wimg speichert bis zu 50 Undo-Schritte — das funktioniert plattformübergreifend im selben Zig-Core."),
        ("Wie lösche ich meine Daten?",
         "Unter Einstellungen → Danger Zone kannst du die Datenbank zurücksetzen. Diese Aktion kann nicht rückgängig gemacht werden."),
        ("Wie kann ich beitragen?",
         "Besuche das GitHub-Repository. Code, Übersetzungen, Feedback und Bug-Reports sind willkommen."),
    ]

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    @State private var expandedFAQ: String?

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Hero
                VStack(spacing: 16) {
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(WimgTheme.heroText)
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                            .overlay {
                                Image(systemName: "creditcard")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(.white)
                            }

                        Circle()
                            .fill(.green)
                            .frame(width: 28, height: 28)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .offset(x: 4, y: 4)
                    }

                    VStack(spacing: 4) {
                        Text("wimg")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)

                        Text(#L("Persönliche Finanzverwaltung.\nLokal. Privat. Offen."))
                            .font(.subheadline)
                            .foregroundStyle(WimgTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)

                // MARK: - About Text
                Text(#L("Ein Open-Source-Projekt von **Komiljon Maksudov**. Gebaut mit **Zig**, **SwiftUI** und **SQLite**."))
                    .font(.subheadline)
                    .foregroundStyle(WimgTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // MARK: - Privacy Badge
                HStack(spacing: 16) {
                    Circle()
                        .fill(.green)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(#L("Privatsphäre zuerst"))
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                        Text(#L("Keine Werbung. Kein Tracking. Niemals."))
                            .font(.caption)
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // MARK: - Privacy Details
                VStack(alignment: .leading, spacing: 12) {
                    Text(#L("Datenschutz im Detail"))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)

                    privacyRow("lock.fill", "Lokal gespeichert", "SQLite-Datenbank auf deinem Gerät. Kein Cloud-Konto nötig.")
                    privacyRow("key.fill", "Ende-zu-Ende verschlüsselt", "Sync nutzt XChaCha20-Poly1305. Der Server sieht nur Chiffretext.")
                    privacyRow("building.columns", "FinTS direkt zur Bank", "Kein Drittanbieter zwischen dir und deiner Bank.")
                    privacyRow("eye.slash.fill", "Kein Tracking", "Keine Analytics, kein Sentry, kein Google. Null Telemetrie.")
                    privacyRow("person.fill.xmark", "Kein Account", "Kein Passwort, keine E-Mail. Dein Sync-Schlüssel ist deine Identität.")
                    privacyRow("brain.head.profile", "KI sieht keine Klarnamen", "MCP-Antworten werden von IBANs, BICs und Namen bereinigt.")
                }
                .padding(16)
                .background(WimgTheme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

                // MARK: - GitHub Button
                Link(destination: URL(string: "https://github.com/komiljonmaksudov/wimg")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.subheadline)
                        Text("GitHub")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(WimgTheme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(WimgTheme.text, lineWidth: 2)
                    }
                }

                // MARK: - MCP Connection Guide
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.title3)
                            .foregroundStyle(.purple)
                        Text(#L("MCP-Verbindung"))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                    }

                    Text(#L("Mit aktivierter Sync kannst du KI-Assistenten (Claude, etc.) per MCP-Protokoll Zugriff auf deine Finanzdaten geben."))
                        .font(.subheadline)
                        .foregroundStyle(WimgTheme.textSecondary)

                    // Steps
                    VStack(spacing: 8) {
                        mcpStep(number: 1, title: "Sync aktivieren", detail: "Unter Einstellungen einen Sync-Schlüssel erstellen.")
                        mcpStep(number: 2, title: "MCP-Client konfigurieren", detail: "In Claude Desktop oder Claude Code die folgende Konfiguration hinzufügen:")
                    }

                    // Config code block
                    Text("""
                    {
                      "mcpServers": {
                        "wimg": {
                          "command": "npx",
                          "args": [
                            "mcp-remote",
                            "https://wimg-sync.komiljonmaksudov.com/mcp",
                            "--header",
                            "Authorization: Bearer DEIN-SYNC-SCHLÜSSEL"
                          ]
                        }
                      }
                    }
                    """)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WimgTheme.text)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    mcpStep(number: 3, title: "Nutzen", detail: "Frage Claude z.B. \"Zeig mir meine Ausgaben diesen Monat\" oder \"Kategorisiere meine letzten Transaktionen\".")

                    // Privacy warning
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(#L("Datenschutz-Hinweis"))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.orange.opacity(0.9))
                            Text(#L("Wenn du wimg mit einem MCP-Client verbindest, werden deine Finanzdaten an diesen Client weitergegeben. Die Daten sind Ende-zu-Ende verschlüsselt zwischen deinen Geräten und dem Server, aber der MCP-Client selbst kann die entschlüsselten Daten lesen. Verwende nur vertrauenswürdige MCP-Clients und teile deinen Sync-Schlüssel niemals mit Dritten."))
                                .font(.caption)
                                .foregroundStyle(Color.orange.opacity(0.8))
                        }
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    }
                }

                // MARK: - Credits
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.circle")
                            .font(.title3)
                            .foregroundStyle(.pink)
                        Text(#L("Mit Hilfe von"))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                    }

                    creditRow(
                        "swift",
                        "Zig & SQLite",
                        "libwimg ist ein Zig-Kern mit eingebetteter SQLite-Amalgamation. Inspiriert von libghostty: Die Bibliothek IS die App."
                    )
                    creditRow(
                        "building.columns",
                        "FinTS-Bankenliste",
                        "Offizielle Bankenliste von www.fints.org / Die Deutsche Kreditwirtschaft."
                    )
                    creditRow(
                        "cloud",
                        "Eigener Server bei Hetzner",
                        "Sync-Server und MCP-Endpunkt in Zig, ohne Cloud-Anbieter dazwischen."
                    )
                    creditRow(
                        "swift",
                        "SwiftUI · Kotlin Compose",
                        "Zwei Plattform-Shells über einer Zig-Bibliothek."
                    )
                }
                .padding(16)
                .background(WimgTheme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

                // MARK: - FAQ
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        Text(#L("Häufig gestellte Fragen"))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                    }

                    VStack(spacing: 8) {
                        ForEach(faqs, id: \.q) { faq in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedFAQ == faq.q },
                                    set: { expandedFAQ = $0 ? faq.q : nil }
                                )
                            ) {
                                Text(L(faq.a))
                                    .font(.subheadline)
                                    .foregroundStyle(WimgTheme.textSecondary)
                                    .padding(.bottom, 4)
                            } label: {
                                Text(L(faq.q))
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(WimgTheme.text)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(16)
                            .wimgCard()
                            .id(faq.q)
                        }
                    }
                }

                // MARK: - Footer
                VStack(spacing: 8) {
                    Link(destination: URL(string: WimgConfig.releasesURL)!) {
                        Text(#L("Was ist neu?"))
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    Text(#L("Version \(appVersion)"))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(WimgTheme.textSecondary.opacity(0.6))
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            if let scrollToFAQ {
                expandedFAQ = scrollToFAQ
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { proxy.scrollTo(scrollToFAQ, anchor: .top) }
                }
            }
        }
        }
        .background(WimgTheme.bg)
        .navigationTitle(#L("Über wimg"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.pink)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(L(title))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(WimgTheme.text)
                Text(L(detail))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
    }

    private func privacyRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(L(title))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(WimgTheme.text)
                Text(L(detail))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
    }

    private func mcpStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.heroText)
                .frame(width: 28, height: 28)
                .background(WimgTheme.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(L(title))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(WimgTheme.text)
                Text(L(detail))
                    .font(.caption)
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .wimgCard()
    }
}
