import Foundation
import Observation

enum Task5SessionStatus: String, Codable {
    case idle, running, playing, paused, completed, aborted, interrupted
}

struct Task5CheckFeedback: Equatable {
    let isCorrect: Bool
    let text: String
}

struct Task5CodeMeaning: Codable, Identifiable, Equatable {
    let code: String
    let number: String
    let expression: String?
    var id: String { code + ":" + (expression ?? number) }
    var display: String { code + " · " + (expression ?? number) }
}

struct Task5Attempt: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let stepID: String
    let input: String
    let correct: Bool
    let errors: Int?
    let aided: Bool
    let selfChecked: Bool
    var inputMethod: String? = nil
}

struct Task5Event: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let stepID: String?
    let kind: String
    /// Event summaries never contain a hidden incoming radiogram or password answer.
    let detail: String
    var codeMeanings: [Task5CodeMeaning]? = nil
}

struct Task5Archive: Codable {
    var schemaVersion = 1
    let id: UUID
    let variant: Task5Variant
    let status: Task5SessionStatus
    let currentStepIndex: Int
    let elapsedSeconds: Int
    let elapsedDuration: TimeInterval?
    let runtimeBotSpeed: Int?
    let startedAt: Date
    let savedAt: Date
    let attempts: [Task5Attempt]
    let events: [Task5Event]
    let completedGroupStepIDs: [String]
    let revealedStepIDs: [String]
    let repeatCount: Int
    var inputText: String? = nil
    var receptionDraft: String? = nil
    var pauseRemainingDuration: TimeInterval? = nil
    var radiogramRepair: Task5RadiogramRepair? = nil
}

/// Portable results can resume from the seed without exposing unheard incoming
/// material. The full reference appears only after the exchange is completed.
struct Task5Export: Codable {
    var schemaVersion = 1
    let id: UUID
    let seed: UInt64
    let profileID: String
    let configuration: Task5Configuration
    let status: Task5SessionStatus
    let currentStepIndex: Int
    let elapsedSeconds: Int
    let elapsedDuration: TimeInterval
    let runtimeBotSpeed: Int?
    let startedAt: Date
    let savedAt: Date
    let attempts: [Task5Attempt]
    let events: [Task5Event]
    let completedGroupStepIDs: [String]
    let revealedStepIDs: [String]
    let repeatCount: Int
    let reviewVariant: Task5Variant?
    var inputText: String? = nil
    var receptionDraft: String? = nil
    var pauseRemainingDuration: TimeInterval? = nil
    var radiogramRepair: Task5RadiogramRepair? = nil
}

enum Task5SessionError: LocalizedError {
    case unfinished, empty, invalidArchive, developerReview
    var errorDescription: String? {
        switch self {
        case .unfinished: "Остановите тренировку перед экспортом"
        case .empty: "Сначала начните тренировку"
        case .invalidArchive: "Файл тренировки повреждён или несовместим"
        case .developerReview: "DEV-просмотр не сохраняется как результат тренировки"
        }
    }
}

/// A complete local task-5 exchange. The coordinator owns audible timing; this
/// model owns request IDs, protocol state, keyed input and operator documents.
@Observable
final class Task5Session {
    let isDeveloperReview: Bool
    var developerAudioEnabled = true
    private(set) var developerStageIsFrozen = true
    private(set) var isDeveloperAutoPreview = false
    @ObservationIgnored private var developerPreviewTask: Task<Void, Never>?
    let reference: Task5Reference
    let rhythm = KeyRhythm()
    var configuration = Task5Configuration() {
        didSet { settings.task5Configuration = configuration }
    }
    var seedText = ""
    var inputText = ""
    var receptionDraft = ""
    var isGuideVisible = false
    var isEnabled = false {
        didSet {
            if !isEnabled {
                if isDeveloperReview { developerStopPreview() }
                releaseKey()
                if isSessionActive && !isPaused { pause() }
            }
        }
    }

    private(set) var variant: Task5Variant?
    private(set) var status: Task5SessionStatus = .idle
    private(set) var currentStepIndex = 0
    private(set) var elapsedSeconds = 0
    private(set) var elapsedDuration: TimeInterval = 0
    private(set) var pauseRemainingSeconds = 0
    private(set) var errorMessage: String?
    private(set) var lastCheckFeedback: Task5CheckFeedback?
    private(set) var storageError: String?
    private(set) var attempts: [Task5Attempt] = []
    private(set) var events: [Task5Event] = []
    private(set) var repeatCount = 0
    private(set) var buffer = ""
    private(set) var previewCharacter = ""
    private(set) var correctionNotice: String?
    private(set) var lastTransmissionText = ""
    private(set) var radiogramRepair: Task5RadiogramRepair?
    private(set) var pulse: Pulse = .none

    @ObservationIgnored private let catalog: MorseCatalog
    @ObservationIgnored private let audio: AudioCoordinator
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private let archiveDirectory: URL?
    @ObservationIgnored private var referenceError: String?
    @ObservationIgnored private var requestID: PlaybackRequestID?
    @ObservationIgnored private var playbackEpoch = UUID()
    @ObservationIgnored private var hardwareObserver: UUID?
    private(set) var isWaitingForBot = false
    @ObservationIgnored private let botResponseDelay: (Task5Step, Bool) -> TimeInterval
    @ObservationIgnored private let authenticationWaitDuration: () -> TimeInterval
    @ObservationIgnored private var activeAuthenticationWaitDuration: TimeInterval?
    @ObservationIgnored private var skipNextBotResponseDelay = false
    @ObservationIgnored private var botReplyTask: Task<Void, Never>?
    @ObservationIgnored private var activeReply: (text: String, repeating: Bool)?
    @ObservationIgnored private var pausedReply: (text: String, repeating: Bool)?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var draftSaveTask: Task<Void, Never>?
    @ObservationIgnored private var gapTask: Task<Void, Never>?
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var startedUptime: TimeInterval?
    @ObservationIgnored private var pauseStageStartedUptime: TimeInterval?
    @ObservationIgnored private var pausedAtUptime: TimeInterval?
    @ObservationIgnored private var completedGroupStepIDs = Set<String>()
    @ObservationIgnored private var revealedStepIDs = Set<String>()
    @ObservationIgnored private var finishedPlaybackStepIDs = Set<String>()
    @ObservationIgnored private var paperCheckedStepIDs = Set<String>()
    @ObservationIgnored private var lastBotMessage: String?
    @ObservationIgnored private var lastBotStepID: String?
    @ObservationIgnored private var repeating = false
    @ObservationIgnored private var startsNewTransmission = false
    @ObservationIgnored private var lastSource: KeySource?
    @ObservationIgnored private var keyPressedUptime: TimeInterval?
    @ObservationIgnored private var lastKeyReleaseUptime: TimeInterval?
    @ObservationIgnored private var keyedStepID: String?
    @ObservationIgnored private var firstSignalRelease: [String: TimeInterval] = [:]
    @ObservationIgnored private var measuredSignalSecondParts = Set<String>()

