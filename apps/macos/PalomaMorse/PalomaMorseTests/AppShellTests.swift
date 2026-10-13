import Foundation
import Testing
@testable import PalomaMorse

/// Window-level rules of the released layout: three modes, tabs locked during a
/// live radio session, and the settings panel's "reset all".
@MainActor
struct AppShellTests {
    let model: AppModel

    init() throws {
        model = AppModel(
            catalog: try loadCatalog(),
            audioService: ScriptedAudioService(),
            networkService: UnavailableNetworkService(),
            settings: SettingsStore(defaults: nil))
    }

    @Test func modesMatchTheReleasedTabs() {
        #expect(AppSection.allCases.map(\.title) == ["Приём", "Передача", "Эфир"])
        #expect(model.section == .reception)
    }

    @Test func liveRadioSessionLocksReceptionAndTransmission() {
        let room = RadioRoom(id: "r", name: "Канал", owner: "A", isPrivate: false, participantCount: 2)
        model.select(.radio)
        model.radio.applyPreview(
            screen: .room(RoomSession(room: room, participants: [], owner: "A", phase: .live)),
            callsign: "A")

        #expect(model.isSectionLocked(.reception))
        #expect(model.isSectionLocked(.transmission))
        #expect(!model.isSectionLocked(.radio))
        model.select(.reception)
        #expect(model.section == .radio)

        model.radio.applyPreview(screen: .lobby(.loaded([room])), callsign: "A")
        model.select(.reception)
        #expect(model.section == .reception)
    }

    @Test func resetAllRestoresSignalAlphabetAndTheme() {
        let settings = model.settings
        settings.audio.speed = 90
        settings.audio.front = 2
        settings.audio.waveform = .square
        settings.alphabet = .en
        settings.appearance = .dark

        settings.resetAll()

        #expect(settings.audio == AudioSettings())
        #expect(settings.alphabet == .ru)
        #expect(settings.appearance == .system)
    }

    @Test func dataSourceIsMarkedOnceForDemoAndFixtures() async throws {
        let demo = AppModel(
            catalog: try loadCatalog(), audioService: DemoAudioService(),
            networkService: UnavailableNetworkService(), settings: SettingsStore(defaults: nil))
        #expect(demo.dataSourceNotice == "Демо · без звука")
        await settle()
        #expect(model.dataSourceNotice == nil)
    }
}

/// The demo engine paces its preview pulses with the released engine formulas
/// (ui/native/morse_audio.hpp): dot = roundEven(66120 / speed) reference samples.
struct DemoTimingTests {
    @Test func elementsFollowTheEngineFormulas() {
        var settings = AudioSettings()
        settings.speed = 50
        settings.dashRatio = 3.0
        settings.pauseFactor = 3.0
        let text = EngineTiming(settings: settings, spacing: .text)
        #expect(text.dot == 1322)                       // 66120 / 50 = 1322.4
        #expect(text.dash == 3966)                      // dot × 3.0
        #expect(abs(EngineTiming.seconds(text.dot) - 0.1199) < 0.0001)
        // text gap: dot + (30·1322·1000/110250 → 359 ms + calibration 111 ms)
        #expect(text.gap(group: false) == 1322 + 5182)
        let learning = EngineTiming(settings: settings, spacing: .lessonOne)
        #expect(learning.gap(group: false) == 1322 + 5512)   // 500 ms
        #expect(learning.gap(group: true) == 1322 + 16538)   // 1500 ms
    }
}

/// Locked parameters: a session lock keeps the value applicable (readable),
/// an inapplicable parameter explains itself; neither can be changed.
struct ParameterAvailabilityTests {
    @Test func sessionLockIsDistinctFromNotApplicable() {
        #expect(ParameterAvailability.available.canChange)
        #expect(!ParameterAvailability.lockedForSession.canChange)
        #expect(ParameterAvailability.lockedForSession.isApplicable)
        #expect(ParameterAvailability.lockedForSession.reason == ParameterAvailability.sessionLockReason)
        let groups = ParameterAvailability.notApplicable("Доступно в 3 и 4 упражнении")
        #expect(!groups.canChange)
        #expect(!groups.isApplicable)
        #expect(groups.reason == "Доступно в 3 и 4 упражнении")
    }
}

/// What the "Напевы и передача" alphabet setting actually switches, as stated
/// in its footer: mnemonics, decoding and radiogram letters, not the lessons.
struct AlphabetScopeTests {
    let catalog: MorseCatalog

    init() throws {
        catalog = try loadCatalog()
    }

    @Test func latinSwitchesMnemonicsWithCyrillicFallback() {
        #expect(catalog.mnemonic(for: "8", alphabet: .en) == "EIGHT-TEN-is-not-E-NOUGH")
        // No Latin mnemonic for Ш: the Russian one is shown.
        #expect(catalog.mnemonic(for: "Ш", alphabet: .en) == catalog.mnemonic(for: "Ш", alphabet: .ru))
        #expect(!catalog.mnemonic(for: "Ш", alphabet: .en).isEmpty)
        // Q-codes keep their Russian meaning.
        #expect(catalog.mnemonic(for: "ЩТР", alphabet: .en) == "Точное время (ч, м)")
    }

    @Test func latinSwitchesDecodingAndRadiogramLetters() {
        #expect(catalog.decode(".-..", alphabet: .en) == "L")
        #expect(catalog.letters(for: .en).allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) })
        #expect(catalog.letters(for: .ru).contains("Ж"))
    }

    @MainActor
    @Test func receptionLessonsStayCyrillic() throws {
        let settings = SettingsStore(defaults: nil)
        settings.alphabet = .en
        let model = AppModel(
            catalog: catalog, audioService: ScriptedAudioService(),
            networkService: UnavailableNetworkService(), settings: settings)
        model.reception.lessonIndex = 2
        #expect(model.reception.lessonSigns == catalog.lessons[2].chars)
        #expect(model.reception.lessonSigns.contains("Р"))
    }
}
