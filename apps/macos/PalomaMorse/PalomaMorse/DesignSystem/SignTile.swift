import SwiftUI

enum SignTileState: Equatable {
    case normal
    case sounding(Pulse)
    case awaitingAnswer
    case correct
    case wrong
    case selected
    /// Another sign is sounding (exercise 1, preview): released "locked" cards.
    case dimmed
}

/// CSS `ease`, the timing function of the released transitions (hover lift).
private func cssEase(_ duration: Double) -> Animation {
    .timingCurve(0.25, 0.1, 0.25, 1, duration: duration)
}

/// A wrong answer shakes once (0.3 s, as released). Reduce Motion: no shake.
private struct WrongShake: ViewModifier {
    var state: SignTileState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakes = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakes) { view, offset in
                view.offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-4, duration: 0.075)
                    CubicKeyframe(4, duration: 0.15)
                    CubicKeyframe(0, duration: 0.075)
                }
            }
            .onChange(of: state) { _, new in
                if new == .wrong, !reduceMotion { shakes += 1 }
            }
    }
}

extension EnvironmentValues {
    /// Namespace of the sounding-sign lens shared by the cards / keys of one grid.
    @Entry var signLens: Namespace.ID?
}

/// The sounding sign's lens: an accent glow under the card's clear glass. With
/// a shared namespace it glides from card to card instead of blinking out and in.
private struct SoundingLens: View {
    var cornerRadius: CGFloat
    var glow: CGFloat

    @Environment(\.signLens) private var lens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.accentColor.opacity(0.34))
            .shadow(color: .accentColor.opacity(0.4), radius: glow)
        if let lens {
            shape.matchedGeometryEffect(id: "sounding-lens", in: lens)
        } else {
            shape.transition(.opacity)
        }
    }
}

/// Presentation of "which sign sounds": follows the engine at once when a sign
/// starts (the lens springs there), but outlives a finished sign by a short
/// hold before fading — a fast sign never flashes, and the next sign picks the
/// lens up in flight.
struct SoundingHold: ViewModifier {
    var active: String?
    @Binding var lit: String?

    @State private var release: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: active, initial: true) { _, sign in
                release?.cancel()
                if let sign {
                    withAnimation(.spring(duration: 0.42, bounce: 0.18)) { lit = sign }
                } else if lit != nil {
                    release = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.5)) { lit = nil }
                    }
                }
            }
            .onDisappear { release?.cancel() }
    }
}

extension SignTileState {
    /// The same sign keeps one look while it sounds, whatever the current element.
    var steady: SignTileState {
        if case .sounding = self { return .sounding(.none) }
        return self
    }
}

/// Lesson sign card of exercises 1–2: the glyph alone on a Liquid Glass button,
/// as in the released client. Pattern and mnemonic appear in the lesson header.
struct LetterCard: View {
    var sign: String
    var state: SignTileState
    var height: CGFloat = 120
    var isEnabled = true
    var accessibilityDetail: String
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(sign)
                // 48 pt in a 120 pt card (36 for Щ-codes), scaled with the card.
                .font(.system(size: (height * (sign.count > 2 ? 0.36 : 0.4)).rounded(), weight: .heavy))
                .foregroundStyle(foreground)
                .shadow(color: glyphGlow(foreground, state, colorScheme), radius: 8)
                // One soft "breath" when the sign starts sounding, no per-element pulse.
                .scaleEffect(isSounding ? 1.05 : 1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, Spacing.s)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(.rect(cornerRadius: Radius.tile))
        }
        .buttonStyle(.plain)
        // Inside a GlassEffectContainer `.opacity` is not applied to glass, so a
        // muted ("locked") card drops its glass and fades its glyph instead.
        .background {
            if isSounding {
                SoundingLens(cornerRadius: Radius.tile, glow: 16)
            } else if state == .dimmed {
                RoundedRectangle(cornerRadius: Radius.tile).fill(.fill.quinary)
                    .transition(.opacity)
            }
        }
        .glassEffect(state == .dimmed ? .identity : glass, in: .rect(cornerRadius: Radius.tile))
        .animation(.smooth(duration: 0.35), value: state.steady)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.tile)
                .strokeBorder(border, lineWidth: borderWidth)
        }
        .overlay(alignment: .topTrailing) {
            if state == .selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .padding(Spacing.xs)
            }
        }
        .modifier(WrongShake(state: state.steady))
        .offset(y: liftsOnHover ? (state == .awaitingAnswer ? -3 : -2) : 0)
        .animation(cssEase(0.1), value: isHovered)
        .onHover { isHovered = $0 }
        // Not `.disabled`: its system dimming would also fade the sounding card.
        .allowsHitTesting(isEnabled)
        .accessibilityRespondsToUserInteraction(isEnabled)
        .accessibilityLabel(sign)
        .accessibilityValue(stateDescription(state))
        .accessibilityHint(accessibilityDetail)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }

    private var liftsOnHover: Bool {
        isHovered && isEnabled && (state == .normal || state == .awaitingAnswer || state == .selected)
    }

    private var glass: Glass {
        switch state {
        case .sounding: .clear.interactive()
        case .correct: .regular.tint(SignalPalette.correct.opacity(0.22)).interactive()
        case .wrong: .regular.tint(SignalPalette.wrong.opacity(0.22)).interactive()
        case .selected: .regular.tint(.accentColor.opacity(0.12)).interactive()
        default: .clear.interactive()
        }
    }

    private var isSounding: Bool {
        if case .sounding = state { return true }
        return false
    }

    private var foreground: Color {
        switch state {
        case .sounding: .primary
        case .selected: .accentColor
        case .correct: SignalPalette.correct
        case .wrong: SignalPalette.wrong
        case .dimmed: .primary.opacity(0.28)
        default: .primary
        }
    }

    private var border: Color {
        switch state {
        case .sounding: .clear
        case .selected: .accentColor.opacity(0.8)
        case .correct: SignalPalette.correct
        case .wrong: SignalPalette.wrong
        // Hover only lifts the card; no accent outline.
        case .awaitingAnswer: .accentColor.opacity(0.25)
        default: .clear
        }
    }

    private var borderWidth: CGFloat {
        switch state {
        case .correct, .wrong, .selected: 1.5
        case .sounding: 1.5
        default: 1
        }
    }
}

