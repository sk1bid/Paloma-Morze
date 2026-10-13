import Foundation
import Testing
@testable import PalomaMorse

struct LiveNetworkTests {
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
        let url = URL(string: "http://127.0.0.1:33071")!
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
        let service = SocketIONetworkService(baseURL: URL(string: "http://127.0.0.1:33072")!, persistCredentials: false)
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
