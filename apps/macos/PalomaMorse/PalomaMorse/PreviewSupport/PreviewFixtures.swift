#if DEBUG
import Foundation

/// PREVIEW ONLY. Deterministic states for SwiftUI previews and review
/// screenshots (`-PalomaFixture <name>`). Callsigns and rooms are visibly
/// fictional, nothing contacts the relay, and the window is labelled as preview.
enum PreviewFixtures {
    static let names = [
        "reception.start", "reception.idle", "reception.learn", "reception.waiting", "reception.wrong",
        "reception.repeat", "reception.groups", "reception.full", "reception.custom", "reception.exam",
        "reception.results", "reception.exam-results", "reception.digits", "reception.qcode",
        "reception.unavailable", "reception.failed", "reception.latin", "reception.qcode-repeat", "reception.rail",
        "transmission.free", "transmission.long", "transmission.rail", "transmission.radiogram", "transmission.report",
        "radio.signed-out", "radio.lobby", "radio.lobby-empty", "radio.room-waiting", "radio.room-ready",
        "radio.live", "radio.collision", "radio.lost",
        "history.empty", "history.filled",
        "settings.panel", "settings.diagnostics",
    ]

    static var catalog: MorseCatalog {
        (try? MorseCatalog.load()) ?? MorseCatalog.empty
    }

    static func appModel(for name: String, catalog: MorseCatalog = catalog) -> AppModel {
        let audio: any AudioService = name == "reception.unavailable" ? UnavailableAudioService() : DemoAudioService()
        let model = AppModel(
            catalog: catalog,
            audioService: audio,
            networkService: PreviewNetworkService(),
            settings: SettingsStore(defaults: nil),
            history: HistoryStore(records: name == "history.filled" ? sampleHistory : []),
            fixtureName: name)
        apply(name, to: model)
        return model
    }

    // MARK: States

