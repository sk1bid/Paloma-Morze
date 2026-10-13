import Foundation

/// Alphabet used for mnemonics, decoding of keyed input and radiogram letters.
/// Mirrors the RU/EN switch of the released client.
enum Alphabet: String, CaseIterable, Identifiable, Codable {
    case ru = "RU"
    case en = "EN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ru: "Кириллица"
        case .en: "Латиница"
        }
    }
}

struct MorseLesson: Identifiable, Hashable, Decodable {
    let id: Int
    let title: String?
    let chars: [String]
}

/// Read-only view of `shared/catalog/morse.v1.json`.
///
/// The JSON is bundled through a symlink to the shared snapshot; this type never
/// edits character or lesson meaning. Lookup rules follow `ui/src/utils/morseProvider.js`,
/// including the Paloma override that keys zero as a single dash.
struct MorseCatalog: Decodable {
    struct Override: Decodable {
        let pattern: String?
        let mnemonics: [String: String]?
    }

    let schemaVersion: Int
    let sourceRelease: String
    let alphabets: [String: [String: String]]
    let mnemonics: [String: [String: String]]
    let lessons: [MorseLesson]
    let qCodes: [String: String]
    let defaultOverrides: [String: Override]

    static let digitsLessonID = 9
    static let signsLessonID = 10
    static let firstQCodeLessonID = 11

    enum LoadError: Error {
        case missingResource
    }

    static func load(from bundle: Bundle = .main) throws -> MorseCatalog {
        guard let url = bundle.url(forResource: "morse.v1", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try JSONDecoder().decode(MorseCatalog.self, from: Data(contentsOf: url))
    }

    // MARK: Lessons

    func isQCodeLesson(_ lesson: MorseLesson) -> Bool {
        lesson.id >= Self.firstQCodeLessonID
    }

    var signsLesson: MorseLesson? {
        lessons.first { $0.id == Self.signsLessonID }
    }

    // MARK: Patterns

    /// Patterns for one display token. A multi-letter token (Q-code) yields one
    /// pattern per letter; the adapter joins them with `,` as the protocol requires.
    func patterns(for token: String, overrides: [String: MorseOverride] = [:]) -> [String] {
        if let pattern = overrides[token]?.pattern, !pattern.isEmpty { return [pattern] }
        if let pattern = defaultOverrides[token]?.pattern {
            return [pattern]
        }
        if token.count > 1 {
            return token.flatMap { patterns(for: String($0), overrides: overrides) }
        }
        return singlePattern(token).map { [$0] } ?? []
    }

    /// Human readable pattern, letters separated by a space.
    func displayPattern(for token: String) -> String {
        patterns(for: token).joined(separator: " ")
    }

    private func singlePattern(_ character: String) -> String? {
        if let pattern = defaultOverrides[character]?.pattern {
            return pattern
        }
        return alphabets[Alphabet.ru.rawValue]?[character] ?? alphabets[Alphabet.en.rawValue]?[character]
    }

    // MARK: Mnemonics

    /// Mnemonic for a sign, or the meaning of a service abbreviation.
    /// As in the released provider, Q_MAP meanings also take precedence for Р.
    func mnemonic(for token: String, alphabet: Alphabet, serviceContext: Bool = false, overrides: [String: MorseOverride] = [:]) -> String {
        if let text = overrides[token]?.mnemonic, !text.isEmpty { return text }
        if let meaning = qCodes[token] {
            return meaning
        }
        if let text = defaultOverrides[token]?.mnemonics?[alphabet.rawValue] {
            return text
        }
        let patterns = patterns(for: token, overrides: overrides)
        guard patterns.count == 1, let pattern = patterns.first else { return "" }
        return mnemonics[alphabet.rawValue]?[pattern]
            ?? mnemonics[Alphabet.ru.rawValue]?[pattern]
            ?? mnemonics[Alphabet.en.rawValue]?[pattern]
            ?? ""
    }

    // MARK: Decoding keyed input

    /// Decodes one keyed pattern. A single dash is always T/Т in transmission,
    /// even though zero is played as a dash (collision rule of the released client).
    func decode(_ pattern: String, alphabet: Alphabet, overrides: [String: MorseOverride] = [:]) -> String {
        if pattern == "-" {
            return alphabet == .ru ? "Т" : "T"
        }
        if let overridden = overrides.sorted(by: { $0.value.order == $1.value.order ? $0.key < $1.key : $0.value.order < $1.value.order }).last(where: { $0.value.pattern == pattern && !pattern.isEmpty }) { return overridden.key }
        let table = alphabets[alphabet.rawValue] ?? [:]
        return table.first { $0.value == pattern }?.key ?? "?"
    }

    /// Meaning of a 3–4 letter Q-code at the end of decoded text, if any.
    func qCodeMeaning(endingWith text: String) -> String? {
        let compact = text.uppercased().replacingOccurrences(of: " ", with: "")
        for length in 3...4 where compact.count >= length {
            if let meaning = qCodes[String(compact.suffix(length))] {
                return meaning
            }
        }
        return nil
    }

    // MARK: Radiogram pools

    func letters(for alphabet: Alphabet) -> [String] {
        (alphabet == .ru ? "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬЭЮЯ" : "ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    }

    var digits: [String] {
        (0...9).map(String.init)
    }
}
