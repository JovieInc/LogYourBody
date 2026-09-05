import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody

@MainActor
final class AuthManagerLocalUserStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OnboardingStateManager.shared.updateCompletionStatus(false)
    }

    override func tearDown() {
        OnboardingStateManager.shared.updateCompletionStatus(false)
        super.tearDown()
    }

    func testIsAuthenticatedRequiresJovieAccessToken() {
        let manager = AuthManager()
        XCTAssertFalse(manager.isAuthenticated)

        manager.authSession = .localFixture(subject: "user-1", email: "user@example.com")
        XCTAssertTrue(manager.isAuthenticated)

        manager.authSession = .localFixture(
            subject: "user-1",
            email: "user@example.com",
            accessToken: "   "
        )
        XCTAssertFalse(manager.isAuthenticated)

        manager.authSession = nil
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testLogoutSetsExitReasonUserInitiated() async {
        let manager = AuthManager()
        manager.authSession = .localFixture(subject: "test-user", email: "test@example.com")

        await manager.logout()

        XCTAssertEqual(manager.lastExitReason, .userInitiated)
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testHandleProductAPIUnauthorizedExpiresSessionWithoutRefreshToken() async {
        let manager = AuthManager()
        manager.authSession = .localFixture(subject: "test-user", email: "test@example.com")
        manager.currentUser = LocalUser(
            id: "test-user",
            email: "test@example.com",
            name: nil,
            avatarUrl: nil,
            profile: nil
        )

        await manager.handleProductAPIUnauthorized()

        XCTAssertEqual(manager.lastExitReason, .sessionExpired)
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
    }

    func testOAuthUserInfoUsesProviderProfileName() throws {
        let payload = Data(#"""
        {
          "sub": "product-user",
          "email": "phone@identity.jov.ie",
          "name": "Test User",
          "phone_number": "+15555550123"
        }
        """#.utf8)
        let user = try JSONDecoder().decode(OAuthUserInfo.self, from: payload)

        XCTAssertEqual(user.subject, "product-user")
        XCTAssertEqual(user.email, "phone@identity.jov.ie")
        XCTAssertEqual(user.name, "Test User")
    }

    func testApplySavedProfileUpdatesPublishedCurrentUser() {
        let manager = AuthManager()
        manager.currentUser = LocalUser(
            id: "profile-user",
            email: "profile@example.com",
            name: "Old Name",
            avatarUrl: nil,
            profile: nil
        )
        let savedProfile = UserProfile(
            id: "profile-user",
            email: "profile@example.com",
            username: nil,
            fullName: "Updated Name",
            dateOfBirth: Date(timeIntervalSince1970: 631_152_000),
            height: 180,
            heightUnit: "cm",
            gender: "male",
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: true
        )

        XCTAssertTrue(manager.applySavedProfileToCurrentUser(savedProfile))
        XCTAssertEqual(manager.currentUser?.name, "Updated Name")
        XCTAssertEqual(manager.currentUser?.profile?.height, 180)
        XCTAssertTrue(manager.currentUser?.onboardingCompleted ?? false)
    }

    func testApplySavedProfileRejectsDifferentUserProfile() {
        let manager = AuthManager()
        manager.currentUser = LocalUser(
            id: "current-user",
            email: "current@example.com",
            name: nil,
            avatarUrl: nil,
            profile: nil
        )
        let other = UserProfile(
            id: "other-user",
            email: "other@example.com",
            username: nil,
            fullName: "Other User",
            dateOfBirth: nil,
            height: 180,
            heightUnit: "cm",
            gender: "male",
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: true
        )

        XCTAssertFalse(manager.applySavedProfileToCurrentUser(other))
        XCTAssertEqual(manager.currentUser?.id, "current-user")
    }

    func testRefreshKeepsCompletedProfileForSameSubject() async throws {
        try XCTSkipUnless(
            KeychainAvailability.isAvailable(),
            "Keychain unavailable on unsigned CI test host"
        )
        ProfileRefreshStubURLProtocol.install { request in
            let path = request.url?.path ?? ""
            if path.contains("oauth2/token") {
                return ProfileRefreshStubURLProtocol.Stub(
                    statusCode: 200,
                    body: Data(#"{"access_token":"rotated-access","refresh_token":"rotated-refresh","expires_in":3600}"#.utf8)
                )
            }
            if path.contains("oauth2/userinfo") {
                return ProfileRefreshStubURLProtocol.Stub(
                    statusCode: 200,
                    body: Data(#"{"sub":"profile-user","email":"profile@example.com","name":"Updated Name"}"#.utf8)
                )
            }
            return ProfileRefreshStubURLProtocol.Stub(statusCode: 404, body: Data("{}".utf8))
        }
        defer { ProfileRefreshStubURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileRefreshStubURLProtocol.self]
        let manager = AuthManager(urlSession: URLSession(configuration: configuration))
        manager.currentUser = LocalUser(
            id: "profile-user",
            email: "profile@example.com",
            name: "Updated Name",
            avatarUrl: nil,
            profile: UserProfile(
                id: "profile-user",
                email: "profile@example.com",
                username: nil,
                fullName: "Updated Name",
                dateOfBirth: Date(timeIntervalSince1970: 631_152_000),
                height: 180,
                heightUnit: "cm",
                gender: "male",
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: nil,
                onboardingCompleted: true
            ),
            onboardingCompleted: true
        )
        manager.authSession = ProductAuthSession(
            accessToken: "expired-access",
            refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(-120),
            subject: "profile-user",
            email: "profile@example.com",
            name: "Updated Name",
            issuedAt: Date().addingTimeInterval(-3_600)
        )

        let token = await manager.getAccessToken()

        XCTAssertEqual(token, "rotated-access")
        XCTAssertTrue(ProfileCompletionPolicy.isComplete(user: manager.currentUser))
        XCTAssertEqual(manager.currentUser?.profile?.height, 180)
        XCTAssertEqual(manager.currentUser?.profile?.gender, "male")
        XCTAssertTrue(manager.currentUser?.onboardingCompleted ?? false)
    }

    func testSyntheticAuthEmailSanitizesIdentitySubject() {
        XCTAssertEqual(
            AuthManager.syntheticAuthEmail(userId: " user:abc/123 "),
            "user-abc-123@identity.logyourbody"
        )
    }
}

private final class ProfileRefreshStubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let body: Data
    }

    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> Stub)?

    static func install(handler: @escaping (URLRequest) -> Stub) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stub = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) ?? HTTPURLResponse()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
