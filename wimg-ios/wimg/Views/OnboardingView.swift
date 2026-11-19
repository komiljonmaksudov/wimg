import SwiftUI
import WimgI18n

/// First start (as Android's OnboardingScreen): welcome on the dark band, then
/// where the transactions come from. "Bank verbinden" and "Datei importieren"
/// open their page right here; "Leer starten" goes to the app.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Page] = []
    @State private var showLinkSheet = false
    /// The phone's own scheme: the welcome is forced dark, the button's denim isn't.
    @Environment(\.colorScheme) private var scheme

    enum Page: Hashable { case source, bank, file }

    var body: some View {
        NavigationStack(path: $path) {
            welcome
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .source: SourceChoiceView(onPick: pick)
                    case .bank: FinTSView().toolbar { doneButton }
                    case .file: ImportView().toolbar { doneButton }
                    }
                }
        }
        .tint(Wimg.accent)
        .sheet(isPresented: $showLinkSheet) {
            SyncLinkSheet(onLinked: {
                showLinkSheet = false
                complete()
            })
        }
    }

    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) { Button(L("Fertig")) { complete() }.bold() }
    }

    private var welcome: some View {
        ZStack(alignment: .bottom) {
            Wimg.band.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image("AppMark")
                        .resizable()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                        .accessibilityHidden(true)
                    Text(L("Deine Finanzen.") + "\n" + L("Auf deinem Gerät."))
                        .font(WimgFont.font(.manrope, .heavy, 34, relativeTo: .largeTitle))
                        .tracking(-0.6)
                        .foregroundStyle(.white)
                        .padding(.top, 36)
                        .accessibilityAddTraits(.isHeader)
                    Text(L("Sieh, wohin dein Geld geht. Ohne Konto, ohne Cloud-Zwang."))
                        .font(WimgFont.font(.inter, .regular, 16))
                        .foregroundStyle(Wimg.bandSub)
                        .padding(.top, 14)
                    VStack(alignment: .leading, spacing: 22) {
                        feature("lock", L("Bleibt auf deinem Gerät"), L("Kein Konto nötig. Deine Daten gehören dir."))
                        feature("building.columns", L("Direkt von deiner Bank"), L("Umsätze per FinTS abrufen, ohne Dienst dazwischen. Oder einen Kontoauszug oder eine CSV-Datei importieren."))
                        feature("arrow.triangle.2.circlepath", L("Sync zwischen deinen Geräten"), L("Ende-zu-Ende-verschlüsselt, mit einem Schlüssel statt Passwort."))
                    }
                    .padding(.top, 36)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 140)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                OnboardingButton(title: L("Ich nutze wimg schon"), primary: false, dark: true) { showLinkSheet = true }
                OnboardingButton(title: L("Los geht’s"), primary: true, dark: true) { path.append(.source) }
                    .environment(\.colorScheme, scheme)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .environment(\.colorScheme, .dark)
    }

    private func feature(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: WimgShape.iconTile, style: .continuous)
                .fill(.white.opacity(0.07))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(Wimg.accentLight))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(WimgFont.font(.inter, .bold, 16)).foregroundStyle(.white)
                Text(desc).wimgStyle(WimgType.body).foregroundStyle(Wimg.bandSub)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pick(_ page: Page?) {
        guard let page else { complete(); return }
        path.append(page)
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "wimg_onboarding_completed")
        dismiss()
    }
}

/// Step 1 of 3: Bank verbinden (recommended), Datei importieren, Leer starten.
private struct SourceChoiceView: View {
    let onPick: (OnboardingView.Page?) -> Void
    @State private var selected = 0

    private let choices: [(page: OnboardingView.Page?, title: String, desc: String, recommended: Bool)] = [
        (.bank, "Bank verbinden", "Umsätze direkt von der Bank holen, ca. 1.700 deutsche Banken. Mit TAN.", true),
        (.file, "Datei importieren", "Kontoauszug von jeder Bank oder CSV von Comdirect, Trade Republic, Scalable oder Revolut.", false),
        (nil, "Leer starten", "Erstmal umsehen. Daten kannst du später hinzufügen.", false),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            BandScreen(title: L("Einrichten"), pushed: true) {
                OnboardingStepBand(over: L("Einrichten"), step: 1, of: 3, title: L("Woher kommen deine Umsätze?"))
            } sheet: {
                VStack(spacing: 12) {
                    ForEach(choices.indices, id: \.self) { i in choiceCard(i) }
                    Text(L("Du kannst später jederzeit eine Bank verbinden oder weitere Dateien importieren, unter Mehr."))
                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.bottom, 90)
            }
            OnboardingButton(title: L("Weiter"), primary: true, dark: false) { onPick(choices[selected].page) }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    private func choiceCard(_ i: Int) -> some View {
        let on = selected == i
        let c = choices[i]
        return Button { selected = i } label: {
            HStack(alignment: .top, spacing: 16) {
                Circle().stroke(on ? Wimg.ink : Wimg.text3, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .overlay { if on { Circle().fill(Wimg.ink).frame(width: 12, height: 12) } }
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(L(c.title)).font(WimgFont.font(.inter, .bold, 16.5)).foregroundStyle(Wimg.text)
                        if c.recommended {
                            Text(L("empfohlen")).wimgStyle(WimgType.caption).foregroundStyle(Wimg.text2)
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .background(Wimg.neutralTint, in: Capsule())
                        }
                    }
                    Text(L(c.desc)).wimgStyle(WimgType.body).foregroundStyle(Wimg.text2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous)
                .stroke(on ? Wimg.ink : Wimg.line, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.wimgPress)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Band for multi-step flows: "Flow · Schritt n von m", a segmented line, the title.
struct OnboardingStepBand: View {
    let over: String
    let step: Int
    let of: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("%s · Schritt %d von %d", over, step, of)).wimgStyle(WimgType.bandOver).foregroundStyle(Wimg.bandSub)
            HStack(spacing: 6) {
                ForEach(1...of, id: \.self) { i in
                    Capsule().fill(i <= step ? .white : .white.opacity(0.18)).frame(height: 4)
                }
            }
            .padding(.top, 10).padding(.bottom, 14)
            .accessibilityHidden(true)
            Text(title).font(WimgFont.font(.manrope, .heavy, 27.6, relativeTo: .title)).tracking(-0.4).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Full-width button pair at the bottom, before the app's tab bar exists.
struct OnboardingButton: View {
    let title: String
    let primary: Bool
    let dark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .wimgStyle(WimgType.button)
                .foregroundStyle(primary ? Wimg.onAccent : (dark ? .white : Wimg.text))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(primary ? Wimg.accent : (dark ? .white.opacity(0.08) : Wimg.card),
                            in: RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: WimgShape.button, style: .continuous)
                    .stroke(primary ? .clear : (dark ? .white.opacity(0.12) : Wimg.line), lineWidth: 1))
        }
        .buttonStyle(.wimgPress)
    }
}
