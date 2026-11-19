import SwiftUI
import WidgetKit
import WimgI18n

// Views of the three widgets (boards 18–24, 26). Light: Monat on the dark band,
// Fixkosten/Heute on paper; dark: all on the band. Tinted and clear (accented
// rendering): no fills, the system tints; the main amount is accentable.
// Hidden amounts show "•••• €", counts stay.

// MARK: - Formatting

private enum WMoney {
    static let mask = "••••\u{00A0}€"

    /// ("+927", ",60 €"); minus is U+2212, income gets a +.
    static func parts(_ euros: Double, plus: Bool = true) -> (String, String) {
        let cents = Int64((abs(euros) * 100).rounded())
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        let whole = f.string(from: NSNumber(value: cents / 100)) ?? "\(cents / 100)"
        let sign = cents == 0 ? "" : euros < 0 ? "\u{2212}" : plus ? "+" : ""
        return (sign + whole, String(format: ",%02d\u{00A0}€", cents % 100))
    }

    static func text(_ euros: Double, plus: Bool = true, masked: Bool) -> String {
        if masked { return mask }
        let p = parts(euros, plus: plus)
        return p.0 + p.1
    }

    /// "927 €" without cents (lock screen).
    static func whole(_ euros: Double, plus: Bool = true, masked: Bool) -> String {
        if masked { return mask }
        return parts((euros).rounded(.towardZero), plus: plus).0 + "\u{00A0}€"
    }
}

private enum WDates {
    private static var en: Bool {
        (UserDefaults(suiteName: "group.com.wimg.app")?.string(forKey: "wimg_locale")
            ?? UserDefaults.standard.string(forKey: "wimg_locale")) == "en"
    }

    private static func parts(_ iso: String) -> [Int] { iso.split(separator: "-").compactMap { Int($0) } }

    /// "1. Dez." (German), "1 Dec" (English).
    static func short(_ iso: String) -> String {
        let p = parts(iso)
        guard p.count == 3 else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: en ? "en_US" : "de_DE")
        let m = f.shortStandaloneMonthSymbols[p[1] - 1].trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return en ? "\(p[2])\u{00A0}\(m)" : "\(p[2]).\u{00A0}\(m)."
    }

    /// "27.11." (German), "27 Nov" (English).
    static func dotted(_ iso: String) -> String {
        let p = parts(iso)
        guard p.count == 3 else { return iso }
        return en ? short(iso) : String(format: "%d.%d.", p[2], p[1])
    }

    static func monthName(_ month: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: en ? "en_US" : "de_DE")
        return month >= 1 && month <= 12 ? f.standaloneMonthSymbols[month - 1] : ""
    }
}

private extension WidgetPayload {
    /// "Bis zum Gehalt", "Bis zum 15." or the month.
    var headline: String {
        switch mode {
        case "salary": L("Bis zum Gehalt")
        case "day": L("Bis zum %d.", startDay)
        default: WDates.monthName(month)
        }
    }

    var daysText: String { daysLeft == 1 ? L("noch 1 Tag") : L("noch %d Tage", daysLeft) }

    var isCalendar: Bool { mode == "calendar" }

    /// The late-salary note replaces the days (board 26/06).
    var overdueText: String? { overdueDay > 0 ? L("Gehalt erwartet am %d., noch nicht da", overdueDay) : nil }
}

// MARK: - Colours and pieces

/// Paper in light, the band in dark (boards 18, 19).
private let paper = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x1E1E21) : UIColor(rgb: 0xFAF9F6) })

private struct FullColor: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
    let color: Color
    func body(content: Content) -> some View {
        content.foregroundStyle(mode == .fullColor ? color : .primary)
    }
}

private extension View {
    func ink(_ c: Color) -> some View { modifier(FullColor(color: c)) }
}

