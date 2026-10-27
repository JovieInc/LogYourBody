//
// KeychainAvailability.swift
// LogYourBodyTests
//
import Foundation
import Security
import XCTest

/// Probes whether the current test host can actually use the keychain.
///
/// Unsigned CI hosts can return `errSecMissingEntitlement` (-34018) or
/// `errSecNotAvailable` (-25291). Only those raw Security results permit a
/// skip. Skipped behavior still requires non-skipped entitled-host execution.
///
/// Deliberately independent of `KeychainManager`: the probe must exercise the
/// raw Security framework directly so a broken subject cannot mask itself as
/// an unavailable environment.
enum KeychainAvailability {
    struct Client {
        let add: (CFDictionary) -> OSStatus
        let copy: (CFDictionary) -> (status: OSStatus, value: AnyObject?)
        let delete: (CFDictionary) -> OSStatus

        static let security = Self(
            add: { SecItemAdd($0, nil) },
            copy: { query in
                var value: AnyObject?
                let status = SecItemCopyMatching(query, &value)
                return (status, value)
            },
            delete: { SecItemDelete($0) }
        )
    }

    enum Failure: Error, Equatable, CustomStringConvertible {
        case unexpectedStatus(operation: String, status: OSStatus)
        case invalidCopiedData

        var description: String {
            switch self {
            case let .unexpectedStatus(operation, status):
                return "Keychain probe \(operation) failed: \(KeychainAvailability.statusDescription(status))."
            case .invalidCopiedData:
                return "Keychain probe SecItemCopyMatching succeeded with missing, invalid or mismatched data."
            }
        }
    }

    struct CleanupFailure: Error, CustomStringConvertible {
        let status: OSStatus
        let precedingError: Error?

        var description: String {
            let cleanup = Failure.unexpectedStatus(operation: "SecItemDelete", status: status).description
            guard let precedingError else { return cleanup }
            return "\(precedingError) Cleanup also failed: \(cleanup)"
        }
    }

    /// Performs a throwaway add → copy → delete round-trip under a unique
    /// service/account pair, independently of the product KeychainManager.
    /// Unexpected statuses and wrong returned data fail rather than skip.
    static func requireAvailable(using client: Client = .security) throws {
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
        try requireSuccess(client.add(addQuery as CFDictionary), operation: "SecItemAdd")
        let copyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: probeAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var precedingError: Error?
        do {
            let copied = client.copy(copyQuery as CFDictionary)
            try requireSuccess(copied.status, operation: "SecItemCopyMatching")
            guard (copied.value as? Data) == probeData else {
                throw Failure.invalidCopiedData
            }
        } catch {
            precedingError = error
        }

        // Always clean up a successful add, retaining any earlier failure.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: probeAccount
        ]
        let cleanupStatus = client.delete(deleteQuery as CFDictionary)
        guard cleanupStatus == errSecSuccess else {
            throw CleanupFailure(status: cleanupStatus, precedingError: precedingError)
        }
        if let precedingError { throw precedingError }
    }

    private static func requireSuccess(_ status: OSStatus, operation: String) throws {
        guard status != errSecSuccess else { return }
        // Only independently recognized host-capability failures may skip.
        if status == errSecMissingEntitlement || status == errSecNotAvailable {
            throw XCTSkip(
                "Keychain capability unavailable: \(operation) returned \(statusDescription(status)). "
                    + "Non-skipped entitled-host execution remains required."
            )
        }
        throw Failure.unexpectedStatus(operation: operation, status: status)
    }

    private static func statusDescription(_ status: OSStatus) -> String {
        let name: String
        switch status {
        case errSecMissingEntitlement: name = "errSecMissingEntitlement"
        case errSecNotAvailable: name = "errSecNotAvailable"
        case errSecParam: name = "errSecParam"
        case errSecAuthFailed: name = "errSecAuthFailed"
        case errSecDuplicateItem: name = "errSecDuplicateItem"
        case errSecItemNotFound: name = "errSecItemNotFound"
        case errSecInteractionNotAllowed: name = "errSecInteractionNotAllowed"
        default: name = "unknown OSStatus"
        }
        return "\(name) (\(status))"
    }
}

