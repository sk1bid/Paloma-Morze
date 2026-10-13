import Foundation
import Testing
@testable import PalomaMorse

final class ScriptedNetworkService: NetworkService {
    let kind = NetworkAdapterKind.live
    let events: AsyncStream<NetworkEvent>
    private let continuation: AsyncStream<NetworkEvent>.Continuation
    var keys: [Bool] = []
    init() { (events, continuation) = AsyncStream.makeStream(of: NetworkEvent.self) }
    func emit(_ event: NetworkEvent) { continuation.yield(event) }
    func signIn(callsign: String, password: String, register: Bool) {}
    func signOut() {}
    func refreshRooms() {}
    func createRoom(name: String, password: String?) {}
    func join(roomID: String, password: String?) {}
    func leave() {}
    func launchSession() {}
    func sendKey(pressed: Bool) { keys.append(pressed) }
    func reconnect() {}
}

struct RadioParityTests {
    @Test func waitingRoomTransmissionRemoteSidetoneAndCollision() async throws {
        let engine = ScriptedAudioService(), network = ScriptedNetworkService()
        let audio = AudioCoordinator(service: engine), settings = SettingsStore(defaults: nil)
        let radio = RadioModel(network: network, audio: audio, settings: settings)
        let transmission = TransmissionSession(catalog: try loadCatalog(), audio: audio, settings: settings, history: HistoryStore(defaults: nil))
        transmission.onKeyStateChange = { radio.transmissionKeyChanged($0) }
        engine.startEngine()
        network.emit(.signedIn(callsign: "AAA"))
        network.emit(.joined(RadioRoom(id: "fixture", name: "Room", owner: "AAA", isPrivate: false, participantCount: 2)))
        await settle()
        transmission.keyDown(from: .keyboard); transmission.keyUp(from: .keyboard)
        #expect(network.keys == [true, false])
        network.emit(.remoteKey(callsign: "BBB", pressed: true)); await settle()
        #expect(engine.remoteKey == [true])
        #expect(engine.muted == [false])
        network.emit(.sessionLaunched); await settle()
        #expect(engine.muted.last == true)
        radio.keyDown()
        #expect(radio.channel == .collision)
        network.emit(.sessionEnded); await settle()
        #expect(!radio.isLive)
        #expect(!radio.localRhythm.isDown && !radio.remoteKeyDown)
        #expect(engine.muted.last == false)
        #expect(engine.localKey.last == false)
        transmission.clear()
    }
    @Test func connectionNoticesIgnoreInitialStateAndFollowReconnect() async {
        let engine = ScriptedAudioService(), audio = AudioCoordinator(service: engine)
        engine.emit(.hardware(.connected("fixture"))); await settle()
        #expect(engine.notices.isEmpty)
        engine.emit(.hardware(.reconnecting)); await settle()
        engine.emit(.hardware(.connected("fixture"))); await settle()
        #expect(engine.notices == [false, true])
        _ = audio.hardware
    }
}
