import SwiftUI
import WimgI18n

// The Dock: one status row directly above the tab bar, only while there is
// something to say (undo, a running fetch, an error, a question). One at a
// time, the newest wins. Same model as Android's `Dock` in WimgKit.kt; drawn
// as on boards 03 (undo) and 04 (fetch progress) of brief 22.

enum DockKind { case sync, error, undo, prompt, info }

struct DockRow: Identifiable, Equatable {
    var id = UUID()
    let kind: DockKind
    var title: String
    var sub: String? = nil
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    /// A second, quieter answer left of `action` ("Nein" before "Ja").
    var action2: String? = nil
    var onAction2: (() -> Void)? = nil
    /// 0…1 for a running fetch; nil when there is no progress bar.
    var progress: Double? = nil
    /// Right-aligned note next to the progress ("12 neu").
    var note: String? = nil
    /// Dismisses itself after this many seconds.
    var timeout: Double? = nil
    /// Replaces the kind's icon.
    var systemImage: String? = nil

    static func == (a: DockRow, b: DockRow) -> Bool {
        a.id == b.id && a.progress == b.progress && a.note == b.note && a.title == b.title && a.sub == b.sub
    }
}

@MainActor @Observable
final class Dock {
    static let shared = Dock()
    private(set) var row: DockRow?
    private var timer: Task<Void, Never>?

    func show(_ r: DockRow) {
        row = r
        timer?.cancel()
        if let t = r.timeout {
            // The timeout runs on the clock, not on an animation: with Reduce
            // Motion an undo row must still stay long enough to be tapped.
            timer = Task { [id = r.id] in
                try? await Task.sleep(for: .seconds(t))
                if !Task.isCancelled { self.dismiss(id) }
            }
        }
    }

    /// Updates a running row (progress, note) without restarting it.
    func update(_ id: UUID, progress: Double? = nil, note: String? = nil, title: String? = nil) {
        guard var r = row, r.id == id else { return }
        if let progress { r.progress = progress }
        if let note { r.note = note }
        if let title { r.title = title }
        row = r
    }

    func dismiss(_ id: UUID? = nil) {
        if id == nil || row?.id == id { row = nil }
    }

    func undo(_ title: String, sub: String? = nil, onUndo: @escaping () -> Void) {
        show(DockRow(kind: .undo, title: title, sub: sub, action: #L("Rückgängig"), onAction: onUndo,
                     timeout: WimgMotion.undoCountdown))
    }

    func info(_ title: String, sub: String? = nil) {
        show(DockRow(kind: .info, title: title, sub: sub, timeout: 4))
    }

    func error(_ title: String, sub: String? = nil, action: String? = nil, onAction: (() -> Void)? = nil) {
        show(DockRow(kind: .error, title: title, sub: sub, action: action, onAction: onAction, timeout: 8))
    }

    /// A running job with a progress bar; returns its id for `update`/`dismiss`.
    @discardableResult
    func progress(_ title: String, note: String? = nil) -> UUID {
        let r = DockRow(kind: .sync, title: title, progress: 0, note: note)
        show(r)
        return r.id
    }
}

// MARK: - View

struct DockView: View {
    let row: DockRow

    var body: some View {
        Group {
            if let progress = row.progress {
                progressRow(progress)
            } else {
                actionRow
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 60)
        .dockBackground()
        .accessibilityElement(children: .contain)
    }

    private var tint: (bg: Color, fg: Color, icon: String) {
        switch row.kind {
        case .sync: (Wimg.syncBg, Wimg.sync, "arrow.triangle.2.circlepath")
        case .error: (Wimg.dangerBg, Wimg.danger, "exclamationmark.circle")
        case .undo: (Wimg.accentSoft, Wimg.accent, "tag")
        case .prompt: (Wimg.accentSoft, Wimg.accent, "info.circle")
        case .info: (Wimg.neutralTint, Wimg.pos, "checkmark")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Circle().fill(tint.bg).frame(width: 34, height: 34)
                .overlay(Image(systemName: row.systemImage ?? tint.icon)
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(tint.fg))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).wimgStyle(WimgType.chip).foregroundStyle(Wimg.text).lineLimit(1)
                if let sub = row.sub {
                    Text(sub).wimgStyle(WimgType.caption).foregroundStyle(Wimg.text2)
                        .lineLimit(row.kind == .error ? 3 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let a2 = row.action2, let on2 = row.onAction2 {
                Button { on2(); Dock.shared.dismiss(row.id) } label: {
                    Text(a2).wimgStyle(WimgType.chip).foregroundStyle(Wimg.text2)
                        .padding(.horizontal, 10).frame(minHeight: 40)
                }
                .buttonStyle(.wimgPress)
            }
            if let a = row.action, let on = row.onAction {
                Button { on(); Dock.shared.dismiss(row.id) } label: {
                    HStack(spacing: 6) {
                        if row.kind == .undo { Image(systemName: "arrow.uturn.backward").font(.system(size: 14, weight: .semibold)) }
                        Text(a).wimgStyle(WimgType.chip)
                    }
                    .foregroundStyle(row.kind == .error ? Wimg.danger : Wimg.onAccent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(row.kind == .error ? Wimg.dangerBg : Wimg.accent, in: Capsule())
                }
                .buttonStyle(.wimgPress)
            }
        }
        .padding(.vertical, 8)
    }

    private func progressRow(_ progress: Double) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(row.title).wimgStyle(WimgType.chip).foregroundStyle(Wimg.text).lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Wimg.line)
                        Capsule().fill(Wimg.accent).frame(width: g.size.width * max(0, min(1, progress)))
                    }
                }
                .frame(height: 4)
                .animation(.linear(duration: 0.4), value: progress)
            }
            if let note = row.note {
                Text(note).wimgStyle(WimgType.desc).foregroundStyle(Wimg.text2)
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue([row.note, "\(Int(progress * 100)) %"].compactMap { $0 }.joined(separator: ", "))
    }
}

extension View {
    /// White capsule with a hairline and a soft shadow (board 03).
    func dockBackground() -> some View {
        background(Wimg.card, in: Capsule())
            .overlay(Capsule().stroke(Wimg.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    /// Shows the Dock directly above the tab bar of this tab. Put it on each
    /// tab's root; only the visible tab draws it.
    func wimgDock() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            DockSlot()
        }
    }
}

private struct DockSlot: View {
    private var dock = Dock.shared

    var body: some View {
        ZStack {
            if let row = dock.row {
                DockView(row: row)
                    .id(row.id)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(WimgMotion.dock(deltaHeight: 68), value: dock.row?.id)
    }
}