/// These injected Security tests run even when the real host lacks entitlements.
final class KeychainAvailabilityTests: XCTestCase {
    private final class SecurityStub {
        var addStatus = errSecSuccess
        var copyStatus = errSecSuccess
        var deleteStatus = errSecSuccess
        var useAddedData = true
        var copiedValue: AnyObject?
        var calls: [String] = []
        var addQuery: NSDictionary?
        var copyQuery: NSDictionary?
        var deleteQuery: NSDictionary?

        var client: KeychainAvailability.Client {
            .init(
                add: { query in
                    self.calls.append("add")
                    self.addQuery = query as NSDictionary
                    return self.addStatus
                },
                copy: { query in
                    self.calls.append("copy")
                    self.copyQuery = query as NSDictionary
                    let value = self.useAddedData
                        ? self.addQuery?[kSecValueData as String] as AnyObject?
                        : self.copiedValue
                    return (self.copyStatus, value)
                },
                delete: { query in
                    self.calls.append("delete")
                    self.deleteQuery = query as NSDictionary
                    return self.deleteStatus
                }
            )
        }
    }

    private let unsupportedStatuses: [(OSStatus, String)] = [
        (errSecMissingEntitlement, "errSecMissingEntitlement"),
        (errSecNotAvailable, "errSecNotAvailable")
    ]

    private let unexpectedStatuses: [OSStatus] = [
        errSecParam, errSecAuthFailed, errSecDuplicateItem,
        errSecItemNotFound, errSecInteractionNotAllowed, -98_765
    ]

    func testSuccessfulRoundTripCleansUpTheExactProbeItem() throws {
        let stub = SecurityStub()
        try KeychainAvailability.requireAvailable(using: stub.client)

        XCTAssertEqual(stub.calls, ["add", "copy", "delete"])
        for key in [kSecClass, kSecAttrService, kSecAttrAccount] {
            let added = stub.addQuery?[key as String] as? String
            XCTAssertNotNil(added)
            XCTAssertTrue((stub.copyQuery?[key as String] as? String) == added)
            XCTAssertTrue((stub.deleteQuery?[key as String] as? String) == added)
        }
        XCTAssertNil(stub.deleteQuery?[kSecValueData as String])
    }

