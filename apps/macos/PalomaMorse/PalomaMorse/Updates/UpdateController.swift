import Combine
import Foundation
import Sparkle

/// Sparkle is enabled only in an explicitly configured native distribution.
/// Tests/previews and local builds without a signing key never contact the feed.
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheck = false
    private var controller: SPUStandardUpdaterController?
    private var observer: AnyCancellable?

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:],
         enabled: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
             && LaunchOptions.current.fixture == nil) {
        guard enabled, UpdateConfiguration.isValid(info) else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observer = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }
        controller.startUpdater()
    }

    func check() { controller?.checkForUpdates(nil) }
}

nonisolated enum UpdateConfiguration {
    static func isValid(_ info: [String: Any]) -> Bool {
        guard let text = info["SUFeedURL"] as? String, let url = URL(string: text),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32 else { return false }
        return true
    }
}
