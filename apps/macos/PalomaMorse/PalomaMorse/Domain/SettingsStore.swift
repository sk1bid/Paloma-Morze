import Foundation
import Observation

/// Persists user settings outside the view hierarchy and forwards audio changes
/// to whoever owns the engine connection.
@Observable
final class SettingsStore {
    private enum Key {
        static let audio = "audio.settings.v1"
        static let alphabet = "training.alphabet"
        static let appearance = "interface.appearance"
        static let parametersCollapsed = "interface.parametersCollapsed"
        static let overrides = "morse.overrides.v1"
        static let key = "transmission.key"
        static let transSpeed = "transmission.speed"
    }

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored var onResetAll: (() -> Void)?
    @ObservationIgnored var onAudioChange: ((AudioSettings) -> Void)?

    var audio: AudioSettings {
        didSet {
            let normalized = audio.normalized()
            if normalized != audio { audio = normalized }
            guard normalized != oldValue else { return }
            save()
            onAudioChange?(audio)
        }
    }

    var customOverrides: [String: MorseOverride] {
        didSet { if let data = try? JSONEncoder().encode(customOverrides) { defaults?.set(data, forKey: Key.overrides) } }
    }
    var transmissionSpeed: Int { didSet { defaults?.set(transmissionSpeed, forKey: Key.transSpeed) } }
    var transmissionKey: String { didSet { defaults?.set(transmissionKey, forKey: Key.key) } }

    var alphabet: Alphabet {
        didSet { defaults?.set(alphabet.rawValue, forKey: Key.alphabet) }
    }

