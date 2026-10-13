import Foundation
import Security

struct RelayCredential: Codable {
    var token: String
    var callsign: String
}

/// Credential scope includes the relay origin; test profiles can disable storage.
final class KeychainCredentialStore {
    private let account: String
    private let service = "com.paloma.morse.native.auth"
    init(origin: URL) { account = origin.absoluteString }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func read() -> RelayCredential? {
        var request = query, result: CFTypeRef?
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(RelayCredential.self, from: data)
    }
    func write(_ credential: RelayCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            if added != errSecSuccess { throw SocketIONetworkService.Failure.message("Keychain error \(added)") }
        } else if status != errSecSuccess { throw SocketIONetworkService.Failure.message("Keychain error \(status)") }
    }
    func clear() { SecItemDelete(query as CFDictionary) }
}
