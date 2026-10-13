import Foundation

struct MorseOverride: Codable, Equatable {
    var pattern: String?
    var mnemonic: String?
    var order: Int = 0

    init(pattern: String? = nil, mnemonic: String? = nil, order: Int = 0) {
        self.pattern = pattern; self.mnemonic = mnemonic; self.order = order
    }
    private enum CodingKeys: String, CodingKey { case pattern, mnemonic, order }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try values.decodeIfPresent(String.self, forKey: .pattern)
        mnemonic = try values.decodeIfPresent(String.self, forKey: .mnemonic)
        order = try values.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }

    static func sanitized(pattern: String?, mnemonic: String?) -> MorseOverride {
        MorseOverride(pattern: pattern?.filter { $0 == "." || $0 == "-" }, mnemonic: mnemonic?.replacingOccurrences(of: " ", with: "-").filter {
            $0 == "-" || $0 == "Ё" || $0 == "ё" || ("A"..."Z").contains(String($0)) || ("a"..."z").contains(String($0)) || ("А"..."Я").contains(String($0)) || ("а"..."я").contains(String($0))
        })
    }
}
