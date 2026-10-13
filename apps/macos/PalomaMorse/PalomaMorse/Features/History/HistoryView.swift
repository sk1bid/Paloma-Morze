import SwiftUI

struct HistoryView: View {
    var history: HistoryStore

    @State private var selection = Set<SessionRecord.ID>()
    @State private var confirmingClear = false

    var body: some View {
        Group {
            if history.records.isEmpty {
                ContentUnavailableView {
                    Label("Пока нет занятий", systemImage: "clock")
                } description: {
                    Text("Завершённые упражнения приёма и радиограммы появятся здесь. В этой версии история хранится до закрытия приложения.")
                }
            } else {
                Table(history.records, selection: $selection) {
                    TableColumn("Дата") { record in
                        Text(record.date, format: .dateTime.day().month().hour().minute())
                            .monospacedDigit()
                    }
                    .width(min: 110, ideal: 130)
                    TableColumn("Занятие") { record in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.title)
                                Text(record.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: record.kind.systemImage)
                        }
                    }
                    .width(min: 200, ideal: 240)
                    TableColumn("Знаков") { record in
                        Text("\(record.total)").monospacedDigit()
                    }
                    .width(60)
                    TableColumn("Ошибки") { record in
                        if let errors = record.errors {
                            Text("\(errors)")
                                .monospacedDigit()
                                .foregroundStyle(errors == 0 ? SignalPalette.correct : SignalPalette.wrong)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                                .help("Не оценивается автоматически")
                        }
                    }
                    .width(60)
                    TableColumn("Точность") { record in
                        Text(record.accuracy?.formatted(.percent.precision(.fractionLength(0))) ?? "—")
                            .monospacedDigit()
                    }
                    .width(70)
                    TableColumn("Время") { record in
                        Text(Duration.clock(record.duration)).monospacedDigit()
                    }
                    .width(60)
                    TableColumn("Повторить") { record in
                        Text(record.errorSigns.joined(separator: " "))
                            .foregroundStyle(SignalPalette.wrong)
                    }
                }
            }
        }
        .navigationTitle("История занятий")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Очистить историю", systemImage: "trash") { confirmingClear = true }
                    .disabled(history.records.isEmpty)
            }
        }
        .confirmationDialog("Очистить всю историю?", isPresented: $confirmingClear) {
            Button("Очистить", role: .destructive, action: history.clear)
        }
        .onDeleteCommand {
            history.remove(selection)
            selection.removeAll()
        }
    }
}
