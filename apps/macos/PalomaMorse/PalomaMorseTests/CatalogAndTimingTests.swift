import Foundation
import Testing
@testable import PalomaMorse

struct CatalogTests {
    let catalog: MorseCatalog

    init() throws {
        catalog = try loadCatalog()
    }

    @Test func bundledSnapshotIsSchemaOne() {
        #expect(catalog.schemaVersion == 1)
        #expect(catalog.sourceRelease == "v0.4.20")
        #expect(catalog.lessons.map(\.id) == Array(1...11))
    }

    @Test func zeroKeepsPalomaSingleDash() {
        #expect(catalog.patterns(for: "0") == ["-"])
        #expect(catalog.mnemonic(for: "0", alphabet: .ru) == "НОЛЬ")
        #expect(catalog.mnemonic(for: "0", alphabet: .en) == "ZERO")
    }

    @Test func qCodeIsOnePatternPerLetter() {
        #expect(catalog.patterns(for: "ЩТР") == ["--.-", "-", ".-."])
        #expect(catalog.mnemonic(for: "ЩТР", alphabet: .ru) == "Точное время (ч, м)")
    }

    @Test func singleLetterAbbreviationMatchesLegacyProvider() {
        #expect(catalog.mnemonic(for: "Р", alphabet: .ru) == "Квитанция на принятый сигнал")
        #expect(catalog.mnemonic(for: "Р", alphabet: .ru, serviceContext: true) == "Квитанция на принятый сигнал")
    }

    @Test func singleDashDecodesAsT() {
        #expect(catalog.decode("-", alphabet: .ru) == "Т")
        #expect(catalog.decode("-", alphabet: .en) == "T")
        #expect(catalog.decode(".-..", alphabet: .ru) == "Л")
        #expect(catalog.decode("-----", alphabet: .ru) == "0")
        #expect(catalog.decode("........", alphabet: .ru) == "?")
    }

    @Test func qCodeMeaningAtEndOfText() {
        #expect(catalog.qCodeMeaning(endingWith: "ВАС ЩРК") == "Разборчивость сигнала (1-5)")
        #expect(catalog.qCodeMeaning(endingWith: "ПРИВЕТ") == nil)
    }

    @Test func radiogramPools() {
        #expect(catalog.letters(for: .ru).count == 31)
        #expect(catalog.letters(for: .en).count == 26)
        #expect(catalog.digits.count == 10)
    }
}

struct SequenceGeneratorTests {
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test(arguments: [1, 7, 42, 99])
    func noConsecutiveRepeats(seed: UInt64) {
        var rng = Seeded(state: seed)
        let sequence = SequenceGenerator.generate(pool: ["Е", "Л", "Ж", "А"], count: 50, groupGaps: false, using: &rng)
        #expect(sequence.count == 50)
        #expect(zip(sequence, sequence.dropFirst()).allSatisfy { $0 != $1 })
    }

    @Test func examGroupsHaveGaps() {
        var rng = Seeded(state: 3)
        let sequence = SequenceGenerator.generate(pool: ["Д", "О", "Р", "И"], count: 25, groupSize: 5, groupGaps: true, using: &rng)
        #expect(sequence.count == 29)
        #expect(sequence.split(separator: SequenceGenerator.groupGap).map(\.count) == [5, 5, 5, 5, 5])
    }

    @Test func emptyPoolGivesNothing() {
        #expect(SequenceGenerator.generate(pool: [], count: 10, groupGaps: false).isEmpty)
    }
}

struct TimingAndSettingsTests {
    @Test func keyClassification() {
        var lastDot = KeyTiming.unit
        #expect(KeyTiming.classify(duration: 0.06, lastDot: &lastDot) == .dot)
        #expect(lastDot == 0.06)
        #expect(KeyTiming.classify(duration: 0.2, lastDot: &lastDot) == .dash)
        #expect(KeyTiming.classify(duration: 0.4, lastDot: &lastDot) == .tooLong)
    }

    @Test func settingsAreClampedToProtocolRanges() {
        let settings = AudioSettings(
            speed: 153, tonePeriod: 3, volumePercent: 140, dashRatio: 9, pauseFactor: 0.2, front: 20, waveform: .square
        ).normalized()
        #expect(settings.speed == 150)
        #expect(settings.tonePeriod == 8)
        #expect(settings.volumePercent == 100)
        #expect(settings.dashRatio == 4.5)
        #expect(settings.pauseFactor == 1)
        #expect(settings.front == 12)
        #expect(AudioSettings().toneHz.rounded() == 479)
    }
}
