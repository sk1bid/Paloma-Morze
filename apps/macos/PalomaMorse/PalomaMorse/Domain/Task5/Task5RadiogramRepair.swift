import Foundation

/// A repeat repairs one part of the received draft, preserving all other parts.
/// Group positions are one-based on the wire, as in Task5RepeatRequest.
struct Task5RadiogramRepair: Codable, Equatable {
    enum Part: Codable, Equatable {
        case header, group(Int), all
        var request: String {
            switch self {
            case .header: "РПТ ПБЛ К"
            case .group(let index): "РПТ ГР \(index + 1) К"
            case .all: "РПТ АЛ К"
            }
        }
    }
    let stepID: String
    let draft: String
    let part: Part

    private struct Sections {
        var header: [String]
        var address: [String]
        var body: [String]
        var trailer: [String]
        var wire: String { (header + ["="] + address + ["="] + body + trailer).joined(separator: " ") }
    }

    private static func sections(_ text: String, radiogram: Task5Radiogram) -> Sections? {
        let words = Task5Validator.tokens(text)
        let separators = words.indices.filter { words[$0] == "=" }
        let suffixCount = radiogram.majorFormat == true ? 1 : 2
        guard separators.count == 2, words.last == "К",
              words.count - suffixCount >= separators[1] + 1 else { return nil }
        return Sections(header: Array(words[..<separators[0]]),
            address: Array(words[(separators[0] + 1)..<separators[1]]),
            body: Array(words[(separators[1] + 1)..<(words.count - suffixCount)]),
            trailer: Array(words.suffix(suffixCount)))
    }

    static func needed(stepID: String, draft: String, radiogram: Task5Radiogram, tdr: Task5TDR) -> Self? {
        let part: Part
        if let sections = sections(draft, radiogram: radiogram), sections.body.count == radiogram.groupCount,
           sections.trailer == (radiogram.majorFormat == true ? ["К"] : [radiogram.operatorGroup, "К"]) {
            var headerCheck = sections
            headerCheck.body = radiogram.groups
            if !Task5Validator.validateRadiogram(Task5Validator.tokens(headerCheck.wire), radiogram: radiogram, tdr: tdr).isCorrect {
                part = .header
            } else if let index = sections.body.indices.first(where: { sections.body[$0] != radiogram.groups[$0] }) {
                part = .group(index)
            } else { return nil }
        } else {
            // Missing/extra groups make positional requests ambiguous. Never
            // splice a shifted body into a supposedly correct group position.
            part = .all
        }
        return Self(stepID: stepID, draft: draft, part: part)
    }

    func merging(_ response: String, radiogram: Task5Radiogram) -> String? {
        if part == .all { return Task5Validator.tokens(response).joined(separator: " ") }
        guard var draft = Self.sections(draft, radiogram: radiogram) else { return nil }
        let words = Task5Validator.tokens(response)
        switch part {
        case .header:
            let separators = words.indices.filter { words[$0] == "=" }
            guard separators.count == 2, words.last == "К", separators[1] == words.count - 2 else { return nil }
            draft.header = Array(words[..<separators[0]])
            draft.address = Array(words[(separators[0] + 1)..<separators[1]])
        case .group(let index):
            guard words.count == 2, words[0].count == 5, words[1] == "К", draft.body.indices.contains(index) else { return nil }
            draft.body[index] = words[0]
        case .all: break
        }
        return draft.wire
    }

    func responseIsCorrect(_ response: String, radiogram: Task5Radiogram, tdr: Task5TDR) -> Bool {
        guard let merged = merging(response, radiogram: radiogram),
              let sections = Self.sections(merged, radiogram: radiogram) else { return false }
        switch part {
        case .group(let index): return sections.body.indices.contains(index) && sections.body[index] == radiogram.groups[index]
        case .header:
            var check = sections; check.body = radiogram.groups
            return Task5Validator.validateRadiogram(Task5Validator.tokens(check.wire), radiogram: radiogram, tdr: tdr).isCorrect
        case .all: return Task5Validator.validateRadiogram(Task5Validator.tokens(merged), radiogram: radiogram, tdr: tdr).isCorrect
        }
    }

    /// Roll back only the current/last lexical group in this section. A section
    /// separator is a boundary: an empty body never deletes an address group.
    static func removingLastGroup(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.last != "=" else { return text }
        let end = trimmed.endIndex
        let start = trimmed.lastIndex(where: { $0.isWhitespace || $0 == "=" }).map { trimmed.index(after: $0) } ?? trimmed.startIndex
        guard start < end else { return text }
        let prefix = String(trimmed[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? "" : prefix + " "
    }
}
