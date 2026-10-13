import Foundation

/// PREVIEW / DEMO ONLY. Emits engine-shaped events paced by `EngineTiming` so
/// the interface can be exercised without the C++ engine. It produces no sound,
/// never reports a connected USB key and is always labelled as demo in the UI.
/// The real engine defines all durations; this adapter is replaced by it.
final class DemoAudioService: AudioService {
    let kind = AudioAdapterKind.demo
    let events: AsyncStream<AudioEvent>
    private let continuation: AsyncStream<AudioEvent>.Continuation

    private var settings = AudioSettings()
    private var nextID = 1
    private var tasks: [PlaybackRequestID: Task<Void, Never>] = [:]
    private let startsReady: Bool

    init(startsReady: Bool = true) {
        self.startsReady = startsReady
        (events, continuation) = AsyncStream.makeStream(of: AudioEvent.self)
    }

    func startEngine() {
        continuation.yield(.engine(.starting))
        continuation.yield(.hardware(.disconnected))
        if startsReady {
            continuation.yield(.engine(.ready(sampleRate: 48_000)))
        }
    }

    func stopEngine() {
        stopAll()
        continuation.yield(.engine(.stopped))
    }

    func updateSettings(_ settings: AudioSettings) {
        self.settings = settings
    }

    func play(_ tokens: [PlaybackToken], spacing: SpacingMode) -> PlaybackRequestID {
        let id = PlaybackRequestID(rawValue: nextID)
        nextID += 1
        let timing = EngineTiming(settings: settings, spacing: spacing)
        let continuation = continuation

        // Same order of events as the engine plan: CHAR after the gap that precedes
        // it, PULSE on/off per element, nothing for a group gap token.
        tasks[id] = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now
            func wait(_ samples: Int) async throws {
                deadline = deadline.advanced(by: .seconds(EngineTiming.seconds(samples)))
                try await Task.sleep(until: deadline, clock: clock)
            }
            continuation.yield(.playback(id, .started(totalFrames: 0)))
            do {
                var hasSign = false
                var groupGap = false
                for (index, token) in tokens.enumerated() {
                    if token.isGroupGap {
                        groupGap = true
                        continue
                    }
                    if hasSign { try await wait(timing.gap(group: groupGap)) }
                    groupGap = false
                    continuation.yield(.playback(id, .token(index)))
                    for (letterIndex, pattern) in token.patterns.enumerated() {
                        if letterIndex > 0 { try await wait(timing.gap(group: false)) }
                        for (elementIndex, element) in pattern.enumerated() {
                            if elementIndex > 0 { try await wait(timing.dot) }
                            continuation.yield(.playback(id, .pulse(element == "-" ? .dash : .dot)))
                            try await wait(element == "-" ? timing.dash : timing.dot)
                            continuation.yield(.playback(id, .pulse(.none)))
                        }
                    }
                    hasSign = true
                }
                try await wait(timing.dot)
                continuation.yield(.playback(id, .finished(cancelled: false)))
            } catch {
                continuation.yield(.playback(id, .pulse(.none)))
                continuation.yield(.playback(id, .finished(cancelled: true)))
            }
            self?.tasks[id] = nil
        }
        return id
    }

    func cancel(_ id: PlaybackRequestID) {
        tasks[id]?.cancel()
    }

    func stopAll() {
        tasks.values.forEach { $0.cancel() }
    }

    func setLocalKey(_ pressed: Bool) {}
    func setRemoteKey(_ pressed: Bool) {}

}

/// PREVIEW ONLY. Element and gap durations of the released engine
/// (ui/native/morse_audio.hpp, `Settings::dot/dash/gap`), in 11025 Hz reference
/// samples, so demo pulses keep the pace of the real sound. The engine stays the
/// source of truth; this produces no audio and is replaced by the live adapter.
nonisolated struct EngineTiming {
    static let referenceRate = 11025.0
    private static let calibration = [188, 161, 140, 124, 111, 93, 92, 91, 70, 65, 60, 62, 58,
                                      43, 56, 45, 39, 37, 41, 33, 41, 34, 25, 23, 31]

    var speed: Int
    var ratio: Int
    var pause: Int
    var spacing: SpacingMode

    init(settings: AudioSettings, spacing: SpacingMode) {
        speed = settings.speed
        ratio = Int((settings.dashRatio * 10).rounded())
        pause = Int((settings.pauseFactor * 10).rounded())
        self.spacing = spacing
    }

    var dot: Int { Self.roundEven(66120.0 / Double(speed)) }
    var dash: Int { Self.roundEven(Double(dot * ratio) / 10) }

    func gap(group: Bool) -> Int {
        let c = Self.calibration[speed / 5 - 6]
        let mul = group ? 3 : 1
        let ms: Int = switch spacing {
        case .lessonOne: group ? 1500 : 500
        case .errorRepeat: mul * 2 * c * pause / 10
        case .text: Int(Double(mul * pause * dot) * 1000.0 / 110250.0) + c
        }
        return dot + Self.roundEven(Double(ms) * Self.referenceRate / 1000)
    }

    static func seconds(_ samples: Int) -> Double { Double(samples) / referenceRate }

    private static func roundEven(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }
}
