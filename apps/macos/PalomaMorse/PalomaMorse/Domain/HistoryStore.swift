import Foundation
import Observation

struct SessionRecord: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case reception
        case transmission

        var title: String {
            switch self {
            case .reception: "Приём"
            case .transmission: "Передача"
            }
        }

        var systemImage: String {
            switch self {
            case .reception: "ear"
            case .transmission: "hand.tap"
            }
        }
    }

    var id = UUID()
    var date: Date
    var kind: Kind
    var title: String
    var detail: String
    var total: Int
    /// `nil` when the exercise is not graded (learning, paper-based control work).
    var errors: Int?
    var duration: TimeInterval
    var errorSigns: [String] = []

    var accuracy: Double? {
        guard let errors, total > 0 else { return nil }
        return max(0, Double(total - errors) / Double(total))
    }
}

/// Durable native session log, an addition beyond the legacy client.
/// Explicit records or nil defaults keep preview/test histories isolated.
@Observable
final class HistoryStore {
    private(set) var records: [SessionRecord]

    @ObservationIgnored private let defaults: UserDefaults?
    init(records: [SessionRecord]? = nil, defaults: UserDefaults? = .standard) {
        self.defaults = records == nil ? defaults : nil
        self.records = records ?? defaults?.data(forKey: "history.v1").flatMap { try? JSONDecoder().decode([SessionRecord].self, from: $0) } ?? []
    }
    private func save() {
        if let data = try? JSONEncoder().encode(records) { defaults?.set(data, forKey: "history.v1") }
    }

    func add(_ record: SessionRecord) {
        records.insert(record, at: 0)
        save()
    }

    func remove(_ ids: Set<SessionRecord.ID>) {
        records.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }
}
