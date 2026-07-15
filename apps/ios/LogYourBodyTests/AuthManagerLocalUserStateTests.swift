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

    func testLogoutSetsExitReasonUserInitiated() async {
        let manager = AuthManager()
        manager.isAuthenticated = true

        await manager.logout()

        XCTAssertEqual(manager.lastExitReason, .userInitiated)
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testHandleSupabaseUnauthorizedExpiresSessionWithoutRefreshToken() async {
        let manager = AuthManager()
        manager.isAuthenticated = true
        manager.currentUser = LocalUser(
            id: "test-user",
            email: "test@example.com",
            name: nil,
            avatarUrl: nil,
            profile: nil
        )

        await manager.handleSupabaseUnauthorized()

        XCTAssertEqual(manager.lastExitReason, .sessionExpired)
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
    }

    func testSupabaseAuthUserUsesProviderProfileName() throws {
        let payload = Data(#"""
        {
          "id": "product-user",
          "email": "phone@identity.jov.ie",
          "created_at": "2026-07-14T12:00:00Z",
          "user_metadata": { "full_name": "Test User" }
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let user = try decoder.decode(SupabaseAuthUser.self, from: payload)

        XCTAssertEqual(user.id, "product-user")
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

    func testSyntheticAuthEmailSanitizesIdentitySubject() {
        XCTAssertEqual(
            AuthManager.syntheticAuthEmail(userId: " user:abc/123 "),
            "user-abc-123@identity.logyourbody"
        )
    }
}
