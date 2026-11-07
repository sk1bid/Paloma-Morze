import Foundation
import Testing
@testable import PalomaMorse

struct ProductionRelaySmokeTests {
    @Test func configuredProductionRelayAllowsAppHostedReadOnlyLobbyRequest() async throws {
        guard let configured = ProcessInfo.processInfo.environment["PALOMA_PRODUCTION_RELAY_URL"],
              let url = URL(string: configured) else { return }
        let service = SocketIONetworkService(baseURL: url, persistCredentials: false)
        let log = LiveNetworkTests.Log(service)
        defer { log.task?.cancel(); service.suspend() }
        service.refreshRooms()
        _ = try await log.wait { event in
            switch event { case .lobby, .lobbyFailed: true; default: false }
        }
        #expect(log.events.contains { if case .lobby = $0 { true } else { false } }, "Events: \(log.events)")
        #expect(!log.events.contains { if case .lobbyFailed = $0 { true } else { false } }, "Events: \(log.events)")
    }
}

struct LiveNetworkTests {
    static var relayURL: URL {
        URL(string: ProcessInfo.processInfo.environment["PALOMA_NETWORK_TEST_URL"] ?? "http://127.0.0.1:33071")!
    }
    @Test(arguments: [false, true]) func nativeAndJavaScriptSocketIOInteroperate(forcePolling: Bool) async throws {
        guard ProcessInfo.processInfo.environment["PALOMA_RUN_NETWORK_TESTS"] == "1" else {
            if ProcessInfo.processInfo.environment["PALOMA_REQUIRE_NETWORK_TESTS"] == "1" { Issue.record("Network tests were required but not enabled") }
            return
        }
        let url = Self.relayURL
        let nativeName = forcePolling ? "NATIVEPOLL" : "NATIVEWEB"
        let jsName = forcePolling ? "JAVAPOLL" : "JAVAWEB"
        let native = SocketIONetworkService(baseURL: url, persistCredentials: false, forcePolling: forcePolling)
        let log = Log(native)
        defer { log.task?.cancel(); native.signOut() }
        func peer(_ action: String, name: String? = nil, value: [String: Any]? = nil) async throws -> [[String: Any]] {
            var body: [String: Any] = ["action": action, "callsign": jsName]
            body["name"] = name; body["value"] = value
            var request = URLRequest(url: url.appendingPathComponent("fixture/js-peer"))
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["events"] as? [[String: Any]] ?? []
        }
        native.signIn(callsign: nativeName, password: "fixture-pass", register: true)
        #expect(try await log.wait { $0 == .connectionRestored })
        native.createRoom(name: "JS interop \(nativeName)", password: "cross-client")
        #expect(try await log.wait { if case .joined = $0 { true } else { false } })
        guard case .joined(let room)? = log.events.first(where: { if case .joined = $0 { true } else { false } }) else { return }
        _ = try await peer("connect")
        _ = try await peer("emit", name: "join", value: ["roomId": room.id, "password": "wrong", "token": "fixture-\(jsName)"])
        var peerEvents: [[String: Any]] = []
        for _ in 0..<100 {
            peerEvents = try await peer("events")
            if peerEvents.contains(where: { $0["name"] as? String == "error" }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(peerEvents.contains { $0["value"] as? String == "Invalid lobby password" })
        _ = try await peer("emit", name: "join", value: ["roomId": room.id, "password": "cross-client", "token": "fixture-\(jsName)"])
        #expect(try await log.wait { if case .roomUpdated(let people, _) = $0 { people.count == 2 } else { false } })
        // A pending join must not redirect keying away from the confirmed room.
        native.join(roomID: "missing-\(nativeName)", password: nil)
        native.sendKey(pressed: true); native.sendKey(pressed: false)
        #expect(try await log.wait { $0 == .joinFailed("Lobby not found") })
        _ = try await peer("emit", name: "start_session", value: ["roomId": room.id])
        #expect(try await log.wait { $0 == .sessionLaunched })
        // Overlapping presses are simplex collisions: both clients must receive
        // the other operator's edges, in order, without a turn gate.
        native.sendKey(pressed: true)
        _ = try await peer("emit", name: "morse_event", value: ["roomId": room.id, "value": 1])
        #expect(try await log.wait { $0 == .remoteKey(callsign: jsName, pressed: true) })
        native.sendKey(pressed: false)
        _ = try await peer("emit", name: "morse_event", value: ["roomId": room.id, "value": 0])
        #expect(try await log.wait { $0 == .remoteKey(callsign: jsName, pressed: false) })
        for _ in 0..<100 {
            peerEvents = try await peer("events")
            if peerEvents.filter({ $0["name"] as? String == "remote_morse" }).count == 4 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let edges = peerEvents.filter { $0["name"] as? String == "remote_morse" }.compactMap { $0["value"] as? [String: Any] }
        #expect(edges.compactMap { $0["value"] as? Int } == [1, 0, 1, 0])
        #expect(edges.allSatisfy { $0["callsign"] as? String == nativeName })
        _ = try await peer("emit", name: "leave_room", value: ["roomId": room.id])
        #expect(try await log.wait { $0 == .sessionEnded })
        _ = try await peer("close")
    }

    final class Log {
        var events: [NetworkEvent] = []
        var task: Task<Void, Never>?
        init(_ service: SocketIONetworkService) {
            task = Task { [weak self] in for await event in service.events { self?.events.append(event) } }
        }
        func wait(_ predicate: (NetworkEvent) -> Bool) async throws -> Bool {
            for _ in 0..<250 {
                if events.contains(where: predicate) { return true }
                try await Task.sleep(for: .milliseconds(20))
            }
            return false
        }
    }
    @Test func localHTTPAndRealSocketIO() async throws {
        guard ProcessInfo.processInfo.environment["PALOMA_RUN_NETWORK_TESTS"] == "1" else {
            if ProcessInfo.processInfo.environment["PALOMA_REQUIRE_NETWORK_TESTS"] == "1" { Issue.record("Network tests were required but not enabled") }
            return
        }
        let url = Self.relayURL
        let first = SocketIONetworkService(baseURL: url, persistCredentials: false)
        let second = SocketIONetworkService(baseURL: url, persistCredentials: false, forcePolling: true)
        let a = Log(first), b = Log(second)
        defer { a.task?.cancel(); b.task?.cancel(); first.signOut(); second.signOut() }
        first.signIn(callsign: "BAD", password: "invalid-fixture", register: false)
        #expect(try await a.wait { if case .signInFailed("Invalid callsign or password") = $0 { return true }; return false })
        first.signIn(callsign: "AAA", password: "fixture-pass", register: false)
        second.signIn(callsign: "BBB", password: "fixture-pass", register: true)
        #expect(try await a.wait { $0 == .connectionRestored })
        #expect(try await b.wait { $0 == .connectionRestored })
        first.createRoom(name: "Fixture Private", password: "local-room")
        #expect(try await a.wait { if case .joined = $0 { return true }; return false })
        guard case .joined(let room)? = a.events.first(where: { if case .joined = $0 { return true }; return false }) else { return }
        second.refreshRooms()
        #expect(try await b.wait { if case .lobby(let rooms, _) = $0 { return rooms.contains { $0.id == room.id } }; return false })
        second.join(roomID: room.id, password: "wrong")
        #expect(try await b.wait { $0 == .joinFailed("Invalid lobby password") })
        second.join(roomID: room.id, password: "local-room")
        #expect(try await b.wait { if case .roomUpdated(let participants, _) = $0 { return participants.count == 2 }; return false })
        first.launchSession()
        #expect(try await b.wait { $0 == .sessionLaunched })
        first.sendKey(pressed: true); first.sendKey(pressed: false)
        #expect(try await b.wait { $0 == .remoteKey(callsign: "AAA", pressed: false) })
        // Multiple server pings must keep the real connection alive.
        try await Task.sleep(for: .milliseconds(2200))
        #expect(!a.events.contains { if case .connectionLost = $0 { return true }; return false })
        let previousConnections = b.events.filter { $0 == .connectionRestored }.count
        var request = URLRequest(url: url.appendingPathComponent("fixture/drop")); request.httpMethod = "POST"
        request.httpBody = Data(#"{"callsign":"BBB"}"#.utf8)
        _ = try await URLSession.shared.data(for: request)
        #expect(try await b.wait { if case .connectionLost = $0 { return true }; return false })
        for _ in 0..<250 where b.events.filter({ $0 == .connectionRestored }).count <= previousConnections { try await Task.sleep(for: .milliseconds(20)) }
        #expect(b.events.filter { $0 == .connectionRestored }.count > previousConnections)
        second.leave()
        #expect(try await a.wait { $0 == .sessionEnded })
    }
}

struct PollingFallbackTests {
    @Test func pollingFallbackWhenWebsocketTransportUnavailable() async throws {
        guard ProcessInfo.processInfo.environment["PALOMA_RUN_NETWORK_TESTS"] == "1" else {
            if ProcessInfo.processInfo.environment["PALOMA_REQUIRE_NETWORK_TESTS"] == "1" { Issue.record("Network tests were required but not enabled") }
            return
        }
        let url = URL(string: ProcessInfo.processInfo.environment["PALOMA_POLLING_TEST_URL"] ?? "http://127.0.0.1:33072")!
        let service = SocketIONetworkService(baseURL: url, persistCredentials: false)
        let log = LiveNetworkTests.Log(service)
        defer { log.task?.cancel(); service.signOut() }
        service.signIn(callsign: "CCC", password: "fixture-pass", register: false)
        #expect(try await log.wait { $0 == .connectionRestored })
        #expect(log.events.contains { if case .reconnecting = $0 { return true }; return false })
        service.createRoom(name: "Polling Open", password: nil)
        #expect(try await log.wait { if case .joined(let room) = $0 { return !room.isPrivate }; return false })
        try await Task.sleep(for: .milliseconds(2200))
        #expect(!log.events.contains { if case .connectionLost = $0 { return true }; return false })
    }
}
