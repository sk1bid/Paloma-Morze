import Foundation
import Testing
@testable import PalomaMorse

@MainActor
struct Task5RadiogramPresentationTests {
    @Test(arguments: [Task5Length.thirty, .full]) func fiveColumnFormPreservesEveryWireGroupAndDelimiter(length: Task5Length) throws {
        var configuration = Task5Configuration(); configuration.length = length
        let variant = try Task5Scenario.generate(configuration: configuration, seed: 2483,
            reference: Task5Reference.load(), catalog: loadCatalog())
        let radiogram = try #require(variant.radiograms.first { $0.direction == .transmit })
        let layout = Task5RadiogramFormLayout(radiogram: radiogram, requestedPart: nil)
        #expect(radiogram.groupCount == length.transmittedGroups)
        #expect(layout.rows.count == radiogram.groupCount / 5)
        #expect(layout.rows.allSatisfy { $0.count == 5 })
        #expect(layout.headerFields.map(\.label) == ["Из", "№", "Групп", "День", "Время", "Повтор №"])
        #expect(layout.headerFields.map(\.value).joined(separator: " ") == layout.headerLine)
        #expect(layout.headerFields.first { $0.label == "Время" }?.value.contains(":") == false)
        #expect(layout.rows.flatMap { $0 } == Array(radiogram.groups.indices))
        let body = layout.rows.flatMap { $0.map { radiogram.groups[$0] } }.joined(separator: " ")
        #expect([layout.headerLine, layout.addressLine, body, layout.closingLine].joined(separator: " ") == radiogram.wireText)
        #expect(layout.shortReply == nil)
    }

    @Test(arguments: [0, 4, 5, 59]) func requestedGroupIsHighlightedWithoutReplacingTheFullTelegram(index: Int) throws {
        let variant = try Task5Scenario.generate(configuration: Task5Configuration(), seed: 2483,
            reference: Task5Reference.load(), catalog: loadCatalog())
        let radiogram = try #require(variant.radiograms.first { $0.direction == .transmit })
        let layout = Task5RadiogramFormLayout(radiogram: radiogram, requestedPart: .group(index))
        #expect(layout.rows.flatMap { $0 }.filter(layout.isRequested) == [index])
        #expect(layout.rows.flatMap { $0 }.count == 60)
        #expect(layout.shortReply == radiogram.groups[index] + " К")
        #expect(layout.headerLine == radiogram.header + " =")
        #expect(layout.addressLine == radiogram.urgencyCode + " " + radiogram.address + " =")
    }

    @Test func headerRepeatHighlightsServiceLinesAndKeepsBody() throws {
        let variant = try Task5Scenario.generate(configuration: Task5Configuration(), seed: 2483,
            reference: Task5Reference.load(), catalog: loadCatalog())
        let radiogram = try #require(variant.radiograms.first { $0.direction == .transmit })
        let layout = Task5RadiogramFormLayout(radiogram: radiogram, requestedPart: .header)
        #expect(layout.isHeaderRequested)
        #expect(!radiogram.groups.indices.contains(where: layout.isRequested))
        #expect(layout.shortReply == Task5RepeatRequest.header.reply(for: radiogram))
        #expect(layout.rows.flatMap { $0 }.count == 60)
    }

    @Test func oldPasswordMeaningsDisappearFromTheRadiogramWhileDisclosureHistoryRemains() async throws {
        let harness = Task5SessionTests(), r = try await harness.rig()
        r.session.startRadioExchange()
        try await harness.advance(r, until: "auth-counter-wait")
        #expect(r.session.displayedCodeMeanings.isEmpty)
        let latestFrame = r.session.events.last { $0.kind == "botDone" && !($0.codeMeanings ?? []).isEmpty }?.codeMeanings
        r.session.inputText = "ОК АС 1 К"; r.session.submit()
        #expect(r.session.displayedCodeMeanings == latestFrame)
        #expect(!r.session.acknowledgedCodeMeanings.isEmpty)
        try await harness.advance(r, until: "rg-0")
        #expect(r.session.displayedCodeMeanings.isEmpty)
        #expect(!r.session.acknowledgedCodeMeanings.isEmpty)
        #expect(r.session.outgoingRadiogram?.id == "rg-0")
        r.session.stop()
    }

    @Test func urgencyMeaningIsGatedAndOnlyDisplayedDuringItsOwnOfferExchange() async throws {
        let harness = Task5SessionTests(), r = try await harness.rig()
        r.session.startRadioExchange()
        try await harness.advance(r, until: "rg-1-ready")
        #expect(r.session.displayedCodeMeanings.isEmpty)
        #expect(r.session.outgoingRadiogram == nil)
        r.session.inputText = "ОК АС 1 К"; r.session.submit()
        let incoming = try #require(r.session.variant?.radiograms.first { $0.direction == .receive })
        #expect(r.session.displayedCodeMeanings.map(\.code) == [incoming.urgencyCode])
        #expect(!r.session.displayedCodeMeanings.contains { $0.expression?.contains("Пароль") == true })
        r.session.inputText = "ЩРЖ К"; r.session.submit()
        #expect(r.session.currentStep?.id == incoming.id)
        #expect(r.session.displayedCodeMeanings.isEmpty)
        #expect(r.session.outgoingRadiogram == nil)
        r.session.stop()
    }
}
