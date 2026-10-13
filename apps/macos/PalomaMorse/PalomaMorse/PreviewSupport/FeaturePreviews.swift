#if DEBUG
import SwiftUI

// PREVIEW ONLY. Canvas previews for each feature state, built from PreviewFixtures.

private struct FixturePreview: View {
    var name: String
    @State private var model: AppModel

    init(_ name: String) {
        self.name = name
        _model = State(initialValue: PreviewFixtures.appModel(for: name))
    }

    var body: some View {
        RootView(model: model)
            .frame(width: 1000, height: 700)
    }
}

#Preview("Приём · начало") { FixturePreview("reception.start") }
#Preview("Приём · ожидание ответа") { FixturePreview("reception.waiting") }
#Preview("Приём · ошибка") { FixturePreview("reception.wrong") }
#Preview("Приём · группы") { FixturePreview("reception.groups") }
#Preview("Приём · полный набор") { FixturePreview("reception.full") }
#Preview("Приём · свой набор") { FixturePreview("reception.custom") }
#Preview("Приём · контрольная") { FixturePreview("reception.exam") }
#Preview("Приём · Щ-коды") { FixturePreview("reception.qcode") }
#Preview("Приём · движок недоступен") { FixturePreview("reception.unavailable") }
#Preview("Передача · свободная") { FixturePreview("transmission.free") }
#Preview("Передача · радиограмма") { FixturePreview("transmission.radiogram") }
#Preview("Эфир · вход") { FixturePreview("radio.signed-out") }
#Preview("Эфир · каналы") { FixturePreview("radio.lobby") }
#Preview("Эфир · ожидание") { FixturePreview("radio.room-waiting") }
#Preview("Эфир · наложение") { FixturePreview("radio.collision") }

#Preview("Результаты приёма") {
    ReceptionResultsView(
        results: ReceptionResults(exercise: .recognize, lessonID: 3, total: 15, errors: ["О", "Р"], wrongAnswers: 3,
                                  radiogramGroups: [], duration: 94),
        catalog: PreviewFixtures.catalog, alphabet: .ru, onRepeat: {}, onClose: {})
}

#Preview("Текст контрольной") {
    ReceptionResultsView(
        results: ReceptionResults(exercise: .exam, lessonID: 8, total: 50, errors: [], wrongAnswers: 0,
                                  radiogramGroups: ["ЛЖАСЩ", "ТЦДОР", "ИГЬФН", "ЙУХКБ", "ПМЫЗВ", "ЮЯЭЧШ"], duration: 412),
        catalog: PreviewFixtures.catalog, alphabet: .ru, onRepeat: {}, onClose: {})
}

#Preview("История") {
    HistoryView(history: HistoryStore(records: PreviewFixtures.sampleHistory))
        .frame(width: 760, height: 420)
}

#Preview("Настройки") {
    SettingsView(model: PreviewFixtures.appModel(for: "settings.panel"))
}
#endif
