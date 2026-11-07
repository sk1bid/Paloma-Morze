import SwiftUI

struct TrainingCommands: Commands {
    var model: AppModel

    @FocusedValue(\.task5FileActions) private var task5Files

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            if model.section == .task5 {
                Button("Открыть тренировку…") { task5Files?.open() }
                    .keyboardShortcut("o")
                    .disabled(task5Files?.canOpen != true)
                Button("Сохранить результат…") { task5Files?.save() }
                    .keyboardShortcut("s")
                    .disabled(task5Files?.canSave != true)
            }
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { model.select(section) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(model.isSectionLocked(section))
            }
            Divider()
            Button(model.settings.parametersCollapsed ? "Показать параметры" : "Скрыть параметры") {
                model.settings.parametersCollapsed.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(model.section == .radio)
            Divider()
        }

        CommandGroup(after: .windowList) {
            if model.task5.isDeveloperReview {
                Button("Панель разработчика задачи №5") { openWindow(id: WindowID.task5Developer) }
            }
            Button("История занятий") { openWindow(id: WindowID.history) }
                .keyboardShortcut("y", modifiers: .command)
        }

        CommandMenu("Тренировка") {
            Button(model.primaryActionTitle) { model.performPrimaryAction() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canPerformPrimaryAction)

            if model.section == .task5 {
                Button("Остановить тренировку", role: .destructive) { model.task5.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.task5.isSessionActive)
            }

            Button("Повторить знак") { model.reception.repeatCurrent() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.section != .reception || !model.reception.canRepeat)

            Divider()

            Button("Очистить текст передачи") { model.transmission.clear() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model.section != .transmission)
        }
    }
}

struct Task5FileActions {
    var open: () -> Void
    var save: () -> Void
    var canOpen: Bool
    var canSave: Bool
}

private struct Task5FileActionsKey: FocusedValueKey {
    typealias Value = Task5FileActions
}

extension FocusedValues {
    var task5FileActions: Task5FileActions? {
        get { self[Task5FileActionsKey.self] }
        set { self[Task5FileActionsKey.self] = newValue }
    }
}
