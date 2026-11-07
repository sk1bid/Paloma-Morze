import Foundation
import Testing
@testable import PalomaMorse

@MainActor
struct Task5RadiogramRepairTests {
    private let harness = Task5SessionTests()

    private func outgoing() async throws -> (Task5SessionTests.Rig, Task5Radiogram) {
        let r = try await harness.rig()
        r.session.startRadioExchange()
        try await harness.advance(r, until: "rg-0")
        let rg = try #require(r.session.variant?.radiograms.first { $0.direction == .transmit })
        return (r, rg)
    }
    private func finishedRequest(_ r: Task5SessionTests.Rig) async {
        r.engine.emit(r.engine.lastID, .finished(cancelled: false)); await settle()
    }
    private func replacingGroups(_ rg: Task5Radiogram, _ groups: [String]) -> String {
        rg.header + " = \(rg.urgencyCode) \(rg.address) = " + groups.joined(separator: " ") + " К"
    }

    @Test func repeatedBadCorrectionAndMultipleGroupsPreserveEverythingElseAndCountOnce() async throws {
        let (r, rg) = try await outgoing()
        let before = r.session.completedGroups
        var bad = rg.groups
        bad[0] = "00000"; bad[2] = "11111"
        r.session.inputText = replacingGroups(rg, bad); r.session.submit()
        #expect(r.session.radiogramRepair?.part == .group(0))
        #expect(r.session.events.last { $0.kind == "radiogramRepeatRequested" }?.detail == "РПТ ГР 1 К")
        await finishedRequest(r)
        r.session.inputText = "22222 К"; r.session.submit()
        #expect(r.session.radiogramRepair?.part == .group(0))
        #expect(r.session.completedGroups == before)
        await finishedRequest(r)
        r.session.inputText = rg.groups[0] + " К"; r.session.submit()
        #expect(r.session.radiogramRepair?.part == .group(2))
        #expect(r.session.radiogramRepair?.draft.contains(rg.groups[1]) == true)
        #expect(r.session.completedGroups == before)
        await finishedRequest(r)
        r.session.inputText = rg.groups[2] + " К"; r.session.submit()
        #expect(r.session.radiogramRepair == nil)
        #expect(r.session.currentStep?.id == "rg-0-receipt")
        #expect(r.session.completedGroups == before + rg.groupCount)
        #expect(r.session.attempts.filter { $0.stepID == rg.id && $0.inputMethod == "assembled" }.count == 1)
        #expect(r.session.attempts.last { $0.inputMethod == "assembled" }?.input == rg.wireText)
        r.session.stop()
    }

    @Test(arguments: ["header", "address"]) func headerAndAddressUseExistingPBLFragmentAndPreserveCorrectBody(section: String) async throws {
        let (r, rg) = try await outgoing()
        let broken = section == "header" ? rg.wireText.replacingOccurrences(of: rg.header, with: "000 1 000000 000") :
            rg.wireText.replacingOccurrences(of: rg.address, with: "00000 11111")
        r.session.inputText = broken; r.session.submit()
        #expect(r.session.radiogramRepair?.part == .header)
        #expect(r.session.events.last { $0.kind == "radiogramRepeatRequested" }?.detail == "РПТ ПБЛ К")
        await finishedRequest(r)
        r.session.inputText = try #require(Task5RepeatRequest.header.reply(for: rg)); r.session.submit()
        #expect(r.session.currentStep?.id == "rg-0-receipt")
        #expect(r.session.attempts.last { $0.inputMethod == "assembled" }?.input == rg.wireText)
        r.session.stop()
    }

    @Test func wrongHeaderThenBodyRequestsEachRemainingPart() async throws {
        let (r, rg) = try await outgoing()
        var groups = rg.groups; groups[1] = "00000"
        let wrong = replacingGroups(rg, groups).replacingOccurrences(of: rg.header, with: "000 1 000000 000")
        r.session.inputText = wrong; r.session.submit(); await finishedRequest(r)
        r.session.inputText = "000 1 000000 000 = \(rg.urgencyCode) \(rg.address) = К"; r.session.submit()
        #expect(r.session.radiogramRepair?.part == .header)
        await finishedRequest(r)
        r.session.inputText = try #require(Task5RepeatRequest.header.reply(for: rg)); r.session.submit()
        #expect(r.session.radiogramRepair?.part == .group(1))
        await finishedRequest(r)
        r.session.inputText = rg.groups[1] + " К"; r.session.submit()
        #expect(r.session.currentStep?.id == "rg-0-receipt")
        r.session.stop()
    }

    @Test(arguments: [-1, 1]) func shiftedBodyCountRequestsAllInsteadOfMisidentifyingGroups(delta: Int) async throws {
        let (r, rg) = try await outgoing()
        var groups = rg.groups
        if delta < 0 { groups.removeFirst() } else { groups.insert("00000", at: 0) }
        r.session.inputText = replacingGroups(rg, groups); r.session.submit()
        #expect(r.session.radiogramRepair?.part == .all)
        #expect(r.session.events.last { $0.kind == "radiogramRepeatRequested" }?.detail == "РПТ АЛ К")
        await finishedRequest(r)
        r.session.inputText = rg.wireText; r.session.submit()
        #expect(r.session.currentStep?.id == "rg-0-receipt")
        r.session.stop()
    }

