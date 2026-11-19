import SwiftUI
import WimgI18n

/// Full-screen gate while the app is locked (Android board 13): the dark band,
/// the app icon, one line on what's hidden, Face ID / Touch ID as the round
/// button, and Entsperren at the bottom where the bar always is.
struct LockScreen: View {
    @ObservedObject var lock: BiometricLock
    /// The phone's own scheme: the screen is forced dark, the button's denim isn't.
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Wimg.band.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer().frame(height: 120)
                Image("AppMark")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .accessibilityHidden(true)
                Text(L("wimg ist gesperrt"))
                    .wimgStyle(WimgType.title).foregroundStyle(.white)
                    .padding(.top, 28)
                    .accessibilityAddTraits(.isHeader)
                Text(L("Beträge sind ausgeblendet, bis du entsperrst."))
                    .wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                Spacer()
                Button(action: unlock) {
                    Image(systemName: iconName)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(.white.opacity(0.05), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.wimgPress)
                .accessibilityLabel(L("Entsperren"))
                Text(methodName).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub).padding(.top, 14)
                Spacer()
                OnboardingButton(title: L("Entsperren"), primary: true, dark: true, action: unlock)
                    .environment(\.colorScheme, scheme)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            // Ask once on appear, as banking apps do.
            await lock.authenticate()
        }
    }

    private func unlock() { Task { await lock.authenticate() } }

    private var iconName: String {
        switch lock.availableMethod {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .passcode, .none: "lock"
        }
    }

    private var methodName: String {
        switch lock.availableMethod {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .passcode, .none: L("Gerätecode")
        }
    }
}

/// Shown while the app is inactive (app switcher), so the system snapshot never
/// contains amounts.
struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            Wimg.band.ignoresSafeArea()
            Image("AppMark")
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}
