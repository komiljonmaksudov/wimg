import SwiftUI
import WidgetKit
import WimgI18n

// Einstellungen › Zeitraum (Gehaltsmonat, board 26/09–10) and
// Einstellungen › Design und Sprache (board 20/03), as on Android.

// MARK: - Zeitraum

struct SettingsPeriodView: View {
    @State private var periods: Periods?
    @State private var choosingPayer = false

    private static let modes = ["salary", "calendar", "day"]

    var body: some View {
        BandScreen(title: L("Zeitraum"), pushed: true) {
            Text(L("Wann für wimg ein Monat beginnt."))
                .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub)
        } sheet: {
            if let p = periods {
                GroupLabel(text: L("Ein Monat beginnt"))
                Picker(L("Ein Monat beginnt"), selection: Binding(get: { p.chosen }, set: { setMode($0, day: $0 == "day" ? (p.day > 1 ? p.day : 15) : 0) })) {
                    Text(L("mit dem Gehalt")).tag("salary")
                    Text(L("am 1.")).tag("calendar")
                    Text(L("Fester Tag")).tag("day")
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 12)

                if p.chosen == "day" {
                    WimgGroup { dayStepper(p) }
                } else if let s = p.salary, p.isSalary {
                    WimgGroup {
                        WimgRow(title: "\(s.name) · \(amountText(s.amount ?? 0, showPlus: false))",
                                desc: L("meist um den %d. · %d× gesehen", s.day ?? 1, s.count ?? 0)) {
                            IconTile(systemImage: "banknote", tint: Wimg.pos)
                        } trailing: {
                            Button(L("Ändern")) { choosingPayer = true }
                                .wimgStyle(WimgType.chip).foregroundStyle(Wimg.accent)
                        }
                    }
                } else if p.chosen == "salary" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Gehalt noch nicht erkannt")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                        Text(L("wimg braucht zwei Gehälter vom selben Absender. Bis dahin zählt es nach Kalendermonat."))
                            .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                        Button(L("Gehalt selbst auswählen")) { choosingPayer = true }
                            .wimgStyle(WimgType.button).foregroundStyle(Wimg.accent)
                            .padding(.top, 6)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))
                }

                GroupLabel(text: L("Gilt für"))
                WimgGroup {
                    let on = p.chosen != "calendar"
                    WimgRow(title: L("Übersicht und Rückblick")) { EmptyView() } trailing: { check(on) }
                    RowDivider()
                    WimgRow(title: L("Wiederkehrend und Widgets")) { EmptyView() } trailing: { check(on) }
                    RowDivider()
                    WimgRow(title: L("Umsätze-Filter"), desc: L("Dort kannst du jederzeit auf Kalendermonate umschalten"))
                }
                QuietLine(text: note(p))
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in Task { await load() } }
        .sheet(isPresented: $choosingPayer) {
            if let p = periods { PayerSheet(periods: p) { choosingPayer = false; Task { await load() } } }
        }
    }

    private func note(_ p: Periods) -> String {
        if p.chosen == "salary" && !p.isSalary {
            return L("Du kannst „mit dem Gehalt“ schon wählen. wimg schaltet von selbst um, sobald es das zweite Gehalt sieht.")
        }
        if p.chosen == "day" { return L("Ein Monat läuft vom %d. bis zum Tag davor im nächsten Monat.", p.day) }
        return L("Kommt das Gehalt früher oder später, verschiebt sich der Zeitraum mit.")
    }

    private func check(_ on: Bool) -> some View {
        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Wimg.pos).opacity(on ? 1 : 0)
    }

    private func dayStepper(_ p: Periods) -> some View {
        HStack(spacing: 8) {
            Text(L("Monat beginnt am")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
            Spacer()
            stepButton("chevron.left", L("Früher"), enabled: p.day > 1) { setMode("day", day: p.day - 1) }
            Text("\(p.day).").wimgStyle(WimgType.button).foregroundStyle(Wimg.text)
                .frame(width: 44).contentTransition(.numericText(value: Double(p.day)))
            stepButton("chevron.right", L("Später"), enabled: p.day < 28) { setMode("day", day: p.day + 1) }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Wimg.text : Wimg.text3)
                .frame(width: 40, height: 40)
                .background(Wimg.neutralTint, in: Circle())
        }
        .buttonStyle(.wimgPress)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func load() async {
        periods = await Task.detached { LibWimg.getPeriods(count: 12) }.value
    }

    /// Only the periods change: screens reload through the data-changed note.
    private func setMode(_ mode: String, day: Int) {
        try? LibWimg.setPeriodMode(mode, day: day)
        Task {
            await load()
            Changes.bump()
        }
    }
}

