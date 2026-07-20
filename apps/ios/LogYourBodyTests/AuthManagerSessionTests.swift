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
    static var recordedRequests: [URLRequest] = []

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler,
              let url = request.url,
              let client else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        Self.recordedRequests.append(request)
        let stub = handler(request)
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
        recordedRequests = []
    }
}

@MainActor
final class AuthManagerSessionTests: XCTestCase {
    private let keychain = KeychainManager.shared
    private let storedSessionKey = "productAuth.jovieOAuthSession"
    private var suiteName: String = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AuthManagerSessionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        AuthStubURLProtocol.reset()
        try? keychain.delete(forKey: storedSessionKey)
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        try? keychain.delete(forKey: storedSessionKey)
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeManager() -> AuthManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubURLProtocol.self]
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

    private func stubRefreshSuccess(tokenBody: String) {
        AuthStubURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.contains("oauth2/token") {
                return AuthStubURLProtocol.StubbedResponse(statusCode: 200, body: Data(tokenBody.utf8))
            }
            if path.contains("oauth2/userinfo") {
                let body = #"{"sub":"user-123","email":"user@example.com","name":"Test User"}"#
                return AuthStubURLProtocol.StubbedResponse(statusCode: 200, body: Data(body.utf8))
            }
            // Profile bootstrap and any other call: fail closed, tests don't depend on it.
            return AuthStubURLProtocol.StubbedResponse(statusCode: 404, body: Data("{}".utf8))
        }
    }

    func testGetAccessTokenReturnsCachedTokenWithoutNetworkWhenSessionUnexpired() async {
        let manager = makeManager()
        manager.authSession = makeSession(expiresAt: Date().addingTimeInterval(3_600))

        let token = await manager.getAccessToken()

        XCTAssertEqual(token, "cached-access")
        XCTAssertTrue(AuthStubURLProtocol.recordedRequests.isEmpty)
    }

    func testExpiredSessionRefreshesAndPersistsRotatedTokens() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(
            accessToken: "expired-access",
            refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(-5)
        )
        stubRefreshSuccess(
            tokenBody: #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#
        )

        let token = await manager.getAccessToken()

        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(manager.authSession?.refreshToken, "new-refresh")
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.lastExitReason, .none)
        let stored = try keychain.get(forKey: storedSessionKey, as: ProductAuthSession.self)
        XCTAssertEqual(stored?.accessToken, "new-access")
        XCTAssertEqual(stored?.refreshToken, "new-refresh")
    }

    func testRefreshKeepsExistingRefreshTokenWhenRotationOmitsIt() async throws {
        let manager = makeManager()
        manager.authSession = makeSession(
            accessToken: "expired-access",
            refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(-5)
        )
        stubRefreshSuccess(tokenBody: #"{"access_token":"new-access","expires_in":3600}"#)

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
        manager.isAuthenticated = true
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
        manager.isAuthenticated = true
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
        manager.isAuthenticated = true
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
}
