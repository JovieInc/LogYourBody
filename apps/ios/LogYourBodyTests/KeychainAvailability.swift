//
// KeychainAvailability.swift
// LogYourBodyTests
//
import Foundation
import Security

/// Probes whether the current test host can actually use the keychain.
///
/// CI builds the test host unsigned (`CODE_SIGNING_ALLOWED=NO`), so every
/// SecItem call there fails with `errSecMissingEntitlement` (-34018) or
/// `errSecNotAvailable` (-25291). Keychain-backed suites gate on this probe
/// with `XCTSkipUnless` so they skip — rather than fail — on such hosts.
///
/// Deliberately independent of `KeychainManager`: the probe must exercise the
/// raw Security framework directly so a broken subject cannot mask itself as
/// an unavailable environment.
enum KeychainAvailability {
    /// Performs a throwaway add → copy → delete round-trip under a unique
    /// service/account pair. Returns false when any step fails; entitlement
    /// errors (-34018 / -25291) are the expected unsigned-host failure mode.
    /// Never triggers UI interaction.
    static func isAvailable() -> Bool {
        let probeService = "com.logyourbody.tests.keychain-availability.\(UUID().uuidString)"
        let probeAccount = UUID().uuidString
        let probeData = Data("keychain-availability".utf8)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: probeAccount,
            kSecValueData as String: probeData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            return false
        }
        defer {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: probeService,
                kSecAttrAccount as String: probeAccount
            ]
            _ = SecItemDelete(deleteQuery as CFDictionary)
        }

        let copyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: probeAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var copied: AnyObject?
        guard SecItemCopyMatching(copyQuery as CFDictionary, &copied) == errSecSuccess else {
            return false
        }
        return (copied as? Data) == probeData
    }
}
