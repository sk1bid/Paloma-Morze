import Foundation
import Testing
@testable import PalomaMorse

@MainActor
struct Task5IntegrationTests {
    private func app(_ service: ScriptedAudioService) throws -> AppModel {
        AppModel(catalog: try loadCatalog(), audioService: service,
                 networkService: UnavailableNetworkService(), settings: SettingsStore(defaults: nil),
                 history: HistoryStore(defaults: nil), fixtureName: "task5.test")
    }

    @Test func taskSettingsAutosaveAndRestoreWithoutRestoringTheExchange() throws {
        let suite = "PalomaTests.Task5." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let session = Task5Session(catalog: try loadCatalog(), audio: AudioCoordinator(service: ScriptedAudioService()),
            settings: settings, archiveDirectory: nil)
        session.configuration.role = .subordinate
        session.configuration.ownCallsign = "КВМЗ"
        session.configuration.botCallsign = "ТУЧА"
        session.configuration.botSpeed = 80
        session.configuration.length = .thirty
        session.configuration.receptionMode = .paper
        session.configuration.radiogramCharset = .digits
        session.inputText = "НЕ СОХРАНЯТЬ КАК НАСТРОЙКУ"
        let reopenedSettings = SettingsStore(defaults: try #require(UserDefaults(suiteName: suite)))
        let reopened = Task5Session(catalog: try loadCatalog(), audio: AudioCoordinator(service: ScriptedAudioService()),
            settings: reopenedSettings, archiveDirectory: nil)
        #expect(reopened.configuration == session.configuration)
        #expect(reopened.status == .idle)
        #expect(reopened.inputText.isEmpty)
        reopenedSettings.resetAll()
        #expect(SettingsStore(defaults: defaults).task5Configuration == Task5Configuration())
    }

    @Test func malformedSavedTaskSettingsFallBackToDefaults() throws {
        let suite = "PalomaTests.Task5." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "task5.configuration.v1")
        #expect(SettingsStore(defaults: defaults).task5Configuration == Task5Configuration())
    }

    @Test func taskOwnsTheKeyAndLocksOtherModesUntilStopped() async throws {
        let engine = ScriptedAudioService()
        let model = try app(engine)
        await settle()
        model.select(.task5)
        model.task5.seedText = "20261102"
        model.task5.start()
        #expect(model.task5.isSessionActive)
        #expect(model.task5.isEnabled)
        #expect(!model.transmission.isEnabled)
        #expect(model.isSectionLocked(.reception))
        #expect(model.isSectionLocked(.transmission))
        #expect(model.isSectionLocked(.radio))
        #expect(!model.isSectionLocked(.task5))
        model.select(.transmission)
        #expect(model.section == .task5)
        model.task5.stop()
        model.select(.transmission)
        #expect(model.section == .transmission)
        #expect(model.transmission.isEnabled)
        #expect(!model.task5.isEnabled)
    }

    @Test func changingToTaskStopsReceptionPreparationAndBackgroundHardwareDoesNotEnterTask() async throws {
        let engine = ScriptedAudioService()
        let model = try app(engine)
        await settle()
        model.reception.toggleRun()
        #expect(model.reception.isSessionActive)
        #expect(model.reception.status == .preparing(secondsRemaining: 5))
        #expect(engine.played.isEmpty)
        model.select(.task5)
        await settle()
        #expect(engine.played.isEmpty)
        #expect(engine.cancelled.isEmpty)
        #expect(!model.reception.isSessionActive)
        model.select(.reception)
        engine.emit(.hardwareKey(pressed: true))
        await settle()
        #expect(!model.task5.isKeyDown)
        #expect(model.task5.inputText.isEmpty)
        engine.emit(.hardwareKey(pressed: false))
    }

    @Test func globalResetStopsTaskAndKeepsAnAbortedResult() async throws {
        let engine = ScriptedAudioService()
        let model = try app(engine)
        await settle()
        model.select(.task5)
        model.task5.seedText = "37"
        model.task5.start()
        model.settings.resetAll()
        #expect(model.section == .reception)
        #expect(!model.task5.isSessionActive)
        #expect(model.task5.status == .aborted)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Task5Export.self, from: model.task5.exportData())
        #expect(archive.status == .aborted)
        #expect(archive.seed == 37)
        #expect(archive.reviewVariant == nil)
    }

    @Test func primaryCommandPausesTheRadioExchangeWithoutConfirmingAStep() async throws {
        let engine = ScriptedAudioService()
        let model = try app(engine)
        await settle()
        model.select(.task5)
        model.task5.seedText = "53"
        model.performPrimaryAction()
        #expect(model.task5.isSessionActive)
        let first = model.task5.currentStepIndex
        model.performPrimaryAction()
        #expect(model.task5.isSessionActive)
        #expect(model.task5.currentStepIndex == first)
        #expect(model.task5.currentStep?.id == "call")
        #expect(model.task5.status == .paused)
        model.performPrimaryAction()
        #expect(model.task5.status == .running)
        #expect(model.task5.status != .aborted)
        model.task5.stop()
    }
}
