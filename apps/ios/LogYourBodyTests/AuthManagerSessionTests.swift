//
// AuthManagerSessionTests.swift
// LogYourBodyTests
//
import XCTest
import CoreData
@testable import LogYourBody

/// Stubs the OAuth/HTTP boundary for AuthManager session tests.
/// Registered on a per-test URLSessionConfiguration, so no global state leaks
/// into other suites.
private final class AuthStubURLProtocol: URLProtocol {
    struct StubbedResponse {
        let statusCode: Int
        let body: Data
    }

    static var requestHandler: ((URLRequest) -> StubbedResponse)?
    static var deferredHandler: ((AuthStubURLProtocol) -> Bool)?
    static var recordedRequests: [URLRequest] = []
    static var activeFixture: String?

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard request.value(forHTTPHeaderField: "X-LYB-Test-Fixture") == Self.activeFixture,
              let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        Self.recordedRequests.append(request)
        if Self.deferredHandler?(self) == true { return }
        let stub = handler(request)
        respond(with: stub)
    }

    func respond(with stub: StubbedResponse) {
        guard let url = request.url, let client else { return }
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) ?? HTTPURLResponse()
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: stub.body)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        requestHandler = nil
        deferredHandler = nil
        recordedRequests = []
        activeFixture = nil
    }

    static func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}

private final class HeldAuthResponse: @unchecked Sendable {
    let started = XCTestExpectation(description: "Auth response is held")
    private let lock = NSLock()
    private var pending: [AuthStubURLProtocol] = []

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return pending.first?.request
    }

    func capture(_ request: AuthStubURLProtocol) {
        lock.lock()
        let isFirst = pending.isEmpty
        pending.append(request)
        lock.unlock()
        if isFirst { started.fulfill() }
    }

    func complete(status: Int, body: String) {
        lock.lock()
        let requests = pending
        pending = []
        lock.unlock()
        for request in requests {
            request.respond(with: .init(statusCode: status, body: Data(body.utf8)))
        }
    }
}

