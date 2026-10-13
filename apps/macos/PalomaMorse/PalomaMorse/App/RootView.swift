import SwiftUI

/// The released Paloma window: compact header (toolbar) with the three mode
/// tabs in its centre when the window is wide enough (else a row above the
/// content), then the mode content. No sidebar, no inspector.
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var uiScale: CGFloat = 1
    @State private var windowWidth: CGFloat = 1000

    /// Below this width the toolbar has no room for the tabs next to the title
    /// (with its data-source marker) and the tone/volume controls.
    private static let toolbarTabsWidth: CGFloat = 1320
    private var tabsInToolbar: Bool { windowWidth >= Self.toolbarTabsWidth }

    var body: some View {
        VStack(spacing: Spacing.s) {
            if !tabsInToolbar {
                ModeTabs(model: model)
            }

            Group {
                switch model.section {
                case .reception:
                    ReceptionView(session: model.reception, settings: model.settings)
                        .transition(.opacity)
                case .transmission:
                    TransmissionView(session: model.transmission, settings: model.settings)
                        .transition(.opacity)
                case .radio:
                    RadioView(model: model.radio)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Modes cross-fade instead of cutting.
            .animation(.smooth(duration: 0.3), value: model.section)
        }
        .padding(.horizontal, Spacing.windowMargin)
        .padding(.top, tabsInToolbar ? Spacing.s : Spacing.xxs)
        .padding(.bottom, Spacing.windowMargin)
        .frame(minWidth: 900, minHeight: 620)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            uiScale = UIScale.forWindow(size)
            windowWidth = size.width
        }
        .environment(\.uiScale, uiScale)
        // The desktop shows through the window (behind-window material), so the
        // glass controls refract the user's wallpaper instead of a painted backdrop.
        .containerBackground(for: .window) { WindowBackdrop() }
        .navigationTitle("Paloma Morse")
        .navigationSubtitle(model.dataSourceNotice ?? "")
        .toolbar { AppToolbar(model: model, showsTabs: tabsInToolbar) }
        .onAppear { model.startKeyboardInput(); model.radio.windowOpened(); model.audio.startEngine(with: model.settings.audio) }
        .onDisappear { model.stopKeyboardInput(); model.reception.stop(); model.transmission.releaseKey(); model.radio.windowClosed(); model.audio.service.stopEngine() }
        .task {
            // Review fixtures for secondary windows open them directly.
            if model.fixtureName?.hasPrefix("settings.") == true { openSettings() }
            if model.fixtureName?.hasPrefix("history.") == true { openWindow(id: WindowID.history) }
        }
    }
}

/// Dark theme: a behind-window material, so the wallpaper shows through and the
/// glass has something to refract. Light theme: opaque, like Apple's light
/// windows — a calm grey window background under white panels.
private struct WindowBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Color(nsColor: .windowBackgroundColor).opacity(0.35)
                }
            } else {
                // A notch greyer than the white panels, like Apple's light windows.
                Color(red: 0.94, green: 0.94, blue: 0.95)
            }
        }
        .ignoresSafeArea()
    }
}

/// Header of the released client: key indicator, name, tone and volume with
/// their values, history and settings. Glass comes from the system toolbar.
struct AppToolbar: ToolbarContent {
    var model: AppModel
    var showsTabs = false

    var body: some ToolbarContent {
        // The system title shows "Paloma Morse" and, as its subtitle, the one
        // marker of demo / preview / missing engine (no duplicate badges).
        ToolbarItem(placement: .navigation) {
            ParametersToggle(settings: model.settings, isAvailable: model.section != .radio)
        }
        ToolbarItem(placement: .navigation) {
            KeyStatusDot(hardware: model.audio.hardware, isPressed: model.audio.hardwareKeyPressed)
                .padding(.horizontal, Spacing.xxs)
        }
        .sharedBackgroundVisibility(.hidden)

        if showsTabs {
            ToolbarItem(placement: .principal) {
                ModeTabs(model: model, inToolbar: true)
            }
            .sharedBackgroundVisibility(.hidden)
        }

        ToolbarItem(placement: .primaryAction) {
            ToneControl(settings: model.settings)
        }
        ToolbarItem(placement: .primaryAction) {
            VolumeControl(settings: model.settings)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            HistoryButton()
            SettingsLink {
                Label("Настройки", systemImage: "gearshape")
            }
            .help("Настройки (⌘,)")
        }
    }
}

