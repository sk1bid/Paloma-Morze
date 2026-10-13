import SwiftUI

/// Reception in the released layout: parameter column on the left; on the right
/// the lesson header (prompt, active sign, mnemonic, progress) directly above the
/// sign cards (exercises 1–2) or the ЙЦУКЕН keyboard (3–4, custom selection).
struct ReceptionView: View {
    @Bindable var session: ReceptionSession
    var settings: SettingsStore

    @FocusState private var isFocused: Bool
    @State private var gridSize = CGSize(width: 700, height: 400)

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            ReceptionControls(session: session, settings: settings)

            VStack(spacing: Spacing.s) {
                LessonHeader(session: session, alphabet: settings.alphabet)

                if session.exercise.usesStudiedPool {
                    AnswerKeyboard(session: session, alphabet: settings.alphabet)
                        .transition(.opacity)
                } else {
                    Color.clear
                        .transition(.opacity)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                            var instant = Transaction()
                            instant.disablesAnimations = true
                            withTransaction(instant) { gridSize = size }
                        }
                        .overlay(alignment: .top) {
                            LetterGrid(session: session, alphabet: settings.alphabet,
                                       availableHeight: gridSize.height, availableWidth: gridSize.width)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Switching between cards and keyboard cross-fades.
            .animation(.smooth(duration: 0.35), value: session.exercise.usesStudiedPool)
        }
        // Column and work area move in one animation (toolbar, menu or ⌃⌘S).
        .animation(.smooth(duration: 0.4), value: settings.parametersCollapsed)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: handleKey)
        .onAppear { isFocused = true }
        .sheet(item: $session.results) { results in
            ReceptionResultsView(
                results: results,
                catalog: session.catalog,
                alphabet: settings.alphabet,
                overrides: settings.customOverrides,
                onRepeat: {
                    session.dismissResults()
                    session.start()
                },
                onClose: session.dismissResults)
        }
    }

    /// Typing a sign answers while waiting (Cyrillic layout, digits and / = ?).
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control]) else { return .ignored }
        let sign = press.characters.uppercased()
        guard !sign.isEmpty else { return .ignored }
        if session.status == .waitingForAnswer, session.answerPool.contains(sign) {
            session.answer(sign)
            return .handled
        }
        return .ignored
    }
}

enum LessonTitle {
    static func full(_ lesson: MorseLesson, catalog: MorseCatalog) -> String {
        "Урок \(lesson.id) — \(short(lesson, catalog: catalog))"
    }

    static func short(_ lesson: MorseLesson, catalog: MorseCatalog) -> String {
        if let title = lesson.title { return title }
        switch lesson.id {
        case MorseCatalog.digitsLessonID: return "Цифры"
        case MorseCatalog.signsLessonID: return "Знаки " + lesson.chars.joined(separator: " ")
        default: return lesson.chars.joined(separator: " ")
        }
    }
}

// MARK: - Lesson header

