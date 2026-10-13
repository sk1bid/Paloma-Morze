import Foundation

// Swift form of the "Network service" section of UI-SERVICE.txt. The relay is
// Socket.IO; the real client, credentials and reconnection policy belong to the
// integration branch. SocketIONetworkService implements the current relay contract.

struct RadioRoom: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var owner: String
    var isPrivate: Bool
    /// The released lobby API does not include occupancy. Nil means unknown.
    var participantCount: Int?
    var capacity = 2
}

struct RadioParticipant: Identifiable, Hashable, Sendable {
    var id: String { callsign }
    var callsign: String
}

enum NetworkAdapterKind: Equatable, Sendable {
    case live
    case preview
    case unavailable
}

enum NetworkEvent: Equatable, Sendable {
    case signedIn(callsign: String)
    case signInFailed(String)
    case signedOut
    case lobby(rooms: [RadioRoom], online: Int)
    case lobbyFailed(String)
    case joined(RadioRoom)
    case joinFailed(String)
    case roomUpdated(participants: [RadioParticipant], owner: String)
    case sessionEnded
    case sessionLaunched
    case left
    case remoteKey(callsign: String, pressed: Bool)
    case latency(milliseconds: Int)
    case connectionLost(reason: String)
    case reconnecting(attempt: Int)
    case connectionRestored
}

protocol NetworkService: AnyObject {
    var kind: NetworkAdapterKind { get }
    var events: AsyncStream<NetworkEvent> { get }

    func signIn(callsign: String, password: String, register: Bool)
    func signOut()
    func refreshRooms()
    func createRoom(name: String, password: String?)
    func join(roomID: String, password: String?)
    func leave()
    func launchSession()
    func sendKey(pressed: Bool)
    func reconnect()
    func suspend()
}

extension NetworkService {
    func suspend() {}
}

/// No relay client in this build. It never connects and never invents rooms.
final class UnavailableNetworkService: NetworkService {
    let kind = NetworkAdapterKind.unavailable
    let events: AsyncStream<NetworkEvent>
    private let continuation: AsyncStream<NetworkEvent>.Continuation

    static let reason = "Сетевой модуль ещё не подключён к этой сборке"

    init() {
        (events, continuation) = AsyncStream.makeStream(of: NetworkEvent.self)
    }

    func signIn(callsign: String, password: String, register: Bool) {
        continuation.yield(.signInFailed(Self.reason))
    }

    func signOut() {}
    func refreshRooms() { continuation.yield(.lobbyFailed(Self.reason)) }
    func createRoom(name: String, password: String?) {}
    func join(roomID: String, password: String?) { continuation.yield(.joinFailed(Self.reason)) }
    func leave() {}
    func launchSession() {}
    func sendKey(pressed: Bool) {}
    func reconnect() {}
}
