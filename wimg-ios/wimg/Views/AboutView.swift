import SwiftUI
import WimgI18n

private let repo = "https://github.com/komiljonmaksudov/wimg"
private let site = "https://wimg.komiljonmaksudov.com"

/// Über wimg (as Android's AboutScreen): the app, help, privacy, the project.
/// The FAQ, privacy and licences are pages of their own.
struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        BandScreen(title: L("Über wimg"), pushed: true) {
            HStack(spacing: 16) {
                Image("AppMark").resizable().scaledToFit().frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("wimg").wimgStyle(WimgType.title).foregroundStyle(.white)
                    Text(L("Wo ist mein Geld?")).wimgStyle(WimgType.body).foregroundStyle(Wimg.bandSub)
                }
            }
            .padding(.bottom, 4)
        } sheet: {
            GroupLabel(text: L("App"))
            WimgGroup {
                WimgRow(title: L("Version")) {
                    IconTile(systemImage: "info.circle", tint: Wimg.text)
                } trailing: {
                    Text(version).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                }
                RowDivider()
                link(L("Neuigkeiten"), desc: L("Auf GitHub"), icon: "gift", url: WimgConfig.releasesURL)
            }
            GroupLabel(text: L("Hilfe"))
            WimgGroup {
                NavigationLink(value: MorePage.faq) {
                    WimgRow(title: L("Häufige Fragen"), chevron: true) { IconTile(systemImage: "questionmark.circle", tint: Wimg.text) }
                }
                .buttonStyle(.plain)
                RowDivider()
                link(L("Problem melden"), desc: L("Öffnet GitHub. Was du dort schreibst, ist öffentlich."), icon: "ladybug", url: repo + "/issues/new")
            }
            GroupLabel(text: L("Datenschutz"))
            WimgGroup {
                NavigationLink(value: MorePage.privacy) {
                    WimgRow(title: L("So bleiben deine Daten bei dir"), chevron: true) { IconTile(systemImage: "shield", tint: Wimg.accent) }
                }
                .buttonStyle(.plain)
                RowDivider()
                link(L("Datenschutzerklärung"), desc: L("Auf der Website"), icon: "doc.text", url: site + "/datenschutz.html")
            }
            GroupLabel(text: L("Projekt"))
            WimgGroup {
                link(L("Quellcode auf GitHub"), icon: "chevron.left.forwardslash.chevron.right", url: repo)
                RowDivider()
                NavigationLink(value: MorePage.licenses) {
                    WimgRow(title: L("Lizenzen"), desc: L("Offene Bibliotheken, die wimg nutzt"), chevron: true) {
                        IconTile(systemImage: "building.columns", tint: Wimg.text)
                    }
                }
                .buttonStyle(.plain)
                RowDivider()
                link(L("Website"), icon: "globe", url: site)
            }
            QuietLine(text: L("Kein Tracking, keine Werbung."))
        }
    }

    private func link(_ title: String, desc: String? = nil, icon: String, url: String) -> some View {
        WimgRow(title: title, desc: desc, action: { if let u = URL(string: url) { openURL(u) } }) {
            IconTile(systemImage: icon, tint: Wimg.text)
        } trailing: {
            Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Wimg.text3)
        }
    }
}

/// Häufige Fragen: grouped and searchable, as on Android.
struct AboutFAQView: View {
    /// The FAQ as on Android (AboutScreen.kt); bank PIN and lost phone in their iOS form.
    static let faqGroups: [(title: String, items: [(q: String, a: String)])] = [
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
    @State private var query = ""
    @State private var open: String?

    var body: some View {
        BandScreen(title: L("Häufige Fragen"), pushed: true) {
            Text(L("Über wimg")).wimgStyle(WimgType.bandOver).foregroundStyle(Wimg.bandSub)
        } sheet: {
            SearchField(text: $query, prompt: L("Frage suchen"))
            let q = query.trimmingCharacters(in: .whitespaces)
            let groups = Self.faqGroups.map { g in
                (g.title, g.items.filter { q.isEmpty || L($0.q).localizedCaseInsensitiveContains(q) || L($0.a).localizedCaseInsensitiveContains(q) })
            }.filter { !$0.1.isEmpty }
            ForEach(groups, id: \.0) { title, items in
                if q.isEmpty { GroupLabel(text: L(title)) } else { Spacer().frame(height: 10) }
                WimgGroup {
                    ForEach(Array(items.enumerated()), id: \.element.q) { i, faq in
                        if i > 0 { RowDivider() }
                        let isOpen = open == faq.q
                        Button { withAnimation(WimgMotion.out(0.2)) { open = isOpen ? nil : faq.q } } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    Text(L(faq.q)).font(WimgFont.font(.inter, .bold, 15)).foregroundStyle(Wimg.text)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 10)
                                    Image(systemName: isOpen ? "minus" : "plus").foregroundStyle(isOpen ? Wimg.accent : Wimg.text2)
                                }
                                if isOpen {
                                    Text(L(faq.a)).wimgStyle(WimgType.body).foregroundStyle(Wimg.text)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isOpen ? Wimg.accentSoft : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOpen ? .isSelected : [])
                    }
                }
            }
            if !q.isEmpty && groups.isEmpty {
                Text(L("Keine Frage gefunden.")).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).padding(.top, 14)
            }
            QuietLine(text: L("Nicht dabei? Unter „Problem melden“ kannst du fragen. Das ist öffentlich auf GitHub, schreib also keine Kontodaten hinein."),
                      systemImage: "questionmark.circle")
        }
    }
}

