import Foundation
import Security

/// Destination secrets (WebDAV passwords, later tokens), one generic-password item per destination id.
/// Readable after the first unlock, so background uploads can sign in; never synced, never backed up
/// to another device.
enum Keychain {
    static let service = "com.etzian.slips.destination"

    static func set(_ secret: String, for destination: UUID) throws {
        try set(secret, account: destination.uuidString)
    }

    static func get(_ destination: UUID) -> String? {
        get(account: destination.uuidString)
    }

    static func delete(_ destination: UUID) {
        delete(account: destination.uuidString)
    }

    // MARK: AI endpoint keys, one per profile and provider

    static func aiAccount(profile: UUID, provider: String) -> String { "ai.\(profile.uuidString).\(provider)" }

    static func set(_ secret: String, account: String) throws {
        let query = base(account)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func get(account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    /// Every AI key of a profile (erase, withdraw).
    static func deleteAIKeys(profile: UUID) {
        for provider in ["ollama", "claude", "openai"] { delete(account: aiAccount(profile: profile, provider: provider)) }
    }

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

struct KeychainError: Error {
    let status: OSStatus
}
