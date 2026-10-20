//
// BodySpecAuthManagerTokenStateTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

/// Mirrors the wire format of `BodySpecAuthManager`'s private stored token so
/// tests can seed the keychain through `KeychainManager`'s public API without
/// reaching into app internals.
private struct BodySpecSeedToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let userId: String?
    let email: String?
}

@MainActor
final class BodySpecAuthManagerTokenStateTests: XCTestCase {
    private let keychain = KeychainManager.shared
    private let tokenStorageKey = "BodySpecAuthToken"

    override func setUpWithError() throws {
        try XCTSkipUnless(
            KeychainAvailability.isAvailable(),
            "Keychain unavailable on unsigned CI test host (errSecMissingEntitlement); "
                + "runs fully on signed hosts and local dev. "
                + "TODO(@itstimwhite): enable when CI signs the test host."
        )
        try super.setUpWithError()
        try? keychain.delete(forKey: tokenStorageKey)
    }

    override func tearDown() {
        try? keychain.delete(forKey: tokenStorageKey)
        super.tearDown()
    }

    func testManagerWithoutStoredTokenReportsDisconnectedState() async throws {
        let manager = BodySpecAuthManager()

        XCTAssertFalse(manager.isConnected)
        XCTAssertNil(manager.connectedEmail)
        // Nil on every host: unconfigured clients return nil, and configured
        // clients have no token to return.
        let token = try await manager.ensureValidToken()
        XCTAssertNil(token)
    }

    func testStoredUnexpiredTokenLoadsOnInit() async throws {
        try seedToken(
            BodySpecSeedToken(
                accessToken: "stored-access",
                refreshToken: "stored-refresh",
                expiresAt: Date().addingTimeInterval(3_600),
                userId: "user-1",
                email: "dexa@example.com"
            )
        )

        let manager = BodySpecAuthManager()

        XCTAssertTrue(manager.isConnected)
        XCTAssertEqual(manager.connectedEmail, "dexa@example.com")
    }

    func testStoredTokenWithoutEmailReportsNilConnectedEmail() async throws {
        try seedToken(
            BodySpecSeedToken(
                accessToken: "stored-access",
                refreshToken: nil,
                expiresAt: Date().addingTimeInterval(3_600),
                userId: nil,
                email: nil
            )
        )

        let manager = BodySpecAuthManager()

        XCTAssertTrue(manager.isConnected)
        XCTAssertNil(manager.connectedEmail)
    }

    func testStoredExpiredTokenIsNotConnected() async throws {
        try seedToken(
            BodySpecSeedToken(
                accessToken: "expired-access",
                refreshToken: "stored-refresh",
                expiresAt: Date().addingTimeInterval(-3_600),
                userId: "user-1",
                email: "dexa@example.com"
            )
        )

        let manager = BodySpecAuthManager()

        XCTAssertFalse(manager.isConnected)
        // Nil on every host: unconfigured clients return nil, and configured
        // clients reject the expired token.
        let token = try await manager.ensureValidToken()
        XCTAssertNil(token)
    }

    func testDisconnectClearsSessionStateAndKeychain() async throws {
        try seedToken(
            BodySpecSeedToken(
                accessToken: "stored-access",
                refreshToken: "stored-refresh",
                expiresAt: Date().addingTimeInterval(3_600),
                userId: "user-1",
                email: "dexa@example.com"
            )
        )
        let manager = BodySpecAuthManager()
        XCTAssertTrue(manager.isConnected)

        manager.disconnect()

        XCTAssertFalse(manager.isConnected)
        XCTAssertNil(manager.connectedEmail)
        XCTAssertNil(try keychain.get(forKey: tokenStorageKey, as: BodySpecSeedToken.self))

        let reloaded = BodySpecAuthManager()
        XCTAssertFalse(reloaded.isConnected)
        XCTAssertNil(reloaded.connectedEmail)
    }

    private func seedToken(_ token: BodySpecSeedToken) throws {
        try keychain.save(token, forKey: tokenStorageKey)
    }
}
