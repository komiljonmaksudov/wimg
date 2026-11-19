import SwiftUI
import UserNotifications
import WimgI18n

/// Einstellungen › Mitteilungen (Android board 20/02): which notices wimg
/// sends, and a quiet time. Only the kinds iOS sends are listed (no salary
/// notice on iOS yet).
struct NotificationSettingsView: View {
    @State private var version = 0
    @State private var status: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL

    private static let quietChoices: [(from: Int, to: Int)?] = [nil, (22, 8), (23, 7), (21, 7)]

    var body: some View {
        BandScreen(title: L("Mitteilungen"), pushed: true) {
            Text(L("Was wimg dir meldet, und wann nicht")).wimgStyle(WimgType.desc).foregroundStyle(Wimg.bandSub)
        } sheet: {
            WimgGroup {
                toggle(.monthEnd, L("Monatsabschluss"), L("Am 1. des Monats, mit deinem Rückblick"))
                RowDivider()
                toggle(.newTx, L("Neue Umsätze"), L("Nach dem Hintergrund-Abruf, gesammelt"))
                RowDivider()
                toggle(.tan, L("TAN nötig"), L("Wenn die Bank eine TAN will · höchstens 1× am Tag"))
                RowDivider()
                toggle(.price, L("Preis gestiegen"), L("Wenn eine feste Zahlung teurer wird"))
            }
            GroupLabel(text: L("Ruhezeit"))
            WimgGroup {
                ForEach(Array(Self.quietChoices.enumerated()), id: \.offset) { i, choice in
                    if i > 0 { RowDivider() }
                    let on = Notifier.quietHours.map { q in choice.map { $0 == q } ?? false } ?? (choice == nil)
                    WimgRow(title: choice.map { "\($0.from):00 – \($0.to):00" } ?? L("Aus"),
                            desc: i == 0 ? L("Keine Mitteilungen in dieser Zeit") : nil,
                            action: { Notifier.quietHours = choice; version += 1 }) {
                        EmptyView()
                    } trailing: {
                        if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Wimg.accent) }
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .id(version)
            switch status {
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    QuietLine(text: L("Mitteilungen sind für wimg in den iOS-Einstellungen aus. Tippe, um sie einzuschalten."),
                              systemImage: "bell.slash", color: Wimg.warn)
                }
                .buttonStyle(.plain)
            case .notDetermined:
                Button {
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                        await refreshStatus()
                        await Notifier.scheduleMonthEnd()
                    }
                } label: {
                    QuietLine(text: L("wimg darf dir noch keine Mitteilungen schicken. Tippe, um es zu erlauben."),
                              systemImage: "bell", color: Wimg.accent)
                }
                .buttonStyle(.plain)
            default:
                EmptyView()
            }
            QuietLine(text: L("Mitteilungen zeigen keine Beträge, wenn „Beträge in Widgets ausblenden“ an ist."))
        }
        .task { await refreshStatus() }
    }

    private func toggle(_ kind: Notifier.Kind, _ title: String, _ desc: String) -> some View {
        Toggle(isOn: Binding(get: { _ = version; return Notifier.isOn(kind) }, set: { Notifier.set(kind, $0); version += 1 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text)
                Text(desc).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
            }
        }
        .toggleStyle(.wimg)
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
    }

    private func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
