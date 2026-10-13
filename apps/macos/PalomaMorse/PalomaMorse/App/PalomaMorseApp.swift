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

        Settings {
            if case .ready(let model) = bootstrap {
                SettingsView(model: model)
                    .themed(model.settings, override: bootstrap.launch.colorScheme)
            }
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

    static func load() -> AppBootstrap {
        let catalog: MorseCatalog
        do {
            catalog = try MorseCatalog.load()
        } catch {
            return .failed("morse.v1.json: \(error.localizedDescription)")
        }

        let options = LaunchOptions.current
        #if DEBUG
        if let fixture = options.fixture {
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
        return .ready(AppModel(
            catalog: catalog,
            audioService: audioService,
            networkService: SocketIONetworkService(baseURL: options.relayURL),
            settings: SettingsStore()))
    }
}
