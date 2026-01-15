import Foundation
import Security

/// Manages secure storage of sensitive data in macOS Keychain
class KeychainManager {
    static let shared = KeychainManager()

    private let serviceName = "com.openwork.api-keys"

    private init() {}

    // MARK: - API Key Storage

    /// Saves an API key for a provider
    func saveAPIKey(_ key: String, for providerID: UUID) throws {
        let account = providerID.uuidString

        // Delete existing key first
        try? deleteAPIKey(for: providerID)

        guard !key.isEmpty else { return }

        guard let keyData = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieves an API key for a provider
    func getAPIKey(for providerID: UUID) -> String? {
        let account = providerID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Deletes an API key for a provider
    func deleteAPIKey(for providerID: UUID) throws {
        let account = providerID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Updates an existing API key
    func updateAPIKey(_ key: String, for providerID: UUID) throws {
        // Simply save again (it deletes first)
        try saveAPIKey(key, for: providerID)
    }

    // MARK: - Batch Operations

    /// Deletes all API keys (for cleanup)
    func deleteAllAPIKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Migrates API keys from UserDefaults to Keychain
    func migrateFromUserDefaults(providers: [LLMProviderConfig]) {
        for provider in providers {
            // If provider has an API key stored in the config, migrate it
            if !provider.apiKey.isEmpty {
                do {
                    try saveAPIKey(provider.apiKey, for: provider.id)
                } catch {
                    print("Failed to migrate API key for \(provider.name): \(error)")
                }
            }
        }
    }

    // MARK: - Generic Data Storage

    /// Saves arbitrary data to keychain with a string key
    func save(key: String, data: Data) {
        // Delete existing first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    /// Loads data from keychain by string key
    func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    /// Deletes data from keychain by string key
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for Keychain"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        case .notFound:
            return "Item not found in Keychain"
        }
    }
}

// MARK: - LLMProviderConfig Extension

extension LLMProviderConfig {
    /// Gets the API key from Keychain (preferred) or falls back to stored value
    var secureAPIKey: String {
        KeychainManager.shared.getAPIKey(for: id) ?? apiKey
    }

    /// Saves the API key to Keychain
    func saveAPIKeyToKeychain() throws {
        try KeychainManager.shared.saveAPIKey(apiKey, for: id)
    }
}
