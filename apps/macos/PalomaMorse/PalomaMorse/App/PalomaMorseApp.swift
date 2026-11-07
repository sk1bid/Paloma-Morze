import SwiftUI

@main
struct PalomaMorseApp: App {
    @StateObject private var updates = UpdateController()
    @State private var bootstrap = AppBootstrap.load()

    var body: some Scene {
        Window("Paloma Morse", id: WindowID.main) {
            Group {
                switch bootstrap {
                case .ready(let model):
                    RootView(model: model)
                        .themed(model.settings, override: bootstrap.launch.colorScheme)
                        .modifier(Task5DeveloperWindowLauncher(enabled: model.task5.isDeveloperReview))
                case .failed(let message):
                    ContentUnavailableView(
                        "Не удалось загрузить каталог",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message))
                        .frame(minWidth: 480, minHeight: 320)
                }
            }
        }
        .defaultSize(bootstrap.launch.windowSize ?? CGSize(width: 1180, height: 780))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…", action: updates.check)
                    .disabled(!updates.canCheck)
            }
            if case .ready(let model) = bootstrap {
                TrainingCommands(model: model)
            }
        }

        Window("История занятий", id: WindowID.history) {
            if case .ready(let model) = bootstrap {
                HistoryView(history: model.history)
                    .frame(minWidth: 640, minHeight: 360)
                    .themed(model.settings, override: bootstrap.launch.colorScheme)
            }
        }
        .defaultSize(width: 920, height: 460)
        .commandsRemoved()

        // SceneBuilder cannot conditionally register scenes. This scene is
        // suppressed from launch/restoration and has no ordinary menu command;
        // only the explicit isolated launch can open its guarded content.
        Window("DEV · Управление задачей №5", id: WindowID.task5Developer) {
            if case .ready(let model) = bootstrap, model.task5.isDeveloperReview {
                Task5DeveloperController(session: model.task5)
                    .themed(model.settings, override: bootstrap.launch.colorScheme)
            }
        }
        .defaultSize(width: 800, height: 112)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Window("Подсказка · Задача №5", id: "task5-guide") {
            if case .ready(let model) = bootstrap {
                Task5GuideView(session: model.task5)
                    .themed(model.settings, override: bootstrap.launch.colorScheme)
            }
        }
        .defaultSize(width: 520, height: 640)
        .commandsRemoved()

        Settings {
            if case .ready(let model) = bootstrap {
                SettingsView(model: model)
                    .themed(model.settings, override: bootstrap.launch.colorScheme)
            }
        }
    }
}

private struct Task5DeveloperWindowLauncher: ViewModifier {
    let enabled: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    func body(content: Content) -> some View {
        content.onAppear {
            if enabled { openWindow(id: WindowID.task5Developer) }
        }.onDisappear {
            if enabled { dismissWindow(id: WindowID.task5Developer) }
        }
    }
}

private extension View {
    /// Theme from Settings; `-PalomaAppearance` (screenshots) takes precedence.
    func themed(_ settings: SettingsStore, override: ColorScheme?) -> some View {
        preferredColorScheme(override ?? settings.appearance.colorScheme)
    }
}

extension AppearanceSetting {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Builds the app model from the bundled catalog and the available adapters.
enum AppBootstrap {
    case ready(AppModel)
    case failed(String)

    var launch: LaunchOptions { LaunchOptions.current }

    static func load(options: LaunchOptions = .current) -> AppBootstrap {
        let catalog: MorseCatalog
        do {
            catalog = try MorseCatalog.load()
        } catch {
            return .failed("morse.v1.json: \(error.localizedDescription)")
        }

        #if DEBUG
        if let fixture = options.fixture, !options.developerTask5Review {
            return .ready(PreviewFixtures.appModel(for: fixture, catalog: catalog))
        }
        #endif

        // Live is the ordinary launch; demo/unavailable require an explicit choice.
        let audioService: any AudioService
        switch options.audioAdapter {
        case .live: audioService = ProcessAudioService()
        case .demo: audioService = DemoAudioService()
        case .unavailable: audioService = UnavailableAudioService()
        }
        if options.developerTask5Review {
            let model = AppModel(catalog: catalog, audioService: audioService,
                networkService: UnavailableNetworkService(), settings: SettingsStore(defaults: nil),
                history: HistoryStore(records: []), fixtureName: "task5.developer-review", developerTask5Review: true)
            model.select(.task5)
            model.task5.seedText = "20261102"
            model.task5.generate()
            Task { @MainActor in
                for _ in 0..<100 where !model.audio.isReady { try? await Task.sleep(for: .milliseconds(20)) }
                if model.audio.isReady { model.task5.developerInspectStage(to: 0) }
            }
            return .ready(model)
        }
        let model = AppModel(
            catalog: catalog,
            audioService: audioService,
            networkService: SocketIONetworkService(baseURL: options.relayURL),
            settings: SettingsStore())
        if let section = options.initialSection { model.select(section) }
        return .ready(model)
    }
}
