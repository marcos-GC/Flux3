import Foundation
import Security

/// Guarda la API key en el Llavero de macOS (nunca en texto plano).
enum KeychainService {
    private static let service = "com.grupocosmic.fluxstudio"
    static let bflAccount = "bfl-api-key"
    static let anthropicAccount = "anthropic-api-key"

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "código \(status)"
            return "No se ha podido guardar en el Llavero: \(text)"
        }
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func saveAPIKey(_ key: String, account: String = bflAccount) throws {
        SecItemDelete(baseQuery(account) as CFDictionary)
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrLabel as String] = account == anthropicAccount
            ? "FLUX Studio · API key de Anthropic"
            : "FLUX Studio · API key de BFL"
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Comprueba si hay una clave guardada SIN leer su contenido
    /// (leer solo los atributos no hace que macOS pida permiso).
    static func hasAPIKey(account: String = bflAccount) -> Bool {
        var query = baseQuery(account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Lee la clave. La primera vez macOS puede pedir permiso («Permitir siempre» lo recuerda).
    static func loadAPIKey(account: String = bflAccount) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(account: String = bflAccount) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