    func testOnlyKnownAddCapabilityFailuresSkipWithActualStatus() {
        for (status, name) in unsupportedStatuses {
            let stub = SecurityStub()
            stub.addStatus = status
            XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
                XCTAssertTrue(error is XCTSkip)
                XCTAssertTrue(String(describing: error).contains("SecItemAdd returned \(name) (\(status))"))
                XCTAssertTrue(String(describing: error).contains("Non-skipped entitled-host execution remains required"))
            }
            XCTAssertEqual(stub.calls, ["add"])
        }
    }

    func testOnlyKnownCopyCapabilityFailuresSkipAfterCleanup() {
        for (status, name) in unsupportedStatuses {
            let stub = SecurityStub()
            stub.copyStatus = status
            XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
                XCTAssertTrue(error is XCTSkip)
                XCTAssertTrue(String(describing: error).contains("SecItemCopyMatching returned \(name) (\(status))"))
            }
            XCTAssertEqual(stub.calls, ["add", "copy", "delete"])
        }
    }

    func testUnexpectedAddFailuresFailWithoutCopyOrCleanup() {
        for status in unexpectedStatuses {
            let stub = SecurityStub()
            stub.addStatus = status
            XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
                XCTAssertEqual(
                    error as? KeychainAvailability.Failure,
                    .unexpectedStatus(operation: "SecItemAdd", status: status)
                )
                XCTAssertFalse(error is XCTSkip)
            }
            XCTAssertEqual(stub.calls, ["add"])
        }
    }

    func testUnexpectedCopyFailuresFailAfterCleanup() {
        for status in unexpectedStatuses {
            let stub = SecurityStub()
            stub.copyStatus = status
            XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
                XCTAssertEqual(
                    error as? KeychainAvailability.Failure,
                    .unexpectedStatus(operation: "SecItemCopyMatching", status: status)
                )
                XCTAssertFalse(error is XCTSkip)
            }
            XCTAssertEqual(stub.calls, ["add", "copy", "delete"])
        }
    }

    func testSuccessfulCopyWithMissingWrongTypeOrWrongValueFailsAfterCleanup() {
        let invalidValues: [AnyObject?] = [nil, "wrong-type" as NSString, Data("wrong-value".utf8) as NSData]
        for value in invalidValues {
            let stub = SecurityStub()
            stub.useAddedData = false
            stub.copiedValue = value
            XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
                XCTAssertEqual(error as? KeychainAvailability.Failure, .invalidCopiedData)
                XCTAssertFalse(error is XCTSkip)
                XCTAssertFalse(String(describing: error).contains("wrong-type"))
                XCTAssertFalse(String(describing: error).contains("wrong-value"))
            }
            XCTAssertEqual(stub.calls, ["add", "copy", "delete"])
        }
    }

    func testCleanupFailuresNeverSkipEvenForCapabilityStatuses() {
        for status in unexpectedStatuses + unsupportedStatuses.map({ $0.0 }) {
            let stub = SecurityStub()
            stub.deleteStatus = status
            XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
                let cleanup = error as? KeychainAvailability.CleanupFailure
                XCTAssertEqual(cleanup?.status, status)
                XCTAssertNil(cleanup?.precedingError)
                XCTAssertFalse(error is XCTSkip)
                XCTAssertTrue(String(describing: error).contains("SecItemDelete"))
            }
            XCTAssertEqual(stub.calls, ["add", "copy", "delete"])
        }
    }

    func testCleanupFailureRetainsUnexpectedCopyFailure() {
        let stub = SecurityStub()
        stub.copyStatus = errSecAuthFailed
        stub.deleteStatus = errSecParam
        XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
            let cleanup = error as? KeychainAvailability.CleanupFailure
            XCTAssertEqual(cleanup?.status, errSecParam)
            XCTAssertEqual(
                cleanup?.precedingError as? KeychainAvailability.Failure,
                .unexpectedStatus(operation: "SecItemCopyMatching", status: errSecAuthFailed)
            )
            XCTAssertTrue(String(describing: error).contains("errSecAuthFailed"))
            XCTAssertTrue(String(describing: error).contains("errSecParam"))
        }
    }

    func testCleanupFailureRetainsInvalidDataFailure() {
        let stub = SecurityStub()
        stub.useAddedData = false
        stub.deleteStatus = errSecParam
        XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
            let cleanup = error as? KeychainAvailability.CleanupFailure
            XCTAssertEqual(cleanup?.precedingError as? KeychainAvailability.Failure, .invalidCopiedData)
        }
    }

    func testCleanupFailureDoesNotBecomeACopyCapabilitySkip() {
        let stub = SecurityStub()
        stub.copyStatus = errSecMissingEntitlement
        stub.deleteStatus = errSecNotAvailable
        XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
            let cleanup = error as? KeychainAvailability.CleanupFailure
            XCTAssertEqual(cleanup?.status, errSecNotAvailable)
            XCTAssertTrue(cleanup?.precedingError is XCTSkip)
            XCTAssertFalse(error is XCTSkip)
        }
    }

    func testFailureDiagnosticsNeverExposeProbeIdentifiersOrData() {
        let stub = SecurityStub()
        stub.copyStatus = errSecItemNotFound
        stub.deleteStatus = errSecParam
        XCTAssertThrowsError(try KeychainAvailability.requireAvailable(using: stub.client)) { error in
            let description = String(describing: error)
            for key in [kSecAttrService, kSecAttrAccount] {
                if let identifier = stub.addQuery?[key as String] as? String {
                    XCTAssertFalse(description.contains(identifier))
                } else {
                    XCTFail("Probe identifier was not captured")
                }
            }
            XCTAssertFalse(description.contains("keychain-availability"))
        }
    }
}
