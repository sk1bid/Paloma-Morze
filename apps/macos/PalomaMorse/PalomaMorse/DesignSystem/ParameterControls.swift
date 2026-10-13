import SwiftUI

// Controls of the released Paloma layout, drawn with platform components:
// mode tabs, the left parameter column, "− value +" steppers, Start/Stop.

/// Приём · Передача · Эфир — the released client's tabs, on Liquid Glass. In a
/// wide window they sit in the centre of the toolbar; in a narrow one (where the
/// toolbar has no room) they form a row above the content.
struct ModeTabs: View {
    @Bindable var model: AppModel
    var inToolbar = false

    @Environment(\.uiScale) private var uiScale

    var body: some View {
        GlassEffectContainer(spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                ForEach(AppSection.allCases) { section in
                    tab(section)
                }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Режим")
    }

    @ViewBuilder
    private func tab(_ section: AppSection) -> some View {
        let selected = model.section == section
        let locked = model.isSectionLocked(section)
        let scale = inToolbar ? 1 : uiScale.controlScale
        // One glass capsule per tab; the selected tint flows to the new tab.
        Button { model.select(section) } label: {
            Label(section.title.uppercased(), systemImage: section.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12 * scale, weight: .bold))
                .tracking(1.4)
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : (locked ? Color.secondary : Color.primary))
                .padding(.horizontal, Spacing.m)
                .frame(minWidth: inToolbar ? 112 : 132 * scale)
                .frame(height: (inToolbar ? 34 : 38) * scale)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
        .animation(.smooth(duration: 0.35), value: selected)
        .disabled(locked)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(locked ? "Недоступно во время сеанса в эфире" : "\(section.title) (⌘\(index(of: section)))")
    }

    private func index(of section: AppSection) -> Int {
        (AppSection.allCases.firstIndex(of: section) ?? 0) + 1
    }
}

extension EnvironmentValues {
    /// The parameter column is folded to its rail; controls in its footer go compact.
    @Entry var parameterColumnCollapsed = false
}

/// The left column of Reception and Transmission: parameters on top,
/// Start/Stop pinned to the bottom, as in the released client. It folds to a
/// narrow rail (toolbar button, ⌃⌘S) that keeps the current values and
/// Start/Stop, so the main controls never disappear with it.
struct ParameterColumn<Content: View, Rail: View, Footer: View>: View {
    var isCollapsed: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var rail: Rail
    @ViewBuilder var footer: Footer

    @Environment(\.uiScale) private var uiScale

    static var railWidth: CGFloat { 76 }
    private var width: CGFloat { Spacing.parameterColumn * uiScale.controlScale }

    var body: some View {
        // Drawer motion: the left edge stays put, both layouts are pinned to the
        // leading edge at their own fixed width, and the clip reveals or hides
        // them as the column width animates — no growth from the centre.
        let inner = isCollapsed ? Self.railWidth - Spacing.xs * 2 : width - Spacing.s * 2
        VStack(alignment: .leading, spacing: Spacing.s) {
            ZStack(alignment: .topLeading) {
                if isCollapsed {
                    VStack(spacing: Spacing.m) { rail }
                        .padding(.top, Spacing.xs)
                        .frame(width: Self.railWidth - Spacing.xs * 2)
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s) { content }
                        .frame(width: width - Spacing.s * 2, alignment: .leading)
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                }
            }
            Spacer(minLength: Spacing.s)
            footer
                .environment(\.parameterColumnCollapsed, isCollapsed)
                .frame(width: inner)
        }
        .padding(.vertical, Spacing.s)
        .padding(.leading, isCollapsed ? Spacing.xs : Spacing.s)
        .frame(width: isCollapsed ? Self.railWidth : width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .clipped()
        .contentSurface()
        .animation(.smooth(duration: 0.4), value: isCollapsed)
    }
}

extension ParameterColumn where Rail == EmptyView {
    init(isCollapsed: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(isCollapsed: isCollapsed, content: content, rail: { EmptyView() }, footer: footer)
    }
}

/// Icon form of an OptionToggle on the folded rail.
struct RailToggle: View {
    var title: String
    var systemImage: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        Button { if isEnabled { isOn.toggle() } } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : (isEnabled ? Color.primary : Color.secondary))
                .frame(width: 40, height: 40)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .circle)
        .animation(.smooth(duration: 0.35), value: isOn)
        .allowsHitTesting(isEnabled)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "включено" : "выключено")
    }
}

