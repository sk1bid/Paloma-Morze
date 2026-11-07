import Foundation
import Testing
@testable import PalomaMorse

@MainActor
struct Task5DomainTests {
    let catalog: MorseCatalog
    let reference: Task5Reference

    init() throws {
        catalog = try loadCatalog()
        reference = try Task5Reference.load()
    }

    func variant(seed: UInt64 = 17, configuration: Task5Configuration? = nil) throws -> Task5Variant {
        try Task5Scenario.generate(configuration: configuration ?? Task5Configuration(), seed: seed, reference: reference, catalog: catalog)
    }

    @Test(arguments: Task5StationRole.allCases) func everyMessageRequiresFinalK(role: Task5StationRole) throws {
        var config = Task5Configuration(); config.role = role
        let v = try variant(configuration: config)
        for original in v.steps where original.kind != .pause && original.kind != .administrative {
            let step = Task5Validator.resolvedStep(original, variant: v, attempts: [])
            if let message = step.botMessage { #expect(Task5Validator.tokens(message).last == "К") }
            for message in step.expectedMessages {
                #expect(Task5Validator.tokens(message).last == "К")
                #expect(Task5Validator.validate(message, for: step, variant: v).isCorrect)
                #expect(!Task5Validator.validate(String(message.dropLast()), for: step, variant: v).isCorrect)
            }
        }
    }

    @Test func authenticationUsesAbsoluteDifferenceForEveryTwoDigitNumber() {
        for number in 0...99 {
            let expected = number > 50 ? number - 50 : 50 - number
            #expect(Task5Scenario.authenticationAnswer(to: number) == expected)
        }
        #expect(Task5Scenario.authenticationAnswer(to: 17) == 33)
        #expect(Task5Scenario.authenticationAnswer(to: 73) == 23)
        #expect(Task5Scenario.authenticationAnswer(to: 50) == 0)
    }

    @Test(arguments: Task5StationRole.allCases) func authenticationHasNineMessagesAndValidatesDecodedNumbers(role: Task5StationRole) throws {
        var config = Task5Configuration(); config.role = role
        let v = try variant(configuration: config)
        let steps = v.steps.filter { $0.id.hasPrefix("auth-") && $0.kind != .pause }
        #expect(steps.count == 9)
        #expect(steps[1].authenticationTokens?.suffix(2) == ["Ц?", "К"])
        #expect(steps[2].expectedMessages == ["Ц К"])
        #expect(Task5Validator.waitMinutes(steps[3].expectedMessages[0]) != nil)
        #expect(steps[5].authenticationTokens?.suffix(2) == ["Ц?", "К"])
        #expect(steps[6].expectedMessages == ["Ц К"])
        #expect(Task5Validator.waitMinutes(steps[7].expectedMessages[0]) != nil)
        let firstNumber = Int(steps[0].authenticationTokens![1])!
        let firstAnswer = Int(steps[4].authenticationTokens![1])!
        let secondNumber = Int(steps[4].authenticationTokens![2])!
        let secondAnswer = Int(steps[8].authenticationTokens![1])!
        #expect(firstAnswer == abs(50 - firstNumber))
        #expect(secondAnswer == abs(50 - secondNumber))
        let mainDirections: [Task5Direction] = [.transmit, .receive, .transmit, .receive, .receive, .transmit, .receive, .transmit, .transmit]
        #expect(steps.map(\.direction) == mainDirections.map { role == .main ? $0 : ($0 == .transmit ? .receive : .transmit) })
        for step in steps {
            #expect(Task5Validator.validate(step.expectedMessages[0], for: step, variant: v).isCorrect)
            guard let rules = step.authenticationTokens else { continue }
            let alternatives = rules.map { rule in
                if rule == "password" { return v.tdr.codes(forExpressionID: "password").last! }
                if let cell = v.tdr.cells.first(where: { $0.number == rule }) { return v.tdr.codes(for: cell).last! }
                return rule
            }.joined(separator: " ")
            #expect(Task5Validator.validate(alternatives, for: step, variant: v).isCorrect)
        }
        let final = steps[8]
        var wrong = Task5Validator.tokens(final.expectedMessages[0])
        let wrongNumber = String(format: "%02d", (secondAnswer + 1) % 100)
        wrong[1] = v.tdr.codes(for: v.tdr.cells.first { $0.number == wrongNumber }!)[0]
        #expect(!Task5Validator.validate(wrong.joined(separator: " "), for: final, variant: v).isCorrect)
        #expect(!Task5Validator.validate("Ц К", for: final, variant: v).isCorrect)
    }

    @Test(arguments: Task5StationRole.allCases, Task5Length.allCases)
    func completeMajorProfileUsesAgreedWireForms(role: Task5StationRole, length: Task5Length) throws {
        for charset in [Task5Charset.letters, .digits] {
            var config = Task5Configuration()
            config.role = role; config.length = length; config.radiogramCharset = charset
            let v = try variant(configuration: config)
            #expect(v.radiograms.count == 2)
            for rg in v.radiograms {
                #expect(rg.groupCount == length.transmittedGroups)
                #expect(rg.charset == charset)
                #expect(rg.declaredGroupCount == rg.groupCount + 2)
                #expect(rg.header.hasPrefix(rg.originCallsign + " " + rg.number + " "))
                #expect(rg.receipt == "Р \(rg.number) К")
                let body = rg.wireText.components(separatedBy: " = ").last!
                #expect(body == rg.groups.joined(separator: " ") + " К")
                let step = v.steps.first { $0.id == rg.id }!
                #expect(Task5Validator.validate(rg.wireText, for: step, variant: v).isCorrect)
                #expect(!Task5Validator.validate(rg.wireText.replacingOccurrences(of: " К", with: " \(rg.operatorGroup) К"), for: step, variant: v).isCorrect)
            }
            for signal in v.signals {
                let call = try #require(signal.networkCallsign)
                #expect(signal.firstPart == "ЬЬЬ ЬЬЬ \(call) \(call) \(signal.group) \(signal.group) К")
                #expect(signal.secondPart == signal.firstPart)
                let receiptIndex = v.steps.firstIndex { $0.id == signal.id + "-receipt" }!
                #expect(v.steps[receiptIndex + 1].id == signal.id + "-report")
            }
            #expect(v.steps.first { $0.id == "close" }?.expectedMessages == ["ЩБЕ К"])
            #expect(v.steps.first { $0.id == "close-reply" }?.expectedMessages == ["ОК ЩБЕ К"])
        }
    }

    @Test func oldMajorAuthenticationProfileRetainsFourRadiogramsAndOldSignals() throws {
        let old = try Task5Scenario.generate(configuration: Task5Configuration(), seed: 17,
            reference: reference, catalog: catalog, profileID: "task5.photos.v4.major-authentication")
        #expect(old.radiograms.count == 4)
        #expect(old.radiograms.allSatisfy { $0.majorFormat == nil && $0.groupCount == 30 })
        #expect(old.signals.allSatisfy { $0.networkCallsign == nil })
        #expect(old.steps.first { $0.id == "close" }?.expectedMessages == ["СК", "СК К"])
    }

    @Test func outgoingErrorIdentifiesTheWrongGroup() throws {
        let v = try variant()
        let step = v.steps.first { $0.id == "call" }!
        let result = Task5Validator.validate("\(v.botCallsign) ДЕ ОШИБКА К", for: step, variant: v)
        #expect(!result.isCorrect)
        #expect(result.message?.contains("Группа 3") == true)
        #expect(result.message?.contains(v.ownCallsign) == true)
    }

    @Test func generatedNumbersVaryButRadiogramAndReceiptMustAgree() throws {
        let variants = try (1...12).map { seed in
            try Task5Scenario.generate(configuration: Task5Configuration(), seed: UInt64(seed), reference: reference, catalog: catalog)
        }
        let ratings = variants.map { v in
            Task5Validator.resolvedStep(v.steps.first { $0.id == "quality-reply" }!, variant: v, attempts: []).botMessage!
        }
        #expect(Set(ratings).count == 5)
        #expect(Set(variants.map { $0.radiograms[0].number }).count > 1)
        #expect(Set(variants.map { $0.radiograms[0].dateTime }).count > 1)
        #expect(Set(variants.map { $0.radiograms[0].address }).count > 1)
        #expect(Set(variants.map { $0.signals[0].group }).count > 1)
        #expect(Set(variants.map { $0.steps.first { $0.id == "auth-peer" }!.authenticationTokens![1] }).count > 1)
        for v in variants {
            let rg = v.radiograms[0]
            let tx = v.steps.first { $0.id == rg.id }!
            #expect(Task5Validator.validate(rg.wireText, for: tx, variant: v).isCorrect)
            var wrong = Task5Validator.tokens(rg.wireText)
            wrong[1] = String(format: "%03d", (Int(rg.number)! + 1) % 100)
            #expect(!Task5Validator.validate(wrong.joined(separator: " "), for: tx, variant: v).isCorrect)
            let receipt = v.steps.first { $0.id == rg.id + "-receipt" }!
            #expect(Task5Validator.validate("Р \(rg.number) К", for: receipt, variant: v).isCorrect)
            #expect(!Task5Validator.validate("Р \(wrong[1]) К", for: receipt, variant: v).isCorrect)
        }
    }

    @Test func qualityRatingIsChosenByOperatorForBothRoles() throws {
        for role in [Task5StationRole.main, .subordinate] {
            var config = Task5Configuration()
            config.role = role
            let v = try variant(configuration: config)
            let step = v.steps.first { $0.id == (role == .main ? "quality-report" : "quality-reply") }!
            let suffix = role == .main ? " К" : " К ЩСА? К"
            for rating in 1...5 {
                #expect(Task5Validator.validate("ЩСА \(rating)\(suffix)", for: step, variant: v).isCorrect)
            }
            for rating in ["0", "6", "10", "11", "-1", "3.5", "А"] {
                #expect(!Task5Validator.validate("ЩСА \(rating)\(suffix)", for: step, variant: v).isCorrect)
            }
            #expect(!Task5Validator.validate("ЩСА 4 К К К", for: step, variant: v).isCorrect)
        }
    }

    @Test func majorQualityMatchesReadableJournalAndOldProfileRemainsStable() throws {
        let v = try variant()
        #expect(v.steps.first { $0.id == "quality" }?.expectedMessages.first == "ЩСА? К")
        #expect(v.steps.first { $0.id == "quality-reply" }?.botMessage == "ЩСА 3 К ЩСА? К")
        #expect(v.steps.first { $0.id == "quality-report" }?.expectedMessages == ["ЩСА 3 К"])
        let old = try Task5Scenario.generate(configuration: Task5Configuration(), seed: 17,
            reference: reference, catalog: catalog, profileID: "task5.photos.v2.checked-receipts")
        #expect(old.steps.first { $0.id == "quality" }?.expectedMessages.first == "ЩСА? ЩРК? К")
        #expect(!old.steps.contains { $0.id == "quality-report" })
    }

    @Test func subordinateRoleChangesBothDirectionsAndSurvivesCoding() throws {
        var config = Task5Configuration()
        config.role = .subordinate
        let v = try variant(configuration: config)
        #expect(v.steps.first { $0.id == "call" }?.botMessage == "\(v.ownCallsign) ДЕ \(v.botCallsign) К")
        #expect(v.steps.first { $0.id == "call-reply" }?.expectedMessages == ["\(v.botCallsign) ДЕ \(v.ownCallsign) К"])
        #expect(v.steps.first { $0.id == "quality-reply" }?.expectedMessages.contains("ЩСА 3 К ЩСА? К") == true)
        #expect(v.radiograms.map(\.direction) == [.receive, .transmit])
        #expect(v.signals.map(\.direction) == [.receive, .transmit])
        #expect(v.steps.first { $0.id == "close" }?.kind == .listen)
        let decoded = try JSONDecoder().decode(Task5Variant.self, from: JSONEncoder().encode(v))
        #expect(decoded.configuration.role == .subordinate)
        #expect(decoded == (try variant(configuration: decoded.configuration)))
        let oldConfig = try JSONDecoder().decode(Task5Configuration.self, from: JSONEncoder().encode(Task5Configuration()))
        #expect(oldConfig.role == .main)
    }

    @Test func replayKeepsTheEntireMaterialAndSerializesLosslessly() throws {
        let first = try variant()
        #expect(first == (try variant()))
        #expect(first != (try variant(seed: 18)))
        let decoded = try JSONDecoder().decode(Task5Variant.self, from: JSONEncoder().encode(first))
        #expect(decoded == first)
        #expect(first.steps.map(\.id).count == Set(first.steps.map(\.id)).count)
    }

    @Test func callsignsHaveOneDigitAndTDRRowsExcludeZe() throws {
        for seed in 1...100 {
            let v = try Task5Scenario.generate(configuration: Task5Configuration(), seed: UInt64(seed), reference: reference, catalog: catalog)
            let network = try #require(v.signals.first?.networkCallsign)
            for call in [v.ownCallsign, v.botCallsign, network] {
                #expect(call.count == 4)
                #expect(call.filter { "0123456789".contains($0) }.count == 1)
            }
            #expect(Set([v.ownCallsign, v.botCallsign, network]).count == 3)
            #expect(!v.tdr.rowKeys.joined().contains("З"))
            #expect(Set(v.tdr.rowKeys.joined()).count == 20)
            for cell in v.tdr.cells {
                for code in v.tdr.codes(for: cell) { #expect(v.tdr.decode(code) == cell) }
            }
        }
        for call in ["КВМЗ", "А12Б"] {
            var config = Task5Configuration(); config.ownCallsign = call
            #expect(throws: Task5Scenario.GenerationError.self) {
                try Task5Scenario.generate(configuration: config, seed: 1, reference: reference, catalog: catalog)
            }
        }
    }

    @Test func regenerationKeepsCustomCallsignsAndRejectsMorseAliases() throws {
        var config = Task5Configuration()
        config.ownCallsign = "квм3"; config.botCallsign = "туч4"
        let first = try variant(configuration: config)
        let second = try variant(seed: 888, configuration: config)
        #expect(first.ownCallsign == "КВМ3")
        #expect(second.ownCallsign == first.ownCallsign)
        #expect(second.botCallsign == first.botCallsign)
        #expect(second.tdr.rowKeys != first.tdr.rowKeys)
        config.ownCallsign = "АА1"; config.botCallsign = "AA1"
        #expect(throws: Task5Scenario.GenerationError.self) { try variant(configuration: config) }
        config.botCallsign = "🐟🐟🐟"
        #expect(throws: Task5Scenario.GenerationError.self) { try variant(configuration: config) }
    }

    @Test func latinCallsignsAcceptKeyedCyrillicMorseAliasesWithoutVisualConfusion() throws {
        var config = Task5Configuration()
        config.ownCallsign = "ABC0"; config.botCallsign = "ZX9"
        let v = try variant(configuration: config)
        let call = try #require(v.steps.first { $0.id == "call" })
        #expect(Task5Validator.validate("ЗЬ9 ДЕ АБЦ0 К", for: call, variant: v).isCorrect)
        #expect(Task5Validator.validate("ZX9 DE ABC0 K", for: call, variant: v).isCorrect)
        #expect(!Task5Validator.validate("ЗЬ9 ДЕ АВЦ0 К", for: call, variant: v).isCorrect)
        #expect(!Task5Validator.validate("ЗЬ9 ДЕ АБЦТ К", for: call, variant: v).isCorrect)
        let rg = v.radiograms[1]
        let receipt = try #require(v.steps.first { $0.id == rg.id + "-receipt" })
        #expect(Task5Validator.validate("Р \(rg.number) К", for: receipt, variant: v).isCorrect)
        #expect(Task5Validator.tokens("ABCDEFGHIJKLMNOPQRSTUVWXYZ") == ["АБЦДЕФГХИЙКЛМНОПЩРСТУЖВЬЫЗ"])
        #expect(Task5Validator.tokens("B В T 0 001 # 🐟") == ["Б", "В", "Т", "0", "001", "#", "🐟"])
        #expect(Task5Validator.tokens("ß é λ") == ["ß", "é", "λ"])
        #expect(Task5Validator.tokens("001 = 00002") == ["001", "=", "00002"])
        #expect(Task5RepeatRequest.parse("RPT AA 2 K") == .after("2"))
    }

    @Test func fullLoadContainsOneRadiogramEachWayWithoutCountingAddressGroups() throws {
        let full = try variant()
        #expect(full.totalBodyGroups == 120)
        #expect(full.radiograms.map(\.direction) == [.transmit, .receive])
        #expect(full.radiograms.map(\.charset) == [.letters, .letters])
        #expect(full.radiograms.allSatisfy { $0.groupCount == 60 && $0.groups.allSatisfy { $0.count == 5 } })
        #expect(full.steps.reduce(0) { $0 + $1.bodyGroups } == 120)
        var config = Task5Configuration(); config.length = .short
        let short = try variant(configuration: config)
        #expect(short.totalBodyGroups == 12)
        #expect(short.radiograms.allSatisfy { $0.groupCount == 6 })
        #expect(short.radiograms.allSatisfy { Task5Validator.tokens($0.header)[2] == "8" })
        #expect(full.radiograms.allSatisfy { $0.declaredGroupCount == 62 && !$0.wireText.hasSuffix($0.operatorGroup + " К") })
    }

    @Test func operatorVolumeIsThirtyOrSixtyInOneRadiogram() throws {
        #expect(Task5Length.allCases == [.thirty, .full])
        for length in Task5Length.allCases {
            var config = Task5Configuration(); config.length = length
            let v = try variant(configuration: config)
            for direction in Task5Direction.allCases {
                let grams = v.radiograms.filter { $0.direction == direction }
                #expect(grams.count == 1)
                #expect(grams.reduce(0) { $0 + $1.groupCount } == length.transmittedGroups)
                #expect(Set(grams.map(\.charset)) == Set([Task5Charset.letters]))
                #expect(grams.allSatisfy { $0.declaredGroupCount == $0.groupCount + 2 })
            }
            #expect(v.totalBodyGroups == length.transmittedGroups * 2)
        }
    }

    @Test func allCellsRoundTripAndEquivalentCommandsAcceptAlternativeAxisLetters() throws {
        let v = try variant()
        #expect(v.tdr.cells.count == 100)
        #expect(v.tdr.cells.first?.number == "00")
        #expect(v.tdr.cells.last?.number == "99")
        #expect(Set(v.tdr.rowKeys.joined()).count == 20)
        #expect(Set(v.tdr.columnKeys.joined()).count == 20)
        for cell in v.tdr.cells {
            let codes = v.tdr.codes(for: cell)
            #expect(codes.count == 4)
            #expect(codes.allSatisfy { v.tdr.decode($0) == cell })
        }
        let legacy = try Task5Scenario.generate(configuration: Task5Configuration(), seed: 17,
            reference: reference, catalog: catalog, profileID: "task5.photos.v3.major-quality")
        let step = try #require(legacy.steps.first { $0.id == "auth-self" })
        let challenge = try #require(v.tdr.cells.first { $0.number == step.tdrCellNumber })
        let alternatives = v.tdr.codes(for: challenge)
        #expect(alternatives.count == 4)
        for code in alternatives { #expect(Task5Validator.validate(code + " К", for: step, variant: v).isCorrect) }
        let wrongCode = try #require(v.tdr.codes(forExpressionID: "air").first)
        #expect(!Task5Validator.validate(wrongCode + " К", for: step, variant: v).isCorrect)
        let otherCell = try #require(v.tdr.cells(forExpressionID: "password").first { $0.number != challenge.number })
        #expect(!Task5Validator.validate(v.tdr.codes(for: otherCell)[0] + " К", for: step, variant: v).isCorrect)
        #expect(!Task5Validator.validate(alternatives[0], for: step, variant: v).isCorrect)
    }

    @Test func radiogramsValidateHeaderAddressBoundariesAndEquivalentUrgency() throws {
        let v = try variant()
        let rg = v.radiograms[1]
        let step = try #require(v.steps.first { $0.id == rg.id })
        #expect(Task5Validator.validate(rg.wireText, for: step, variant: v).isCorrect)
        #expect(!Task5Validator.validate(rg.wireText.replacingOccurrences(of: " ", with: ""), for: step, variant: v).isCorrect)
        let wrongHeader = "999 " + Task5Validator.tokens(rg.wireText).dropFirst().joined(separator: " ")
        #expect(!Task5Validator.validate(wrongHeader, for: step, variant: v).isCorrect)
        #expect(!Task5Validator.validate(rg.wireText.replacingOccurrences(of: " = ", with: " "), for: step, variant: v).isCorrect)
        let category = try #require(v.tdr.decode(rg.urgencyCode)?.expressionId)
        let alternative = try #require(v.tdr.codes(forExpressionID: category).first { $0 != rg.urgencyCode })
        #expect(Task5Validator.validate(rg.wireText.replacingOccurrences(of: rg.urgencyCode, with: alternative), for: step, variant: v).isCorrect)
        var parts = Task5Validator.tokens(rg.wireText)
        parts[parts.count - 3] = String(parts[parts.count - 3].dropLast())
        #expect(!Task5Validator.validate(parts.joined(separator: " "), for: step, variant: v).isCorrect)
    }

    @Test func leadingZerosAndReceiptNumbersCannotBeNormalizedAway() throws {
        var found = false
        for seed in UInt64(0)..<50 {
            let v = try variant(seed: seed)
            guard let rg = v.radiograms.first(where: { $0.direction == .receive && $0.number.hasPrefix("0") }) else { continue }
            found = true
            let step = try #require(v.steps.first { $0.id == rg.id + "-receipt" })
            #expect(Task5Validator.validate(rg.receipt, for: step, variant: v).isCorrect)
            let collapsed = rg.receipt.replacingOccurrences(of: rg.number, with: String(Int(rg.number)!))
            #expect(!Task5Validator.validate(collapsed, for: step, variant: v).isCorrect)
            #expect(!Task5Validator.validate("\(v.ownCallsign) Р 999 К", for: step, variant: v).isCorrect)
            break
        }
        #expect(found)
    }

    @Test func mayorOrderAndSignalRepetitionsRemainExplicit() throws {
        let v = try variant()
        let ids = v.steps.map(\.id)
        #expect(try #require(ids.firstIndex(of: "quality")) < #require(ids.firstIndex(of: "auth-peer")))
        #expect(v.steps.filter { $0.kind == .pause && $0.id.hasPrefix("signal-") }.map(\.requiredPauseSeconds) == [10, 10])
        let signal = v.signals[0]
        let first = try #require(v.steps.first { $0.id == signal.id + "-first" })
        #expect(Task5Validator.validate(signal.firstPart, for: first, variant: v).isCorrect)
        #expect(!Task5Validator.validate("ЬЬЬ \(signal.group)", for: first, variant: v).isCorrect)
        let receive = v.signals[1]
        let second = try #require(v.steps.first { $0.id == receive.id + "-second" })
        #expect(Task5Validator.validate(receive.wireText, for: second, variant: v).isCorrect)
        #expect(!Task5Validator.validate(receive.secondPart, for: second, variant: v).isCorrect)
        for gram in v.radiograms where gram.direction == .receive {
            #expect(!v.steps.map(\.title).joined(separator: " ").contains(gram.number))
        }
    }

    @Test func malformedRadiogramsReturnAnErrorWithoutInvalidRanges() throws {
        let v = try variant()
        let rg = v.radiograms[1]
        let step = try #require(v.steps.first { $0.id == rg.id })
        let start = rg.header + " = \(rg.urgencyCode) \(rg.address) ="
        for malformed in ["", "=", "= =", "= = К", rg.header, start, start + " К", start + " = К", start + " \(rg.operatorGroup) К"] {
            #expect(!Task5Validator.validate(malformed, for: step, variant: v).isCorrect)
        }
        let unusualWhitespace = rg.wireText.replacingOccurrences(of: " ", with: "\n\t")
        #expect(Task5Validator.validate(unusualWhitespace, for: step, variant: v).isCorrect)
    }

    @Test func repeatsPreserveCurrentRadiogramAndExcludeRequestedEndpoints() throws {
        let v = try variant()
        let rg = v.radiograms[1]
        #expect(Task5RepeatRequest.parse("РПТ К")?.reply(for: rg) == rg.wireText)
        #expect(Task5RepeatRequest.parse("РПТ НР")?.reply(for: rg) == "НР \(rg.number) К")
        #expect(Task5RepeatRequest.parse("РПТ ГР 2")?.reply(for: rg) == rg.groups[1] + " К")
        #expect(Task5RepeatRequest.parse("РПТ АА 28 К")?.reply(for: rg) == rg.groups[28...].joined(separator: " ") + " К")
        #expect(Task5RepeatRequest.parse("РПТ АБ 3")?.reply(for: rg) == rg.groups[..<2].joined(separator: " ") + " К")
        #expect(Task5RepeatRequest.parse("РПТ БН 1 4")?.reply(for: rg) == rg.groups[1..<3].joined(separator: " ") + " К")
        #expect(Task5RepeatRequest.parse("РПТ БН 4 1")?.reply(for: rg) == nil)
        #expect(Task5RepeatRequest.parse("РПТ АА 999")?.reply(for: rg) == nil)
        #expect(Task5RepeatRequest.parse("РПТ ЛИШНЕЕ К") == nil)
    }

    @Test func originalReferenceKeepsFullCorpusAndUnitVariants() throws {
        #expect(reference.codes.count == 180)
        let slow = try #require(reference.codes.first { $0.code == "ЩРС" })
        #expect(Set(slow.variants.compactMap(\.parameterUnit)) == ["groups/min", "words/min"])
        #expect(reference.codes.contains { $0.code == "ЩРЖ?" })
        #expect(reference.codes.contains { $0.code == "ЩРЖ" })
        #expect(reference.cells.filter { $0.expressionId == "password" }.count == 6)
        #expect(reference.cells.contains { $0.expression == nil })
        #expect(Task5Category.allCases.map(\.thresholdsMinutes) == [[50,55,60], [40,45,50], [35,40,45], [35,40,45]])
    }

    @Test func timeBandsDoNotRoundPastAnyBoundary() {
        for category in Task5Category.allCases {
            let thresholds = category.thresholdsMinutes.map { Double($0 * 60) }
            #expect(category.timeBand(for: thresholds[0] - 0.001) == .excellent)
            #expect(category.timeBand(for: thresholds[0]) == .excellent)
            #expect(category.timeBand(for: thresholds[0] + 0.001) == .good)
            #expect(category.timeBand(for: thresholds[1]) == .good)
            #expect(category.timeBand(for: thresholds[1] + 0.001) == .satisfactory)
            #expect(category.timeBand(for: thresholds[2]) == .satisfactory)
            #expect(category.timeBand(for: thresholds[2] + 0.001) == .overLimit)
            #expect(category.timeBand(for: -.infinity) == nil)
            #expect(category.timeBand(for: .nan) == nil)
        }
    }
}
