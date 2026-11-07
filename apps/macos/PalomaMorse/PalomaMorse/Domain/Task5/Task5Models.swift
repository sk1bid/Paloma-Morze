import Foundation

enum Task5Category: String, CaseIterable, Codable, Identifiable {
    case first, second, thirdToFifth, officers
    var id: String { rawValue }
    var title: String {
        switch self { case .first: "1 категория"; case .second: "2 категория"; case .thirdToFifth: "3–5 категории"; case .officers: "Офицеры" }
    }
    var thresholdsMinutes: [Int] {
        switch self { case .first: [50, 55, 60]; case .second: [40, 45, 50]; case .thirdToFifth, .officers: [35, 40, 45] }
    }
    /// Only a time band, not an overall normative grade. Exact boundaries are
    /// inclusive in this educational profile; no rounding of elapsed seconds.
    func timeBand(for elapsed: TimeInterval) -> Task5TimeBand? {
        guard elapsed.isFinite, elapsed >= 0 else { return nil }
        for (index, minutes) in thresholdsMinutes.enumerated() where elapsed <= Double(minutes * 60) {
            return [.excellent, .good, .satisfactory][index]
        }
        return .overLimit
    }
}

enum Task5TimeBand: String, Codable {
    case excellent, good, satisfactory, overLimit
    var title: String {
        switch self { case .excellent: "Отлично по времени"; case .good: "Хорошо по времени"; case .satisfactory: "Удовлетворительно по времени"; case .overLimit: "Время превышено" }
    }
}

enum Task5Length: String, CaseIterable, Codable, Identifiable {
    // Legacy short is retained only for existing archives and test fixtures.
    case short, thirty, full
    static var allCases: [Self] { [.thirty, .full] }
    var id: String { rawValue }
    var title: String { "\(transmittedGroups)" }
    var transmittedGroups: Int { groupsPerRadiogram * 2 }
    var groupsPerRadiogram: Int {
        switch self { case .short: 3; case .thirty: 15; case .full: 30 }
    }
}

enum Task5ReceptionMode: String, CaseIterable, Codable, Identifiable {
    case typed, paper
    var id: String { rawValue }
    var title: String { self == .typed ? "Ввод в приложении" : "На бумаге" }
}

enum Task5StationRole: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case main, subordinate
    var title: String { self == .main ? "Главная" : "Подчинённая" }
    var counterpart: Task5StationRole { self == .main ? .subordinate : .main }
}

struct Task5Configuration: Codable, Equatable {
    var ownCallsign = ""
    var botCallsign = ""
    var botSpeed = 50
    var keySpeed = 75
    var category: Task5Category = .first
    var length: Task5Length = .full
    var receptionMode: Task5ReceptionMode = .typed
    var rehearsal = false
    var radioFlow: Bool? = nil
    // Missing in older archives, whose operator always followed the main-station scenario.
    var stationRole: Task5StationRole? = nil
    var radiogramCharset: Task5Charset? = nil
    var role: Task5StationRole {
        get { stationRole ?? .main }
        set { stationRole = newValue }
    }

    static let authenticationTitle = "Пароль: разность с 50 по ТДР"
    static let profileNote = "Профиль майора: одна радиограмма на передачу и одна на приём; по 30 или 60 групп текста. В заголовке дополнительно учитываются две адресные группы. Ответ на пароль — |50 − число|, закодированный по ТДР. Ноль — пять тире."
}

enum Task5Direction: String, Codable, CaseIterable {
    case transmit, receive
    var title: String { self == .transmit ? "Передача" : "Приём" }
}

enum Task5Charset: String, Codable {
    case letters, digits
    var title: String { self == .letters ? "Буквы" : "Цифры" }
}

struct Task5RadioData: Codable, Equatable {
    let mainFrequency: String
    let reserveFrequency: String
    let networkNumber: String
    let operatorName: String
}

struct Task5Radiogram: Codable, Identifiable, Equatable {
    let id: String
    let number: String
    let charset: Task5Charset
    let direction: Task5Direction
    let groups: [String]
    let urgency: String
    let urgencyCode: String
    let address: String
    let operatorGroup: String
    /// Day, hour, minute of the generated exercise; no implied historical date.
    let dateTime: String
    let originCallsign: String
    let recipientCallsign: String
    var majorFormat: Bool? = nil
    var groupCount: Int { groups.count }
    var declaredGroupCount: Int { groupCount + (majorFormat == true ? 2 : 3) }
    var header: String { (majorFormat == true ? originCallsign + " " : "") + "\(number) \(declaredGroupCount) \(dateTime) \(number)" }
    var wireText: String { "\(header) = \(urgencyCode) \(address) = \(groups.joined(separator: " "))" + (majorFormat == true ? " К" : " \(operatorGroup) К") }
    var receipt: String { (majorFormat == true ? "" : recipientCallsign + " ") + "Р \(number) К" }
}

struct Task5Signal: Codable, Identifiable, Equatable {
    let id: String
    let direction: Task5Direction
    let group: String
    let originCallsign: String
    let recipientCallsign: String
    var networkCallsign: String? = nil
    var terminatesFirstPart: Bool? = nil
    private var signalBody: String { "ЬЬЬ ЬЬЬ " + (networkCallsign.map { "\($0) \($0) " } ?? "") + "\(group) \(group)" }
    var firstPart: String { signalBody + (terminatesFirstPart == true ? " К" : "") }
    var secondPart: String { signalBody + " К" }
    var wireText: String { firstPart + "\n" + secondPart }
    var receipt: String { "\(recipientCallsign) Р \(group) К" }
    static let pauseSeconds: TimeInterval = 10
}

enum Task5StepKind: String, Codable {
    case administrative, transmit, receive, receipt, signal, listen, pause
}

struct Task5Step: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let instruction: String
    let kind: Task5StepKind
    var expectedMessages: [String] = []
    /// Played when this step begins. Never a response implicitly played after submit.
    var botMessage: String?
    var radiogramID: String?
    var direction: Task5Direction?
    var bodyGroups = 0
    var requiredPauseSeconds: TimeInterval = 0
    /// Decoding by meaning accepts equivalent cells and either axis-key letter.
    var tdrExpressionID: String?
    /// The educational cell challenge requires this cell, not any synonymous cell.
    var tdrCellNumber: String?
    /// Expected decoded authentication tokens: password expression, numeric cells, or literal service signs.
    var authenticationTokens: [String]?
}

struct Task5Variant: Codable, Equatable {
    let seed: UInt64
    let profileID: String
    let configuration: Task5Configuration
    let ownCallsign: String
    let botCallsign: String
    let radioData: Task5RadioData
    let tdr: Task5TDR
    let radiograms: [Task5Radiogram]
    let signals: [Task5Signal]
    let steps: [Task5Step]
    var totalBodyGroups: Int { radiograms.reduce(0) { $0 + $1.groupCount } }
}

struct Task5Validation: Equatable {
    let isCorrect: Bool
    let message: String?
    let errors: Int
    static let correct = Task5Validation(isCorrect: true, message: nil, errors: 0)
    static func wrong(_ message: String, errors: Int = 1) -> Self {
        .init(isCorrect: false, message: message, errors: max(1, errors))
    }
}
