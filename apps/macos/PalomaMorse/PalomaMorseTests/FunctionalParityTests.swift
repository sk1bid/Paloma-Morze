import Foundation
import Testing
@testable import PalomaMorse

struct FunctionalParityTests {
    @Test func legacySettingsImportAndOverrideRoundTrip() throws {
        let name = "paloma-test-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let fixture = Data(#"{"wpm":11,"frequency":612.5,"volume":75,"lang":"EN","theme":"dark","transmissionKey":"KeyA","customOverrides":{"Л":{"pattern":"x.-..x","mnemonic":"hello world!"}}}"#.utf8)
        try settings.importLegacySettings(fixture)
        #expect(settings.audio.speed == 55)
        #expect(settings.audio.tonePeriod == 18)
        #expect(settings.customOverrides["Л"]?.pattern == ".-..")
        #expect(settings.customOverrides["Л"]?.mnemonic == "hello-world")
        try settings.importLegacySettings(fixture)
        let restored = SettingsStore(defaults: defaults)
        #expect(restored.customOverrides == settings.customOverrides)
        #expect(restored.transmissionKey == "KeyA")
        settings.resetOverride(for: "Л")
        #expect(settings.customOverrides.isEmpty)
        settings.resetAll()
        #expect(settings.transmissionKey == "Space")
        #expect(settings.audio == AudioSettings())
    }
    @Test func legacyProviderPrecedence() throws {
        let catalog = try loadCatalog()
        let overrides = ["Р": MorseOverride(pattern: "...", mnemonic: "override"), "0": MorseOverride(pattern: ".", mnemonic: nil)]
        #expect(catalog.patterns(for: "ЩР", overrides: overrides) == ["--.-", "..."])
        #expect(catalog.mnemonic(for: "Р", alphabet: .ru) == "Квитанция на принятый сигнал")
        #expect(catalog.mnemonic(for: "Р", alphabet: .ru, overrides: overrides) == "override")
        #expect(catalog.decode("...", alphabet: .ru, overrides: overrides) == "Р")
        #expect(catalog.decode("-", alphabet: .ru, overrides: ["0": MorseOverride(pattern: "-", mnemonic: nil)]) == "Т")
    }
    @Test func speedUsesLegacyNearestStep() {
        var value = AudioSettings(); value.speed = 53
        #expect(value.normalized().speed == 55)
    }
    @Test func historyRoundTrip() {
        let name = "paloma-history-test-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HistoryStore(defaults: defaults)
        let record = SessionRecord(date: .now, kind: .reception, title: "test", detail: "fixture", total: 15, errors: 1, duration: 2)
        store.add(record)
        let restored = HistoryStore(defaults: defaults)
        #expect(restored.records == [record])
        restored.remove([record.id])
        #expect(HistoryStore(defaults: defaults).records.isEmpty)
    }
    @Test func stdoutSplitLinesAndLogs() async {
        let service = ProcessAudioService(executable: URL(fileURLWithPath: "/nonexistent-fixture-helper"))
        var iterator = service.events.makeAsyncIterator()
        service.consume(Data("unrecognized log\nAUDIO REA".utf8))
        service.consume(Data("DY 1 48000\n1\nDisconnected\n".utf8))
        #expect(await iterator.next() == .engine(.ready(sampleRate: 48000)))
        #expect(await iterator.next() == .hardwareKey(pressed: true))
        #expect(await iterator.next() == .hardwareKey(pressed: false))
        #expect(await iterator.next() == .hardware(.disconnected))
    }
}

