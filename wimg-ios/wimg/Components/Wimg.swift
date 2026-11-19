import SwiftUI
import UIKit

// Design tokens for the wimg redesign, the same values as Android's
// `ui/theme/WimgTheme.kt`. Rules: ~/Desktop/wimg-redesign/handoff/DESIGN-SYSTEM.md.
// A colour from the design exports that isn't here gets a named token here,
// never a raw hex in a screen. iOS-specific structure: brief 22, option A.

// MARK: - Colours

/// A colour with a light and a dark value. Follows the trait collection, so the
/// app's own theme choice (`preferredColorScheme`) switches it too.
private func dyn(_ light: UInt32, _ dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
    Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(rgb: dark, alpha: darkAlpha) : UIColor(rgb: light, alpha: lightAlpha)
    })
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

enum Wimg {
    // Band (dark in both themes) and its text
    static let band = dyn(0x1D1C1A, 0x1E1E21)
    static let bandSub = dyn(0xA8A49C, 0x9A9BA0)
    static let bandNeg = dyn(0xFF9A85, 0xFF9A85)
    static let bandPos = dyn(0x86DDA6, 0x86DDA6)
    /// Glass/frosted buttons over the band (fallback fill below iOS 26).
    static let bandButton = Color.white.opacity(0.12)
    static let bandButtonLine = Color.white.opacity(0.14)

    // Sheet and surfaces
    static let sheet = dyn(0xFAF9F6, 0x111114)
    static let card = dyn(0xFFFFFF, 0x1C1C1E)
    static let text = dyn(0x1A1A1A, 0xF2F2F3)
    static let text2 = dyn(0x6B6A66, 0x9A9BA0)
    static let text3 = dyn(0xB5B2AC, 0x4A4A50)
    static let line = dyn(0xECE8E1, 0xFFFFFF, darkAlpha: 0.08)
    static let neutralTint = dyn(0xF1EDE5, 0x26262A)
    static let ink = dyn(0x1A1A1A, 0xF2F2F3)
    static let inkText = dyn(0xFFFFFF, 0x111114)

    // Accent (denim) and states
    static let accent = dyn(0x4A6D96, 0x6F93BC)
    static let onAccent = Color.white
    static let accentSoft = dyn(0xE4ECF5, 0x8FB0D3, darkAlpha: 0.16)
    static let accentLight = dyn(0x8FB0D3, 0x8FB0D3)
    static let pos = dyn(0x1B7A43, 0x6FD39A)
    static let danger = dyn(0xB3261E, 0xFF8A80)
    static let dangerBg = dyn(0xFCE8E6, 0xFF8A80, darkAlpha: 0.12)
    static let warn = dyn(0x9A5B00, 0xF5B54A)
    static let warnBg = dyn(0xFFF1D6, 0xF5B54A, darkAlpha: 0.12)
    static let sync = dyn(0xE8710A, 0xFF9A3C)
    static let syncBg = dyn(0xFDEBDC, 0xFF9A3C, darkAlpha: 0.14)
    static let trackOff = dyn(0xE3E5E9, 0x3A3B41)
    static let neuBg = dyn(0xECE6FF, 0xB9A8FF, darkAlpha: 0.18)
    static let neuFg = dyn(0x5236C9, 0xCFC2FF)
    static let catSonstigesBar = dyn(0xC9C4BB, 0x5A5A60)

