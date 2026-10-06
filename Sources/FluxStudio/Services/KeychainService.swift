import Foundation
import Security

/// Guarda la API key en el Llavero de macOS (nunca en texto plano).
enum KeychainService {
    private static let service = "com.grupocosmic.fluxstudio"
    private static let account = "bfl-api-key"

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "código \(status)"
            return "No se ha podido guardar en el Llavero: \(text)"
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func saveAPIKey(_ key: String) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrLabel as String] = "FLUX Studio · API key de BFL"
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func loadAPIKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