/// The released "lesson header": exercise prompt and hint, replaced by the
/// hovered / sounding sign with its pattern and mnemonic. Progress, status and
/// repeat sit in the same panel so question, answers and progress stay together.
struct LessonHeader: View {
    var session: ReceptionSession
    var alphabet: Alphabet

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiScale) private var uiScale
    /// Measured width of the counter / repeat badge, reserved on both sides of
    /// the centred text only while the badge is shown.
    @State private var badgeWidth: CGFloat = 0

    var body: some View {
        let inset = max(Spacing.m, badgeWidth)
        VStack(spacing: Spacing.xxs) {
            // As released: the title is the exercise prompt or the active sign, the
            // line under it the hint or the sign's mnemonic. A new title scales in
            // from 0.95 over 0.1 s, a new line fades in over 0.2 s; the old text
            // leaves at once.
            Group {
                if let sign = displayedSign {
                    Text(sign)
                        .font(.system(size: 30 * uiScale, weight: .bold))
                        .foregroundStyle(signColor)
                } else {
                    Text(prompt)
                        .font(.system(size: 17 * uiScale, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(promptColor)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .id(displayedSign ?? prompt)
            .transition(.asymmetric(
                insertion: reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity),
                removal: .identity))
            .animation(.easeOut(duration: 0.1), value: displayedSign ?? prompt)
            .frame(height: 38 * uiScale)
            .padding(.horizontal, inset)

            // Hints wrap to two lines; the height of two lines is always reserved
            // so the cards and keyboard below never move when the text changes.
            // A playback failure may take more lines and keeps its full text.
            Text(detail)
                .font(isFailure ? .callout : .system(size: 18 * uiScale, weight: .medium))
                .foregroundStyle(isFailure ? Color.orange : Color.primary.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(isFailure ? 4 : 2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .help(detail)
                .id(detail)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .animation(.easeOut(duration: 0.2), value: detail)
                .frame(maxWidth: .infinity, minHeight: twoLineHeight * uiScale, alignment: .top)
                .padding(.horizontal, inset)

            progressBar
                .frame(height: 6)
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.xs)
        }
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xs)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            progressBadge
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { badgeWidth = $0 }
        }
        .contentSurface()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Content

    @ScaledMetric(relativeTo: .title3) private var twoLineHeight: CGFloat = 52

    private var isFailure: Bool {
        if case .failed = session.status { return true }
        return false
    }

    /// The sounding sign, else the hovered one (hints stay available during
    /// exercises 1–3, as released); never during the control work, and the
    /// answer feedback briefly takes precedence over a hover.
    private var displayedSign: String? {
        if let active = session.activeSign { return active }
        if session.exercise == .exam, session.isSessionActive { return nil }
        if case .feedback = session.status { return nil }
        return session.hoveredSign
    }

    private var signColor: Color {
        switch session.status {
        case .repeatingError: SignalPalette.wrong
        default: session.activeSign != nil ? .accentColor : .primary
        }
    }

    private var prompt: String {
        switch session.status {
        case .feedback(let correct): return correct ? "Верно" : "Неверно"
        case .cancelling: return "Остановка…"
        case .completed: return "Упражнение завершено"
        case .failed: return "Воспроизведение прервано"
        default: break
        }
        if session.customSelection, session.exercise.usesStudiedPool, !session.isSessionActive {
            return "Выберите знаки для набора"
        }
        switch session.exercise {
        case .learn: return "НОВЫЕ ЗНАКИ"
        case .recognize, .groups: return "Нажимайте знаки, которые вы слышали!"
        case .exam: return "ТЕКСТ КОНТРОЛЬНОЙ"
        }
    }

    private var promptColor: Color {
        switch session.status {
        case .feedback(let correct): correct ? SignalPalette.correct : SignalPalette.wrong
        case .failed: .orange
        default: .primary
        }
    }

    /// The sign's mnemonic (or Q-code meaning), as released; no instructions.
    /// Only a playback failure puts its reason here, in full.
    private var detail: String {
        if let sign = displayedSign {
            return session.mnemonic(for: sign, alphabet: alphabet)
        }
        if case .failed(let reason) = session.status { return reason }
        return ""
    }

    // MARK: Progress

    private var showsProgress: Bool {
        (session.isSessionActive || session.status == .completed) && session.progress.total > 0
    }

    @ViewBuilder
    private var progressBadge: some View {
        HStack(spacing: Spacing.xs) {
            if session.exercise.isInteractive, session.isSessionActive {
                Button("Повторить знак", systemImage: "arrow.counterclockwise") {
                    session.repeatCurrent()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!session.canRepeat)
                .help("Повторить знак (⌘R)")
            }
            if showsProgress {
                Text("\(session.progress.completed) / \(session.progress.total)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Пройдено \(session.progress.completed) из \(session.progress.total)")
            }
        }
        .padding(hasBadge ? Spacing.s : 0)
    }

    private var hasBadge: Bool {
        showsProgress || (session.exercise.isInteractive && session.isSessionActive)
    }

    @ViewBuilder
    private var progressBar: some View {
        // Always laid out (hidden when idle): the header keeps one height, so
        // starting an exercise does not shrink the cards or keyboard below.
        ProgressView(value: Double(session.progress.completed), total: Double(max(session.progress.total, 1)))
            .progressViewStyle(.linear)
            .controlSize(.small)
            .opacity(showsProgress ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: showsProgress)
            .accessibilityHidden(true)
    }
}

// MARK: - Lesson signs (exercises 1–2)

struct LetterGrid: View {
    var session: ReceptionSession
    var alphabet: Alphabet
    /// Space left under the lesson header; cards grow into it up to a limit.
    var availableHeight: CGFloat
    var availableWidth: CGFloat

    @Environment(\.uiScale) private var uiScale
    @State private var lit: String?

    var body: some View {
        let signs = session.lessonSigns
        let columns = Self.columns(for: signs.count, qCodes: session.isQCodeLesson)
        let rows = max(1, Int((Double(signs.count) / Double(columns)).rounded(.up)))
        // Released sizes: 120 pt cards, 100 pt for Щ-codes; shrink only when the window is short.
        let preferred: CGFloat = (session.isQCodeLesson ? 100 : 120) * uiScale
        // Cards fill the free height in big windows, at most 4 : 3 of their width.
        let gridWidth = min(availableWidth, CGFloat(columns) * 230 * uiScale)
        let cardWidth = (gridWidth - CGFloat(columns - 1) * Spacing.m) / CGFloat(columns)
        let fitted = (availableHeight - CGFloat(rows - 1) * Spacing.m) / CGFloat(rows)
        let height = max(72, min(max(preferred, cardWidth * 0.75), fitted).rounded(.down))

        GlassEffectContainer(spacing: 0) {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.m), count: columns),
            spacing: Spacing.m
        ) {
            ForEach(signs, id: \.self) { sign in
                LetterCard(
                    sign: sign,
                    state: state(for: sign),
                    height: height,
                    isEnabled: isEnabled,
                    accessibilityDetail: session.mnemonic(for: sign, alphabet: alphabet)
                ) {
                    session.tap(sign)
                }
                .onHover { inside in
                    if inside { session.hoveredSign = sign } else if session.hoveredSign == sign { session.hoveredSign = nil }
                }
            }
        }
        }
        // A short lesson keeps card proportions instead of stretching across the window.
        .frame(maxWidth: CGFloat(columns) * 230 * uiScale)
        .padding(.top, 2)
        // The highlight lights and fades in place (no glide between cards).
        .modifier(SoundingHold(active: session.activeSign, lit: $lit))
        .animation(.smooth(duration: 0.4), value: signs)
    }

    static func columns(for count: Int, qCodes: Bool) -> Int {
        if count <= 4 { return max(count, 1) }
        return qCodes ? 4 : 5
    }

    private var isEnabled: Bool {
        switch session.status {
        case .waitingForAnswer, .idle, .completed, .failed: true
        default: false
        }
    }

    private func state(for sign: String) -> SignTileState {
        if session.chosenSign == sign, case .feedback(let correct) = session.status {
            return correct ? .correct : .wrong
        }
        if lit == sign { return .sounding(.none) }
        if session.status == .waitingForAnswer { return .awaitingAnswer }
        if lit != nil || (session.isSessionActive && session.exercise == .learn) { return .dimmed }
        if session.hoveredSign == sign, isEnabled { return .awaitingAnswer }
        return .normal
    }
}

