import Foundation
import Observation

enum SignInPhase: Equatable {
    case idle
    case submitting
    case failed(String)
}

enum LobbyPhase: Equatable {
    case loading
    case loaded([RadioRoom])
    case failed(String)
}

enum RoomPhase: Equatable {
    case waitingForCorrespondent
    case readyToLaunch
    case waitingForOwner
    case live
}

/// Simplex channel: anyone may key at any time; overlap is a collision.
enum ChannelState: Equatable {
    case clear
    case transmitting
    case receiving
    case collision
}

struct RoomSession: Equatable {
    var room: RadioRoom
    var participants: [RadioParticipant]
    var owner: String
    var phase: RoomPhase
}

struct ConnectionLoss: Equatable {
    var reason: String
    var attempt: Int
    var roomName: String?
}

/// The four Radio presentation states are mutually exclusive.
enum RadioScreen: Equatable {
    case signedOut(SignInPhase)
    case lobby(LobbyPhase)
    case room(RoomSession)
    case connectionLost(ConnectionLoss)
}

@Observable
final class RadioModel {
    private(set) var screen: RadioScreen = .signedOut(.idle)
    private(set) var callsign: String?
    private(set) var onlineCount: Int?
    private(set) var latency: Int?
    private(set) var remoteKeyDown = false
    private(set) var actionError: String?
    func dismissActionError() { actionError = nil }
    @ObservationIgnored private var localKeyIsHardware = false

    let localRhythm = KeyRhythm()
    let remoteRhythm = KeyRhythm()

    @ObservationIgnored private let network: any NetworkService
    @ObservationIgnored private let audio: AudioCoordinator
    @ObservationIgnored private let settings: SettingsStore?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var hardwareObserver: UUID?

    init(network: any NetworkService, audio: AudioCoordinator, settings: SettingsStore? = nil) {
        self.settings = settings
        self.network = network
        self.audio = audio
        let stream = network.events
        listenTask = Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
        hardwareObserver = audio.observeHardwareKey { [weak self] pressed in
            guard let self, isLive else { return }
            pressed ? keyDown(fromHardware: true) : keyUp(fromHardware: true)
        }
    }

    deinit {
        listenTask?.cancel()
    }

    func matchesTransmissionKey(_ character: Character) -> Bool { settings?.matchesTransmissionKey(character) ?? (character == " ") }

    var transmissionKeyLabel: String { settings?.transmissionKeyLabel ?? "Пробел" }

    var adapterKind: NetworkAdapterKind { network.kind }
    var isNetworkAvailable: Bool { network.kind != .unavailable }

    var isLive: Bool {
        if case .room(let session) = screen, session.phase == .live { true } else { false }
    }

    var correspondent: String? {
        guard case .room(let session) = screen else { return nil }
        return session.participants.first { $0.callsign.caseInsensitiveCompare(callsign ?? "") != .orderedSame }?.callsign
    }

    var channel: ChannelState {
        switch (localRhythm.isDown, remoteKeyDown) {
        case (true, true): .collision
        case (true, false): .transmitting
        case (false, true): .receiving
        case (false, false): .clear
        }
    }

    // MARK: Actions

    func signIn(callsign: String, password: String, register: Bool) {
        screen = .signedOut(.submitting)
        network.signIn(callsign: callsign, password: password, register: register)
    }

    func signOut() {
        leaveIfNeeded()
        network.signOut()
        callsign = nil
        screen = .signedOut(.idle)
    }

    func refreshRooms() {
        if case .room = screen {} else { screen = .lobby(.loading) }
        network.refreshRooms()
    }

    func createRoom(name: String, password: String?) {
        network.createRoom(name: name, password: password)
    }

    func join(_ room: RadioRoom, password: String?) {
        network.join(roomID: room.id, password: password)
    }

    func leave() {
        leaveIfNeeded()
        refreshRooms()
    }

    func launchSession() {
        network.launchSession()
    }

    func resetSession() {
        if case .room = screen { leave() }
        else if callsign != nil { refreshRooms() }
        else { screen = .signedOut(.idle) }
    }

    func windowClosed() { leaveIfNeeded(); network.suspend() }
    func windowOpened() { if callsign != nil { network.reconnect() } }

    func reconnect() {
        network.reconnect()
    }

    /// Legacy Transmission forwards keying whenever a waiting/live room is joined.
    func transmissionKeyChanged(_ pressed: Bool) {
        guard case .room = screen else { return }
        network.sendKey(pressed: pressed)
    }

