import AppKit
import Foundation
import Testing
@testable import PalomaMorse

struct IntegrationReviewTests {
    @Test func malformedImportDoesNotResetExistingSettings() throws {
        let settings = SettingsStore(defaults: nil)
        settings.audio.speed = 90
        settings.transmissionKey = "KeyF"
        settings.setOverride(for: "Р", pattern: "...", mnemonic: "тест")
        for json in ["[]", "{}", #"{"unrelated":1}"#, #"{"wpm":"bad"}"#,
                     #"{"paloma_morse_v1":"[]"}"#, #"{"customOverrides":[]}"#] {
            #expect(throws: (any Error).self) { try settings.importLegacySettings(Data(json.utf8)) }
            #expect(settings.audio.speed == 90)
            #expect(settings.transmissionKey == "KeyF")
            #expect(settings.customOverrides["Р"]?.pattern == "...")
        }
    }

    @Test func transientLobbyErrorsKeepLiveRoomAndCanStillReleaseKeys() async throws {
        let engine = ScriptedAudioService(), network = ScriptedNetworkService()
        let audio = AudioCoordinator(service: engine)
        let radio = RadioModel(network: network, audio: audio)
        engine.startEngine()
        network.emit(.signedIn(callsign: "A"))
        network.emit(.joined(RadioRoom(id: "r", name: "Room", owner: "A", isPrivate: false, participantCount: 2)))
        network.emit(.sessionLaunched)
        await settle()
        radio.keyDown()
        network.emit(.remoteKey(callsign: "B", pressed: true))
        await settle()
        network.emit(.lobbyFailed("temporary HTTP failure"))
        network.emit(.joinFailed("Only owner may launch"))
        await settle()
        #expect(radio.isLive)
        #expect(radio.channel == .collision)
        #expect(radio.actionError == "Only owner may launch")
        radio.leave()
        #expect(!radio.localRhythm.isDown && !radio.remoteKeyDown)
        #expect(engine.localKey.last == false && engine.remoteKey.last == false)
        #expect(engine.muted.last == false)
    }

    @Test func staleLobbyReplyCannotHideConnectionLoss() async {
        let network = ScriptedNetworkService()
        let radio = RadioModel(network: network, audio: AudioCoordinator(service: ScriptedAudioService()))
        network.emit(.signedIn(callsign: "A"))
        network.emit(.connectionLost(reason: "offline"))
        network.emit(.lobby(rooms: [], online: 1))
        await settle()
        guard case .connectionLost = radio.screen else { Issue.record("Lobby reply replaced disconnect screen"); return }
    }

    @Test func keyboardCommandsAndTextFieldsDoNotTransmit() async throws {
        let engine = ScriptedAudioService()
        let settings = SettingsStore(defaults: nil)
        settings.transmissionKey = "KeyA"
        let model = AppModel(catalog: try loadCatalog(), audioService: engine,
            networkService: UnavailableNetworkService(), settings: settings, history: HistoryStore(defaults: nil))
        model.select(.transmission)
        await settle()
        let input = NativeKeyboardInput(model: model)
        defer { input.stop() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.title = "Paloma Morse"
        func key(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        }
        #expect(input.handle(key(.keyDown, modifiers: .command), in: window) != nil)
        #expect(!model.transmission.isKeyDown)
        let editor = NSTextView(frame: .zero)
        window.contentView = editor
        window.makeFirstResponder(editor)
        #expect(input.handle(key(.keyDown), in: window) != nil)
        #expect(!model.transmission.isKeyDown)
        window.makeFirstResponder(nil)
        #expect(input.handle(key(.keyDown), in: window) == nil)
        #expect(model.transmission.isKeyDown)
        _ = input.handle(key(.keyUp), in: window)
        #expect(!model.transmission.isKeyDown)
    }
}
