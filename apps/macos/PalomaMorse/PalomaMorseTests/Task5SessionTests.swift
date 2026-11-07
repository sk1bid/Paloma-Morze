import Foundation
import Testing
@testable import PalomaMorse

@MainActor
struct Task5SessionTests {
    final class Clock {
        var date = Date(timeIntervalSinceReferenceDate: 1000)
        func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
    }

    struct Rig {
        let engine: ScriptedAudioService
        let audio: AudioCoordinator
        let session: Task5Session
        let clock: Clock
    }

    func rig(ready: Bool = true, archiveDirectory: URL? = nil, full: Bool = false, replyDelay: TimeInterval = 0,
             waitDuration: TimeInterval = 60, delaySource: ((Task5Step, Bool) -> TimeInterval)? = nil) async throws -> Rig {
        let engine = ScriptedAudioService(), audio = AudioCoordinator(service: engine), clock = Clock()
        let session = Task5Session(catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil),
                                   archiveDirectory: archiveDirectory, now: { clock.date }, uptime: { clock.date.timeIntervalSinceReferenceDate },
                                   botResponseDelay: delaySource ?? { _, _ in replyDelay }, authenticationWaitDuration: { waitDuration })
        session.configuration.length = full ? .full : .short
        session.seedText = "2483"; session.isEnabled = true
        if ready { engine.startEngine(); await settle() }
        return Rig(engine: engine, audio: audio, session: session, clock: clock)
    }

    /// Advancing the simulated operator clock makes a character eligible for
    /// commit; the production gap task still has to run on the MainActor. Wait
    /// for that state transition rather than assuming a 100 ms scheduling slot.
    private func waitForCharacterCommit(_ session: Task5Session) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !session.buffer.isEmpty, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(session.buffer.isEmpty,
            "Character did not commit: buffer=\(session.buffer), input=\(session.inputText), step=\(session.currentStep?.id ?? "none")")
    }

    @Test(arguments: Task5StationRole.allCases) func announcedWaitStartsAfterBotFinishesAndFreezesOnUserPause(role: Task5StationRole) async throws {
        let r = try await rig()
        r.session.configuration.role = role
        r.session.startRadioExchange()
        let waitID = role == .main ? "auth-request-wait" : "auth-counter-wait"
        // Reach the preceding confirmation so that the wait transmission has
        // begun but its audio completion event has not yet arrived.
        try await advance(r, until: role == .main ? "auth-request-confirm" : "auth-peer-reply")
        r.session.inputText = "Ц К"; r.session.submit()
        #expect(r.session.currentStep?.id == waitID)
        let message = try #require(r.session.currentStep?.botMessage)
        #expect(message == "ОК АС 1 К")
        r.clock.advance(300); r.session.tick()
        #expect(r.session.status == .playing)
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        #expect(r.session.currentStep?.id == waitID + "-pause")
        #expect(r.session.pauseRemainingSeconds == 60)
        let count = r.engine.played.count
        r.clock.advance(59); r.session.tick()
        #expect(r.session.pauseRemainingSeconds == 1)
        #expect(r.engine.played.count == count)
        r.session.pause(); r.clock.advance(120); r.session.resume()
        #expect(r.session.pauseRemainingSeconds == 1)
        r.clock.advance(1); r.session.tick()
        #expect(r.session.currentStep?.id != waitID + "-pause")
        #expect(r.session.events.contains { $0.kind == "waitFinished" })
        r.session.stop()
    }

    @Test func timedWaitArchiveRestoresRemainingTimeAndLegacyProfileStaysUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let r = try await rig(archiveDirectory: directory)
        r.session.configuration.role = .main
        r.session.startRadioExchange()
        try await advance(r, until: "auth-request-confirm")
        r.session.inputText = "Ц К"; r.session.submit()
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        r.clock.advance(10); r.session.tick(); r.session.pause()
        let url = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let data = try Data(contentsOf: url)
        let restored = try await rig()
        try restored.session.restore(data: data)
        #expect(restored.session.pauseRemainingSeconds == 50)
        restored.clock.advance(600); restored.session.resume()
        #expect(restored.session.pauseRemainingSeconds == 50)
        restored.clock.advance(49); restored.session.tick()
        #expect(restored.session.currentStep?.kind == .pause)
        restored.clock.advance(1); restored.session.tick()
        #expect(restored.session.currentStep?.id == "auth-counter")
        let legacy = try Task5Scenario.generate(configuration: r.session.configuration, seed: 2483,
            reference: r.session.reference, catalog: loadCatalog(), profileID: "task5.photos.v6.callsigns-tdr")
        #expect(legacy.steps.first { $0.id == "auth-request-wait" }?.expectedMessages == ["ОК АС"])
        #expect(!legacy.steps.contains { $0.id == "auth-request-wait-pause" })
        r.session.stop(); restored.session.stop()
    }

    @Test(arguments: Task5StationRole.allCases, [1, 3, 99]) func operatorASNeverLocksTheKey(role: Task5StationRole, minutes: Int) async throws {
        let r = try await rig()
        r.session.configuration.role = role
        r.session.startRadioExchange()
        try await advance(r, until: role == .main ? "auth-counter-wait" : "auth-request-wait")
        let step = try #require(r.session.currentStep), variant = try #require(r.session.variant)
        for invalid in ["ОК АС", "ОК АС 0 К", "ОК АС -1 К", "ОК АС 100 К", "ОК АС 3"] {
            #expect(!Task5Validator.validate(invalid, for: step, variant: variant).isCorrect)
        }
        r.session.inputText = "ОКАС\(minutes)К"; r.session.submit()
        #expect(r.session.currentStep?.id == (role == .main ? "auth-self" : "auth-counter"))
        #expect(r.session.status == .running)
        #expect(r.session.pauseRemainingSeconds == 0)
        r.session.keyDown(from: .keyboard)
        #expect(r.session.isKeyDown)
        r.session.keyUp(from: .keyboard)
        r.session.stop()
    }

    @Test(arguments: Task5StationRole.allCases, [55.0, 65.0]) func botWaitHasNaturalBoundsWithoutAdditionalReplyDelay(role: Task5StationRole, seconds: Double) async throws {
        var nextDelay: TimeInterval = 0
        let r = try await rig(waitDuration: seconds, delaySource: { _, _ in nextDelay })
        r.session.configuration.role = role
        r.session.startRadioExchange()
        let confirmation = role == .main ? "auth-request-confirm" : "auth-peer-reply"
        try await advance(r, until: confirmation)
        r.session.inputText = "Ц К"; r.session.submit()
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        #expect(r.session.isAuthenticationWait)
        #expect(r.session.currentStep?.requiredPauseSeconds == seconds)
        nextDelay = 100
        let count = r.engine.played.count
        r.clock.advance(seconds - 0.01); r.session.tick()
        #expect(r.engine.played.count == count)
        r.clock.advance(0.01); r.session.tick()
        #expect(r.engine.played.count == count + 1)
        #expect(!r.session.isWaitingForBot)
        r.session.stop()
    }

    @Test(arguments: Task5StationRole.allCases) func receivedMeaningsWaitForValidOperatorASAndOutgoingEchoIsReady(role: Task5StationRole) async throws {
        let r = try await rig()
        r.session.configuration.role = role
        r.session.startRadioExchange()
        let echoID = role == .main ? "auth-counter-echo" : "auth-request-echo"
        try await advance(r, until: echoID)
        #expect(r.session.preparedServiceTransmission == r.session.currentStep?.expectedMessages.first)
        #expect(r.session.acknowledgedCodeMeanings.isEmpty)
        #expect(r.session.hintCount == 0 && r.session.automaticGuidanceCount == 0)
        let count = r.engine.played.count
        r.clock.advance(5); r.session.tick()
        #expect(r.engine.played.count == count)
        #expect(r.session.currentStep?.id == echoID)
        let waitID = role == .main ? "auth-counter-wait" : "auth-request-wait"
        try await advance(r, until: waitID)
        #expect(r.session.acknowledgedCodeMeanings.isEmpty)
        r.session.inputText = "ОК АС 0 К"; r.session.submit()
        #expect(r.session.acknowledgedCodeMeanings.isEmpty)
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        r.session.inputText = "ОК АС 99 К"; r.session.submit()
        #expect(!r.session.acknowledgedCodeMeanings.isEmpty)
        #expect(r.session.status == .running)
        #expect(r.session.pauseRemainingSeconds == 0)
        #expect(r.session.acknowledgedCodeMeanings.contains { $0.expression != nil })
        #expect(r.session.acknowledgedCodeMeanings.contains { $0.expression == nil })
        r.session.stop()
    }

    @Test func numericAuthenticationMeaningDoesNotUseTheCellsUnrelatedCommand() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        try await advance(r, until: "auth-peer")
        let variant = try #require(r.session.variant)
        let target = try #require(variant.tdr.cells.first { cell in
            (Int(cell.number) ?? 99) <= 50 && cell.expressionId != nil && cell.expressionId != "password"
        })
        let challengeNumber = String(format: "%02d", abs(50 - (Int(target.number) ?? 0)))
        let challenge = try #require(variant.tdr.cells.first { $0.number == challengeNumber })
        let password = try #require(variant.tdr.codes(forExpressionID: "password").first)
        r.session.inputText = "\(password) \(variant.tdr.codes(for: challenge)[0]) К"; r.session.submit()
        try await advance(r, until: "auth-counter-wait")
        r.session.inputText = "ОК АС 1 К"; r.session.submit()
        #expect(r.session.acknowledgedCodeMeanings.contains { $0.number == target.number && $0.expression == nil })
        #expect(!r.session.acknowledgedCodeMeanings.contains { $0.expression == target.expression })
        r.session.stop()
    }

    @Test func optionalASRevealsReceivedUrgencyWithoutAdvancingOrLockingTheUserTurn() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        try await advance(r, until: "rg-1-ready")
        let stepID = r.session.currentStep?.id
        let previous = r.session.acknowledgedCodeMeanings
        let count = r.engine.played.count
        r.session.inputText = "ОК АС 3 К"; r.session.submit()
        #expect(r.session.currentStep?.id == stepID)
        #expect(r.session.status == .running && r.session.canSubmit)
        #expect(r.session.pauseRemainingSeconds == 0)
        #expect(r.engine.played.count == count)
        #expect(r.session.acknowledgedCodeMeanings.count > previous.count)
        let incoming = try #require(r.session.variant?.radiograms.first { $0.direction == .receive })
        let urgency = r.session.variant?.tdr.decode(incoming.urgencyCode)?.expression
        #expect(r.session.acknowledgedCodeMeanings.contains { $0.expression == urgency })
        r.session.keyDown(from: .keyboard)
        #expect(r.session.isKeyDown)
        r.session.keyUp(from: .keyboard)
        r.session.stop()
    }

    @Test func optionalASDuringReceptionPreservesDraftAndPendingReceipt() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        try await advance(r, until: "rg-1")
        r.session.receptionDraft = "МОЯ ЗАПИСЬ ПРИЁМА"
        let receipt = r.session.receptionReceipt
        let attempts = r.session.attempts.count, groups = r.session.completedGroups
        r.session.inputText = "ОК АС 1 К"; r.session.submit()
        #expect(r.session.currentStep?.id == "rg-1")
        #expect(r.session.receptionReceipt?.id == receipt?.id)
        #expect(r.session.receptionDraft == "МОЯ ЗАПИСЬ ПРИЁМА")
        #expect(r.session.attempts.count == attempts + 1 && r.session.completedGroups == groups)
        #expect(r.session.attempts.last?.inputMethod == "service")
        #expect(r.session.canSubmit && r.session.inputText.isEmpty)
        r.session.stop()
    }

    @Test(arguments: Task5StationRole.allCases, [true, false]) func legacyASPauseArchivesUseCurrentDirectionPolicy(role: Task5StationRole, ownAS: Bool) async throws {
        let r = try await rig()
        r.session.configuration.role = role
        r.session.startRadioExchange()
        let commandID = ownAS ? (role == .main ? "auth-counter-wait" : "auth-request-wait") :
            (role == .main ? "auth-request-wait" : "auth-counter-wait")
        try await advance(r, until: ownAS ? commandID : (role == .main ? "auth-request-confirm" : "auth-peer-reply"))
        if !ownAS {
            r.session.inputText = "Ц К"; r.session.submit()
            r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        }
        r.session.stop()
        var archive = try #require(JSONSerialization.jsonObject(with: r.session.exportData()) as? [String: Any])
        let index = try #require(r.session.variant?.steps.firstIndex { $0.id == commandID + "-pause" })
        archive["currentStepIndex"] = index
        archive["pauseRemainingDuration"] = 5900
        archive["journal"] = "obsolete operator document"
        let restored = try await rig()
        try restored.session.restore(data: JSONSerialization.data(withJSONObject: archive))
        if ownAS {
            #expect(restored.session.currentStep?.id != commandID + "-pause")
            restored.session.resume()
            #expect(restored.session.canSubmit)
            #expect(restored.session.pauseRemainingSeconds == 0)
        } else {
            #expect(restored.session.isAuthenticationWait)
            #expect(restored.session.pauseRemainingSeconds == 65)
            restored.session.resume()
            restored.clock.advance(65); restored.session.tick()
            #expect(!restored.session.isAuthenticationWait)
        }
        restored.session.stop()
    }

    /// Finish a real keyed K, so the automatic gap watcher (not submit())
    /// decides whether the exchange advances.
    func keyK(_ r: Rig) async throws {
        for mark in "-.-" {
            r.session.keyDown(from: .keyboard)
            r.clock.advance(mark == "-" ? 0.24 : 0.08)
            r.session.keyUp(from: .keyboard)
            r.clock.advance(0.08)
        }
        r.clock.advance(0.8)
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test(arguments: ["joinedTerminator", "splitQuestion", "compact"]) func authenticationSpacingDoesNotStall(style: String) async throws {
        let r = try await rig()
        r.session.configuration.role = .subordinate
        r.session.startRadioExchange()
        try await advance(r, until: "auth-request-echo")
        let expected = try #require(r.session.currentStep?.expectedMessages.first)
        var prefix = String(expected.dropLast())
        if style == "joinedTerminator" { prefix = prefix.trimmingCharacters(in: .whitespaces) }
        if style == "splitQuestion" { prefix = prefix.replacingOccurrences(of: "Ц?", with: "Ц ?") }
        if style == "compact" { prefix = prefix.replacingOccurrences(of: " ", with: "") }
        r.session.inputText = prefix
        try await keyK(r)
        #expect(r.session.currentStep?.id != "auth-request-echo")
        #expect(r.session.attempts.last?.correct == true)
        #expect(r.session.attempts.last?.input == expected)
        #expect(r.session.events.contains { $0.kind == "spacingRecovered" })
        r.session.stop()
    }

    @Test func incompleteInputGetsOneNoticeAndCanContinueAfterPause() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        try await advance(r, until: "quality-report")
        r.session.inputText = "ЩСА "
        for mark in "....-" {
            r.session.keyDown(from: .keyboard); r.clock.advance(mark == "-" ? 0.24 : 0.08)
            r.session.keyUp(from: .keyboard); r.clock.advance(0.08)
        }
        r.clock.advance(0.3)
        try await Task.sleep(for: .milliseconds(100))
        r.session.pause(); r.clock.advance(20); r.session.resume()
        r.clock.advance(7)
        try await Task.sleep(for: .milliseconds(100))
        #expect(r.session.currentStep?.id == "quality-report")
        #expect(r.session.correctionNotice != nil)
        #expect(r.session.events.filter { $0.kind == "waitingForTransmission" }.count == 1)
        #expect(r.session.attempts.allSatisfy { $0.correct })
        r.clock.advance(20)
        try await Task.sleep(for: .milliseconds(100))
        #expect(r.session.events.filter { $0.kind == "waitingForTransmission" }.count == 1)
        try await keyK(r)
        #expect(r.session.currentStep?.id == "auth-peer")
        r.session.stop()
    }

    @Test(arguments: Task5StationRole.allCases) func completeExchangeToleratesServiceSpacingButKeepsRadiogramGroups(role: Task5StationRole) async throws {
        let r = try await rig(full: true)
        r.session.configuration.role = role
        r.session.startRadioExchange()
        for _ in 0..<160 where r.session.isSessionActive {
            let s = r.session
            if s.status == .playing {
                r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
            } else if let step = s.currentStep, step.kind == .pause {
                r.clock.advance(step.requiredPauseSeconds); s.tick()
            } else if let step = s.currentStep, let variant = s.variant {
                let target = s.receptionReceipt ?? step
                s.receptionDraft = step.expectedMessages.first ?? ""
                let wire = try #require(target.expectedMessages.first)
                if target.bodyGroups == 0 {
                    s.inputText = Task5Validator.tokens(wire).joined()
                } else {
                    // A missing boundary inside the body remains an error.
                    let rg = try #require(variant.radiograms.first { $0.id == target.radiogramID })
                    let joinedBody = wire.replacingOccurrences(of: rg.groups.prefix(2).joined(separator: " "),
                        with: rg.groups.prefix(2).joined())
                    #expect(!Task5Validator.validate(joinedBody, for: target, variant: variant).isCorrect)
                    // The terminator boundary itself is unambiguous.
                    s.inputText = String(wire.dropLast(2)) + "К"
                }
                s.submit()
            }
        }
        #expect(r.session.status == .completed)
        #expect(r.session.attempts.allSatisfy { $0.correct })
        #expect(r.session.completedGroups(in: .transmit) == 60)
        #expect(r.session.completedGroups(in: .receive) == 60)
    }

    @Test func serviceCommandAlsoRequiresFinalK() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        let speed = r.session.configuration.botSpeed
        r.session.inputText = "ЩРС 10"; r.session.submit()
        #expect(r.session.configuration.botSpeed == speed)
        #expect(r.session.errorMessage == "Завершите служебную команду знаком К.")
        r.session.stop()
    }

    @Test func malformedServiceRequestDoesNotPoisonNextTransmission() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        r.session.inputText = "ЩРС 999 К"; r.session.submit()
        #expect(r.session.errorMessage != nil)
        #expect(r.session.status == .running)
        r.session.keyDown(from: .keyboard)
        #expect(r.session.inputText.isEmpty)
        r.clock.advance(0.08); r.session.keyUp(from: .keyboard)
        r.session.stop()
    }

    @Test func spacingRecoveryNeverRepairsWrongPasswordOrMissingTerminator() async throws {
        let r = try await rig()
        r.session.configuration.role = .subordinate
        r.session.startRadioExchange()
        try await advance(r, until: "auth-request-echo")
        let step = try #require(r.session.currentStep), variant = try #require(r.session.variant)
        let expected = try #require(step.expectedMessages.first)
        #expect(!Task5Validator.validate(String(expected.dropLast()), for: step, variant: variant).isCorrect)
        var groups = Task5Validator.tokens(expected)
        groups[1] = groups[0] // password-command cell differs from this seeded challenge
        #expect(!Task5Validator.validate(groups.joined(), for: step, variant: variant).isCorrect)
        #expect(!Task5Validator.validate(expected.replacingOccurrences(of: "Ц?", with: "Ц�"), for: step, variant: variant).isCorrect)
        r.session.stop()
    }

    @Test(arguments: [5, 8, 11]) func errorSignalRestartsTransmissionOnlyWithEightDots(count: Int) async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        r.session.inputText = "ОШИБКА"
        for _ in 0..<count {
            r.session.keyDown(from: .keyboard)
            r.clock.advance(0.08)
            r.session.keyUp(from: .keyboard)
            r.clock.advance(0.08)
        }
        r.clock.advance(0.3)
        try await Task.sleep(for: .milliseconds(100))
        for _ in 0..<50 where !r.session.buffer.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        if count >= 8 {
            #expect(r.session.inputText.isEmpty)
            #expect(r.session.correctionNotice != nil)
            #expect(r.session.events.contains { $0.kind == "operatorCorrection" && $0.detail.contains("ОШИБКА") })
            #expect(r.session.attempts.isEmpty)
            r.session.inputText = r.session.currentStep!.expectedMessages[0]
            r.session.submit()
            #expect(r.session.currentStep?.id == "call-reply")
        } else {
            #expect(r.session.inputText == "ОШИБКА5")
            #expect(r.session.correctionNotice == nil)
        }
        r.session.stop()
    }

    @Test func acceptedTransmissionKeepsTapeAndDisplayWithoutReusingInput() async throws {
        let r = try await rig()
        let s = r.session
        s.startRadioExchange()
        s.keyDown(from: .keyboard); r.clock.advance(0.08); s.keyUp(from: .keyboard)
        r.clock.advance(0.3)
        try await waitForCharacterCommit(s)
        #expect(s.inputText == "Е")
        let call = s.currentStep!.expectedMessages[0]
        s.inputText = call
        let marks = s.rhythm.marks
        s.submit()
        #expect(s.currentStep?.id == "call-reply")
        #expect(s.inputText.isEmpty)
        #expect(s.lastTransmissionText == call)
        #expect(s.rhythm.marks == marks)
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        #expect(s.currentStep?.id == "quality")
        #expect(s.lastTransmissionText == call)
        #expect(s.rhythm.marks == marks)
        s.keyDown(from: .keyboard); r.clock.advance(0.08); s.keyUp(from: .keyboard)
        r.clock.advance(0.3)
        try await waitForCharacterCommit(s)
        #expect(s.inputText == "Е")
        #expect(s.lastTransmissionText.isEmpty)
        s.stop()
    }

    @Test func focusLossReleasesKeyWithoutPausingExchange() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        r.session.keyDown(from: .keyboard)
        r.clock.advance(0.08)
        r.session.focusLost()
        #expect(!r.session.isKeyDown)
        #expect(r.engine.localKey.last == false)
        #expect(r.session.status == .running)
        r.clock.advance(0.3)
        try await waitForCharacterCommit(r.session)
        #expect(r.session.inputText == "Е")
        r.session.stop()
    }

    @Test func focusLossDoesNotCancelPendingOrPlayingBotReply() async throws {
        let r = try await rig(replyDelay: 0.1)
        r.session.startRadioExchange()
        r.session.inputText = r.session.currentStep!.expectedMessages[0]
        r.session.submit()
        r.session.focusLost()
        #expect(r.session.isWaitingForBot)
        try await Task.sleep(for: .milliseconds(200))
        #expect(r.engine.played.count == 1)
        #expect(r.session.status == .playing)
        r.session.focusLost()
        #expect(r.engine.cancelled.isEmpty)
        #expect(r.session.status == .playing)
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        #expect(r.session.currentStep?.id == "quality")
        #expect(r.session.status == .running)
        r.session.stop()
    }

    @Test func qualityExchangeDoesNotEndAtItsInternalK() async throws {
        let r = try await rig()
        r.session.configuration.role = .subordinate
        r.session.startRadioExchange()
        try await advance(r, until: "quality-reply")
        r.session.inputText = "ЩСА 3 "
        for duration in [0.24, 0.08, 0.24] {
            r.session.keyDown(from: .keyboard); r.clock.advance(duration)
            r.session.keyUp(from: .keyboard); r.clock.advance(0.08)
        }
        r.clock.advance(0.8)
        try await Task.sleep(for: .milliseconds(100))
        #expect(r.session.currentStep?.id == "quality-reply")
        #expect(r.session.status == .running)
        #expect(r.session.errorMessage == nil)
        #expect(r.session.inputText.trimmingCharacters(in: .whitespaces) == "ЩСА 3 К")
        r.session.inputText = "ЩСА 3 К ЩСА? К"
        r.session.submit()
        #expect(r.session.currentStep?.id == "quality-report")
        r.session.stop()
    }

    @Test(arguments: [false, true]) func qualityReportRequiresTerminator(withK: Bool) async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        try await advance(r, until: "quality-report")
        r.session.inputText = "ЩСА "
        for mark in "....-" {
            r.session.keyDown(from: .keyboard); r.clock.advance(mark == "-" ? 0.24 : 0.08)
            r.session.keyUp(from: .keyboard); r.clock.advance(0.08)
        }
        r.clock.advance(0.8)
        try await Task.sleep(for: .milliseconds(100))
        #expect(r.session.currentStep?.id == "quality-report")
        if withK {
            for mark in "-.-" {
                r.session.keyDown(from: .keyboard); r.clock.advance(mark == "-" ? 0.24 : 0.08)
                r.session.keyUp(from: .keyboard); r.clock.advance(0.08)
            }
            r.clock.advance(0.8)
        } else { r.clock.advance(3) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(r.session.currentStep?.id == (withK ? "auth-peer" : "quality-report"))
        if withK { #expect(r.session.attempts.last?.input == "ЩСА 4 К") }
        else { #expect(r.session.inputText.trimmingCharacters(in: .whitespaces) == "ЩСА 4") }
        #expect(r.session.attempts.allSatisfy { $0.correct })
        r.session.stop()
    }

    @Test func keysDuringBotPlaybackDoNotAlterSession() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        r.session.inputText = r.session.currentStep!.expectedMessages[0]; r.session.submit()
        for source in [KeySource.keyboard, .pointer, .hardware] {
            r.session.keyDown(from: source); r.clock.advance(0.24); r.session.keyUp(from: source)
        }
        #expect(r.session.status == .playing)
        #expect(r.engine.cancelled.isEmpty)
        #expect(r.session.inputText.isEmpty)
        #expect(!r.session.isKeyDown)
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        #expect(r.session.currentStep?.id == "quality")
        r.session.stop()
    }

    @Test(arguments: [false, true]) func incorrectQualityReportIsCheckedAutomatically(finalK: Bool) async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        try await advance(r, until: "quality-report")
        r.session.inputText = finalK ? "ЩСА 11 " : "ЩСА 1"
        let pattern = finalK ? "-.-" : ".----"
        for mark in pattern {
            r.session.keyDown(from: .keyboard)
            r.clock.advance(mark == "-" ? 0.24 : 0.08)
            r.session.keyUp(from: .keyboard)
            r.clock.advance(0.08)
        }
        r.clock.advance(0.8)
        try await Task.sleep(for: .milliseconds(100))
        if !finalK {
            #expect(r.session.errorMessage == nil)
            r.clock.advance(3)
            try await Task.sleep(for: .milliseconds(100))
            #expect(r.session.errorMessage == nil)
            #expect(r.session.currentStep?.id == "quality-report")
            r.session.stop()
            return
        }
        #expect(r.session.currentStep?.id == "quality-report")
        #expect(r.session.errorMessage != nil)
        #expect(r.session.attempts.last?.correct == false)
        #expect(r.session.attempts.last?.input == (finalK ? "ЩСА 11 К" : "ЩСА 11"))
        #expect(r.session.status == .playing)
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        r.session.inputText = "ЩСА 3 К"
        r.session.submit()
        #expect(r.session.currentStep?.id == "auth-peer")
        r.session.stop()
    }

    @Test(arguments: Task5StationRole.allCases, [0, 17, 50, 73, 99])
    func chosenPasswordDrivesBotResponseAndSurvivesRestore(role: Task5StationRole, challenge: Int) async throws {
        let r = try await rig()
        r.session.configuration.role = role
        r.session.startRadioExchange()
        let target = role == .main ? "auth-peer" : "auth-counter"
        try await advance(r, until: target)
        let v = try #require(r.session.variant)
        let step = try #require(r.session.currentStep)
        let index = try #require(Task5Validator.chosenPasswordIndex(for: step, variant: v))
        let cell = try #require(v.tdr.cells.first { $0.number == String(format: "%02d", challenge) })
        var wire = Task5Validator.tokens(step.expectedMessages[0])
        wire[index] = try #require(v.tdr.codes(for: cell).last)
        wire[0] = try #require(v.tdr.codes(forExpressionID: "password").last)
        r.session.inputText = wire.joined(separator: " ")
        r.session.submit()
        #expect(r.session.attempts.last?.correct == true)
        #expect(r.session.currentStep?.botMessage == wire.dropLast().joined(separator: " ") + " Ц? К")
        r.session.stop()
        let restored = try await rig()
        try restored.session.restore(data: r.session.exportData())
        #expect(restored.session.currentStep == r.session.currentStep)
        restored.session.resume()
        if role == .main {
            // Echo, Ц К, ОК АС: inspect the actual subsequent answer from the bot.
            restored.engine.emit(restored.engine.lastID, .finished(cancelled: false)); await settle()
            restored.session.inputText = "Ц К"; restored.session.submit()
            restored.engine.emit(restored.engine.lastID, .finished(cancelled: false)); await settle()
            #expect(restored.session.currentStep?.kind == .pause)
            restored.clock.advance(restored.session.currentStep!.requiredPauseSeconds); restored.session.tick()
            #expect(restored.session.currentStep?.id == "auth-counter")
        } else {
            restored.engine.emit(restored.engine.lastID, .finished(cancelled: false)); await settle()
            restored.session.inputText = "Ц К"; restored.session.submit()
            restored.engine.emit(restored.engine.lastID, .finished(cancelled: false)); await settle()
            #expect(restored.session.currentStep?.kind == .pause)
            restored.clock.advance(restored.session.currentStep!.requiredPauseSeconds); restored.session.tick()
            #expect(restored.session.currentStep?.id == "auth-self")
        }
        let response = try #require(restored.session.currentStep?.botMessage)
        #expect(v.tdr.decode(Task5Validator.tokens(response)[1])?.number == String(format: "%02d", abs(50 - challenge)))
        try await advance(restored, until: role == .main ? "rg-0-offer" : "rg-0-ready")
        #expect(restored.session.currentStep?.id == (role == .main ? "rg-0-offer" : "rg-0-ready"))
        #expect(restored.session.attempts.allSatisfy { $0.correct })
        restored.session.stop()
    }

    @Test func majorClosingWaitsForAcknowledgementAndArchiveRestores() async throws {
        let r = try await rig()
        r.session.start()
        try await advance(r, until: "close")
        #expect(r.session.currentStep?.expectedMessages == ["ЩБЕ К"])
        r.session.inputText = "СК"; r.session.submit()
        #expect(r.session.currentStep?.id == "close")
        r.session.inputText = "ЩБЕ К"; r.session.submit()
        #expect(r.session.currentStep?.id == "close-reply")
        #expect(r.session.status == .playing)
        #expect(r.engine.played.last?.tokens.filter { !$0.isGroupGap }.map(\.display).joined() == "ОКЩБЕК")
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        r.session.submit()
        #expect(r.session.status == .completed)
        let restored = try await rig()
        try restored.session.restore(data: r.session.exportData())
        #expect(restored.session.variant == r.session.variant)
        #expect(restored.session.status == .completed)
        #expect(restored.session.variant?.radiograms.count == 2)
    }

    @Test func delayedReplyStartsOnlyAfterWaitingAndStopCancelsIt() async throws {
        let r = try await rig(replyDelay: 0.15)
        r.session.startRadioExchange()
        r.session.inputText = r.session.currentStep!.expectedMessages[0]
        r.session.submit()
        #expect(r.session.isWaitingForBot)
        #expect(r.engine.played.isEmpty)
        try await Task.sleep(for: .milliseconds(250))
        #expect(!r.session.isWaitingForBot)
        #expect(!r.engine.played.isEmpty)
        r.session.stop()

        let stopped = try await rig(replyDelay: 0.15)
        stopped.session.startRadioExchange()
        stopped.session.inputText = stopped.session.currentStep!.expectedMessages[0]
        stopped.session.submit()
        stopped.session.stop()
        try await Task.sleep(for: .milliseconds(250))
        #expect(stopped.engine.played.isEmpty)
        #expect(!stopped.session.isWaitingForBot)
    }

    @Test func pausedRepeatRetainsItsMessageAndCannotPlayWhilePaused() async throws {
        let r = try await rig(replyDelay: 0.15)
        r.session.startRadioExchange()
        r.session.inputText = "ОШИБКА К"
        r.session.submit()
        #expect(r.session.isWaitingForBot)
        r.session.pause()
        try await Task.sleep(for: .milliseconds(250))
        #expect(r.engine.played.isEmpty)
        #expect(!r.session.isWaitingForBot)
        r.session.resume()
        #expect(r.session.isWaitingForBot)
        try await Task.sleep(for: .milliseconds(250))
        #expect(!r.engine.played.isEmpty)
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        #expect(r.session.currentStep?.id == "call")
        #expect(r.session.status == .running)
        r.session.stop()
    }

    /// A scripted operator handles the protocol; the engine still decides when
    /// each audible transmission ends. This is deliberately not a timer shortcut.
    func advance(_ rig: Rig, until target: String? = nil) async throws {
        for _ in 0..<160 {
            let s = rig.session
            if s.currentStep?.id == target && s.status == .running { return }
            if !s.isSessionActive { return }
            if s.status == .playing {
                rig.engine.emit(rig.engine.lastID, .finished(cancelled: false)); await settle()
            } else if let step = s.currentStep, step.kind == .pause {
                rig.clock.advance(step.requiredPauseSeconds); s.tick()
            } else if let step = s.currentStep {
                s.inputText = step.expectedMessages.first ?? ""; s.submit(); await settle()
            }
        }
        Issue.record("Task 5 did not reach \(target ?? "completion")")
    }

    @Test func incomingReceiptRequiresCorrectReceptionAndCanBeRepeated() async throws {
        let r = try await rig()
        r.session.start()
        try await advance(r, until: "rg-0-receipt")
        #expect(r.session.currentStep?.kind == .receive)
        #expect(r.session.canRepeat)
        let groups = r.session.completedGroups
        r.session.inputText = "НЕВЕРНЫЙ Р 999 К"; r.session.submit()
        #expect(r.session.currentStep?.id == "rg-0-receipt")
        r.session.repeatBot()
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        #expect(r.session.currentStep?.id == "rg-0-receipt")
        #expect(r.session.completedGroups == groups)
        r.session.inputText = r.session.currentStep?.expectedMessages.first ?? ""; r.session.submit()
        #expect(r.session.currentStep?.id != "rg-0-receipt")
        r.session.stop()
    }

    @Test func heldKeyCannotBeSubmittedAndStopAlwaysReleasesAudio() async throws {
        let r = try await rig()
        r.session.start(); r.session.submit(); r.session.submit()
        r.session.inputText = r.session.currentStep?.expectedMessages.first ?? ""
        r.session.keyDown(from: .keyboard)
        #expect(!r.session.canSubmit)
        r.session.submit()
        #expect(r.session.currentStep?.id == "call")
        #expect(r.session.isKeyDown)
        r.session.stop()
        #expect(!r.session.isKeyDown)
        #expect(r.engine.localKey.last == false)
    }

    @Test func retryKeepsTheFailedTransmissionAndRestoreKeepsReceptionDraft() async throws {
        let r = try await rig()
        r.session.start(); r.session.submit(); r.session.submit()
        r.session.inputText = "ОШИБКА"
        r.session.retryTransmission()
        #expect(r.session.inputText.isEmpty)
        #expect(r.session.attempts.last?.input == "ОШИБКА")
        #expect(r.session.attempts.last?.correct == false)
        try await advance(r, until: "rg-1")
        r.session.inputText = "001 18 ЧАСТЬ ЗАПИСИ"
        r.session.stop()
        let restored = try await rig()
        try restored.session.restore(data: r.session.exportData())
        #expect(restored.session.inputText == "001 18 ЧАСТЬ ЗАПИСИ")
        #expect(restored.session.status == .paused)
        #expect(restored.session.currentStep?.id == "rg-1")
        restored.session.stop()
    }

    @Test func oldPortableProfileStillRestoresWithoutChangingItsMaterial() async throws {
        let r = try await rig()
        r.session.start(); r.session.stop()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(Task5Export.self, from: r.session.exportData())
        let old = try Task5Scenario.generate(configuration: exported.configuration, seed: exported.seed,
            reference: r.session.reference, catalog: loadCatalog(), profileID: "task5.photos.v1.cell-lookup")
        let archive = Task5Archive(id: exported.id, variant: old, status: .aborted, currentStepIndex: 0,
            elapsedSeconds: 0, elapsedDuration: 0, runtimeBotSpeed: nil, startedAt: exported.startedAt,
            savedAt: exported.savedAt, attempts: [], events: [], completedGroupStepIDs: [],
            revealedStepIDs: [], repeatCount: 0)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try r.session.restore(data: encoder.encode(archive))
        #expect(r.session.variant == old)
        #expect(r.session.variant?.steps.first { $0.id == "rg-0-receipt" }?.kind == .listen)
        r.session.stop()
    }

    @Test(arguments: Task5StationRole.allCases, Task5Length.allCases) func radioExchangeCompletesWithReceiptsInsteadOfUIConfirmations(role: Task5StationRole, length: Task5Length) async throws {
        let r = try await rig()
        r.session.configuration.length = length
        r.session.configuration.role = role
        r.session.startRadioExchange()
        #expect(r.session.currentStep?.id == "call")
        #expect(r.session.teachingTransmission == nil)
        #expect(r.session.automaticGuidanceCount == 0)
        for _ in 0..<160 where r.session.isSessionActive {
            let s = r.session
            if s.status == .playing {
                r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
            } else if let step = s.currentStep, step.kind == .pause {
                r.clock.advance(step.requiredPauseSeconds); s.tick()
            } else if let receipt = s.receptionReceipt {
                s.receptionDraft = s.currentStep?.expectedMessages.first ?? ""
                s.inputText = receipt.expectedMessages.first ?? ""; s.submit()
            } else {
                #expect(s.currentStep?.kind != .administrative)
                s.inputText = s.currentStep?.expectedMessages.first ?? ""; s.submit()
            }
        }
        #expect(r.session.status == .completed)
        #expect(r.session.completedGroups(in: .transmit) == length.transmittedGroups)
        #expect(r.session.completedGroups(in: .receive) == length.transmittedGroups)
        #expect(!r.session.attempts.contains { ["duty", "setup", "report", "journal"].contains($0.stepID) })
    }

    @Test func radioReceiptDoesNotEraseDraftAndWrongNumberCannotAdvance() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        for _ in 0..<80 {
            let s = r.session
            if s.currentStep?.id == "rg-1" && s.status == .running { break }
            if s.status == .playing {
                r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
            } else if let step = s.currentStep, step.kind == .pause {
                r.clock.advance(step.requiredPauseSeconds); s.tick()
            } else { s.inputText = s.currentStep?.expectedMessages.first ?? ""; s.submit() }
        }
        #expect(r.session.currentStep?.id == "rg-1")
        r.session.receptionDraft = "МОЯ ЗАПИСЬ"
        let receipt = try #require(r.session.receptionReceipt)
        r.session.inputText = "НЕВЕРНЫЙ Р 999 К"; r.session.submit()
        #expect(r.session.currentStep?.id == "rg-1")
        #expect(r.session.receptionDraft == "МОЯ ЗАПИСЬ")
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        r.session.inputText = receipt.expectedMessages.first ?? ""; r.session.submit()
        #expect(r.session.currentStep?.id != "rg-1")
        #expect(r.session.attempts.contains { $0.stepID == "rg-1" && !$0.correct && $0.input == "МОЯ ЗАПИСЬ" })
        #expect(r.session.completedGroups(in: .receive) == 0)
        r.session.stop()
    }

    @Test func wrongKeyedTerminatorGetsAudibleRepeatWithoutCheckButton() async throws {
        let r = try await rig()
        r.session.startRadioExchange()
        r.session.inputText = "НЕВЕРНЫЙ "
        for mark in "-.-" {
            r.session.keyDown(from: .keyboard)
            r.clock.advance(mark == "-" ? 0.24 : 0.08)
            r.session.keyUp(from: .keyboard)
            r.clock.advance(0.08)
        }
        r.clock.advance(0.7)
        for _ in 0..<50 where r.session.status != .playing { try await Task.sleep(for: .milliseconds(20)) }
        #expect(r.session.status == .playing)
        #expect(r.session.currentStep?.id == "call")
        #expect(r.session.attempts.last?.correct == false)
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        r.session.keyDown(from: .keyboard)
        #expect(r.session.inputText.isEmpty)
        r.session.stop()
    }

    @Test func restoredLegacyDutyCanResumeAsRadioExchange() async throws {
        let r = try await rig()
        r.session.start(); r.session.stop()
        let data = try r.session.exportData()
        try r.session.restore(data: data)
        try r.session.useRadioFlowForRestoredSession()
        r.session.resume()
        #expect(r.session.currentStep?.id == "call")
        #expect(r.session.usesRadioFlow)
        r.session.stop()
    }

    @Test func cannotStartWithoutReadyEngine() async throws {
        let r = try await rig(ready: false)
        #expect(!r.session.canStart)
        r.session.start()
        #expect(r.session.status == .idle)
        #expect(r.engine.played.isEmpty)
    }

    @Test func cannotStartWhileAnotherModeAwaitsPlaybackCancellation() async throws {
        let r = try await rig()
        let id = try #require(r.audio.play([PlaybackToken(display: "Е", patterns: ["."])], spacing: .text) { _, _ in })
        r.audio.cancel(id)
        #expect(!r.session.canStart)
        r.session.start()
        #expect(r.session.status == .idle)
        r.engine.emit(id, .finished(cancelled: true)); await settle()
        #expect(r.session.canStart)
    }

    @Test func completesBothRadiogramsAndSignalReceipts() async throws {
        let r = try await rig(full: true)
        r.session.start()
        try await advance(r)
        #expect(r.session.status == .completed)
        #expect(r.session.completedGroups == 120)
        #expect(r.session.variant?.radiograms.filter { $0.direction == .transmit }.count == 1)
        #expect(r.session.variant?.radiograms.filter { $0.direction == .receive }.count == 1)
        #expect(r.session.errorCount == 0)
        let data = try r.session.exportData()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Task5Export.self, from: data)
        #expect(archive.status == .completed)
        #expect(archive.completedGroupStepIDs.count == 2)
        #expect(archive.seed == 2483)
        #expect(archive.reviewVariant?.seed == 2483)
    }

    @Test func wrongAuthenticationAndReceiptNeverAdvance() async throws {
        let r = try await rig()
        r.session.start()
        try await advance(r, until: "auth-self")
        #expect(r.session.outboundText == nil)
        r.session.inputText = "З00 К"; r.session.submit()
        #expect(r.session.currentStep?.id == "auth-self")
        #expect(r.session.errorMessage != nil)
        r.session.inputText = r.session.currentStep?.expectedMessages.first ?? ""; r.session.submit()
        try await advance(r, until: "rg-1-receipt")
        r.session.inputText = "НЕВЕРНЫЙ Р 999 К"; r.session.submit()
        #expect(r.session.currentStep?.id == "rg-1-receipt")
        #expect(r.session.errorCount >= 2)
        r.session.stop()
    }

    @Test func learningSuppliesOnlyTheOperatorsServiceCodeAndStillRejectsWrongInput() async throws {
        let r = try await rig()
        r.session.start(); try await advance(r, until: "auth-self")
        #expect(r.session.currentStep?.id == "auth-self")
        #expect(r.session.teachingTransmission == r.session.currentStep?.expectedMessages.first)
        #expect(r.session.teachingTransmission != r.session.currentStep?.botMessage)
        r.session.inputText = "З00 К"; r.session.submit()
        #expect(r.session.currentStep?.id == "auth-self")
        #expect(r.session.lastCheckFeedback?.isCorrect == false)
        #expect(r.session.attempts.last?.aided == true)
        r.session.inputText = r.session.teachingTransmission ?? ""; r.session.submit()
        #expect(r.session.currentStep?.id != "auth-self")
        #expect(r.session.lastCheckFeedback?.isCorrect == true)
        #expect(r.session.attempts.last?.aided == true)
        #expect(r.session.automaticGuidanceCount > 0)
        try await advance(r, until: "rg-1")
        #expect(r.session.teachingTransmission == nil)
        #expect(r.session.outboundText == nil)
        r.session.stop()
    }

    @Test func rehearsalKeepsServiceAndPasswordAnswersBehindExplicitAssistance() async throws {
        let r = try await rig()
        r.session.configuration.rehearsal = true
        r.session.start(); r.session.submit(); r.session.submit()
        #expect(r.session.currentStep?.id == "call")
        #expect(r.session.teachingTransmission == nil)
        try await advance(r, until: "auth-self")
        #expect(r.session.teachingTransmission == nil)
        #expect(r.session.revealedReference == nil)
        #expect(r.session.automaticGuidanceCount == 0)
        #expect(r.session.attempts.allSatisfy { !$0.aided })
        r.session.revealReference()
        #expect(r.session.revealedReference != nil)
        #expect(r.session.hintCount == 1)
        #expect(r.session.teachingTransmission == nil)
        r.session.stop()
    }

    @Test func ordinaryOutgoingRadiogramFormDoesNotCountAsAutomaticServiceHelp() async throws {
        let r = try await rig()
        r.session.start(); try await advance(r, until: "rg-0")
        #expect(r.session.teachingTransmission == nil)
        #expect(r.session.outboundText != nil)
        r.session.inputText = r.session.currentStep?.expectedMessages.first ?? ""; r.session.submit()
        #expect(r.session.attempts.last?.stepID == "rg-0")
        #expect(r.session.attempts.last?.aided == false)
        #expect(r.session.lastCheckFeedback?.text == "Верно")
        r.session.stop()
    }

    @Test func pauseStopAndLateDoneCannotSkipAReceiveStep() async throws {
        let r = try await rig()
        r.session.start()
        r.session.submit(); r.session.submit()
        r.session.inputText = r.session.currentStep?.expectedMessages.first ?? ""; r.session.submit()
        #expect(r.session.status == .playing)
        let old = r.engine.lastID, index = r.session.currentStepIndex
        r.session.pause()
        r.engine.emit(old, .finished(cancelled: false)); await settle()
        #expect(r.session.status == .paused)
        #expect(r.session.currentStepIndex == index)
        r.session.resume()
        let current = r.engine.lastID
        #expect(current != old)
        r.engine.emit(old, .finished(cancelled: false)); await settle()
        #expect(r.session.status == .playing)
        r.session.stop()
        r.engine.emit(current, .finished(cancelled: false)); await settle()
        #expect(r.session.status == .aborted)
        #expect(r.session.currentStepIndex == index)
    }

    @Test func engineCancellationAndFailureAreInterruptedResults() async throws {
        for failed in [false, true] {
            let r = try await rig()
            r.session.start(); r.session.submit(); r.session.submit()
            r.session.inputText = r.session.currentStep?.expectedMessages.first ?? ""; r.session.submit()
            r.engine.emit(r.engine.lastID, failed ? .failed("test failure") : .finished(cancelled: true))
            await settle()
            #expect(r.session.status == .interrupted)
            #expect(r.session.currentStep?.id == "call-reply")
        }
    }

    @Test func repeatUsesBodyGroupLocatorsAndDoesNotCountGroupsTwice() async throws {
        let r = try await rig()
        r.session.start(); try await advance(r, until: "rg-1")
        #expect(r.session.revealedReference == nil)
        #expect(r.session.outboundText == nil)
        let before = r.session.completedGroups, index = r.session.currentStepIndex
        r.session.inputText = "РПТ АА 1 К"; r.session.submit()
        #expect(r.session.status == .playing)
        #expect(r.session.repeatCount == 1)
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
        #expect(r.session.currentStepIndex == index)
        #expect(r.session.completedGroups == before)
        r.session.inputText = r.session.currentStep?.expectedMessages.first ?? ""; r.session.submit()
        #expect(r.session.completedGroups == before + r.session.configuration.length.transmittedGroups)
        r.session.stop()
    }

    @Test func speedRequestAcceptsTerminatorAndDoesNotChangeOperatorTempoOrVariant() async throws {
        let r = try await rig()
        r.session.configuration.botSpeed = 100
        r.session.configuration.keySpeed = 75
        r.session.start(); try await advance(r, until: "rg-1")
        let seed = r.session.variant?.seed, index = r.session.currentStepIndex
        r.session.inputText = "ЩРС 10 К"; r.session.submit()
        #expect(r.session.configuration.botSpeed == 50)
        #expect(r.session.configuration.keySpeed == 75)
        #expect(r.session.variant?.seed == seed)
        #expect(r.session.currentStepIndex == index)
        #expect(r.session.errorMessage == nil)
        r.session.inputText = "QRQ 12 K"; r.session.submit()
        #expect(r.session.configuration.botSpeed == 60)
        r.session.inputText = "QRS 10 K"; r.session.submit()
        #expect(r.session.configuration.botSpeed == 50)
        #expect(r.session.errorMessage == nil)
        r.session.inputText = "ЩРС А К"; r.session.submit()
        #expect(r.session.configuration.botSpeed == 50)
        #expect(r.session.errorMessage != nil)
        r.session.stop()
        let restored = try await rig()
        try restored.session.restore(data: r.session.exportData())
        #expect(restored.session.configuration.botSpeed == 50)
        #expect(restored.session.configuration.keySpeed == 75)
        #expect(restored.session.variant?.seed == seed)
        restored.session.stop()
    }

    @Test func keyedRepeatTerminatorAutomaticallyRequestsTheSameIncomingMessage() async throws {
        let r = try await rig()
        r.session.start(); try await advance(r, until: "rg-1")
        let index = r.session.currentStepIndex
        r.session.inputText = "РПТ "
        for mark in "-.-" {
            r.session.keyDown(from: .keyboard)
            r.clock.advance(mark == "-" ? 0.24 : 0.08)
            r.session.keyUp(from: .keyboard)
            r.clock.advance(0.08)
        }
        r.clock.advance(0.7)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while r.session.status != .playing, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(r.session.status == .playing)
        #expect(r.session.repeatCount == 1)
        #expect(r.session.currentStepIndex == index)
        r.session.stop()
    }

    @Test func hiddenReferenceRequiresAnExplicitRecordedAid() async throws {
        let r = try await rig()
        r.session.start(); try await advance(r, until: "rg-1")
        #expect(r.session.revealedReference == nil)
        #expect(r.session.events.allSatisfy { !$0.detail.contains(r.session.variant!.radiograms[1].groups.joined(separator: " ")) })
        r.session.revealReference()
        #expect(r.session.hintCount == 1)
        #expect(r.session.revealedReference != nil)
        #expect(throws: Task5SessionError.self) { try r.session.exportData() }
        r.session.stop()
    }

    @Test func paperReceptionUsesSelfCheckWithoutAnInventedAccuracy() async throws {
        let r = try await rig()
        r.session.configuration.receptionMode = .paper
        r.session.start(); try await advance(r, until: "rg-1")
        let index = r.session.currentStepIndex
        r.session.submit()
        #expect(r.session.paperReference != nil)
        #expect(r.session.currentStepIndex == index)
        r.session.confirmPaperReception(correct: true)
        let attempt = try #require(r.session.attempts.last)
        #expect(attempt.selfChecked)
        #expect(attempt.errors == nil)
        #expect(r.session.currentStepIndex > index)
        r.session.stop()
    }

    @Test func signalSecondPartWaitsForTheWholeTenSecondGap() async throws {
        let r = try await rig()
        r.session.start(); try await advance(r, until: "signal-0-first")
        r.session.inputText = r.session.currentStep?.expectedMessages.first ?? ""; r.session.submit()
        #expect(r.session.currentStep?.id == "signal-0-pause")
        #expect(!r.session.canSubmit)
        r.clock.advance(9.99); r.session.tick()
        #expect(r.session.currentStep?.id == "signal-0-pause")
        r.clock.advance(0.01); r.session.tick()
        #expect(r.session.currentStep?.id == "signal-0-second")
        r.session.stop()
    }

    @Test func historicalJournalDataIsIgnoredAndDiagnosticsRestorePaused() async throws {
        let r = try await rig()
        r.session.start()
        r.clock.advance(17); r.session.interrupt(reason: "Проверка")
        let data = try r.session.exportData()
        let portable = String(decoding: data, as: UTF8.self)
        #expect(!portable.contains("reviewVariant"))
        #expect(!portable.contains(r.session.variant!.signals[1].group))
        let restored = try await rig()
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy["journal"] = ["obsolete": "Any historical journal shape is ignored"]
        try restored.session.restore(data: JSONSerialization.data(withJSONObject: legacy))
        #expect(restored.session.status == .paused)
        #expect(restored.session.elapsedSeconds == 17)
        #expect(restored.session.events.contains { $0.kind == "interrupted" })
        restored.session.stop()
        let reexported = try #require(JSONSerialization.jsonObject(with: restored.session.exportData()) as? [String: Any])
        #expect(reexported["journal"] == nil)
    }

    @Test func abortResultAndPortableExportDoNotRevealUnheardMaterial() async throws {
        let r = try await rig()
        r.session.start()
        let incoming = try #require(r.session.variant?.radiograms.first { $0.direction == .receive })
        r.session.stop()
        let data = try r.session.exportData()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let portable = try decoder.decode(Task5Export.self, from: data)
        #expect(portable.reviewVariant == nil)
        #expect(!String(decoding: data, as: UTF8.self).contains(incoming.groups.joined(separator: " ")))
    }

    @Test func correctKeyedTerminatorAdvancesWithoutAnotherButtonPress() async throws {
        let r = try await rig()
        r.session.start(); r.session.submit(); r.session.submit()
        let expected = try #require(r.session.currentStep?.expectedMessages.first)
        r.session.inputText = String(expected.dropLast())
        for mark in "-.-" {
            r.session.keyDown(from: .keyboard)
            r.clock.advance(mark == "-" ? 0.24 : 0.08)
            r.session.keyUp(from: .keyboard)
            r.clock.advance(0.08)
        }
        r.clock.advance(0.7)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while r.session.currentStep?.id == "call", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(r.session.currentStep?.id == "call-reply")
        #expect(r.session.status == .playing)
        r.session.stop()
    }

    @Test func storageFailureIsVisibleAndCannotBeReportedAsSaved() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("occupied".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let r = try await rig(archiveDirectory: path)
        r.session.start()
        #expect(r.session.storageError != nil)
        #expect(r.session.isSessionActive)
        r.session.stop()
    }

    @Test func elapsedTimeUsesMonotonicClockInsteadOfWallClockChanges() async throws {
        let engine = ScriptedAudioService(), audio = AudioCoordinator(service: engine)
        let wall = Clock(), monotonic = Clock()
        let s = Task5Session(catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil),
                             archiveDirectory: nil, now: { wall.date }, uptime: { monotonic.date.timeIntervalSinceReferenceDate })
        s.isEnabled = true; s.seedText = "2483"
        engine.startEngine(); await settle(); s.start()
        wall.advance(3600); monotonic.advance(1.25); s.tick()
        #expect(s.elapsedDuration == 1.25)
        wall.advance(-7200); s.tick()
        #expect(s.elapsedDuration == 1.25)
        s.stop()
    }

    @Test func restoredResultCannotClaimAnUninterruptedRehearsalTimeBand() async throws {
        let r = try await rig(full: true)
        r.session.configuration.rehearsal = true
        r.session.start()
        try await advance(r)
        #expect(r.session.timeComparison != nil)
        #expect(!r.session.hasInterruptions)
        let restored = try await rig()
        try restored.session.restore(data: r.session.exportData())
        #expect(restored.session.status == .completed)
        #expect(restored.session.hasInterruptions)
        #expect(restored.session.timeComparison == nil)
    }

    @Test func hardwareInputIsIgnoredWhenInactiveAndNeverEchoesItsSidetone() async throws {
        let r = try await rig()
        r.session.start(); r.session.submit(); r.session.submit()
        r.engine.emit(.hardwareKey(pressed: true)); await settle()
        #expect(r.session.isKeyDown)
        r.clock.advance(0.08)
        r.engine.emit(.hardwareKey(pressed: false)); await settle()
        #expect(r.engine.localKey.isEmpty)
        r.session.stop(); r.session.isEnabled = false
        let buffer = r.session.buffer
        r.engine.emit(.hardwareKey(pressed: true)); await settle()
        #expect(!r.session.isKeyDown)
        #expect(r.session.buffer == buffer)
        r.engine.emit(.hardwareKey(pressed: false)); await settle()
    }

    @Test func fullZeroIsUnambiguousAndUnrelatedKeyUpCannotReleaseHeldKey() async throws {
        let r = try await rig()
        r.session.start(); r.session.submit(); r.session.submit()
        r.session.keyDown(from: .keyboard)
        r.session.keyUp(from: .hardware)
        #expect(r.session.isKeyDown)
        r.clock.advance(0.24); r.session.keyUp(from: .keyboard)
        #expect(r.session.previewCharacter == "Т")
        for _ in 0..<4 {
            r.clock.advance(0.08); r.session.keyDown(from: .keyboard)
            r.clock.advance(0.24); r.session.keyUp(from: .keyboard)
        }
        #expect(r.session.buffer == "-----")
        #expect(r.session.previewCharacter == "0")
        #expect(r.engine.localKey == [true,false,true,false,true,false,true,false,true,false])
        r.session.stop()
    }
}
