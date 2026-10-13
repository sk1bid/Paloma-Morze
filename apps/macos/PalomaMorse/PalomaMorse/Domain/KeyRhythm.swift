import Foundation
import Observation

enum KeyMarkKind: Equatable {
    case dot
    case dash
    case tooLong
}

struct KeyMark: Identifiable, Equatable {
    let id: Int
    let start: Date
    var end: Date?
    /// `nil` while the key is still held.
    var kind: KeyMarkKind?
}

/// Keying thresholds of the released client: fixed 15 WPM, dash from two units,
/// "too long" judged against the operator's own last dot. These classify input
/// timing for display and decoding; they never schedule audio.
enum KeyTiming {
    static let wpm = 15.0
    static let unit: TimeInterval = 1.2 / wpm
    static let dashThreshold = unit * 2
    static let characterGap = unit * 2.5
    static let wordGap = unit * 8
    static let tooLongFactor = 4.5

    static func classify(duration: TimeInterval, lastDot: inout TimeInterval) -> KeyMarkKind {
        if duration >= dashThreshold {
            return duration > lastDot * tooLongFactor ? .tooLong : .dash
        }
        lastDot = duration
        return .dot
    }
}

/// Press/release history for one key (local operator or a correspondent),
/// feeding the rhythm ribbon.
@Observable
final class KeyRhythm {
    private(set) var marks: [KeyMark] = []
    private(set) var isDown = false
    private(set) var lastRelease: Date?

    @ObservationIgnored private var lastDot = KeyTiming.unit
    @ObservationIgnored private var nextID = 0

    /// How far back the tape can show (a 2× wide window shows ≈ 45 s at
    /// 100 pt/s); older marks are dropped.
    static let retention: TimeInterval = 60

    func press(at date: Date = .now) {
        guard !isDown else { return }
        isDown = true
        marks.removeAll { ($0.end ?? date) < date.addingTimeInterval(-Self.retention) }
        marks.append(KeyMark(id: nextID, start: date))
        nextID += 1
    }

    @discardableResult
    func release(at date: Date = .now) -> KeyMarkKind? {
        guard isDown, let index = marks.indices.last else { return nil }
        isDown = false
        lastRelease = date
        let kind = KeyTiming.classify(duration: date.timeIntervalSince(marks[index].start), lastDot: &lastDot)
        marks[index].end = date
        marks[index].kind = kind
        return kind
    }

    func clear() {
        marks.removeAll()
        isDown = false
        lastRelease = nil
    }

    #if DEBUG
    func applyPreview(marks: [KeyMark], isDown: Bool) {
        self.marks = marks
        self.isDown = isDown
        nextID = (marks.map(\.id).max() ?? 0) + 1
    }
    #endif
}