/// A read-only value on the folded rail: short caption over the number, no box.
struct RailValue: View {
    var caption: String
    var value: String
    var title: String

    var body: some View {
        VStack(spacing: 3) {
            Text(caption)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .help(title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// Why a parameter cannot be changed right now. A session lock is temporary and
/// keeps the value fully readable; an inapplicable parameter is muted and says why.
enum ParameterAvailability: Equatable {
    case available
    /// Fixed until the running exercise or radiogram stops.
    case lockedForSession
    /// Not used by the current exercise or mode.
    case notApplicable(String)

    static let sessionLockReason = "Изменяется после остановки"

    var canChange: Bool { self == .available }
    var isApplicable: Bool {
        if case .notApplicable = self { return false }
        return true
    }

    var reason: String? {
        switch self {
        case .available: nil
        case .lockedForSession: Self.sessionLockReason
        case .notApplicable(let reason): reason
        }
    }
}

/// Uppercase caption + control, the unit of the parameter column. The caption
/// never fades the control: a session lock adds a small lock, an inapplicable
/// parameter mutes only the caption.
struct ParameterGroup<Content: View>: View {
    var title: String
    var note: String?
    var availability: ParameterAvailability = .available
    @ViewBuilder var content: Content

    @Environment(\.uiScale) private var uiScale

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Spacing.xxs) {
                Text(title.uppercased())
                    .font(.system(size: 10 * uiScale.controlScale, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(availability.isApplicable ? .secondary : .tertiary)
                Spacer(minLength: 0)
                if availability == .lockedForSession {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .help(ParameterAvailability.sessionLockReason)
                }
            }
            .accessibilityHidden(true)
            content
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// "− value +" stepper of the released client. Adjustable with VoiceOver,
/// focusable buttons, press-and-hold repeats. When the value cannot change only
/// the −/+ buttons go quiet; the number stays readable (secondary when the
/// parameter does not apply).
struct ValueStepper: View {
    var title: String
    var value: String
    var valueTint: Color = .accentColor
    var canDecrement: Bool
    var canIncrement: Bool
    var availability: ParameterAvailability = .available
    var onDecrement: () -> Void
    var onIncrement: () -> Void

    @Environment(\.uiScale) private var uiScale
    private var height: CGFloat { 30 * uiScale.controlScale }

    var body: some View {
        let canChange = availability.canChange
        HStack(spacing: 0) {
            stepButton("minus", label: "Меньше", enabled: canChange && canDecrement, action: onDecrement)
            Text(value)
                .font(.system(size: 13 * uiScale.controlScale, weight: .semibold).monospacedDigit())
                .foregroundStyle(availability.isApplicable ? valueTint : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            stepButton("plus", label: "Больше", enabled: canChange && canIncrement, action: onIncrement)
        }
        .frame(height: height)
        .glassEffect(canChange ? .regular.interactive() : .regular, in: .rect(cornerRadius: Radius.key))
        .help(availability.reason ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(availability.reason ?? "")
        .accessibilityAdjustableAction { direction in
            guard canChange else { return }
            switch direction {
            case .increment: if canIncrement { onIncrement() }
            case .decrement: if canDecrement { onDecrement() }
            @unknown default: break
            }
        }
        // Reported as unavailable to VoiceOver; the explicit colours above keep
        // the value from being dimmed with it.
        .disabled(!canChange)
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * uiScale.controlScale, weight: .semibold))
                .frame(width: 34 * uiScale.controlScale, height: height)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

extension ValueStepper {
    /// Integer value clamped to `range`, moved by `step`.
    init(
        _ title: String,
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        availability: ParameterAvailability = .available,
        valueTint: Color = .accentColor,
        format: @escaping (Int) -> String = { "\($0)" }
    ) {
        self.init(
            title: title,
            value: format(value.wrappedValue),
            valueTint: valueTint,
            canDecrement: value.wrappedValue - step >= range.lowerBound,
            canIncrement: value.wrappedValue + step <= range.upperBound,
            availability: availability,
            onDecrement: { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) },
            onIncrement: { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) })
    }

    /// Decimal value on a 0.5 grid (dash ratio, pause factor).
    init(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        availability: ParameterAvailability = .available,
        format: @escaping (Double) -> String
    ) {
        let current = value.wrappedValue
        self.init(
            title: title,
            value: format(current),
            canDecrement: current - step >= range.lowerBound - 0.001,
            canIncrement: current + step <= range.upperBound + 0.001,
            availability: availability,
            onDecrement: { value.wrappedValue = max(range.lowerBound, ((current - step) * 10).rounded() / 10) },
            onIncrement: { value.wrappedValue = min(range.upperBound, ((current + step) * 10).rounded() / 10) })
    }
}

/// Two or three choices as one glass control the size of a stepper; the
/// selected segment's tint glides between options. A session lock keeps the
/// choice readable (accent); an inapplicable control greys it.
struct GlassSegmented<Value: Hashable & Identifiable>: View {
    var title: String
    var options: [Value]
    var label: (Value) -> String
    @Binding var selection: Value
    var availability: ParameterAvailability = .available

    @Environment(\.uiScale) private var uiScale
    @Namespace private var segment

    private var height: CGFloat { 30 * uiScale.controlScale }

    var body: some View {
        let canChange = availability.canChange
        let applicable = availability.isApplicable
        HStack(spacing: 0) {
            ForEach(options) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(.system(size: 13 * uiScale.controlScale, weight: .semibold))
                        .foregroundStyle(selected ? (applicable ? Color.white : Color.primary)
                                         : (applicable ? Color.primary : Color.secondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: height - 6)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: Radius.key - 3)
                                    .fill(applicable ? Color.accentColor : Color.secondary.opacity(0.22))
                                    .matchedGeometryEffect(id: "selected", in: segment)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: height)
        .glassEffect(canChange ? .regular.interactive() : .regular, in: .rect(cornerRadius: Radius.key))
        .animation(.smooth(duration: 0.3), value: selection)
        .allowsHitTesting(canChange)
        .help(availability.reason ?? "")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(availability.reason ?? "")
    }
}

/// Full-width on/off button of the parameter column (ВЫБРАТЬ БУКВЫ, ЗНАКИ, РАДИОГРАММА).
struct OptionToggle: View {
    var title: String
    @Binding var isOn: Bool
    var isEnabled = true
    var help: String?

    @Environment(\.uiScale) private var uiScale

    /// One glass capsule whose accent tint flows in and out; a switched-on
    /// option locked for the session keeps its colour and just stops reacting.
    var body: some View {
        Button { if isEnabled { isOn.toggle() } } label: {
            Text(title.uppercased())
                .font(.system(size: 10 * uiScale.controlScale, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(isOn ? Color.white : (isEnabled ? Color.primary : Color.secondary))
                .frame(maxWidth: .infinity)
                .frame(height: 32 * uiScale.controlScale)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.accentColor).interactive()
                     : (isEnabled ? .regular.interactive() : .regular), in: .capsule)
        .animation(.smooth(duration: 0.35), value: isOn)
        .animation(.smooth(duration: 0.35), value: isEnabled)
        .allowsHitTesting(isEnabled)
        .accessibilityRespondsToUserInteraction(isEnabled)
        .help(help ?? "")
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "включено" : "выключено")
        .accessibilityHint(isEnabled ? "" : (help ?? ParameterAvailability.sessionLockReason))
    }
}

/// Start / Stop pinned to the bottom of the parameter column. One tinted glass
/// capsule that morphs with the column: full width with СТАРТ/СТОП when open,
/// a 44 pt circle (same capsule, equal sides) on the folded rail — the title
/// fades, the icon stays, nothing switches shape mid-animation.
struct StartStopButton: View {
    var isRunning: Bool
    var disabledReason: String?
    var action: () -> Void

    @Environment(\.parameterColumnCollapsed) private var isCompact

    private static let height: CGFloat = 44
    private var isEnabled: Bool { isRunning || disabledReason == nil }
    private var tint: Color { isRunning ? SignalPalette.stop : SignalPalette.start }

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Button(action: action) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                    if !isCompact {
                        Text(isRunning ? "СТОП" : "СТАРТ")
                            .font(.system(size: 14, weight: .heavy))
                            .tracking(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .frame(maxWidth: isCompact ? Self.height : .infinity)
                .frame(height: Self.height)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(isEnabled ? .regular.tint(tint).interactive() : .regular, in: .capsule)
            .animation(.smooth(duration: 0.35), value: isRunning)
            .animation(.smooth(duration: 0.35), value: isEnabled)
            .disabled(!isEnabled)
            .frame(maxWidth: .infinity)
            .help(isRunning ? "Остановить (⌘↩)" : (disabledReason ?? "Начать (⌘↩)"))
            .accessibilityLabel(isRunning ? "Стоп" : "Старт")
            .accessibilityHint(disabledReason ?? "")

            if !isRunning, !isCompact, let disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }
}
