import Foundation
import Observation

enum ReceptionExercise: Int, CaseIterable, Identifiable {
    /// 1 — each lesson sign five times; the playing sign is highlighted.
    case learn = 1
    /// 2 — 15 random lesson signs, answered one by one on the sign grid.
    case recognize
    /// 3 — groups × 5 signs from all studied lessons, answered on the keyboard.
    case groups
    /// 4 — paper-based control work: continuous groups, text revealed at the end.
    case exam

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .learn: "Знакомство"
        case .recognize: "Узнавание"
        case .groups: "Группы"
        case .exam: "Контрольная"
        }
    }

    var summary: String {
        switch self {
        case .learn: "Каждый знак урока звучит пять раз подряд"
        case .recognize: "Услышали знак — выберите его на карточках"
        case .groups: "Знаки всех пройденных уроков, ответ с клавиатуры"
        case .exam: "Записывайте на бумаге, текст откроется в конце"
        }
    }

    var systemImage: String {
        switch self {
        case .learn: "book"
        case .recognize: "ear"
        case .groups: "square.grid.3x3"
        case .exam: "doc.text"
        }
    }

    /// Exercises 3 and 4 draw from every studied lesson and support custom selection.
    var usesStudiedPool: Bool { self == .groups || self == .exam }
    var isInteractive: Bool { self == .recognize || self == .groups }
}

enum ReceptionStatus: Equatable {
    case idle
    case playing
    case waitingForAnswer
    case feedback(correct: Bool)
    case repeatingError
    case cancelling
    case completed
    case failed(String)
}

struct ReceptionResults: Equatable, Identifiable {
    let id = UUID()
    var exercise: ReceptionExercise
    var lessonID: Int
    var total: Int
    /// Distinct signs answered wrong, in order of first mistake.
    var errors: [String]
    /// Every wrong answer, for accuracy.
    var wrongAnswers: Int
    /// Groups of the control work in playback order (exercise 4 only).
    var radiogramGroups: [String]
    var duration: TimeInterval
}

/// Reception training state (UI-SERVICE "Training presentation state").
/// Progress follows engine events; this model never times audible elements.
@Observable
final class ReceptionSession {
    let catalog: MorseCatalog
    @ObservationIgnored private let audio: AudioCoordinator
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let history: HistoryStore

    // MARK: Selection

    var lessonIndex = 0 {
        didSet {
            if isQCodeLesson, !availableExercises.contains(exercise) {
                exercise = .recognize
            }
        }
    }

    var exercise: ReceptionExercise = .learn {
        didSet {
            if !exercise.usesStudiedPool { customSelection = false }
        }
    }

    var groupCount = 5
    var includeSigns = false
    var customSelection = false
    var customPool: [String] = []
    /// Sign under the pointer; shows its mnemonic in the header.
    var hoveredSign: String?
    var results: ReceptionResults?

    // MARK: Playback state

    private(set) var status: ReceptionStatus = .idle
    private(set) var sequence: [String] = []
    /// Answered targets (exercises 2–3).
    private(set) var step = 0
    /// Tokens reported by the engine (exercises 1 and 4).
    private(set) var playedTokens = 0
    private(set) var activeSign: String?
    private(set) var pulse: Pulse = .none
    private(set) var chosenSign: String?
    private(set) var errors: [String] = []
    private(set) var wrongAnswers = 0

    @ObservationIgnored private var requestID: PlaybackRequestID?
    @ObservationIgnored private var previewID: PlaybackRequestID?
    @ObservationIgnored private var pendingStep: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date()

    static let groupSize = 5
    static let groupCountRange = 5...100
    static let recognizeCount = 15
    static let repeatCount = 5

    init(catalog: MorseCatalog, audio: AudioCoordinator, settings: SettingsStore, history: HistoryStore) {
        self.catalog = catalog
        self.audio = audio
        self.settings = settings
        self.history = history
    }

    // MARK: Derived

    func patterns(for sign: String) -> [String] { catalog.patterns(for: sign, overrides: settings.customOverrides) }
    func mnemonic(for sign: String, alphabet: Alphabet) -> String { catalog.mnemonic(for: sign, alphabet: alphabet, overrides: settings.customOverrides) }

    var lessons: [MorseLesson] { catalog.lessons }
    var lesson: MorseLesson { lessons[lessonIndex] }
    var isQCodeLesson: Bool { catalog.isQCodeLesson(lesson) }
    var lessonSigns: [String] { lesson.chars }

    var availableExercises: [ReceptionExercise] {
        isQCodeLesson ? [.learn, .recognize] : ReceptionExercise.allCases
    }

    var isSessionActive: Bool {
        switch status {
        case .playing, .waitingForAnswer, .feedback, .repeatingError, .cancelling: true
        default: false
        }
    }

    var signs: [String] { catalog.signsLesson?.chars ?? [] }

