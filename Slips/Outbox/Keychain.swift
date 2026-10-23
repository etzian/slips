import Foundation
import Security

/// Destination secrets (WebDAV passwords, later tokens), one generic-password item per destination id.
/// Readable after the first unlock, so background uploads can sign in; never synced, never backed up
/// to another device.
enum Keychain {
    static let service = "com.etzian.slips.destination"

    static func set(_ secret: String, for destination: UUID) throws {
        let query = base(destination)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func get(_ destination: UUID) -> String? {
        var query = base(destination)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ destination: UUID) {
        SecItemDelete(base(destination) as CFDictionary)
    }

    private static func base(_ destination: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: destination.uuidString]
    }
}

struct KeychainError: Error {
    let status: OSStatus
}
