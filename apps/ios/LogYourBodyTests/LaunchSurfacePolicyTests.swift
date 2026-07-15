//
// LaunchAndBodyCompositionTests.swift
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


final class LaunchSurfacePolicyTests: XCTestCase {
    func testIncompleteOnboardingRequiresBodyCompositionOnboarding() {
        XCTAssertTrue(
            LaunchSurfacePolicy.requiresBodyCompositionOnboarding(
                hasCompletedOnboarding: false
            )
        )
        XCTAssertFalse(
            LaunchSurfacePolicy.requiresBodyCompositionOnboarding(
                hasCompletedOnboarding: true
            )
        )
    }

    func testIncompleteProfileRequiresProfileCompletion() {
        XCTAssertTrue(
            LaunchSurfacePolicy.requiresCompleteProfile(
                isProfileComplete: false
            )
        )
        XCTAssertFalse(
            LaunchSurfacePolicy.requiresCompleteProfile(
                isProfileComplete: true
            )
        )
    }

    func testEntryDeepLinkPolicyRequiresFullLaunchGateChain() {
        let user = makeLaunchPolicyUser(id: "eligible-user")

        XCTAssertFalse(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: false,
                user: user,
                hasCompletedOnboarding: true,
                isSubscribed: true
            )
        )
        XCTAssertFalse(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true,
                user: nil,
                hasCompletedOnboarding: true,
                isSubscribed: true
            )
        )
        XCTAssertFalse(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true,
                user: user,
                hasCompletedOnboarding: false,
                isSubscribed: true
            )
        )
        XCTAssertFalse(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true,
                user: makeLaunchPolicyUser(id: "incomplete-user", height: 0),
                hasCompletedOnboarding: true,
                isSubscribed: true
            )
        )
        XCTAssertFalse(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true,
                user: user,
                hasCompletedOnboarding: true,
                isSubscribed: false
            )
        )
        XCTAssertTrue(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true,
                user: user,
                hasCompletedOnboarding: true,
                isSubscribed: true
            )
        )
    }

    func testEntryDeepLinkParserSupportsCustomSchemeTabs() throws {
        XCTAssertEqual(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "logyourbody://log/weight"))),
            .entry(tab: 0)
        )
        XCTAssertEqual(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "logyourbody://log/bodyfat"))),
            .entry(tab: 1)
        )
        XCTAssertEqual(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "logyourbody://log/photo"))),
            .entry(tab: 2)
        )
    }

    func testEntryDeepLinkParserSupportsUniversalLinks() throws {
        XCTAssertEqual(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "https://logyourbody.com/log/weight"))),
            .entry(tab: 0)
        )
        XCTAssertEqual(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "https://www.logyourbody.com/log/bodyfat"))),
            .entry(tab: 1)
        )
        XCTAssertEqual(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "https://www.logyourbody.com/log/photo"))),
            .entry(tab: 2)
        )
    }

    func testEntryDeepLinkParserDefaultsGenericLogLinksToWeightTab() throws {
        XCTAssertEqual(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "logyourbody://log"))),
            .entry(tab: 0)
        )
        XCTAssertEqual(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "https://www.logyourbody.com/log"))),
            .entry(tab: 0)
        )
        XCTAssertEqual(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "https://www.logyourbody.com/log/unknown"))),
            .entry(tab: 0)
        )
    }

    func testEntryDeepLinkParserIgnoresUnsupportedUrlsAndKeepsOAuthCallbacksSeparate() throws {
        var insecureUniversalLink = URLComponents()
        insecureUniversalLink.scheme = "http"
        insecureUniversalLink.host = "logyourbody.com"
        insecureUniversalLink.path = "/log/weight"

        XCTAssertNil(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "https://example.com/log/weight")))
        )
        XCTAssertNil(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(insecureUniversalLink.url))
        )
        XCTAssertNil(
            LogYourBodyDeepLink.destination(for: try XCTUnwrap(URL(string: "logyourbody://settings")))
        )

        let oauthURL = try XCTUnwrap(URL(string: "logyourbody://oauth-callback"))
        XCTAssertTrue(LogYourBodyDeepLink.isOAuthCallback(oauthURL))
        XCTAssertNil(LogYourBodyDeepLink.destination(for: oauthURL))
    }

    func testEntryDeepLinkRoutingStoresDuringStartupAndReplaysWhenEligible() {
        let destination = LogYourBodyDeepLink.Destination.entry(tab: 2)
        let receivedAt = Date()
        let pending = EntryDeepLinkRoutingPolicy.PendingDestination(
            destination: destination,
            userId: nil,
            receivedAt: receivedAt
        )

        XCTAssertEqual(
            EntryDeepLinkRoutingPolicy.action(
                for: destination,
                canOpenNow: false,
                canStoreForLater: true
            ),
            .store(destination)
        )
        XCTAssertEqual(
            EntryDeepLinkRoutingPolicy.actionForStoredDestination(
                pending,
                currentUserId: "restored-user",
                canOpenNow: true,
                canStoreForLater: true,
                now: receivedAt.addingTimeInterval(1)
            ),
            .open(destination)
        )
    }

    func testEntryDeepLinkRoutingDropsKnownSignedOutUsers() {
        let destination = LogYourBodyDeepLink.Destination.entry(tab: 0)
        let receivedAt = Date()
        let pending = EntryDeepLinkRoutingPolicy.PendingDestination(
            destination: destination,
            userId: nil,
            receivedAt: receivedAt
        )

        XCTAssertFalse(
            EntryDeepLinkRoutingPolicy.canStoreForLater(
                isAuthProviderLoaded: true,
                isAuthenticated: false
            )
        )
        XCTAssertEqual(
            EntryDeepLinkRoutingPolicy.action(
                for: destination,
                canOpenNow: false,
                canStoreForLater: false
            ),
            .ignore
        )
        XCTAssertEqual(
            EntryDeepLinkRoutingPolicy.actionForStoredDestination(
                pending,
                currentUserId: nil,
                canOpenNow: false,
                canStoreForLater: false,
                now: receivedAt.addingTimeInterval(1)
            ),
            .ignore
        )
    }

    func testEntryDeepLinkRoutingKeepsAuthenticatedDeferredLinksUntilDownstreamGatesOpen() {
        let destination = LogYourBodyDeepLink.Destination.entry(tab: 1)
        let receivedAt = Date()
        let pending = EntryDeepLinkRoutingPolicy.PendingDestination(
            destination: destination,
            userId: "user-a",
            receivedAt: receivedAt
        )

        XCTAssertTrue(
            EntryDeepLinkRoutingPolicy.canStoreForLater(
                isAuthProviderLoaded: true,
                isAuthenticated: true
            )
        )
        XCTAssertEqual(
            EntryDeepLinkRoutingPolicy.actionForStoredDestination(
                pending,
                currentUserId: "user-a",
                canOpenNow: false,
                canStoreForLater: true,
                now: receivedAt.addingTimeInterval(1)
            ),
            .keepPending
        )
    }

    func testEntryDeepLinkRoutingExpiresStalePendingLinks() {
        let receivedAt = Date()
        let pending = EntryDeepLinkRoutingPolicy.PendingDestination(
            destination: .entry(tab: 2),
            userId: "user-a",
            receivedAt: receivedAt
        )

        XCTAssertEqual(
            EntryDeepLinkRoutingPolicy.actionForStoredDestination(
                pending,
                currentUserId: "user-a",
                canOpenNow: true,
                canStoreForLater: true,
                now: receivedAt.addingTimeInterval(EntryDeepLinkRoutingPolicy.pendingLinkTTL + 1)
            ),
            .ignore
        )
    }

    func testEntryDeepLinkRoutingClearsPendingLinksAcrossAccountSwitch() {
        let receivedAt = Date()
        let pending = EntryDeepLinkRoutingPolicy.PendingDestination(
            destination: .entry(tab: 1),
            userId: "user-a",
            receivedAt: receivedAt
        )

        XCTAssertEqual(
            EntryDeepLinkRoutingPolicy.actionForStoredDestination(
                pending,
                currentUserId: "user-b",
                canOpenNow: true,
                canStoreForLater: true,
                now: receivedAt.addingTimeInterval(1)
            ),
            .ignore
        )
    }

    @MainActor
    func testEntryDeepLinkPolicyBlocksAccountSwitchWithPreviousOnboardingCompletion() {
        let suiteName = "entry-deeplink-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 1)
        manager.markCompleted(userId: "previous-user")

        let newUser = makeLaunchPolicyUser(id: "new-user")

        XCTAssertFalse(manager.hasCompletedCurrentVersion(for: newUser.id))
        XCTAssertFalse(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true,
                user: newUser,
                hasCompletedOnboarding: manager.hasCompletedCurrentVersion(for: newUser.id),
                isSubscribed: true
            )
        )
    }

    func testProfileCompletionPolicyRequiresRealNameHeightGenderAndDateOfBirth() {
        let dateOfBirth = Date(timeIntervalSince1970: 631_152_000)
        let completeProfile = UserProfile(
            id: "profile-complete",
            email: "complete@example.com",
            username: nil,
            fullName: "Complete User",
            dateOfBirth: dateOfBirth,
            height: 180,
            heightUnit: "cm",
            gender: "male",
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: true
        )
        let blankNameProfile = UserProfile(
            id: "profile-blank-name",
            email: "blank@example.com",
            username: nil,
            fullName: "   ",
            dateOfBirth: dateOfBirth,
            height: 180,
            heightUnit: "cm",
            gender: "male",
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: true
        )
        let zeroHeightProfile = UserProfile(
            id: "profile-zero-height",
            email: "height@example.com",
            username: nil,
            fullName: "Height User",
            dateOfBirth: dateOfBirth,
            height: 0,
            heightUnit: "cm",
            gender: "male",
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: true
        )

        XCTAssertTrue(ProfileCompletionPolicy.isComplete(profile: completeProfile, fallbackName: nil))
        XCTAssertFalse(ProfileCompletionPolicy.isComplete(profile: blankNameProfile, fallbackName: nil))
        XCTAssertFalse(ProfileCompletionPolicy.isComplete(profile: zeroHeightProfile, fallbackName: nil))
        XCTAssertTrue(ProfileCompletionPolicy.isComplete(profile: blankNameProfile, fallbackName: "Fallback User"))
    }

    private func makeLaunchPolicyUser(
        id: String,
        name: String = "Launch User",
        height: Double = 180
    ) -> User {
        User(
            id: id,
            email: "\(id)@example.com",
            name: name,
            avatarUrl: nil,
            profile: UserProfile(
                id: "profile-\(id)",
                email: "\(id)@example.com",
                username: nil,
                fullName: name,
                dateOfBirth: Date(timeIntervalSince1970: 631_152_000),
                height: height,
                heightUnit: "cm",
                gender: "male",
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: nil,
                onboardingCompleted: true
            ),
            onboardingCompleted: true
        )
    }
}
