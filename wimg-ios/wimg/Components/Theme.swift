import SwiftUI

// MARK: - Theme Mode

enum ThemeMode: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@Observable
class ThemeManager {
    static let shared = ThemeManager()
    private let key = "wimg_theme_mode"

    var mode: ThemeMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: key) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: key) ?? "system"
        mode = ThemeMode(rawValue: stored) ?? .system
    }

}

// MARK: - Old theme names, now on the redesign tokens
//
// Screens not yet rebuilt (FinTS, Import, Settings, About, …) still use these
// names. They point at the wimg tokens in Wimg.swift, so every old screen gets
// the new colours at once: denim instead of yellow, hairlines instead of shadows.

enum WimgTheme {
    static var accent: Color { Wimg.accent }
    /// Text on accent and hero fills (denim and the dark band): white.
    static let heroText = Color.white

    static var bg: Color { Wimg.sheet }
    static var text: Color { Wimg.text }
    static var textSecondary: Color { Wimg.text2 }
    static var border: Color { Wimg.line }
    static var cardBg: Color { Wimg.card }

    // Corner radii, closer to the redesign's groups (16) and sheets (20).
    static let radiusSmall: CGFloat = 13
    static let radiusMedium: CGFloat = 16
    static let radiusLarge: CGFloat = 20
    static let radiusXL: CGFloat = 24
}

// MARK: - Card style: white group with a hairline, no shadow

struct WimgCardStyle: ViewModifier {
    var radius: CGFloat = WimgTheme.radiusMedium

    func body(content: Content) -> some View {
        content
            .background(Wimg.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Wimg.line, lineWidth: 1))
    }
}

/// The old yellow hero card is the dark band colour now.
struct WimgHeroStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Wimg.band)
            .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusXL, style: .continuous))
    }
}

extension View {
    func wimgCard(radius: CGFloat = WimgTheme.radiusMedium) -> some View {
        modifier(WimgCardStyle(radius: radius))
    }

    func wimgHero() -> some View {
        modifier(WimgHeroStyle())
    }
}
