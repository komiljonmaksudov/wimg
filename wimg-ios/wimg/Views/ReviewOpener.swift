import SwiftUI
import WimgI18n

// Rückblick opener (as Android's ReviewOpener.kt): up to four cards before a
// finished period's review, tap for the next, "Überspringen" to leave. Only
// cards that are true for the period.

struct OpenerCard: Identifiable {
    enum Figure { case voll, ring(Double), sleep(stitches: Int), caught(old: String, new: String) }
    let id = UUID()
    let label: String
    /// Headline as (before, highlighted amount, after); amount may be empty.
    let head: (String, String, String)
    let sub: String
    let figure: Figure
}

/// A fixed cost that got dearer in the period ("Abo erwischt").
struct PriceRise {
    let name: String
    let old: Double
    let new: Double
}

enum ReviewOpenerCards {
    static func cards(_ d: ReviewData, label: String, prevLabel: String?, salaryMode: Bool) -> [OpenerCard] {
        guard let s = d.summary else { return [] }
        func eur(_ v: Double) -> String { amountText(v, showPlus: false) }
        let net = s.income - abs(s.expenses)
        let leftOver = s.income > 0 && net > 0
        let rate = leftOver ? Int(net / s.income * 100) : 0
        var out: [OpenerCard] = []
        if leftOver {
            let parts = (salaryMode ? L("Vom Gehalt sind %s übrig geblieben.", "\u{0}") : L("Von den Einnahmen sind %s übrig geblieben.", "\u{0}"))
                .components(separatedBy: "\u{0}")
            out.append(OpenerCard(label: label, head: (parts.first ?? "", eur(net), parts.count > 1 ? parts[1] : ""),
                                  sub: L("Sparquote %d %%.", rate), figure: .voll))
        }
        if leftOver, let p = d.previous, p.income > 0 {
            let prevRate = Int((p.income - abs(p.expenses)) / p.income * 100)
            if rate > prevRate {
                out.append(OpenerCard(
                    label: L("Sparquote"),
                    head: (prevLabel.map { L("Sparquote %d %%, höher als im %s.", rate, $0) } ?? L("Sparquote %d %%, höher als im Zeitraum davor.", rate), "", ""),
                    sub: prevLabel.map { L("%s: %d %%.", $0, prevRate) } ?? L("Davor: %d %%.", prevRate),
                    figure: .ring(min(max(Double(rate) / 100, 0), 1))))
            }
        }
        if d.noSpend >= 3 {
            var sub = ""
            if let prev = d.prevNoSpend, d.noSpend > prev {
                sub = prevLabel.map { L("%d mehr als im %s.", d.noSpend - prev, $0) } ?? L("%d mehr als im Zeitraum davor.", d.noSpend - prev)
            }
            out.append(OpenerCard(label: L("Ruhige Tage"), head: (L("%d Tage ohne Ausgaben.", d.noSpend), "", ""),
                                  sub: sub, figure: .sleep(stitches: d.noSpend)))
        }
        if let r = d.priceRise {
            out.append(OpenerCard(label: L("Abo erwischt"), head: (L("Abo erwischt: %s +%s.", r.name, eur(r.new - r.old)), "", ""),
                                  sub: L("Jetzt %s statt %s.", eur(r.new), eur(r.old)),
                                  figure: .caught(old: eur(r.old), new: eur(r.new))))
        }
        return out
    }

    /// Days in from…to (up to today) without any spending.
    static func noSpendCount(from: String, to: String, txs: [Transaction]) -> Int {
        let today = WimgDates.todayIso()
        let end = to < today ? to : today
        let spent = Set(txs.filter { $0.amount < 0 && !$0.isExcluded && $0.date >= from && $0.date <= end }.map(\.date))
        guard var d = WimgDates.parse(from) else { return 0 }
        let cal = Calendar(identifier: .gregorian)
        var n = 0
        while WimgDates.iso(d) <= end {
            if !spent.contains(WimgDates.iso(d)) { n += 1 }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return n
    }

    static func priceRise(from: String, to: String) -> PriceRise? {
        LibWimg.getRecurring()
            .filter { p in
                guard let prev = p.prev_amount else { return false }
                return p.isActive && !p.isHidden && p.amount < 0 && p.price_change != nil
                    && abs(p.amount) - abs(prev) > 0.5 && p.last_seen >= from && p.last_seen <= to
            }
            .max { $0.last_seen < $1.last_seen }
            .map { PriceRise(name: $0.displayName, old: abs($0.prev_amount ?? 0), new: abs($0.amount)) }
    }
}

/// The cards, full screen.
struct ReviewOpenerView: View {
    let title: String
    let cards: [OpenerCard]
    let onDone: () -> Void

    @State private var i = 0
    @State private var t: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme

    private var bg: Color { scheme == .dark ? Color(UIColor(rgb: 0x111114)) : Color(UIColor(rgb: 0xF3ECDD)) }
    private var ink: Color { scheme == .dark ? Color(UIColor(rgb: 0xF2F2F3)) : Color(UIColor(rgb: 0x1A1A1A)) }
    private var sub: Color { scheme == .dark ? Color(UIColor(rgb: 0x9A9BA0)) : Color(UIColor(rgb: 0x6B6A66)) }

