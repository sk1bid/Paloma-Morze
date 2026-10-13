import SwiftUI

/// One settings pane, like the released panel: alphabet, theme, signal edge and
/// waveform, transmission key, engine state, reset. Tone and volume are in the
/// window header; speed, dash ratio and pause are in the Reception column.
/// Output is always clean: there is deliberately no Clean/APAK selector.
struct SettingsView: View {
    var model: AppModel

    @State private var confirmingReset = false
    @State private var showsShortcuts: Bool
    @State private var showsDiagnostics: Bool

    init(model: AppModel) {
        self.model = model
        let expanded = model.fixtureName == "settings.diagnostics"
        _showsShortcuts = State(initialValue: expanded)
        _showsDiagnostics = State(initialValue: expanded)
    }

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            // The alphabet does not translate lessons: the catalog lessons, the
            // studied pool and the ЙЦУКЕН keyboard are Cyrillic. It selects the
            // mnemonics, the decoding of keyed signs and the radiogram letters.
            Section {
                Picker("Алфавит", selection: $settings.alphabet) {
                    ForEach(Alphabet.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Напевы и передача")
            } footer: {
                Text("Напевы, расшифровка передачи и радиограммы. Уроки приёма — кириллица.")
                    .foregroundStyle(.secondary)
            }

            Section("Оформление") {
                Picker("Тема", selection: $settings.appearance) {
                    ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Сигнал") {
                LabeledContent("Фронт сигнала") {
                    ValueStepper("Фронт сигнала", value: $settings.audio.front, in: AudioSettings.frontRange)
                        .frame(width: 130)
                }
                Picker("Форма сигнала", selection: $settings.audio.waveform) {
                    ForEach(Waveform.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Передача") {
                LabeledContent("Клавиша передачи", value: model.settings.transmissionKeyLabel)
                DisclosureGroup("Сочетания клавиш", isExpanded: $showsShortcuts) {
                    ForEach(Self.shortcuts, id: \.keys) { shortcut in
                        LabeledContent(shortcut.title) {
                            Text(shortcut.keys).monospaced()
                        }
                    }
                }
            }

            Section("Звуковой движок") {
                // Always visible: demo and preview data never read as a live engine.
                if let notice = model.dataSourceNotice {
                    LabeledContent("Источник") { PreviewModeBadge(text: notice) }
                }
                model.audio.engineIndicator
                model.audio.keyIndicator
                DisclosureGroup("Диагностика", isExpanded: $showsDiagnostics) {
                    LabeledContent("Адаптер", value: adapterTitle)
                    if case .ready(let rate) = model.audio.engineState {
                        LabeledContent("Частота вывода", value: "\(rate) Гц")
                    }
                    if let fixture = model.fixtureName {
                        LabeledContent("Набор превью", value: fixture)
                    }
                }
            }

            Section {
                Button("Сбросить все настройки", role: .destructive) { confirmingReset = true }
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Сбросить все настройки?", isPresented: $confirmingReset) {
            Button("Сбросить", role: .destructive, action: model.settings.resetAll)
        } message: {
            Text("Сигнал, тон, громкость, скорость, алфавит и тема вернутся к значениям по умолчанию.")
        }
    }

    private static let shortcuts: [(title: String, keys: String)] = [
        ("Приём · Передача · Эфир", "⌘1 – ⌘3"),
        ("Старт и стоп", "⌘↩"),
        ("Повторить знак", "⌘R"),
        ("Пауза передачи", "⌥⌘P"),
        ("Очистить передачу", "⌘K"),
        ("История занятий", "⌘Y"),
    ]

    private var adapterTitle: String {
        switch model.audio.adapterKind {
        case .live: "Paloma audio engine (C++)"
        case .demo: "Демо — события без звука"
        case .unavailable: "Не подключён"
        }
    }
}
