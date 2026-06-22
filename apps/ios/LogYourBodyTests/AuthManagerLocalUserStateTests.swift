//
// AuthManagerLocalUserStateTests.swift
// LogYourBodyTests
//
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

    func testHandleSupabaseUnauthorizedSetsSessionExpired() async {
        let manager = AuthManager()
        manager.isAuthenticated = true
        manager.lastExitReason = .none
        manager.currentUser = LocalUser(
            id: "test-user",
            email: "test@example.com",
            name: "Test User",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )

        await manager.handleSupabaseUnauthorized()

        XCTAssertEqual(manager.lastExitReason, .sessionExpired)
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
    }

    func testUpdateLocalUserResetsExitReasonToNoneOnSignIn() {
        let manager = AuthManager()
        manager.lastExitReason = .sessionExpired

        struct FakeEmailAddress {
            let emailAddress: String
        }

        struct FakeClerkUser {
            let id: String
            let emailAddresses: [FakeEmailAddress]
            let firstName: String?
            let lastName: String?
            let username: String?
            let imageUrl: String?
        }

        let fakeUser = FakeClerkUser(
            id: "user_123",
            emailAddresses: [FakeEmailAddress(emailAddress: "test@example.com")],
            firstName: "Test",
            lastName: "User",
            username: "testuser",
            imageUrl: nil
        )

        manager.updateLocalUser(clerkUser: fakeUser)

        XCTAssertEqual(manager.lastExitReason, .none)
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.currentUser?.email, "test@example.com")
    }

    func testUpdateLocalUserUsesExternalAccountEmailWhenPrimaryEmailsMissing() {
        let manager = AuthManager()

        struct FakeExternalAccount {
            let provider: String
            let emailAddress: String
        }

        struct FakeClerkUser {
            let id: String
            let emailAddresses: [String]
            let externalAccounts: [FakeExternalAccount]
            let firstName: String?
            let lastName: String?
            let username: String?
            let imageUrl: String?
        }

        let fakeUser = FakeClerkUser(
            id: "user_apple_123",
            emailAddresses: [],
            externalAccounts: [
                FakeExternalAccount(
                    provider: "oauth_apple",
                    emailAddress: "private@example.com"
                )
            ],
            firstName: "Apple",
            lastName: "User",
            username: nil,
            imageUrl: nil
        )

        manager.updateLocalUser(clerkUser: fakeUser)

        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.currentUser?.email, "private@example.com")
    }

    func testUpdateLocalUserSynthesizesEmailWhenClerkEmailMissing() {
        let manager = AuthManager()

        struct FakeClerkUser {
            let id: String
            let emailAddresses: [String]
            let externalAccounts: [String]
            let firstName: String?
            let lastName: String?
            let username: String?
            let imageUrl: String?
        }

        let fakeUser = FakeClerkUser(
            id: "user_apple_123",
            emailAddresses: [],
            externalAccounts: [],
            firstName: nil,
            lastName: nil,
            username: nil,
            imageUrl: nil
        )

        manager.updateLocalUser(clerkUser: fakeUser)

        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.currentUser?.email, "user_apple_123@apple.local.logyourbody")
    }

    func testApplySavedProfileUpdatesPublishedCurrentUser() {
        let manager = AuthManager()
        manager.currentUser = LocalUser(
            id: "profile-user",
            email: "profile@example.com",
            name: "Old Name",
            avatarUrl: nil,
            profile: UserProfile(
                id: "profile-user",
                email: "profile@example.com",
                username: nil,
                fullName: "Old Name",
                dateOfBirth: nil,
                height: nil,
                heightUnit: "cm",
                gender: nil,
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: nil,
                onboardingCompleted: false
            ),
            onboardingCompleted: false
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

        let didApply = manager.applySavedProfileToCurrentUser(savedProfile)

        XCTAssertTrue(didApply)
        XCTAssertEqual(manager.currentUser?.name, "Updated Name")
        XCTAssertEqual(manager.currentUser?.profile?.height, 180)
        XCTAssertEqual(manager.currentUser?.profile?.gender, "male")
        XCTAssertEqual(manager.currentUser?.onboardingCompleted, true)
    }

    func testApplySavedProfileRejectsDifferentUserProfile() {
        let manager = AuthManager()
        manager.currentUser = LocalUser(
            id: "current-user",
            email: "current@example.com",
            name: "Current User",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )

        let didApply = manager.applySavedProfileToCurrentUser(
            UserProfile(
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
        )

        XCTAssertFalse(didApply)
        XCTAssertEqual(manager.currentUser?.id, "current-user")
        XCTAssertNil(manager.currentUser?.profile)
        XCTAssertFalse(manager.currentUser?.onboardingCompleted ?? true)
    }

    func testSyntheticAuthEmailSanitizesClerkUserId() {
        XCTAssertEqual(
            AuthManager.syntheticAuthEmail(userId: " user:abc/123 "),
            "user-abc-123@apple.local.logyourbody"
        )
    }

    func testNormalizedAuthEmailRejectsNonEmailIdentifier() {
        XCTAssertNil(AuthManager.normalizedAuthEmailCandidate("user_apple_123"))
        XCTAssertEqual(
            AuthManager.normalizedAuthEmailCandidate(" private@example.com "),
            "private@example.com"
        )
    }
}