    /// Category colours (light, dark) by libwimg category id. Unkategorisiert
    /// (0) and Sonstiges (255) have none: text2 for icons, their own bar colour.
    private static let categoryColors: [Int: (UInt32, UInt32)] = [
        1: (0x2E9E6A, 0x5CC992),   // Lebensmittel
        2: (0xC2410C, 0xF07F5A),   // Essen gehen
        3: (0x0E7490, 0x4FC3D9),   // Transport
        4: (0x8B5E3C, 0xC9A27E),   // Wohnen
        5: (0x8A63D2, 0xB39AF0),   // Nebenkosten
        6: (0xBE185D, 0xF078B0),   // Unterhaltung
        7: (0xD9822B, 0xF2A65E),   // Shopping
        8: (0xD14343, 0xF07272),   // Gesundheit
        9: (0x3B6FD8, 0x7FA6F5),   // Versicherung
        10: (0x1B7A43, 0x6FD39A),  // Einkommen
        11: (0x64748B, 0x94A3B8),  // Umbuchung
        12: (0x7C8B2E, 0xB5C25A),  // Bargeld
        13: (0x4F46E5, 0x8B8CF5),  // Abonnements
        14: (0x0284C7, 0x5BC0F0),  // Reisen
        15: (0xA16207, 0xD9A54A),  // Bildung
    ]

    /// Foreground colour of a category (icons, dots).
    static func category(_ id: Int) -> Color {
        categoryColors[id].map { dyn($0.0, $0.1) } ?? text2
    }

    /// Bar / segment colour of a category.
    static func categoryBar(_ id: Int) -> Color {
        categoryColors[id].map { dyn($0.0, $0.1) } ?? catSonstigesBar
    }
}

extension WimgCategory {
    /// Redesign colour (the old `color` stays for screens not yet redesigned).
    var tint: Color { Wimg.category(rawValue) }
    var bar: Color { Wimg.categoryBar(rawValue) }
}

// MARK: - Type

/// Bundled fonts (wimg/Fonts, listed in Info.plist `UIAppFonts`). The static
/// files were renamed per weight by scripts/ios-fonts.py: the originals all
/// carried the same PostScript name, so iOS would have loaded only one weight.
enum WimgFont {
    enum Family { case manrope, inter, mono }

    static func name(_ family: Family, _ weight: Font.Weight) -> String {
        switch family {
        case .manrope:
            switch weight {
            case .heavy, .black: "Manrope-ExtraBold"
            case .bold: "Manrope-Bold"
            case .semibold: "Manrope-SemiBold"
            default: "Manrope-Medium"
            }
        case .inter:
            switch weight {
            case .bold, .heavy, .black: "Inter-Bold"
            case .semibold: "Inter-SemiBold"
            case .medium: "Inter-Medium"
            default: "Inter-Regular"
            }
        case .mono:
            weight == .regular ? "JetBrainsMono-Regular" : "JetBrainsMono-Medium"
        }
    }

    /// A custom font that grows with Dynamic Type, scaled relative to `style`.
    static func font(_ family: Family, _ weight: Font.Weight, _ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(name(family, weight), size: size, relativeTo: style)
    }
}

/// One text style of the design system: font, line height and tracking.
struct WimgTextStyle {
    let family: WimgFont.Family
    let weight: Font.Weight
    let size: CGFloat
    let lineHeight: CGFloat
    var tracking: CGFloat = 0
    var relativeTo: Font.TextStyle = .body
    /// Tabular figures, only where amounts stack in a column.
    var tabular = false

    var font: Font {
        let f = WimgFont.font(family, weight, size, relativeTo: relativeTo)
        return tabular ? f.monospacedDigit() : f
    }

    func size(_ s: CGFloat, tracking t: CGFloat? = nil) -> WimgTextStyle {
        WimgTextStyle(family: family, weight: weight, size: s, lineHeight: lineHeight * s / size,
                      tracking: t ?? tracking, relativeTo: relativeTo, tabular: tabular)
    }
}

