import SwiftUI

/// Launch arguments used for design review and screenshots:
///   -PalomaFixture reception.waiting   (Debug only; see PreviewFixtures)
///   -PalomaAudio demo|unavailable
///   -PalomaAppearance light|dark
///   -PalomaWindowSize 1000x700
struct LaunchOptions {
    enum AudioAdapterChoice: String {
        case live
        case demo
        case unavailable
    }

    var fixture: String?
    var audioAdapter: AudioAdapterChoice
    var colorScheme: ColorScheme?
    var windowSize: CGSize?
    var relayURL: URL

    static let current = LaunchOptions(defaults: .standard)

    init(defaults: UserDefaults) {
        // Explicit configuration; never silently send credentials to another origin.
        let configured = defaults.string(forKey: "PalomaRelayURL") ?? (Bundle.main.object(forInfoDictionaryKey: "PalomaRelayURL") as? String) ?? "http://127.0.0.1:3001"
        let candidate = URL(string: configured)
        relayURL = candidate.flatMap {
            ["http", "https"].contains($0.scheme ?? "") && $0.host != nil && $0.user == nil && $0.password == nil ? $0 : nil
        } ?? URL(string: "http://127.0.0.1:3001")!
        fixture = defaults.string(forKey: "PalomaFixture")
        let fallback = AudioAdapterChoice.live
        audioAdapter = defaults.string(forKey: "PalomaAudio").flatMap(AudioAdapterChoice.init(rawValue:)) ?? fallback
        switch defaults.string(forKey: "PalomaAppearance") {
        case "light": colorScheme = .light
        case "dark": colorScheme = .dark
        default: colorScheme = nil
        }
        if let size = defaults.string(forKey: "PalomaWindowSize")?.split(separator: "x").compactMap({ Double($0) }),
           size.count == 2 {
            windowSize = CGSize(width: size[0], height: size[1])
        }
    }
}
