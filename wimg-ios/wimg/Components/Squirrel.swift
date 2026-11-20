import SwiftUI
import WimgI18n

// The squirrel in the band (as Android's Squirrel.kt / HomeScreen figureState):
// its pose says how the period is going; a tap says it in one line; a short
// moment plays once per period (Gehalt da, Knapp, Leer) or day (kein Euro raus).
// The poses are images rendered from the prototype's SVG (export-html/34).

enum SquirrelPose: String {
    case voll, normal, knapp, leer, gehalt, yawn, sleep, look

    var image: String { "squirrel-\(rawValue)" }
}

enum SquirrelState {
    /// Pose and the line a tap shows. Same rules as Android's figureState.
    static func of(available: Double, daysLeft: Int, usualPerDay: Double, salaryToday: Bool,
                   salary: Double?, salaryMode: Bool) -> (SquirrelPose, String) {
        let days = max(daysLeft, 1)
        let perDay = available / Double(days)
        func eur(_ v: Double) -> String { amountText(v, showPlus: false) }
        if salaryToday { return (.gehalt, L("Gehalt da: %s. Neuer Gehaltsmonat.", eur(salary ?? available))) }
        if available <= 0.004 {
            return (.leer, salaryMode ? L("Leer: %s im Minus. Gehalt kommt in ~%d Tagen.", eur(-available), days)
                                      : L("Leer: %s im Minus. Neuer Monat in %d Tagen.", eur(-available), days))
        }
        if usualPerDay > 0.5 && perDay < usualPerDay {
            return (.knapp, L("Knapp: noch %s für %d Tage, sonst gibst du ~%s am Tag aus.", eur(available), days, eur(usualPerDay)))
        }
        if usualPerDay > 0.5 && perDay > usualPerDay * 1.5 {
            return (.voll, L("Voll: noch %s für %d Tage. Du brauchst sonst ~%s am Tag. Viel Luft.", eur(available), days, eur(usualPerDay)))
        }
        if usualPerDay > 0.5 {
            return (.normal, L("Normal: %s für %d Tage, das sind %s am Tag. Sonst gibst du ~%s aus.", eur(available), days, eur(perDay), eur(usualPerDay)))
        }
        return (.normal, L("Normal: %s für %d Tage, das sind %s am Tag.", eur(available), days, eur(perDay)))
    }
}

/// The squirrel with its pose; blinks now and then, plays a moment once.
struct SquirrelView: View {
    let pose: SquirrelPose
    let line: String
    /// Key of the moment to play once ("knapp:2026-11-01"); nil = none.
    var moment: (key: String, from: SquirrelPose, text: String)? = nil
    var size: CGFloat = 88
    /// Android's ring around it: one stitch per day of the period, days
    /// already past dim, past days without spending sewn in orange.
    var ring: SquirrelRingDays? = nil
    /// A link under the moment's line ("Ansehen" on a price rise).
    var momentAction: (label: String, run: () -> Void)? = nil

    @State private var shown: SquirrelPose?
    @State private var blink = false
    @State private var hop: CGFloat = 0
    @State private var squash: CGFloat = 1
    @State private var bubble: String?
    @State private var bubbleHasAction = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let playedKey = "wimg_moments"

    var body: some View {
        let current = shown ?? pose
        figure(current)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .onTapGesture { if !line.isEmpty { show(bubble == line ? nil : line) } }
            // As on Android: a white bubble left of the ring, pointing at it,
            // over the amount without taking room.
            .overlay(alignment: .leading) {
                if let text = bubble {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(text).wimgStyle(WimgType.desc).foregroundStyle(Color(UIColor(rgb: 0x1A1A1A)))
                                .fixedSize(horizontal: false, vertical: true)
                            if bubbleHasAction, let a = momentAction {
                                Button(a.label) { a.run() }.wimgStyle(WimgType.chip).foregroundStyle(Wimg.accent)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                        BubbleTail().fill(.white).frame(width: 8, height: 14)
                    }
                    .frame(maxWidth: 228, alignment: .trailing)
                    .frame(width: 228, alignment: .trailing)
                    .alignmentGuide(.leading) { d in d[.trailing] - 10 }
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                    .onTapGesture { withAnimation(WimgMotion.out(0.15)) { bubble = nil } }
                }
            }
            .zIndex(1)
            .accessibilityElement()
            .accessibilityLabel(line)
            .accessibilityAddTraits(.isButton)
            .task(id: moment?.key) { await playMoment() }
            .task { await blinkLoop() }
    }

