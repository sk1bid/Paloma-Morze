import Foundation
import SwiftUI
import AppKit
import Testing
@testable import PalomaMorse

@MainActor
struct Task5DeveloperReviewTests {
    private func session(review: Bool = true, archiveDirectory: URL? = nil) async throws -> (Task5Session, ScriptedAudioService) {
        let engine = ScriptedAudioService(), audio = AudioCoordinator(service: engine)
        let session = Task5Session(catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil),
            archiveDirectory: archiveDirectory, botResponseDelay: { _, _ in 0 }, developerReview: review)
        session.isEnabled = true; session.seedText = "2483"; session.configuration.length = .short
        session.developerAudioEnabled = false
        engine.startEngine(); await settle()
        return (session, engine)
    }

    @Test func launchGateCannotBeEnabledByPersistedDefaults() throws {
        let name = "PalomaTests.DevReview." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "PalomaTask5Review")
        #expect(!LaunchOptions(defaults: defaults, arguments: [], environment: [:]).developerTask5Review)
        #expect(LaunchOptions(defaults: defaults, arguments: ["app", "--task5-dev"], environment: [:]).developerTask5Review)
        #expect(LaunchOptions(defaults: defaults, arguments: [], environment: ["PALOMA_TASK5_REVIEW": "1"]).developerTask5Review)
    }

    @Test func normalSessionCannotJumpOrSimulateActions() async throws {
        let (normal, engine) = try await session(review: false)
        normal.developerJump(to: 20); normal.developerNext(); normal.developerStartPreview(interval: 0.05)
        normal.developerShowGroupError()
        #expect(normal.variant == nil && normal.attempts.isEmpty)
        #expect(normal.status == .idle && !normal.isDeveloperAutoPreview)
        #expect(engine.played.isEmpty)
    }

    @Test func aPreviewFixtureNameAloneDoesNotActivateDeveloperControls() throws {
        let model = AppModel(catalog: try loadCatalog(), audioService: UnavailableAudioService(),
            networkService: UnavailableNetworkService(), settings: SettingsStore(defaults: nil),
            history: HistoryStore(records: []), fixtureName: "task5.developer-review")
        #expect(!model.task5.isDeveloperReview)
    }

    @Test func administrativeStagesRemainInspectableWithoutBeingSkippedOnSelection() async throws {
        let (review, _) = try await session()
        review.developerInspectStage(to: 0)
        #expect(review.currentStep?.id == "duty")
        #expect(review.developerStages.contains { $0.id == "setup" })
        review.tick()
        #expect(review.currentStep?.id == "duty")
        review.developerNext()
        #expect(review.currentStep?.id == "setup")
        review.stop()
    }

    @Test func reviewCannotPersistOrExportAndDoesNotTouchSavedTaskSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let savedSettings = UserDefaults.standard.data(forKey: "task5.configuration.v1")
        let (review, _) = try await session(archiveDirectory: directory)
        review.configuration.botSpeed = 85
        review.developerJump(to: 10)
        review.stop()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(UserDefaults.standard.data(forKey: "task5.configuration.v1") == savedSettings)
        #expect(throws: Task5SessionError.self) { try review.exportData() }
        #expect(throws: Task5SessionError.self) { try review.restore(data: Data()) }
        #expect(review.timeComparison == nil)
    }

    @Test(arguments: Task5StationRole.allCases) func frozenJumpBuildsCanonicalAuthenticationPrefixAndNextCanSubmit(role: Task5StationRole) async throws {
        let (review, engine) = try await session()
        review.configuration.role = role
        review.developerJump(to: 0)
        let id = role == .main ? "auth-self" : "auth-counter"
        let index = try #require(review.variant?.steps.firstIndex { $0.id == id })
        review.developerInspectStage(to: index)
        #expect(review.currentStep?.id == id && review.developerStageIsFrozen)
        let step = try #require(review.currentStep), variant = try #require(review.variant)
        #expect(Task5Validator.validate(step.expectedMessages.first ?? "", for: step, variant: variant).isCorrect)
        #expect(review.attempts.allSatisfy { $0.inputMethod == "developerReview" })
        #expect(engine.played.isEmpty)
        review.developerNext()
        #expect(review.currentStep?.id != id)
        review.stop()
    }

    @Test func manualRunUsesRealAudioAndLateCallbacksCannotMoveAChosenFrozenStage() async throws {
        let (review, engine) = try await session()
        review.developerAudioEnabled = true
        review.developerJump(to: 0)
        let botIndex = try #require(review.variant?.steps.firstIndex { $0.id == "call-reply" })
        review.developerInspectStage(to: botIndex)
        #expect(engine.played.isEmpty)
        review.developerRunStage()
        #expect(review.status == .playing && !review.developerStageIsFrozen)
        let previous = engine.lastID
        let target = try #require(review.variant?.steps.firstIndex { $0.id == "rg-0" })
        review.developerInspectStage(to: target)
        #expect(engine.cancelled.contains(previous))
        engine.emit(previous, .finished(cancelled: false)); await settle()
        #expect(review.currentStep?.id == "rg-0")
        #expect(review.developerStageIsFrozen)
        review.stop()
    }

    @Test func automaticPreviewSkipsLongWaitsStopsAndKeepsTheSelectedStageInspectable() async throws {
        let (review, _) = try await session()
        review.developerJump(to: 0)
        let index = try #require(review.variant?.steps.firstIndex { $0.id == "auth-request-wait-pause" })
        review.developerInspectStage(to: index)
        review.tick()
        #expect(review.currentStepIndex == index)
        review.developerStartPreview(interval: 0.05)
        for _ in 0..<30 where review.currentStepIndex == index { try await Task.sleep(for: .milliseconds(20)) }
        #expect(review.currentStepIndex > index)
        review.developerFreeze()
        let selected = review.currentStepIndex
        try await Task.sleep(for: .milliseconds(100))
        #expect(!review.isDeveloperAutoPreview && review.developerStageIsFrozen)
        #expect(review.currentStepIndex == selected)
        review.developerBack()
        #expect(review.currentStepIndex < selected)
        review.stop()
    }

    @Test func groupErrorPresetCanBeCorrectedWithNextWithoutWritingAResult() async throws {
        let (review, _) = try await session()
        review.developerJump(to: 0)
        review.developerShowGroupError()
        #expect(review.radiogramRepair?.part == .group(0))
        #expect(review.currentStep?.id == "rg-0")
        review.developerNext()
        #expect(review.radiogramRepair == nil)
        #expect(review.currentStep?.id == "rg-0-receipt")
        review.stop()
    }

    @Test func controllerAndMainShareOneSessionAndClosingDoesNotCancelManualAudio() async throws {
        let (review, engine) = try await session()
        review.developerAudioEnabled = true; review.developerInspectStage(to: 0)
        let main = Task5View(session: review), controller = Task5DeveloperController(session: review)
        #expect(main.session === controller.session)
        let index = try #require(review.variant?.steps.firstIndex { $0.id == "call-reply" })
        controller.session.developerInspectStage(to: index)
        controller.session.developerRunStage()
        let id = engine.lastID
        controller.session.developerControllerClosed()
        #expect(main.session.status == .playing)
        #expect(!engine.cancelled.contains(id))
        #expect(main.session.currentStepIndex == index)
        let reopened = Task5DeveloperController(session: review)
        #expect(reopened.session === main.session)
        #expect(reopened.session.currentStepIndex == index)
        engine.emit(id, .finished(cancelled: false)); await settle()
        #expect(main.session.currentStepIndex > index)
        review.stop()
    }

    @Test func controllerCloseStopsOnlyAutomaticNavigation() async throws {
        let (review, _) = try await session()
        review.developerInspectStage(to: 0)
        review.developerStartPreview(interval: 0.05)
        let index = review.currentStepIndex
        review.developerControllerClosed()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!review.isDeveloperAutoPreview)
        #expect(review.currentStepIndex == index)
        #expect(review.isSessionActive)
        review.stop()
    }

    @Test func keyboardKeyingRemainsOnTheOrdinaryMainWindowAndNotTheDeveloperController() async throws {
        let engine = ScriptedAudioService()
        let model = AppModel(catalog: try loadCatalog(), audioService: engine,
            networkService: UnavailableNetworkService(), settings: SettingsStore(defaults: nil),
            history: HistoryStore(records: []), fixtureName: "task5.developer-review", developerTask5Review: true)
        model.select(.task5); await settle()
        model.task5.developerAudioEnabled = false
        model.task5.developerInspectStage(to: 0)
        let index = try #require(model.task5.variant?.steps.firstIndex { $0.id == "call" })
        model.task5.developerInspectStage(to: index)
        let input = NativeKeyboardInput(model: model)
        defer { input.stop(); model.task5.stop() }
        let main = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        main.title = "Paloma Morse"
        let controller = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        controller.title = "DEV · Управление задачей №5"
        func key(_ type: NSEvent.EventType, _ window: NSWindow) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ",
                isARepeat: false, keyCode: 49))
        }
        #expect(input.handle(try key(.keyDown, controller), in: controller) != nil)
        #expect(!model.task5.isKeyDown)
        #expect(input.handle(try key(.keyDown, main), in: main) == nil)
        #expect(model.task5.isKeyDown)
        #expect(input.handle(try key(.keyUp, main), in: main) == nil)
        #expect(!model.task5.isKeyDown)
    }
}