@MainActor
final class AuthManagerSessionTests: XCTestCase {
    private let keychain = KeychainManager.shared
    private let storedSessionKey = "productAuth.jovieOAuthSession"
    private var suiteName: String = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            KeychainAvailability.isAvailable(),
            "Keychain unavailable on unsigned CI test host (errSecMissingEntitlement); "
                + "runs fully on signed hosts and local dev. "
                + "TODO(@itstimwhite): enable when CI signs the test host."
        )
        try super.setUpWithError()
        suiteName = "AuthManagerSessionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        AuthStubURLProtocol.reset()
        AuthStubURLProtocol.activeFixture = suiteName
        try? keychain.delete(forKey: storedSessionKey)
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        try? keychain.delete(forKey: storedSessionKey)
        // setUpWithError may have thrown XCTSkip before the fixtures were
        // initialized; XCTest still runs tearDown, so guard the IUOs.
        if let defaults = defaults {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        super.tearDown()
    }

    private func makeManager() -> AuthManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-LYB-Test-Fixture": suiteName]
        return AuthManager(
            userDefaults: defaults,
            keychain: keychain,
            urlSession: URLSession(configuration: configuration)
        )
    }

    private func makeSession(
        accessToken: String = "cached-access",
        refreshToken: String = "cached-refresh",
        expiresAt: Date
    ) -> ProductAuthSession {
        ProductAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            subject: "user-123",
            email: "user@example.com",
            name: "Test User",
            issuedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func stubSessionSuccess(
        userBody: String = #"{"id":"user-123","email":"user@example.com","name":"Test User"}"#,
        includesRotatedRefreshToken: Bool = true
    ) {
        AuthStubURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.contains("oauth2/token") {
                let body = includesRotatedRefreshToken
                    ? #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#
                    : #"{"access_token":"new-access","expires_in":3600}"#
                return AuthStubURLProtocol.StubbedResponse(
                    statusCode: 200,
                    body: Data(body.utf8)
                )
            }
            if path.contains("oauth2/userinfo") {
                return AuthStubURLProtocol.StubbedResponse(
                    statusCode: 200,
                    body: Data(#"{"sub":"user-123","email":"user@example.com","name":"Test User"}"#.utf8)
                )
            }
            if path.hasSuffix("/get-session") {
                let body = "{\"session\":{\"id\":\"session-123\",\"expiresAt\":\"2030-01-01T00:00:00Z\"},\"user\":"
                    + userBody + "}"
                return AuthStubURLProtocol.StubbedResponse(statusCode: 200, body: Data(body.utf8))
            }
            if path.hasSuffix("/user") {
                let body = "{\"user\":" + userBody + "}"
                return AuthStubURLProtocol.StubbedResponse(statusCode: 200, body: Data(body.utf8))
            }
            // Profile bootstrap and any other call: fail closed, tests don't depend on it.
            return AuthStubURLProtocol.StubbedResponse(statusCode: 404, body: Data("{}".utf8))
        }
    }

    func testInitializeValidatesStoredSessionWithCanonicalBetterAuthRoute() async throws {
        let stored = makeSession(expiresAt: Date().addingTimeInterval(3_600))
        try keychain.save(stored, forKey: storedSessionKey)
        stubSessionSuccess()
        let manager = makeManager()

        await manager.initialize()

        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(
            AuthStubURLProtocol.recordedRequests.first?.url?.path,
            "/api/auth/get-session"
        )
    }

    func testGetAccessTokenReturnsCachedTokenWithoutNetworkWhenSessionUnexpired() async {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(3_600))

        let token = await manager.getAccessToken()

        XCTAssertEqual(token, "cached-access")
        XCTAssertTrue(AuthStubURLProtocol.recordedRequests.isEmpty)
    }

    func testInitializeRefreshesExpiredStoredSessionWithoutAnAppliedSession() async throws {
        try keychain.save(makeSession(expiresAt: Date().addingTimeInterval(-5)), forKey: storedSessionKey)
        stubSessionSuccess()
        let manager = makeManager()
        XCTAssertNil(manager.authSession)

        await manager.initialize()

        XCTAssertTrue(manager.isAuthProviderReady)
        XCTAssertEqual(manager.authSession?.accessToken, "new-access")
        XCTAssertEqual(manager.currentUser?.id, "user-123")
        XCTAssertEqual(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self), manager.authSession)
    }

    func testStoredSessionValidationAfterLogoutCannotRestoreCredentials() async throws {
        try keychain.save(makeSession(expiresAt: Date().addingTimeInterval(3_600)), forKey: storedSessionKey)
        let held = holdResponse(path: "/get-session")
        let manager = makeManager()
        let initialization = Task { await manager.initialize() }
        await fulfillment(of: [held.started], timeout: 3)
        await manager.performLogout(exitReason: .userInitiated)
        held.complete(status: 200, body: #"{"user":{"id":"user-123","email":"user@example.com"}}"#)
        await initialization.value

        XCTAssertNil(manager.authSession)
        XCTAssertNil(manager.currentUser)
        XCTAssertEqual(manager.lastExitReason, .userInitiated)
        XCTAssertNil(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self))
    }

    func testExpiredSessionRefreshesAndPersistsRotatedTokens() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(
            accessToken: "expired-access",
            refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(-5)
        )
        stubSessionSuccess()

        let token = await manager.getAccessToken()

        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(manager.authSession?.refreshToken, "new-refresh")
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.lastExitReason, .none)
        let stored = try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self)
        XCTAssertEqual(stored?.accessToken, "new-access")
        XCTAssertEqual(stored?.refreshToken, "new-refresh")
    }

    func testScopedAuthorizationCarriesValidatedSameAccountRefreshGeneration() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        manager.currentUser = LocalUser(
            id: "user-123", email: "user@example.com", name: "Test User",
            avatarUrl: nil, profile: nil, onboardingCompleted: false
        )
        let original = try XCTUnwrap(manager.captureRequestSession())
        stubSessionSuccess()

        let authorization = await manager.getAccessToken(for: original)

        XCTAssertEqual(authorization?.token, "new-access")
        XCTAssertEqual(authorization?.ownership.subject, original.subject)
        XCTAssertNotEqual(authorization?.ownership, original)
        let refreshed = try XCTUnwrap(authorization?.ownership)
        XCTAssertTrue(manager.ownsRequestSession(refreshed))
        XCTAssertFalse(manager.ownsRequestSession(original))
    }

    func testValidatedTokenRotationKeepsHeldHealthImportInSameAccountLifetime() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        manager.currentUser = LocalUser(
            id: "user-123", email: "user@example.com", name: "Synthetic Health",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        let ownership = try XCTUnwrap(manager.captureAccountSession())
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        let store = CoreDataManager(persistentStoreDescriptions: [description])
        let query = HeldWeightImportQuery()
        let health = HealthKitManager(
            userDefaults: defaults, authManager: manager, coreDataManager: store,
            weightImportQuery: { _, _ in await query.fetch() }, bodyFatImportQuery: { _ in [] },
            syncTrigger: {}, importCompletion: { _ in },
            rawImportStore: { _ in XCTFail("Synthetic query cannot dispatch raw samples") }
        )
        health.isAuthorized = true
        let sample = HealthKitWeightImportSample(weight: 70, date: Date())
        let work = Task { try await health.syncWeightFromHealthKitIncremental(days: 30) }
        defer { query.complete([]) }
        await fulfillment(of: [query.started], timeout: 3)
        stubSessionSuccess()
        let token = await manager.getAccessToken()
        XCTAssertEqual(token, "new-access")
        XCTAssertTrue(manager.ownsAccountSession(ownership))
        query.complete([sample])
        try await work.value
        let records = await store.fetchAllBodyMetrics(for: "user-123")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.userId, "user-123")
        XCTAssertEqual(records.first?.weight, 70)
    }

    func testRefreshKeepsExistingRefreshTokenWhenRotationOmitsIt() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(
            accessToken: "expired-access",
            refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(-5)
        )
        stubSessionSuccess(includesRotatedRefreshToken: false)

        let token = await manager.getAccessToken()

        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(manager.authSession?.refreshToken, "old-refresh")
        let stored = try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self)
        XCTAssertEqual(stored?.refreshToken, "old-refresh")
    }

    func testFailedRefreshExpiresSessionAndClearsStoredCredentials() async throws {
        let manager = makeManager()
        let expired = makeSession(expiresAt: Date().addingTimeInterval(-5))
        try keychain.save(expired, forKey: storedSessionKey)
        manager.authSession = expired
        manager.currentUser = LocalUser(
            id: "user-123",
            email: "user@example.com",
            name: "Test User",
            avatarUrl: nil,
            profile: nil
        )
        AuthStubURLProtocol.requestHandler = { _ in
            AuthStubURLProtocol.StubbedResponse(
                statusCode: 400,
                body: Data(#"{"error":"invalid_grant","error_description":"refresh token expired"}"#.utf8)
            )
        }

        let token = await manager.getAccessToken()

        XCTAssertNil(token)
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.authSession)
        XCTAssertNil(manager.currentUser)
        XCTAssertEqual(manager.lastExitReason, .sessionExpired)
        XCTAssertNil(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self))
    }

    func testMalformedTokenResponseExpiresSession() async {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        AuthStubURLProtocol.requestHandler = { _ in
            AuthStubURLProtocol.StubbedResponse(statusCode: 200, body: Data("not-json".utf8))
        }

        let token = await manager.getAccessToken()

        XCTAssertNil(token)
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.authSession)
        XCTAssertEqual(manager.lastExitReason, .sessionExpired)
    }

    func testLogoutClearsStoredSessionAndCachedState() async throws {
        let manager = makeManager()
        try keychain.save(makeSession(expiresAt: Date().addingTimeInterval(3_600)), forKey: storedSessionKey)
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(3_600))
        manager.currentUser = LocalUser(
            id: "user-123",
            email: "user@example.com",
            name: "Test User",
            avatarUrl: nil,
            profile: nil
        )
        manager.needsLegalConsent = true
        manager.memberSinceDate = Date()

        await manager.logout()

        XCTAssertNil(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self))
        XCTAssertNil(manager.authSession)
        XCTAssertNil(manager.currentUser)
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertFalse(manager.needsLegalConsent)
        XCTAssertNil(manager.memberSinceDate)
        XCTAssertEqual(manager.lastExitReason, .userInitiated)
    }

    private func holdResponse(path: String) -> HeldAuthResponse {
        stubSessionSuccess()
        let held = HeldAuthResponse()
        AuthStubURLProtocol.deferredHandler = { request in
            guard request.request.url?.path.hasSuffix(path) == true else { return false }
            held.capture(request)
            return true
        }
        return held
    }

    func testRefreshSuccessAfterLogoutCannotRestoreCredentials() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        let held = holdResponse(path: "/oauth2/userinfo")
        let refresh = Task { await manager.getAccessToken() }
        await fulfillment(of: [held.started], timeout: 3)
        await manager.performLogout(exitReason: .userInitiated)
        held.complete(status: 200, body: #"{"sub":"user-123","email":"user@example.com"}"#)
        let token = await refresh.value
        XCTAssertNil(token)
        XCTAssertNil(manager.authSession)
        XCTAssertNil(manager.currentUser)
        XCTAssertEqual(manager.lastExitReason, .userInitiated)
        XCTAssertNil(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self))
    }

    func testRefreshSuccessAfterAToBToACannotOverwriteReplacementSession() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        let held = holdResponse(path: "/oauth2/userinfo")
        let refresh = Task { await manager.getAccessToken() }
        await fulfillment(of: [held.started], timeout: 3)
        manager.authSession = .localFixture(subject: "user-b", email: "b@example.invalid")
        let replacement = makeSession(accessToken: "replacement-a", expiresAt: Date().addingTimeInterval(3_600))
        manager.authSession = replacement
        try keychain.save(replacement, forKey: storedSessionKey)
        held.complete(status: 200, body: #"{"sub":"user-123","email":"user@example.com"}"#)
        let token = await refresh.value
        XCTAssertNil(token)
        XCTAssertEqual(manager.authSession, replacement)
        XCTAssertEqual(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self), replacement)
    }

    func testRefreshFailureFromADoesNotSignOutB() async throws {
        try await assertLateFailurePreservesB(throughUnauthorized: false)
    }

    func testPendingUnauthorizedRefreshFromADoesNotSignOutB() async throws {
        try await assertLateFailurePreservesB(throughUnauthorized: true)
    }

    private func assertLateFailurePreservesB(throughUnauthorized: Bool) async throws {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        let held = holdResponse(path: "/oauth2/token")
        let refresh = Task { () -> String? in
            if throughUnauthorized {
                await manager.handleProductAPIUnauthorized()
                return nil
            }
            return await manager.getAccessToken()
        }
        await fulfillment(of: [held.started], timeout: 3)
        let replacement = ProductAuthSession.localFixture(
            subject: "user-b", email: "b@example.invalid", accessToken: "replacement-b"
        )
        manager.authSession = replacement
        manager.currentUser = LocalUser(
            id: "user-b", email: "b@example.invalid", name: "User B", avatarUrl: nil, profile: nil
        )
        try keychain.save(replacement, forKey: storedSessionKey)
        held.complete(status: 400, body: #"{"error":"invalid_grant"}"#)
        let token = await refresh.value
        XCTAssertNil(token)
        XCTAssertEqual(manager.authSession, replacement)
        XCTAssertEqual(manager.currentUser?.id, "user-b")
        XCTAssertEqual(manager.lastExitReason, .none)
        XCTAssertEqual(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self), replacement)
    }

    func testLogoutClearsLocallyBeforeTheServerRespondsAndDoesNotClearB() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(3_600))
        let held = holdResponse(path: "/sign-out")
        let logout = Task { await manager.logout() }
        await fulfillment(of: [held.started], timeout: 3)
        XCTAssertEqual(held.request?.value(forHTTPHeaderField: "Authorization"), "Bearer cached-access")
        XCTAssertNil(manager.authSession)
        XCTAssertEqual(manager.lastExitReason, .userInitiated)
        let replacement = ProductAuthSession.localFixture(subject: "user-b", email: "b@example.invalid")
        manager.authSession = replacement
        try keychain.save(replacement, forKey: storedSessionKey)
        held.complete(status: 200, body: "{}")
        await logout.value
        XCTAssertEqual(manager.authSession, replacement)
        XCTAssertEqual(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self), replacement)
    }

    func testReplacementAccountRefreshRemainsSharedWhenOldRefreshFinishes() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        stubSessionSuccess()
        let heldA = HeldAuthResponse()
        let heldB = HeldAuthResponse()
        AuthStubURLProtocol.deferredHandler = { request in
            guard request.request.url?.path.hasSuffix("/oauth2/token") == true else { return false }
            let form = String(data: AuthStubURLProtocol.requestBody(request.request), encoding: .utf8) ?? ""
            (form.contains("refresh_token=b-refresh") ? heldB : heldA).capture(request)
            return true
        }
        let refreshA = Task { await manager.getAccessToken() }
        await fulfillment(of: [heldA.started], timeout: 3)
        manager.authSession = .localFixture(
            subject: "user-b", email: "b@example.invalid", refreshToken: "b-refresh",
            expiresAt: Date().addingTimeInterval(-5)
        )
        let refreshB = Task { await manager.getAccessToken() }
        await fulfillment(of: [heldB.started], timeout: 3)
        heldA.complete(status: 400, body: #"{"error":"invalid_grant"}"#)
        let tokenA = await refreshA.value
        XCTAssertNil(tokenA)

        let joined = expectation(description: "Second B caller joins the refresh")
        let secondB = Task {
            joined.fulfill()
            return await manager.getAccessToken()
        }
        await fulfillment(of: [joined], timeout: 3)
        AuthStubURLProtocol.requestHandler = { request in
            let body = request.url?.path.hasSuffix("/oauth2/userinfo") == true
                ? #"{"sub":"user-b","email":"b@example.invalid"}"# : "{}"
            return .init(statusCode: 200, body: Data(body.utf8))
        }
        heldB.complete(status: 200, body: #"{"access_token":"new-b","refresh_token":"rotated-b","expires_in":3600}"#)
        let tokenB = await refreshB.value
        let secondTokenB = await secondB.value
        XCTAssertEqual(tokenB, "new-b")
        XCTAssertEqual(secondTokenB, "new-b")
        XCTAssertEqual(manager.authSession?.subject, "user-b")
        XCTAssertEqual(AuthStubURLProtocol.recordedRequests.filter {
            $0.url?.path.hasSuffix("/oauth2/token") == true
        }.count, 2)
    }

    func testRefreshRejectsUserInfoForAnotherSubject() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        let held = holdResponse(path: "/oauth2/userinfo")
        let refresh = Task { await manager.getAccessToken() }
        await fulfillment(of: [held.started], timeout: 3)
        held.complete(status: 200, body: #"{"sub":"user-b","email":"b@example.invalid"}"#)
        let token = await refresh.value

        XCTAssertNil(token)
        XCTAssertNil(manager.authSession)
        XCTAssertEqual(manager.lastExitReason, .sessionExpired)
        XCTAssertNil(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self))
    }

    private func applyProfileAccount(
        _ manager: AuthManager, subject: String, name: String, accessToken: String = "jovie-local-access"
    ) {
        let email = "\(subject)@example.invalid"
        manager.authSession = .localFixture(subject: subject, email: email, name: name, accessToken: accessToken)
        manager.currentUser = LocalUser(
            id: subject, email: email, name: name, avatarUrl: nil,
            profile: nil, onboardingCompleted: false
        )
    }

    private func profileBody(subject: String, name: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["profile": [
            "id": subject, "full_name": name, "onboarding_completed": true,
            "legal_accepted_at": "2026-10-06T00:00:00Z"
        ]])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func testProfileBootstrapAfterAccountSwitchCannotOverwriteReplacement() async throws {
        let manager = makeManager()
        let subjectA = "profile-a-\(UUID().uuidString)"
        let subjectB = "profile-b-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subjectA, name: "Account A")
        let held = holdResponse(path: "/api/auth/mobile/profile")
        let bootstrap = Task { await manager.bootstrapAuthenticatedProfileIfNeeded(sessionId: subjectA) }
        await fulfillment(of: [held.started], timeout: 3)
        applyProfileAccount(manager, subject: subjectB, name: "Account B")
        held.complete(status: 200, body: try profileBody(subject: subjectA, name: "Old A"))
        await bootstrap.value

        XCTAssertEqual(manager.currentUser?.id, subjectB)
        XCTAssertEqual(manager.currentUser?.name, "Account B")
        XCTAssertNil(manager.currentUser?.profile)
        XCTAssertEqual(manager.currentUser?.onboardingCompleted, false)
        let staleCache = await CoreDataManager.shared.fetchUserProfileSnapshot(for: subjectA)
        XCTAssertNil(staleCache, "An obsolete response must not persist its profile after the account changes")
    }

    func testProfileBootstrapAfterAccountABACannotOverwriteFreshProfile() async throws {
        let manager = makeManager()
        let subjectA = "profile-a-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subjectA, name: "Original A")
        let held = holdResponse(path: "/api/auth/mobile/profile")
        let bootstrap = Task { await manager.bootstrapAuthenticatedProfileIfNeeded(sessionId: subjectA) }
        await fulfillment(of: [held.started], timeout: 3)
        applyProfileAccount(manager, subject: "profile-b-\(UUID().uuidString)", name: "Account B")
        applyProfileAccount(manager, subject: subjectA, name: "Fresh A")
        let freshProfile = try AuthManager.decodeProductProfileEnvelope(
            from: Data(profileBody(subject: subjectA, name: "Fresh A").utf8)
        ).profile.userProfile
        XCTAssertTrue(manager.applySavedProfileToCurrentUser(freshProfile))
        held.complete(status: 200, body: try profileBody(subject: subjectA, name: "Old A"))
        await bootstrap.value

        XCTAssertEqual(manager.currentUser?.profile?.fullName, "Fresh A")
        XCTAssertEqual(manager.currentUser?.name, "Fresh A")
        let staleCache = await CoreDataManager.shared.fetchUserProfileSnapshot(for: subjectA)
        XCTAssertNil(staleCache, "An obsolete A lifetime must not persist over the fresh A profile")
    }

    func testProfileBootstrapRejectsWrongOwnerResponse() async throws {
        let manager = makeManager()
        let subject = "profile-a-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subject, name: "Account A")
        let body = try profileBody(subject: "profile-b-\(UUID().uuidString)", name: "Wrong owner")
        AuthStubURLProtocol.requestHandler = { _ in .init(statusCode: 200, body: Data(body.utf8)) }

        await manager.bootstrapAuthenticatedProfileIfNeeded(sessionId: subject)

        XCTAssertNil(manager.currentUser?.profile)
        XCTAssertEqual(manager.currentUser?.name, "Account A")
        XCTAssertEqual(manager.currentUser?.onboardingCompleted, false)
    }

    func testNameWriteAfterAccountSwitchCannotRenameReplacement() async throws {
        let manager = makeManager()
        let subjectA = "profile-a-\(UUID().uuidString)"
        let subjectB = "profile-b-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subjectA, name: "Account A")
        let held = holdResponse(path: "/api/auth/mobile/profile")
        let save = Task {
            do {
                try await manager.consolidateNameUpdate("Old A edit")
                return true
            } catch { return false }
        }
        await fulfillment(of: [held.started], timeout: 3)
        applyProfileAccount(manager, subject: subjectB, name: "Account B")
        held.complete(status: 204, body: "")
        let saved = await save.value

        XCTAssertFalse(saved)
        XCTAssertEqual(manager.currentUser?.name, "Account B")
        XCTAssertEqual(manager.currentUser?.id, subjectB)
    }

    func testDeleteResponseAfterAccountSwitchCannotLogOutReplacement() async throws {
        let manager = makeManager()
        applyProfileAccount(manager, subject: "profile-a-\(UUID().uuidString)", name: "Account A")
        let held = holdResponse(path: "/api/auth/mobile/profile")
        let deletion = Task {
            do {
                try await manager.deleteCurrentAccount()
                return true
            } catch { return false }
        }
        await fulfillment(of: [held.started], timeout: 3)
        let subjectB = "profile-b-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subjectB, name: "Account B")
        let replacement = try XCTUnwrap(manager.authSession)
        try keychain.save(replacement, forKey: storedSessionKey)
        held.complete(status: 204, body: "")
        let deleted = await deletion.value

        XCTAssertFalse(deleted)
        XCTAssertEqual(manager.authSession, replacement)
        XCTAssertEqual(manager.currentUser?.id, subjectB)
        XCTAssertEqual(try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self), replacement)
    }

    func testLegalConsentWriteAfterAccountSwitchCannotClearReplacementConsent() async {
        let manager = makeManager()
        let subjectA = "profile-a-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subjectA, name: "Account A")
        let held = holdResponse(path: "/api/auth/mobile/profile")
        let consent = Task { await manager.acceptLegalConsent(userId: subjectA) }
        await fulfillment(of: [held.started], timeout: 3)
        applyProfileAccount(manager, subject: "profile-b-\(UUID().uuidString)", name: "Account B")
        manager.needsLegalConsent = true
        held.complete(status: 204, body: "")
        await consent.value

        XCTAssertTrue(manager.needsLegalConsent)
    }

    func testLegalConsentReadAfterAccountSwitchDoesNotReturnDepartingConsent() async throws {
        let manager = makeManager()
        let subjectA = "profile-a-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subjectA, name: "Account A")
        let held = holdResponse(path: "/api/auth/mobile/profile")
        let consent = Task { await manager.checkLegalConsent(userId: subjectA) }
        await fulfillment(of: [held.started], timeout: 3)
        applyProfileAccount(manager, subject: "profile-b-\(UUID().uuidString)", name: "Account B")
        held.complete(status: 200, body: try profileBody(subject: subjectA, name: "Old A"))
        let accepted = await consent.value

        XCTAssertFalse(accepted)
    }

    func testValidatedTokenRotationKeepsTheBoundBillingLifetime() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        let client = MockRevenueCatPurchasesClient()
        let billing = RevenueCatManager(purchasesClient: client, userDefaults: defaults)
        billing.markAsConfigured()
        manager.bindBillingLifecycle(billing)
        await billing.waitForBillingReconciliation()
        let owner = try XCTUnwrap(billing.captureBillingSession())
        stubSessionSuccess()

        let token = await manager.getAccessToken()
        await billing.waitForBillingReconciliation()

        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(billing.captureBillingSession(), owner)
        XCTAssertEqual(client.identifiedUserIDs, ["user-123"])
    }

    func testProfileWriteStillSucceedsAfterValidTokenRotation() async throws {
        let manager = makeManager()
        applyProfileAccount(manager, subject: "user-123", name: "Test User")
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(-5))
        stubSessionSuccess()
        let oauthHandler = try XCTUnwrap(AuthStubURLProtocol.requestHandler)
        let body = try profileBody(subject: "user-123", name: "Saved name")
        AuthStubURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("/api/auth/mobile/profile") == true {
                return .init(statusCode: 200, body: Data(body.utf8))
            }
            return oauthHandler(request)
        }

        try await manager.consolidateNameUpdate("Saved name")

        XCTAssertEqual(manager.authSession?.accessToken, "new-access")
        XCTAssertEqual(manager.currentUser?.name, "Saved name")
        let patch = try XCTUnwrap(AuthStubURLProtocol.recordedRequests.first { $0.httpMethod == "PATCH" })
        XCTAssertEqual(patch.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
    }

    func testProfileWriteRejectsDecodableWrongOwnerInsteadOfSuccessfulFallback() async throws {
        let manager = makeManager()
        let subject = "profile-a-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subject, name: "Account A")
        let body = try profileBody(subject: "profile-b-\(UUID().uuidString)", name: "Wrong owner")
        AuthStubURLProtocol.requestHandler = { _ in .init(statusCode: 200, body: Data(body.utf8)) }
        do {
            try await manager.updateProfileDurably(["fullName": "Account A edit"])
            XCTFail("A decodable wrong-owner profile must not be acknowledged as the current account save")
        } catch {
            XCTAssertEqual(manager.currentUser?.name, "Account A")
        }
    }

    func testFreshAccountABACanBootstrapWhileOldRequestIsHeld() async throws {
        let manager = makeManager()
        let subject = "profile-a-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subject, name: "Old A", accessToken: "old-a")
        stubSessionSuccess()
        let heldOld = HeldAuthResponse()
        let heldFresh = HeldAuthResponse()
        AuthStubURLProtocol.deferredHandler = { request in
            guard request.request.url?.path.hasSuffix("/api/auth/mobile/profile") == true else { return false }
            let held = request.request.value(forHTTPHeaderField: "Authorization") == "Bearer old-a"
                ? heldOld : heldFresh
            held.capture(request)
            return true
        }
        let old = Task { await manager.bootstrapAuthenticatedProfileIfNeeded(sessionId: subject) }
        await fulfillment(of: [heldOld.started], timeout: 3)
        applyProfileAccount(manager, subject: "profile-b-\(UUID().uuidString)", name: "Account B")
        applyProfileAccount(manager, subject: subject, name: "Fresh A", accessToken: "fresh-a")
        let fresh = Task { await manager.bootstrapAuthenticatedProfileIfNeeded(sessionId: subject) }
        await fulfillment(of: [heldFresh.started], timeout: 3)
        heldFresh.complete(status: 200, body: try profileBody(subject: subject, name: "Fresh A"))
        await fresh.value
        heldOld.complete(status: 200, body: try profileBody(subject: subject, name: "Old A"))
        await old.value

        XCTAssertEqual(manager.currentUser?.profile?.fullName, "Fresh A")
        XCTAssertEqual(manager.currentUser?.name, "Fresh A")
    }

    func testLegalConsentWaiterCannotWriteAfterAccountABA() async throws {
        let manager = makeManager()
        let subject = "profile-a-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subject, name: "Old A")
        let body = try profileBody(subject: subject, name: "Fresh A")
        AuthStubURLProtocol.requestHandler = { _ in .init(statusCode: 200, body: Data(body.utf8)) }
        await manager.legalConsentGate.wait()
        let waiting = expectation(description: "Consent task waits for the gate")
        let consent = Task {
            waiting.fulfill()
            await manager.acceptLegalConsent(userId: subject)
        }
        await fulfillment(of: [waiting], timeout: 3)
        applyProfileAccount(manager, subject: "profile-b-\(UUID().uuidString)", name: "Account B")
        applyProfileAccount(manager, subject: subject, name: "Fresh A")
        manager.needsLegalConsent = true
        await manager.legalConsentGate.signal()
        await consent.value

        XCTAssertTrue(manager.needsLegalConsent)
        XCTAssertTrue(AuthStubURLProtocol.recordedRequests.isEmpty)
    }

    func testCancelledProfileBootstrapCanRetryInTheSameAccountLifetime() async throws {
        let manager = makeManager()
        let subject = "profile-a-\(UUID().uuidString)"
        applyProfileAccount(manager, subject: subject, name: "Account A")
        let held = holdResponse(path: "/api/auth/mobile/profile")
        let bootstrap = Task { await manager.bootstrapAuthenticatedProfileIfNeeded(sessionId: subject) }
        await fulfillment(of: [held.started], timeout: 3)
        bootstrap.cancel()
        held.complete(status: 200, body: try profileBody(subject: subject, name: "Cancelled response"))
        await bootstrap.value
        AuthStubURLProtocol.deferredHandler = nil
        let body = try profileBody(subject: subject, name: "Retried profile")
        AuthStubURLProtocol.requestHandler = { _ in .init(statusCode: 200, body: Data(body.utf8)) }

        await manager.bootstrapAuthenticatedProfileIfNeeded(sessionId: subject)

        XCTAssertEqual(manager.currentUser?.profile?.fullName, "Retried profile")
        XCTAssertEqual(AuthStubURLProtocol.recordedRequests.filter {
            $0.url?.path.hasSuffix("/api/auth/mobile/profile") == true
        }.count, 2)
    }

    func testAnotherAccountSessionClearsPreviousLocalGoals() async throws {
        let manager = makeManager()
        manager.currentUser = localUser(id: "user-a", email: "a@example.invalid")
        storePersonalGoals()
        try keychain.save(
            ProductAuthSession.localFixture(subject: "user-b", email: "b@example.invalid"),
            forKey: storedSessionKey
        )
        stubSessionSuccess()

        await manager.initialize()

        XCTAssertEqual(manager.currentUser?.id, "user-b")
        assertPersonalGoalsCleared()
        assertDeviceMeasurementSystemRemains()
    }

    func testLogoutKeepsGoalsUntilADifferentAccountSignsIn() async throws {
        let manager = makeManager()
        manager.currentUser = localUser(id: "user-a", email: "a@example.invalid")
        storePersonalGoals()

        await manager.performLogout(exitReason: .userInitiated)

        XCTAssertNil(manager.currentUser)
        assertPersonalGoalsIntact()
        try keychain.save(
            ProductAuthSession.localFixture(subject: "user-b", email: "b@example.invalid"),
            forKey: storedSessionKey
        )
        stubSessionSuccess()

        await manager.initialize()

        XCTAssertEqual(manager.currentUser?.id, "user-b")
        assertPersonalGoalsCleared()
        assertDeviceMeasurementSystemRemains()
    }

    func testLogoutThenSameAccountKeepsLocalGoals() async throws {
        let manager = makeManager()
        manager.currentUser = localUser(id: "user-a", email: "a@example.invalid")
        storePersonalGoals()
        await manager.performLogout(exitReason: .userInitiated)
        try keychain.save(
            ProductAuthSession.localFixture(subject: "user-a", email: "a@example.invalid"),
            forKey: storedSessionKey
        )
        stubSessionSuccess()

        await manager.initialize()

        XCTAssertEqual(manager.currentUser?.id, "user-a")
        assertPersonalGoalsIntact()
        assertDeviceMeasurementSystemRemains()
    }

    func testColdStartKeepsLocalGoalsForTheRestoredAccount() async throws {
        let manager = makeManager()
        storePersonalGoals()
        try keychain.save(
            ProductAuthSession.localFixture(subject: "user-a", email: "a@example.invalid"),
            forKey: storedSessionKey
        )
        stubSessionSuccess()

        await manager.initialize()

        XCTAssertEqual(manager.currentUser?.id, "user-a")
        assertPersonalGoalsIntact()
        assertDeviceMeasurementSystemRemains()
    }

    func testRejectedStoredSessionKeepsGoalsWithThatAccount() async throws {
        let manager = makeManager()
        storePersonalGoals()
        try keychain.save(
            ProductAuthSession.localFixture(subject: "user-a", email: "a@example.invalid"),
            forKey: storedSessionKey
        )
        AuthStubURLProtocol.requestHandler = { _ in
            AuthStubURLProtocol.StubbedResponse(statusCode: 401, body: Data("{}".utf8))
        }

        await manager.initialize()

        XCTAssertNil(manager.currentUser)
        XCTAssertEqual(defaults.string(forKey: AccountLocalGoalFence.ownerKey), "user-a")
        assertPersonalGoalsIntact()
        try keychain.save(
            ProductAuthSession.localFixture(subject: "user-a", email: "a@example.invalid"),
            forKey: storedSessionKey
        )
        stubSessionSuccess()

        await manager.retryAuthProviderInitialization()

        XCTAssertEqual(manager.currentUser?.id, "user-a")
        assertPersonalGoalsIntact()
        assertDeviceMeasurementSystemRemains()
    }

    func testFailedColdRefreshKeepsGoalsUntilADifferentAccountSignsIn() async throws {
        let manager = makeManager()
        storePersonalGoals()
        try keychain.save(
            ProductAuthSession.localFixture(
                subject: "user-a",
                email: "a@example.invalid",
                expiresAt: Date().addingTimeInterval(-5)
            ),
            forKey: storedSessionKey
        )
        AuthStubURLProtocol.requestHandler = { _ in
            AuthStubURLProtocol.StubbedResponse(
                statusCode: 400,
                body: Data(#"{"error":"invalid_grant"}"#.utf8)
            )
        }

        await manager.initialize()

        XCTAssertNil(manager.currentUser)
        XCTAssertEqual(defaults.string(forKey: AccountLocalGoalFence.ownerKey), "user-a")
        assertPersonalGoalsIntact()
        try keychain.save(
            ProductAuthSession.localFixture(subject: "user-b", email: "b@example.invalid"),
            forKey: storedSessionKey
        )
        stubSessionSuccess()

        await manager.retryAuthProviderInitialization()

        XCTAssertEqual(manager.currentUser?.id, "user-b")
        assertPersonalGoalsCleared()
        assertDeviceMeasurementSystemRemains()
    }

    private func localUser(id: String, email: String) -> LocalUser {
        LocalUser(
            id: id,
            email: email,
            name: "Test User",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
    }

    private func storePersonalGoals() {
        defaults.set(70.0, forKey: Constants.goalWeightKilogramsKey)
        defaults.set(154.0, forKey: Constants.goalWeightKey)
        defaults.set(18.0, forKey: Constants.goalBodyFatPercentageKey)
        defaults.set(22.0, forKey: Constants.goalFFMIKey)
        defaults.set(8_000, forKey: "stepGoal")
        defaults.set(
            MeasurementSystem.imperial.rawValue,
            forKey: Constants.preferredMeasurementSystemKey
        )
    }

    private func assertPersonalGoalsIntact() {
        XCTAssertEqual(defaults.double(forKey: Constants.goalWeightKilogramsKey), 70, accuracy: 0.001)
        XCTAssertEqual(defaults.double(forKey: Constants.goalWeightKey), 154, accuracy: 0.001)
        XCTAssertEqual(defaults.double(forKey: Constants.goalBodyFatPercentageKey), 18, accuracy: 0.001)
        XCTAssertEqual(defaults.double(forKey: Constants.goalFFMIKey), 22, accuracy: 0.001)
        XCTAssertEqual(defaults.integer(forKey: "stepGoal"), 8_000)
    }

    private func assertPersonalGoalsCleared() {
        XCTAssertNil(defaults.object(forKey: Constants.goalWeightKilogramsKey))
        XCTAssertNil(defaults.object(forKey: Constants.goalWeightKey))
        XCTAssertNil(defaults.object(forKey: Constants.goalBodyFatPercentageKey))
        XCTAssertNil(defaults.object(forKey: Constants.goalFFMIKey))
        XCTAssertNil(defaults.object(forKey: "stepGoal"))
    }

    private func assertDeviceMeasurementSystemRemains() {
        XCTAssertEqual(
            defaults.string(forKey: Constants.preferredMeasurementSystemKey),
            MeasurementSystem.imperial.rawValue
        )
    }
}
