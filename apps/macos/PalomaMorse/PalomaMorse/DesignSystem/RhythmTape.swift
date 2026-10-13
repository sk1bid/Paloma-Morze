import SwiftUI

/// Rhythm tape of the released client (TapeDisplay.jsx): a dark strip that
/// scrolls continuously at 15 WPM (100 pt/s) with the "now" line 200 pt from
/// the right edge, presses emerging from it. Each press is a see-through piece
/// tinted and rimmed with its colour (green dot, pink dash, red too long) over
/// a faint halo; the held press is a little brighter. With Reduce Motion the tape does not scroll
/// and lays the latest presses out side by side.
struct RhythmTape: View {
    var rhythm: KeyRhythm
    var label: String?
    var isHighlighted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorScheme) private var colorScheme
    /// Pieces grow with the window: thicker and, through the scroll speed, longer.
    @Environment(\.uiScale) private var uiScale

    private var isDark: Bool { colorScheme == .dark }
    private var rim: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }

    /// `wpm / 150` px per ms in the released tape at its fixed 15 WPM.
    static let pointsPerSecond: CGFloat = 100
    /// Distance of the "now" line from the right edge (released `rightMargin`).
    static let nowInset: CGFloat = 200
    private static let barHeight: CGFloat = 24
    /// The tape is dark in both appearances, like the released one.
    static let background = Color(red: 0.14, green: 0.16, blue: 0.20)

    var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                tape(pieces: staticPieces(width: proxy.size.width), size: proxy.size)
            } else {
                // Runs while the window is active, like the released requestAnimationFrame loop.
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !appearsActive)) { timeline in
                    tape(pieces: scrollingPieces(width: proxy.size.width, now: timeline.date), size: proxy.size)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: Radius.panel))
        // Dark theme: the released dark strip. Light theme: a strip of light
        // Liquid Glass, so the tape does not punch a black hole in the window.
        .background {
            if isDark {
                RoundedRectangle(cornerRadius: Radius.panel).fill(Self.background)
            }
        }
        .glassEffect(isDark ? .identity : .regular, in: .rect(cornerRadius: Radius.panel))
        .overlay(alignment: .topLeading) {
            if let label {
                Text(label.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(isDark ? Color.white.opacity(0.6) : Color.secondary)
                    .padding(Spacing.s)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(isHighlighted ? SignalPalette.collision : rim, lineWidth: isHighlighted ? 2 : 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Лента ритма")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Pieces

    private struct Piece: Identifiable {
        let id: Int
        let x0: CGFloat
        let x1: CGFloat
        let color: Color
        let isHeld: Bool
    }

    /// One Canvas for axis and pieces: a see-through tinted body, a light wash of
    /// the colour from the top edge, a 1 pt rim and a faint halo. (Real glass per
    /// piece would add a backdrop layer per press redrawn every frame, with
    /// nothing to refract on the flat tape.)
    private func tape(pieces: [Piece], size: CGSize) -> some View {
        Canvas { context, size in
            drawAxis(in: &context, size: size)
            let midY = size.height / 2
            let barHeight = Self.barHeight * uiScale
            let corner = 7 * uiScale
            func rect(_ piece: Piece) -> CGRect {
                CGRect(x: piece.x0, y: midY - barHeight / 2, width: piece.x1 - piece.x0, height: barHeight)
            }
            var halo = context
            halo.addFilter(.blur(radius: 6))
            for piece in pieces {
                halo.fill(Path(roundedRect: rect(piece), cornerRadius: corner),
                          with: .color(piece.color.opacity(piece.isHeld ? 0.55 : 0.32)))
            }
            for piece in pieces {
                let r = rect(piece)
                let shape = Path(roundedRect: r, cornerRadius: corner)
                context.fill(shape, with: .color(piece.color.opacity(piece.isHeld ? 0.6 : 0.42)))
                context.fill(shape, with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(isDark ? 0.22 : 0.45), piece.color.opacity(0.15), .clear]),
                    startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
                context.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: corner - 0.5),
                               with: .color(piece.color.opacity(0.95)), lineWidth: 1)
            }
        }
    }

    private func nowX(_ width: CGFloat) -> CGFloat { max(width * 0.5, width - Self.nowInset * uiScale) }
    private var speed: CGFloat { Self.pointsPerSecond * uiScale }

    private func scrollingPieces(width: CGFloat, now: Date) -> [Piece] {
        let origin = nowX(width)
        return rhythm.marks.compactMap { mark in
            let end = mark.end ?? now
            let x1 = origin - CGFloat(now.timeIntervalSince(end)) * speed
            let x0 = origin - CGFloat(now.timeIntervalSince(mark.start)) * speed
            guard x1 > -8, x0 < width else { return nil }
            return Piece(id: mark.id, x0: x0, x1: max(x1, x0 + 3), color: color(of: mark, now: now), isHeld: mark.end == nil)
        }
    }

    private func staticPieces(width: CGFloat) -> [Piece] {
        var pieces: [Piece] = []
        var x = nowX(width)
        for mark in rhythm.marks.reversed() {
            let length: CGFloat = (mark.kind == .dot ? 10 : 30) * uiScale
            x -= length
            guard x > 0 else { break }
            pieces.append(Piece(id: mark.id, x0: x, x1: x + length, color: color(of: mark, now: .now), isHeld: mark.end == nil))
            x -= 8 * uiScale
        }
        return pieces
    }

    /// Finished presses by their class; the held press by its running length
    /// (released thresholds: dash from 2 units, too long past 4.5 units).
    private func color(of mark: KeyMark, now: Date) -> Color {
        let kind = mark.kind ?? {
            let held = now.timeIntervalSince(mark.start)
            if held > KeyTiming.unit * KeyTiming.tooLongFactor { return .tooLong }
            return held >= KeyTiming.dashThreshold ? .dash : .dot
        }()
        return switch kind {
        case .dot: SignalPalette.dot
        case .dash: SignalPalette.dash
        case .tooLong: SignalPalette.tooLong
        }
    }

    private func drawAxis(in context: inout GraphicsContext, size: CGSize) {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: size.height / 2))
        line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(line, with: .color(isDark ? .white.opacity(0.12) : .black.opacity(0.12)),
                       style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        var now = Path()
        now.move(to: CGPoint(x: nowX(size.width), y: 6))
        now.addLine(to: CGPoint(x: nowX(size.width), y: size.height - 6))
        context.stroke(now, with: .color(isDark ? SignalPalette.glow.opacity(0.3) : Color.accentColor.opacity(0.35)),
                       lineWidth: 1)
    }

    private var accessibilitySummary: String {
        let recent = rhythm.marks.suffix(8).compactMap { mark -> String? in
            switch mark.kind {
            case .dot: "точка"
            case .dash: "тире"
            case .tooLong: "передержка"
            case nil: nil
            }
        }
        if rhythm.isDown { return (recent + ["ключ нажат"]).joined(separator: ", ") }
        return recent.isEmpty ? "нет нажатий" : recent.joined(separator: ", ")
    }
}

/// Legend of the tape: ТОЧКА · ТИРЕ · ПЕРЕДЕРЖАЛ.
struct RhythmLegend: View {
    var body: some View {
        HStack(spacing: Spacing.m) {
            item("Точка", SignalPalette.dot)
            item("Тире", SignalPalette.dash)
            item("Передержал", SignalPalette.tooLong)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func item(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title.uppercased()).tracking(0.5)
        }
    }
}