    var appearance: AppearanceSetting {
        didSet { defaults?.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var parametersCollapsed: Bool {
        didSet { defaults?.set(parametersCollapsed, forKey: Key.parametersCollapsed) }
    }

    /// Pass `nil` for previews and tests so nothing is written to disk.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        parametersCollapsed = defaults?.bool(forKey: Key.parametersCollapsed) ?? false
        customOverrides = defaults?.data(forKey: Key.overrides).flatMap { try? JSONDecoder().decode([String: MorseOverride].self, from: $0) } ?? [:]
        transmissionSpeed = defaults?.object(forKey: Key.transSpeed) as? Int ?? 50
        transmissionKey = defaults?.string(forKey: Key.key) ?? "Space"
        if let data = defaults?.data(forKey: Key.audio),
           let stored = try? JSONDecoder().decode(AudioSettings.self, from: data) {
            audio = stored.normalized()
        } else {
            audio = AudioSettings()
        }
        alphabet = defaults?.string(forKey: Key.alphabet).flatMap(Alphabet.init(rawValue:)) ?? .ru
        appearance = defaults?.string(forKey: Key.appearance).flatMap(AppearanceSetting.init(rawValue:)) ?? .system
    }

    func resetAudio() {
        audio = AudioSettings()
    }

    /// "Сбросить все настройки" of the released client: signal, alphabet and theme.
    func resetAll() {
        audio = AudioSettings()
        alphabet = .ru
        appearance = .system
        customOverrides = [:]
        transmissionKey = "Space"
        transmissionSpeed = 50
        parametersCollapsed = false
        onResetAll?()
    }

    func setOverride(for sign: String, pattern: String? = nil, mnemonic: String? = nil) {
        let existing = customOverrides[sign]
        var value = MorseOverride.sanitized(pattern: pattern ?? existing?.pattern, mnemonic: mnemonic ?? existing?.mnemonic)
        value.order = customOverrides[sign]?.order ?? ((customOverrides.values.map(\.order).max() ?? 0) + 1)
        customOverrides[sign] = value
    }
    func resetOverride(for sign: String) { customOverrides[sign] = nil }

    /// Imports a user-provided JSON export; credentials are deliberately excluded.
    func importLegacySettings(_ data: Data) throws {
        var source = String(decoding: data, as: UTF8.self)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFormat
        }
        if let encoded = object["paloma_morse_v1"] as? String {
            source = encoded
            guard let nested = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any] else {
                throw ImportError.invalidFormat
            }
            object = nested
        }
        let knownKeys: Set<String> = ["wpm", "frequency", "volume", "dashRatio", "pauseFactor", "front", "waveform", "lang", "theme", "transWpm", "transmissionKey", "customOverrides"]
        guard !knownKeys.isDisjoint(with: object.keys) else { throw ImportError.invalidFormat }
        for key in ["wpm", "frequency", "volume", "dashRatio", "pauseFactor", "front", "transWpm"] {
            if let value = object[key] {
                guard let number = value as? NSNumber, number.doubleValue.isFinite,
                      CFGetTypeID(number) != CFBooleanGetTypeID() else { throw ImportError.invalidFormat }
            }
        }
        for key in ["waveform", "lang", "theme", "transmissionKey"] {
            if let value = object[key], !(value is String) { throw ImportError.invalidFormat }
        }
        if let value = object["customOverrides"], !(value is [String: [String: String]]) { throw ImportError.invalidFormat }
        func number(_ key: String, _ fallback: Double) -> Double {
            let value = (object[key] as? NSNumber)?.doubleValue ?? fallback
            return value.isFinite ? value : fallback
        }
        var next = AudioSettings()
        let speed = number("wpm", 50)
        next.speed = Int((speed < 20 ? speed * 5 : speed).clamped(to: 30...150).rounded())
        let frequency = number("frequency", next.toneHz)
        if frequency.isFinite, frequency > 0 { next.tonePeriod = Int((11025 / frequency).clamped(to: 8...38).rounded()) }
        next.volumePercent = Int(number("volume", 50).clamped(to: 0...100).rounded())
        next.dashRatio = number("dashRatio", 3)
        next.pauseFactor = number("pauseFactor", 3)
        next.front = Int(number("front", 6).clamped(to: 0...12).rounded())
        next.waveform = (object["waveform"] as? String) == "square" ? .square : .sine
        audio = next.normalized()
        alphabet = (object["lang"] as? String).flatMap(Alphabet.init(rawValue:)) ?? .ru
        appearance = (object["theme"] as? String).flatMap(AppearanceSetting.init(rawValue:)) ?? .system
        transmissionSpeed = Int(number("transWpm", 50).clamped(to: 0...1000).rounded())
        transmissionKey = object["transmissionKey"] as? String ?? "Space"
        customOverrides = [:]
        let rawOverrides = object["customOverrides"] as? [String: [String: String]] ?? [:]
        let regex = try NSRegularExpression(pattern: #""((?:\\.|[^"\\])+)"\s*:\s*\{"#)
        let keys = regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }; let encoded = "\"" + String(source[range]) + "\""
            return try? JSONDecoder().decode(String.self, from: Data(encoded.utf8))
        }.filter { rawOverrides[$0] != nil }
        for sign in keys {
            guard let raw = rawOverrides[sign] else { continue }
            setOverride(for: sign, pattern: raw["pattern"], mnemonic: raw["mnemonic"])
        }
    }

    var transmissionKeyLabel: String { transmissionKey == "Space" ? "Пробел" : transmissionKey }

    func matchesTransmissionKey(_ character: Character) -> Bool {
        if transmissionKey == "Space" { return character == " " }
        if transmissionKey.hasPrefix("Key") { return String(character).uppercased() == String(transmissionKey.dropFirst(3)) }
        if transmissionKey.hasPrefix("Digit") { return String(character) == String(transmissionKey.dropFirst(5)) }
        return false
    }

    enum ImportError: LocalizedError {
        case invalidFormat
        var errorDescription: String? { "Файл не содержит корректные настройки Paloma Morse. Настройки не изменены." }
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(audio) else { return }
        defaults.set(data, forKey: Key.audio)
    }
}

/// Theme choice of the released settings panel (auto / light / dark).
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Как в системе"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
}
