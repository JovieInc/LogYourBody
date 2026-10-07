//
// AuthManagerSessionTests.swift
// LogYourBodyTests
//
import XCTest
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
}
