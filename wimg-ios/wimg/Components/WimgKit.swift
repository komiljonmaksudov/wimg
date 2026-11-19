import SwiftUI
import WimgI18n

// Building blocks of the redesign, the iOS twins of Android's
// `ui/components/WimgKit.kt`. Same look (band, sheet, groups, rows, amounts),
// iOS structure (navigation bar, sheets, tab bar): brief 22, option A.

// MARK: - Amounts: 1.234,56 €, minus is U+2212, income gets a +, cents smaller

let wimgMinus = "\u{2212}"

/// Splits an amount in euros into ("−1.234", ",56 €").
func amountParts(_ euros: Double, showPlus: Bool = true) -> (whole: String, cents: String) {
    let cents = Int64((abs(euros) * 100).rounded())
    let f = NumberFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    let whole = f.string(from: NSNumber(value: cents / 100)) ?? "\(cents / 100)"
    let sign = cents == 0 ? "" : euros < 0 ? wimgMinus : showPlus ? "+" : ""
    // No-break space before €: an amount never splits across lines.
    return (sign + whole, String(format: ",%02d\u{00A0}€", cents % 100))
}

/// Plain-text amount for titles and accessibility.
func amountText(_ euros: Double, showPlus: Bool = true) -> String {
    let p = amountParts(euros, showPlus: showPlus)
    return p.whole + p.cents
}

/// An amount with smaller cents. With `rolls`, changed digits roll to the new
/// value (up when it grows, down when it shrinks): the system's numeric text
/// transition, which also respects Reduce Motion.
struct Amount: View {
    let euros: Double
    var style: WimgTextStyle = WimgType.amountRow
    var centsStyle: WimgTextStyle = WimgType.amountRowCents
    var color: Color = Wimg.text
    var showPlus: Bool = true
    var rolls: Bool = false

    var body: some View {
        let p = amountParts(euros, showPlus: showPlus)
        (Text(p.whole).font(style.font).tracking(style.tracking)
            + Text(p.cents).font(centsStyle.font).tracking(centsStyle.tracking))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText(value: euros))
            .animation(rolls ? WimgMotion.inOut(0.26) : nil, value: euros)
            .accessibilityLabel(p.whole + p.cents)
    }
}

// MARK: - Press feedback: scale 0.97 while pressed, 120 ms ease-out

struct WimgPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? WimgMotion.pressScale : 1)
            .animation(WimgMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == WimgPressStyle {
    static var wimgPress: WimgPressStyle { WimgPressStyle() }
}

// MARK: - Band + sheet: the one number that matters on dark, the list on light

/// A tab's root page: dark band at the top with the title and the page's round
/// buttons (period, filter, +), then the light sheet with 20 pt top corners.
/// The buttons live in the band, not in the navigation bar, so iOS 26 doesn't
/// wrap them in its own glass: they look the same on every iOS version.
struct BandScreen<Controls: View, Band: View, Sheet: View>: View {
    let title: String
    /// "Mehr" style: big title on its own line (board 05) instead of the
    /// small title next to the buttons (board 02).
    var largeTitle = false
    /// A pushed page (detail): the system bar stays, in band colour, with its
    /// back button and swipe-back; the title sits in the bar.
    var pushed = false
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let band: () -> Band
    @ViewBuilder let sheet: () -> Sheet

    private var hasControls: Bool { Controls.self != EmptyView.self }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if pushed {
                        // Pushed page: the title is in the bar, the buttons sit
                        // beside the band content instead of on a row of their own.
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) { band() }
                            Spacer(minLength: 0)
                            controls()
                        }
                        .padding(.top, 8)
                    } else {
                    if (!largeTitle && !pushed) || hasControls {
                        HStack(spacing: 10) {
                            if !largeTitle && !pushed {
                                Text(title).wimgStyle(WimgType.section).foregroundStyle(.white)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            Spacer(minLength: 0)
                            controls()
                        }
                        .frame(minHeight: WimgDimens.bandButton)
                    }
                    if largeTitle {
                        Text(title).wimgStyle(WimgType.largeTitle).foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                    }
                    band()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 22)
                .environment(\.colorScheme, .dark)
                // Lazy: Umsätze puts thousands of rows in here.
                LazyVStack(alignment: .leading, spacing: 0) { sheet() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, WimgDimens.sheetPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, minHeight: 400, alignment: .top)
                    .background(Wimg.sheet,
                                in: UnevenRoundedRectangle(topLeadingRadius: WimgShape.sheetTop,
                                                           topTrailingRadius: WimgShape.sheetTop, style: .continuous))
            }
        }
        // Band above, sheet below: overscroll at either end shows the right colour.
        .background(VStack(spacing: 0) { Wimg.band; Wimg.sheet }.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(pushed ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(Wimg.band, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Back arrow without the previous page's name: long titles need the room.
        .toolbarRole(.editor)
    }
}

extension BandScreen where Controls == EmptyView {
    init(title: String, largeTitle: Bool = false, pushed: Bool = false,
         @ViewBuilder band: @escaping () -> Band, @ViewBuilder sheet: @escaping () -> Sheet) {
        self.init(title: title, largeTitle: largeTitle, pushed: pushed, controls: { EmptyView() }, band: band, sheet: sheet)
    }
}

/// "Over" line (13, bandSub) + optional title, for list pages.
struct BandOver: View {
    let text: String
    var body: some View {
        Text(text).wimgStyle(WimgType.bandOver).foregroundStyle(Wimg.bandSub)
    }
}

/// A round control over the band (filter, +), with an optional count badge
/// (active filters).
struct BandButton: View {
    let systemImage: String
    let label: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) { BandIcon(systemImage: systemImage, badge: badge) }
            .buttonStyle(.wimgPress)
            .accessibilityLabel(badge > 0 ? "\(label), \(badge)" : label)
    }
}

