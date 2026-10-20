import Foundation
import Security
import YanaMarketData

enum KeychainError: Error, Equatable, LocalizedError {
    case status(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        case .invalidData:
            return "The saved credential could not be read."
        }
    }
}

/// Provider credentials as generic-password Keychain items: one per provider ID, never synchronized to iCloud
/// Keychain, and readable only on this Mac.
struct KeychainCredentialStore: CredentialStore {
    /// Keychain service name; the provider ID is the account.
    let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "Yana") + ".market-data") {
        self.service = service
    }

    func credential(for providerID: String) throws -> String? {
        var query = baseQuery(providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    func save(_ credential: String, for providerID: String) throws {
        let data = Data(credential.utf8)
        let update = SecItemUpdate(baseQuery(providerID) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError.status(update) }

        var item = baseQuery(providerID)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "Yana market data (\(providerID))"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func remove(for providerID: String) throws {
        let status = SecItemDelete(baseQuery(providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    /// The stored item's attributes, for verifying how it is protected.
    func attributes(for providerID: String) throws -> [String: Any]? {
        var query = baseQuery(providerID)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return result as? [String: Any]
    }

    private func baseQuery(_ providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
