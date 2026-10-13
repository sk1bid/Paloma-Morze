import Foundation

/// Used when no engine adapter is bundled. It never pretends to be ready,
/// so Start stays disabled with an explanation.
final class UnavailableAudioService: AudioService {
    let kind = AudioAdapterKind.unavailable
    let events: AsyncStream<AudioEvent>
    private let continuation: AsyncStream<AudioEvent>.Continuation
    private var nextID = 1

    static let reason = "Звуковой движок не подключён к этой сборке"

    init() {
        (events, continuation) = AsyncStream.makeStream(of: AudioEvent.self)
    }

    func startEngine() {
        continuation.yield(.engine(.unavailable(Self.reason)))
        continuation.yield(.hardware(.unknown))
    }

    func stopEngine() {}
    func updateSettings(_ settings: AudioSettings) {}

    func play(_ tokens: [PlaybackToken], spacing: SpacingMode) -> PlaybackRequestID {
        let id = PlaybackRequestID(rawValue: nextID)
        nextID += 1
        continuation.yield(.playback(id, .failed(Self.reason)))
        return id
    }

    func cancel(_ id: PlaybackRequestID) {}
    func stopAll() {}
    func setLocalKey(_ pressed: Bool) {}
    func setRemoteKey(_ pressed: Bool) {}
}
