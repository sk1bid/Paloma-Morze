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
    private let clock: ReceptionTestClock

    init() throws {
        let clock = ReceptionTestClock()
        self.clock = clock
        audio = AudioCoordinator(service: engine)
        session = ReceptionSession(catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil), history: history,
                                   sleep: { [clock] in await clock.sleep($0) })
    }

    func ready() async {
        engine.startEngine()
        await settle()
    }

    func startPlayback() async {
        session.start()
        for _ in 0..<5 { await clock.advance() }
    }

    @Test(arguments: ReceptionExercise.allCases)
    func preparesAllExercisesBeforeAudio(exercise: ReceptionExercise) async {
        await ready()
        session.exercise = exercise
        session.start()
        for remaining in stride(from: 5, through: 1, by: -1) {
            #expect(session.status == .preparing(secondsRemaining: remaining))
            #expect(session.isConfigurationLocked)
            #expect(engine.played.isEmpty)
            session.tap(session.lessonSigns[0])
            session.repeatCurrent()
            #expect(engine.played.isEmpty)
            await clock.advance()
        }
        #expect(session.status == .playing)
        #expect(engine.played.count == 1)
    }

    @Test func stopAndRestartDiscardsOldPreparation() async {
        await ready()
        session.start()
        await clock.advance()
        session.stop()
        #expect(session.status == .idle)
        session.start()
        // Wake both the cancelled sleep and the new preparation's first tick.
        await clock.advance()
        #expect(session.status == .preparing(secondsRemaining: 4))
        #expect(engine.played.isEmpty)
        for _ in 0..<4 { await clock.advance() }
        #expect(engine.played.count == 1)
        #expect(history.records.isEmpty)
    }

    @Test func stopPreparationNeverSubmitsAudio() async {
        await ready()
        session.start()
        await clock.advance()
        session.stop()
        for _ in 0..<6 { await clock.advance() }
        #expect(session.status == .idle)
        #expect(engine.played.isEmpty)
        #expect(history.records.isEmpty)
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
        await startPlayback()
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
        await startPlayback()
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

        await clock.advance()
        #expect(session.status == .repeatingError)
        let repeatRequest = engine.played[1]
        #expect(repeatRequest.spacing == .errorRepeat)
        #expect(repeatRequest.tokens.count == 5)
        #expect(session.activeSign == target)
    }

    @Test func nextTargetDoesNotRepeatPreparation() async throws {
        await ready()
        session.exercise = .recognize
        await startPlayback()
        engine.emit(engine.played[0].id, .finished(cancelled: false))
        await settle()
        session.answer(try #require(session.currentTarget))
        await clock.advance()
        #expect(engine.played.count == 2)
        #expect(session.status == .playing)
        #expect(session.step == 1)
    }

    @Test func stopWaitsForEngineCancellation() async {
        await ready()
        session.exercise = .learn
        await startPlayback()
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
        await startPlayback()
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
        await startPlayback()
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
private final class ReceptionTestClock {
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { sleepers.append($0) }
    }

    func advance() async {
        await settle()
        let pending = sleepers
        sleepers = []
        for sleeper in pending { sleeper.resume() }
        await settle()
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
