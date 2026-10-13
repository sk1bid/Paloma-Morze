import Foundation
import Observation

enum TransmissionMode: String, CaseIterable, Identifiable {
    case free
    case radiogram

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Свободная передача"
        case .radiogram: "Радиограмма"
        }
    }
}

enum RadiogramCharset: String, CaseIterable, Identifiable {
    case letters
    case digits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .letters: "Буквы"
        case .digits: "Цифры"
        }
    }
}

enum KeySource: Equatable {
    case keyboard
    case pointer
    case hardware
}

/// A radiogram being keyed: the text is shown in portions of 25 signs.
struct RadiogramRun: Equatable {
    static let portionSize = 25

    var sequence: [String]
    var portionIndex = 0
    var targetIndex = 0
    /// Per sign of the current portion: `true` correct, `false` keyed wrong at least once.
    var marks: [Int: Bool] = [:]
    var errors = 0
    var startedAt: Date

    var portionCount: Int { max(1, Int((Double(sequence.count) / Double(Self.portionSize)).rounded(.up))) }

    var portion: [String] {
        let start = portionIndex * Self.portionSize
        guard start < sequence.count else { return [] }
        return Array(sequence[start..<min(start + Self.portionSize, sequence.count)])
    }

    var completed: Int { portionIndex * Self.portionSize + targetIndex }
}

struct RadiogramReport: Equatable, Identifiable {
    let id = UUID()
    var total: Int
    var errors: Int
    var elapsed: TimeInterval

    var accuracy: Int {
        guard total > 0 else { return 100 }
        return max(0, Int((Double(total - errors) / Double(total) * 100).rounded()))
    }

    /// Characters per minute and the matching words per minute (5 signs per word).
    var charactersPerMinute: Int? {
        guard elapsed >= 1 else { return nil }
        return Int((Double(total) / (elapsed / 60)).rounded())
    }
}

/// Transmission practice: decodes local or hardware key presses into text,
/// and checks keyed radiograms. Sidetone comes from the engine (`K local`).
@Observable
final class TransmissionSession {
    let catalog: MorseCatalog
    let rhythm = KeyRhythm()
    @ObservationIgnored private let audio: AudioCoordinator
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let history: HistoryStore
    /// Input measurement clock only; audible timing remains in the C++ helper.
    @ObservationIgnored private let now: () -> Date

    var mode: TransmissionMode = .free {
        didSet {
            guard mode != oldValue else { return }
            stopRadiogram()
            commitPendingCharacter()
        }
    }

    var isEnabled = true { didSet { if !isEnabled { releaseKey() } } }
    private(set) var elapsedSeconds = 0
    @ObservationIgnored private var reportTimer: Task<Void, Never>?
    private(set) var isPaused = false
    private(set) var buffer = ""
    private(set) var previewCharacter = ""
    private(set) var hint = ""
    private(set) var decodedText = ""
    private(set) var lastSource: KeySource?

    var charset: RadiogramCharset = .letters
    var groupCount = 5
    private(set) var radiogram: RadiogramRun?
    var report: RadiogramReport?

    @ObservationIgnored var onKeyStateChange: ((Bool) -> Void)?
    @ObservationIgnored private var gapTask: Task<Void, Never>?
    @ObservationIgnored private var hardwareObserver: UUID?

    init(catalog: MorseCatalog, audio: AudioCoordinator, settings: SettingsStore, history: HistoryStore, now: @escaping () -> Date = { .now }) {
        self.catalog = catalog
        self.audio = audio
        self.settings = settings
        self.history = history
        self.now = now
        hardwareObserver = audio.observeHardwareKey { [weak self] pressed in
            guard let self else { return }
            pressed ? keyDown(from: .hardware) : keyUp(from: .hardware)
        }
    }

    func matchesTransmissionKey(_ character: Character) -> Bool { settings.matchesTransmissionKey(character) }

    var alphabet: Alphabet { settings.alphabet }
    var transmissionKeyLabel: String { settings.transmissionKeyLabel }
    var isKeyDown: Bool { rhythm.isDown }
    var hardware: HardwareKeyState { audio.hardware }
    var hasSidetone: Bool { audio.isReady }
    var isRadiogramRunning: Bool { radiogram != nil }

    // MARK: Keying

    func keyDown(from source: KeySource) {
        guard isEnabled, !isPaused, !rhythm.isDown else { return }
        if source != .hardware { audio.setLocalKey(true) }
        lastSource = source
        gapTask?.cancel()
        rhythm.press(at: now())
        onKeyStateChange?(true)
    }

    func keyUp(from source: KeySource) {
        guard rhythm.isDown else { return }
        if source != .hardware { audio.setLocalKey(false) }
        guard let kind = rhythm.release(at: now()) else { return }
        onKeyStateChange?(false)
        buffer += kind == .dot ? "." : "-"
        previewCharacter = catalog.decode(buffer, alphabet: alphabet, overrides: settings.customOverrides)
        hint = catalog.mnemonic(for: previewCharacter, alphabet: alphabet, overrides: settings.customOverrides)
        watchGaps()
    }