    static var defaultArchiveDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PalomaMorse/Task5", isDirectory: true)
    }

    init(catalog: MorseCatalog, audio: AudioCoordinator, settings: SettingsStore,
         reference: Task5Reference? = nil,
         archiveDirectory: URL? = Task5Session.defaultArchiveDirectory,
         now: @escaping () -> Date = { .now },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         botResponseDelay: @escaping (Task5Step, Bool) -> TimeInterval = { step, repeating in
             // Allow time to finish writing, look up a password or check a receipt.
             if !repeating && (step.tdrExpressionID == "password" || step.id.hasPrefix("auth-") || step.id.hasSuffix("-receipt")) {
                 return Double.random(in: 2.5...5.0)
             }
             return Double.random(in: 1.0...3.0)
         }, authenticationWaitDuration: @escaping () -> TimeInterval = { Double.random(in: 55...65) },
         developerReview: Bool = false) {
        self.isDeveloperReview = developerReview
        self.catalog = catalog; self.audio = audio; self.settings = settings
        self.configuration = settings.task5Configuration
        self.botResponseDelay = botResponseDelay
        self.authenticationWaitDuration = authenticationWaitDuration
        self.archiveDirectory = developerReview ? nil : archiveDirectory; self.now = now; self.uptime = uptime
        do { self.reference = try reference ?? Task5Reference.load() }
        catch {
            self.reference = Task5Reference(cells: [], codes: [])
            self.referenceError = error.localizedDescription
        }
        hardwareObserver = audio.observeHardwareKey { [weak self] pressed in
            guard let self, isEnabled else { return }
            pressed ? keyDown(from: .hardware) : keyUp(from: .hardware)
        }
    }

    deinit { botReplyTask?.cancel(); timer?.cancel(); gapTask?.cancel(); draftSaveTask?.cancel(); developerPreviewTask?.cancel() }

    var usesRadioFlow: Bool { variant?.configuration.radioFlow == true }
    var receptionReceipt: Task5Step? {
        guard usesRadioFlow, currentStep?.kind == .receive, let variant,
              variant.steps.indices.contains(currentStepIndex + 1) else { return nil }
        let next = variant.steps[currentStepIndex + 1]
        return next.kind == .receipt && next.direction == .transmit ? next : nil
    }
    func startRadioExchange() {
        guard !isSessionActive else { return }
        configuration.radioFlow = true
        configuration.rehearsal = false
        start()
    }
    func useRadioFlowForRestoredSession() throws {
        guard let current = variant, status == .paused else { return }
        var restoredConfiguration = current.configuration
        restoredConfiguration.radioFlow = true
        restoredConfiguration.rehearsal = false
        variant = try Task5Scenario.generate(configuration: restoredConfiguration, seed: current.seed,
            reference: reference, catalog: catalog, profileID: current.profileID)
        configuration.radioFlow = true
        configuration.rehearsal = false
        if currentStep?.kind == .receive {
            if receptionDraft.isEmpty { receptionDraft = inputText }
            inputText = ""
        }
        log("radioFlow", "Восстановлен обмен без кнопок подтверждения")
        persist()
    }

    func recordGuideUse() {
        guard isSessionActive, isGuideVisible, let step = currentStep else { return }
        log("guide", "Открыта пошаговая инструкция")
        if step.direction == .transmit && step.bodyGroups == 0 {
            revealedStepIDs.insert(step.id)
        }
        persist()
    }

    var currentStep: Task5Step? {
        guard let variant, variant.steps.indices.contains(currentStepIndex) else { return nil }
        var step = Task5Validator.resolvedStep(variant.steps[currentStepIndex], variant: variant, attempts: attempts)
        if step.id.hasSuffix("-wait-pause") {
            step.requiredPauseSeconds = activeAuthenticationWaitDuration ?? 60
        } else if step.direction == .receive && Task5Validator.isWaitCommand(step) {
            step.expectedMessages = ["ОК АС 1 К"]
            step.botMessage = "ОК АС 1 К"
        }
        return step
    }
    var isAuthenticationWait: Bool { currentStep?.id.hasSuffix("-wait-pause") == true }
    var preparedServiceTransmission: String? {
        guard status == .running, let step = currentStep, step.direction == .transmit,
              step.bodyGroups == 0, let text = step.expectedMessages.first, let variant,
              Task5Validator.tokens(text).contains(where: { variant.tdr.decode($0) != nil }) else { return nil }
        return text
    }
    /// Only a valid operator AS acknowledgment releases meanings of completed
    /// incoming authentication frames. Displaying an outgoing echo never does.
    var acknowledgedCodeMeanings: [Task5CodeMeaning] {
        codeDisclosure.revealed
    }
    /// Disclosure history remains intact; the workspace shows only the latest
    /// acknowledged frame belonging to its current service exchange.
    var displayedCodeMeanings: [Task5CodeMeaning] {
        guard let variant, let currentStep, let scope = codeDisplayScope(currentStep) else { return [] }
        var pending: [Task5CodeMeaning] = [], latest: [Task5CodeMeaning] = []
        for event in events {
            let step = variant.steps.first(where: { $0.id == event.stepID }).map {
                Task5Validator.resolvedStep($0, variant: variant, attempts: attempts)
            }
            if event.kind == "botDone", let step, codeDisplayScope(step) == scope {
                let frame = event.codeMeanings ?? step.botMessage.map { decodeCodeMeanings($0, step: step) } ?? []
                if !frame.isEmpty { pending = frame }
            }
            let legacyAcknowledgment = event.kind == "accepted" && step?.direction == .transmit &&
                step.map(Task5Validator.isWaitCommand) == true &&
                attempts.contains(where: { $0.stepID == event.stepID && $0.correct && Task5Validator.waitMinutes($0.input) != nil })
            if event.kind == "codesAcknowledged" || legacyAcknowledgment {
                if !pending.isEmpty {
                    latest = []
                    for meaning in pending where !latest.contains(where: { $0.id == meaning.id }) { latest.append(meaning) }
                }
                pending = []
            }
        }
        return latest
    }
    private func codeDisplayScope(_ step: Task5Step) -> String? {
        if step.id.hasPrefix("auth-") { return "authentication" }
        guard step.id.hasSuffix("-offer") || step.id.hasSuffix("-ready"), let variant,
              let radiogram = variant.radiograms.first(where: { step.id.hasPrefix($0.id + "-") }) else { return nil }
        return "offer:" + radiogram.id
    }
    private var pendingCodeMeanings: [Task5CodeMeaning] { codeDisclosure.pending }
    private func decodeCodeMeanings(_ text: String, step: Task5Step) -> [Task5CodeMeaning] {
        guard let variant else { return [] }
        return Task5Validator.tokens(text).enumerated().compactMap { index, code in
            variant.tdr.decode(code).map { cell in
                let rule = step.authenticationTokens.flatMap { $0.indices.contains(index) ? $0[index] : nil }
                let numericAuthentication = step.id.hasPrefix("auth-") && rule != "password" && step.tdrExpressionID != "password"
                return Task5CodeMeaning(code: code, number: cell.number, expression: numericAuthentication ? nil : cell.expression)
            }
        }
    }
    private var codeDisclosure: (pending: [Task5CodeMeaning], revealed: [Task5CodeMeaning]) {
        guard let variant else { return ([], []) }
        var pending: [Task5CodeMeaning] = [], revealed: [Task5CodeMeaning] = []
        for event in events {
            let step = variant.steps.first(where: { $0.id == event.stepID }).map {
                Task5Validator.resolvedStep($0, variant: variant, attempts: attempts)
            }
            if event.kind == "botDone" {
                if let meanings = event.codeMeanings { pending += meanings }
                else if let step, let text = step.botMessage { pending += decodeCodeMeanings(text, step: step) }
            }
            let legacyAcknowledgment = event.kind == "accepted" && step?.direction == .transmit &&
                step.map(Task5Validator.isWaitCommand) == true &&
                attempts.contains(where: { $0.stepID == event.stepID && $0.correct && Task5Validator.waitMinutes($0.input) != nil })
            if event.kind == "codesAcknowledged" || legacyAcknowledgment {
                for meaning in pending where !revealed.contains(where: { $0.id == meaning.id }) {
                    revealed.append(meaning)
                }
                pending = []
            }
        }
        return (pending, revealed)
    }
    var isSessionActive: Bool { status == .running || status == .playing || status == .paused }
    var isActive: Bool { isSessionActive }
    var isPaused: Bool { status == .paused }
    var completedSteps: Int { currentStepIndex }
    var completedGroups: Int {
        variant?.steps.filter { completedGroupStepIDs.contains($0.id) }.reduce(0) { $0 + $1.bodyGroups } ?? 0
    }
    func completedGroups(in direction: Task5Direction) -> Int {
        variant?.steps.filter { $0.direction == direction && completedGroupStepIDs.contains($0.id) }
            .reduce(0) { $0 + $1.bodyGroups } ?? 0
    }
    func totalGroups(in direction: Task5Direction) -> Int {
        variant?.radiograms.filter { $0.direction == direction }.reduce(0) { $0 + $1.groupCount } ?? 0
    }
    var errorCount: Int { attempts.compactMap(\.errors).reduce(0,+) }
    var hintCount: Int { revealedStepIDs.count }
    var automaticGuidanceCount: Int {
        Set(events.filter { $0.kind == "autoGuidance" }.compactMap(\.stepID)).count
    }
    var hasInterruptions: Bool {
        events.contains { $0.kind == "interrupted" || $0.kind == "restored" || $0.kind == "focusLost" }
    }
    var hasSidetone: Bool { audio.isReady }
    var isKeyDown: Bool { rhythm.isDown }
    var transmissionKeyLabel: String { settings.transmissionKeyLabel }
    var effectiveAudioSettings: AudioSettings {
        var value = settings.audio
        if isSessionActive { value.speed = configuration.botSpeed.clamped(to: AudioSettings.speedRange) }
        return value
    }
    var startBlockReason: String? {
        if let referenceError { return referenceError }
        if !audio.isReady { return audio.unavailableReason }
        if isSessionActive { return "Тренировка уже идёт" }
        if audio.hasActivePlayback { return "Дождитесь окончания передачи" }
        if !seedText.isEmpty && UInt64(seedText.trimmingCharacters(in: .whitespacesAndNewlines)) == nil { return "Введите целое число для варианта" }
        if !(30...150).contains(configuration.botSpeed) { return "Скорость бота: 30–150 зн/мин" }
        if !(30...150).contains(configuration.keySpeed) { return "Темп ключа: 30–150 зн/мин" }
        return nil
    }
    var canStart: Bool { startBlockReason == nil }
    var canSubmit: Bool {
        guard status == .running, !rhythm.isDown, let step = currentStep else { return false }
        return step.kind != .listen && step.kind != .pause
    }
    var canRepeat: Bool { status == .running && lastBotMessage != nil && (usesRadioFlow || lastBotStepID == currentStep?.id) }
    var canReveal: Bool {
        guard status == .running, let step = currentStep else { return false }
        return !step.expectedMessages.isEmpty && !revealedStepIDs.contains(step.id)
    }
    var outboundText: String? {
        guard let step = currentStep else { return nil }
        if let id = step.radiogramID, step.kind == .transmit,
           let radiogram = variant?.radiograms.first(where: { $0.id == id && $0.direction == .transmit }) {
            return radiogram.wireText
        }
        guard
              step.bodyGroups > 0 || step.kind == .signal,
              step.direction != .receive, step.tdrExpressionID == nil else { return nil }
        return step.expectedMessages.first
    }
    var outgoingRadiogram: Task5Radiogram? {
        guard let step = currentStep, step.direction == .transmit, step.bodyGroups > 0,
              let id = step.radiogramID else { return nil }
        return variant?.radiograms.first { $0.id == id && $0.direction == .transmit }
    }
    /// Learning supplies the operator's service transmission directly. Prepared
    /// radiograms retain their ordinary outgoing form; incoming material never
    /// appears here. Availability itself is recorded as assistance on submit.
    var teachingTransmission: String? {
        guard let variant, !variant.configuration.rehearsal, (!usesRadioFlow || isGuideVisible), let step = currentStep,
              step.direction == .transmit, step.bodyGroups == 0,
              step.kind == .transmit || step.kind == .receipt || step.kind == .signal else { return nil }
        return step.expectedMessages.first
    }
    var revealedReference: String? {
        guard let step = currentStep, revealedStepIDs.contains(step.id) else { return nil }
        return step.expectedMessages.first
    }
    var paperReference: String? {
        guard configuration.receptionMode == .paper, let step = currentStep,
              paperCheckedStepIDs.contains(step.id) else { return nil }
        return step.expectedMessages.first
    }
    var needsPaperSelfCheck: Bool {
        configuration.receptionMode == .paper && currentStep?.kind == .receive && (currentStep?.bodyGroups ?? 0) > 0
    }
    /// Time-only comparison. It is not a complete normative grade of the exchange.
    var timeComparison: String? {
        guard !isDeveloperReview, status == .completed, !hasInterruptions, let variant,
              completedGroups == variant.totalBodyGroups,
              variant.configuration.rehearsal, variant.configuration.length == .full,
              let band = variant.configuration.category.timeBand(for: elapsedDuration) else { return nil }
        return "\(band.title) · учебные границы"
    }

    func generate(randomizeSeed: Bool = false) {
        guard !isSessionActive else { return }
        if randomizeSeed || seedText.isEmpty { seedText = String(UInt64.random(in: 1...UInt64.max)) }
        guard let seed = UInt64(seedText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Введите целое число для варианта"; return
        }
        do {
            variant = try Task5Scenario.generate(configuration: configuration, seed: seed, reference: reference, catalog: catalog)
            errorMessage = nil
            status = .idle
            currentStepIndex = 0
            startedAt = nil; startedUptime = nil; elapsedSeconds = 0; elapsedDuration = 0; inputText = ""; receptionDraft = ""; startsNewTransmission = false
            attempts = []; events = []; repeatCount = 0; lastCheckFeedback = nil
            activeAuthenticationWaitDuration = nil; skipNextBotResponseDelay = false
            radiogramRepair = nil
            completedGroupStepIDs = []; revealedStepIDs = []; paperCheckedStepIDs = []; finishedPlaybackStepIDs = []
            firstSignalRelease = [:]; measuredSignalSecondParts = []; keyedStepID = nil
            lastBotMessage = nil; lastBotStepID = nil
        } catch { variant = nil; errorMessage = error.localizedDescription }
    }

    func generateNewVariant() {
        guard !isSessionActive else { return }
        if configuration.length == .short { configuration.length = .thirty }
        configuration.rehearsal = false
        generate(randomizeSeed: true)
    }

    func start() {
        guard let reason = startBlockReason else {
            startReadyVariant(); return
        }
        errorMessage = reason
    }

    private func startReadyVariant() {
        generate()
        guard variant != nil else { return }
        cancelPlayback(); pausedReply = nil
        lastTransmissionText = ""; rhythm.clear()
        sessionID = UUID(); startedAt = now(); startedUptime = uptime(); currentStepIndex = 0; elapsedSeconds = 0; elapsedDuration = 0
        completedGroupStepIDs = []; revealedStepIDs = []; finishedPlaybackStepIDs = []; paperCheckedStepIDs = []
        attempts = []; events = []; repeatCount = 0; inputText = ""; errorMessage = nil; storageError = nil; lastCheckFeedback = nil
        activeAuthenticationWaitDuration = nil; skipNextBotResponseDelay = false
        radiogramRepair = nil
        status = .running
        log("started", "Тренировка начата")
        startTimer()
        enterStep()
    }

    func restartSameVariant() {
        guard !isSessionActive, let variant else { return }
        configuration = variant.configuration
        seedText = String(variant.seed)
        start()
    }

    func submit() {
        guard canSubmit, let step = currentStep, let variant else { return }
        commitPendingCharacter()
        errorMessage = nil
        let rawText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = Task5Validator.normalizedTransmission(rawText, for: receptionReceipt ?? step, variant: variant)
        if text != Task5Validator.tokens(rawText).joined(separator: " ") {
            log("spacingRecovered", "Границы групп: «\(rawText)» → «\(text)»")
        }
        if handleServiceRequest(text) {
            lastCheckFeedback = Task5CheckFeedback(isCorrect: errorMessage == nil, text: errorMessage ?? "Команда принята")
            if let errorMessage {
                startsNewTransmission = true
                log("serviceRejected", errorMessage)
                persist()
            }
            return
        }
        if let repair = radiogramRepair, repair.stepID == step.id,
           let radiogram = variant.radiograms.first(where: { $0.id == step.radiogramID }) {
            submitRadiogramCorrection(text, repair: repair, radiogram: radiogram, step: step, variant: variant)
            return
        }
        if usesRadioFlow, let receipt = receptionReceipt {
            let check = Task5Validator.validate(text, for: receipt, variant: variant)
            guard check.isCorrect else {
                rejectRadioTransmission(text, step: receipt, validation: check)
                return
            }
            if configuration.receptionMode == .typed {
                let received = Task5Validator.validate(receptionDraft, for: step, variant: variant)
                attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: step.id, input: receptionDraft,
                    correct: received.isCorrect, errors: received.errors,
                    aided: revealedStepIDs.contains(step.id), selfChecked: false, inputMethod: "reception"))
            } else {
                log("paperUnverified", "Приём записан на бумаге; точность не проверена")
            }
            let method = keyedStepID == step.id ? "key" : "text"
            acceptStep()
            attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: receipt.id, input: text,
                correct: true, errors: 0, aided: isGuideVisible, selfChecked: false, inputMethod: method))
            acceptStep()
            return
        }
        if needsPaperSelfCheck && !usesRadioFlow {
            paperCheckedStepIDs.insert(step.id)
            revealedStepIDs.insert(step.id)
            log("paperReview", "Открыта сверка бумажного приёма")
            persist()
            return
        }
        let validation = Task5Validator.validate(text, for: step, variant: variant)
        lastCheckFeedback = Task5CheckFeedback(isCorrect: validation.isCorrect, text: validation.message ?? "Верно")
        attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: step.id, input: text,
                                     correct: validation.isCorrect, errors: validation.errors,
                                     aided: revealedStepIDs.contains(step.id) || teachingTransmission != nil, selfChecked: false,
                                     inputMethod: keyedStepID == step.id ? "key" : "text"))
        if validation.isCorrect {
            if step.direction == .transmit && Task5Validator.isWaitCommand(step) {
                log("codesAcknowledged", "Принята квитанция на расшифровку кодов")
            }
            acceptStep()
        } else {
            errorMessage = validation.message ?? "Проверьте передачу"
            log("rejected", errorMessage ?? "Сообщение требует исправления")
            if usesRadioFlow {
                startsNewTransmission = true
                if step.direction == .transmit, step.bodyGroups > 0,
                   let radiogram = variant.radiograms.first(where: { $0.id == step.radiogramID }),
                   let repair = Task5RadiogramRepair.needed(stepID: step.id, draft: text, radiogram: radiogram, tdr: variant.tdr) {
                    radiogramRepair = repair
                    requestRadiogramCorrection(repair)
                } else { playBot("РПТ К", repeating: true) }
            }
            persist()
        }
    }

    private func requestRadiogramCorrection(_ repair: Task5RadiogramRepair) {
        // The received candidate lives in repair.draft, independently of the
        // next keyed fragment. Snapshot inputText therefore contains only an
        // actual unfinished correction, never the rejected whole radiogram.
        let previous = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !previous.isEmpty { lastTransmissionText = previous }
        inputText = ""; buffer = ""; previewCharacter = ""
        startsNewTransmission = false
        lastBotMessage = repair.part.request; lastBotStepID = repair.stepID
        correctionNotice = "Корреспондент запросил: \(repair.part.request)"
        log("radiogramRepeatRequested", repair.part.request)
        playBot(repair.part.request, repeating: true)
    }

    private func submitRadiogramCorrection(_ text: String, repair: Task5RadiogramRepair,
                                           radiogram: Task5Radiogram, step: Task5Step, variant: Task5Variant) {
        let correctPart = repair.responseIsCorrect(text, radiogram: radiogram, tdr: variant.tdr)
        attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: step.id, input: text,
            correct: correctPart, errors: correctPart ? 0 : 1, aided: isGuideVisible,
            selfChecked: false, inputMethod: "radiogramCorrection"))
        guard let assembled = repair.merging(text, radiogram: radiogram) else {
            errorMessage = "Передайте запрошенную часть и завершите К"
            requestRadiogramCorrection(repair); persist(); return
        }
        let validation = Task5Validator.validate(assembled, for: step, variant: variant)
        if validation.isCorrect {
            attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: step.id, input: assembled,
                correct: true, errors: 0, aided: isGuideVisible, selfChecked: false, inputMethod: "assembled"))
            inputText = assembled
            radiogramRepair = nil
            lastCheckFeedback = Task5CheckFeedback(isCorrect: true, text: "Радиограмма исправлена")
            log("radiogramRepaired", "Запрошенные части исправлены; радиограмма принята")
            acceptStep()
        } else {
            let next = Task5RadiogramRepair.needed(stepID: step.id, draft: assembled, radiogram: radiogram, tdr: variant.tdr) ?? repair
            radiogramRepair = next
            errorMessage = validation.message
            requestRadiogramCorrection(next)
            persist()
        }
    }

    private func rejectRadioTransmission(_ text: String, step: Task5Step, validation: Task5Validation) {
        attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: step.id, input: text,
            correct: false, errors: validation.errors, aided: isGuideVisible, selfChecked: false,
            inputMethod: "key"))
        errorMessage = validation.message
        startsNewTransmission = true
        log("rejected", validation.message ?? "Неверная квитанция; запрошен повтор")
        playBot("РПТ К", repeating: true)
        persist()
    }

    /// Paper reception is explicitly self-checked, never assigned an automatic accuracy.
    func confirmPaperReception(correct: Bool) {
        guard canSubmit, needsPaperSelfCheck, let step = currentStep, paperCheckedStepIDs.contains(step.id) else { return }
        attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: step.id, input: "",
                                     correct: correct, errors: nil, aided: true, selfChecked: true))
        lastCheckFeedback = Task5CheckFeedback(isCorrect: correct, text: correct ? "Сверено" : "Проверьте запись")
        if correct { acceptStep() }
        else { errorMessage = "Повторите приём и сверьте запись"; persist() }
    }

    /// Restarting a transmission preserves the failed attempt, never silently edits it.
    func retryTransmission() {
        guard canSubmit, let step = currentStep, step.direction == .transmit, let variant else { return }
        commitPendingCharacter()
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let check = Task5Validator.validate(inputText, for: step, variant: variant)
        if attempts.last?.stepID != step.id || attempts.last?.input != inputText {
            attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: step.id, input: inputText,
                correct: check.isCorrect, errors: check.errors,
                aided: teachingTransmission != nil || revealedStepIDs.contains(step.id), selfChecked: false,
                inputMethod: keyedStepID == step.id ? "key" : "text"))
        }
        gapTask?.cancel()
        inputText = ""; buffer = ""; previewCharacter = ""; rhythm.clear()
        radiogramRepair = nil
        lastTransmissionText = ""
        keyedStepID = nil; errorMessage = nil; lastCheckFeedback = nil
        log("retryTransmission", "Начата новая попытка передачи")
        persist()
    }

    func saveDraft() {
        draftSaveTask?.cancel()
        guard isSessionActive else { return }
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func acceptStep() {
        guard let step = currentStep else { return }
        releaseKey()
        gapTask?.cancel()
        if step.kind == .signal {
            let signalID = step.id.replacingOccurrences(of: "-first", with: "").replacingOccurrences(of: "-second", with: "")
            if step.id.hasSuffix("-first"), keyedStepID == step.id, let lastKeyReleaseUptime {
                firstSignalRelease[signalID] = lastKeyReleaseUptime
            } else if keyedStepID != step.id {
                log("simulatedSignalInput", "Сигнал введён текстом; интервал ключа не измерен")
            }
        }
        if step.bodyGroups > 0 {
            if !usesRadioFlow || step.direction != .receive || attempts.last(where: { $0.stepID == step.id })?.correct == true {
                completedGroupStepIDs.insert(step.id)
            }
        }
        log("accepted", "Этап выполнен")
        if step.direction == .transmit || receptionReceipt != nil {
            let transmitted = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transmitted.isEmpty { lastTransmissionText = transmitted }
        }
        // Retain the visual tape; validation still starts with a clean input buffer.
        inputText = ""; buffer = ""; previewCharacter = ""
        radiogramRepair = nil
        currentStepIndex += 1
        enterStep()
    }

    private func enterStep() {
        errorMessage = nil; correctionNotice = nil
        pauseStageStartedUptime = nil; pausedAtUptime = nil; pauseRemainingSeconds = 0
        activeAuthenticationWaitDuration = nil
        guard var step = currentStep else { finish(); return }
        status = .running
        if step.id.hasSuffix("-wait-pause"), let variant {
            let commandID = String(step.id.dropLast("-pause".count))
            if variant.steps.first(where: { $0.id == commandID })?.direction == .transmit {
                currentStepIndex += 1
                enterStep()
                return
            }
            activeAuthenticationWaitDuration = authenticationWaitDuration().clamped(to: 55...65)
            step.requiredPauseSeconds = activeAuthenticationWaitDuration!
        }
        if step.id == "journal" || (usesRadioFlow && step.kind == .administrative) {
            // These are physical operator duties, not computer-verified actions.
            log("operatorDuty", step.title + " — самостоятельное действие")
            currentStepIndex += 1
            enterStep()
            if step.id.hasSuffix("-report") { correctionNotice = step.instruction.replacingOccurrences(of: " и внесите запись в аппаратный журнал", with: "") }
            return
        }
        if usesRadioFlow && step.kind == .receive { receptionDraft = "" }
        log("step", step.title)
        if teachingTransmission != nil { log("autoGuidance", "Показан код для передачи") }
        if step.kind == .pause {
            pauseStageStartedUptime = uptime()
            pauseRemainingSeconds = Int(ceil(step.requiredPauseSeconds))
            log("waitStarted", "Ожидание: \(pauseRemainingSeconds) с")
        } else if let message = step.botMessage, !message.isEmpty {
            lastBotMessage = message; lastBotStepID = step.id
            playBot(message, repeating: false)
        } else if !usesRadioFlow {
            lastBotMessage = nil; lastBotStepID = nil
        }
        persist()
    }

    private func playBot(_ text: String, repeating: Bool) {
        guard let step = currentStep, audio.isReady else {
            interrupt(reason: audio.unavailableReason ?? "Звуковой движок недоступен"); return
        }
        cancelPlayback()
        if isDeveloperReview && (!developerAudioEnabled || developerStageIsFrozen) { status = .running; return }
        releaseKey(); gapTask?.cancel(); buffer = ""; previewCharacter = ""
        activeReply = (text, repeating)
        // The second signal part follows the prescribed ten-second gap exactly.
        let secondSignalPart = step.id.hasPrefix("signal-") && step.id.hasSuffix("-second")
        let delay = usesRadioFlow && !isDeveloperReview && !(secondSignalPart && !repeating) && !skipNextBotResponseDelay ? botResponseDelay(step, repeating) : 0
        skipNextBotResponseDelay = false
        status = .playing
        guard delay > 0 else { beginBotPlayback(text, repeating: repeating); return }
        isWaitingForBot = true
        let epoch = playbackEpoch
        botReplyTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled, playbackEpoch == epoch,
                  status == .playing, currentStep?.id == step.id else { return }
            botReplyTask = nil
            isWaitingForBot = false
            beginBotPlayback(text, repeating: repeating)
        }
    }

    private func beginBotPlayback(_ text: String, repeating: Bool) {
        guard let step = currentStep, audio.isReady else {
            interrupt(reason: audio.unavailableReason ?? "Звуковой движок недоступен"); return
        }
        let tokens = tokenize(text)
        guard !tokens.isEmpty, !tokens.contains(where: { !$0.isGroupGap && $0.patterns.isEmpty }) else {
            interrupt(reason: "Не удалось подготовить передачу"); return
        }
        audio.updateSettings(effectiveAudioSettings)
        let epoch = UUID(); playbackEpoch = epoch; self.repeating = repeating
        status = .playing
        let expectedStepID = step.id
        requestID = audio.play(tokens, spacing: .text, protectedFromKey: true) { [weak self] id, event in
            guard let self, playbackEpoch == epoch, requestID == id,
                  currentStep?.id == expectedStepID, status == .playing else { return }
            switch event {
            case .pulse(let value): pulse = value
            case .finished(let cancelled):
                requestID = nil; pulse = .none; activeReply = nil
                guard !cancelled else { interrupt(reason: "Передача прервана"); return }
                finishedPlaybackStepIDs.insert(expectedStepID)
                status = .running
                log("botDone", "Передача корреспондента окончена", codeMeanings: decodeCodeMeanings(text, step: step))
                if !self.repeating && (currentStep?.kind == .listen ||
                    (usesRadioFlow && currentStep?.kind == .receive && receptionReceipt == nil)) {
                    acceptStep()
                } else { persist() }
            case .failed(let reason):
                requestID = nil; pulse = .none; interrupt(reason: reason)
            default: break
            }
        }
        if requestID == nil { interrupt(reason: audio.unavailableReason ?? "Передача не запущена") }
    }

    private func tokenize(_ text: String) -> [PlaybackToken] {
        var tokens: [PlaybackToken] = []
        for character in text.uppercased() {
            if character.isWhitespace {
                if !tokens.isEmpty && tokens.last?.isGroupGap == false { tokens.append(.groupGap) }
            } else {
                let sign = String(character)
                // This protocol profile uses a full five-dash zero. It avoids
                // ambiguity with Т in service messages and numeric groups.
                let patterns = sign == "0" ? ["-----"] : catalog.patterns(for: sign, overrides: settings.customOverrides)
                guard !patterns.isEmpty else { return [] }
                tokens.append(PlaybackToken(display: sign, patterns: patterns))
            }
        }
        if tokens.last?.isGroupGap == true { tokens.removeLast() }
        return tokens
    }

    func repeatBot() {
        guard canRepeat, let message = lastBotMessage else { return }
        repeatCount += 1; log("repeat", "Повтор передачи корреспондента")
        playBot(message, repeating: true)
        persist()
    }

    func revealReference() {
        guard canReveal, let step = currentStep else { return }
        revealedStepIDs.insert(step.id)
        log("hint", "Открыт образец сообщения")
        persist()
    }

    func pause() {
        guard status == .running || status == .playing else { return }
        pausedReply = activeReply
        releaseKey(); commitPendingCharacter(); cancelPlayback()
        gapTask?.cancel(); gapTask = nil
        pausedAtUptime = uptime()
        status = .paused; log("paused", "Пауза")
        persist()
    }

    func resume() {
        guard status == .paused, isEnabled else { return }
        guard audio.isReady else { errorMessage = audio.unavailableReason; return }
        if let pausedAtUptime, let began = pauseStageStartedUptime {
            pauseStageStartedUptime = began + max(0, uptime() - pausedAtUptime)
        }
        pausedAtUptime = nil
        status = .running; log("resumed", "Тренировка продолжена")
        if usesRadioFlow && currentStep?.kind == .administrative { enterStep(); return }
        if let reply = pausedReply {
            pausedReply = nil
            playBot(reply.text, repeating: reply.repeating)
        } else if let step = currentStep, let message = step.botMessage, !finishedPlaybackStepIDs.contains(step.id) {
            playBot(message, repeating: false)
        }
        if canSubmit, !inputText.isEmpty {
            lastKeyReleaseUptime = uptime()
            watchKeyGaps(unit: 6.0 / Double(configuration.keySpeed.clamped(to: 30...150)))
        }
        tick()
        persist()
    }

    func togglePause() { isPaused ? resume() : pause() }

    func focusLost() {
        releaseKey()
        guard isSessionActive else { return }
        // Switching apps/minimizing must release a held key, but the radio
        // exchange and any pending correspondent reply continue in background.
        log("focusLost", "Окно потеряло фокус; обмен продолжается")
        persist()
    }

    func stop() {
        guard isSessionActive else { return }
        close(status: .aborted, reason: "Тренировка остановлена")
    }

    func interrupt(reason: String = "Окно закрыто") {
        guard isSessionActive else { return }
        errorMessage = reason
        close(status: .interrupted, reason: reason)
    }

    private func finish() { close(status: .completed, reason: "Обмен завершён") }

    private func close(status nextStatus: Task5SessionStatus, reason: String) {
        developerStopPreview()
        releaseKey(); commitPendingCharacter(); cancelPlayback()
        gapTask?.cancel(); timer?.cancel(); timer = nil
        updateElapsed()
        status = nextStatus; pauseRemainingSeconds = 0; pausedReply = nil
        audio.updateSettings(settings.audio)
        log(nextStatus.rawValue, reason)
        persist()
    }

    private func cancelPlayback() {
        botReplyTask?.cancel(); botReplyTask = nil
        isWaitingForBot = false; activeReply = nil
        playbackEpoch = UUID()
        let old = requestID; requestID = nil; pulse = .none
        if let old { audio.cancel(old) }
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self, isSessionActive else { return }
                tick()
            }
        }
    }

    func tick() {
        updateElapsed()
        if isDeveloperReview && developerStageIsFrozen { return }
        guard status == .running, let step = currentStep, step.kind == .pause,
              let began = pauseStageStartedUptime else { return }
        let remaining = max(0, step.requiredPauseSeconds - (uptime() - began))
        let changed = pauseRemainingSeconds != Int(ceil(remaining))
        pauseRemainingSeconds = Int(ceil(remaining))
        if remaining > 0 && changed { persist() }
        if remaining == 0 {
            log("waitFinished", "Указанное время ожидания выдержано")
            if isAuthenticationWait { skipNextBotResponseDelay = true }
            acceptStep()
        }
    }

    private func updateElapsed() {
        guard let startedUptime else { return }
        elapsedDuration = max(elapsedDuration, max(0, uptime() - startedUptime))
        elapsedSeconds = Int(elapsedDuration)
    }

    private func log(_ kind: String, _ detail: String, codeMeanings: [Task5CodeMeaning]? = nil) {
        events.append(Task5Event(id: UUID(), date: now(), stepID: currentStep?.id, kind: kind, detail: detail, codeMeanings: codeMeanings))
    }

    private var remainingPauseDuration: TimeInterval? {
        guard let step = currentStep, step.kind == .pause, let began = pauseStageStartedUptime else { return nil }
        return max(0, step.requiredPauseSeconds - ((pausedAtUptime ?? uptime()) - began))
    }

    private func snapshot() throws -> Task5Archive {
        guard let variant, let startedAt else { throw Task5SessionError.empty }
        return Task5Archive(id: sessionID, variant: variant, status: status, currentStepIndex: currentStepIndex,
                            elapsedSeconds: elapsedSeconds, elapsedDuration: elapsedDuration, runtimeBotSpeed: configuration.botSpeed,
                            startedAt: startedAt, savedAt: now(),
                            attempts: attempts, events: events,
                            completedGroupStepIDs: completedGroupStepIDs.sorted(), revealedStepIDs: revealedStepIDs.sorted(), repeatCount: repeatCount, inputText: inputText, receptionDraft: receptionDraft, pauseRemainingDuration: remainingPauseDuration, radiogramRepair: radiogramRepair)
    }

    func exportData() throws -> Data {
        guard !isDeveloperReview else { throw Task5SessionError.developerReview }
        guard !isSessionActive else { throw Task5SessionError.unfinished }
        let value = try snapshot()
        let portable = Task5Export(id: value.id, seed: value.variant.seed, profileID: value.variant.profileID,
                                  configuration: value.variant.configuration, status: value.status,
                                  currentStepIndex: value.currentStepIndex, elapsedSeconds: value.elapsedSeconds,
                                  elapsedDuration: value.elapsedDuration ?? Double(value.elapsedSeconds), runtimeBotSpeed: value.runtimeBotSpeed,
                                  startedAt: value.startedAt,
                                  savedAt: value.savedAt, attempts: value.attempts, events: value.events,
                                  completedGroupStepIDs: value.completedGroupStepIDs, revealedStepIDs: value.revealedStepIDs,
                                  repeatCount: value.repeatCount, reviewVariant: value.status == .completed ? value.variant : nil, inputText: value.inputText, receptionDraft: value.receptionDraft, pauseRemainingDuration: value.pauseRemainingDuration, radiogramRepair: value.radiogramRepair)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(portable)
    }

    private func persist() {
        guard let archiveDirectory, startedAt != nil else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot())
            try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            try data.write(to: archiveDirectory.appendingPathComponent("\(sessionID.uuidString).json"), options: .atomic)
            storageError = nil
        } catch { storageError = "Не удалось сохранить тренировку: \(error.localizedDescription)" }
    }

    /// Explicitly selected archives can be resumed. Loading never silently creates
    /// a completed result; an unfinished exchange always returns paused.
    func restore(data: Data) throws {
        guard !isDeveloperReview else { throw Task5SessionError.developerReview }
        guard !isSessionActive else { throw Task5SessionError.unfinished }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let archive: Task5Archive
        if let portable = try? decoder.decode(Task5Export.self, from: data) {
            let regenerated = try Task5Scenario.generate(configuration: portable.configuration, seed: portable.seed,
                                                        reference: reference, catalog: catalog, profileID: portable.profileID)
            guard portable.schemaVersion == 1, portable.profileID == regenerated.profileID,
                  portable.reviewVariant == nil || portable.reviewVariant == regenerated else { throw Task5SessionError.invalidArchive }
            archive = Task5Archive(id: portable.id, variant: regenerated, status: portable.status,
                                   currentStepIndex: portable.currentStepIndex, elapsedSeconds: portable.elapsedSeconds,
                                   elapsedDuration: portable.elapsedDuration, runtimeBotSpeed: portable.runtimeBotSpeed,
                                   startedAt: portable.startedAt, savedAt: portable.savedAt,
                                   attempts: portable.attempts, events: portable.events,
                                   completedGroupStepIDs: portable.completedGroupStepIDs, revealedStepIDs: portable.revealedStepIDs, repeatCount: portable.repeatCount, inputText: portable.inputText, receptionDraft: portable.receptionDraft, pauseRemainingDuration: portable.pauseRemainingDuration, radiogramRepair: portable.radiogramRepair)
        } else { archive = try decoder.decode(Task5Archive.self, from: data) }
        guard archive.schemaVersion == 1, !archive.variant.steps.isEmpty,
              (0...archive.variant.steps.count).contains(archive.currentStepIndex), archive.elapsedSeconds >= 0,
              archive.variant.radiograms.count == (["task5.photos.v5.major-complete", "task5.photos.v6.callsigns-tdr", "task5.photos.v7.timed-wait", "task5.photos.v8.final-k"].contains(archive.variant.profileID) ? 2 : 4) else { throw Task5SessionError.invalidArchive }
        guard (try? Task5Scenario.generate(configuration: archive.variant.configuration, seed: archive.variant.seed,
                                           reference: reference, catalog: catalog, profileID: archive.variant.profileID)) == archive.variant else {
            throw Task5SessionError.invalidArchive
        }
        let duration = archive.elapsedDuration ?? Double(archive.elapsedSeconds)
        let stepIDs = Set(archive.variant.steps.map(\.id))
        let finishedBodyIDs = Set(archive.variant.steps.prefix(archive.currentStepIndex).filter { $0.bodyGroups > 0 }.map(\.id))
        guard duration.isFinite, duration >= 0, duration < Double(Int.max), Int(duration) == archive.elapsedSeconds,
              archive.repeatCount >= 0, archive.status != .idle,
              archive.runtimeBotSpeed == nil || (30...150).contains(archive.runtimeBotSpeed!),
              archive.status != .completed || archive.currentStepIndex == archive.variant.steps.count,
              Set(archive.completedGroupStepIDs).isSubset(of: finishedBodyIDs),
              Set(archive.revealedStepIDs).isSubset(of: stepIDs),
              archive.attempts.allSatisfy({ stepIDs.contains($0.stepID) }) else { throw Task5SessionError.invalidArchive }
        variant = archive.variant; configuration = archive.variant.configuration; seedText = String(archive.variant.seed)
        configuration.botSpeed = archive.runtimeBotSpeed ?? configuration.botSpeed
        sessionID = archive.id; currentStepIndex = archive.currentStepIndex; elapsedSeconds = archive.elapsedSeconds
        elapsedDuration = duration
        startedAt = archive.startedAt; startedUptime = uptime() - elapsedDuration; attempts = archive.attempts; events = archive.events
        completedGroupStepIDs = Set(archive.completedGroupStepIDs); revealedStepIDs = Set(archive.revealedStepIDs)
        repeatCount = archive.repeatCount; inputText = archive.inputText ?? ""; receptionDraft = archive.receptionDraft ?? ""; startsNewTransmission = false; errorMessage = nil; lastCheckFeedback = nil; finishedPlaybackStepIDs = []; paperCheckedStepIDs = []
        gapTask?.cancel(); draftSaveTask?.cancel()
        lastTransmissionText = ""
        buffer = ""; previewCharacter = ""; rhythm.clear(); keyedStepID = nil
        firstSignalRelease = [:]; measuredSignalSecondParts = []
        radiogramRepair = archive.radiogramRepair
        if let repair = radiogramRepair {
            guard let step = currentStep, step.id == repair.stepID, step.direction == .transmit, step.bodyGroups > 0,
                  let radiogram = variant?.radiograms.first(where: { $0.id == step.radiogramID }),
                  Task5RadiogramRepair.needed(stepID: step.id, draft: repair.draft, radiogram: radiogram, tdr: archive.variant.tdr) == repair else {
                throw Task5SessionError.invalidArchive
            }
        }
        activeAuthenticationWaitDuration = nil; skipNextBotResponseDelay = false
        pauseStageStartedUptime = nil; pauseRemainingSeconds = 0
        if isAuthenticationWait, let step = currentStep {
            let commandID = String(step.id.dropLast("-pause".count))
            if variant?.steps.first(where: { $0.id == commandID })?.direction == .transmit {
                // Historical archives stored a mandatory pause after the user's AS.
                // It is no longer an operator lock, even when the archive has minutes left.
                currentStepIndex += 1
            }
        }
        status = archive.status == .completed ? .completed : .paused
        pausedAtUptime = uptime()
        if let step = currentStep, step.kind == .pause {
            var remaining = archive.pauseRemainingDuration ?? step.requiredPauseSeconds
            guard remaining.isFinite, remaining >= 0 else {
                throw Task5SessionError.invalidArchive
            }
            if isAuthenticationWait {
                remaining = min(remaining, 65)
                activeAuthenticationWaitDuration = max(authenticationWaitDuration().clamped(to: 55...65), remaining)
            } else if remaining > step.requiredPauseSeconds { throw Task5SessionError.invalidArchive }
            let duration = currentStep?.requiredPauseSeconds ?? step.requiredPauseSeconds
            pauseStageStartedUptime = uptime() - (duration - remaining)
            pauseRemainingSeconds = Int(ceil(remaining))
        }
        lastBotMessage = currentStep?.botMessage; lastBotStepID = currentStep?.id
        if let repair = radiogramRepair {
            lastBotMessage = repair.part.request; lastBotStepID = repair.stepID
            pausedReply = (repair.part.request, true)
            correctionNotice = "Корреспондент запросил: \(repair.part.request)"
        }
        log("restored", "Тренировка открыта из файла")
        if isSessionActive { startTimer() }
        persist()
    }

    // MARK: Explicitly isolated developer walkthrough

    var developerStages: [Task5Step] {
        guard isDeveloperReview, let variant else { return [] }
        return variant.steps.filter { step in
            guard step.id != "journal" else { return false }
            if step.id.hasSuffix("-wait-pause") {
                let command = String(step.id.dropLast("-pause".count))
                return variant.steps.first(where: { $0.id == command })?.direction != .transmit
            }
            return true
        }
    }

    /// A dev jump rebuilds only this isolated session's canonical prefix. The
    /// selected stage enters normally, with real audio callbacks and request IDs.
    /// No completion is fabricated for the selected audible transmission.
    func developerJump(to index: Int, preserveAutoPreview: Bool = false) {
        guard isDeveloperReview, isEnabled, audio.isReady else { return }
        if !preserveAutoPreview { developerStopPreview() }
        releaseKey(); cancelPlayback(); gapTask?.cancel(); timer?.cancel(); draftSaveTask?.cancel()
        configuration.radioFlow = true; configuration.rehearsal = false
        if seedText.isEmpty { seedText = "20261102" }
        guard let seed = UInt64(seedText), let generated = try? Task5Scenario.generate(configuration: configuration,
            seed: seed, reference: reference, catalog: catalog), (0...generated.steps.count).contains(index) else { return }
        variant = generated
        sessionID = UUID(); startedAt = now(); startedUptime = uptime()
        elapsedDuration = 0; elapsedSeconds = 0
        currentStepIndex = 0; attempts = []; events = []; repeatCount = 0
        completedGroupStepIDs = []; revealedStepIDs = []; finishedPlaybackStepIDs = []; paperCheckedStepIDs = []
        inputText = ""; receptionDraft = ""; buffer = ""; previewCharacter = ""; lastTransmissionText = ""
        rhythm.clear(); radiogramRepair = nil; pausedReply = nil; activeAuthenticationWaitDuration = nil
        skipNextBotResponseDelay = false; startsNewTransmission = false; keyedStepID = nil
        firstSignalRelease = [:]; measuredSignalSecondParts = []; lastKeyReleaseUptime = nil
        errorMessage = nil; lastCheckFeedback = nil; correctionNotice = nil
        for prefixIndex in 0..<index {
            currentStepIndex = prefixIndex
            guard let step = currentStep else { continue }
            if let text = step.expectedMessages.first {
                attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: step.id, input: text,
                    correct: true, errors: 0, aided: false, selfChecked: false, inputMethod: "developerReview"))
            }
            if let message = step.botMessage {
                log("botDone", "DEV · имитация предыдущего этапа", codeMeanings: decodeCodeMeanings(message, step: step))
                finishedPlaybackStepIDs.insert(step.id)
            }
            if step.bodyGroups > 0 { completedGroupStepIDs.insert(step.id) }
            if step.kind == .signal && step.id.hasSuffix("-first") {
                firstSignalRelease[String(step.id.dropLast("-first".count))] = uptime() - Task5Signal.pauseSeconds
            }
            log("accepted", "DEV · имитация предыдущего этапа")
        }
        currentStepIndex = index; status = .running
        log("developerJump", "DEV · переход без сохранения результата")
        startTimer()
        if developerStageIsFrozen || currentStep?.kind == .administrative {
            pauseStageStartedUptime = nil; pausedAtUptime = nil; pauseRemainingSeconds = 0
            lastBotMessage = currentStep?.botMessage; lastBotStepID = currentStep?.id
            if let step = currentStep, step.kind == .pause {
                pauseStageStartedUptime = uptime(); pauseRemainingSeconds = Int(ceil(step.requiredPauseSeconds))
            }
            if currentStep == nil { finish() }
        } else { enterStep() }
    }

    func developerNext(preserveAutoPreview: Bool = false) {
        guard isDeveloperReview, let variant else { return }
        if !preserveAutoPreview, status == .running, canSubmit, currentStep?.kind != .administrative {
            developerStopPreview()
            if let repair = radiogramRepair,
               let radiogram = variant.radiograms.first(where: { $0.id == currentStep?.radiogramID }) {
                switch repair.part {
                case .header: inputText = Task5RepeatRequest.header.reply(for: radiogram) ?? ""
                case .group(let index): inputText = radiogram.groups[index] + " К"
                case .all: inputText = radiogram.wireText
                }
            } else if let receipt = receptionReceipt {
                receptionDraft = currentStep?.expectedMessages.first ?? ""
                inputText = receipt.expectedMessages.first ?? ""
            } else { inputText = currentStep?.expectedMessages.first ?? "" }
            submit()
            return
        }
        let next = developerStages.compactMap { step in variant.steps.firstIndex(where: { $0.id == step.id }) }
            .first(where: { $0 > currentStepIndex }) ?? variant.steps.count
        developerJump(to: next, preserveAutoPreview: preserveAutoPreview)
    }

    func developerInspectStage(to index: Int) {
        guard isDeveloperReview else { return }
        developerStageIsFrozen = true
        developerJump(to: index)
    }

    func developerRunStage() {
        guard isDeveloperReview else { return }
        developerStageIsFrozen = false
        developerJump(to: currentStepIndex)
    }

    func developerBack() {
        guard isDeveloperReview, let variant else { return }
        let previous = developerStages.compactMap { step in variant.steps.firstIndex(where: { $0.id == step.id }) }
            .last(where: { $0 < currentStepIndex }) ?? 0
        developerInspectStage(to: previous)
    }

    func developerFreeze() {
        guard isDeveloperReview else { return }
        developerStopPreview()
        developerStageIsFrozen = true
    }

    func developerStartPreview(interval: TimeInterval = 3) {
        guard isDeveloperReview, isEnabled, audio.isReady else { return }
        developerStopPreview()
        developerStageIsFrozen = false
        developerJump(to: variant != nil && isSessionActive ? currentStepIndex : 0)
        isDeveloperAutoPreview = true
        developerPreviewTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(max(0.05, interval))) } catch { return }
                guard let self, isDeveloperAutoPreview, isEnabled else { return }
                developerNext(preserveAutoPreview: true)
                if !isSessionActive { developerStopPreview(); return }
            }
        }
    }

    func developerStopPreview() {
        developerPreviewTask?.cancel(); developerPreviewTask = nil; isDeveloperAutoPreview = false
        if isDeveloperReview {
            cancelPlayback()
            if status == .playing { status = .running }
        }
    }

    func developerControllerClosed() {
        guard isDeveloperReview else { return }
        // Do not cancel a manually started transmission or change its phase.
        // The controller owns only the automatic-navigation timer.
        developerPreviewTask?.cancel(); developerPreviewTask = nil; isDeveloperAutoPreview = false
    }

    func developerShowGroupError() {
        guard isDeveloperReview, let variant,
              let index = variant.steps.firstIndex(where: { $0.direction == .transmit && $0.bodyGroups > 0 }),
              let id = variant.steps[index].radiogramID else { return }
        developerInspectStage(to: index)
        guard let radiogram = self.variant?.radiograms.first(where: { $0.id == id }) else { return }
        var groups = radiogram.groups
        groups[0] = groups[0] == "00000" ? "11111" : "00000"
        inputText = radiogram.header + " = \(radiogram.urgencyCode) \(radiogram.address) = " + groups.joined(separator: " ") + " К"
        submit()
    }

    // MARK: Key input — no second audio engine

    func keyDown(from source: KeySource) {
        guard isEnabled, canSubmit, currentStep?.kind != .administrative, audio.isReady, !rhythm.isDown else { return }
        if let step = currentStep, step.kind == .signal, step.id.hasSuffix("-second"), !measuredSignalSecondParts.contains(step.id) {
            let signalID = String(step.id.dropLast("-second".count))
            if let firstRelease = firstSignalRelease[signalID] {
                let gap = max(0, uptime() - firstRelease)
                guard gap >= Task5Signal.pauseSeconds else { errorMessage = "Выдержите 10 секунд между частями"; return }
                measuredSignalSecondParts.insert(step.id)
                log("signalKeyGap", "Интервал ключа: \(String(format: "%.2f", gap)) с")
            }
        }
        if startsNewTransmission {
            inputText = ""; buffer = ""; previewCharacter = ""; startsNewTransmission = false
            errorMessage = nil; lastCheckFeedback = nil
        }
        if source != .hardware { audio.setLocalKey(true) }
        lastSource = source; keyPressedUptime = uptime(); gapTask?.cancel(); keyedStepID = currentStep?.id
        rhythm.unit = 6.0 / Double(configuration.keySpeed.clamped(to: 30...150))
        rhythm.press(at: now())
    }

    func keyUp(from source: KeySource) {
        guard rhythm.isDown, source == lastSource else { return }
        if lastSource != .hardware { audio.setLocalKey(false) }
        let released = now()
        lastKeyReleaseUptime = uptime()
        _ = rhythm.release(at: released)
        let duration = max(0, uptime() - (keyPressedUptime ?? uptime()))
        let unit = 6.0 / Double(configuration.keySpeed.clamped(to: 30...150))
        correctionNotice = nil
        buffer += duration >= unit * 2 ? "-" : "."
        previewCharacter = decode(buffer)
        watchKeyGaps(unit: unit)
    }

    func releaseKey() {
        if rhythm.isDown { keyUp(from: lastSource ?? .keyboard) }
    }

    private func watchKeyGaps(unit: TimeInterval) {
        gapTask?.cancel()
        gapTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled, let self, !rhythm.isDown, let released = lastKeyReleaseUptime else { return }
                let gap = max(0, uptime() - released)
                if !buffer.isEmpty && gap >= unit * 2.5 { commitPendingCharacter() }
                if buffer.isEmpty && gap >= unit * 8 {
                    if !inputText.isEmpty && !inputText.hasSuffix(" ") { inputText += " " }
                    if canSubmit, !startsNewTransmission, let step = currentStep, let variant {
                        let target = receptionReceipt ?? step
                        let normalized = Task5Validator.normalizedTransmission(inputText, for: target, variant: variant)
                        let completeMessage = (target.kind == .transmit || target.kind == .receipt || target.kind == .signal)
                            && Task5Validator.validate(normalized, for: target, variant: variant).isCorrect
                        let words = Task5Validator.tokens(normalized)
                        let controlMessage = words.last == "К" && validServiceRequest(inputText)
                        let expected = (receptionReceipt ?? step).expectedMessages.map(Task5Validator.tokens)
                        // A K inside a longer exchange (ЩСА 3 К ЩСА?) is not
                        // its terminator, even if the preceding rating was mistyped.
                        let internalK = expected.contains {
                            words.count < $0.count && !words.isEmpty && $0[words.count - 1] == "К"
                        }
                        let finishedRadioMessage = usesRadioFlow && words.last == "К" && !internalK
                        if completeMessage || controlMessage || finishedRadioMessage {
                            submit()
                            return
                        }
                        // Some approved exchanges have no final K. Give the
                        // operator time to continue or send the error signal,
                        // then check a full-length incorrect reply as well.
                        let unfinishedPrefix = expected.contains {
                            $0.joined(separator: " ").hasPrefix(words.joined(separator: " "))
                        }
                        let fullReplyWithoutK = usesRadioFlow && !expected.isEmpty && !words.isEmpty
                            && expected.allSatisfy { $0.last != "К" }
                            && expected.contains { words.count >= $0.count }
                            && !unfinishedPrefix
                        if fullReplyWithoutK {
                            if gap >= max(3, unit * 16) { submit(); return }
                            continue
                        }
                        // Silence is not an error or an end-of-message. Explain
                        // what is pending without clearing input or making the
                        // bot interrupt a student who is still composing.
                        if usesRadioFlow && !words.isEmpty {
                            if gap < max(6, unit * 24) { continue }
                            let detail: String
                            if Task5Validator.validate(normalized + " К", for: target, variant: variant).isCorrect {
                                detail = "Осталось передать К. Ввод сохранён."
                            } else if normalized.contains("�") {
                                detail = "Есть нераспознанный знак. Дайте перебой (8 точек) и повторите сообщение."
                            } else if unfinishedPrefix || internalK {
                                detail = "Сообщение не закончено. Продолжайте передачу; ввод сохранён."
                            } else {
                                let check = Task5Validator.validate(normalized, for: target, variant: variant)
                                detail = (check.message ?? "Не удалось завершить разбор.")
                                    + " Продолжите передачу или дайте перебой (8 точек) и повторите."
                            }
                            correctionNotice = detail
                            log("waitingForTransmission", detail + " Принято: «\(inputText.trimmingCharacters(in: .whitespaces))»")
                            persist()
                        }
                    }
                    return
                }
            }
        }
    }

    private func decode(_ pattern: String) -> String {
        if pattern == "-----" { return "0" }
        return catalog.decode(pattern, alphabet: .ru, overrides: settings.customOverrides)
    }

    private func commitPendingCharacter() {
        guard !buffer.isEmpty else { return }
        // Eight or more uninterrupted dots are the error signal, not text.
        if buffer.count >= 8 && buffer.allSatisfy({ $0 == "." }) {
            let radiogramGroup = currentStep?.direction == .transmit && (currentStep?.bodyGroups ?? 0) > 0
            if radiogramGroup {
                inputText = Task5RadiogramRepair.removingLastGroup(from: inputText)
                log("operatorCorrection", "Перебой: отменена последняя группа радиограммы")
            } else {
                log("operatorCorrection", "Перебой: отменена передача «\(inputText)»; ввод начат заново")
                inputText = ""
            }
            buffer = ""; previewCharacter = ""
            errorMessage = nil; lastCheckFeedback = nil; startsNewTransmission = false
            lastTransmissionText = ""
            correctionNotice = radiogramGroup ? "Перебой принят. Передайте группу заново." : "Перебой принят. Передайте сообщение заново."
            persist()
            return
        }
        lastTransmissionText = ""
        inputText += decode(buffer)
        buffer = ""; previewCharacter = ""
    }

    private func validServiceRequest(_ text: String) -> Bool {
        if Task5Validator.waitMinutes(text) != nil, currentStep.map(Task5Validator.isWaitCommand) != true,
           !pendingCodeMeanings.isEmpty, currentStep?.direction == .transmit || receptionReceipt != nil { return true }
        var words = Task5Validator.tokens(text)
        if words.last == "К" { words.removeLast() }
        guard let command = words.first else { return false }
        if command == "ЩРС" || command == "ЩРЩ" {
            return words.count == 1 || (words.count == 2 && (Int(words[1]).map { (6...30).contains($0) } ?? false))
        }
        guard canRepeat, let request = Task5RepeatRequest.parse(text) else { return false }
        if let id = currentStep?.radiogramID, let rg = variant?.radiograms.first(where: { $0.id == id && $0.direction == .receive }) {
            return request.reply(for: rg) != nil
        }
        return request == .all
    }

    private func handleServiceRequest(_ text: String) -> Bool {
        if Task5Validator.waitMinutes(text) != nil, currentStep.map(Task5Validator.isWaitCommand) != true,
           !pendingCodeMeanings.isEmpty, currentStep?.direction == .transmit || receptionReceipt != nil {
            if let step = currentStep {
                attempts.append(Task5Attempt(id: UUID(), date: now(), stepID: step.id, input: text,
                    correct: true, errors: 0, aided: false, selfChecked: false, inputMethod: "service"))
            }
            lastTransmissionText = text
            inputText = ""; buffer = ""; previewCharacter = ""
            log("codesAcknowledged", "Принята дополнительная квитанция на расшифровку кодов")
            persist()
            return true
        }
        var words = Task5Validator.tokens(text)
        if variant?.profileID == "task5.photos.v8.final-k",
           let command = words.first, ["РПТ", "ЩРС", "ЩРЩ"].contains(command), words.last != "К" {
            errorMessage = "Завершите служебную команду знаком К."
            return true
        }
        if words.last == "К" { words.removeLast() }
        guard let command = words.first else { return false }
        if command == "ЩРС" || command == "ЩРЩ" {
            // The selected photographic profile uses groups/min; a group has five
            // signs. This is explicit conversion, never a WPM interpretation.
            if words.count == 1 {
                configuration.botSpeed = (configuration.botSpeed + (command == "ЩРС" ? -5 : 5)).clamped(to: 30...150)
            } else if words.count == 2, let groups = Int(words[1]), (6...30).contains(groups) {
                configuration.botSpeed = groups * 5
            } else { errorMessage = "Скорость указывается в группах/мин: 6–30"; return true }
            audio.updateSettings(effectiveAudioSettings)
            inputText = ""; log("speed", "Скорость корреспондента: \(configuration.botSpeed) зн/мин"); persist(); return true
        }
        guard command == "РПТ", canRepeat, let original = lastBotMessage else { return false }
        guard let request = Task5RepeatRequest.parse(text) else {
            errorMessage = "Укажите РПТ, ПБЛ или границы АА/АБ/БН"; return true
        }
        let repeated: String
        if let id = currentStep?.radiogramID,
           let rg = variant?.radiograms.first(where: { $0.id == id && $0.direction == .receive }) {
            guard let fragment = request.reply(for: rg) else {
                errorMessage = "В указанном диапазоне нет групп"; return true
            }
            repeated = fragment
        } else if request == .all { repeated = original }
        else { errorMessage = "Для этого сообщения доступен полный повтор"; return true }
        repeatCount += 1; log("repeat", "Повтор запрошенного фрагмента")
        inputText = ""; playBot(repeated, repeating: true); persist(); return true
    }
}
