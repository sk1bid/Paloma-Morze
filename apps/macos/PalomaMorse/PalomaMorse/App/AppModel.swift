import Foundation
import Observation

/// The three modes of the released client, switched by the tabs under the toolbar.
/// History is a secondary window (Window › История занятий, ⌘Y), not a mode.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case reception
    case transmission
    case radio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reception: "Приём"
        case .transmission: "Передача"
        case .radio: "Эфир"
        }
    }

    var systemImage: String {
        switch self {
        case .reception: "headphones"
        case .transmission: "dot.radiowaves.left.and.right"
        case .radio: "globe"
        }
    }
}

enum WindowID {
    static let main = "main"
    static let history = "history"
}

/// Composition root: wires services into feature models. Views receive the
/// feature models they need and never construct services themselves.
@Observable
final class AppModel {
    var section: AppSection = .reception {
        didSet { transmission.isEnabled = section == .transmission }
    }

    let catalog: MorseCatalog
    let settings: SettingsStore
    let audio: AudioCoordinator
    let history: HistoryStore
    let reception: ReceptionSession
    let transmission: TransmissionSession
    let radio: RadioModel

    /// Non-nil when the window shows fixture data (screenshots, design review).
    let fixtureName: String?
    @ObservationIgnored private var keyboardInput: NativeKeyboardInput?
    func startKeyboardInput() { if keyboardInput == nil { keyboardInput = NativeKeyboardInput(model: self) } }
    func stopKeyboardInput() { keyboardInput?.stop(); keyboardInput = nil }

    init(
        catalog: MorseCatalog,
        audioService: any AudioService,
        networkService: any NetworkService,
        settings: SettingsStore,
        history: HistoryStore = HistoryStore(),
        fixtureName: String? = nil
    ) {
        self.catalog = catalog
        self.settings = settings
        self.history = history
        self.fixtureName = fixtureName
        let audio = AudioCoordinator(service: audioService)
        self.audio = audio
        reception = ReceptionSession(catalog: catalog, audio: audio, settings: settings, history: history)
        transmission = TransmissionSession(catalog: catalog, audio: audio, settings: settings, history: history)
        transmission.isEnabled = false
        radio = RadioModel(network: networkService, audio: audio, settings: settings)

        transmission.onKeyStateChange = { [weak radio] in radio?.transmissionKeyChanged($0) }

        settings.onResetAll = { [weak self] in
            guard let self else { return }
            reception.stop()
            reception.lessonIndex = 0; reception.exercise = .learn; reception.groupCount = 5
            reception.includeSigns = false; reception.customSelection = false; reception.customPool = []
            reception.dismissResults()
            transmission.clear(); transmission.stopRadiogram(); transmission.report = nil
            if transmission.isPaused { transmission.togglePause() }
            transmission.mode = .free; transmission.charset = .letters; transmission.groupCount = 5
            radio.resetSession()
            audio.stopAll()
            section = .reception
        }
        settings.onAudioChange = { [weak audio] in audio?.updateSettings($0) }
        audio.startEngine(with: settings.audio)
        (networkService as? SocketIONetworkService)?.restoreAuthentication()
    }

    /// The single visible marker of where sound and data come from (toolbar).
    /// Nil only for a live engine with real data.
    var dataSourceNotice: String? {
        if fixtureName != nil { return "Превью-данные · без звука" }
        switch audio.adapterKind {
        case .live: return audio.unavailableReason
        case .demo: return "Демо · без звука"
        case .unavailable: return "Нет звукового движка"
        }
    }

    /// As in the released client, Reception and Transmission are locked while a
    /// live radio session runs; the session is left from the Эфир tab.
    func isSectionLocked(_ section: AppSection) -> Bool {
        radio.isLive && section != .radio
    }

    func select(_ section: AppSection) {
        guard !isSectionLocked(section) else { return }
        self.section = section
    }

    // MARK: Menu commands

    var primaryActionTitle: String {
        switch section {
        case .reception: reception.isSessionActive ? "Остановить упражнение" : "Начать упражнение"
        case .transmission where transmission.mode == .radiogram:
            transmission.isRadiogramRunning ? "Остановить радиограмму" : "Начать радиограмму"
        default: "Старт"
        }
    }

    var canPerformPrimaryAction: Bool {
        switch section {
        case .reception: reception.isSessionActive || reception.startBlockReason == nil
        case .transmission: transmission.mode == .radiogram
        default: false
        }
    }

    func performPrimaryAction() {
        switch section {
        case .reception: reception.toggleRun()
        case .transmission where transmission.mode == .radiogram: transmission.toggleRadiogram()
        default: break
        }
    }
}