/// Where the data is, as Android's AboutPrivacyScreen.
struct AboutPrivacyView: View {
    @Environment(\.openURL) private var openURL

    private let places: [(icon: String, title: String, desc: String)] = [
        ("iphone", "Auf diesem iPhone", "Alles: Umsätze, Kategorien, Regeln und, wenn du sie merkst, deine Bank-PIN im Schlüsselbund von iOS."),
        ("cloud", "Auf dem Sync-Server", "Nur wenn du Sync nutzt, und nur verschlüsselt. Ohne deinen Schlüssel unlesbar. Verbindest du Claude per MCP, entschlüsselt der Server deine Daten für diese Anfrage."),
        ("building.columns", "Bei deiner Bank", "Was sie ohnehin hat. wimg fragt direkt bei ihr an, ohne Dienst dazwischen."),
        ("xmark", "Sonst nirgends", "Keine Kopie bei Dritten, kein Konto, das man hacken könnte."),
    ]

    var body: some View {
        BandScreen(title: L("So bleiben deine Daten bei dir"), pushed: true) {
            Text(L("Über wimg")).wimgStyle(WimgType.bandOver).foregroundStyle(Wimg.bandSub)
        } sheet: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(places.enumerated()), id: \.offset) { i, p in
                    let last = i == places.count - 1
                    let (bg, fg): (Color, Color) = i == 0 ? (Wimg.accentSoft, Wimg.accent) : last ? (Wimg.dangerBg, Wimg.danger) : (Wimg.neutralTint, Wimg.text)
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Image(systemName: p.icon).font(.system(size: 18)).foregroundStyle(fg)
                                .frame(width: 42, height: 42).background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            if !last { Rectangle().fill(Wimg.line).frame(width: 2).frame(maxHeight: .infinity) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L(p.title)).font(WimgFont.font(.inter, .bold, 16)).foregroundStyle(Wimg.text)
                            Text(L(p.desc)).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, last ? 0 : 18)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))

            GroupLabel(text: L("Was wimg nie macht"))
            ForEach([("Kein Konto", "Keine Werbung"), ("Kein Tracking", "Keine Daten an Dritte")], id: \.0) { a, b in
                HStack(spacing: 10) { never(a); never(b) }.padding(.bottom, 10)
            }
            Button { if let u = URL(string: site + "/datenschutz.html") { openURL(u) } } label: {
                HStack(spacing: 8) {
                    Text(L("Ganze Datenschutzerklärung lesen")).wimgStyle(WimgType.button)
                    Image(systemName: "arrow.up.right")
                }
                .foregroundStyle(Wimg.accent)
                .padding(.vertical, 8).padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private func never(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Wimg.danger)
            Text(L(text)).font(WimgFont.font(.inter, .semibold, 15)).foregroundStyle(Wimg.text)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))
    }
}

/// What the iOS app ships, with links to the licence texts.
struct AboutLicensesView: View {
    @Environment(\.openURL) private var openURL
    private let apache = "https://www.apache.org/licenses/LICENSE-2.0"
    private let ofl = "https://openfontlicense.org/open-font-license-official-text/"

    private var libs: [(String, String, String)] {[
        ("wimg", "MIT", repo + "/blob/main/LICENSE"),
        ("SQLite", "Public Domain", "https://sqlite.org/copyright.html"),
        ("Zig Standardbibliothek", "MIT", "https://github.com/ziglang/zig/blob/master/LICENSE"),
        ("Swift, SwiftUI", "Apache-2.0", apache),
        ("Manrope", "SIL OFL 1.1", ofl),
        ("Inter", "SIL OFL 1.1", ofl),
        ("JetBrains Mono", "SIL OFL 1.1", ofl),
    ]}

    var body: some View {
        BandScreen(title: L("Lizenzen"), pushed: true) {
            Text(L("Über wimg")).wimgStyle(WimgType.bandOver).foregroundStyle(Wimg.bandSub)
        } sheet: {
            WimgGroup {
                ForEach(Array(libs.enumerated()), id: \.offset) { i, lib in
                    if i > 0 { RowDivider() }
                    WimgRow(title: L(lib.0), desc: lib.1, action: { if let u = URL(string: lib.2) { openURL(u) } }) {
                        EmptyView()
                    } trailing: {
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Wimg.text3)
                    }
                }
            }
            QuietLine(text: L("Danke an alle, die diese Bibliotheken bauen. Die Lizenztexte öffnen sich im Browser."))
        }
    }
}