    @Test func partialRepairMustHaveKAndRestoreKeepsValidatedDraft() async throws {
        let (r, rg) = try await outgoing()
        var groups = rg.groups; groups[1] = "00000"
        r.session.inputText = replacingGroups(rg, groups); r.session.submit(); await finishedRequest(r)
        let saved = try #require(r.session.radiogramRepair)
        r.session.inputText = rg.groups[1]; r.session.submit()
        #expect(r.session.radiogramRepair == saved)
        await finishedRequest(r)
        r.session.stop()
        let restored = try await harness.rig()
        try restored.session.restore(data: r.session.exportData())
        #expect(restored.session.radiogramRepair == saved)
        restored.session.resume(); await finishedRequest(restored)
        restored.session.inputText = rg.groups[1] + " К"; restored.session.submit()
        #expect(restored.session.currentStep?.id == "rg-0-receipt")
        #expect(restored.session.completedGroups(in: .transmit) == rg.groupCount)
        restored.session.stop()
    }

    @Test func keyedPartialResponseCompletesWithoutFullRadiogramLength() async throws {
        let (r, rg) = try await outgoing()
        var groups = rg.groups; groups[0] = "00000"
        r.session.inputText = replacingGroups(rg, groups); r.session.submit(); await finishedRequest(r)
        r.session.inputText = rg.groups[0] + " "
        try await harness.keyK(r)
        for _ in 0..<50 where r.session.currentStep?.id == rg.id { try await Task.sleep(for: .milliseconds(20)) }
        #expect(r.session.currentStep?.id == "rg-0-receipt")
        r.session.stop()
    }

    @Test(arguments: [false, true]) func restoreRepairStartsFreshOrPreservesAnUnfinishedFragment(partlyKeyed: Bool) async throws {
        let (r, rg) = try await outgoing()
        var groups = rg.groups; groups[0] = "00000"
        r.session.inputText = replacingGroups(rg, groups); r.session.submit()
        if partlyKeyed {
            await finishedRequest(r)
            r.session.inputText = String(rg.groups[0].prefix(2))
        }
        r.session.stop()
        let restored = try await harness.rig()
        try restored.session.restore(data: r.session.exportData())
        restored.session.resume(); await finishedRequest(restored)
        #expect(restored.session.inputText == (partlyKeyed ? String(rg.groups[0].prefix(2)) : ""))
        restored.session.inputText += partlyKeyed ? String(rg.groups[0].dropFirst(2)) + " " : rg.groups[0] + " "
        try await harness.keyK(restored)
        for _ in 0..<50 where restored.session.currentStep?.id == rg.id { try await Task.sleep(for: .milliseconds(20)) }
        #expect(restored.session.currentStep?.id == "rg-0-receipt")
        #expect(restored.session.completedGroups(in: .transmit) == rg.groupCount)
        restored.session.stop()
    }

    @Test(arguments: ["partial", "wordGap", "emptyBody"]) func eightDotsCancelsOnlyCurrentOrLastRadiogramGroup(boundary: String) async throws {
        let (r, rg) = try await outgoing()
        let prefix = rg.header + " = \(rg.urgencyCode) \(rg.address) = "
        r.session.inputText = prefix + (boundary == "partial" ? rg.groups[0] + " ОШИ" : boundary == "wordGap" ? rg.groups[0] + " " : "")
        for _ in 0..<8 {
            r.session.keyDown(from: .keyboard); r.clock.advance(0.08)
            r.session.keyUp(from: .keyboard); r.clock.advance(0.08)
        }
        r.clock.advance(0.3)
        for _ in 0..<50 where !r.session.buffer.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let expected = boundary == "partial" ? prefix + rg.groups[0] + " " : prefix
        #expect(r.session.inputText == expected)
        #expect(r.session.currentStep?.id == rg.id)
        #expect(r.session.correctionNotice?.contains("группу") == true)
        r.session.stop()
    }

    @Test func paperReceiptStillAdvancesWithoutAutomaticReceptionAccuracy() async throws {
        let r = try await harness.rig()
        r.session.configuration.receptionMode = .paper
        r.session.startRadioExchange()
        try await harness.advance(r, until: "rg-1")
        let receipt = try #require(r.session.receptionReceipt?.expectedMessages.first)
        r.session.inputText = receipt; r.session.submit()
        #expect(r.session.currentStep?.id != "rg-1")
        #expect(!r.session.attempts.contains { $0.stepID == "rg-1" && $0.inputMethod == "reception" })
        #expect(r.session.events.contains { $0.kind == "paperUnverified" })
        r.session.stop()
    }
}