enum WimgType {
    static let amountHero = WimgTextStyle(family: .manrope, weight: .heavy, size: 38, lineHeight: 46, tracking: -1, relativeTo: .largeTitle)
    static let amountHeroCents = amountHero.size(21, tracking: -0.3)
    static let amountLarge = WimgTextStyle(family: .manrope, weight: .heavy, size: 24, lineHeight: 30, tracking: -0.4, relativeTo: .title)
    static let amountStat = WimgTextStyle(family: .manrope, weight: .bold, size: 15, lineHeight: 20, tracking: -0.2, relativeTo: .subheadline)
    static let title = WimgTextStyle(family: .manrope, weight: .heavy, size: 24, lineHeight: 30, tracking: -0.4, relativeTo: .title)
    static let largeTitle = WimgTextStyle(family: .manrope, weight: .heavy, size: 34, lineHeight: 40, tracking: -0.6, relativeTo: .largeTitle)
    static let sheetTitle = WimgTextStyle(family: .manrope, weight: .heavy, size: 21, lineHeight: 28, relativeTo: .title2)
    static let section = WimgTextStyle(family: .manrope, weight: .heavy, size: 18, lineHeight: 24, relativeTo: .headline)
    static let rowTitle = WimgTextStyle(family: .inter, weight: .semibold, size: 15, lineHeight: 21, relativeTo: .body)
    static let amountRow = WimgTextStyle(family: .manrope, weight: .bold, size: 16, lineHeight: 22, relativeTo: .body, tabular: true)
    static let amountRowCents = amountRow.size(11)
    static let button = WimgTextStyle(family: .manrope, weight: .bold, size: 15, lineHeight: 20, relativeTo: .body)
    static let chip = WimgTextStyle(family: .manrope, weight: .bold, size: 14, lineHeight: 18, relativeTo: .subheadline)
    static let body = WimgTextStyle(family: .inter, weight: .regular, size: 15, lineHeight: 22, relativeTo: .body)
    static let desc = WimgTextStyle(family: .inter, weight: .regular, size: 13, lineHeight: 18, relativeTo: .footnote)
    static let label = WimgTextStyle(family: .inter, weight: .bold, size: 13, lineHeight: 18, relativeTo: .footnote)
    static let caption = WimgTextStyle(family: .inter, weight: .medium, size: 12, lineHeight: 16, relativeTo: .caption)
    static let bandOver = WimgTextStyle(family: .inter, weight: .medium, size: 13, lineHeight: 18, relativeTo: .footnote)
    static let mono = WimgTextStyle(family: .mono, weight: .medium, size: 13, lineHeight: 19, relativeTo: .footnote)
}

extension View {
    /// Applies a design-system text style: font, tracking and line height.
    func wimgStyle(_ s: WimgTextStyle) -> some View {
        font(s.font)
            .tracking(s.tracking)
            .lineSpacing(max(0, s.lineHeight - s.size * 1.2))
    }
}

// MARK: - Shapes, sizes, motion

enum WimgShape {
    static let sheetTop: CGFloat = 20
    static let group: CGFloat = 16
    static let button: CGFloat = 13
    static let dockAction: CGFloat = 12
    static let iconTile: CGFloat = 12
    static let toggleTrack: CGFloat = 8
    static let toggleKnob: CGFloat = 6
    static let segmentOuter: CGFloat = 10
    static let segmentInner: CGFloat = 8
    static let badge: CGFloat = 6
}

enum WimgDimens {
    static let sheetPadding: CGFloat = 16
    static let rowMinHeight: CGFloat = 56
    static let rowInsetDivider: CGFloat = 16
    static let touchTarget: CGFloat = 44
    static let toggleWidth: CGFloat = 48
    static let toggleHeight: CGFloat = 26
    static let toggleKnob: CGFloat = 20
    static let dockSeam: CGFloat = 3
    /// Round band buttons (period ring, filter, +), as on board 02.
    static let bandButton: CGFloat = 44
}

enum WimgMotion {
    static let pressScale: CGFloat = 0.97
    static let undoCountdown: Double = 6
    static let undock: Double = 0.18

    /// Enter, exit, docking.
    static func out(_ seconds: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: seconds) }
    /// Shape changes on screen.
    static func inOut(_ seconds: Double) -> Animation { .timingCurve(0.77, 0, 0.175, 1, duration: seconds) }
    static let press = out(0.12)
    /// Height change when a row docks: Δh / 500 pt per s, clamped to 150–270 ms.
    static func dock(deltaHeight: CGFloat) -> Animation { out(min(max(Double(deltaHeight) / 500, 0.15), 0.27)) }
}