    /// Pool for exercises 3–4: letters up to the current lesson, or the digits /
    /// signs lesson alone, or the custom selection; signs can be mixed in.
    var studiedPool: [String] {
        var pool: [String]
        if customSelection {
            pool = customPool
        } else if lesson.id == MorseCatalog.digitsLessonID || lesson.id == MorseCatalog.signsLessonID {
            pool = lesson.chars
        } else {
            let start = isQCodeLesson
                ? lessons.firstIndex { catalog.isQCodeLesson($0) } ?? lessonIndex
                : 0
            pool = lessons[start...lessonIndex].flatMap(\.chars)
        }
        if !customSelection {
            if includeSigns, !isQCodeLesson, lessonIndex < 8 { pool += signs }
            var seen = Set<String>()
            pool = pool.filter { seen.insert($0).inserted }
        }
        if includeSigns { pool += signs }
        return pool
    }

    /// Signs that count as a valid answer in the current exercise.
    var answerPool: [String] {
        exercise.usesStudiedPool ? studiedPool : lessonSigns
    }

    var currentTarget: String? {
        guard exercise.isInteractive, sequence.indices.contains(step) else { return nil }
        return sequence[step]
    }

    var progress: (completed: Int, total: Int) {
        if exercise.isInteractive {
            return (min(step, sequence.count), sequence.count)
        }
        let isSign: (String) -> Bool = { $0 != SequenceGenerator.groupGap }
        return (sequence.prefix(playedTokens).filter(isSign).count, sequence.filter(isSign).count)
    }

    var startBlockReason: String? {
        if let reason = audio.unavailableReason { return reason }
        if exercise.usesStudiedPool, studiedPool.isEmpty { return "Выберите хотя бы один знак" }
        return nil
    }

    var adapterKind: AudioAdapterKind { audio.adapterKind }

    /// Locks selection controls while a session runs.
    var isConfigurationLocked: Bool { isSessionActive }

    // MARK: Actions

    func toggleRun() {
        isSessionActive ? stop() : start()
    }

    func start() {
        guard !isSessionActive, startBlockReason == nil else { return }
        cancelPreview()
        errors = []
        wrongAnswers = 0
        results = nil
        step = 0
        playedTokens = 0
        chosenSign = nil
        activeSign = nil
        startedAt = .now

        switch exercise {
        case .learn:
            sequence = lessonSigns.flatMap { Array(repeating: $0, count: Self.repeatCount) + [SequenceGenerator.groupGap] }
            playContinuous(spacing: .lessonOne)
        case .exam:
            sequence = SequenceGenerator.generate(
                pool: studiedPool, count: groupCount * Self.groupSize, groupSize: Self.groupSize, groupGaps: true)
            playContinuous(spacing: .text)
        case .recognize, .groups:
            let pool = exercise == .recognize ? lessonSigns : studiedPool
            let count = exercise == .groups ? groupCount * Self.groupSize : Self.recognizeCount
            sequence = SequenceGenerator.generate(pool: pool, count: count, groupSize: Self.groupSize, groupGaps: false)
            playTarget()
        }
    }

    func stop() {
        pendingStep?.cancel()
        pendingStep = nil
        if let requestID {
            status = .cancelling
            audio.cancel(requestID)
        } else {
            resetToIdle()
        }
    }

    /// Grid / keyboard tap: answer, custom selection or listening preview.
    func tap(_ sign: String) {
        if customSelection, !isSessionActive, previewID != nil { return }
        if isSessionActive {
            if status == .waitingForAnswer { answer(sign) }
            return
        }
        if customSelection, exercise.usesStudiedPool {
            toggleCustom(sign)
        }
        preview(sign)
    }

    func answer(_ sign: String) {
        guard status == .waitingForAnswer, let target = currentTarget, answerPool.contains(sign) else { return }
        chosenSign = sign
        if sign == target {
            status = .feedback(correct: true)
            schedule(after: .milliseconds(600)) { $0.advance() }
        } else {
            status = .feedback(correct: false)
            wrongAnswers += 1
            if !errors.contains(target) { errors.append(target) }
            schedule(after: .seconds(1)) { $0.repeatError(target) }
        }
    }

    /// Plays the current target again while waiting for an answer.
    func repeatCurrent() {
        guard status == .waitingForAnswer, let target = currentTarget else { return }
        playTarget(target)
    }

    var canRepeat: Bool { status == .waitingForAnswer }

    func toggleCustom(_ sign: String) {
        if let index = customPool.firstIndex(of: sign) {
            customPool.remove(at: index)
        } else {
            customPool.append(sign)
        }
    }

    func preview(_ sign: String) {
        guard !isSessionActive else { return }
        cancelPreview()
        let token = token(for: sign)
        previewID = audio.play([token], spacing: .text) { [weak self] id, event in
            guard let self, previewID == id else { return }
            switch event {
            case .started: activeSign = sign
            case .pulse(let value): pulse = value
            case .finished, .failed:
                previewID = nil
                activeSign = nil
                pulse = .none
            case .token: break
            }
        }
    }

    func dismissResults() {
        results = nil
        if status == .completed { status = .idle }
    }

    // MARK: Engine-driven flow