    private static func apply(_ name: String, to model: AppModel) {
        let reception = model.reception
        let transmission = model.transmission
        let radio = model.radio
        let section = name.split(separator: ".").first.map(String.init) ?? "reception"
        model.section = AppSection(rawValue: section) ?? .reception

        switch name {
        case "reception.start":
            break

        case "reception.idle":
            reception.lessonIndex = 2
            reception.hoveredSign = "Р"

        case "reception.learn":
            reception.lessonIndex = 2
            reception.exercise = .learn
            let sequence = ["Д", "О", "Р", "И"].flatMap { Array(repeating: $0, count: 5) + [" "] }
            reception.applyPreview(.init(status: .playing, sequence: sequence, playedTokens: 14, activeSign: "Р", pulse: .dash))

        case "reception.waiting":
            reception.lessonIndex = 2
            reception.exercise = .recognize
            reception.applyPreview(.init(
                status: .waitingForAnswer,
                sequence: ["Д", "О", "Р", "И", "Д", "Р", "О", "И", "Р", "Д", "О", "И", "Д", "Р", "О"],
                step: 6))

        case "reception.wrong":
            reception.lessonIndex = 2
            reception.exercise = .recognize
            reception.applyPreview(.init(
                status: .feedback(correct: false),
                sequence: ["Д", "О", "Р", "И", "Д", "Р", "О", "И", "Р", "Д", "О", "И", "Д", "Р", "О"],
                step: 6, chosenSign: "Д", errors: ["О"]))

        case "reception.repeat":
            reception.lessonIndex = 2
            reception.exercise = .recognize
            reception.applyPreview(.init(
                status: .repeatingError,
                sequence: ["Д", "О", "Р", "И", "Д", "Р", "О", "И", "Р", "Д", "О", "И", "Д", "Р", "О"],
                step: 6, activeSign: "Р", pulse: .dash, errors: ["Р"]))

        case "reception.full":
            reception.lessonIndex = 7
            reception.exercise = .groups
            reception.groupCount = 10

        case "reception.digits":
            reception.lessonIndex = 8
            reception.exercise = .learn

        case "reception.groups":
            reception.lessonIndex = 4
            reception.exercise = .groups
            reception.groupCount = 10
            reception.applyPreview(.init(
                status: .waitingForAnswer,
                sequence: Array(repeating: ["Е", "Л", "Ж", "А", "С"], count: 10).flatMap { $0 },
                step: 23, errors: ["Ж", "Ф"]))

        case "reception.custom":
            reception.lessonIndex = 6
            reception.exercise = .groups
            reception.customSelection = true
            reception.customPool = ["Ж", "Щ", "Ф", "Ю", "Э", "Х"]

        case "reception.exam":
            reception.lessonIndex = 5
            reception.exercise = .exam
            reception.applyPreview(.init(
                status: .playing,
                sequence: ["Е", "Л", "Ж", "А", "С", " ", "Щ", "Т", "Ц", "Д", "О"],
                playedTokens: 8))

        case "reception.results":
            reception.lessonIndex = 2
            reception.exercise = .recognize
            reception.applyPreview(.init(status: .completed, errors: ["О", "Р"]))
            reception.results = ReceptionResults(
                exercise: .recognize, lessonID: 3, total: 15, errors: ["О", "Р"], wrongAnswers: 3,
                radiogramGroups: [], duration: 94)

        case "reception.exam-results":
            reception.lessonIndex = 7
            reception.exercise = .exam
            reception.applyPreview(.init(status: .completed))
            reception.results = ReceptionResults(
                exercise: .exam, lessonID: 8, total: 50, errors: [], wrongAnswers: 0,
                radiogramGroups: ["ЛЖАСЩ", "ТЦДОР", "ИГЬФН", "ЙУХКБ", "ПМЫЗВ", "ЮЯЭЧШ", "АЖЛЕС", "ЦТЩОД", "РИФНГ", "ЬКХУЙ"],
                duration: 412)

        case "reception.qcode":
            reception.lessonIndex = reception.lessons.count - 1
            reception.exercise = .recognize
            reception.hoveredSign = "ЩТР"

        case "reception.unavailable":
            reception.lessonIndex = 0

        case "reception.failed":
            reception.lessonIndex = 2
            reception.exercise = .recognize
            reception.applyPreview(.init(
                status: .failed("Звуковой движок остановил воспроизведение: устройство вывода отключено. "
                    + "Подключите наушники или выберите другой выход в системных настройках звука и нажмите «Старт»."),
                sequence: ["Д", "О", "Р", "И", "Д", "Р", "О", "И", "Р", "Д", "О", "И", "Д", "Р", "О"],
                step: 6))

        case "reception.latin":
            // Latin mnemonics on the Cyrillic lesson, with the progress counter shown.
            model.settings.alphabet = .en
            reception.lessonIndex = 8
            reception.exercise = .recognize
            let digits = reception.lessons[8].chars
            reception.applyPreview(.init(
                status: .waitingForAnswer,
                sequence: digits + digits.reversed(),
                step: 12))
            reception.hoveredSign = "8"

        case "reception.rail":
            model.settings.parametersCollapsed = true
            reception.lessonIndex = 4
            reception.exercise = .groups
            reception.groupCount = 10
            reception.applyPreview(.init(
                status: .waitingForAnswer,
                sequence: Array(repeating: ["Е", "Л", "Ж", "А", "С"], count: 10).flatMap { $0 },
                step: 23, errors: ["Ж"]))

        case "reception.qcode-repeat":
            let lesson = reception.lessons.count - 1
            reception.lessonIndex = lesson
            reception.exercise = .recognize
            reception.applyPreview(.init(
                status: .repeatingError,
                sequence: reception.lessons[lesson].chars,
                step: 11, activeSign: "ЩТЦ", pulse: .dash, errors: ["ЩТЦ"]))

        case "transmission.free":
            transmission.applyPreview(text: "ЩРК 5 ОК ", buffer: ".-.", hint: "ре-ША-ет", source: .keyboard)
            transmission.rhythm.applyPreview(marks: sampleMarks, isDown: false)

        case "transmission.long":
            // Overflow check: many lines of keyed text, newest line kept in view.
            let words = ["ЩРК", "5", "ОК", "ЩСА", "4", "ЩТР", "1230", "ПРИЕМ", "ВАС", "СЛЫШУ", "ХОРОШО", "ЩРМ"]
            transmission.applyPreview(text: Array(repeating: words, count: 4).flatMap { $0 }.joined(separator: " ") + " ",
                                      buffer: "--.-", hint: "ГА-ГА-НЕ-ПУ", source: .keyboard)
            transmission.rhythm.applyPreview(marks: sampleMarks, isDown: false)

        case "transmission.rail":
            model.settings.parametersCollapsed = true
            transmission.mode = .radiogram
            transmission.groupCount = 5
            var railRun = RadiogramRun(
                sequence: Array("ОУМХЬТЫЖЗЦЭЕЩНСФГШЯРЮПЙЛИ").map(String.init),
                startedAt: .now.addingTimeInterval(-10))
            railRun.targetIndex = 2
            railRun.errors = 1
            railRun.marks = [0: true, 1: true]
            transmission.applyPreview(radiogram: railRun)
            transmission.rhythm.applyPreview(marks: sampleMarks, isDown: false)

        case "transmission.radiogram":
            transmission.mode = .radiogram
            transmission.groupCount = 10
            var run = RadiogramRun(
                sequence: Array("КЛМНОПРСТУФХЦЧШЩЫЬЭЮЯАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬ").map(String.init),
                startedAt: .now.addingTimeInterval(-74))
            run.targetIndex = 12
            run.errors = 2
            run.marks = Dictionary(uniqueKeysWithValues: (0..<12).map { ($0, $0 != 7) })
            transmission.applyPreview(radiogram: run)
            transmission.rhythm.applyPreview(marks: sampleMarks, isDown: true)

        case "transmission.report":
            transmission.mode = .radiogram
            transmission.report = RadiogramReport(total: 50, errors: 3, elapsed: 268)

        case "radio.signed-out":
            radio.applyPreview(screen: .signedOut(.idle), callsign: nil)

        case "radio.lobby":
            radio.applyPreview(screen: .lobby(.loaded(sampleRooms)), callsign: "ДЕМО-1", online: 7, latency: 42)

        case "radio.lobby-empty":
            radio.applyPreview(screen: .lobby(.loaded([])), callsign: "ДЕМО-1", online: 1, latency: 38)

        case "radio.room-waiting":
            radio.applyPreview(screen: .room(RoomSession(
                room: sampleRooms[0], participants: [RadioParticipant(callsign: "ДЕМО-1")],
                owner: "ДЕМО-1", phase: .waitingForCorrespondent)), callsign: "ДЕМО-1")

        case "radio.room-ready":
            radio.applyPreview(screen: .room(RoomSession(
                room: sampleRooms[0], participants: [RadioParticipant(callsign: "ДЕМО-1"), RadioParticipant(callsign: "ДЕМО-2")],
                owner: "ДЕМО-1", phase: .readyToLaunch)), callsign: "ДЕМО-1")

        case "radio.live", "radio.collision":
            radio.applyPreview(
                screen: .room(RoomSession(
                    room: sampleRooms[0],
                    participants: [RadioParticipant(callsign: "ДЕМО-1"), RadioParticipant(callsign: "ДЕМО-2")],
                    owner: "ДЕМО-1", phase: .live)),
                callsign: "ДЕМО-1",
                remoteKeyDown: true)
            radio.localRhythm.applyPreview(marks: sampleMarks, isDown: name == "radio.collision")
            radio.remoteRhythm.applyPreview(marks: shifted(sampleMarks, by: -1.4), isDown: true)

        case "radio.lost":
            radio.applyPreview(
                screen: .connectionLost(ConnectionLoss(reason: "Сервер не отвечает", attempt: 2, roomName: "Учебный канал")),
                callsign: "ДЕМО-1")

        default:
            break
        }
    }