/// Key of the ЙЦУКЕН answer keyboard (exercises 3–4 and custom selection), on
/// Liquid Glass. The sounding key fills with the accent colour, keys waiting for
/// an answer breathe slowly, signs outside the pool stay clickable for preview.
struct AnswerKey: View {
    var sign: String
    var size: CGFloat = 44
    var state: SignTileState
    var isEligible: Bool
    var isEnabled: Bool
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { (size * 1.2).rounded() }

    var body: some View {
        Button(action: action) {
            Text(sign)
                .font(.system(size: (size * 0.47).rounded(), weight: .bold))
                .foregroundStyle(foreground)
                .shadow(color: isMuted ? .clear : glyphGlow(foreground, state, colorScheme), radius: 6)
                .scaleEffect(isSounding ? 1.06 : 1)
                .frame(width: size, height: height)
                .contentShape(.rect(cornerRadius: Radius.key))
        }
        .buttonStyle(.plain)
        .background {
            if isSounding {
                SoundingLens(cornerRadius: Radius.key, glow: 10)
            }
        }
        // The key always keeps its glass; leaving or joining the pool only
        // changes its opacity, so it fades in and out without a dark flash.
        .glassEffect(glass, in: .rect(cornerRadius: Radius.key))
        .animation(.smooth(duration: 0.35), value: state.steady)
        .overlay { breathingBorder }
        .opacity(isMuted ? (isHovered && isEnabled ? 0.55 : 0.3) : 1)
        .animation(.smooth(duration: 0.5), value: isMuted)
        .modifier(WrongShake(state: state.steady))
        .offset(y: isHovered && isEnabled && isEligible ? -2 : 0)
        .animation(cssEase(0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .allowsHitTesting(isEnabled)
        .accessibilityRespondsToUserInteraction(isEnabled)
        .accessibilityLabel(sign)
        .accessibilityValue(isEligible ? stateDescription(state) : "не входит в набор")
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }

    /// Signs outside the pool and keys locked during the control work.
    private var isMuted: Bool { !isEligible || state == .dimmed }

    private var isSounding: Bool {
        if case .sounding = state { return true }
        return false
    }

    @ViewBuilder
    private var breathingBorder: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key)
        if state == .awaitingAnswer, !reduceMotion, !isHovered {
            // `key-pulse 2s infinite`: border 0.2 → 0.5 with a faint accent fill at the peak.
            shape.fill(Color.accentColor.opacity(0.05))
                .overlay { shape.strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1) }
                .phaseAnimator([0.2, 0.5]) { view, phase in
                    view.opacity(phase == 0.5 ? 1 : 0.4)
                } animation: { _ in .easeInOut(duration: 1) }
        } else {
            shape.strokeBorder(border, lineWidth: state == .normal || state == .dimmed ? 1 : 1.5)
        }
    }

    private var glass: Glass {
        switch state {
        case .sounding: .clear.interactive()
        case .selected: .regular.tint(.accentColor.opacity(0.18)).interactive()
        case .correct: .regular.tint(SignalPalette.correct.opacity(0.3)).interactive()
        case .wrong: .regular.tint(SignalPalette.wrong.opacity(0.3)).interactive()
        default: .clear.interactive()
        }
    }

    private var foreground: Color {
        if isMuted { return .primary }
        return switch state {
        case .correct: SignalPalette.correct
        case .wrong: SignalPalette.wrong
        case .sounding: .primary
        case .selected: .accentColor
        default: .primary
        }
    }

    private var border: Color {
        switch state {
        case .selected: .accentColor.opacity(0.8)
        case .awaitingAnswer: .accentColor.opacity(0.4)
        case .correct: SignalPalette.correct
        case .wrong: SignalPalette.wrong
        default: .clear
        }
    }
}

/// Glyphs in a coloured state glow in their own colour, like the released
/// text-shadow; plain glyphs stay crisp.
private func glyphGlow(_ color: Color, _ state: SignTileState, _ scheme: ColorScheme) -> Color {
    switch state {
    // On the light theme a dark glyph with a blue halo looks muddy; the lens glows instead.
    case .sounding: scheme == .dark ? Color.accentColor.opacity(0.7) : .clear
    case .selected, .correct, .wrong: color.opacity(0.6)
    default: .clear
    }
}

private func stateDescription(_ state: SignTileState) -> String {
    switch state {
    case .correct: "верно"
    case .wrong: "ошибка"
    case .sounding: "звучит"
    case .selected: "в наборе"
    default: ""
    }
}
