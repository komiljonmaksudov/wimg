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

// MARK: - Friendly Finance Design System

enum WimgTheme {
    // Colors — adaptive for light/dark
    static let accent = Color(red: 1.0, green: 0.914, blue: 0.49)        // #FFE97D
    /// Always-dark text for use on accent/hero cards (yellow bg needs dark text in both themes)
    static let heroText = Color(red: 0.102, green: 0.102, blue: 0.102)   // #1A1A1A

    static var bg: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.067, green: 0.067, blue: 0.078, alpha: 1) // #111114
                : UIColor(red: 0.98, green: 0.976, blue: 0.965, alpha: 1) // #FAF9F6
        })
    }

    static var text: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1) // #1A1A1A
        })
    }

    static var textSecondary: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.6, green: 0.6, blue: 0.62, alpha: 1)
                : UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1) // #8E8E93
        })
    }

    static var border: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1, green: 1, blue: 1, alpha: 0.05)
                : UIColor(red: 0.941, green: 0.925, blue: 0.902, alpha: 1) // #f0ece6
        })
    }

    static var cardBg: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1) // #1c1c1e
                : UIColor.white
        })
    }

    // Corner Radii
    static let radiusSmall: CGFloat = 20
    static let radiusMedium: CGFloat = 24
    static let radiusLarge: CGFloat = 28
    static let radiusXL: CGFloat = 32
}

// MARK: - Card Style Modifier

struct WimgCardStyle: ViewModifier {
    var radius: CGFloat = WimgTheme.radiusMedium

    func body(content: Content) -> some View {
        content
            .background(WimgTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

struct WimgHeroStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WimgTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusXL, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
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
