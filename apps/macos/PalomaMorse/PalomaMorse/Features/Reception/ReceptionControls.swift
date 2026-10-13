import SwiftUI

/// Left column of Reception in the order of the released client:
/// ВЫБРАТЬ БУКВЫ, УРОК, УПРАЖНЕНИЕ, ГРУПП, СКОРОСТЬ ЗНАКА, ТИРЕ / ТОЧКА,
/// ПАУЗА, ЗНАКИ, and Start/Stop at the bottom. Front and waveform are in Settings.
struct ReceptionControls: View {
    @Bindable var session: ReceptionSession
    @Bindable var settings: SettingsStore

    private static let poolOnlyHint = "Доступно в 3 и 4 упражнении"

    var body: some View {
        let locked = session.isConfigurationLocked
        let poolExercise = session.exercise.usesStudiedPool

        ParameterColumn(isCollapsed: settings.parametersCollapsed) {
            OptionToggle(
                title: "Выбрать буквы",
                isOn: $session.customSelection,
                isEnabled: poolExercise && !locked,
                help: poolExercise ? "Свой набор знаков вместо урока" : Self.poolOnlyHint)

            let lesson = availability(applies: !session.customSelection, otherwise: "Доступно в обычном режиме")
            ParameterGroup(title: "Урок", availability: lesson) {
                ValueStepper(
                    "Урок",
                    value: $session.lessonIndex,
                    in: 0...(session.lessons.count - 1),
                    availability: lesson,
                    format: { session.lessons[$0].id.formatted() })
            }

            ParameterGroup(title: "Упражнение", availability: sessionAvailability) {
                ValueStepper(
                    "Упражнение",
                    value: exerciseBinding,
                    in: 1...(session.availableExercises.last?.rawValue ?? 4),
                    availability: sessionAvailability)
            }

            let groups = availability(applies: poolExercise, otherwise: Self.poolOnlyHint)
            ParameterGroup(title: "Групп", availability: groups) {
                ValueStepper(
                    "Групп по 5 знаков",
                    value: $session.groupCount,
                    in: ReceptionSession.groupCountRange,
                    step: 5,
                    availability: groups)
            }

            Divider()
                .padding(.vertical, 2)

            ParameterGroup(title: "Скорость знака", availability: sessionAvailability) {
                ValueStepper(
                    "Скорость знака",
                    value: $settings.audio.speed,
                    in: AudioSettings.speedRange,
                    step: AudioSettings.speedStep,
                    availability: sessionAvailability)
            }

            ParameterGroup(title: "Тире / точка", availability: sessionAvailability) {
                ValueStepper(
                    "Отношение тире к точке",
                    value: $settings.audio.dashRatio,
                    in: AudioSettings.dashRatioRange,
                    step: AudioSettings.halfStep,
                    availability: sessionAvailability,
                    format: { $0.formatted(.number.precision(.fractionLength(1))) })
            }

            ParameterGroup(title: "Пауза", availability: sessionAvailability) {
                ValueStepper(
                    "Пауза",
                    value: $settings.audio.pauseFactor,
                    in: AudioSettings.pauseFactorRange,
                    step: AudioSettings.halfStep,
                    availability: sessionAvailability,
                    format: { "×" + $0.formatted(.number.precision(.fractionLength(1))) })
            }

            OptionToggle(
                title: "Знаки  / = ?",
                isOn: $session.includeSigns,
                isEnabled: poolExercise && !locked,
                help: poolExercise ? "Добавить знаки / = ? к набору" : Self.poolOnlyHint)
                .padding(.top, 2)
        } rail: {
            RailValue(caption: "УРОК", value: session.lessons[session.lessonIndex].id.formatted(), title: "Урок")
                .opacity(session.customSelection ? 0.5 : 1)
            RailValue(caption: "УПР", value: "\(session.exercise.rawValue)", title: "Упражнение")
            if poolExercise {
                RailValue(caption: "ГРУПП", value: "\(session.groupCount)", title: "Групп по 5 знаков")
            }
            RailValue(caption: "СКОР", value: "\(settings.audio.speed)", title: "Скорость знака")
        } footer: {
            StartStopButton(
                isRunning: session.isSessionActive,
                disabledReason: session.startBlockReason,
                action: session.toggleRun)
        }
    }

    /// Speed, ratio, pause, exercise: fixed while a session runs, as released.
    private var sessionAvailability: ParameterAvailability {
        session.isConfigurationLocked ? .lockedForSession : .available
    }

    private func availability(applies: Bool, otherwise reason: String) -> ParameterAvailability {
        applies ? sessionAvailability : .notApplicable(reason)
    }

    private var exerciseBinding: Binding<Int> {
        Binding(
            get: { session.exercise.rawValue },
            set: { session.exercise = ReceptionExercise(rawValue: $0) ?? .learn })
    }
}
