import Foundation

struct Task5TDRCell: Codable, Identifiable, Equatable {
    let number: String
    let row: Int
    let column: Int
    let expressionId: String?
    let expression: String?
    let printedLetterMarker: String?
    var id: String { number }
}

struct Task5TDR: Codable, Equatable {
    let cells: [Task5TDRCell]
    /// Two alternatives per digit, disjoint within each axis.
    let rowKeys: [String]
    let columnKeys: [String]

    func cells(forExpressionID id: String) -> [Task5TDRCell] {
        cells.filter { $0.expressionId == id }
    }

    func codes(for cell: Task5TDRCell) -> [String] {
        guard rowKeys.indices.contains(cell.row), columnKeys.indices.contains(cell.column) else { return [] }
        return rowKeys[cell.row].flatMap { r in columnKeys[cell.column].map { c in "З\(r)\(c)" } }
    }

    func codes(forExpressionID id: String) -> [String] {
        cells(forExpressionID: id).flatMap { codes(for: $0) }
    }

    func decode(_ code: String) -> Task5TDRCell? {
        let chars = Array(code.uppercased())
        guard chars.count == 3, chars[0] == "З",
              let row = rowKeys.firstIndex(where: { $0.contains(chars[1]) }),
              let col = columnKeys.firstIndex(where: { $0.contains(chars[2]) }) else { return nil }
        return cells.first { $0.row == row && $0.column == col }
    }
}

struct Task5ServiceCode: Decodable, Identifiable, Equatable {
    struct Variant: Decodable, Equatable {
        struct Source: Decodable, Equatable { let id: String; let column: String }
        let meaning: String
        let sources: [Source]
        let parameterUnit: String?
    }
    let code: String
    let variants: [Variant]
    var id: String { code }
}

struct Task5Reference {
    let cells: [Task5TDRCell]
    let codes: [Task5ServiceCode]

    enum LoadError: LocalizedError {
        case missing(String), invalid(String)
        var errorDescription: String? {
            switch self {
            case .missing(let name): "Не найден справочник \(name)"
            case .invalid(let reason): "Ошибка справочника: \(reason)"
            }
        }
    }

    init(cells: [Task5TDRCell], codes: [Task5ServiceCode]) {
        self.cells = cells; self.codes = codes
    }

    static func load(from bundle: Bundle = .main) throws -> Task5Reference {
        func data(_ name: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "json") else { throw LoadError.missing(name) }
            return try Data(contentsOf: url)
        }
        struct Table: Decodable { let cells: [Task5TDRCell] }
        struct CodeBook: Decodable { let entries: [Task5ServiceCode] }
        let table = try JSONDecoder().decode(Table.self, from: data("task5-tdr.v1"))
        let codes = try JSONDecoder().decode(CodeBook.self, from: data("task5-service-radiocodes.v1"))
        guard table.cells.count == 100,
              Set(table.cells.map(\.number)) == Set((0...99).map { String(format: "%02d", $0) }),
              table.cells.allSatisfy({ $0.number == String(format: "%d%d", $0.row, $0.column) }) else {
            throw LoadError.invalid("ТДР должна содержать ячейки 00–99")
        }
        guard !codes.entries.isEmpty, Set(codes.entries.map(\.code)).count == codes.entries.count else {
            throw LoadError.invalid("повторяющиеся или отсутствующие коды")
        }
        return Task5Reference(cells: table.cells, codes: codes.entries)
    }
}