    @ViewBuilder private func figure(_ current: SquirrelPose) -> some View {
        let img = Image(blink && (current == .normal || current == .look) ? "squirrel-blink" : current.image)
            .resizable()
            .scaledToFit()
            .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
            .offset(y: hop)
        if let ring {
            // Same geometry as Android's SquirrelRing (a 112 box): ring radius 48,
            // squirrel 104 wide at (4, 2), inside the ring except ears and tail on top.
            let k = size / 112
            ZStack(alignment: .topLeading) {
                DayRing(days: ring, k: k)
                img.frame(width: 104 * k, height: 104 * k)
                    .offset(x: 4 * k, y: 2 * k)
                    .frame(width: size, height: size, alignment: .topLeading)
                    .mask {
                        ZStack(alignment: .top) {
                            Circle().frame(width: 88 * k, height: 88 * k).frame(width: size, height: size)
                            Rectangle().frame(width: size, height: 56 * k)
                        }
                    }
            }
        } else {
            img
        }
    }

    private func show(_ text: String?, action: Bool = false) {
        bubbleHasAction = action
        withAnimation(WimgMotion.out(0.2)) { bubble = text }
        guard let text else { return }
        Task {
            try? await Task.sleep(for: .seconds(action ? 7 : 5))
            withAnimation(WimgMotion.out(0.15)) { if bubble == text { bubble = nil } }
        }
    }

    /// The moment: from its start pose, a small squash and hop into the pose, the line.
    private func playMoment() async {
        guard let m = moment else { shown = nil; return }
        var played = Set(UserDefaults.standard.stringArray(forKey: Self.playedKey) ?? [])
        guard !played.contains(m.key) else { shown = nil; return }
        played.insert(m.key)
        UserDefaults.standard.set(Array(played.suffix(60)), forKey: Self.playedKey)
        let act = momentAction != nil
        if reduceMotion { shown = nil; show(m.text, action: act); return }
        shown = m.from
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(WimgMotion.out(0.22)) { squash = 0.93; hop = 2 }
        try? await Task.sleep(for: .milliseconds(220))
        shown = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { squash = 1.04; hop = -6 }
        try? await Task.sleep(for: .milliseconds(260))
        withAnimation(WimgMotion.inOut(0.26)) { squash = 1; hop = 0 }
        show(m.text, action: act)
    }

    private func blinkLoop() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3.5...7)))
            blink = true
            try? await Task.sleep(for: .milliseconds(140))
            blink = false
        }
    }
}

/// The period's days for the ring around the squirrel.
struct SquirrelRingDays: Equatable {
    let total: Int
    /// Days already past (today is the next one).
    let past: Int
    /// 1-based days among the past ones without spending.
    let noSpend: Set<Int>
}

/// Android's SquirrelRing without the squirrel: a stitch per day.
private struct DayRing: View {
    let days: SquirrelRingDays
    let k: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let c = CGPoint(x: 56 * k, y: 56 * k)
            let r: CGFloat = 48 * k, w: CGFloat = 7 * k
            let n = max(days.total, 1)
            let stitch = Color(UIColor(rgb: 0xE08A2E))
            for i in 0..<n {
                let step: Double = 360.0 / Double(n)
                let a0: Double = -90.0 + Double(i) * step + 1.6
                let sweep: Double = step - 3.2
                let past = i < days.past
                let quiet = past && days.noSpend.contains(i + 1)
                let future = Color(UIColor(rgb: 0x8FB0D3))
                let col: Color = !past ? future : (quiet ? stitch.opacity(0.25) : Color.white.opacity(0.12))
                var arc = Path()
                arc.addArc(center: c, radius: r, startAngle: .degrees(a0), endAngle: .degrees(a0 + sweep), clockwise: false)
                ctx.stroke(arc, with: .color(col), lineWidth: w)
                if quiet {
                    let mid: Double = (a0 + sweep / 2) * Double.pi / 180
                    let mx: CGFloat = c.x + r * CGFloat(cos(mid))
                    let my: CGFloat = c.y + r * CGFloat(sin(mid))
                    let m = CGPoint(x: mx, y: my)
                    let a: CGFloat = 3.4 * k
                    var x = Path()
                    x.move(to: CGPoint(x: -a, y: -a)); x.addLine(to: CGPoint(x: a, y: a))
                    x.move(to: CGPoint(x: -a, y: a)); x.addLine(to: CGPoint(x: a, y: -a))
                    let t = CGAffineTransform(translationX: m.x, y: m.y).rotated(by: CGFloat(mid))
                    ctx.stroke(x.applying(t), with: .color(stitch), style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round))
                }
            }
        }
        .frame(width: 112 * k, height: 112 * k)
        .accessibilityHidden(true)
    }
}

/// The bubble's tail, pointing right at the squirrel.
private struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
