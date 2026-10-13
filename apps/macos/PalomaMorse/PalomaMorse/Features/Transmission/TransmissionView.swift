import SwiftUI

/// Transmission in the released layout: РАДИОГРАММА, ТИП СИМВОЛОВ, ГРУПП and
/// Start/Stop on the left; the rhythm tape, the decoded text or radiogram and
/// the legend with Очистить on the right.
struct TransmissionView: View {
    @Bindable var session: TransmissionSession
    var settings: SettingsStore

    @FocusState private var isFocused: Bool
    @Environment(\.uiScale) private var uiScale
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            TransmissionControls(session: session, settings: settings)

            VStack(spacing: Spacing.s) {
                RhythmTape(rhythm: session.rhythm, label: nil)
                    .frame(height: 104 * uiScale)

                // As released, the panel sits right under the tape and hugs its
                // content; the rest of the height stays plain background.
                Group {
                    switch session.mode {
                    case .free: DecodedTextPanel(session: session).frame(height: 300 * uiScale)
                    case .radiogram: RadiogramPanel(session: session)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                TransmissionFooter(session: session)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Column and work area move in one animation (toolbar, menu or ⌃⌘S).
        .animation(.smooth(duration: 0.4), value: settings.parametersCollapsed)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onDisappear { session.releaseKey() }
        .onChange(of: controlActiveState) { _, state in
            if state != .key { session.releaseKey() }
        }
        .sheet(item: $session.report) { report in
            RadiogramReportView(report: report, onRetry: session.retryRadiogram) {
                session.report = nil
            }
        }
    }
}

// MARK: - Parameter column

struct TransmissionControls: View {
    @Bindable var session: TransmissionSession
    var settings: SettingsStore

    var body: some View {
        let running = session.isRadiogramRunning
        let radiogram = session.mode == .radiogram

        ParameterColumn(isCollapsed: settings.parametersCollapsed) {
            OptionToggle(
                title: "Радиограмма",
                isOn: radiogramBinding,
                isEnabled: !running,
                help: running ? "Остановите радиограмму, чтобы сменить режим" : "Передача учебной радиограммы с проверкой")

            let radiogramParameter: ParameterAvailability = !radiogram
                ? .notApplicable("Доступно в режиме радиограммы")
                : running ? .lockedForSession : .available
            ParameterGroup(title: "Тип символов", availability: radiogramParameter) {
                GlassSegmented(
                    title: "Тип символов",
                    options: RadiogramCharset.allCases,
                    label: \.title,
                    selection: $session.charset,
                    availability: radiogramParameter)
            }

            ParameterGroup(title: "Групп", availability: radiogramParameter) {
                ValueStepper(
                    "Групп по 5 знаков",
                    value: $session.groupCount,
                    in: 5...100,
                    step: 5,
                    availability: radiogramParameter)
            }
        } rail: {
            RailToggle(title: "Радиограмма", systemImage: "list.bullet.rectangle",
                       isOn: radiogramBinding, isEnabled: !running)
            if radiogram {
                RailValue(caption: "ГРУПП", value: "\(session.groupCount)", title: "Групп по 5 знаков")
            }
        } footer: {
            if radiogram {
                StartStopButton(isRunning: running, disabledReason: nil, action: session.toggleRadiogram)
            }
        }
    }

    private var radiogramBinding: Binding<Bool> {
        Binding(
            get: { session.mode == .radiogram },
            set: { session.mode = $0 ? .radiogram : .free })
    }
}

// MARK: - Free keying

struct DecodedTextPanel: View {
    var session: TransmissionSession

    @Environment(\.uiScale) private var uiScale

    @State private var textViewport: CGFloat = 200
    @State private var textHeight: CGFloat = 0
    @Namespace private var glass

    private var overflows: Bool { textHeight > textViewport + 1 }

    var body: some View {
        VStack(spacing: Spacing.s) {
            hintLine

            // Short text sits in the middle of the panel, as released. Once it no
            // longer fits, the newest line stays at the bottom and older lines
            // move up and fade out under the chip; nothing is cut mid-line.
            // The reader fixes the frame: the text can never resize the panel.
            GeometryReader { proxy in
                text
                    .font(.system(size: 52 * uiScale, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.l)
                    .frame(width: proxy.size.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                    .frame(width: proxy.size.width, height: proxy.size.height,
                           alignment: overflows ? .bottom : .center)
                    .onAppear { textViewport = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in textViewport = height }
            }
            .clipped()
            .mask {
                LinearGradient(
                    stops: [.init(color: overflows ? .clear : .black, location: 0),
                            .init(color: .black, location: overflows ? 0.35 : 0)],
                    startPoint: .top, endPoint: .bottom)
            }
            .animation(.smooth(duration: 0.3), value: session.decodedText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Принятый текст")
                .accessibilityValue(session.decodedText.isEmpty ? "пусто" : session.decodedText)
        }
        .padding(.vertical, Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentSurface()
    }

    /// What the chip shows. It keeps the last sign (pattern and mnemonic) after
    /// the session clears its buffer, so the chip does not empty out between signs.
    @State private var chipPattern = ""
    @State private var chipHint = ""
    @State private var chipVisible = false
    @State private var hideTask: Task<Void, Never>?

    /// The sign being keyed — pattern and its mnemonic or Q-code meaning — on a
    /// glass chip. The slot keeps its height whether or not the chip is shown,
    /// so the text below never moves. When keying stops the chip stays for a
    /// moment and then dissolves slowly; a new press interrupts that at once.
    /// While keying, its glass flows to the new width.
    private var hintLine: some View {
        GlassEffectContainer {
            if chipVisible {
                HStack(spacing: Spacing.s * uiScale) {
                    if !chipPattern.isEmpty {
                        MorsePatternView(patterns: [chipPattern], unit: 9 * uiScale, tint: .accentColor)
                            .transition(.opacity)
                    }
                    if !chipHint.isEmpty {
                        Text(chipHint)
                            .font(.system(size: 18 * uiScale, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineLimit(1)
                            .contentTransition(.opacity)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, Spacing.m * uiScale)
                .frame(height: 40 * uiScale)
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("hint", in: glass)
                .glassEffectTransition(.materialize)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44 * uiScale)
        .animation(.smooth(duration: 0.3), value: chipPattern)
        .animation(.smooth(duration: 0.4), value: chipHint)
        .onChange(of: session.buffer, initial: true) { _, buffer in
            guard !buffer.isEmpty else { return }
            show { chipPattern = buffer }
        }
        .onChange(of: session.hint, initial: true) { _, hint in
            if !hint.isEmpty {
                show { chipHint = hint }
            } else if session.buffer.isEmpty {
                scheduleHide()
            }
        }
        .onDisappear { hideTask?.cancel() }
    }

    private func show(_ update: () -> Void) {
        hideTask?.cancel()
        hideTask = nil
        update()
        if !chipVisible {
            withAnimation(.smooth(duration: 0.35)) { chipVisible = true }
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) { chipVisible = false }
        }
    }

    private var text: Text {
        let caret = Text("_").foregroundStyle(.tint)
        if session.decodedText.isEmpty, session.previewCharacter.isEmpty {
            let key = Text(session.transmissionKeyLabel).foregroundStyle(.tint)
            return Text("\(Text("Нажмите").foregroundStyle(.secondary)) \(key)\(caret)")
        }
        let preview = Text(session.previewCharacter).foregroundStyle(.tint)
        return Text("\(session.decodedText)\(preview)\(caret)")
    }
}

// MARK: - Radiogram

struct RadiogramPanel: View {
    var session: TransmissionSession

    @Environment(\.uiScale) private var uiScale

    var body: some View {
        Group {
            if let run = session.radiogram {
                running(run)
            } else {
                VStack(spacing: Spacing.xs) {
                    Text("Нажмите «Старт» для начала")
                        .font(.system(size: 22 * uiScale, weight: .semibold))
                    Text("\(session.groupCount) групп по 5 \(session.charset == .digits ? "цифр" : "букв")")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Spacing.xl * 2)
                .frame(maxWidth: .infinity)
            }
        }
        .contentSurface()
    }

    @State private var width: CGFloat = 700

    /// As released: a stats header (ПОРЦИЯ · ВРЕМЯ · ОШИБКИ), the current
    /// portion as five group cells, a thin progress line. Keyed signs glow green,
    /// a wrong sign glows red, the next one is bright with a blinking accent bar.
    private func running(_ run: RadiogramRun) -> some View {
        let portion = run.portion
        let groups = stride(from: 0, to: portion.count, by: 5).map { Array(portion.indices[$0..<min($0 + 5, portion.count)]) }
        let cellWidth = (width - Spacing.l * 2 - Spacing.s * 4) / 5
        // Five heavy signs (Ш/Щ are the widest, ≈ 0.95 em) plus gaps and padding fit the cell.
        let size = min(30 * uiScale, max(14, (cellWidth - 28) / 4.75))

        return VStack(spacing: Spacing.l) {
            GlassEffectContainer(spacing: Spacing.s) {
                VStack(spacing: Spacing.l) {
                    // `justify-content: space-around` of the released header.
                    HStack(spacing: 0) {
                        stat("Порция", "\(run.portionIndex + 1) / \(run.portionCount)", tint: .accentColor)
                        TimelineView(.periodic(from: run.startedAt, by: 1)) { context in
                            stat("Время", Duration.clock(context.date.timeIntervalSince(run.startedAt)), tint: .accentColor)
                        }
                        stat("Ошибки", "\(run.errors)", tint: run.errors == 0 ? SignalPalette.correct : SignalPalette.wrong)
                    }
                    .padding(.vertical, Spacing.s)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))

                    HStack(spacing: Spacing.s) {
                        ForEach(groups, id: \.self) { group in
                            HStack(spacing: 2) {
                                ForEach(group, id: \.self) { index in
                                    RadiogramSign(sign: portion[index], state: state(index, run: run),
                                                  isTarget: index == run.targetIndex, size: size)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity)
                            .glassEffect(.clear, in: .rect(cornerRadius: 10))
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Текст радиограммы")
            .accessibilityValue("Следующий знак: \(run.targetIndex < portion.count ? portion[run.targetIndex] : "")")

            ProgressView(value: Double(run.completed), total: Double(max(run.sequence.count, 1)))
                .progressViewStyle(.linear)
                .controlSize(.small)
                .accessibilityLabel("Передано \(run.completed) из \(run.sequence.count)")
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func stat(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10 * uiScale, weight: .heavy))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 19 * uiScale, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func state(_ index: Int, run: RadiogramRun) -> RadiogramSign.State {
        if index < run.targetIndex { return run.marks[index] == false ? .wrong : .correct }
        if index == run.targetIndex { return run.marks[index] == false ? .wrong : .current }
        return .pending
    }
}

/// One sign of the radiogram text with the released glow and cursor.
struct RadiogramSign: View {
    enum State { case pending, current, correct, wrong }

    var sign: String
    var state: State
    var isTarget: Bool
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(sign)
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(color)
            .overlay(alignment: .bottom) {
                if isTarget {
                    cursor.offset(y: 5)
                }
            }
            .animation(.easeOut(duration: 0.15), value: state)
    }

    @ViewBuilder
    private var cursor: some View {
        let bar = Capsule().fill(Color.accentColor).frame(height: 3)
            .shadow(color: .accentColor, radius: 4)
        if reduceMotion {
            bar
        } else {
            bar.phaseAnimator([1.0, 0.0]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.5) }
        }
    }

    /// Muted colours: the text stays the subject, the state is a quiet tint.
    private var color: Color {
        switch state {
        case .pending: .primary.opacity(0.22)
        case .current: .primary
        case .correct: SignalPalette.correct.mix(with: .gray, by: 0.35).opacity(0.85)
        case .wrong: SignalPalette.wrong.mix(with: .gray, by: 0.25).opacity(0.9)
        }
    }
}

// MARK: - Footer

/// Legend of the tape, then the on-screen key and Очистить, as released.
struct TransmissionFooter: View {
    var session: TransmissionSession

    var body: some View {
        HStack(spacing: Spacing.s) {
            RhythmLegend()
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
                .contentSurface(radius: 12)

            Spacer(minLength: Spacing.s)

            HoldToKeyButton(isDown: session.isKeyDown, isPaused: session.isPaused, keyLabel: session.transmissionKeyLabel) {
                session.keyDown(from: .pointer)
            } onRelease: {
                session.keyUp(from: .pointer)
            }

            if session.mode == .free {
                Button("Очистить", action: session.clear)
                    .buttonStyle(.glass)
                    .disabled(session.decodedText.isEmpty && session.rhythm.marks.isEmpty)
                    .help("Очистить (⌘K)")
            }
        }
        .controlSize(.large)
    }
}

/// On-screen key for pointer keying: press and hold like a straight key.
struct HoldToKeyButton: View {
    var isDown: Bool
    var isPaused: Bool
    var keyLabel = "Пробел"
    var onPress: () -> Void
    var onRelease: () -> Void

    var body: some View {
        Label("Ключ", systemImage: "hand.tap.fill")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, Spacing.m)
            .frame(height: 32)
            .foregroundStyle(isDown ? Color.white : Color.primary)
            .glassEffect(isDown ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
            .contentShape(.capsule)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isDown { onPress() } }
                    .onEnded { _ in onRelease() })
            .opacity(isPaused ? 0.5 : 1)
            .allowsHitTesting(!isPaused)
            .help("Удерживайте, чтобы передавать. Клавиша \(keyLabel) работает так же.")
            .accessibilityElement()
            .accessibilityLabel("Ключ")
            .accessibilityValue(isDown ? "нажат" : "отпущен")
            .accessibilityHint("Для передачи удерживайте \(keyLabel)")
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Report

/// "Результаты передачи" of the released client.
struct RadiogramReportView: View {
    var report: RadiogramReport
    var onRetry: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            Text("Результаты передачи")
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.s) {
                row("Всего символов", "\(report.total)")
                Divider()
                row("Затраченное время", Duration.clock(report.elapsed))
                Divider()
                row("Количество ошибок", "\(report.errors)",
                    tint: report.errors == 0 ? SignalPalette.correct : SignalPalette.wrong)
                Divider()
                row("Точность", "\(report.accuracy) %", tint: .accentColor)
                Divider()
                row("Скорость передачи", speed)
            }

            HStack {
                Button("Повторить", systemImage: "arrow.counterclockwise", action: onRetry)
                Spacer()
                Button("Закрыть", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.l)
        .frame(width: 400)
    }

    private func row(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .gridColumnAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var speed: String {
        guard let cpm = report.charactersPerMinute else { return "—" }
        return "\(cpm) зн/мин (\(Int((Double(cpm) / 5).rounded())) WPM)"
    }
}
