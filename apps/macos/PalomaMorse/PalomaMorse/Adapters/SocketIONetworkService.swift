import Foundation

/// Native Engine.IO 4 + Socket.IO 5 JSON default namespace transport.
/// Default is loopback until the delivery configuration is explicitly approved.
final class SocketIONetworkService: NetworkService {
    let kind = NetworkAdapterKind.live
    let events: AsyncStream<NetworkEvent>
    private let continuation: AsyncStream<NetworkEvent>.Continuation
    private let baseURL: URL
    private let session: URLSession
    private let credentials: KeychainCredentialStore?
    private var preferPolling: Bool
    private var pollingSID: String?
    private var writer: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var generation = UUID()
    private var authenticationID = UUID()
    private var connected = false
    private var attempts = 0
    private var token: String?
    private var callsign = ""
    private var roomID: String?
    private var roomPassword: String?
    private var awaitingJoin = false
    private var confirmedRoomID: String?
    private var confirmedRoomPassword: String?
    private var rooms: [RadioRoom] = []
    private var online = 0
    private var heartbeatWindow = 45_000

    init(baseURL: URL = URL(string: "http://127.0.0.1:3001")!, session: URLSession = .shared, persistCredentials: Bool = true, forcePolling: Bool = false) {
        self.baseURL = baseURL; self.session = session
        preferPolling = forcePolling
        credentials = persistCredentials ? KeychainCredentialStore(origin: baseURL) : nil
        (events, continuation) = AsyncStream.makeStream(of: NetworkEvent.self)
    }
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
    private func http(_ path: String, _ body: [String: Any]? = nil) async throws -> Any {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 15
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let result = try JSONSerialization.jsonObject(with: data)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw Failure.message((result as? [String: Any])?["error"] as? String ?? "HTTP request failed")
        }
        return result
    }
    func signIn(callsign: String, password: String, register: Bool) {
        authenticationID = UUID()
        let auth = authenticationID
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await http("api/auth/\(register ? "register" : "login")", ["callsign": callsign.uppercased(), "password": password])
                guard auth == authenticationID else { return }
                guard let data = response as? [String: Any], let token = data["token"] as? String,
                      let user = data["user"] as? [String: Any], let name = user["callsign"] as? String else { throw Failure.message("Invalid authentication response") }
                try credentials?.write(RelayCredential(token: token, callsign: name))
                self.token = token; self.callsign = name
                continuation.yield(.signedIn(callsign: name)); connect()
            } catch { if auth == authenticationID { continuation.yield(.signInFailed(error.localizedDescription)) } }
        }
    }
    func signOut() { authenticationID = UUID(); leave(); disconnect(); credentials?.clear(); token = nil; callsign = ""; continuation.yield(.signedOut) }
    func refreshRooms() {
        let epoch = generation, started = Date()
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await http("api/lobbies")
                guard epoch == generation else { return }
                guard let list = result as? [[String: Any]] else { throw Failure.message("Invalid lobby response") }
                rooms = list.compactMap { object in
                    guard let id = object["id"] as? String, let name = object["name"] as? String else { return nil }
                    return RadioRoom(id: id, name: name, owner: object["owner"] as? String ?? "?", isPrivate: object["hasPassword"] as? Bool ?? false, participantCount: object["participantCount"] as? Int)
                }
                continuation.yield(.lobby(rooms: rooms, online: online))
                continuation.yield(.latency(milliseconds: Int(Date().timeIntervalSince(started) * 1000)))
            } catch { if epoch == generation { continuation.yield(.lobbyFailed(error.localizedDescription)) } }
        }
    }
    func createRoom(name: String, password: String?) {
        guard let token else { continuation.yield(.joinFailed("Authentication required")); return }
        let epoch = generation
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await http("api/lobbies", ["name": name, "password": password ?? "", "token": token])
                guard epoch == generation else { return }
                guard let object = result as? [String: Any], let id = object["id"] as? String else { throw Failure.message("Invalid create response") }
                rooms.append(RadioRoom(id: id, name: object["name"] as? String ?? name.trimmingCharacters(in: .whitespacesAndNewlines), owner: callsign, isPrivate: !(password ?? "").isEmpty, participantCount: 0))
                join(roomID: id, password: password)
            } catch { if epoch == generation { continuation.yield(.joinFailed(error.localizedDescription)) } }
        }
    }
    func join(roomID: String, password: String?) {
        guard connected, let token else { continuation.yield(.joinFailed("Relay is not connected")); return }
        self.roomID = roomID; roomPassword = password; awaitingJoin = true
        emit("join", ["roomId": roomID, "password": password ?? "", "token": token])
    }
    func leave() {
        if let roomID { emit("morse_event", ["roomId": roomID, "value": 0]); emit("leave_room", ["roomId": roomID]) }
        roomID = nil; roomPassword = nil; confirmedRoomID = nil; confirmedRoomPassword = nil
        awaitingJoin = false; continuation.yield(.left)
    }
    func launchSession() { if let roomID { emit("start_session", ["roomId": roomID]) } }
    func sendKey(pressed: Bool) { if let roomID { emit("morse_event", ["roomId": roomID, "value": pressed ? 1 : 0]) } }
    func reconnect() { attempts = 0; connect() }
    func suspend() { disconnect() }
    func restoreAuthentication() {
        guard let stored = credentials?.read() else { return }
        token = stored.token; callsign = stored.callsign
        continuation.yield(.signedIn(callsign: stored.callsign)); connect()
    }
    private func disconnect() {
        if preferPolling, let sid = pollingSID { closePollingSession(sid) }
        generation = UUID(); connected = false
        reader?.cancel(); writer?.cancel(); writer = nil; pollingSID = nil
        retry?.cancel(); retry = nil; watchdog?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
    }
    private func connect() {
        disconnect()
        guard token != nil else { return }
        if preferPolling { startPolling(); return }
        var url = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        url.scheme = baseURL.scheme == "https" ? "wss" : "ws"; url.path = "/socket.io/"
        url.queryItems = [URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "websocket")]
        guard let endpoint = url.url else { return }
        let ws = session.webSocketTask(with: endpoint), epoch = generation
        socket = ws; ws.resume()
        reader = Task { [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled, epoch == generation {
                    let message = try await ws.receive()
                    guard epoch == generation else { return }
                    if case .string(let packet) = message { consume(packet) }
                }
            } catch { if epoch == generation { lost(error.localizedDescription) } }
        }
    }
    /// POSTs and websocket sends are serialized to preserve down/up ordering.
    private func send(_ packet: String) {
        let epoch = generation, previous = writer
        writer = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, epoch == generation else { return }
            do {
                if preferPolling {
                    _ = try await engineHTTP(packet)
                } else if let socket {
                    try await socket.send(.string(packet))
                }
            } catch { if epoch == generation { lost(error.localizedDescription) } }
        }
    }

    /// Engine.IO v4 polling payloads are text packets separated by record separator.
    private func engineHTTP(_ packet: String?) async throws -> String {
        var url = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        url.path = "/socket.io/"
        url.queryItems = [URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "polling"), URLQueryItem(name: "t", value: UUID().uuidString)]
        if let pollingSID { url.queryItems?.append(URLQueryItem(name: "sid", value: pollingSID)) }
        guard let endpoint = url.url else { throw Failure.message("Invalid relay origin") }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        if let packet {
            request.httpMethod = "POST"
            request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(packet.utf8)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw Failure.message("Engine.IO polling request failed") }
        return String(decoding: data, as: UTF8.self)
    }
    private func closePollingSession(_ sid: String) {
        var url = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        url.path = "/socket.io/"
        url.queryItems = [URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "polling"), URLQueryItem(name: "sid", value: sid)]
        guard let endpoint = url.url else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 5
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("1".utf8)
        let session = session
        Task { _ = try? await session.data(for: request) }
    }
    private func startPolling() {
        let epoch = generation
        reader = Task { [weak self] in
            guard let self else { return }
            do {
                let opening = try await engineHTTP(nil)
                guard epoch == generation else { return }
                let packets = opening.split(separator: "\u{1e}")
                guard let first = packets.first, first.hasPrefix("0"),
                      let object = try JSONSerialization.jsonObject(with: Data(first.dropFirst().utf8)) as? [String: Any],
                      let sid = object["sid"] as? String else { throw Failure.message("Invalid Engine.IO handshake") }
                pollingSID = sid
                for packet in packets { consume(String(packet)) }
                while !Task.isCancelled, epoch == generation {
                    let payload = try await engineHTTP(nil)
                    guard epoch == generation else { return }
                    for packet in payload.split(separator: "\u{1e}") {
                        guard epoch == generation else { return }; consume(String(packet))
                    }
                }
            } catch { if epoch == generation { lost(error.localizedDescription) } }
        }
    }
    private func emit(_ name: String, _ object: [String: Any]) {
        guard connected, let data = try? JSONSerialization.data(withJSONObject: [name, object]), let json = String(data: data, encoding: .utf8) else { return }
        send("42" + json)
    }
    func consume(_ packet: String) {
        if packet.hasPrefix("0") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(packet.dropFirst().utf8)) as? [String: Any],
                  let interval = object["pingInterval"] as? Int, let timeout = object["pingTimeout"] as? Int else { return }
            heartbeatWindow = interval + timeout
            armWatchdog(heartbeatWindow)
            if let data = try? JSONSerialization.data(withJSONObject: ["callsign": callsign]), let json = String(data: data, encoding: .utf8) { send("40" + json) }
        } else if packet.hasPrefix("2") {
            send("3" + packet.dropFirst()); armWatchdog(heartbeatWindow)
        } else if packet.hasPrefix("40") {
            connected = true; attempts = 0; continuation.yield(.connectionRestored); refreshRooms()
            if let roomID, let token { awaitingJoin = true; emit("join", ["roomId": roomID, "password": roomPassword ?? "", "token": token]) }
        } else if packet == "1" || packet == "41" || packet.hasPrefix("44") {
            lost("Relay disconnected")
        } else if packet.hasPrefix("42"), let array = try? JSONSerialization.jsonObject(with: Data(packet.dropFirst(2).utf8)) as? [Any], let name = array.first as? String {
            handle(name, array.count > 1 ? array[1] : NSNull())
        }
    }
    private func armWatchdog(_ milliseconds: Int) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled, let self else { return }; lost("Engine.IO heartbeat timeout")
        }
    }
    private func lost(_ reason: String) {
        guard retry == nil else { return }
        if !connected, !preferPolling {
            preferPolling = true
            continuation.yield(.reconnecting(attempt: attempts + 1))
            connect()
            return
        }
        generation = UUID()
        connected = false; watchdog?.cancel(); socket?.cancel(with: .goingAway, reason: nil)
        continuation.yield(.connectionLost(reason: reason)); attempts += 1; continuation.yield(.reconnecting(attempt: attempts))
        let delay = min(30, attempts * 2)
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }; retry = nil; connect()
        }
    }
    private func handle(_ name: String, _ body: Any) {
        let object = body as? [String: Any] ?? [:]
        switch name {
        case "global_online": online = body as? Int ?? 0; continuation.yield(.lobby(rooms: rooms, online: online))
        case "lobby_update": refreshRooms()
        case "error":
            if awaitingJoin {
                roomID = confirmedRoomID; roomPassword = confirmedRoomPassword
                awaitingJoin = false
            }
            continuation.yield(.joinFailed(body as? String ?? "Relay error"))
        case "room_update":
            if awaitingJoin, let roomID {
                awaitingJoin = false
                confirmedRoomID = roomID; confirmedRoomPassword = roomPassword
                continuation.yield(.joined(rooms.first { $0.id == roomID } ?? RadioRoom(id: roomID, name: roomID, owner: object["owner"] as? String ?? "?", isPrivate: roomPassword != nil, participantCount: 0)))
            }
            let participants = (object["participants"] as? [[String: Any]] ?? []).compactMap { ($0["callsign"] as? String).map { RadioParticipant(callsign: $0) } }
            continuation.yield(.roomUpdated(participants: participants, owner: object["owner"] as? String ?? "?"))
        case "session_started": continuation.yield(.sessionLaunched)
        case "session_ended": continuation.yield(.sessionEnded)
        case "remote_morse": continuation.yield(.remoteKey(callsign: object["callsign"] as? String ?? "?", pressed: (object["value"] as? Int) == 1))
        default: break
        }
    }
}