// MARK: - Answer keyboard (exercises 3–4, custom selection)

struct AnswerKeyboard: View {
    var session: ReceptionSession
    var alphabet: Alphabet

    @State private var available = CGSize(width: 640, height: 360)
    @State private var lit: String?
    /// Keys shown as part of the pool. Follows the real pool with a stagger, so
    /// stepping through lessons fills the keyboard key by key.
    @State private var shownPool: Set<String> = []
    @State private var hasShownPool = false
    @State private var fillTask: Task<Void, Never>?

    /// ЙЦУКЕН layout of the released client, plus digits and signs.
    static let rows: [[String]] = [
        ["Й", "Ц", "У", "К", "Е", "Н", "Г", "Ш", "Щ", "З", "Х"],
        ["Ф", "Ы", "В", "А", "П", "Р", "О", "Л", "Д", "Ж", "Э"],
        ["Я", "Ч", "С", "М", "И", "Т", "Ь", "Б", "Ю"],
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "/", "=", "?"],
    ]

    private var spacing: CGFloat { (keySize * 0.16).rounded() }

    /// 13 keys in the widest row and four rows (keys are 1.2 × as tall as wide)
    /// fill the panel: 44 pt at 1000 × 700 like the released 44 × 54 keys,
    /// growing with the window up to 96 pt, never below 30.
    private var keySize: CGFloat {
        let byWidth = (available.width - Spacing.l * 2) / (13 + 12 * 0.16)
        let byHeight = (available.height - Spacing.l * 2) / (4 * 1.2 + 3 * 0.16)
        return min(96, max(30, min(byWidth, byHeight).rounded(.down)))
    }

    var body: some View {
        // No GlassEffectContainer: each key keeps its own glass, so a muted key
        // can simply be translucent (opacity is not applied to glass inside a
        // container) and never switches material.
        VStack(spacing: spacing) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { sign in
                        AnswerKey(
                            sign: sign,
                            size: keySize,
                            state: state(for: sign),
                            isEligible: isEligible(sign),
                            isEnabled: isEnabled(sign)
                        ) {
                            session.tap(sign)
                        }
                        .help(session.mnemonic(for: sign, alphabet: alphabet))
                        .onHover { inside in
                            if inside { session.hoveredSign = sign } else if session.hoveredSign == sign { session.hoveredSign = nil }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Resizing follows the panel at once; it must not ride along with a
        // state animation (keys would slide when an exercise starts or appears).
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { available = size }
        }
        // No shared lens on the keyboard: on small keys a glow travelling across
        // the layout looks odd, so each key lights and fades in place.
        .modifier(SoundingHold(active: session.activeSign, lit: $lit))
        .onChange(of: targetPool, initial: true) { _, target in fill(to: target) }
        .onDisappear { fillTask?.cancel() }
        .overlay(alignment: .topTrailing) {
            if isCustomEditing, !session.customPool.isEmpty {
                Button("Очистить выбор") { session.customPool.removeAll() }
                    .buttonStyle(.borderless)
                    .padding(Spacing.s)
            }
        }
        .contentSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isExamRunning ? "Клавиатура отключена: ответы записываются на бумаге" : "Клавиатура ответов")
    }

    private var isExamRunning: Bool { session.exercise == .exam && session.isSessionActive }

    private var isCustomEditing: Bool {
        session.customSelection && !session.isSessionActive
    }

    private func isEligible(_ sign: String) -> Bool {
        shownPool.contains(sign)
    }

    private var targetPool: Set<String> {
        isCustomEditing ? Set(Self.rows.joined()) : Set(session.studiedPool)
    }

    /// Removed keys fade together; added keys appear one after another in the
    /// order they are studied. A new change cancels the rest and continues from
    /// what is already shown.
    private func fill(to target: Set<String>) {
        fillTask?.cancel()
        guard hasShownPool else {
            shownPool = target
            hasShownPool = true
            return
        }
        let removed = shownPool.subtracting(target)
        if !removed.isEmpty {
            withAnimation(.smooth(duration: 0.3)) { shownPool.subtract(removed) }
        }
        let order = isCustomEditing ? Array(Self.rows.joined()) : session.studiedPool
        let added = order.filter { target.contains($0) && !shownPool.contains($0) }
        guard !added.isEmpty else { return }
        fillTask = Task { @MainActor in
            for sign in added {
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.35)) { _ = shownPool.insert(sign) }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func isEnabled(_ sign: String) -> Bool {
        if isCustomEditing { return true }
        if isExamRunning { return false }
        if session.isSessionActive { return session.status == .waitingForAnswer && session.studiedPool.contains(sign) }
        // Outside a session every key plays its sign, as released.
        return true
    }

    private func state(for sign: String) -> SignTileState {
        if session.chosenSign == sign, case .feedback(let correct) = session.status {
            return correct ? .correct : .wrong
        }
        if lit == sign { return .sounding(.none) }
        if isExamRunning { return .dimmed }
        if isCustomEditing, session.customPool.contains(sign) { return .selected }
        if session.status == .waitingForAnswer, session.studiedPool.contains(sign) { return .awaitingAnswer }
        return .normal
    }
}
