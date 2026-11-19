import SwiftUI
import WimgI18n

struct AboutView: View {
    var scrollToFAQ: String?

    /// The FAQ as on Android (AboutScreen.kt); bank PIN and lost phone in their iOS form.
    private static let faqGroups: [(title: String, items: [(q: String, a: String)])] = [
        ("Grundlagen", [
            ("Was ist wimg?", "Eine App, die zeigt, wohin dein Geld geht. Deine Umsätze liegen auf deinem Gerät, nicht in einer Cloud. wimg heißt „Wo ist mein Geld?“."),
            ("Kostet wimg etwas?", "Nein. wimg ist kostenlos, ohne Werbung, und der Quellcode ist offen auf GitHub."),
            ("Funktioniert wimg ohne Internet?", "Ja. Übersicht, Umsätze, Kategorien und CSV-Import gehen offline. Internet brauchst du nur für den Bankabruf und für wimg Sync."),
        ]),
        ("Bank & TAN", [
            ("Welche Banken gehen?", "Fast alle deutschen Banken mit FinTS, rund 1.700. Am meisten getestet ist comdirect. Ohne FinTS kannst du CSV-Dateien von Comdirect, Trade Republic und Scalable importieren."),
            ("Warum verlangt meine Bank eine TAN?", "Banken verlangen eine TAN beim ersten Anmelden und für Umsätze, die älter als 90 Tage sind. Die Schnellabfrage holt deshalb nur die letzten 90 Tage, meist ohne TAN."),
            ("Warum fehlen ältere Umsätze?", "Beim ersten Abruf holt wimg so weit zurück, wie du gewählt hast und deine Bank erlaubt. Danach nur noch die letzten 90 Tage. Ältere Umsätze kannst du per CSV ergänzen."),
            ("Wo liegt meine Bank-PIN?", "Nur auf diesem iPhone, und nur, wenn du „PIN merken“ einschaltest: im Schlüsselbund von iOS, nur für wimg lesbar. Sie wird nie synchronisiert."),
        ]),
        ("Sync", [
            ("Sieht der Server meine Umsätze?", "Nein. wimg verschlüsselt alles auf deinem Gerät, bevor es zum Server geht. Ohne deinen Sync-Schlüssel sind die Daten dort unlesbar. Ausnahme: Verbindest du Claude oder einen anderen KI-Assistenten per MCP, entschlüsselt der Server deine Daten für diese Anfrage mit deinem Schlüssel."),
            ("Ich habe den Sync-Schlüssel verloren", "Solange ein Gerät verknüpft ist, findest du ihn dort unter Einstellungen › wimg Sync › Sync-Schlüssel anzeigen. Ist kein Gerät mehr verknüpft, kann niemand die Daten wiederherstellen, auch wimg nicht."),
            ("Wie verbinde ich ein zweites Gerät?", "Auf dem ersten Gerät den Sync-Schlüssel anzeigen. Auf dem zweiten „Ich nutze wimg schon“ wählen und den Schlüssel einfügen."),
        ]),
        ("Daten & Sicherheit", [
            ("Was passiert, wenn ich mein Handy verliere?", "Mit der App-Sperre kommt ohne Face ID, Touch ID oder Gerätecode niemand in wimg. Mit wimg Sync holst du deine Daten auf ein neues Gerät, wenn du den Sync-Schlüssel hast. Ohne Sync und ohne Backup-Datei sind sie weg, denn es gibt sonst keine Kopie."),
            ("Wie sichere ich meine Daten?", "Einstellungen › Daten › Exportieren und sichern. Die Backup-Datei ist nicht verschlüsselt, bewahre sie auf wie einen Kontoauszug."),
            ("Wie lösche ich alles?", "Einstellungen › Alle Daten löschen. Das löscht alles auf diesem Gerät und beendet wimg Sync hier. Andere verknüpfte Geräte behalten ihre Kopie."),
        ]),
    ]
    @State private var faqQuery = ""

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
                            .fill(Wimg.band)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Image(systemName: "creditcard")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(.white)
                            }

                        Circle()
                            .fill(Wimg.pos)
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
                            .font(WimgFont.font(.manrope, .bold, 28, relativeTo: .title))
                            .foregroundStyle(WimgTheme.text)

                        Text(#L("Persönliche Finanzverwaltung.") + "\n" + #L("Lokal. Privat. Offen."))
                            .font(.subheadline)
                            .foregroundStyle(WimgTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)

                // MARK: - About Text
                // LocalizedStringKey: the bold parts are Markdown.
                Text(LocalizedStringKey(#L("Ein Open-Source-Projekt von **Komiljon Maksudov**. Gebaut mit **Zig**, **SwiftUI** und **SQLite**.")))
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
                            .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
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
                        .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
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
                            .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
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
                            .font(WimgFont.font(.manrope, .bold, 20, relativeTo: .title3))
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
                                .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
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
                            .font(WimgFont.font(.manrope, .bold, 20, relativeTo: .title3))
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

                // MARK: - FAQ (grouped and searchable, as on Android)
                VStack(alignment: .leading, spacing: 0) {
                    Text(#L("Häufige Fragen")).wimgStyle(WimgType.section).foregroundStyle(Wimg.text)
                        .padding(.bottom, 10)
                    SearchField(text: $faqQuery, prompt: L("Frage suchen"))
                    let q = faqQuery.trimmingCharacters(in: .whitespaces)
                    let groups = Self.faqGroups.map { g in
                        (g.title, g.items.filter { q.isEmpty || L($0.q).localizedCaseInsensitiveContains(q) || L($0.a).localizedCaseInsensitiveContains(q) })
                    }.filter { !$0.1.isEmpty }
                    ForEach(groups, id: \.0) { title, items in
                        if q.isEmpty { GroupLabel(text: L(title)) } else { Spacer().frame(height: 10) }
                        WimgGroup {
                            ForEach(Array(items.enumerated()), id: \.element.q) { i, faq in
                                if i > 0 { RowDivider() }
                                let open = expandedFAQ == faq.q
                                Button { withAnimation(WimgMotion.out(0.2)) { expandedFAQ = open ? nil : faq.q } } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top) {
                                            Text(L(faq.q)).font(WimgFont.font(.inter, .bold, 15)).foregroundStyle(Wimg.text)
                                                .multilineTextAlignment(.leading)
                                            Spacer(minLength: 10)
                                            Image(systemName: open ? "minus" : "plus").foregroundStyle(open ? Wimg.accent : Wimg.text2)
                                        }
                                        if open {
                                            Text(L(faq.a)).wimgStyle(WimgType.body).foregroundStyle(Wimg.text)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(open ? Wimg.accentSoft : .clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(faq.q)
                                .accessibilityAddTraits(open ? .isSelected : [])
                            }
                        }
                    }
                    if !q.isEmpty && groups.isEmpty {
                        Text(L("Keine Frage gefunden.")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).padding(.top, 14)
                    }
                }

                // MARK: - Footer
                VStack(spacing: 8) {
                    Link(destination: URL(string: WimgConfig.releasesURL)!) {
                        Text(#L("Was ist neu?"))
                            .font(WimgFont.font(.inter, .bold, 12, relativeTo: .caption))
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
                    .font(WimgFont.font(.inter, .semibold, 12, relativeTo: .caption))
                    .foregroundStyle(WimgTheme.text)
                Text(L(detail))
                    .font(WimgFont.font(.inter, .regular, 11, relativeTo: .caption2))
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
                    .font(WimgFont.font(.inter, .semibold, 12, relativeTo: .caption))
                    .foregroundStyle(WimgTheme.text)
                Text(L(detail))
                    .font(WimgFont.font(.inter, .regular, 11, relativeTo: .caption2))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
    }

    private func mcpStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(WimgFont.font(.inter, .bold, 12, relativeTo: .caption))
                .foregroundStyle(WimgTheme.heroText)
                .frame(width: 28, height: 28)
                .background(WimgTheme.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(L(title))
                    .font(WimgFont.font(.inter, .semibold, 15, relativeTo: .subheadline))
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
