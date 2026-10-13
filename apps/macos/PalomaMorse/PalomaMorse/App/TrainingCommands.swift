import SwiftUI

struct TrainingCommands: Commands {
    var model: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
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
            Button("История занятий") { openWindow(id: WindowID.history) }
                .keyboardShortcut("y", modifiers: .command)
        }

        CommandMenu("Тренировка") {
            Button(model.primaryActionTitle) { model.performPrimaryAction() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canPerformPrimaryAction)

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
