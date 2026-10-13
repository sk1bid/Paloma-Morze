import Foundation
import Observation

/// Owns the single `AudioService` event stream and fans it out: observable
/// engine/hardware state for views, and per-request callbacks for sessions.
/// Events for unknown or finished request IDs are dropped here.
@Observable
final class AudioCoordinator {
    let service: any AudioService

    private(set) var engineState: EngineState = .notStarted
    private(set) var hardware: HardwareKeyState = .unknown
    private(set) var hardwareKeyPressed = false

    @ObservationIgnored private var handlers: [PlaybackRequestID: (PlaybackEvent) -> Void] = [:]
    @ObservationIgnored private var keyObservers: [UUID: (Bool) -> Void] = [:]
    @ObservationIgnored private var lastStableConnection: Bool?
    @ObservationIgnored private var listenTask: Task<Void, Never>?

    init(service: any AudioService) {
        self.service = service
        let stream = service.events
        listenTask = Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
    }

    deinit {
        listenTask?.cancel()
    }

    var adapterKind: AudioAdapterKind { service.kind }

    var isReady: Bool {
        if case .ready = engineState { true } else { false }
    }

    /// Why playback cannot start right now, phrased for the UI.
    var unavailableReason: String? {
        switch engineState {
        case .ready: nil
        case .notStarted, .stopped: "Звуковой движок не запущен"
        case .starting: "Звуковой движок запускается…"
        case .failed(let reason): "Ошибка движка: \(reason)"
        case .unavailable(let reason): reason
        }
    }

    func startEngine(with settings: AudioSettings) {
        service.updateSettings(settings)
        service.startEngine()
    }

    func updateSettings(_ settings: AudioSettings) {
        service.updateSettings(settings)
    }

    /// Returns `nil` when the engine is not ready; the caller keeps its idle state.
    @discardableResult
    func play(
        _ tokens: [PlaybackToken],
        spacing: SpacingMode,
        onEvent: @escaping (PlaybackRequestID, PlaybackEvent) -> Void
    ) -> PlaybackRequestID? {
        guard isReady, !tokens.isEmpty else { return nil }
        let id = service.play(tokens, spacing: spacing)
        handlers[id] = { onEvent(id, $0) }
        return id
    }

    func cancel(_ id: PlaybackRequestID) {
        service.cancel(id)
    }

    func stopAll() {
        service.stopAll()
    }

    func setLocalKey(_ pressed: Bool) {
        guard isReady else { return }
        service.setLocalKey(pressed)
    }

    func setRemoteKey(_ pressed: Bool) {
        guard isReady else { return }
        service.setRemoteKey(pressed)
    }

    /// Hardware key observers; the returned token removes the observer.
    func observeHardwareKey(_ observer: @escaping (Bool) -> Void) -> UUID {
        let token = UUID()
        keyObservers[token] = observer
        return token
    }

    func removeHardwareKeyObserver(_ token: UUID) {
        keyObservers[token] = nil
    }

    private func handle(_ event: AudioEvent) {
        switch event {
        case .engine(let state):
            engineState = state
            switch state {
            case .failed(let reason):
                let pending = handlers
                handlers.removeAll()
                pending.values.forEach { $0(.failed(reason)) }
            case .stopped:
                let pending = handlers
                handlers.removeAll()
                pending.values.forEach { $0(.finished(cancelled: true)) }
            default: break
            }
        case .hardware(let state):
            if state != .unknown, state != .searching {
                if let previous = lastStableConnection, previous != state.isConnected { service.notifyConnection(state.isConnected) }
                lastStableConnection = state.isConnected
            }
            hardware = state
            if !state.isConnected, hardwareKeyPressed {
                hardwareKeyPressed = false
                keyObservers.values.forEach { $0(false) }
            }
        case .hardwareKey(let pressed):
            guard pressed != hardwareKeyPressed else { return }
            hardwareKeyPressed = pressed
            keyObservers.values.forEach { $0(pressed) }
        case .playback(let id, let playback):
            guard let handler = handlers[id] else { return }
            switch playback {
            case .finished, .failed:
                handlers[id] = nil
            default:
                break
            }
            handler(playback)
        }
    }
}