/// Folds the parameter column to its rail (Start/Stop stays on the rail).
private struct ParametersToggle: View {
    @Bindable var settings: SettingsStore
    var isAvailable: Bool

    var body: some View {
        Button(settings.parametersCollapsed ? "Показать параметры" : "Скрыть параметры",
               systemImage: "sidebar.leading") {
            settings.parametersCollapsed.toggle()
        }
        .disabled(!isAvailable)
        .help(settings.parametersCollapsed ? "Показать параметры (⌃⌘S)" : "Скрыть параметры (⌃⌘S)")
    }
}

private struct HistoryButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("История занятий", systemImage: "clock.arrow.circlepath") {
            openWindow(id: WindowID.history)
        }
        .help("История занятий (⌘Y)")
    }
}

/// The one key indicator of the released header: a dot, colour plus tooltip and
/// spoken state. Disconnected is red, as in v0.4.20.
struct KeyStatusDot: View {
    var hardware: HardwareKeyState
    var isPressed: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5) }
            .padding(4)
            .help(text)
            .accessibilityElement()
            .accessibilityLabel("Ключ")
            .accessibilityValue(text)
    }

    private var color: Color {
        if isPressed { return .accentColor }
        switch hardware {
        case .connected: return .green
        case .searching, .reconnecting: return .yellow
        case .permissionDenied: return .orange
        case .disconnected: return .red
        case .unknown: return .gray
        }
    }

    private var text: String {
        switch hardware {
        case .connected(let name): isPressed ? "Ключ нажат · \(name)" : "Ключ подключён · \(name)"
        case .searching: "Поиск USB-ключа…"
        case .reconnecting: "Переподключение ключа…"
        case .permissionDenied(let detail): "Нет доступа к USB-ключу: \(detail)"
        case .disconnected: "USB-ключ не подключён. Передача — клавишей Пробел"
        case .unknown: "Состояние ключа неизвестно"
        }
    }
}

/// Tone on the engine period grid (Hz = 11025 / period), value shown in Hz.
struct ToneControl: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: 64, alignment: .trailing)
            Slider(value: binding, in: range) { Text("Тон") }
                .labelsHidden()
                .frame(width: 86)
                .accessibilityValue(label)
        }
        .padding(.horizontal, Spacing.xs)
        .help("Тон")
    }

    private var label: String {
        settings.audio.toneHz.formatted(.number.precision(.fractionLength(0...1))) + " Гц"
    }

    private var range: ClosedRange<Double> {
        Double(AudioSettings.tonePeriodRange.lowerBound)...Double(AudioSettings.tonePeriodRange.upperBound)
    }

    /// Right means higher pitch, i.e. a shorter engine period.
    private var binding: Binding<Double> {
        let periods = AudioSettings.tonePeriodRange
        return Binding(
            get: { Double(periods.upperBound + periods.lowerBound - settings.audio.tonePeriod) },
            set: { settings.audio.tonePeriod = periods.upperBound + periods.lowerBound - Int($0.rounded()) })
    }
}

struct VolumeControl: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        HStack(spacing: Spacing.xs) {
            HStack(spacing: 4) {
                Image(systemName: settings.audio.volumePercent == 0 ? "speaker.slash" : "speaker.wave.2")
                Text("\(settings.audio.volumePercent) %")
            }
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: 70, alignment: .trailing)
                .accessibilityHidden(true)
            Slider(value: binding, in: 0...100) { Text("Громкость") }
                .labelsHidden()
                .frame(width: 86)
                .accessibilityValue("\(settings.audio.volumePercent) %")
        }
        .padding(.horizontal, Spacing.xs)
        .help("Громкость")
    }

    private var binding: Binding<Double> {
        Binding(
            get: { Double(settings.audio.volumePercent) },
            set: { settings.audio.volumePercent = Int($0.rounded()) })
    }
}