/// The wimg pocket on a denim tile, top right on the Monat widgets.
private struct PocketBadge: View {
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(mode == .fullColor ? Wimg.accent : Color.white.opacity(0.25))
            .frame(width: 24, height: 24)
            .overlay(PocketShape().stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)).frame(width: 13, height: 13))
            .accessibilityHidden(true)
    }
}

private struct PocketShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX, y: r.minY + 0.1 * h))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 0.1 * h))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 0.62 * h))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + 0.62 * h))
        p.closeSubpath()
        p.move(to: CGPoint(x: r.minX, y: r.minY + 0.36 * h))
        p.addLine(to: CGPoint(x: r.minX + w, y: r.minY + 0.36 * h))
        return p
    }
}

/// Big amount with smaller cents.
private struct BigAmount: View {
    let euros: Double
    let size: CGFloat
    var plus = true
    let masked: Bool
    var color: Color = .white

    var body: some View {
        Group {
            if masked {
                Text(WMoney.mask).font(WimgFont.font(.manrope, .heavy, size))
            } else {
                let p = WMoney.parts(euros, plus: plus)
                Text(p.0).font(WimgFont.font(.manrope, .heavy, size)).tracking(-size / 38)
                    + Text(p.1).font(WimgFont.font(.manrope, .heavy, size * 0.56))
            }
        }
        .ink(color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .widgetAccentable()
    }
}

/// Remaining money (grey) followed by the categories' spending, as on the boards.
private struct SpendBar: View {
    let data: WidgetPayload
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        GeometryReader { g in
            let cats = Array(data.categories.prefix(5))
            let rest = max(0, data.available)
            let total = max(rest + cats.reduce(0) { $0 + $1.amount }, 0.01)
            let gaps = CGFloat(cats.count) * 3
            HStack(spacing: 3) {
                if rest > 0 {
                    Capsule().fill(mode == .fullColor ? Color(UIColor(rgb: 0x7A766E)) : .white.opacity(0.35))
                        .frame(width: max(6, (g.size.width - gaps) * rest / total))
                }
                ForEach(cats, id: \.id) { c in
                    Capsule().fill(mode == .fullColor ? Wimg.categoryBar(c.id) : .white.opacity(0.85))
                        .frame(width: max(6, (g.size.width - gaps) * c.amount / total))
                }
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

private struct NoData: View {
    let text: String
    var color: Color
    var body: some View {
        Text(text).font(WimgFont.font(.inter, .medium, 13)).ink(color)
    }
}

// MARK: - Monat

struct MonthWidgetView: View {
    let entry: WimgEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .accessoryCircular: daysRing
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    private var d: WidgetPayload { entry.data }
    private var masked: Bool { entry.masked }
    private var sub: Color { Wimg.bandSub }

    private var header: some View {
        HStack(alignment: .top) {
            Text(family == .systemSmall ? d.headline : "\(d.headline) · \(d.daysText)")
                .font(WimgFont.font(.inter, .semibold, 13)).ink(sub).lineLimit(2)
            Spacer(minLength: 6)
            PocketBadge()
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !d.hasData {
                Spacer()
                NoData(text: L("Öffne wimg einmal, dann steht hier dein Monat."), color: sub)
            } else {
                Spacer(minLength: 4)
                BigAmount(euros: d.available, size: 26, masked: masked)
                Text(d.overdueText ?? d.daysText).font(WimgFont.font(.inter, .regular, 13))
                    .ink(d.overdueText != nil ? Wimg.bandNeg : sub).lineLimit(2)
                Spacer(minLength: 4)
                Text(d.isCalendar ? L("%s Ausgaben", WMoney.text(-d.expenses, masked: masked))
                                  : L("%s pro Tag", WMoney.text(max(0, d.perDay), masked: masked)))
                    .font(WimgFont.font(.inter, .regular, 12)).ink(sub).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Wimg.band, for: .widget)
        .environment(\.colorScheme, .dark)
    }

    private var footer: some View {
        HStack {
            (Text(L("Ausgaben") + " ").font(WimgFont.font(.inter, .regular, 13))
                + Text(WMoney.text(-d.expenses, masked: masked)).font(WimgFont.font(.manrope, .bold, 14)))
            Spacer(minLength: 8)
            (Text((d.isCalendar ? L("Ausgaben/Tag") : L("pro Tag")) + " ").font(WimgFont.font(.inter, .regular, 13))
                + Text(WMoney.text(max(0, d.perDay), plus: false, masked: masked)).font(WimgFont.font(.manrope, .bold, 14)))
        }
        .ink(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !d.hasData {
                Spacer()
                NoData(text: L("Öffne wimg einmal, dann steht hier dein Monat."), color: sub)
            } else {
                Spacer(minLength: 4)
                BigAmount(euros: d.available, size: 34, masked: masked)
                if let o = d.overdueText {
                    Text(o).font(WimgFont.font(.inter, .regular, 13)).ink(Wimg.bandNeg).lineLimit(1)
                }
                Spacer(minLength: 6)
                SpendBar(data: d)
                Spacer(minLength: 8)
                footer
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Wimg.band, for: .widget)
        .environment(\.colorScheme, .dark)
    }

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var scheme

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if d.hasData {
                    BigAmount(euros: d.available, size: 34, masked: masked).padding(.top, 8)
                    if let o = d.overdueText {
                        Text(o).font(WimgFont.font(.inter, .regular, 13)).ink(Wimg.bandNeg).lineLimit(1)
                    }
                    SpendBar(data: d).padding(.top, 12)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(renderingMode == .fullColor ? Wimg.band : .clear)
            .environment(\.colorScheme, .dark)

            VStack(alignment: .leading, spacing: 0) {
                if !d.hasData {
                    NoData(text: L("Öffne wimg einmal, dann steht hier dein Monat."), color: Wimg.text2)
                } else {
                    ForEach(Array(d.categories.prefix(4).enumerated()), id: \.element.id) { i, c in
                        HStack(spacing: 10) {
                            Circle().fill(renderingMode == .fullColor ? Wimg.categoryBar(c.id) : .primary).frame(width: 8, height: 8)
                            Text(L(WimgCategory.from(c.id).name)).font(WimgFont.font(.inter, .semibold, 14)).ink(Wimg.text).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(WMoney.text(c.amount, plus: false, masked: masked)).font(WimgFont.font(.manrope, .bold, 14)).ink(Wimg.text)
                        }
                        .frame(height: 30)
                        Rectangle().fill(Wimg.line).frame(height: 1)
                    }
                    if !d.nextDue.isEmpty {
                        Text(L("Als Nächstes fällig")).font(WimgFont.font(.inter, .bold, 12)).ink(Wimg.text2).padding(.top, 10)
                        ForEach(d.nextDue.prefix(2), id: \.self) { due in
                            HStack {
                                Text("\(due.name) · \(WDates.short(due.date))").font(WimgFont.font(.inter, .regular, 13)).ink(Wimg.text).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(WMoney.text(due.amount, masked: masked)).font(WimgFont.font(.manrope, .bold, 13)).ink(Wimg.text)
                            }
                            .padding(.top, 3)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .containerBackground(paper, for: .widget)
    }

    // MARK: Lock screen (always one colour: shape and number carry it)

    /// "wimg · 927 € bis 27.11."
    private var inline: some View {
        Label {
            Text(d.hasData ? "wimg · " + L("%s bis %s", WMoney.whole(d.available, plus: false, masked: masked), WDates.dotted(d.periodEnd)) : "wimg")
        } icon: {
            Image(systemName: "wallet.bifold")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(d.headline, systemImage: "wallet.bifold")
                .font(WimgFont.font(.inter, .semibold, 13))
                .lineLimit(1)
            Text(WMoney.whole(d.available, masked: masked))
                .font(WimgFont.font(.manrope, .heavy, 22))
                .widgetAccentable()
            Text(d.isCalendar ? d.daysText
                              : L("%s pro Tag", WMoney.whole(max(0, d.perDay), plus: false, masked: masked)) + " · " + L("%d Tage", d.daysLeft))
                .font(WimgFont.font(.inter, .regular, 12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }

    /// The band's ring: an arc for the days until the period ends.
    private var daysRing: some View {
        Gauge(value: Double(max(0, d.daysLeft)), in: 0...Double(max(1, d.periodDays))) {
            EmptyView()
        } currentValueLabel: {
            VStack(spacing: -2) {
                Text("\(d.daysLeft)").font(WimgFont.font(.manrope, .heavy, 20))
                Text(L("Tage")).font(WimgFont.font(.inter, .semibold, 10))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel(d.daysText)
    }
}

// MARK: - Fixkosten offen

struct FixedWidgetView: View {
    let entry: WimgEntry
    @Environment(\.widgetFamily) private var family
    private var d: WidgetPayload { entry.data }

    var body: some View {
        if family == .accessoryCircular { circular } else { small }
    }

    private var foot: String {
        if !d.hasData { return L("Öffne wimg einmal.") }
        if let n = d.nextDue.first { return L("nächste: %s · %s", n.name, WDates.short(n.date)) }
        return L("Keine festen Zahlungen erkannt")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Fixkosten offen")).font(WimgFont.font(.inter, .semibold, 13)).ink(Wimg.text2).lineLimit(1)
            Spacer(minLength: 4)
            if d.hasData {
                BigAmount(euros: -d.fixedOpen, size: 26, masked: entry.masked, color: Wimg.text)
                Text(L("%d von %d", d.fixedOpenCount, d.fixedCount)).font(WimgFont.font(.inter, .regular, 13)).ink(Wimg.text2)
                Spacer(minLength: 4)
            }
            Text(foot).font(WimgFont.font(.inter, .regular, 12)).ink(Wimg.text2).lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(paper, for: .widget)
    }

    /// "3 offen" with the recurring symbol.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .semibold))
                Text("\(d.fixedOpenCount)").font(WimgFont.font(.manrope, .heavy, 18)).widgetAccentable()
                Text(L("offen")).font(WimgFont.font(.inter, .semibold, 10))
            }
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Fixkosten offen") + ": \(d.fixedOpenCount)")
    }
}

// MARK: - Heute

struct TodayWidgetView: View {
    let entry: WimgEntry
    private var d: WidgetPayload { entry.data }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Heute")).font(WimgFont.font(.inter, .semibold, 13)).ink(Wimg.text2)
            Spacer(minLength: 4)
            if d.hasData {
                BigAmount(euros: d.todaySum, size: 26, masked: entry.masked, color: Wimg.text)
                Text(d.todayCount == 1 ? L("1 Umsatz") : L("%d Umsätze", d.todayCount))
                    .font(WimgFont.font(.inter, .regular, 13)).ink(Wimg.text2)
                Spacer(minLength: 4)
                if let last = d.todayLast {
                    Text(L("zuletzt %s", last)).font(WimgFont.font(.inter, .regular, 12)).ink(Wimg.text2).lineLimit(1)
                }
            } else {
                Text(L("Öffne wimg einmal.")).font(WimgFont.font(.inter, .regular, 12)).ink(Wimg.text2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(paper, for: .widget)
    }
}

// MARK: - Previews

#Preview("Bis zum Gehalt", as: .systemSmall) { WimgWidget() } timeline: {
    WimgEntry(date: .now, data: .sample, masked: false)
}
#Preview("Monat", as: .systemMedium) { WimgWidget() } timeline: {
    WimgEntry(date: .now, data: .sample, masked: false)
}
#Preview("Groß", as: .systemLarge) { WimgWidget() } timeline: {
    WimgEntry(date: .now, data: .sample, masked: false)
}
#Preview("Fixkosten", as: .systemSmall) { WimgFixedWidget() } timeline: {
    WimgEntry(date: .now, data: .sample, masked: true)
}