/// The look of a band button, also usable as a `Menu` label.
struct BandIcon: View {
    let systemImage: String
    var badge: Int = 0

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: WimgDimens.bandButton, height: WimgDimens.bandButton)
            .bandButtonBackground(Circle())
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(WimgType.caption.font.bold())
                        .foregroundStyle(Wimg.band)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Wimg.accentLight, in: Circle())
                        .offset(x: 3, y: -3)
                }
            }
    }
}

/// The period control over the band: progress ring + short period ("Nov.").
struct BandPeriodButton: View {
    let fraction: Double
    let text: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                PeriodRing(fraction: fraction, color: Wimg.accentLight, track: .white.opacity(0.25))
                    .frame(width: 20, height: 20)
                Text(text).wimgStyle(WimgType.chip).foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .frame(height: WimgDimens.bandButton)
            .bandButtonBackground(Capsule())
        }
        .buttonStyle(.wimgPress)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Frosted fill for a control over the band. No hand-made glass: built with
    /// the iOS 26 SDK, the system's own controls get it by themselves.
    func bandButtonBackground<S: Shape>(_ shape: S) -> some View {
        background(Wimg.bandButton, in: shape)
            .overlay(shape.stroke(Wimg.bandButtonLine, lineWidth: 1))
    }
}

/// How far the period has run (0…1) as a ring.
struct PeriodRing: View {
    let fraction: Double
    let color: Color
    let track: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Section heading in the sheet ("Ausgaben nach Kategorie") with an optional
/// quiet link on the right ("Wiederkehrend").
struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    var onTrailing: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).wimgStyle(WimgType.section).foregroundStyle(Wimg.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if let trailing {
                if let onTrailing {
                    Button(trailing, action: onTrailing).buttonStyle(.plain)
                        .wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                } else {
                    Text(trailing).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

// MARK: - Groups and rows: lists, not cards

struct GroupLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text)
            Spacer()
            if let trailing { Text(trailing) }
        }
        .wimgStyle(WimgType.label)
        .foregroundStyle(Wimg.text2)
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// White group with a hairline border; rows inside are separated by `RowDivider`.
struct WimgGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity)
            .background(Wimg.card, in: RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous).stroke(Wimg.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: WimgShape.group, style: .continuous))
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Wimg.line).frame(height: 1).padding(.leading, WimgDimens.rowInsetDivider)
    }
}

/// 36 pt tile with 12 pt corners: an SF Symbol in a colour at 10–13 %.
struct IconTile: View {
    let systemImage: String
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: WimgShape.iconTile, style: .continuous)
            .fill(tint.opacity(scheme == .dark ? 0.13 : 0.10))
            .frame(width: 36, height: 36)
            .overlay(Image(systemName: systemImage).font(.system(size: 16, weight: .medium)).foregroundStyle(tint))
            .accessibilityHidden(true)
    }
}

/// A category dot in a neutral tile, as in transaction rows (board 03).
struct CategoryTile: View {
    let category: Int

    var body: some View {
        RoundedRectangle(cornerRadius: WimgShape.iconTile, style: .continuous)
            .fill(Wimg.neutralTint)
            .frame(width: 36, height: 36)
            .overlay(Circle().fill(Wimg.category(category)).frame(width: 10, height: 10))
            .accessibilityHidden(true)
    }
}

/// One row: optional leading tile, title + description, optional trailing
/// content and chevron. With `action` the whole row is one button.
struct WimgRow<Leading: View, Trailing: View>: View {
    let title: String
    var desc: String? = nil
    var chevron: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        if let action {
            Button(action: action) { content }.buttonStyle(RowPressStyle())
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 1) {
                Text(title).wimgStyle(WimgType.rowTitle).foregroundStyle(Wimg.text).lineLimit(1)
                if let desc {
                    Text(desc).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Wimg.text3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: desc != nil ? 60 : WimgDimens.rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension WimgRow where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, desc: String? = nil, chevron: Bool = false, action: (() -> Void)? = nil) {
        self.init(title: title, desc: desc, chevron: chevron, action: action, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension WimgRow where Trailing == EmptyView {
    init(title: String, desc: String? = nil, chevron: Bool = false, action: (() -> Void)? = nil,
         @ViewBuilder leading: @escaping () -> Leading) {
        self.init(title: title, desc: desc, chevron: chevron, action: action, leading: leading, trailing: { EmptyView() })
    }
}

/// Rows highlight instead of shrinking: a list row scaling looks loose.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Wimg.neutralTint : .clear)
    }
}

// MARK: - Toggle: soft rectangle, accent when on

struct WimgToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: WimgShape.toggleTrack, style: .continuous)
                .fill(configuration.isOn ? Wimg.accent : Wimg.trackOff)
                .frame(width: WimgDimens.toggleWidth, height: WimgDimens.toggleHeight)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: WimgShape.toggleKnob, style: .continuous)
                        .fill(.white)
                        .frame(width: WimgDimens.toggleKnob, height: WimgDimens.toggleKnob)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                        .padding(3)
                }
                .animation(WimgMotion.inOut(0.18), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        // The system reads this as a switch with its on/off value.
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == WimgToggleStyle {
    static var wimg: WimgToggleStyle { WimgToggleStyle() }
}

// MARK: - Quiet line: icon + one sentence in text2 instead of a dialog

struct QuietLine: View {
    let text: String
    var systemImage = "info.circle"
    var color: Color = Wimg.text2

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 14))
            Text(text).wimgStyle(WimgType.desc)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }
}
