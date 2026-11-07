import Foundation
import Observation

/// Practice modes, switched by the tabs under the toolbar.
/// History is a secondary window (Window › История занятий, ⌘Y), not a mode.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case reception
    case transmission
    case radio
    case task5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reception: "Приём"
        case .transmission: "Передача"
        case .radio: "Эфир"
        case .task5: "Задача №5"
        }
    }

    var systemImage: String {
        switch self {
        case .reception: "headphones"
        case .transmission: "dot.radiowaves.left.and.right"
        case .radio: "globe"
        case .task5: "list.bullet.clipboard"
        }
    }
}

enum WindowID {
    static let main = "main"
    static let history = "history"
    static let task5Developer = "task5-developer-controller"
}

/// Composition root: wires services into feature models. Views receive the
/// feature models they need and never construct services themselves.
@Observable
final class AppModel {
    var section: AppSection = .reception {
        didSet {
            transmission.isEnabled = section == .transmission
            task5.isEnabled = section == .task5
            if section != oldValue {
                reception.stop()
                transmission.releaseKey()
                transmission.stopRadiogram()
            }
        }
    }

    let catalog: MorseCatalog
    let settings: SettingsStore
    let audio: AudioCoordinator
    let history: HistoryStore
    let reception: ReceptionSession
    let transmission: TransmissionSession
    let radio: RadioModel
    let task5: Task5Session

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
        fixtureName: String? = nil,
        developerTask5Review: Bool = false
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
        if fixtureName != nil || developerTask5Review {
            task5 = Task5Session(catalog: catalog, audio: audio, settings: settings, archiveDirectory: nil,
                developerReview: developerTask5Review)
        } else {
            task5 = Task5Session(catalog: catalog, audio: audio, settings: settings)
        }
        task5.isEnabled = false

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
            task5.stop()
            task5.configuration = settings.task5Configuration
            audio.stopAll()
            section = .reception
        }
        settings.onAudioChange = { [weak self] _ in
            guard let self else { return }
            audio.updateSettings(task5.effectiveAudioSettings)
        }
        audio.startEngine(with: settings.audio)
        (networkService as? SocketIONetworkService)?.restoreAuthentication()
    }

    /// The single visible marker of where sound and data come from (toolbar).
    /// Nil only for a live engine with real data.
    var dataSourceNotice: String? {
        if fixtureName != nil && !task5.isDeveloperReview { return "Превью-данные · без звука" }
        switch audio.adapterKind {
        case .live: return audio.unavailableReason
        case .demo: return "Демо · без звука"
        case .unavailable: return "Нет звукового движка"
        }
    }

    /// As in the released client, Reception and Transmission are locked while a
    /// live radio session runs; the session is left from the Эфир tab.
    func isSectionLocked(_ section: AppSection) -> Bool {
        (radio.isLive && section != .radio) || (task5.isSessionActive && section != .task5)
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
        case .task5:
            task5.isSessionActive ? (task5.isPaused ? "Продолжить обмен" : "Пауза") : "Начать задачу №5"
        default: "Старт"
        }
    }

    var canPerformPrimaryAction: Bool {
        switch section {
        case .reception: reception.isSessionActive || reception.startBlockReason == nil
        case .transmission: transmission.mode == .radiogram
        case .task5: task5.isSessionActive || task5.canStart
        default: false
        }
    }

    func performPrimaryAction() {
        switch section {
        case .reception: reception.toggleRun()
        case .transmission where transmission.mode == .radiogram: transmission.toggleRadiogram()
        case .task5: task5.isSessionActive ? task5.togglePause() : task5.startRadioExchange()
        default: break
        }
    }
}