    var body: some View {
        let card = cards[min(i, cards.count - 1)]
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(cards.indices, id: \.self) { j in
                    Capsule().fill(j <= i ? ink : ink.opacity(0.14)).frame(height: 3)
                }
            }
            .padding(.top, 6)
            HStack {
                Text(title).wimgStyle(WimgType.desc).foregroundStyle(sub)
                Spacer()
                Button(L("Überspringen"), action: onDone).wimgStyle(WimgType.desc).foregroundStyle(sub)
            }
            .padding(.top, 12)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 0) {
                figure(card).frame(maxWidth: .infinity).frame(minHeight: 250)
                if case let .sleep(n) = card.figure { stitches(n) }
                Text(card.label).wimgStyle(WimgType.desc).foregroundStyle(sub).padding(.top, 22)
                (Text(card.head.0) + Text(card.head.1).foregroundStyle(Wimg.pos) + Text(card.head.2))
                    .font(WimgFont.font(.manrope, .heavy, 28, relativeTo: .title)).tracking(-0.4)
                    .foregroundStyle(ink)
                    .padding(.top, 6)
                if !card.sub.isEmpty {
                    Text(card.sub).wimgStyle(WimgType.body).foregroundStyle(sub).padding(.top, 10)
                }
            }
            .id(card.id)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)), removal: .opacity))
            Spacer(minLength: 12)
            Text(L("Tippen für weiter")).wimgStyle(WimgType.desc).foregroundStyle(sub).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
        .background(bg.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture {
            if i < cards.count - 1 { withAnimation(WimgMotion.out(0.24)) { i += 1 } } else { onDone() }
        }
        .accessibilityAction(named: L("Weiter")) { if i < cards.count - 1 { i += 1 } else { onDone() } }
        .task(id: i) {
            t = reduce ? 1 : 0
            guard !reduce else { return }
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.7)) { t = 1 }
        }
    }

    @ViewBuilder private func figure(_ card: OpenerCard) -> some View {
        switch card.figure {
        case .voll:
            Image(SquirrelPose.voll.image).resizable().scaledToFit().frame(width: 220, height: 220)
                .scaleEffect(x: 1.03 - 0.03 * t, y: 0.95 + 0.05 * t, anchor: .bottom)
        case let .ring(f):
            ZStack {
                Circle().stroke(ink.opacity(0.10), lineWidth: 12)
                Circle().trim(from: 0, to: f * t)
                    .stroke(scheme == .dark ? Wimg.accentLight : Wimg.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(SquirrelPose.normal.image).resizable().scaledToFit().frame(width: 176, height: 176).offset(y: 4)
            }
            .frame(width: 204, height: 204)
        case .sleep:
            Image(SquirrelPose.sleep.image).resizable().scaledToFit().frame(width: 220, height: 220)
        case let .caught(old, new):
            ZStack(alignment: .leading) {
                Image(SquirrelPose.look.image).resizable().scaledToFit().frame(width: 220, height: 220)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                PriceTag(old: old, new: new, flipped: t > 0.5).offset(y: 30)
            }
            .frame(width: 300)
        }
    }

    private func stitches(_ n: Int) -> some View {
        let shown = min(n, Int(t * 1.1 * Double(n) + 0.0001))
        return GeometryReader { g in
            let left: CGFloat = 18, right = g.size.width - 18
            let step = n > 1 ? min(24, (right - left) / CGFloat(n - 1)) : 0
            let a = max(min(5, step * 0.4), 2)
            ZStack {
                Capsule().fill(ink.opacity(0.10)).frame(height: 10)
                Path { p in
                    for j in 0..<shown {
                        let x = left + CGFloat(j) * step, y = g.size.height / 2
                        p.move(to: CGPoint(x: x - a, y: y - a)); p.addLine(to: CGPoint(x: x + a, y: y + a))
                        p.move(to: CGPoint(x: x - a, y: y + a)); p.addLine(to: CGPoint(x: x + a, y: y - a))
                    }
                }
                .stroke(Color(UIColor(rgb: 0xE08A2E)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .frame(height: 28)
        .padding(.top, 14)
        .accessibilityHidden(true)
    }
}

/// The caught price tag: old price, flipping to the new one.
private struct PriceTag: View {
    let old: String
    let new: String
    let flipped: Bool

    var body: some View {
        Text(flipped ? new : old)
            .font(WimgFont.font(.manrope, .heavy, 15))
            .foregroundStyle(flipped ? Color(UIColor(rgb: 0x9A5B00)) : Color(UIColor(rgb: 0x6B6A66)))
            .padding(.leading, 12).padding(.trailing, 20).padding(.vertical, 8)
            .background(TagShape().fill(Color(UIColor(rgb: 0xFFF6E2))))
            .overlay(TagShape().stroke(Color(UIColor(rgb: 0xB8922E)), lineWidth: 1.8))
            .rotationEffect(.degrees(-8))
            .rotation3DEffect(.degrees(flipped ? 0 : 180), axis: (x: 1, y: 0, z: 0))
            .animation(WimgMotion.inOut(0.3), value: flipped)
            .accessibilityHidden(true)
    }

    private struct TagShape: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - 10, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX - 10, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}