    // MARK: Sample data

    static let sampleRooms = [
        RadioRoom(id: "preview-1", name: "Учебный канал", owner: "ДЕМО-1", isPrivate: false, participantCount: 1),
        RadioRoom(id: "preview-2", name: "Тренировка группы", owner: "ДЕМО-3", isPrivate: true, participantCount: 1),
        RadioRoom(id: "preview-3", name: "Вечерний сеанс", owner: "ДЕМО-4", isPrivate: false, participantCount: 2),
    ]

    static var sampleMarks: [KeyMark] {
        let now = Date.now
        let pattern: [(TimeInterval, TimeInterval, KeyMarkKind)] = [
            (6.2, 6.12, .dash), (5.98, 5.9, .dot), (5.76, 5.52, .dash), (5.0, 4.92, .dot),
            (4.78, 4.54, .dash), (4.4, 4.32, .dot), (3.7, 3.46, .dash), (3.32, 3.24, .dot),
            (2.8, 2.0, .tooLong), (1.6, 1.52, .dot), (1.38, 1.14, .dash), (1.0, 0.92, .dot),
        ]
        return pattern.enumerated().map { index, item in
            KeyMark(id: index, start: now.addingTimeInterval(-item.0), end: now.addingTimeInterval(-item.1), kind: item.2)
        }
    }

