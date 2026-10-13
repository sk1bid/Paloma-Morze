import Foundation
import Testing
@testable import PalomaMorse

/// Reception and transmission state follow engine events, not timers.
@MainActor
struct ReceptionFlowTests {
    let engine = ScriptedAudioService()
    let audio: AudioCoordinator
    let history = HistoryStore(defaults: nil)
    let session: ReceptionSession

    init() throws {
        audio = AudioCoordinator(service: engine)
        session = ReceptionSession(catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil), history: history)
    }

    func ready() async {
        engine.startEngine()
        await settle()
    }

    @Test func startIsBlockedWithoutEngine() {
        #expect(session.startBlockReason != nil)
        session.start()
        #expect(session.status == .idle)
        #expect(engine.played.isEmpty)
    }

    @Test func learningPlaysEachSignFiveTimesAndHighlightsFromEvents() async {
        await ready()
        session.lessonIndex = 0
        session.exercise = .learn
        session.start()
        #expect(session.status == .playing)
        let request = engine.played[0]
        #expect(request.spacing == .lessonOne)
        #expect(request.tokens.count == 4 * 6)
        #expect(request.tokens[5].isGroupGap)

        engine.emit(request.id, .token(6))
        engine.emit(request.id, .pulse(.dot))
        await settle()
        #expect(session.activeSign == "Л")
        #expect(session.pulse == .dot)

        engine.emit(request.id, .finished(cancelled: false))
        await settle()
        #expect(session.status == .completed)
        #expect(session.results == nil)
        #expect(history.records.count == 1)
    }

    @Test func wrongAnswerRepeatsTargetFiveTimes() async throws {
        await ready()
        session.lessonIndex = 2
        session.exercise = .recognize
        session.start()
        let first = engine.played[0]
        #expect(first.tokens.count == 1)
        #expect(session.activeSign == nil)

        engine.emit(first.id, .finished(cancelled: false))
        await settle()
        #expect(session.status == .waitingForAnswer)

        let target = try #require(session.currentTarget)
        let wrong = try #require(session.lessonSigns.first { $0 != target })
        session.answer(wrong)
        #expect(session.status == .feedback(correct: false))
        #expect(session.errors == [target])

        try await Task.sleep(for: .milliseconds(1100))
        #expect(session.status == .repeatingError)
        let repeatRequest = engine.played[1]
        #expect(repeatRequest.spacing == .errorRepeat)
        #expect(repeatRequest.tokens.count == 5)
        #expect(session.activeSign == target)
    }

    @Test func stopWaitsForEngineCancellation() async {
        await ready()
        session.exercise = .learn
        session.start()
        let request = engine.played[0]
        session.stop()
        #expect(session.status == .cancelling)
        #expect(engine.cancelled == [request.id])

        engine.emit(request.id, .finished(cancelled: true))
        await settle()
        #expect(session.status == .idle)
        #expect(history.records.isEmpty)
    }

    @Test func staleEventsAreIgnored() async {
        await ready()
        session.exercise = .learn
        session.start()
        engine.emit(PlaybackRequestID(rawValue: 999), .token(3))
        engine.emit(PlaybackRequestID(rawValue: 999), .finished(cancelled: false))
        await settle()
        #expect(session.status == .playing)
        #expect(session.activeSign == nil)
    }

    @Test func examShowsRadiogramGroupsAtTheEnd() async {
        await ready()
        session.lessonIndex = 3
        session.exercise = .exam
        session.groupCount = 5
        session.start()
        let request = engine.played[0]
        #expect(request.tokens.filter(\.isGroupGap).count == 4)

        engine.emit(request.id, .finished(cancelled: false))
        await settle()
        #expect(session.results?.radiogramGroups.count == 5)
        #expect(session.results?.radiogramGroups.allSatisfy { $0.count == 5 } == true)
    }

    @Test func qCodeLessonOffersOnlyFirstTwoExercises() {
        session.exercise = .exam
        session.lessonIndex = session.lessons.count - 1
        #expect(session.availableExercises == [.learn, .recognize])
        #expect(session.exercise == .recognize)
    }

    @Test func customSelectionDrivesThePool() {
        session.lessonIndex = 5
        session.exercise = .groups
        session.customSelection = true
        session.tap("Ж")
        session.tap("Ф")
        session.tap("Ж")
        #expect(session.studiedPool == ["Ф"])
        session.includeSigns = true
        #expect(session.studiedPool == ["Ф", "/", "=", "?"])
    }
}

@MainActor
struct TransmissionFlowTests {
    @Test func keyboardKeyingSendsLocalKeyAndDecodes() async throws {
        let engine = ScriptedAudioService()
        let audio = AudioCoordinator(service: engine)
        var inputTime = Date(timeIntervalSinceReferenceDate: 0)
        let session = TransmissionSession(
            catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil),
            history: HistoryStore(defaults: nil), now: { inputTime })
        engine.startEngine()
        await settle()

        // Wall-clock sleep is not a key duration: CI may resume a task hundreds
        // of milliseconds late. Inject measured input time without changing DSP.
        session.keyDown(from: .keyboard)
        inputTime.addTimeInterval(0.03)
        session.keyUp(from: .keyboard)
        #expect(engine.localKey == [true, false])
        #expect(session.buffer == ".")

        inputTime.addTimeInterval(0.3)
        // Keep the real gap-monitor task exercised, but wait for its outcome.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while session.decodedText.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.decodedText == "Е")
        session.clear()
    }

    @Test(arguments: [0.03, 0.159, 0.16, 0.24])
    func measuredInputRespectsDotDashBoundary(duration: TimeInterval) async throws {
        let engine = ScriptedAudioService(), audio = AudioCoordinator(service: engine)
        var inputTime = Date(timeIntervalSinceReferenceDate: 0)
        let session = TransmissionSession(
            catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil),
            history: HistoryStore(defaults: nil), now: { inputTime })
        engine.startEngine()
        await settle()
        session.keyDown(from: .keyboard)
        inputTime.addTimeInterval(duration)
        session.keyUp(from: .keyboard)
        #expect(session.buffer == (duration < 0.16 ? "." : "-"))
        #expect(engine.localKey == [true, false])
        session.clear()
    }

    @Test func hardwareKeyIsNotEchoedToTheEngine() async throws {
        let engine = ScriptedAudioService()
        let audio = AudioCoordinator(service: engine)
        let session = TransmissionSession(
            catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil), history: HistoryStore(defaults: nil))
        engine.startEngine()
        engine.emit(.hardware(.connected("Paloma USB")))
        engine.emit(.hardwareKey(pressed: true))
        await settle()
        #expect(session.isKeyDown)
        engine.emit(.hardwareKey(pressed: false))
        await settle()
        #expect(!session.isKeyDown)
        #expect(engine.localKey.isEmpty)
    }
}