    private func playContinuous(spacing: SpacingMode) {
        status = .playing
        requestID = audio.play(sequence.map(token(for:)), spacing: spacing) { [weak self] id, event in
            guard let self, requestID == id else { return }
            switch event {
            case .started: break
            case .token(let index):
                playedTokens = index + 1
                if exercise == .learn, sequence.indices.contains(index) {
                    let sign = sequence[index]
                    activeSign = sign == SequenceGenerator.groupGap ? nil : sign
                }
            case .pulse(let value):
                pulse = exercise == .learn ? value : .none
            case .finished(let cancelled):
                requestID = nil
                cancelled ? resetToIdle() : complete()
            case .failed(let reason):
                requestID = nil
                fail(reason)
            }
        }
        if requestID == nil { fail(audio.unavailableReason ?? "Не удалось начать воспроизведение") }
    }

    private func playTarget(_ target: String? = nil) {
        guard let target = target ?? currentTarget else { return complete() }
        status = .playing
        // The target is not revealed while it plays; that is the exercise.
        activeSign = nil
        requestID = audio.play([token(for: target)], spacing: .text) { [weak self] id, event in
            guard let self, requestID == id else { return }
            switch event {
            case .finished(let cancelled):
                requestID = nil
                if cancelled { resetToIdle() } else { status = .waitingForAnswer }
            case .failed(let reason):
                requestID = nil
                fail(reason)
            default: break
            }
        }
        if requestID == nil { fail(audio.unavailableReason ?? "Не удалось начать воспроизведение") }
    }

    private func repeatError(_ target: String) {
        status = .repeatingError
        activeSign = target
        let tokens = Array(repeating: token(for: target), count: Self.repeatCount)
        requestID = audio.play(tokens, spacing: .errorRepeat) { [weak self] id, event in
            guard let self, requestID == id else { return }
            switch event {
            case .pulse(let value): pulse = value
            case .finished(let cancelled):
                requestID = nil
                pulse = .none
                if cancelled {
                    resetToIdle()
                } else {
                    activeSign = nil
                    schedule(after: .seconds(1)) { $0.advance() }
                }
            case .failed(let reason):
                requestID = nil
                fail(reason)
            default: break
            }
        }
        if requestID == nil { fail(audio.unavailableReason ?? "Не удалось начать воспроизведение") }
    }

    private func advance() {
        chosenSign = nil
        step += 1
        if step >= sequence.count {
            complete()
        } else {
            playTarget()
        }
    }

    private func complete() {
        let duration = Date.now.timeIntervalSince(startedAt)
        status = .completed
        activeSign = nil
        pulse = .none
        chosenSign = nil

        let total = progress.total
        let groups = sequence
            .split(separator: SequenceGenerator.groupGap)
            .map { $0.joined() }

        if exercise != .learn {
            results = ReceptionResults(
                exercise: exercise,
                lessonID: lesson.id,
                total: total,
                errors: errors,
                wrongAnswers: wrongAnswers,
                radiogramGroups: exercise == .exam ? groups : [],
                duration: duration)
        }

        history.add(SessionRecord(
            date: .now,
            kind: .reception,
            title: "Урок \(lesson.id) · \(exercise.title)",
            detail: exercise == .exam ? "\(groups.count) групп, проверка по бумаге" : lessonSigns.joined(separator: " "),
            total: total,
            errors: exercise.isInteractive ? wrongAnswers : nil,
            duration: duration,
            errorSigns: errors))
    }

    private func fail(_ reason: String) {
        pendingStep?.cancel()
        status = .failed(reason)
        activeSign = nil
        pulse = .none
    }

    private func resetToIdle() {
        pendingStep?.cancel()
        pendingStep = nil
        requestID = nil
        status = .idle
        activeSign = nil
        pulse = .none
        chosenSign = nil
    }

    private func cancelPreview() {
        if let previewID {
            audio.cancel(previewID)
            self.previewID = nil
        }
        activeSign = nil
        pulse = .none
    }

    /// Short presentation pauses between answer feedback and the next sign.
    /// They only delay the next `play` request; audio timing stays in the engine.
    private func schedule(after delay: Duration, _ action: @escaping (ReceptionSession) -> Void) {
        pendingStep?.cancel()
        pendingStep = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    private func token(for sign: String) -> PlaybackToken {
        sign == SequenceGenerator.groupGap ? .groupGap : PlaybackToken(display: sign, patterns: catalog.patterns(for: sign, overrides: settings.customOverrides))
    }
}

#if DEBUG
/// Preview-only state injection. Never called by the running app's flow.
extension ReceptionSession {
    struct PreviewState {
        var status: ReceptionStatus = .idle
        var sequence: [String] = []
        var step = 0
        var playedTokens = 0
        var activeSign: String?
        var pulse: Pulse = .none
        var chosenSign: String?
        var errors: [String] = []
    }

    func applyPreview(_ state: PreviewState) {
        status = state.status
        sequence = state.sequence
        step = state.step
        playedTokens = state.playedTokens
        activeSign = state.activeSign
        pulse = state.pulse
        chosenSign = state.chosenSign
        errors = state.errors
        wrongAnswers = state.errors.count
    }
}
#endif
