import Foundation

// Swift form of shared/contracts/UI-SERVICE.txt (AudioService) and
// audio-protocol-v1. Views never talk to an AudioService directly; they go
// through `AudioCoordinator`. The live Process/Pipe adapter is owned by Codex
// and only has to conform to `AudioService`.

struct PlaybackRequestID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: Int
    var description: String { "#\(rawValue)" }
}

enum Pulse: Equatable, Sendable {
    case none
    case dot
    case dash
}

/// Protocol `spacing` field of the `P` command.
enum SpacingMode: Int, Sendable {
    case text = 0
    case lessonOne = 1
    case errorRepeat = 2
}

/// One UI token of a `P` command. `patterns` holds one entry per letter
/// (several for a Q-code). An empty list is the `/` group-space token.
struct PlaybackToken: Equatable, Sendable {
    let display: String
    let patterns: [String]

    var isGroupGap: Bool { patterns.isEmpty }

    static let groupGap = PlaybackToken(display: " ", patterns: [])
}

enum EngineState: Equatable, Sendable {
    case notStarted
    case starting
    case ready(sampleRate: Int)
    case stopped
    case failed(String)
    /// No adapter is bundled in this build.
    case unavailable(String)
}

/// Physical USB key state, parsed from engine lines by the adapter.
enum HardwareKeyState: Equatable, Sendable {
    case unknown
    case searching
    case connected(String)
    case disconnected
    case reconnecting
    case permissionDenied(String)

    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }
}

enum PlaybackEvent: Equatable, Sendable {
    case started(totalFrames: Int)
    /// Index into the token list submitted with `play`, including group gaps.
    case token(Int)
    case pulse(Pulse)
    case finished(cancelled: Bool)
    case failed(String)
}

enum AudioEvent: Equatable, Sendable {
    case engine(EngineState)
    case hardware(HardwareKeyState)
    /// Physical key press/release. The C++ engine already produces the sidetone;
    /// clients must not echo it back as `K local`.
    case hardwareKey(pressed: Bool)
    case playback(PlaybackRequestID, PlaybackEvent)
}

enum AudioAdapterKind: Equatable, Sendable {
    case live
    /// Deterministic stand-in: emits engine-like events, produces no sound.
    case demo
    case unavailable
}

protocol AudioService: AnyObject {
    var kind: AudioAdapterKind { get }
    /// Single-consumer stream. `AudioCoordinator` is the only reader.
    var events: AsyncStream<AudioEvent> { get }

    func startEngine()
    func stopEngine()
    /// Live parameters (`S`) apply immediately; sequence parameters apply to the next `play`.
    func updateSettings(_ settings: AudioSettings)
    func play(_ tokens: [PlaybackToken], spacing: SpacingMode) -> PlaybackRequestID
    func cancel(_ id: PlaybackRequestID)
    func stopAll()
    func setLocalKey(_ pressed: Bool)
    func setRemoteKey(_ pressed: Bool)
    func setSidetoneMuted(_ muted: Bool)
    func notifyConnection(_ connected: Bool)
}

extension AudioService {
    func setSidetoneMuted(_ muted: Bool) {}
    func notifyConnection(_ connected: Bool) {}
}
