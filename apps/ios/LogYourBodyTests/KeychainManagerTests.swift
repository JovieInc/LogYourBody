//
// KeychainManagerTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class KeychainManagerTests: XCTestCase {
    private struct SampleSession: Codable, Equatable {
        let token: String
        let issuedAt: Int
    }

    private let keychain = KeychainManager.shared
    private var sessionKeysToClean: [String] = []

    override func setUp() {
        super.setUp()
        // Start from a clean slate for the fixed token entries this suite exercises.
        try? keychain.deleteAuthToken()
        try? keychain.deleteRefreshToken()
    }

    override func tearDown() {
        for key in sessionKeysToClean {
            try? keychain.deleteUserSession(forKey: key)
        }
        sessionKeysToClean.removeAll()
        try? keychain.deleteAuthToken()
        try? keychain.deleteRefreshToken()
        super.tearDown()
    }

    private func uniqueSessionKey(_ label: String) -> String {
        let key = "keychain-tests.\(label).\(UUID().uuidString)"
        sessionKeysToClean.append(key)
        return key
    }

    func testSaveAndReadAuthTokenRoundTrip() throws {
        try keychain.saveAuthToken("auth-token-abc")

        XCTAssertEqual(try keychain.getAuthToken(), "auth-token-abc")
    }

    func testSaveAndReadRefreshTokenRoundTrip() throws {
        try keychain.saveRefreshToken("refresh-token-xyz")

        XCTAssertEqual(try keychain.getRefreshToken(), "refresh-token-xyz")
    }

    func testOverwriteAuthTokenUpdatesStoredValue() throws {
        try keychain.saveAuthToken("first-token")
        try keychain.saveAuthToken("second-token")

        XCTAssertEqual(try keychain.getAuthToken(), "second-token")
    }

    func testReadMissingAuthTokenReturnsNil() throws {
        XCTAssertNil(try keychain.getAuthToken())
    }

    func testDeleteAuthTokenRemovesStoredValue() throws {
        try keychain.saveAuthToken("token-to-delete")

        try keychain.deleteAuthToken()

        XCTAssertNil(try keychain.getAuthToken())
    }

    func testDeleteMissingAuthTokenDoesNotThrow() throws {
        XCTAssertNoThrow(try keychain.deleteAuthToken())
    }

    func testAuthAndRefreshTokensAreIsolated() throws {
        try keychain.saveAuthToken("auth-only")
        try keychain.saveRefreshToken("refresh-only")

        try keychain.deleteAuthToken()

        XCTAssertNil(try keychain.getAuthToken())
        XCTAssertEqual(try keychain.getRefreshToken(), "refresh-only")
    }

    func testUserSessionRoundTripPreservesCodableValue() throws {
        let key = uniqueSessionKey("roundtrip")
        let session = SampleSession(token: "session-token", issuedAt: 1_700_000_000)

        try keychain.saveUserSession(session, forKey: key)

        XCTAssertEqual(try keychain.getUserSession(forKey: key, as: SampleSession.self), session)
    }

    func testReadMissingUserSessionReturnsNil() throws {
        let key = uniqueSessionKey("missing")

        XCTAssertNil(try keychain.getUserSession(forKey: key, as: SampleSession.self))
    }

    func testDistinctSessionKeysAreIsolated() throws {
        let firstKey = uniqueSessionKey("first")
        let secondKey = uniqueSessionKey("second")
        try keychain.saveUserSession(SampleSession(token: "first", issuedAt: 1), forKey: firstKey)
        try keychain.saveUserSession(SampleSession(token: "second", issuedAt: 2), forKey: secondKey)

        try keychain.deleteUserSession(forKey: firstKey)

        XCTAssertNil(try keychain.getUserSession(forKey: firstKey, as: SampleSession.self))
        XCTAssertEqual(
            try keychain.getUserSession(forKey: secondKey, as: SampleSession.self),
            SampleSession(token: "second", issuedAt: 2)
        )
    }

    func testClearAllRemovesSeededEntriesAndToleratesEmptyKeychain() throws {
        let key = uniqueSessionKey("clearall")
        try keychain.saveAuthToken("auth-to-clear")
        try keychain.saveRefreshToken("refresh-to-clear")
        try keychain.saveUserSession(SampleSession(token: "session-to-clear", issuedAt: 3), forKey: key)

        try keychain.clearAll()

        XCTAssertNil(try keychain.getAuthToken())
        XCTAssertNil(try keychain.getRefreshToken())
        XCTAssertNil(try keychain.getUserSession(forKey: key, as: SampleSession.self))
        // A second pass over an empty keychain must not throw.
        XCTAssertNoThrow(try keychain.clearAll())
    }
}