/// "Gehalt selbst auswählen": incomes of the last months, largest first.
private struct PayerSheet: View {
    let periods: Periods
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                if periods.payers.isEmpty {
                    QuietLine(text: L("Noch keine Einnahmen in den letzten Monaten.")).padding()
                } else {
                    WimgGroup {
                        ForEach(Array(periods.payers.enumerated()), id: \.element.key) { i, p in
                            if i > 0 { RowDivider() }
                            let on = periods.salary?.key == p.key && (periods.salary?.confirmed ?? false)
                            WimgRow(title: p.title ?? p.key,
                                    desc: L("%s · %d× seit %s", amountText(p.amount ?? 0, showPlus: false), p.count ?? 0,
                                            PeriodLabels.dotted(p.last ?? "")),
                                    action: { pick(p) }) {
                                EmptyView()
                            } trailing: {
                                if on { Image(systemName: "checkmark").foregroundStyle(Wimg.accent) }
                            }
                        }
                    }
                    .padding(WimgDimens.sheetPadding)
                }
            }
            .background(Wimg.sheet)
            .navigationTitle(L("Welche Einnahme ist dein Gehalt?"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Wimg.sheet)
    }

    private func pick(_ p: Payer) {
        try? LibWimg.answerSalary(key: p.key, .onlyThisPayer)
        try? LibWimg.setPeriodMode("salary")
        Changes.bump()
        onDone()
    }
}

// MARK: - Design und Sprache

/// The language choice: "de", "en" or "system". `wimg_locale` (what the
/// i18n lookup and the widgets read, also in the App Group) always holds the
/// resolved "de" or "en"; the choice itself is kept apart.
enum LocaleChoice {
    static let choiceKey = "wimg_locale_choice"

    static var choice: String {
        UserDefaults.standard.string(forKey: choiceKey)
            ?? UserDefaults.standard.string(forKey: "wimg_locale") ?? "system"
    }

    static var systemLanguage: String {
        (Locale.preferredLanguages.first ?? "de").hasPrefix("de") ? "de" : "en"
    }

    static func set(_ c: String) {
        UserDefaults.standard.set(c, forKey: choiceKey)
        apply()
    }

    /// Writes the resolved language. Call at start too, so "Systemsprache"
    /// follows a change of the phone's language.
    static func apply() {
        let resolved = choice == "system" ? systemLanguage : choice
        if UserDefaults.standard.string(forKey: "wimg_locale") != resolved {
            UserDefaults.standard.set(resolved, forKey: "wimg_locale")
            UserDefaults(suiteName: "group.com.wimg.app")?.set(resolved, forKey: "wimg_locale")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

struct SettingsLanguageView: View {
    @State private var choice = LocaleChoice.choice
    private var themeManager = ThemeManager.shared

    static var label: String {
        switch LocaleChoice.choice {
        case "en": "English"
        case "system": L("Systemsprache")
        default: "Deutsch"
        }
    }

    var body: some View {
        BandScreen(title: L("Design und Sprache"), pushed: true) {
            EmptyView()
        } sheet: {
            WimgGroup {
                HStack(spacing: 12) {
                    Text(L("Design")).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                    Spacer(minLength: 8)
                    Picker(L("Design"), selection: Binding(get: { themeManager.mode }, set: { themeManager.mode = $0 })) {
                        Text(L("Hell")).tag(ThemeMode.light)
                        Text(L("Dunkel")).tag(ThemeMode.dark)
                        Text(L("System")).tag(ThemeMode.system)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: WimgDimens.rowMinHeight)
            }
            GroupLabel(text: L("Sprache"))
            WimgGroup {
                row("de", "Deutsch", nil)
                RowDivider()
                row("en", "English", nil)
                RowDivider()
                row("system", L("Systemsprache"), LocaleChoice.systemLanguage == "de" ? "Deutsch" : "English")
            }
            GroupLabel(text: L("Zahlen und Datum"))
            WimgGroup {
                WimgRow(title: L("Beträge")) { EmptyView() } trailing: {
                    Text(amountText(1234.56, showPlus: false)).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                }
                RowDivider()
                WimgRow(title: L("Datum")) { EmptyView() } trailing: {
                    Text(WimgDates.dayMonth(12, 11)).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                }
            }
            QuietLine(text: L("Buchungstexte der Bank bleiben in ihrer Sprache."))
        }
    }

    private func row(_ code: String, _ label: String, _ sub: String?) -> some View {
        WimgRow(title: label, desc: sub, action: {
            choice = code
            LocaleChoice.set(code)
        }) {
            EmptyView()
        } trailing: {
            if choice == code {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Wimg.accent)
            }
        }
        .accessibilityAddTraits(choice == code ? .isSelected : [])
    }
}