    func keyDown(fromHardware: Bool = false) {
        guard isLive, !localRhythm.isDown else { return }
        localKeyIsHardware = fromHardware
        if !fromHardware { audio.setLocalKey(true) }
        localRhythm.press()
        network.sendKey(pressed: true)
    }

    func keyUp(fromHardware: Bool = false) {
        guard localRhythm.isDown else { return }
        if !localKeyIsHardware { audio.setLocalKey(false) }
        localKeyIsHardware = false
        localRhythm.release()
        network.sendKey(pressed: false)
    }

    private func leaveIfNeeded() {
        guard case .room = screen else { return }
        keyUp()
        setRemoteKey(false)
        network.leave()
        audio.service.setSidetoneMuted(false)
    }

    private func setRemoteKey(_ pressed: Bool) {
        guard pressed != remoteKeyDown else { return }
        remoteKeyDown = pressed
        audio.setRemoteKey(pressed)
        audio.service.setSidetoneMuted(isLive && pressed)
        if pressed { remoteRhythm.press() } else { remoteRhythm.release() }
    }

    // MARK: Events

    private func handle(_ event: NetworkEvent) {
        switch event {
        case .signedIn(let name):
            callsign = name
            refreshRooms()
        case .signInFailed(let reason):
            screen = .signedOut(.failed(reason))
        case .signedOut:
            callsign = nil
            screen = .signedOut(.idle)
        case .lobby(let rooms, let online):
            guard callsign != nil else { return }
            onlineCount = online
            if case .room = screen { return }
            if case .connectionLost = screen { return }
            screen = .lobby(.loaded(rooms))
        case .lobbyFailed(let reason):
            guard callsign != nil else { return }
            if case .room = screen { actionError = reason; return }
            if case .connectionLost = screen { return }
            screen = .lobby(.failed(reason))
        case .joined(let room):
            localRhythm.clear()
            remoteRhythm.clear()
            screen = .room(RoomSession(room: room, participants: [], owner: room.owner, phase: .waitingForCorrespondent))
        case .joinFailed(let reason):
            guard callsign != nil else { return }
            if case .room = screen { actionError = reason; return }
            screen = .lobby(.failed(reason))
        case .roomUpdated(let participants, let owner):
            guard case .room(var session) = screen else { return }
            session.participants = participants
            session.owner = owner
            if session.phase != .live {
                let amOwner = owner.caseInsensitiveCompare(callsign ?? "") == .orderedSame
                session.phase = participants.count < 2 ? .waitingForCorrespondent : (amOwner ? .readyToLaunch : .waitingForOwner)
            }
            screen = .room(session)
        case .sessionEnded:
            keyUp()
            audio.setLocalKey(false)
            setRemoteKey(false)
            guard case .room(var session) = screen else { return }
            session.phase = session.participants.count < 2 ? .waitingForCorrespondent : (session.owner == callsign ? .readyToLaunch : .waitingForOwner)
            screen = .room(session)
        case .sessionLaunched:
            guard case .room(var session) = screen else { return }
            localRhythm.clear(); remoteRhythm.clear()
            if remoteKeyDown { remoteRhythm.press() }
            audio.service.setSidetoneMuted(remoteKeyDown)
            session.phase = .live
            screen = .room(session)
        case .left:
            setRemoteKey(false)
            guard callsign != nil else { return }
            screen = .lobby(.loading)
            refreshRooms()
        case .remoteKey(_, let pressed):
            guard case .room = screen else { return }
            setRemoteKey(pressed)
        case .latency(let milliseconds):
            latency = milliseconds
        case .connectionLost(let reason):
            keyUp()
            setRemoteKey(false)
            var roomName: String?
            if case .room(let session) = screen { roomName = session.room.name }
            screen = .connectionLost(ConnectionLoss(reason: reason, attempt: 0, roomName: roomName))
        case .reconnecting(let attempt):
            guard case .connectionLost(var loss) = screen else { return }
            loss.attempt = attempt
            screen = .connectionLost(loss)
        case .connectionRestored:
            refreshRooms()
        }
    }

    #if DEBUG
    func applyPreview(screen: RadioScreen, callsign: String?, online: Int? = nil, latency: Int? = nil, remoteKeyDown: Bool = false) {
        self.screen = screen
        self.callsign = callsign
        onlineCount = online
        self.latency = latency
        self.remoteKeyDown = remoteKeyDown
    }
    #endif
}