    private static func shifted(_ marks: [KeyMark], by seconds: TimeInterval) -> [KeyMark] {
        marks.map {
            KeyMark(id: $0.id, start: $0.start.addingTimeInterval(seconds), end: $0.end?.addingTimeInterval(seconds), kind: $0.kind)
        }
    }

    static var sampleHistory: [SessionRecord] {
        let now = Date.now
        return [
            SessionRecord(date: now.addingTimeInterval(-600), kind: .reception, title: "Урок 3 · Узнавание",
                          detail: "Д О Р И", total: 15, errors: 2, duration: 94, errorSigns: ["О", "Р"]),
            SessionRecord(date: now.addingTimeInterval(-1800), kind: .transmission, title: "Радиограмма · буквы",
                          detail: "10 групп", total: 50, errors: 3, duration: 268),
            SessionRecord(date: now.addingTimeInterval(-3600), kind: .reception, title: "Урок 8 · Контрольная",
                          detail: "10 групп, проверка по бумаге", total: 50, errors: nil, duration: 412),
            SessionRecord(date: now.addingTimeInterval(-86_400), kind: .reception, title: "Урок 2 · Знакомство",
                          detail: "С Щ Т Ц", total: 20, errors: nil, duration: 61),
        ]
    }
}

/// PREVIEW ONLY. Accepts calls and does nothing; it never opens a socket.
final class PreviewNetworkService: NetworkService {
    let kind = NetworkAdapterKind.preview
    let events: AsyncStream<NetworkEvent>

    init() {
        events = AsyncStream { _ in }
    }

    func signIn(callsign: String, password: String, register: Bool) {}
    func signOut() {}
    func refreshRooms() {}
    func createRoom(name: String, password: String?) {}
    func join(roomID: String, password: String?) {}
    func leave() {}
    func launchSession() {}
    func sendKey(pressed: Bool) {}
    func reconnect() {}
}

extension MorseCatalog {
    /// Only for a preview canvas that cannot load the bundle resource.
    static let empty = MorseCatalog(
        schemaVersion: 1, sourceRelease: "", alphabets: [:], mnemonics: [:],
        lessons: [MorseLesson(id: 1, title: nil, chars: [])], qCodes: [:], defaultOverrides: [:])
}
#endif