struct AdditionalParityTests {
    @Test func overrideCollisionKeepsLegacyInsertionOrder() throws {
        let settings = SettingsStore(defaults: nil)
        let data = Data(#"{"customOverrides":{"А":{"pattern":"..."},"Б":{"pattern":"..."}}}"#.utf8)
        try settings.importLegacySettings(data)
        let catalog = try loadCatalog()
        #expect(catalog.decode("...", alphabet: .ru, overrides: settings.customOverrides) == "Б")
        settings.setOverride(for: "А", pattern: "...", mnemonic: "test")
        settings.setOverride(for: "А", pattern: "...")
        #expect(settings.customOverrides["А"]?.mnemonic == "test")
        #expect(catalog.decode("...", alphabet: .ru, overrides: settings.customOverrides) == "Б")
        settings.resetOverride(for: "А")
        settings.setOverride(for: "А", pattern: "...", mnemonic: nil)
        #expect(catalog.decode("...", alphabet: .ru, overrides: settings.customOverrides) == "А")
        try settings.importLegacySettings(Data(#"{"customOverrides":{"\u0410":{"pattern":".-"}}}"#.utf8))
        #expect(settings.customOverrides["А"]?.pattern == ".-")
    }
    @Test func symbolsKeepLegacyDoubleWeight() throws {
        let session = ReceptionSession(catalog: try loadCatalog(), audio: AudioCoordinator(service: ScriptedAudioService()), settings: SettingsStore(defaults: nil), history: HistoryStore(defaults: nil))
        session.exercise = .groups; session.includeSigns = true
        #expect(session.studiedPool.filter { $0 == "/" }.count == 2)
        session.customSelection = true; session.customPool = ["/", "Е"]
        #expect(session.studiedPool.filter { $0 == "/" }.count == 2)
    }
    @Test func physicalScanCodesPreserveRemappingAcrossLayouts() {
        #expect(NativeKeyboardInput.browserCode(for: 0) == "KeyA")
        #expect(NativeKeyboardInput.browserCode(for: 49) == "Space")
        #expect(NativeKeyboardInput.browserCode(for: 122) == "F1")
        #expect(NativeKeyboardInput.browserCode(for: 59) == "ControlLeft")
    }
    @Test func nonfiniteAndHugeLegacyNumbersAreSafe() throws {
        let settings = SettingsStore(defaults: nil)
        try settings.importLegacySettings(Data(#"{"wpm":1e100,"frequency":1e-100,"volume":1e100,"front":-1e100}"#.utf8))
        #expect(settings.audio.speed == 150)
        #expect(settings.audio.tonePeriod == 38)
        #expect(settings.audio.volumePercent == 100)
        #expect(settings.audio.front == 0)
    }
}

struct KeychainParityTests {
    @Test func syntheticCredentialRoundTripIsScopedAndRemovable() throws {
        let origin = URL(string: "http://127.0.0.1/keychain-fixture-\(UUID())")!
        let store = KeychainCredentialStore(origin: origin)
        defer { store.clear() }
        try store.write(RelayCredential(token: "synthetic-fixture-token", callsign: "FIXTURE"))
        #expect(store.read()?.callsign == "FIXTURE")
        #expect(store.read()?.token == "synthetic-fixture-token")
        #expect(KeychainCredentialStore(origin: URL(string: "http://127.0.0.1/other-\(UUID())")!).read() == nil)
        store.clear()
        #expect(store.read() == nil)
    }
}

struct ResetParityTests {
    @Test func normalizedEditsStillPersistAndReachAudio() {
        let suite = "paloma-normalize-fixture-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        var updates: [AudioSettings] = []
        settings.onAudioChange = { updates.append($0) }
        settings.audio.speed = 53
        #expect(settings.audio.speed == 55)
        #expect(updates.last?.speed == 55)
        #expect(SettingsStore(defaults: defaults).audio.speed == 55)
    }
    @Test func resetAllResetsTrainingLikeLegacyReloadAndKeepsSignedOutRadio() throws {
        let model = AppModel(catalog: try loadCatalog(), audioService: ScriptedAudioService(), networkService: UnavailableNetworkService(), settings: SettingsStore(defaults: nil), history: HistoryStore(defaults: nil))
        model.select(.transmission)
        model.reception.lessonIndex = 2; model.reception.exercise = .groups; model.reception.customPool = ["А"]
        model.transmission.mode = .radiogram; model.transmission.groupCount = 10
        model.transmission.togglePause()
        model.settings.resetAll()
        #expect(model.section == .reception)
        #expect(model.reception.lessonIndex == 0 && model.reception.exercise == .learn)
        #expect(model.reception.customPool.isEmpty)
        #expect(model.transmission.mode == .free && model.transmission.groupCount == 5 && !model.transmission.isPaused)
        #expect(model.radio.screen == .signedOut(.idle))
    }
}
