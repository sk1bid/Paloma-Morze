import Foundation
@testable import PalomaMorse

/// Scripted engine for model tests: records requests, emits events on demand.
final class ScriptedAudioService: AudioService {
    let kind = AudioAdapterKind.live
    let events: AsyncStream<AudioEvent>
    private let continuation: AsyncStream<AudioEvent>.Continuation
    private var nextID = 1

    private(set) var played: [(id: PlaybackRequestID, tokens: [PlaybackToken], spacing: SpacingMode)] = []
    private(set) var cancelled: [PlaybackRequestID] = []
    private(set) var localKey: [Bool] = []
    private(set) var remoteKey: [Bool] = []
    private(set) var muted: [Bool] = []
    private(set) var notices: [Bool] = []

    init() {
        (events, continuation) = AsyncStream.makeStream(of: AudioEvent.self)
    }

    func emit(_ event: AudioEvent) { continuation.yield(event) }
    func emit(_ id: PlaybackRequestID, _ event: PlaybackEvent) { continuation.yield(.playback(id, event)) }

    var lastID: PlaybackRequestID { played.last!.id }

    func startEngine() { continuation.yield(.engine(.ready(sampleRate: 48_000))) }
    func stopEngine() {}
    func updateSettings(_ settings: AudioSettings) {}

    func play(_ tokens: [PlaybackToken], spacing: SpacingMode) -> PlaybackRequestID {
        let id = PlaybackRequestID(rawValue: nextID)
        nextID += 1
        played.append((id, tokens, spacing))
        return id
    }

    func cancel(_ id: PlaybackRequestID) { cancelled.append(id) }
    func stopAll() {}
    func setLocalKey(_ pressed: Bool) { localKey.append(pressed) }
    func setRemoteKey(_ pressed: Bool) { remoteKey.append(pressed) }
    func setSidetoneMuted(_ value: Bool) { muted.append(value) }
    func notifyConnection(_ value: Bool) { notices.append(value) }
}

/// Lets the coordinator's stream consumer run.
func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

/// Tests are hosted in the app, so the bundled catalog symlink is in `Bundle.main`.
func loadCatalog() throws -> MorseCatalog {
    try MorseCatalog.load(from: .main)
}
