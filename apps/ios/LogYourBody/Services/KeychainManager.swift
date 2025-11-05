//
// KeychainManager.swift
// LogYourBody
//
// Secure storage manager using iOS Keychain for sensitive data
// Replaces UserDefaults for tokens, credentials, and sensitive preferences
//

import Foundation
import Security

enum KeychainError: Error {
    case duplicateEntry
    case unknown(OSStatus)
    case itemNotFound
    case invalidData
}

final class KeychainManager {
    static let shared = KeychainManager()

    private init() {}

    // MARK: - Service Identifiers

    private enum Service: String {
        case authToken = "com.logyourbody.authToken"
        case refreshToken = "com.logyourbody.refreshToken"
        case userSession = "com.logyourbody.userSession"
        case biometricSettings = "com.logyourbody.biometric"

        var identifier: String { rawValue }
    }

    // MARK: - Public API

    /// Store auth token securely
    func saveAuthToken(_ token: String) throws {
        try save(token, service: .authToken, account: "primary")
    }

    /// Retrieve auth token
    func getAuthToken() throws -> String? {
        try retrieve(service: .authToken, account: "primary")
    }

    /// Delete auth token
    func deleteAuthToken() throws {
        try delete(service: .authToken, account: "primary")
    }

    /// Store refresh token securely
    func saveRefreshToken(_ token: String) throws {
        try save(token, service: .refreshToken, account: "primary")
    }

    /// Retrieve refresh token
    func getRefreshToken() throws -> String? {
        try retrieve(service: .refreshToken, account: "primary")
    }

    /// Delete refresh token
    func deleteRefreshToken() throws {
        try delete(service: .refreshToken, account: "primary")
    }

    /// Store user session data (JSON-encoded)
    func saveUserSession<T: Codable>(_ session: T, forKey key: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        try save(data, service: .userSession, account: key)
    }

    /// Retrieve user session data
    func getUserSession<T: Codable>(forKey key: String, as type: T.Type) throws -> T? {
        guard let data: Data = try retrieve(service: .userSession, account: key) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    /// Delete user session data
    func deleteUserSession(forKey key: String) throws {
        try delete(service: .userSession, account: key)
    }

    /// Clear all keychain data (logout, account deletion)
    func clearAll() throws {
        let services: [Service] = [.authToken, .refreshToken, .userSession, .biometricSettings]

        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service.identifier
            ]

            let status = SecItemDelete(query as CFDictionary)
            // Ignore itemNotFound errors during clear all
            if status != errSecSuccess && status != errSecItemNotFound {
                throw KeychainError.unknown(status)
            }
        }
    }

    // MARK: - Generic Storage Methods

    /// Save string to keychain
    private func save(_ value: String, service: Service, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data, service: service, account: account)
    }

    /// Save data to keychain
    private func save(_ data: Data, service: Service, account: String) throws {
        // Check if item exists first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.identifier,
            kSecAttrAccount as String: account
        ]

        // Try to update existing item
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        // If item doesn't exist, add it
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }
    }

    /// Retrieve string from keychain
    private func retrieve(service: Service, account: String) throws -> String? {
        guard let data: Data = try retrieve(service: service, account: account) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieve data from keychain
    private func retrieve<T>(service: Service, account: String) throws -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.identifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }

        return result as? T
    }

    /// Delete item from keychain
    private func delete(service: Service, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.identifier,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Success if deleted or already didn't exist
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }
}

// MARK: - Convenience Extensions

extension KeychainManager {
    /// Store any Codable value
    func save<T: Codable>(_ value: T, forKey key: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        try save(data, service: .userSession, account: key)
    }

    /// Retrieve any Codable value
    func get<T: Codable>(forKey key: String, as type: T.Type) throws -> T? {
        guard let data: Data = try retrieve(service: .userSession, account: key) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    /// Delete any value
    func delete(forKey key: String) throws {
        try delete(service: .userSession, account: key)
    }
}