    /// Safety release when the view disappears or the window loses focus.
    func releaseKey() {
        if rhythm.isDown { keyUp(from: lastSource ?? .keyboard) }
    }

    func togglePause() {
        releaseKey()
        commitPendingCharacter()
        isPaused.toggle()
    }

    func clear() {
        releaseKey()
        gapTask?.cancel()
        decodedText = ""
        buffer = ""
        previewCharacter = ""
        hint = ""
        rhythm.clear()
    }

    // MARK: Radiogram

    func toggleRadiogram() {
        radiogram == nil ? startRadiogram() : stopRadiogram()
    }

    func startRadiogram() {
        releaseKey()
        gapTask?.cancel()
        let pool = charset == .digits ? catalog.digits : catalog.letters(for: alphabet)
        let sequence = SequenceGenerator.generate(pool: pool, count: groupCount * 5, groupGaps: false)
        guard !sequence.isEmpty else { return }
        report = nil
        isPaused = false
        rhythm.clear()
        buffer = ""
        previewCharacter = ""
        elapsedSeconds = 0
        radiogram = RadiogramRun(sequence: sequence, startedAt: now())
        reportTimer?.cancel()
        reportTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let run = radiogram else { return }
                elapsedSeconds = Int(now().timeIntervalSince(run.startedAt).rounded())
            }
        }
    }

    func stopRadiogram() {
        reportTimer?.cancel()
        radiogram = nil
    }

    func retryRadiogram() {
        report = nil
        startRadiogram()
    }

    // MARK: Decoding

    private func watchGaps() {
        gapTask?.cancel()
        gapTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled, !rhythm.isDown, let released = rhythm.lastRelease else { return }
                let gap = now().timeIntervalSince(released)
                if !buffer.isEmpty, gap > KeyTiming.characterGap {
                    commitPendingCharacter()
                }
                if buffer.isEmpty {
                    let needsSpace = mode == .free && !decodedText.isEmpty && !decodedText.hasSuffix(" ")
                    guard needsSpace else { return }
                    if gap > KeyTiming.wordGap {
                        decodedText += " "
                        hint = ""
                        return
                    }
                }
            }
        }
    }

    private func commitPendingCharacter() {
        guard !buffer.isEmpty else { return }
        let character = catalog.decode(buffer, alphabet: alphabet, overrides: settings.customOverrides)
        buffer = ""
        previewCharacter = ""

        if radiogram != nil {
            check(character)
            return
        }
        decodedText += character
        hint = catalog.qCodeMeaning(endingWith: decodedText) ?? catalog.mnemonic(for: character, alphabet: alphabet, overrides: settings.customOverrides)
    }

    /// Compares patterns, not glyphs, so a keyed dash satisfies Paloma's zero.
    private func check(_ character: String) {
        guard var run = radiogram else { return }
        let portion = run.portion
        guard run.targetIndex < portion.count else { return }
        let target = portion[run.targetIndex]
        hint = ""

        if catalog.patterns(for: character, overrides: settings.customOverrides) == catalog.patterns(for: target, overrides: settings.customOverrides) {
            run.marks[run.targetIndex] = true
            run.targetIndex += 1
            if run.targetIndex >= portion.count {
                run.portionIndex += 1
                run.targetIndex = 0
                run.marks = [:]
                if run.portion.isEmpty {
                    finish(run)
                    return
                }
            }
        } else {
            run.marks[run.targetIndex] = false
            run.errors += 1
        }
        radiogram = run
    }

    private func finish(_ run: RadiogramRun) {
        reportTimer?.cancel()
        let elapsed = Double(elapsedSeconds)
        radiogram = nil
        report = RadiogramReport(total: run.sequence.count, errors: run.errors, elapsed: elapsed)
        history.add(SessionRecord(
            date: .now,
            kind: .transmission,
            title: "Радиограмма · \(charset.title.lowercased())",
            detail: "\(run.sequence.count / 5) групп",
            total: run.sequence.count,
            errors: run.errors,
            duration: elapsed))
    }
}

#if DEBUG
extension TransmissionSession {
    func applyPreview(
        text: String = "",
        buffer: String = "",
        hint: String = "",
        paused: Bool = false,
        source: KeySource? = nil,
        radiogram: RadiogramRun? = nil
    ) {
        decodedText = text
        self.buffer = buffer
        previewCharacter = buffer.isEmpty ? "" : catalog.decode(buffer, alphabet: alphabet, overrides: settings.customOverrides)
        self.hint = hint
        isPaused = paused
        lastSource = source
        self.radiogram = radiogram
    }
}
#endif
