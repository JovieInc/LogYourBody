import XCTest
@testable import LogYourBody

@MainActor
final class BodySpecMemoryTokenStore: BodySpecTokenStoring {
    var token: BodySpecStoredToken?
    var saveError: Error?
    var deleteError: Error?
    var saveCount = 0

    init(token: BodySpecStoredToken? = nil) { self.token = token }
    func load() throws -> BodySpecStoredToken? { token }
    func save(_ token: BodySpecStoredToken) throws {
        if let saveError { throw saveError }
        saveCount += 1
        self.token = token
    }
    func delete() throws {
        if let deleteError { throw deleteError }
        token = nil
    }
}

@MainActor
final class BodySpecSyntheticAccount {
    var ownership: AuthManager.ProfileSessionOwnership? = .init(subject: "synthetic-owner", generation: 1)
    var access: BodySpecAccountAccess {
        BodySpecAccountAccess(capture: { [weak self] in self?.ownership }, owns: { [weak self] in self?.ownership == $0 })
    }
}

@MainActor
func syntheticBodySpecToken(owner: String? = "synthetic-owner", expiresAt: Date = .distantFuture) -> BodySpecStoredToken {
    BodySpecStoredToken(accessToken: "synthetic-access", refreshToken: nil, expiresAt: expiresAt,
                        userId: "synthetic-provider", email: "scan@example.invalid", lybOwnerId: owner)
}

@MainActor
final class BodySpecAuthManagerTokenStateTests: XCTestCase {
    func testManagerWithoutStoredTokenReportsDisconnectedState() async throws {
        let account = BodySpecSyntheticAccount()
        let manager = makeManager(store: BodySpecMemoryTokenStore(), account: account)
        XCTAssertFalse(manager.isConnected)
        XCTAssertNil(manager.connectedEmail)
        let token = try await manager.ensureValidToken()
        XCTAssertNil(token)
    }

    func testStoredOwnedUnexpiredTokenLoadsOnInit() throws {
        let account = BodySpecSyntheticAccount()
        let manager = makeManager(store: BodySpecMemoryTokenStore(token: syntheticBodySpecToken()), account: account)
        XCTAssertTrue(manager.isConnected)
        XCTAssertEqual(manager.connectedEmail, "scan@example.invalid")
        XCTAssertNoThrow(try manager.connectionSnapshot().validate())
    }

    func testLegacyStoredTokenDecodesButRequiresReconnect() throws {
        let data = Data("{\"accessToken\":\"synthetic-legacy\",\"expiresAt\":9999999999}".utf8)
        let legacy = try JSONDecoder().decode(BodySpecStoredToken.self, from: data)
        XCTAssertNil(legacy.lybOwnerId)
        let account = BodySpecSyntheticAccount()
        let manager = makeManager(store: BodySpecMemoryTokenStore(token: legacy), account: account)
        XCTAssertFalse(manager.isConnected)
        XCTAssertNil(manager.connectedEmail)
        XCTAssertThrowsError(try manager.connectionSnapshot())
    }

    func testForeignOwnedTokenCannotExposeConnectionOrEmail() throws {
        let account = BodySpecSyntheticAccount()
        account.ownership = .init(subject: "other-owner", generation: 1)
        let manager = makeManager(store: BodySpecMemoryTokenStore(token: syntheticBodySpecToken()), account: account)
        XCTAssertFalse(manager.isConnected)
        XCTAssertNil(manager.connectedEmail)
        XCTAssertThrowsError(try manager.connectionSnapshot())
    }

    func testSnapshotRejectsSameSubjectSessionReplacement() throws {
        let account = BodySpecSyntheticAccount()
        let manager = makeManager(store: BodySpecMemoryTokenStore(token: syntheticBodySpecToken()), account: account)
        let snapshot = try manager.connectionSnapshot()
        account.ownership = .init(subject: "other-owner", generation: 2)
        XCTAssertThrowsError(try snapshot.validate())
        account.ownership = .init(subject: "synthetic-owner", generation: 3)
        XCTAssertThrowsError(try snapshot.validate())
        XCTAssertNoThrow(try manager.connectionSnapshot().validate())
    }

    func testExpiredAndLaterExpiringSnapshotAreUnavailable() throws {
        let account = BodySpecSyntheticAccount()
        var instant = Date(timeIntervalSince1970: 100)
        let store = BodySpecMemoryTokenStore(token: syntheticBodySpecToken(expiresAt: instant.addingTimeInterval(1)))
        let manager = BodySpecAuthManager(
            tokenStore: store, account: account.access,
            configuration: { ("synthetic", "lyb-test://oauth") }, now: { instant }
        )
        let snapshot = try manager.connectionSnapshot()
        instant.addTimeInterval(2)
        XCTAssertFalse(manager.isConnected)
        XCTAssertThrowsError(try snapshot.validate())
        XCTAssertThrowsError(try manager.connectionSnapshot())
    }

    func testDisconnectInvalidatesSnapshotAndDurableStore() throws {
        let account = BodySpecSyntheticAccount()
        let store = BodySpecMemoryTokenStore(token: syntheticBodySpecToken())
        let manager = makeManager(store: store, account: account)
        let snapshot = try manager.connectionSnapshot()
        try manager.disconnect()
        XCTAssertFalse(manager.isConnected)
        XCTAssertNil(store.token)
        XCTAssertThrowsError(try snapshot.validate())
        XCTAssertFalse(makeManager(store: store, account: account).isConnected)
    }

    func testDeleteFailureIsReportedAndRuntimeSnapshotIsInvalidated() throws {
        let account = BodySpecSyntheticAccount()
        let store = BodySpecMemoryTokenStore(token: syntheticBodySpecToken())
        let manager = makeManager(store: store, account: account)
        let snapshot = try manager.connectionSnapshot()
        store.deleteError = URLError(.cannotWriteToFile)
        XCTAssertThrowsError(try manager.disconnect())
        XCTAssertFalse(manager.isConnected)
        XCTAssertThrowsError(try snapshot.validate())
        XCTAssertNotNil(store.token)
    }

    func testUnchangedAccountLifetimeKeepsSnapshotValid() throws {
        let account = BodySpecSyntheticAccount()
        let manager = makeManager(store: BodySpecMemoryTokenStore(token: syntheticBodySpecToken()), account: account)
        let ownership = try XCTUnwrap(account.ownership)
        let snapshot = try manager.connectionSnapshot(for: ownership)
        account.ownership = ownership // Ordinary token renewal retains this account lifetime.
        XCTAssertNoThrow(try snapshot.validate())
    }

    private func makeManager(store: BodySpecMemoryTokenStore, account: BodySpecSyntheticAccount) -> BodySpecAuthManager {
        BodySpecAuthManager(tokenStore: store, account: account.access, configuration: { ("synthetic", "lyb-test://oauth") })
    }
}
