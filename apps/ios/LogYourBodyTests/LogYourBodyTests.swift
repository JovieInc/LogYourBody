//
// LogYourBodyTests.swift
// LogYourBody
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody

// swiftlint:disable single_test_class

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

final class AuthProfileBootstrapPolicyTests: XCTestCase {
    func testIdentityOnlyProfileIsNotPersistedDuringSessionProjection() {
        let profile = UserProfile(
            id: "identity-only",
            email: "identity@example.com",
            username: nil,
            fullName: "Identity User",
            dateOfBirth: nil,
            height: nil,
            heightUnit: "cm",
            gender: nil,
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: "kg",
            onboardingCompleted: nil
        )

        XCTAssertFalse(profile.hasAppOwnedProfileData)
        XCTAssertFalse(AuthProfileBootstrapPolicy.shouldPersistProjectedProfile(profile))
    }

    func testCompletedOnboardingProfileCanBePersistedAfterExplicitUserInput() {
        let profile = UserProfile(
            id: "completed-profile",
            email: "complete@example.com",
            username: nil,
            fullName: "Complete User",
            dateOfBirth: nil,
            height: nil,
            heightUnit: "cm",
            gender: nil,
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: "kg",
            onboardingCompleted: true
        )

        XCTAssertTrue(profile.hasAppOwnedProfileData)
        XCTAssertTrue(AuthProfileBootstrapPolicy.shouldPersistProjectedProfile(profile))
    }

    func testProfileDetailsCountAsAppOwnedProfileData() {
        let dateOfBirth = Date(timeIntervalSince1970: 631_152_000)
        let profile = UserProfile(
            id: "details-profile",
            email: "details@example.com",
            username: nil,
            fullName: "Details User",
            dateOfBirth: dateOfBirth,
            height: 180,
            heightUnit: "cm",
            gender: "male",
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: nil
        )

        XCTAssertTrue(profile.hasAppOwnedProfileData)
        XCTAssertTrue(AuthProfileBootstrapPolicy.shouldPersistProjectedProfile(profile))
    }
}

final class SupabaseProfilePayloadTests: XCTestCase {
    func testProfilePayloadNormalizesLaunchGateColumns() throws {
        let birthDate = Date(timeIntervalSince1970: 631_152_000)
        let payload: [String: Any] = [
            "id": "profile-user",
            "email": "profile@example.com",
            "fullName": "Profile User",
            "dateOfBirth": birthDate,
            "heightUnit": "cm",
            "onboardingCompleted": true,
            "avatarUrl": Optional<String>.none as Any,
            "activity_level": "active"
        ]

        let sanitized = try SupabaseManager.sanitizedProfilePayload(payload)

        XCTAssertEqual(sanitized["id"] as? String, "profile-user")
        XCTAssertEqual(sanitized["full_name"] as? String, "Profile User")
        XCTAssertEqual(sanitized["date_of_birth"] as? String, ISO8601DateFormatter().string(from: birthDate))
        XCTAssertEqual(sanitized["height_unit"] as? String, "cm")
        XCTAssertEqual(sanitized["onboarding_completed"] as? Bool, true)
        XCTAssertEqual(sanitized["activity_level"] as? String, "active")
        XCTAssertNil(sanitized["avatar_url"])
        XCTAssertNil(sanitized["fullName"])
        XCTAssertNil(sanitized["dateOfBirth"])
        XCTAssertNil(sanitized["onboardingCompleted"])
    }
}

final class BodyCompositionMathGoldenTests: XCTestCase {
    private let calendar = Calendar.current

    func testFFMILeanMassAndFatMassMatchGoldenValues() throws {
        let ffmi = try XCTUnwrap(UnitConversion.calculateFFMI(
            weightKg: 80,
            bodyFatPercentage: 10,
            heightCm: 177.8
        ))
        XCTAssertEqual(ffmi, 22.9, accuracy: 0.05)

        let leanMassKg = try XCTUnwrap(UnitConversion.calculateLeanMass(
            weightKg: 80,
            bodyFatPercentage: 10,
            useMetric: true
        ))
        XCTAssertEqual(leanMassKg, 72, accuracy: 0.001)

        let leanMassLbs = try XCTUnwrap(UnitConversion.calculateLeanMass(
            weightKg: 80,
            bodyFatPercentage: 10,
            useMetric: false
        ))
        XCTAssertEqual(leanMassLbs, 158.733, accuracy: 0.001)

        let fatMassKg = try XCTUnwrap(UnitConversion.calculateFatMass(
            weightKg: 80,
            bodyFatPercentage: 10,
            useMetric: true
        ))
        XCTAssertEqual(fatMassKg, 8, accuracy: 0.001)

        let fatMassLbs = try XCTUnwrap(UnitConversion.calculateFatMass(
            weightKg: 80,
            bodyFatPercentage: 10,
            useMetric: false
        ))
        XCTAssertEqual(fatMassLbs, 17.637, accuracy: 0.001)
    }

    func testBodyCompositionCalculationsRejectInvalidInputsAndKeepExtremeValuesFinite() throws {
        XCTAssertNil(UnitConversion.calculateFFMI(weightKg: 0, bodyFatPercentage: 10, heightCm: 180))
        XCTAssertNil(UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 0, heightCm: 180))
        XCTAssertNil(UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 100, heightCm: 180))
        XCTAssertNil(UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 10, heightCm: 0))

        let extremeFFMI = try XCTUnwrap(UnitConversion.calculateFFMI(
            weightKg: 80,
            bodyFatPercentage: 99.9,
            heightCm: 180
        ))
        XCTAssertTrue(extremeFFMI.isFinite)
        XCTAssertGreaterThan(extremeFFMI, 0)

        let extremeLeanMass = try XCTUnwrap(UnitConversion.calculateLeanMass(
            weightKg: 80,
            bodyFatPercentage: 99.9,
            useMetric: true
        ))
        XCTAssertTrue(extremeLeanMass.isFinite)
        XCTAssertEqual(extremeLeanMass, 0.08, accuracy: 0.0001)
    }

    func testWeightConversionsRoundTripWithinHundredth() {
        for weightKg in [20.0, 80.0, 123.45, 300.0] {
            let roundTripped = UnitConversion.lbsToKg(UnitConversion.kgToLbs(weightKg))
            XCTAssertEqual(roundTripped, weightKg, accuracy: 0.01)
        }
    }

    func testWeightSanityRangeMatchesLaunchValidationBounds() {
        XCTAssertFalse(UnitConversion.isValidWeight(31.9))
        XCTAssertTrue(UnitConversion.isValidWeight(32))
        XCTAssertTrue(UnitConversion.isValidWeight(300))
        XCTAssertFalse(UnitConversion.isValidWeight(300.1))
    }

    func testTrendWeightUsesHandComputedEMAReference() throws {
        let context = try makeWeightContext([
            (dayOffset: 0, weight: 100),
            (dayOffset: 1, weight: 104),
            (dayOffset: 2, weight: 108)
        ])

        let dayTwoTrend = try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: 2)))

        XCTAssertEqual(dayTwoTrend.value, 102.8, accuracy: 0.001)
        XCTAssertFalse(dayTwoTrend.isInterpolated)
        XCTAssertFalse(dayTwoTrend.isLastKnown)
        XCTAssertNil(dayTwoTrend.confidenceLevel)
    }

    func testTrendWeightConfidenceDegradesWithInterpolationGap() throws {
        let cases: [(gapDays: Int, queryDay: Int, expected: InterpolatedMetric.ConfidenceLevel)] = [
            (7, 3, .high),
            (14, 7, .medium),
            (30, 15, .low)
        ]

        for testCase in cases {
            let context = try makeWeightContext([
                (dayOffset: 0, weight: 100),
                (dayOffset: testCase.gapDays, weight: 130)
            ])

            let trend = try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: testCase.queryDay)))
            XCTAssertTrue(trend.isInterpolated)
            XCTAssertEqual(trend.confidenceLevel?.rawValue, testCase.expected.rawValue)
        }
    }

    func testTrendWeightReturnsNilWhenInterpolationGapExceedsThirtyDays() throws {
        let context = try makeWeightContext([
            (dayOffset: 0, weight: 100),
            (dayOffset: 31, weight: 131)
        ])

        XCTAssertNil(context.trendWeight(for: date(daysAfterStart: 15)))
    }

    private func makeWeightContext(
        _ points: [(dayOffset: Int, weight: Double)]
    ) throws -> MetricsInterpolationService.WeightInterpolationContext {
        let metrics = points.map { point in
            makeMetric(
                date: date(daysAfterStart: point.dayOffset),
                weight: point.weight
            )
        }
        return try XCTUnwrap(MetricsInterpolationService.shared.makeWeightInterpolationContext(for: metrics))
    }

    private func makeMetric(date: Date, weight: Double) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: "body-comp-golden-tests",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }

    private func date(daysAfterStart dayOffset: Int) -> Date {
        let start = calendar.date(from: DateComponents(
            year: 2_026,
            month: 1,
            day: 1
        ))!
        return calendar.date(byAdding: .day, value: dayOffset, to: start)!
    }
}

@MainActor
final class AccountDeletionCleanupServiceTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case clerkDeletionFailed
        case coreDataCleanupFailed
    }

    func testPerformDeletionRunsProviderAndLocalCleanupInOrder() async throws {
        var events: [String] = []
        let service = AccountDeletionCleanupService(
            dependencies: .init(
                logoutRevenueCat: {
                    events.append("revenuecat")
                },
                resetHealthKitAnchors: {
                    events.append("healthkit")
                },
                notifyBackendOfAccountDeletion: {
                    events.append("backend")
                },
                deleteClerkAccount: {
                    events.append("clerk")
                },
                deleteCoreData: {
                    events.append("coredata")
                },
                clearKeychain: {
                    events.append("keychain")
                },
                deleteSpotlightMetrics: {
                    events.append("spotlight")
                },
                clearUserDefaults: {
                    events.append("defaults")
                    return ["currentUser"]
                },
                logoutAuthSession: {
                    events.append("auth")
                }
            )
        )

        try await service.performDeletion()

        XCTAssertEqual(
            events,
            [
                "revenuecat",
                "healthkit",
                "backend",
                "clerk",
                "coredata",
                "keychain",
                "defaults",
                "spotlight",
                "auth"
            ]
        )
    }

    func testPerformDeletionStillClearsCredentialsAndSessionWhenCoreDataCleanupFails() async {
        var events: [String] = []
        let service = AccountDeletionCleanupService(
            dependencies: .init(
                logoutRevenueCat: {
                    events.append("revenuecat")
                },
                resetHealthKitAnchors: {
                    events.append("healthkit")
                },
                notifyBackendOfAccountDeletion: {
                    events.append("backend")
                },
                deleteClerkAccount: {
                    events.append("clerk")
                },
                deleteCoreData: {
                    events.append("coredata")
                    throw TestError.coreDataCleanupFailed
                },
                clearKeychain: {
                    events.append("keychain")
                },
                deleteSpotlightMetrics: {
                    events.append("spotlight")
                },
                clearUserDefaults: {
                    events.append("defaults")
                    return []
                },
                logoutAuthSession: {
                    events.append("auth")
                }
            )
        )

        do {
            try await service.performDeletion()
            XCTFail("Expected Core Data cleanup failure to be rethrown")
        } catch {
            XCTAssertEqual(error as? TestError, .coreDataCleanupFailed)
        }

        XCTAssertEqual(
            events,
            [
                "revenuecat",
                "healthkit",
                "backend",
                "clerk",
                "coredata",
                "keychain",
                "defaults",
                "spotlight",
                "auth"
            ]
        )
    }

    func testPerformDeletionStopsBeforeLocalDestructiveCleanupWhenClerkDeletionFails() async {
        var events: [String] = []
        let service = AccountDeletionCleanupService(
            dependencies: .init(
                logoutRevenueCat: {
                    events.append("revenuecat")
                },
                resetHealthKitAnchors: {
                    events.append("healthkit")
                },
                notifyBackendOfAccountDeletion: {
                    events.append("backend")
                },
                deleteClerkAccount: {
                    events.append("clerk")
                    throw TestError.clerkDeletionFailed
                },
                deleteCoreData: {
                    events.append("coredata")
                },
                clearKeychain: {
                    events.append("keychain")
                },
                deleteSpotlightMetrics: {
                    events.append("spotlight")
                },
                clearUserDefaults: {
                    events.append("defaults")
                    return []
                },
                logoutAuthSession: {
                    events.append("auth")
                }
            )
        )

        do {
            try await service.performDeletion()
            XCTFail("Expected Clerk deletion failure to be rethrown")
        } catch {
            XCTAssertEqual(error as? TestError, .clerkDeletionFailed)
        }

        XCTAssertEqual(events, ["revenuecat", "healthkit", "backend", "clerk"])
    }

    func testClearAccountUserDefaultsRemovesAuthHealthKitBillingAndLaunchState() {
        let suiteName = "AccountDeletionCleanupServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let keys = [
            Constants.currentUserKey,
            Constants.authTokenKey,
            Constants.hasCompletedOnboardingKey,
            Constants.onboardingCompletedVersionKey,
            Constants.onboardingCompletedUserIdKey,
            Constants.defaultHomeModeKey,
            Constants.timelineModeKey,
            "healthKitSyncEnabled",
            HealthKitDefaultsKey.authorizationConfirmed.rawValue,
            HealthKitDefaultsKey.lastObserverSyncDate.rawValue,
            HealthKitDefaultsKey.fullSyncCompleted.rawValue,
            "HasSyncedHistoricalSteps",
            "lastSupabaseSyncDate",
            "lastHealthKitWeightSyncDate",
            "revenuecat_isSubscribed",
            "revenuecat_lastFetchTimestamp",
            "biometricLockEnabled",
            "appleSignInName",
            "supabaseAccessToken",
            "supabaseRefreshToken"
        ]

        for key in keys {
            defaults.set("value", forKey: key)
        }

        let removedKeys = AccountDeletionCleanupService.clearAccountUserDefaults(in: defaults)

        for key in keys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should be removed")
        }
        XCTAssertTrue(Set(removedKeys).isSuperset(of: keys))
    }
}

final class PhotoTimelineHUDPolicyTests: XCTestCase {
    func testPhotoTimelineHUDIsDefaultV1Surface() {
        XCTAssertTrue(PhotoTimelineHUDPolicy.defaultShowsPhotoTimelineHUD)
        XCTAssertTrue(PhotoTimelineHUDPolicy.shouldShowPhotoTimelineHUD())
        XCTAssertEqual(PaidAppSurfacePolicy.surface(), .photoTimelineHUD)
    }

    func testDefaultHomeModeDefaultsToAvatar() {
        XCTAssertEqual(Constants.defaultHomeModeKey, "defaultHomeMode")
        XCTAssertEqual(Constants.onboardingCompletedUserIdKey, "onboardingCompletedUserId")
        XCTAssertEqual(DefaultHomeMode.default, .avatar)
        XCTAssertEqual(DefaultHomeMode(storedValue: "photo"), .photo)
        XCTAssertEqual(DefaultHomeMode(storedValue: "unexpected"), .avatar)
        XCTAssertEqual(DefaultHomeMode.avatar.timelineMode, .avatar)
        XCTAssertEqual(DefaultHomeMode.photo.timelineMode, .photo)
        XCTAssertEqual(DefaultHomeMode(timelineMode: .avatar), .avatar)
        XCTAssertEqual(DefaultHomeMode(timelineMode: .photo), .photo)
    }

    func testAvatarBodyFatCatalogSelectsNearestMaleBucket() {
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 16.4, gender: "male"),
            AvatarBodyFatCatalog.Match(sex: .male, bucket: 15)
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 20.2, gender: "male").assetName,
            "avatar_male_22"
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 80, gender: "male").bucket,
            55
        )
    }

    func testAvatarBodyFatCatalogSelectsNearestFemaleBucket() {
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 22.4, gender: "female"),
            AvatarBodyFatCatalog.Match(sex: .female, bucket: 21)
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 45.2, gender: "woman").assetName,
            "avatar_female_50"
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 72, gender: "f").bucket,
            60
        )
    }

    func testAvatarBodyFatCatalogUsesSexSpecificDefaultsWhenBodyFatIsMissing() {
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: nil, gender: "male").assetName,
            "avatar_male_18"
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: nil, gender: "female").assetName,
            "avatar_female_28"
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: nil, gender: nil).assetName,
            "avatar_male_18"
        )
    }

    func testAvatarBodyFatAssetsHaveTransparentSourceBackgrounds() throws {
        let assetNames = AvatarBodyFatCatalog.Sex.male.buckets.map {
            AvatarBodyFatCatalog.Match(sex: .male, bucket: $0).assetName
        } + AvatarBodyFatCatalog.Sex.female.buckets.map {
            AvatarBodyFatCatalog.Match(sex: .female, bucket: $0).assetName
        }

        for assetName in assetNames {
            let image = try XCTUnwrap(UIImage(named: assetName), "\(assetName) should exist in the app asset catalog")
            let perimeterAlphaValues = try renderedPerimeterAlphaValues(for: image)

            XCTAssertTrue(
                perimeterAlphaValues.allSatisfy { $0 <= 4 },
                "\(assetName) should not retain the black source-image rectangle"
            )
        }
    }

    func testPhotoTimelineHUDMetricStateCopyIsExplicit() {
        XCTAssertEqual(PhotoTimelineHUDPolicy.stateText(presence: .present), "Measured")
        XCTAssertEqual(
            PhotoTimelineHUDPolicy.stateText(presence: .interpolated, confidence: .medium),
            "Interpolated - medium confidence"
        )
        XCTAssertEqual(PhotoTimelineHUDPolicy.stateText(presence: .lastKnown), "Last known")
        XCTAssertEqual(PhotoTimelineHUDPolicy.stateText(presence: .missing), "Missing")
    }

    private func renderedPerimeterAlphaValues(for image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var alphaValues: [UInt8] = []
        alphaValues.reserveCapacity((width * 2) + (height * 2))

        for xValue in 0..<width {
            alphaValues.append(alphaValue(in: pixels, width: width, x: xValue, y: 0))
            alphaValues.append(alphaValue(in: pixels, width: width, x: xValue, y: height - 1))
        }

        for yValue in 0..<height {
            alphaValues.append(alphaValue(in: pixels, width: width, x: 0, y: yValue))
            alphaValues.append(alphaValue(in: pixels, width: width, x: width - 1, y: yValue))
        }

        return alphaValues
    }

    private func alphaValue(in pixels: [UInt8], width: Int, x: Int, y: Int) -> UInt8 {
        let bytesPerPixel = 4
        let index = (y * width + x) * bytesPerPixel + 3
        return pixels[index]
    }
}

@MainActor
final class BodyScoreShareCardTests: XCTestCase {
    func testShareSheetDefaultsToPortraitExportAspect() {
        XCTAssertEqual(BodyScoreShareAspect.defaultExportAspect, .portrait)
        XCTAssertEqual(BodyScoreShareAspect.preferredExportAspect(for: nil), .portrait)
    }

    func testPhotoShareAspectTracksNativeImageShape() {
        XCTAssertEqual(
            BodyScoreShareAspect.preferredExportAspect(
                for: makeShareTestImage(size: CGSize(width: 480, height: 640))
            ),
            .portrait
        )
        XCTAssertEqual(
            BodyScoreShareAspect.preferredExportAspect(
                for: makeShareTestImage(size: CGSize(width: 360, height: 760))
            ),
            .story
        )
        XCTAssertEqual(
            BodyScoreShareAspect.preferredExportAspect(
                for: makeShareTestImage(size: CGSize(width: 640, height: 640))
            ),
            .square
        )
    }

    func testMetricSummaryDataPointIdentityIsStableAcrossRenders() {
        let first = MetricSummaryCard.DataPoint(index: 4, value: 181.2)
        let second = MetricSummaryCard.DataPoint(index: 4, value: 179.8)

        XCTAssertEqual(first.id, second.id)
    }

    func testMetricChartDataPointIdentityIsStableAcrossRenders() {
        let date = Date(timeIntervalSince1970: 1_771_000_000)
        let first = MetricChartDataPoint(date: date, value: 181.2, presence: .present)
        let second = MetricChartDataPoint(date: date, value: 181.2, presence: .present)
        let interpolated = MetricChartDataPoint(date: date, value: 181.2, presence: .interpolated)

        XCTAssertEqual(first.id, second.id)
        XCTAssertNotEqual(first.id, interpolated.id)
    }

    func testShareCardLayoutScalesDownForNarrowStoryPreview() {
        let layout = ShareCardLayout(size: CGSize(width: 260, height: 462), aspect: .story)

        XCTAssertLessThan(layout.scale, 0.7)
        XCTAssertLessThan(layout.scoreFontSize, 42)
        XCTAssertLessThan(layout.metricValueFontSize, 14)
    }

    func testShareCardLayoutReservesBottomMatteForStoryPreviewText() {
        let layout = ShareCardLayout(size: CGSize(width: 260, height: 462), aspect: .story)

        XCTAssertGreaterThan(layout.summaryMatteHeight, layout.size.height * 0.44)
        XCTAssertLessThan(layout.visualTopOffset + layout.visualHeight, layout.size.height * 0.72)
    }

    func testShareCardLayoutKeepsAvatarVisualClearOfSummaryText() {
        let previewSizes: [(BodyScoreShareAspect, CGSize)] = [
            (.square, CGSize(width: 320, height: 320)),
            (.portrait, CGSize(width: 320, height: 400)),
            (.story, CGSize(width: 260, height: 462)),
            (.story, CGSize(width: 1_080, height: 1_920))
        ]

        for (aspect, size) in previewSizes {
            let layout = ShareCardLayout(size: size, aspect: aspect)
            let avatarBottom = layout.visualTopOffset + layout.visualHeight

            XCTAssertLessThanOrEqual(
                avatarBottom + layout.textVisualGap,
                layout.summaryTopY + 0.5,
                "Avatar visual overlaps text budget for \(aspect.rawValue)"
            )
            XCTAssertGreaterThanOrEqual(
                layout.summaryMatteHeight,
                layout.size.height - layout.summaryTopY,
                "Summary matte must cover the full text area for \(aspect.rawValue)"
            )
        }
    }

    func testSharePayloadUsesSameNearestAvatarBucketAsHomeHero() {
        let payload = makePayload(bodyFatPercentage: 16.4, gender: "male")

        XCTAssertEqual(payload.avatarMatch.assetName, "avatar_male_15")
        XCTAssertEqual(payload.avatarMatch.badgeText, "Male 15% body fat")
        XCTAssertEqual(payload.visualBadgeText, "Male 15% body fat")
        XCTAssertNil(payload.photoImage)
    }

    func testPhotoBackedSharePayloadUsesProgressPhotoBadge() {
        let payload = makePayload(
            bodyFatPercentage: 16.4,
            gender: "male",
            photoImage: makeShareTestImage()
        )

        XCTAssertEqual(payload.visualBadgeText, "Progress photo")
        XCTAssertNotNil(payload.photoImage)
    }

    func testShareCardRendersRequestedExportSize() throws {
        let size = BodyScoreShareAspect.portrait.pixelSize
        let renderer = ImageRenderer(
            content: BodyScoreShareCardView(
                payload: makePayload(bodyFatPercentage: 22.4, gender: "female"),
                aspect: .portrait
            )
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1.0

        let image = try XCTUnwrap(renderer.uiImage)

        XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)
    }

    func testShareCardRendersEveryLaunchExportAspect() throws {
        for aspect in BodyScoreShareAspect.allCases {
            let size = aspect.pixelSize
            let renderer = ImageRenderer(
                content: BodyScoreShareCardView(
                    payload: makePayload(bodyFatPercentage: 18.6, gender: "male"),
                    aspect: aspect
                )
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
            )
            renderer.scale = 1.0

            let image = try XCTUnwrap(renderer.uiImage, "Missing rendered image for \(aspect.rawValue)")

            XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)
        }
    }

    func testPhotoBackedShareCardRendersEveryLaunchExportAspect() throws {
        for aspect in BodyScoreShareAspect.allCases {
            let size = aspect.pixelSize
            let renderer = ImageRenderer(
                content: BodyScoreShareCardView(
                    payload: makePayload(
                        bodyFatPercentage: 18.6,
                        gender: "male",
                        photoImage: makeShareTestImage()
                    ),
                    aspect: aspect
                )
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
            )
            renderer.scale = 1.0

            let image = try XCTUnwrap(renderer.uiImage, "Missing rendered photo image for \(aspect.rawValue)")

            XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)
        }
    }

    private func makePayload(
        bodyFatPercentage: Double?,
        gender: String?,
        photoImage: UIImage? = nil
    ) -> BodyScoreSharePayload {
        BodyScoreSharePayload(
            score: 82,
            scoreText: "82",
            tagline: "Athletic and trending leaner",
            ffmiValue: "21.8",
            ffmiCaption: "Strong",
            bodyFatValue: "16.4",
            bodyFatCaption: "%",
            weightValue: "181.0",
            weightCaption: "lb",
            deltaText: "+4 over 30 days",
            bodyFatPercentage: bodyFatPercentage,
            gender: gender,
            photoImage: photoImage
        )
    }

    private func makeShareTestImage(size: CGSize = CGSize(width: 480, height: 640)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // swiftlint:disable:next object_literal
            UIColor(red: 0.05, green: 0.11, blue: 0.18, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // swiftlint:disable:next object_literal
            UIColor(red: 0.12, green: 0.55, blue: 1.0, alpha: 1).setFill()
            context.fill(
                CGRect(
                    x: size.width * 0.23,
                    y: size.height * 0.12,
                    width: size.width * 0.54,
                    height: size.height * 0.72
                )
            )

            UIColor.white.withAlphaComponent(0.82).setFill()
            context.fill(
                CGRect(
                    x: size.width * 0.35,
                    y: size.height * 0.19,
                    width: size.width * 0.30,
                    height: size.height * 0.50
                )
            )
        }
    }
}

final class DashboardTimelineProviderPerformanceTests: XCTestCase {
    func testNearestBodyMetricIndexSelectsClosestTimelineDate() {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.date(from: DateComponents(year: 2_026, month: 6, day: 1))!
        let metrics = [
            makeMetric(id: "old", date: baseDate, weight: 181, bodyFat: 18.5),
            makeMetric(
                id: "middle",
                date: calendar.date(byAdding: .day, value: 7, to: baseDate)!,
                weight: 180,
                bodyFat: 18.2
            ),
            makeMetric(
                id: "new",
                date: calendar.date(byAdding: .day, value: 14, to: baseDate)!,
                weight: 179,
                bodyFat: 18.0
            )
        ]

        let scrubDate = calendar.date(byAdding: .day, value: 9, to: baseDate)!

        XCTAssertEqual(nearestBodyMetricIndex(in: metrics, to: scrubDate), 1)
    }

    func testNearestBodyMetricIndexReturnsNilForEmptyTimeline() {
        XCTAssertNil(nearestBodyMetricIndex(in: [], to: Date()))
    }

    func testTimelineRenderSignatureTracksOnlyRenderInputs() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let metric = makeMetric(
            id: "metric",
            date: baseDate,
            weight: 181,
            bodyFat: 18.4,
            photoUrl: "https://example.com/original.jpg"
        )
        let sameMetric = makeMetric(
            id: "metric",
            date: baseDate,
            weight: 181,
            bodyFat: 18.4,
            photoUrl: "https://example.com/original.jpg"
        )
        let changedPhoto = makeMetric(
            id: "metric",
            date: baseDate,
            weight: 181,
            bodyFat: 18.4,
            photoUrl: "https://example.com/changed.jpg"
        )
        let changedUpdatedAt = makeMetric(
            id: "metric",
            date: baseDate,
            weight: 181,
            bodyFat: 18.4,
            photoUrl: "https://example.com/original.jpg",
            updatedAt: baseDate.addingTimeInterval(1)
        )

        let signature = TimelineRenderSignature(metrics: [metric], mode: .photo)

        XCTAssertEqual(
            signature,
            TimelineRenderSignature(metrics: [sameMetric], mode: .photo)
        )
        XCTAssertNotEqual(
            signature,
            TimelineRenderSignature(metrics: [metric], mode: .avatar)
        )
        XCTAssertNotEqual(
            signature,
            TimelineRenderSignature(metrics: [changedPhoto], mode: .photo)
        )
        XCTAssertNotEqual(
            signature,
            TimelineRenderSignature(metrics: [changedUpdatedAt], mode: .photo)
        )
    }

    func testTimelineRenderDataFactorySortsMetricsAndBuildsAnchors() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let newest = makeMetric(id: "newest", date: baseDate, weight: 181, bodyFat: nil)
        let oldest = makeMetric(id: "oldest", date: baseDate.addingTimeInterval(-86_400 * 3), weight: 184, bodyFat: nil)
        let photo = makeMetric(
            id: "photo",
            date: baseDate.addingTimeInterval(-86_400),
            weight: nil,
            bodyFat: 18.4,
            photoUrl: "https://example.com/photo.jpg"
        )

        let renderData = TimelineRenderData.make(metrics: [newest, photo, oldest], mode: .photo)

        XCTAssertEqual(renderData.metrics.map(\.id), ["oldest", "photo", "newest"])
        XCTAssertEqual(renderData.provider.bodyMetrics.map(\.id), ["oldest", "photo", "newest"])
        XCTAssertFalse(renderData.anchors.isEmpty)
        XCTAssertTrue(renderData.anchors.contains { $0.id == "photo" })
    }

    func testLoadMetricsBuildsSortedTimelineIndexesOnce() {
        let provider = TimelineDataProvider()
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let oldest = makeMetric(id: "oldest", date: baseDate.addingTimeInterval(-86_400 * 2), weight: 181, bodyFat: nil)
        let photo = makeMetric(
            id: "photo",
            date: baseDate.addingTimeInterval(-86_400),
            weight: nil,
            bodyFat: nil,
            photoUrl: "https://example.com/photo.jpg"
        )
        let bodyData = makeMetric(id: "body-data", date: baseDate, weight: nil, bodyFat: 18.4)

        provider.loadMetrics([bodyData, photo, oldest])

        XCTAssertEqual(provider.bodyMetrics.map(\.id), ["oldest", "photo", "body-data"])
        XCTAssertEqual(provider.getAllDataDates(), [oldest.date, photo.date, bodyData.date])
        XCTAssertEqual(provider.findNearestDataDate(to: baseDate.addingTimeInterval(-3_600)), bodyData.date)
    }

    func testLocalDateLookupHandlesMultipleMetricsOnSameDay() throws {
        let provider = TimelineDataProvider()
        let calendar = Calendar(identifier: .gregorian)
        let morningDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2_026,
            month: 6,
            day: 14,
            hour: 8
        )))
        let eveningDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2_026,
            month: 6,
            day: 14,
            hour: 16
        )))
        let morning = makeMetric(
            id: "morning",
            date: morningDate,
            localDate: "2026-06-14",
            weight: 181,
            bodyFat: nil
        )
        let evening = makeMetric(
            id: "evening",
            date: eveningDate,
            localDate: "2026-06-14",
            weight: 180.5,
            bodyFat: nil
        )

        provider.loadMetrics([evening, morning])

        XCTAssertEqual(provider.getMetric(for: morning.date)?.id, "evening")
    }

    private func makeMetric(
        id: String,
        date: Date,
        localDate: String? = nil,
        weight: Double?,
        bodyFat: Double?,
        photoUrl: String? = nil,
        updatedAt: Date? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "timeline-performance-user",
            date: date,
            localDate: localDate,
            weight: weight,
            weightUnit: "lbs",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "scale",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoUrl,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date,
            updatedAt: updatedAt ?? date
        )
    }
}

@MainActor
final class ProgressPhotoImagePipelineTests: XCTestCase {
    func testOptimizeImageDownsamplesLargeImages() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2_400, height: 1_800), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 1_800))
        }

        let optimized = ProgressPhotoImagePipeline.optimizeImage(image, maxDimension: 1_200)

        XCTAssertLessThanOrEqual(max(optimized.size.width, optimized.size.height), 1_200)
        XCTAssertEqual(optimized.size.width, 1_200, accuracy: 1)
        XCTAssertEqual(optimized.size.height, 900, accuracy: 1)
    }

    func testCacheCostUsesPixelBytesWithoutEncodingImageData() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        }

        XCTAssertEqual(ProgressPhotoImagePipeline.cacheCost(for: image), 20_000)
    }

    func testResolvedImageLoadsAndCachesLocalPhotoForShareExport() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
        }
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyb-share-cache-\(UUID().uuidString).png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = await OptimizedProgressPhotoView.resolvedImage(for: url.absoluteString)
        let second = await OptimizedProgressPhotoView.resolvedImage(for: url.absoluteString)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.size.width, second?.size.width)
        XCTAssertEqual(first?.size.height, second?.size.height)
    }
}

final class DashboardDataVizPolicyTests: XCTestCase {
    func testMetricSummaryFootnoteKeepsOneGoalStatWhenGoalExists() {
        XCTAssertEqual(
            metricSummaryFootnote(
                averageText: "181.4 lb average",
                goalText: "Target 180.0 lb"
            ),
            "Target 180.0 lb"
        )
    }

    func testMetricSummaryFootnoteFallsBackToOneAverageStat() {
        XCTAssertEqual(
            metricSummaryFootnote(
                averageText: "18.2 average",
                goalText: nil
            ),
            "18.2 average"
        )
    }

    func testMetricSummaryFootnoteOmitsEmptyStats() {
        XCTAssertNil(
            metricSummaryFootnote(
                averageText: "",
                goalText: ""
            )
        )
    }
}

final class PreferenceGoalValidatorTests: XCTestCase {
    func testAcceptsValidGoalValuesAtBoundaries() {
        XCTAssertEqual(
            PreferenceGoalValidator.validate("1", for: .weight),
            PreferenceGoalValidationResult(value: 1, errorMessage: nil)
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("3", for: .bodyFat),
            PreferenceGoalValidationResult(value: 3, errorMessage: nil)
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("60", for: .bodyFat),
            PreferenceGoalValidationResult(value: 60, errorMessage: nil)
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("10", for: .ffmi),
            PreferenceGoalValidationResult(value: 10, errorMessage: nil)
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("30", for: .ffmi),
            PreferenceGoalValidationResult(value: 30, errorMessage: nil)
        )
    }

    func testRejectsInvalidGoalValuesWithSpecificMessages() {
        XCTAssertEqual(
            PreferenceGoalValidator.validate(" ", for: .weight).errorMessage,
            "Enter a value."
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("abc", for: .weight).errorMessage,
            "Enter a valid number."
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("0", for: .weight).errorMessage,
            "Weight goal must be greater than 0."
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("2.9", for: .bodyFat).errorMessage,
            "Body fat goal must be between 3-60%."
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("30.1", for: .ffmi).errorMessage,
            "FFMI goal must be between 10-30."
        )
    }
}

final class DailyReminderPolicyTests: XCTestCase {
    func testPromptRequiresSubscriptionAndIncompletePrompt() {
        XCTAssertTrue(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: true,
                hasCompletedPrompt: false
            )
        )
        XCTAssertFalse(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: false,
                hasCompletedPrompt: false
            )
        )
        XCTAssertFalse(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: true,
                hasCompletedPrompt: true
            )
        )
    }

    func testDailyWeighInReminderDefaultsToSevenAM() {
        XCTAssertEqual(DailyReminderPolicy.defaultHour, 7)
        XCTAssertEqual(DailyReminderPolicy.defaultMinute, 0)
        XCTAssertEqual(
            NotificationReminderKind.dailyWeighIn.requestIdentifier,
            "lyb.notification.daily_weigh_in"
        )
    }

    func testReminderTimeNormalizationClampsInvalidValues() {
        let low = DailyReminderPolicy.normalizedTime(hour: -2, minute: -10)
        XCTAssertEqual(low.hour, 0)
        XCTAssertEqual(low.minute, 0)

        let high = DailyReminderPolicy.normalizedTime(hour: 30, minute: 91)
        XCTAssertEqual(high.hour, 23)
        XCTAssertEqual(high.minute, 59)
    }

    func testTriggerComponentsUseNormalizedHourAndMinuteOnly() {
        let components = DailyReminderPolicy.triggerDateComponents(hour: 26, minute: 75)

        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 59)
        XCTAssertNil(components.day)
        XCTAssertNil(components.month)
    }
}

final class BodyMetricLoggingServiceTests: XCTestCase {
    func testStoredWeightConvertsPoundsToKilograms() {
        let stored = BodyMetricLoggingService.storedWeightInKilograms(
            displayWeight: 180,
            unit: "lbs"
        )

        XCTAssertEqual(stored ?? 0, 81.6467, accuracy: 0.001)
    }

    func testStoredWeightKeepsKilograms() {
        let stored = BodyMetricLoggingService.storedWeightInKilograms(
            displayWeight: 82.5,
            unit: "kg"
        )

        XCTAssertEqual(stored, 82.5)
    }

    func testLoggedSummaryUsesPreferredWeightUnitAndBodyFatPercent() {
        let metric = BodyMetrics(
            id: "metric-1",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: 81.6467,
            weightUnit: "kg",
            bodyFatPercentage: 14.8,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(
            BodyMetricLoggingService.loggedSummary(for: metric, preferredSystem: .imperial),
            "Logged 180.0 lbs and 14.8% body fat."
        )
    }

    func testSpotlightDocumentUsesLatestMetricSearchCopy() {
        let metric = BodyMetrics(
            id: "metric-spotlight",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: 81.6467,
            weightUnit: "kg",
            bodyFatPercentage: 14.8,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let document = BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .imperial)

        XCTAssertEqual(document?.identifier, "body-metric-metric-spotlight")
        XCTAssertEqual(document?.title, "Latest LogYourBody metrics")
        XCTAssertEqual(document?.contentDescription, "180.0 lbs, 14.8% body fat on 1970-01-01")
        XCTAssertEqual(
            document?.keywords,
            [
                "LogYourBody",
                "body metrics",
                "weight",
                "body composition",
                "1970-01-01",
                "latest weight",
                "body fat"
            ]
        )
    }

    func testSpotlightDocumentSkipsEntriesWithoutSearchableMetrics() {
        let metric = BodyMetrics(
            id: "metric-empty",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: nil,
            weightUnit: nil,
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertNil(BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .imperial))
    }
}

final class PhaseInsightPolicyTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()

        calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testPhaseInsightShowsByDefaultForV1Launch() {
        XCTAssertTrue(PhaseInsightPolicy.defaultShowsPhaseInsight)
        XCTAssertTrue(PhaseInsightPolicy.shouldShowPhaseInsight())
    }

    func testClassifiesCuttingWithBodyFatContext() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 1, day: 1), weight: 85, bodyFat: 18),
            makePhaseMetric(date: makeDate(year: 2_026, month: 1, day: 29), weight: 82, bodyFat: 16.9)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .cutting)
        XCTAssertEqual(insight.title, "Cutting")
        XCTAssertTrue(insight.message.contains("body fat is moving lower"))
        XCTAssertLessThan(try XCTUnwrap(insight.weightDeltaPercentPerWeek), -0.25)
        XCTAssertEqual(try XCTUnwrap(insight.bodyFatDeltaPercentagePoints), -1.1, accuracy: 0.001)
    }

    func testClassifiesMaintainingWhenWeightIsStable() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 2, day: 1), weight: 80, bodyFat: 15),
            makePhaseMetric(date: makeDate(year: 2_026, month: 2, day: 28), weight: 80.2, bodyFat: 15.1)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .maintaining)
        XCTAssertEqual(insight.title, "Maintaining")
        XCTAssertTrue(insight.message.contains("holding steady"))
        XCTAssertFalse(insight.isLongRunning)
    }

    func testClassifiesGainingWithBodyFatContext() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 3, day: 1), weight: 80, bodyFat: 14),
            makePhaseMetric(date: makeDate(year: 2_026, month: 3, day: 29), weight: 82, bodyFat: 14.8)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .gaining)
        XCTAssertEqual(insight.title, "Gaining")
        XCTAssertTrue(insight.message.contains("body fat is moving higher"))
        XCTAssertGreaterThan(try XCTUnwrap(insight.weightDeltaPercentPerWeek), 0.25)
    }

    func testInsufficientDataRequiresTwoWeeksOfWeights() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 4, day: 1), weight: 80, bodyFat: nil),
            makePhaseMetric(date: makeDate(year: 2_026, month: 4, day: 7), weight: 79.5, bodyFat: nil)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .insufficientData)
        XCTAssertEqual(insight.title, "Need more data")
        XCTAssertNil(insight.weightDeltaPercentPerWeek)
    }

    func testLongRunningCutAddsCautionWithoutChatCopy() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 1, day: 1), weight: 90, bodyFat: 22),
            makePhaseMetric(date: makeDate(year: 2_026, month: 3, day: 1), weight: 86, bodyFat: 20),
            makePhaseMetric(date: makeDate(year: 2_026, month: 4, day: 1), weight: 84, bodyFat: 19),
            makePhaseMetric(date: makeDate(year: 2_026, month: 5, day: 1), weight: 82, bodyFat: 18)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .cutting)
        XCTAssertTrue(insight.isLongRunning)
        XCTAssertEqual(insight.detail, "This cut has run 12+ weeks; review photos and body-fat context.")
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }

    private func makePhaseMetric(
        date: Date,
        weight: Double,
        bodyFat: Double?
    ) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: "phase-user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: date,
            updatedAt: date
        )
    }
}

final class Glp1WeeklyCheckInPolicyTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()

        calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testWeeklyCheckInShowsByDefaultForV1Launch() {
        XCTAssertTrue(Glp1WeeklyCheckInPolicy.defaultShowsWeeklyCheckIn)
        XCTAssertTrue(Glp1WeeklyCheckInPolicy.shouldShowWeeklyCheckIn())
    }

    func testSetupStateWhenNoDoseExists() {
        let medication = makeMedication(startedAt: makeDate(year: 2_026, month: 1, day: 1))

        let summary = Glp1WeeklyCheckInPolicy.summary(
            medications: [medication],
            doseLogs: [],
            now: makeDate(year: 2_026, month: 1, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(summary.status, .setup)
        XCTAssertEqual(summary.title, "Weekly GLP-1 check-in")
        XCTAssertEqual(summary.actionTitle, "Set up")
        XCTAssertEqual(summary.medicationName, "Zepbound")
        XCTAssertNil(summary.daysSinceLastDose)
    }

    func testDueStateUsesLastLoggedDoseWithoutMedicalAdvice() {
        let medication = makeMedication(startedAt: makeDate(year: 2_026, month: 1, day: 1))
        let log = makeDoseLog(takenAt: makeDate(year: 2_026, month: 1, day: 1))

        let summary = Glp1WeeklyCheckInPolicy.summary(
            medications: [medication],
            doseLogs: [log],
            now: makeDate(year: 2_026, month: 1, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(summary.status, .due)
        XCTAssertEqual(summary.title, "Weekly GLP-1 check-in")
        XCTAssertEqual(summary.latestDoseText, "5.0 mg/week")
        XCTAssertEqual(summary.daysSinceLastDose, 9)
        XCTAssertTrue(summary.message.contains("Zepbound was last logged 9 days ago"))
        XCTAssertFalse(summary.message.lowercased().contains("take"))
        XCTAssertFalse(summary.message.lowercased().contains("inject"))
    }

    func testLoggedStateWhenDoseWasRecordedThisWeek() {
        let medication = makeMedication(startedAt: makeDate(year: 2_026, month: 1, day: 1))
        let log = makeDoseLog(takenAt: makeDate(year: 2_026, month: 1, day: 8))

        let summary = Glp1WeeklyCheckInPolicy.summary(
            medications: [medication],
            doseLogs: [log],
            now: makeDate(year: 2_026, month: 1, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(summary.status, .logged)
        XCTAssertEqual(summary.title, "GLP-1 checked in")
        XCTAssertEqual(summary.actionTitle, "Log dose")
        XCTAssertEqual(summary.daysSinceLastDose, 2)
        XCTAssertTrue(summary.message.contains("2 days ago"))
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }

    private func makeMedication(startedAt: Date) -> Glp1Medication {
        Glp1Medication(
            id: "medication",
            userId: "glp1-user",
            displayName: "Zepbound",
            genericName: "tirzepatide",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            isCompounded: false,
            hkIdentifier: "hk.glp1.tirzepatide.zepbound.weekly",
            startedAt: startedAt,
            endedAt: nil,
            notes: nil,
            createdAt: startedAt,
            updatedAt: startedAt
        )
    }

    private func makeDoseLog(takenAt: Date) -> Glp1DoseLog {
        Glp1DoseLog(
            id: "dose",
            userId: "glp1-user",
            takenAt: takenAt,
            medicationId: "medication",
            doseAmount: 5.0,
            doseUnit: "mg/week",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: nil,
            createdAt: takenAt,
            updatedAt: takenAt
        )
    }
}

final class Glp1DoseHistoryFormatterTests: XCTestCase {
    func testDoseTextRemovesUnneededDecimalZeros() {
        let log = makeDoseLog(amount: 2.50, unit: "mg/week")

        XCTAssertEqual(Glp1DoseHistoryFormatter.doseText(log), "2.5 mg/week")
    }

    func testDateTextUsesPlainRelativeLabelsForRecentDoses() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2_026,
            month: 6,
            day: 16,
            hour: 12
        ))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        XCTAssertEqual(Glp1DoseHistoryFormatter.dateText(now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(Glp1DoseHistoryFormatter.dateText(yesterday, now: now, calendar: calendar), "Yesterday")
    }

    func testDoseTextShowsRestDayForNoDoseRestLog() {
        let log = makeDoseLog(amount: nil, unit: nil, notes: "Rest day: traveling")

        XCTAssertEqual(Glp1DoseHistoryFormatter.doseText(log), "Rest day")
        XCTAssertTrue(Glp1DoseHistoryFormatter.isRestDay(log))
    }

    private func makeDoseLog(amount: Double?, unit: String?, notes: String? = nil) -> Glp1DoseLog {
        let now = Date()

        return Glp1DoseLog(
            id: "dose",
            userId: "glp1-user",
            takenAt: now,
            medicationId: "medication",
            doseAmount: amount,
            doseUnit: unit,
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: notes,
            createdAt: now,
            updatedAt: now
        )
    }
}

@MainActor
final class Glp1DoseCoreDataTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    func testDeletedDoseLogsAreHiddenButRemainPendingForSync() async throws {
        let userId = "glp1-delete-\(UUID().uuidString)"
        let log = makeDoseLog(userId: userId)

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([log], userId: userId, markAsSynced: true)
        let savedLogIds = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId).map(\.id)

        XCTAssertEqual(savedLogIds, [log.id])

        let deleted = await CoreDataManager.shared.markGlp1DoseLogDeleted(id: log.id, userId: userId)
        let visibleLogsAfterDelete = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)

        XCTAssertTrue(deleted)
        XCTAssertTrue(visibleLogsAfterDelete.isEmpty)

        let unsynced = await CoreDataManager.shared.fetchUnsyncedGlp1DoseLogs(for: userId)

        XCTAssertEqual(unsynced.count, 1)
        XCTAssertEqual(unsynced.first?.id, log.id)
        XCTAssertEqual(unsynced.first?.isMarkedDeleted, true)
        XCTAssertEqual(unsynced.first?.isSynced, false)
        XCTAssertEqual(unsynced.first?.syncStatus, "pending")
    }

    func testRemoteDoseRefreshDoesNotResurrectPendingDeletedLog() async throws {
        let userId = "glp1-tombstone-\(UUID().uuidString)"
        let log = makeDoseLog(userId: userId)

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([log], userId: userId, markAsSynced: true)

        let deleted = await CoreDataManager.shared.markGlp1DoseLogDeleted(id: log.id, userId: userId)
        XCTAssertTrue(deleted)

        let staleServerLog = Glp1DoseLog(
            id: log.id,
            userId: log.userId,
            takenAt: log.takenAt,
            medicationId: log.medicationId,
            doseAmount: log.doseAmount,
            doseUnit: log.doseUnit,
            drugClass: log.drugClass,
            brand: log.brand,
            isCompounded: log.isCompounded,
            supplierType: log.supplierType,
            supplierName: log.supplierName,
            notes: "stale server copy",
            createdAt: log.createdAt,
            updatedAt: log.updatedAt.addingTimeInterval(60)
        )

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([staleServerLog], userId: userId, markAsSynced: true)

        let visibleLogs = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)
        let unsynced = await CoreDataManager.shared.fetchUnsyncedGlp1DoseLogs(for: userId)

        XCTAssertTrue(visibleLogs.isEmpty)
        XCTAssertEqual(unsynced.count, 1)
        XCTAssertEqual(unsynced.first?.id, log.id)
        XCTAssertEqual(unsynced.first?.isMarkedDeleted, true)
        XCTAssertEqual(unsynced.first?.isSynced, false)
        XCTAssertEqual(unsynced.first?.syncStatus, "pending")
    }

    func testDoseLogNotesPersistThroughCoreData() async throws {
        let userId = "glp1-notes-\(UUID().uuidString)"
        let log = makeDoseLog(userId: userId, notes: "Left side injection")

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([log], userId: userId, markAsSynced: true)

        let saved = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.notes, "Left side injection")
    }

    private func makeDoseLog(userId: String, notes: String? = nil) -> Glp1DoseLog {
        let now = Date(timeIntervalSince1970: 1_735_000_000)

        return Glp1DoseLog(
            id: UUID().uuidString,
            userId: userId,
            takenAt: now,
            medicationId: "medication",
            doseAmount: 5.0,
            doseUnit: "mg/week",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: notes,
            createdAt: now,
            updatedAt: now
        )
    }
}

final class AuthSurfacePolicyTests: XCTestCase {
    func testAppleSignInShowsByDefaultForV1Launch() {
        XCTAssertTrue(AuthSurfacePolicy.defaultShowsAppleSignIn)
        XCTAssertTrue(AuthSurfacePolicy.shouldShowAppleSignIn())
    }

    func testEmailOTPRemainsPrimaryLaunchMethod() {
        XCTAssertEqual(AuthSurfacePolicy.primarySignInMethod, "email_otp")
    }
}

final class PaidWeightLoggerMVPPolicyTests: XCTestCase {
    func testWeightSaveRequiresValidInput() {
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(
                weightText: "",
                unit: "lbs",
                isSaving: false
            )
        )
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(
                weightText: "12",
                unit: "lbs",
                isSaving: false
            )
        )
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(
                weightText: "999",
                unit: "lbs",
                isSaving: false
            )
        )
        XCTAssertTrue(
            PaidWeightLoggerMVPPolicy.canSaveWeight(
                weightText: "182.4",
                unit: "lbs",
                isSaving: false
            )
        )
    }

    func testWeightValidationMessageExplainsInvalidRange() {
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.validationMessage(weightText: "12", unit: "lbs"),
            "Enter a weight between 70 and 660 lbs"
        )
        XCTAssertNil(
            PaidWeightLoggerMVPPolicy.validationMessage(weightText: "182.4", unit: "lbs")
        )
    }

    func testSyncStatusCopyAvoidsRawPendingState() {
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.syncStatusText(status: .idle, pendingCount: 1),
            "Pending sync"
        )
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.syncStatusText(status: .offline, pendingCount: 1),
            "Saved offline"
        )
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.syncStatusText(status: .error("No auth session"), pendingCount: 1),
            "Sync needs retry"
        )
    }
}

final class ValidationServiceTests: XCTestCase {
    func testWeightBoundariesAreInclusiveForPoundsAndKilograms() throws {
        let service = ValidationService.shared

        XCTAssertEqual(try service.validateWeight("70", unit: "lbs"), 70)
        XCTAssertEqual(try service.validateWeight("660", unit: "lbs"), 660)
        XCTAssertEqual(try service.validateWeight("32", unit: "kg"), 32)
        XCTAssertEqual(try service.validateWeight("300", unit: "kg"), 300)

        assertValidationError(
            try service.validateWeight("69.9", unit: "lbs"),
            expectedMessage: "Enter a weight between 70 and 660 lbs"
        )
        assertValidationError(
            try service.validateWeight("660.1", unit: "lbs"),
            expectedMessage: "Enter a weight between 70 and 660 lbs"
        )
        assertValidationError(
            try service.validateWeight("31.9", unit: "kg"),
            expectedMessage: "Enter a weight between 32 and 300 kg"
        )
        assertValidationError(
            try service.validateWeight("300.1", unit: "kg"),
            expectedMessage: "Enter a weight between 32 and 300 kg"
        )
    }

    func testBodyFatBoundariesAreInclusive() throws {
        let service = ValidationService.shared

        XCTAssertEqual(try service.validateBodyFat("3"), 3)
        XCTAssertEqual(try service.validateBodyFat("60"), 60)

        assertValidationError(
            try service.validateBodyFat("2.9"),
            expectedMessage: "Body fat must be between 3-60%"
        )
        assertValidationError(
            try service.validateBodyFat("60.1"),
            expectedMessage: "Body fat must be between 3-60%"
        )
    }

    func testRejectsBadNumericStrings() {
        let service = ValidationService.shared

        assertValidationError(
            try service.validateWeight("abc", unit: "lbs"),
            expectedMessage: "Please enter a valid number"
        )
        assertValidationError(
            try service.validateWeight("1..2", unit: "kg"),
            expectedMessage: "Please enter a valid number"
        )
        assertValidationError(
            try service.validateBodyFat("not a percentage"),
            expectedMessage: "Please enter a valid percentage"
        )
        assertValidationError(
            try service.validateBodyFat("5..0"),
            expectedMessage: "Please enter a valid percentage"
        )
    }

    private func assertValidationError<T>(
        _ expression: @autoclosure () throws -> T,
        expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual((error as? ValidationError)?.errorDescription, expectedMessage, file: file, line: line)
        }
    }
}

final class LogWeightFormValidatorTests: XCTestCase {
    func testRejectsOutOfRangeWeightValues() {
        let zeroPounds = LogWeightFormValidator.validate(weight: "0", bodyFat: "", unit: "lbs")
        XCTAssertFalse(zeroPounds.isValid)
        XCTAssertEqual(zeroPounds.weightError, "Enter a weight between 70 and 660 lbs")
        XCTAssertNil(zeroPounds.weightValue)

        let extremePounds = LogWeightFormValidator.validate(weight: "999", bodyFat: "", unit: "lbs")
        XCTAssertFalse(extremePounds.isValid)
        XCTAssertEqual(extremePounds.weightError, "Enter a weight between 70 and 660 lbs")
        XCTAssertNil(extremePounds.weightValue)
    }

    func testRejectsOutOfRangeBodyFatValues() {
        let tooLow = LogWeightFormValidator.validate(weight: "", bodyFat: "1", unit: "lbs")
        XCTAssertFalse(tooLow.isValid)
        XCTAssertEqual(tooLow.bodyFatError, "Body fat must be between 3-60%")
        XCTAssertNil(tooLow.bodyFatValue)

        let tooHigh = LogWeightFormValidator.validate(weight: "", bodyFat: "60.1", unit: "lbs")
        XCTAssertFalse(tooHigh.isValid)
        XCTAssertEqual(tooHigh.bodyFatError, "Body fat must be between 3-60%")
        XCTAssertNil(tooHigh.bodyFatValue)
    }

    func testAllowsValidWeightAndBodyFat() {
        let validation = LogWeightFormValidator.validate(weight: "175", bodyFat: "18", unit: "lbs")

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.weightValue, 175)
        XCTAssertEqual(validation.bodyFatValue, 18)
        XCTAssertNil(validation.weightError)
        XCTAssertNil(validation.bodyFatError)
        XCTAssertNil(validation.formError)
    }

    func testRequiresAtLeastOneMeasurement() {
        let validation = LogWeightFormValidator.validate(weight: " ", bodyFat: "", unit: "lbs")

        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.formError, "Please enter at least one measurement")
    }

    func testRoutesFieldAndSubmitValidationThroughValidationService() throws {
        let expectedWeight = try ValidationService.shared.validateWeight("175.04", unit: "lbs")
        let expectedBodyFat = try ValidationService.shared.validateBodyFat("18.04")

        let validation = LogWeightFormValidator.validate(weight: "175.04", bodyFat: "18.04", unit: "lbs")

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.weightValue, expectedWeight)
        XCTAssertEqual(validation.bodyFatValue, expectedBodyFat)
        XCTAssertNil(validation.weightError)
        XCTAssertNil(validation.bodyFatError)

        let expectedKgError = validationErrorDescription {
            _ = try ValidationService.shared.validateWeight("300.1", unit: "kg")
        }
        let expectedBodyFatError = validationErrorDescription {
            _ = try ValidationService.shared.validateBodyFat("60.1")
        }

        XCTAssertEqual(
            LogWeightFormValidator.fieldError(for: "300.1", field: .weight, unit: "kg"),
            expectedKgError
        )
        XCTAssertEqual(
            LogWeightFormValidator.fieldError(for: "60.1", field: .bodyFat, unit: "kg"),
            expectedBodyFatError
        )
    }

    private func validationErrorDescription(_ expression: () throws -> Void) -> String? {
        do {
            try expression()
            XCTFail("Expected validation to fail")
            return nil
        } catch let error as ValidationError {
            return error.errorDescription
        } catch {
            XCTFail("Unexpected error: \(error)")
            return nil
        }
    }
}

final class ProgressPhotoAttachPolicyTests: XCTestCase {
    func testProgressPhotoAttachStateCopyCoversCoreStates() {
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .empty), "Choose a photo")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .ready), "Ready to attach")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .processing), "Processing photo")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .success), "Photo added")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .permissionDenied), "Permission needed")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .failed("Upload failed")), "Photo failed")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusMessage(for: .failed("Upload failed")), "Upload failed")
    }

    func testProgressPhotoAttachTargetCopyDistinguishesAttachAndCreate() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.targetCopy(
                hasTargetMetric: true,
                targetDate: date
            ).hasPrefix("Attaches to")
        )
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.targetCopy(
                hasTargetMetric: false,
                targetDate: date
            ).hasPrefix("Adds to")
        )
    }

    func testProgressPhotoAttachCameraPolicyRequiresAvailableAuthorizedCamera() {
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: true,
                authorizationStatus: .authorized
            )
        )
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: true,
                authorizationStatus: .notDetermined
            )
        )
        XCTAssertFalse(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: false,
                authorizationStatus: .authorized
            )
        )
        XCTAssertFalse(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: true,
                authorizationStatus: .denied
            )
        )
    }

    func testProgressPhotoAttachBusyStateOnlyComesFromLocalProcessingStatus() {
        XCTAssertTrue(ProgressPhotoAttachPolicy.isBusy(status: .processing))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .empty))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .ready))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .success))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .failed("Upload failed")))
    }
}

final class HealthKitAuthorizationPolicyTests: XCTestCase {
    func testConfirmedReadAccessKeepsReadOnlyHealthKitAccessUsableWhenSharingIsDenied() {
        XCTAssertTrue(
            HealthKitAuthorizationPolicy.isAuthorized(
                writeStatus: .sharingDenied,
                hasConfirmedReadAccess: true
            )
        )
    }

    func testDeniedSharingWithoutConfirmedReadAccessIsNotAuthorized() {
        XCTAssertFalse(
            HealthKitAuthorizationPolicy.isAuthorized(
                writeStatus: .sharingDenied,
                hasConfirmedReadAccess: false
            )
        )
    }

    func testShareAuthorizationIsEnoughWithoutStoredPromptState() {
        XCTAssertTrue(
            HealthKitAuthorizationPolicy.isAuthorized(
                writeStatus: .sharingAuthorized,
                hasConfirmedReadAccess: false
            )
        )
    }

    func testUndeterminedStatusWithoutCompletedRequestIsNotAuthorized() {
        XCTAssertFalse(
            HealthKitAuthorizationPolicy.isAuthorized(
                writeStatus: .notDetermined,
                hasConfirmedReadAccess: false
            )
        )
    }
}

final class HealthKitFullSyncCompletionPolicyTests: XCTestCase {
    func testFullSyncCompletionIsOnlyMarkedAfterSuccessfulImport() {
        XCTAssertTrue(
            HealthKitFullSyncCompletionPolicy.shouldMarkCompleted(importSucceeded: true)
        )
        XCTAssertFalse(
            HealthKitFullSyncCompletionPolicy.shouldMarkCompleted(importSucceeded: false)
        )
    }
}

final class PhotoUploadBatchPolicyTests: XCTestCase {
    func testPhotoUploadBatchProgressHandlesEmptyAndCompletedCounts() {
        XCTAssertEqual(PhotoUploadBatchPolicy.progress(completedCount: 0, totalCount: 0), 0)
        XCTAssertEqual(PhotoUploadBatchPolicy.progress(completedCount: 1, totalCount: 4), 0.25)
        XCTAssertEqual(PhotoUploadBatchPolicy.progress(completedCount: 4, totalCount: 4), 1.0)
    }

    func testPhotoUploadBatchProgressTextCapsCurrentIndexAtTotal() {
        XCTAssertEqual(PhotoUploadBatchPolicy.progressText(processedCount: 0, totalCount: 0), "Processing photos")
        XCTAssertEqual(PhotoUploadBatchPolicy.progressText(processedCount: 0, totalCount: 3), "Processing 1 of 3")
        XCTAssertEqual(PhotoUploadBatchPolicy.progressText(processedCount: 3, totalCount: 3), "Processing 3 of 3")
    }

    func testPhotoUploadBatchSelectionCannotChangeWhileProcessing() {
        XCTAssertTrue(PhotoUploadBatchPolicy.canChangeSelection(isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canChangeSelection(isProcessing: true))
    }

    func testPhotoUploadBatchStartsOnlyWhenIdleWithSelection() {
        XCTAssertTrue(PhotoUploadBatchPolicy.canStartUpload(selectedCount: 1, isSaving: false, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canStartUpload(selectedCount: 0, isSaving: false, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canStartUpload(selectedCount: 1, isSaving: true, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canStartUpload(selectedCount: 1, isSaving: false, isProcessing: true))
    }

    func testPhotoUploadBatchDismissesOnlyWhenIdle() {
        XCTAssertTrue(PhotoUploadBatchPolicy.canDismiss(isSaving: false, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canDismiss(isSaving: true, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canDismiss(isSaving: false, isProcessing: true))
    }

    func testPhotoUploadBatchDismissesOnlyAfterAllSelectedPhotosUpload() {
        XCTAssertTrue(PhotoUploadBatchPolicy.shouldDismissAfterUpload(successfulCount: 3, totalCount: 3))
        XCTAssertFalse(PhotoUploadBatchPolicy.shouldDismissAfterUpload(successfulCount: 2, totalCount: 3))
        XCTAssertFalse(PhotoUploadBatchPolicy.shouldDismissAfterUpload(successfulCount: 0, totalCount: 0))
    }

    func testPhotoUploadBatchFailureMessageDistinguishesPartialAndFullFailure() {
        XCTAssertEqual(
            PhotoUploadBatchPolicy.uploadFailureMessage(successfulCount: 0, totalCount: 2),
            "Photo upload failed. Please try again."
        )
        XCTAssertEqual(
            PhotoUploadBatchPolicy.uploadFailureMessage(successfulCount: 2, totalCount: 3),
            "Uploaded 2 of 3 photos. 1 photo failed. Try again."
        )
    }
}

final class EditEntrySavePolicyTests: XCTestCase {
    func testEditEntryCanRetryAfterPreviousErrorWhenCurrentValueIsValid() {
        XCTAssertTrue(EditEntrySavePolicy.canAttemptSave(
            isSaving: false,
            validationMessage: nil,
            value: "20"
        ))
    }

    func testEditEntrySaveIsBlockedForCurrentValidationErrorSavingOrBlankValue() {
        XCTAssertFalse(EditEntrySavePolicy.canAttemptSave(
            isSaving: false,
            validationMessage: "Enter percentage between 3 and 60",
            value: "99"
        ))
        XCTAssertFalse(EditEntrySavePolicy.canAttemptSave(
            isSaving: true,
            validationMessage: nil,
            value: "20"
        ))
        XCTAssertFalse(EditEntrySavePolicy.canAttemptSave(
            isSaving: false,
            validationMessage: nil,
            value: "   "
        ))
    }
}

@MainActor
final class BodyMetricPhotoUpdateTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    func testUpdateBodyMetricPhotoMarksMetricPendingInsideContext() async throws {
        let userId = "photo_update_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_766_000_000)
        let metric = makePhotoUpdateMetric(id: metricId, userId: userId, date: date)

        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: userId, markAsSynced: true)

        let didUpdate = try await CoreDataManager.shared.updateBodyMetricPhoto(
            id: metricId,
            userId: userId,
            storagePath: "\(userId)/\(metricId).png",
            processedUrl: "https://cdn.example.com/\(metricId).png"
        )

        XCTAssertTrue(didUpdate)

        let updated = try await cachedPhotoState(metricId: metricId)
        XCTAssertEqual(updated.photoUrl, "https://cdn.example.com/\(metricId).png")
        XCTAssertEqual(updated.originalPhotoUrl, "\(userId)/\(metricId).png")
        XCTAssertFalse(updated.isSynced)
        XCTAssertEqual(updated.syncStatus, "pending")
    }

    func testUpdateBodyMetricPhotoDoesNotCrossUsers() async throws {
        let ownerId = "photo_owner_\(UUID().uuidString)"
        let otherUserId = "photo_other_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_766_100_000)
        let metric = makePhotoUpdateMetric(id: metricId, userId: ownerId, date: date)

        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: ownerId, markAsSynced: true)

        let didUpdate = try await CoreDataManager.shared.updateBodyMetricPhoto(
            id: metricId,
            userId: otherUserId,
            storagePath: "\(otherUserId)/\(metricId).png",
            processedUrl: "https://cdn.example.com/wrong-user.png"
        )

        XCTAssertFalse(didUpdate)

        let updated = try await cachedPhotoState(metricId: metricId)
        XCTAssertNil(updated.photoUrl)
        XCTAssertNil(updated.originalPhotoUrl)
        XCTAssertTrue(updated.isSynced)
        XCTAssertEqual(updated.syncStatus, "synced")
    }

    private func makePhotoUpdateMetric(id: String, userId: String, date: Date) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 81.2,
            weightUnit: "kg",
            bodyFatPercentage: 16.4,
            bodyFatMethod: "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date,
            updatedAt: date
        )
    }

    private func cachedPhotoState(metricId: String) async throws -> (
        photoUrl: String?,
        originalPhotoUrl: String?,
        isSynced: Bool,
        syncStatus: String?
    ) {
        let context = CoreDataManager.shared.viewContext

        return try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", metricId)
            request.fetchLimit = 1

            guard let metric = try context.fetch(request).first else {
                throw CoreDataPhotoUpdateTestError.missingMetric
            }

            return (
                metric.photoUrl,
                metric.originalPhotoUrl,
                metric.isSynced,
                metric.syncStatus
            )
        }
    }

    private enum CoreDataPhotoUpdateTestError: Error {
        case missingMetric
    }
}

final class PhotoMetadataServiceTests: XCTestCase {
    func testCreateOrUpdateMetricsPreservesExistingMeasurementsForFirstPhotoBaseline() async throws {
        let userId = "photo_baseline_existing_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_764_000_000)
        let existing = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: 18.0,
            bodyFatMethod: "HealthKit",
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "Imported from HealthKit",
            photoUrl: nil,
            dataSource: BodyMetricSource.healthKit.rawValue,
            createdAt: date,
            updatedAt: date
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(existing, userId: userId)

        let updated = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            photoUrl: "file:///first-photo.jpg",
            weight: 77.0,
            bodyFatPercentage: 14.0,
            userId: userId,
            dataSource: BodyMetricSource.manual.rawValue,
            preserveExistingMeasurements: true
        )

        XCTAssertEqual(updated.id, existing.id)
        XCTAssertEqual(updated.weight, 80.0)
        XCTAssertEqual(updated.bodyFatPercentage, 18.0)
        XCTAssertEqual(updated.bodyFatMethod, "HealthKit")
        XCTAssertEqual(updated.dataSource, BodyMetricSource.healthKit.rawValue)
        XCTAssertEqual(updated.photoUrl, "file:///first-photo.jpg")
    }

    func testCreateOrUpdateMetricsAssignsDataSourceForNewFirstPhotoBaseline() async {
        let userId = "photo_baseline_new_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_000_000)

        let created = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            weight: 79.5,
            bodyFatPercentage: 16.5,
            userId: userId,
            dataSource: BodyMetricSource.manual.rawValue,
            preserveExistingMeasurements: true
        )

        XCTAssertEqual(created.weight, 79.5)
        XCTAssertEqual(created.bodyFatPercentage, 16.5)
        XCTAssertEqual(created.dataSource, BodyMetricSource.manual.rawValue)
        XCTAssertNil(created.photoUrl)
    }

    func testCreateOrUpdateMetricsDefaultsNewManualMeasurementsToManualSource() async {
        let userId = "manual_entry_default_source_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_100_000)

        let weightEntry = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            weight: 82.4,
            userId: userId
        )

        let bodyFatEntry = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date.addingTimeInterval(86_400),
            bodyFatPercentage: 17.1,
            userId: userId
        )

        XCTAssertEqual(weightEntry.dataSource, BodyMetricSource.manual.rawValue)
        XCTAssertEqual(bodyFatEntry.dataSource, BodyMetricSource.manual.rawValue)
    }

    func testCreateOrUpdateMetricsKeepsPhotoDefaultForPhotoOnlyPlaceholder() async {
        let userId = "photo_entry_default_source_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_200_000)

        let photoEntry = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            userId: userId
        )

        XCTAssertEqual(photoEntry.dataSource, BodyMetricSource.photo.rawValue)
        XCTAssertNil(photoEntry.weight)
        XCTAssertNil(photoEntry.bodyFatPercentage)
    }
}

final class BulkProgressPhotoImportPolicyTests: XCTestCase {
    func testBulkProgressPhotoImportRequiresActivationEvidence() {
        XCTAssertFalse(BulkProgressPhotoImportPolicy.defaultShowsBulkImport)
        XCTAssertFalse(
            BulkProgressPhotoImportPolicy.shouldShowBulkImport(
                existingProgressPhotoCount: 0
            )
        )
    }

    func testBulkProgressPhotoImportUnlocksAfterActivationEvidence() {
        XCTAssertFalse(
            BulkProgressPhotoImportPolicy.shouldShowBulkImport(
                existingProgressPhotoCount: BulkProgressPhotoImportPolicy.activationProgressPhotoCount - 1
            )
        )
        XCTAssertTrue(
            BulkProgressPhotoImportPolicy.shouldShowBulkImport(
                existingProgressPhotoCount: BulkProgressPhotoImportPolicy.activationProgressPhotoCount
            )
        )
    }

    func testBulkProgressPhotoImportFooterExplainsLockedAndEnabledStates() {
        XCTAssertEqual(
            BulkProgressPhotoImportPolicy.footerText(isEnabled: false, existingProgressPhotoCount: 0),
            "Bulk import unlocks after you have added progress photos or request migration access."
        )
        XCTAssertEqual(
            BulkProgressPhotoImportPolicy.footerText(isEnabled: false, existingProgressPhotoCount: 1),
            "Bulk import unlocks after one more added progress photo or migration access."
        )
        XCTAssertEqual(
            BulkProgressPhotoImportPolicy.footerText(isEnabled: true, existingProgressPhotoCount: 0),
            "Import progress photos from your photo library."
        )
    }
}

final class BodyMetricSourceContractTests: XCTestCase {
    func testSourceNormalizationCoversLaunchImportSources() {
        XCTAssertEqual(BodyMetricSource.normalizedRawValue(nil), "manual")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("Manual"), "manual")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("HealthKit"), "healthkit")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("smart scale"), "smart_scale")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("partner:bodyspec"), "bodyspec_dexa")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("skinfold caliper"), "caliper")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("Photo Import"), "photo")
    }

    func testSourceMetadataTrimsEmptyValuesAndSerializesPointersOnly() throws {
        let metadata = BodyMetricSourceMetadata(
            vendor: " BodySpec ",
            sourceName: "",
            deviceModel: "Scanner X",
            externalResultId: " result-123 "
        )

        let jsonString = try XCTUnwrap(metadata.jsonString)
        let decoded = try XCTUnwrap(BodyMetricSourceMetadata(jsonString: jsonString))

        XCTAssertEqual(decoded.vendor, "BodySpec")
        XCTAssertNil(decoded.sourceName)
        XCTAssertEqual(decoded.deviceModel, "Scanner X")
        XCTAssertEqual(decoded.externalResultId, "result-123")
        XCTAssertEqual(decoded.jsonObject["vendor"], "BodySpec")
    }
}

final class BodyMetricLocalDateContractTests: XCTestCase {
    func testLocalDateCapturesDeviceCalendarDayNearMidnight() throws {
        let losAngeles = try makeCalendar(timeZoneIdentifier: "America/Los_Angeles")
        let newYork = try makeCalendar(timeZoneIdentifier: "America/New_York")

        let losAngelesLateNight = try makeDate(
            year: 2_026,
            month: 6,
            day: 9,
            hour: 23,
            minute: 58,
            calendar: losAngeles
        )
        let newYorkLateNight = try makeDate(
            year: 2_026,
            month: 6,
            day: 9,
            hour: 23,
            minute: 58,
            calendar: newYork
        )

        XCTAssertEqual(BodyMetricLocalDate.key(for: losAngelesLateNight, calendar: losAngeles), "2026-06-09")
        XCTAssertEqual(BodyMetricLocalDate.key(for: newYorkLateNight, calendar: newYork), "2026-06-09")
        XCTAssertEqual(BodyMetricLocalDate.key(for: losAngelesLateNight, calendar: newYork), "2026-06-10")
    }

    func testLocalDateCaptures2358AcrossUtcOffsetRange() throws {
        for offsetHours in -12...14 {
            let calendar = try makeCalendar(secondsFromGMT: offsetHours * 3_600)
            let lateNight = try makeDate(
                year: 2_026,
                month: 6,
                day: 9,
                hour: 23,
                minute: 58,
                calendar: calendar
            )
            let label = offsetHours >= 0 ? "UTC+\(offsetHours)" : "UTC\(offsetHours)"

            XCTAssertEqual(
                BodyMetricLocalDate.key(for: lateNight, calendar: calendar),
                "2026-06-09",
                "\(label) should keep the user's 23:58 local calendar day"
            )

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lateNight)
            XCTAssertEqual(components.year, 2_026, label)
            XCTAssertEqual(components.month, 6, label)
            XCTAssertEqual(components.day, 9, label)
            XCTAssertEqual(components.hour, 23, label)
            XCTAssertEqual(components.minute, 58, label)
        }
    }

    func testStartOfDayUsesStoredLocalDateAfterTimezoneChange() throws {
        let tokyo = try makeCalendar(timeZoneIdentifier: "Asia/Tokyo")
        let startOfDay = try XCTUnwrap(BodyMetricLocalDate.startOfDay(for: "2026-06-09", calendar: tokyo))
        let components = tokyo.dateComponents([.year, .month, .day], from: startOfDay)

        XCTAssertEqual(components.year, 2_026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 9)
    }

    func testBodyMetricsRoundTripsLocalDateToSupabaseKey() throws {
        let calendar = try makeCalendar(timeZoneIdentifier: "America/Los_Angeles")
        let loggedAt = try makeDate(year: 2_026, month: 6, day: 9, hour: 23, minute: 58, calendar: calendar)
        let metric = makeMetric(date: loggedAt, localDate: "2026-06-09")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metric)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["local_date"] as? String, "2026-06-09")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BodyMetrics.self, from: data)

        XCTAssertEqual(decoded.localDate, "2026-06-09")
    }

    func testBodyMetricsFallbackNormalizesInvalidLocalDate() throws {
        let calendar = try makeCalendar(timeZoneIdentifier: "America/Los_Angeles")
        let loggedAt = try makeDate(year: 2_026, month: 6, day: 9, hour: 23, minute: 58, calendar: calendar)
        let metric = makeMetric(date: loggedAt, localDate: "not-a-date")

        XCTAssertEqual(metric.localDate, BodyMetricLocalDate.key(for: loggedAt))
    }

    func testVisibilityConflictResolutionCollapsesSameStoredLocalDay() throws {
        let userId = "local-date-user"
        let older = makeMetric(
            id: "older",
            userId: userId,
            date: try makeDate(
                year: 2_026,
                month: 6,
                day: 9,
                hour: 23,
                minute: 58,
                calendar: makeCalendar(timeZoneIdentifier: "America/Los_Angeles")
            ),
            localDate: "2026-06-09",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeMetric(
            id: "newer",
            userId: userId,
            date: try makeDate(
                year: 2_026,
                month: 6,
                day: 10,
                hour: 1,
                minute: 15,
                calendar: makeCalendar(timeZoneIdentifier: "America/New_York")
            ),
            localDate: "2026-06-09",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let visible = EntryVisibilityManager.shared.resolvedVisibleMetrics([older, newer], userId: userId)

        XCTAssertEqual(visible.map(\.id), ["newer"])
    }

    private func makeMetric(
        id: String = UUID().uuidString,
        userId: String = "user",
        date: Date,
        localDate: String?,
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            localDate: localDate,
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func makeCalendar(timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier))
        return calendar
    }

    private func makeCalendar(secondsFromGMT: Int) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: secondsFromGMT))
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: calendar.timeZone,
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}

@MainActor
final class OnboardingFlowViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OnboardingStateManager.shared.updateCompletionStatus(false)
    }

    override func tearDown() {
        OnboardingStateManager.shared.updateCompletionStatus(false)
        super.tearDown()
    }

    func testAdvanceAfterHealthConfirmationSkipsToLoadingWhenMetricsExist() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 185, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .healthKit)
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .loading)
    }

    func testPersistedProgressRestoresDefaultHomeModeChoice() {
        let userId = "onboarding-default-mode-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated
        let previousDefaultHomeMode = UserDefaults.standard.string(forKey: Constants.defaultHomeModeKey)

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            if let previousDefaultHomeMode {
                UserDefaults.standard.set(previousDefaultHomeMode, forKey: Constants.defaultHomeModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.defaultHomeModeKey)
            }
            OnboardingProgressStore.shared.clearProgress(for: userId)
        }

        AuthManager.shared.currentUser = User(
            id: userId,
            email: "default-mode@example.com",
            name: "Default Mode"
        )
        AuthManager.shared.isAuthenticated = true
        UserDefaults.standard.set(DefaultHomeMode.avatar.rawValue, forKey: Constants.defaultHomeModeKey)

        let viewModel = OnboardingFlowViewModel()
        viewModel.currentStep = .defaultHomeMode
        viewModel.updateDefaultHomeMode(.photo)

        let savedSnapshot = OnboardingProgressStore.shared.snapshotForTesting(for: userId)
        XCTAssertEqual(savedSnapshot?.currentStep, .defaultHomeMode)
        XCTAssertEqual(savedSnapshot?.defaultHomeMode, .photo)

        UserDefaults.standard.set(DefaultHomeMode.avatar.rawValue, forKey: Constants.defaultHomeModeKey)
        let restoredViewModel = OnboardingFlowViewModel()

        XCTAssertEqual(restoredViewModel.currentStep, .defaultHomeMode)
        XCTAssertEqual(restoredViewModel.defaultHomeMode, .photo)
    }

    func testAuthenticatedFlowConsumesPreAuthDefaultHomeModeChoice() {
        let userId = "preauth-default-mode-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated
        let previousDefaultHomeMode = UserDefaults.standard.string(forKey: Constants.defaultHomeModeKey)

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            if let previousDefaultHomeMode {
                UserDefaults.standard.set(previousDefaultHomeMode, forKey: Constants.defaultHomeModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.defaultHomeModeKey)
            }
            OnboardingProgressStore.shared.clearProgress(for: userId)
            PreAuthOnboardingStore.shared.clear()
        }

        PreAuthOnboardingStore.shared.clear()
        AuthManager.shared.currentUser = User(
            id: userId,
            email: "preauth-default-mode@example.com",
            name: "Pre Auth"
        )
        AuthManager.shared.isAuthenticated = true
        UserDefaults.standard.set(DefaultHomeMode.avatar.rawValue, forKey: Constants.defaultHomeModeKey)

        let input = BodyScoreInput(
            sex: .male,
            birthYear: 1_990,
            height: HeightValue(value: 70, unit: .inches),
            weight: WeightValue(value: 185, unit: .pounds),
            bodyFat: BodyFatValue(percentage: 18, source: .manualValue)
        )
        let result = BodyScoreResult(
            score: 82,
            ffmi: 21.4,
            leanPercentile: 0.72,
            ffmiStatus: "Strong",
            targetBodyFat: .init(lowerBound: 10, upperBound: 15, label: "Athletic"),
            statusTagline: "Strong base"
        )

        PreAuthOnboardingStore.shared.save(
            input: input,
            result: result,
            defaultHomeMode: .photo
        )

        let viewModel = OnboardingFlowViewModel()

        XCTAssertEqual(viewModel.currentStep, .profileDetails)
        XCTAssertEqual(viewModel.bodyScoreInput, input)
        XCTAssertEqual(viewModel.bodyScoreResult, result)
        XCTAssertEqual(viewModel.defaultHomeMode, .photo)
        XCTAssertEqual(UserDefaults.standard.string(forKey: Constants.defaultHomeModeKey), DefaultHomeMode.photo.rawValue)

        let savedSnapshot = OnboardingProgressStore.shared.snapshotForTesting(for: userId)
        XCTAssertEqual(savedSnapshot?.currentStep, .profileDetails)
        XCTAssertEqual(savedSnapshot?.defaultHomeMode, .photo)
        XCTAssertNil(PreAuthOnboardingStore.shared.load())
    }

    func testPersistedProgressRestoresProfileDetailsDraft() throws {
        let userId = "onboarding-profile-draft-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated
        let dateOfBirth = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 1_992, month: 7, day: 4))
        )

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            OnboardingProgressStore.shared.clearProgress(for: userId)
        }

        let initialUser = User(
            id: userId,
            email: "profile-draft@example.com",
            name: "Seed User"
        )
        AuthManager.shared.currentUser = initialUser
        AuthManager.shared.isAuthenticated = true

        let viewModel = OnboardingFlowViewModel()
        viewModel.currentStep = .profileDetails
        viewModel.hydrateProfileDetailsDraftIfNeeded(from: initialUser)
        viewModel.profileFirstName = "Avery"
        viewModel.profileLastName = "Stone"
        viewModel.profileDateOfBirth = dateOfBirth
        viewModel.updateProfileBiologicalSex(.female)
        viewModel.profileHeightUnit = .inches
        viewModel.profileHeightFeet = 5
        viewModel.profileHeightInches = 7
        viewModel.profileHeightCentimetersText = "170"
        viewModel.profileDetailsActiveSubstep = .height

        let savedSnapshot = OnboardingProgressStore.shared.snapshotForTesting(for: userId)
        XCTAssertEqual(savedSnapshot?.currentStep, .profileDetails)
        XCTAssertEqual(savedSnapshot?.profileFirstName, "Avery")
        XCTAssertEqual(savedSnapshot?.profileLastName, "Stone")
        XCTAssertEqual(savedSnapshot?.profileDateOfBirth, dateOfBirth)
        XCTAssertEqual(savedSnapshot?.profileBiologicalSex, .female)
        XCTAssertEqual(savedSnapshot?.profileHeightUnit, .inches)
        XCTAssertEqual(savedSnapshot?.profileHeightFeet, 5)
        XCTAssertEqual(savedSnapshot?.profileHeightInches, 7)
        XCTAssertEqual(savedSnapshot?.profileDetailsActiveSubstep, .height)

        let restoredViewModel = OnboardingFlowViewModel()

        XCTAssertEqual(restoredViewModel.currentStep, .profileDetails)
        XCTAssertEqual(restoredViewModel.profileFirstName, "Avery")
        XCTAssertEqual(restoredViewModel.profileLastName, "Stone")
        XCTAssertEqual(restoredViewModel.profileDateOfBirth, dateOfBirth)
        XCTAssertEqual(restoredViewModel.profileBiologicalSex, .female)
        XCTAssertEqual(restoredViewModel.profileHeightUnit, .inches)
        XCTAssertEqual(restoredViewModel.profileHeightFeet, 5)
        XCTAssertEqual(restoredViewModel.profileHeightInches, 7)
        XCTAssertEqual(restoredViewModel.profileHeightCentimetersText, "170")
        XCTAssertEqual(restoredViewModel.profileDetailsActiveSubstep, .height)

        let laterUserSnapshot = User(
            id: userId,
            email: "profile-draft@example.com",
            name: "Server Override"
        )
        restoredViewModel.hydrateProfileDetailsDraftIfNeeded(from: laterUserSnapshot)

        XCTAssertEqual(restoredViewModel.profileFirstName, "Avery")
        XCTAssertEqual(restoredViewModel.profileLastName, "Stone")
        XCTAssertEqual(restoredViewModel.profileDetailsActiveSubstep, .height)
    }

    func testAdvanceAfterHealthConfirmationRequestsBodyFatWhenMissing() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 185, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue()
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .bodyFatChoice)
    }

    func testAdvanceAfterHealthConfirmationRequiresWeightWhenMissing() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue()
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .healthKit)
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .manualWeight)
    }

    func testManualWeightStepContinuesToBodyFatChoiceWhenNeeded() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 180, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue()
        viewModel.currentStep = .manualWeight

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .bodyFatChoice)
    }

    func testManualWeightStepSkipsBodyFatWhenAlreadyEntered() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 180, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 17.5, source: .manualValue)
        viewModel.currentStep = .manualWeight

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .loading)
    }

    func testProfileDetailsAdvancesToFirstPhotoWhenEnabled() {
        let viewModel = OnboardingFlowViewModel(includesFirstPhotoStep: true)
        viewModel.currentStep = .profileDetails

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .firstPhoto)
        XCTAssertFalse(OnboardingStateManager.shared.hasCompletedCurrentVersion)
    }

    func testProfileCompletionGateSkipsFirstPhotoOnSubmit() {
        let viewModel = ProfileCompletionGatePolicy.makeViewModel()

        XCTAssertFalse(viewModel.includesFirstPhotoStep)
    }

    func testProfileDetailsCompletesOnboardingWhenFirstPhotoDisabled() async {
        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: false,
            profileUpdateHandler: { _ in }
        )
        viewModel.currentStep = .profileDetails

        await viewModel.finishOnboardingAndShowPaywall()

        XCTAssertEqual(viewModel.currentStep, .paywall)
        XCTAssertTrue(OnboardingStateManager.shared.hasCompletedCurrentVersion)
    }

    func testProfileDetailsDoesNotCompleteWhenDurableProfileWriteFails() async {
        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: false,
            profileUpdateHandler: { _ in throw SupabaseError.requestFailed }
        )
        viewModel.currentStep = .profileDetails

        await viewModel.finishOnboardingAndShowPaywall()

        XCTAssertEqual(viewModel.currentStep, .profileDetails)
        XCTAssertFalse(OnboardingStateManager.shared.hasCompletedCurrentVersion)
        XCTAssertEqual(
            viewModel.errorMessage,
            "We couldn't save your setup. Check your connection and try again."
        )
    }

    func testFirstPhotoStepCanCompleteToPaywall() async {
        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: true,
            profileUpdateHandler: { _ in }
        )
        viewModel.currentStep = .firstPhoto

        await viewModel.completeFirstPhotoStep()

        XCTAssertEqual(viewModel.currentStep, .paywall)
        XCTAssertTrue(OnboardingStateManager.shared.hasCompletedCurrentVersion)
    }

    func testFirstPhotoStepDoesNotAdvanceDuringConcurrentCompletionSave() async {
        var releaseSave: CheckedContinuation<Void, Never>?
        var updateAttempts = 0
        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: true,
            profileUpdateHandler: { _ in
                updateAttempts += 1
                await withCheckedContinuation { continuation in
                    releaseSave = continuation
                }
                throw SupabaseError.requestFailed
            }
        )
        viewModel.currentStep = .firstPhoto

        let firstCompletion = Task {
            await viewModel.completeFirstPhotoStep()
        }
        while releaseSave == nil {
            await Task.yield()
        }

        await viewModel.completeFirstPhotoStep()

        XCTAssertEqual(updateAttempts, 1)
        XCTAssertEqual(viewModel.currentStep, .firstPhoto)
        XCTAssertTrue(viewModel.isCompletingOnboarding)
        XCTAssertFalse(OnboardingStateManager.shared.hasCompletedCurrentVersion)

        releaseSave?.resume()
        await firstCompletion.value

        XCTAssertEqual(updateAttempts, 1)
        XCTAssertEqual(viewModel.currentStep, .firstPhoto)
        XCTAssertFalse(viewModel.isCompletingOnboarding)
        XCTAssertFalse(OnboardingStateManager.shared.hasCompletedCurrentVersion)
        XCTAssertEqual(
            viewModel.firstPhotoErrorMessage,
            "We couldn't save your setup. Check your connection and try again."
        )
    }

    func testFirstPhotoCompletionMarksLocalUserComplete() async {
        let userId = "onboarding-first-photo-complete-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            OnboardingProgressStore.shared.clearProgress(for: userId)
        }

        AuthManager.shared.currentUser = User(
            id: userId,
            email: "first-photo-complete@example.com",
            name: "First Photo",
            profile: UserProfile(
                id: userId,
                email: "first-photo-complete@example.com",
                username: nil,
                fullName: "First Photo",
                dateOfBirth: nil,
                height: nil,
                heightUnit: nil,
                gender: nil,
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: nil,
                onboardingCompleted: false
            ),
            onboardingCompleted: false
        )
        AuthManager.shared.isAuthenticated = true

        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: true,
            profileUpdateHandler: { _ in }
        )
        viewModel.currentStep = .firstPhoto

        await viewModel.completeFirstPhotoStep()

        XCTAssertEqual(viewModel.currentStep, .paywall)
        XCTAssertTrue(OnboardingStateManager.shared.hasCompletedCurrentVersion)
        XCTAssertTrue(AuthManager.shared.currentUser?.onboardingCompleted == true)
        XCTAssertEqual(AuthManager.shared.currentUser?.profile?.onboardingCompleted, true)
        XCTAssertNil(OnboardingProgressStore.shared.snapshotForTesting(for: userId))
    }

    func testProfileCompletionSyncPersistsCurrentOnboardingVersion() {
        let suiteName = "onboarding-profile-sync-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 2)

        manager.syncCompletionFlagFromProfile(true)

        XCTAssertTrue(manager.hasCompletedCurrentVersion)
        XCTAssertEqual(defaults.integer(forKey: Constants.onboardingCompletedVersionKey), 2)
    }

    func testProfileCompletionSyncIgnoresStaleFalseForSameCompletedUser() {
        let suiteName = "onboarding-profile-stale-false-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 1)

        manager.markCompleted(userId: "same-user")
        manager.syncCompletionFlagFromProfile(false, userId: "same-user")

        XCTAssertTrue(manager.hasCompletedCurrentVersion)
        XCTAssertTrue(manager.hasCompletedCurrentVersion(for: "same-user"))
        XCTAssertEqual(defaults.string(forKey: Constants.onboardingCompletedUserIdKey), "same-user")
    }

    func testCompletionUpdateIgnoresUnauthenticatedFalseForCompletedUser() {
        let suiteName = "onboarding-auth-refresh-false-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 1)

        manager.markCompleted(userId: "same-user")
        manager.updateCompletionStatus(false)

        XCTAssertTrue(manager.hasCompletedCurrentVersion)
        XCTAssertTrue(manager.hasCompletedCurrentVersion(for: "same-user"))
        XCTAssertEqual(defaults.string(forKey: Constants.onboardingCompletedUserIdKey), "same-user")
        XCTAssertEqual(defaults.integer(forKey: Constants.onboardingCompletedVersionKey), 1)
    }

    func testProfileCompletionSyncClearsInheritedCompletionForDifferentUser() {
        let suiteName = "onboarding-profile-user-switch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 1)

        manager.markCompleted(userId: "previous-user")
        XCTAssertFalse(manager.hasCompletedCurrentVersion(for: "new-user"))

        manager.syncCompletionFlagFromProfile(false, userId: "new-user")

        XCTAssertFalse(manager.hasCompletedCurrentVersion)
        XCTAssertFalse(manager.hasCompletedCurrentVersion(for: "previous-user"))
        XCTAssertNil(defaults.string(forKey: Constants.onboardingCompletedUserIdKey))
    }

    func testFirstPhotoBackNavigationAndPaywallBackNavigation() {
        let viewModel = OnboardingFlowViewModel(includesFirstPhotoStep: true)
        viewModel.currentStep = .firstPhoto

        viewModel.goBack()
        XCTAssertEqual(viewModel.currentStep, .profileDetails)

        viewModel.currentStep = .paywall
        viewModel.goBack()
        XCTAssertEqual(viewModel.currentStep, .firstPhoto)
    }

    func testFirstPhotoProgressOnlyAppearsWhenEnabled() {
        let enabledViewModel = OnboardingFlowViewModel(includesFirstPhotoStep: true)
        let disabledViewModel = OnboardingFlowViewModel(includesFirstPhotoStep: false)

        XCTAssertNotNil(enabledViewModel.progress(for: .firstPhoto))
        XCTAssertNil(disabledViewModel.progress(for: .firstPhoto))
    }

    func testBuildOnboardingProfileUpdatesIncludesGenderDobAndHeight() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.updateSex(.female)
        viewModel.updateBirthYear(1_990)
        viewModel.bodyScoreInput.height = HeightValue(value: 180, unit: .centimeters)
        viewModel.setHeightUnit(.centimeters)

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["gender"] as? String, "Female")

        let dateOfBirth = updates["dateOfBirth"] as? Date
        XCTAssertNotNil(dateOfBirth)

        if let dateOfBirth {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: dateOfBirth)
            XCTAssertEqual(components.year, 1_990)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 1)
        }

        let height = updates["height"] as? Double
        XCTAssertNotNil(height)
        if let height {
            XCTAssertEqual(height, 180.0, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "cm")
        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testBuildOnboardingProfileUpdatesRespectsImperialHeightUnit() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.height = HeightValue(value: 72, unit: .inches)
        viewModel.setHeightUnit(.inches)

        let updates = viewModel.buildOnboardingProfileUpdates()

        let height = updates["height"] as? Double
        XCTAssertNotNil(height)
        if let height {
            XCTAssertEqual(height, 72 * 2.54, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "in")
    }

    func testBuildOnboardingProfileUpdatesPrefersPersistedProfileDetailsDraft() throws {
        let userId = "onboarding-profile-update-draft-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated
        let profileDateOfBirth = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 1_991, month: 3, day: 22))
        )

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            OnboardingProgressStore.shared.clearProgress(for: userId)
        }

        let user = User(
            id: userId,
            email: "profile-update-draft@example.com",
            name: "Profile Draft"
        )
        AuthManager.shared.currentUser = user
        AuthManager.shared.isAuthenticated = true

        let viewModel = OnboardingFlowViewModel()
        viewModel.updateSex(.male)
        viewModel.updateBirthYear(1_979)
        viewModel.bodyScoreInput.height = HeightValue(value: 180, unit: .centimeters)
        viewModel.setHeightUnit(.centimeters)
        viewModel.hydrateProfileDetailsDraftIfNeeded(from: user)
        viewModel.updateProfileBiologicalSex(.female)
        viewModel.profileDateOfBirth = profileDateOfBirth
        viewModel.profileHeightUnit = .inches
        viewModel.profileHeightFeet = 5
        viewModel.profileHeightInches = 7

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["gender"] as? String, "Female")

        let dateOfBirth = updates["dateOfBirth"] as? Date
        XCTAssertEqual(dateOfBirth, profileDateOfBirth)

        let height = updates["height"] as? Double
        XCTAssertNotNil(height)
        if let height {
            XCTAssertEqual(height, 67 * 2.54, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "in")
        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testBuildOnboardingProfileUpdatesAlwaysMarksOnboardingCompleted() {
        let viewModel = OnboardingFlowViewModel()

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
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

final class AuthConfigurationValidationTests: XCTestCase {
    func testProductionRejectsDevelopmentAuthAndTelemetryConfig() {
        let snapshot = Configuration.AuthEnvironmentSnapshot(
            environment: .production,
            clerkPublishableKey: "pk_test_123",
            supabaseURL: "https://dev-project.supabase.co",
            supabaseExpectedHost: "prod-project.supabase.co",
            apiBaseURL: "ht" + "tp://localhost:3000",
            apiExpectedHost: "www.logyourbody.com",
            revenueCatAPIKey: "replace_with_prod_revenuecat_public_key",
            sentryEnvironment: "development",
            statsigEnvironmentTier: "development",
            allowProductionServicesInDevelopment: false
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.messages.contains("Production builds cannot use Clerk test publishable keys."))
        XCTAssertTrue(result.messages.contains("Supabase URL host must match SUPABASE_EXPECTED_HOST for this environment."))
        XCTAssertTrue(result.messages.contains("Production API base URL must use HTTPS."))
        XCTAssertTrue(result.messages.contains("Production RevenueCat API key must be configured."))
        XCTAssertTrue(result.messages.contains("Production Sentry environment must be production."))
        XCTAssertTrue(result.messages.contains("Production Statsig tier must be production."))
    }

    func testProductionRequiresExplicitSupabaseExpectedHost() {
        let snapshot = Configuration.AuthEnvironmentSnapshot(
            environment: .production,
            clerkPublishableKey: "pk_live_123",
            supabaseURL: "https://prod-project.supabase.co",
            supabaseExpectedHost: "",
            apiBaseURL: "https://www.logyourbody.com",
            apiExpectedHost: "www.logyourbody.com",
            revenueCatAPIKey: "appl_123",
            sentryEnvironment: "production",
            statsigEnvironmentTier: "production",
            allowProductionServicesInDevelopment: false
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.messages.contains("Supabase expected host must be configured for production."))
    }

    func testDevelopmentRejectsProductionClerkKeyByDefault() {
        let snapshot = Configuration.AuthEnvironmentSnapshot(
            environment: .development,
            clerkPublishableKey: "pk_live_123",
            supabaseURL: "https://dev-project.supabase.co",
            supabaseExpectedHost: "dev-project.supabase.co",
            apiBaseURL: "ht" + "tp://localhost:3000",
            apiExpectedHost: "localhost",
            revenueCatAPIKey: "",
            sentryEnvironment: "development",
            statsigEnvironmentTier: "development",
            allowProductionServicesInDevelopment: false
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(
            result.messages.contains("Development builds cannot use Clerk live publishable keys unless explicitly allowed.")
        )
    }

    func testDevelopmentAllowsProductionServicesWhenExplicitlyAllowed() {
        let snapshot = Configuration.AuthEnvironmentSnapshot(
            environment: .development,
            clerkPublishableKey: "pk_live_123",
            supabaseURL: "https://prod-project.supabase.co",
            supabaseExpectedHost: "prod-project.supabase.co",
            apiBaseURL: "https://www.logyourbody.com",
            apiExpectedHost: "www.logyourbody.com",
            revenueCatAPIKey: "appl_123",
            sentryEnvironment: "development",
            statsigEnvironmentTier: "development",
            allowProductionServicesInDevelopment: true
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.messages.isEmpty)
    }
}

final class RevenueCatProductConfigurationTests: XCTestCase {
    private let annualProductID = "com.logyourbody.app.pro1.annual.3daytrial"
    private let monthlyProductID = "com.logyourbody.app.pro1.monthly.3daytrial"

    func testStoreKitProductIdentifiersMatchReleasePreflight() throws {
        let storeKitURL = iOSDirectory.appendingPathComponent("LogYourBody.storekit")
        let storeKitData = try Data(contentsOf: storeKitURL)
        let storeKitObject = try JSONSerialization.jsonObject(with: storeKitData)
        let productIDs = try storeKitProductIDs(from: storeKitObject)

        XCTAssertEqual(Set(productIDs), [annualProductID, monthlyProductID])
        XCTAssertFalse(productIDs.contains { $0.contains(".pro.") })

        let preflightScriptURL = iOSDirectory
            .appendingPathComponent("Scripts")
            .appendingPathComponent("verify_revenuecat_offerings.sh")
        let preflightScript = try String(contentsOf: preflightScriptURL, encoding: .utf8)

        XCTAssertTrue(preflightScript.contains("$rc_annual:\(annualProductID)"))
        XCTAssertTrue(preflightScript.contains("$rc_monthly:\(monthlyProductID)"))
    }

    private var iOSDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func storeKitProductIDs(from object: Any) throws -> [String] {
        let dictionary = try XCTUnwrap(object as? [String: Any])
        let subscriptionGroups = try XCTUnwrap(dictionary["subscriptionGroups"] as? [[String: Any]])

        return try subscriptionGroups.flatMap { group in
            let subscriptions = try XCTUnwrap(group["subscriptions"] as? [[String: Any]])
            return try subscriptions.map { subscription in
                try XCTUnwrap(subscription["productID"] as? String)
            }
        }
    }
}

final class RevenueCatSubscriptionAnalyticsTransitionTests: XCTestCase {
    func testTrialStartTracksWhenEnteringTrial() {
        XCTAssertEqual(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .none, to: .trial),
            .trialStart
        )
    }

    func testTrialStartDoesNotDuplicateForRepeatedTrialRefresh() {
        XCTAssertNil(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .trial, to: .trial)
        )
    }

    func testTrialConversionTracksWhenTrialBecomesPaid() {
        XCTAssertEqual(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .trial, to: .paid),
            .trialConvertedToPaid
        )
    }

    func testTrialExpirationTracksWhenTrialExpiresUnpaid() {
        XCTAssertEqual(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .trial, to: .expiredUnpaid),
            .trialExpiredUnpaid
        )
    }

    func testExistingPaidSubscriberDoesNotBackfillTrialConversion() {
        XCTAssertNil(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .none, to: .paid)
        )
    }
}

final class PaywallSavingsPolicyTests: XCTestCase {
    func testSavingsPercentUsesLiveMonthlyAndAnnualPrices() throws {
        let monthly = try XCTUnwrap(Decimal(string: "9.99"))
        let annual = try XCTUnwrap(Decimal(string: "69.99"))

        XCTAssertEqual(
            PaywallSavingsPolicy.savingsPercent(monthlyPrice: monthly, annualPrice: annual),
            42
        )
    }

    func testMonthlyEquivalentUsesAnnualPriceDividedByTwelve() throws {
        let annual = try XCTUnwrap(Decimal(string: "69.99"))
        let monthlyEquivalent = try XCTUnwrap(PaywallSavingsPolicy.monthlyEquivalent(annualPrice: annual))
        let rounded = monthlyEquivalent.rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 2,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        )

        XCTAssertEqual(rounded, NSDecimalNumber(string: "5.83"))
    }

    func testSavingsPercentOmitsNonDiscountedAnnualPrice() throws {
        let monthly = try XCTUnwrap(Decimal(string: "9.99"))
        let annual = try XCTUnwrap(Decimal(string: "119.88"))

        XCTAssertNil(PaywallSavingsPolicy.savingsPercent(monthlyPrice: monthly, annualPrice: annual))
    }

    func testSavingsPercentOmitsInvalidPrices() throws {
        let annual = try XCTUnwrap(Decimal(string: "69.99"))

        XCTAssertNil(PaywallSavingsPolicy.savingsPercent(monthlyPrice: 0, annualPrice: annual))
        XCTAssertNil(PaywallSavingsPolicy.monthlyEquivalent(annualPrice: 0))
    }
}

final class CachedPaywallOfferingDisplayTests: XCTestCase {
    func testPreferredPackageUsesAnnualBeforeMonthly() {
        let display = CachedPaywallOfferingDisplay(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            packages: [
                CachedPaywallOfferingDisplay.PackageDisplay(
                    packageIdentifier: "$rc_monthly",
                    productIdentifier: "com.logyourbody.app.pro1.monthly.3daytrial",
                    localizedPrice: "$9.99",
                    billingPeriod: "month",
                    trialText: "3 days free"
                ),
                CachedPaywallOfferingDisplay.PackageDisplay(
                    packageIdentifier: "$rc_annual",
                    productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
                    localizedPrice: "$79.99",
                    billingPeriod: "year",
                    trialText: "3 days free"
                )
            ]
        )

        XCTAssertEqual(display.preferredPackage?.packageIdentifier, "$rc_annual")
        XCTAssertEqual(display.preferredPackage?.localizedPrice, "$79.99")
    }

    func testCachedPaywallOfferingDisplayPersistsAsDisplayOnlyData() throws {
        let display = CachedPaywallOfferingDisplay(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            packages: [
                CachedPaywallOfferingDisplay.PackageDisplay(
                    packageIdentifier: "$rc_annual",
                    productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
                    localizedPrice: "$79.99",
                    billingPeriod: "year",
                    trialText: "3 days free"
                )
            ]
        )

        let data = try JSONEncoder().encode(display)
        let decoded = try JSONDecoder().decode(CachedPaywallOfferingDisplay.self, from: data)

        XCTAssertEqual(decoded, display)
        XCTAssertEqual(decoded.preferredPackage?.productIdentifier, "com.logyourbody.app.pro1.annual.3daytrial")
    }
}

@MainActor
final class RevenueCatPurchaseRestoreFlowTests: XCTestCase {
    private static let isSubscribedKey = "revenuecat_isSubscribed"

    func testPurchaseSuccessMarksSubscribedAndPersistsCache() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let package = Self.makeAnnualPackage()
        fixture.client.purchaseResult = .success(Self.customer(isActive: true))
        fixture.client.onPurchase = {
            XCTAssertTrue(fixture.manager.isPurchasing)
        }

        let didPurchase = await fixture.manager.purchase(package: package)

        XCTAssertTrue(didPurchase)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertNil(fixture.manager.errorMessage)
        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.client.purchasedPackageIdentifier, "$rc_annual")
        XCTAssertEqual(fixture.client.purchaseEntitlementID, Constants.proEntitlementID)
    }

    func testPurchaseCancellationStopsPurchasingWithoutShowingError() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.client.purchaseResult = .failure(RevenueCatPurchasingError.purchaseCancelled)

        let didPurchase = await fixture.manager.purchase(package: Self.makeAnnualPackage())

        XCTAssertFalse(didPurchase)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertNil(fixture.manager.errorMessage)
        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testPurchaseStoreProblemSetsFriendlyError() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.client.purchaseResult = .failure(RevenueCatPurchasingError.storeProblem)

        let didPurchase = await fixture.manager.purchase(package: Self.makeAnnualPackage())

        XCTAssertFalse(didPurchase)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertEqual(fixture.manager.errorMessage, "There was a problem with the App Store. Please try again.")
    }

    func testRestoreSuccessMarksSubscribedAndPersistsCache() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.client.restoreResult = .success(Self.customer(isActive: true))
        fixture.client.onRestore = {
            XCTAssertTrue(fixture.manager.isPurchasing)
        }

        let didRestore = await fixture.manager.restorePurchases()

        XCTAssertTrue(didRestore)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertNil(fixture.manager.errorMessage)
        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.client.restoreEntitlementID, Constants.proEntitlementID)
    }

    func testRestoreWithoutActiveSubscriptionInvalidatesStaleCache() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        XCTAssertTrue(fixture.manager.isSubscribed)
        fixture.client.restoreResult = .success(Self.customer(isActive: false))

        let didRestore = await fixture.manager.restorePurchases()

        XCTAssertFalse(didRestore)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.manager.errorMessage, "No active subscriptions found")
    }

    func testRefreshFailurePreservesCachedSubscribedAccess() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        XCTAssertTrue(fixture.manager.isSubscribed)
        fixture.client.customerInfoResult = .failure(MockRevenueCatPurchasesClient.MockError.customerInfoFailed)

        await fixture.manager.refreshCustomerInfo()

        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testRefreshInactiveCustomerInvalidatesStaleSubscribedCache() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        XCTAssertTrue(fixture.manager.isSubscribed)
        fixture.client.customerInfoResult = .success(Self.customer(isActive: false))

        await fixture.manager.refreshCustomerInfo()

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testLogoutUserFailureStillClearsLocalSubscriptionState() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        fixture.client.customerInfoResult = .success(Self.customer(isActive: true))
        await fixture.manager.refreshCustomerInfo()
        fixture.client.logOutResult = .failure(MockRevenueCatPurchasesClient.MockError.logOutFailed)

        await fixture.manager.logoutUser()

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.customerInfo)
    }

    func testLogoutUserSuccessClearsLocalSubscriptionState() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        fixture.client.customerInfoResult = .success(Self.customer(isActive: true))
        await fixture.manager.refreshCustomerInfo()

        await fixture.manager.logoutUser()

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.customerInfo)
    }

    func testEntitlementIdentifierMatchesRevenueCatDashboardContract() {
        XCTAssertEqual(RevenueCatManager.entitlementID, Constants.proEntitlementID)
        XCTAssertEqual(RevenueCatManager.entitlementID, "Premium")
    }

    private func makeFixture(cachedSubscribed: Bool = false) -> RevenueCatPurchaseFixture {
        let suiteName = "revenuecat-purchase-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(cachedSubscribed, forKey: Self.isSubscribedKey)

        let client = MockRevenueCatPurchasesClient()
        let manager = RevenueCatManager(purchasesClient: client, userDefaults: defaults)
        manager.markAsConfigured()

        return RevenueCatPurchaseFixture(
            manager: manager,
            client: client,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private static func customer(
        isActive: Bool,
        appUserId: String = "unit-test-user",
        periodType: PeriodType = .normal
    ) -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(
            originalAppUserId: appUserId,
            entitlement: isActive ? RevenueCatEntitlementSnapshot(
                isActive: true,
                expirationDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                periodType: periodType,
                willRenew: true,
                productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
                unsubscribeDetectedAt: nil
            ) : nil
        )
    }

    private static func makeAnnualPackage() -> Package {
        let product = TestStoreProduct(
            localizedTitle: "LogYourBody Pro Annual",
            price: Decimal(string: "69.99") ?? 0,
            localizedPriceString: "$69.99",
            productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
            productType: .autoRenewableSubscription,
            localizedDescription: "Annual LogYourBody Pro subscription",
            subscriptionGroupIdentifier: "logyourbody_pro",
            subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .year),
            locale: Locale(identifier: "en_US")
        ).toStoreProduct()

        return Package(
            identifier: "$rc_annual",
            packageType: .annual,
            storeProduct: product,
            offeringIdentifier: "unit_test_paywall",
            webCheckoutUrl: nil
        )
    }
}

@MainActor
private struct RevenueCatPurchaseFixture {
    let manager: RevenueCatManager
    let client: MockRevenueCatPurchasesClient
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class MockRevenueCatPurchasesClient: RevenueCatPurchasesProtocol {
    enum MockError: Error {
        case notImplemented
        case customerInfoFailed
        case logOutFailed
    }

    var customerInfoResult: Result<RevenueCatCustomerSnapshot, Error> = .success(
        RevenueCatCustomerSnapshot(originalAppUserId: "unit-test-user", entitlement: nil)
    )
    var purchaseResult: Result<RevenueCatCustomerSnapshot, Error> = .success(
        RevenueCatCustomerSnapshot(originalAppUserId: "unit-test-user", entitlement: nil)
    )
    var restoreResult: Result<RevenueCatCustomerSnapshot, Error> = .success(
        RevenueCatCustomerSnapshot(originalAppUserId: "unit-test-user", entitlement: nil)
    )
    var logOutResult: Result<Void, Error> = .success(())
    var onPurchase: (() -> Void)?
    var onRestore: (() -> Void)?

    private(set) var configuredAPIKey: String?
    private(set) var delegateWasSet = false
    private(set) var purchaseEntitlementID: String?
    private(set) var purchasedPackageIdentifier: String?
    private(set) var restoreEntitlementID: String?

    func configure(apiKey: String, delegate: PurchasesDelegate) {
        configuredAPIKey = apiKey
        delegateWasSet = true
    }

    func logIn(userId: String, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(originalAppUserId: userId, entitlement: nil)
    }

    func logOut() async throws {
        try logOutResult.get()
    }

    func customerInfo(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        try customerInfoResult.get()
    }

    func offerings() async throws -> Offerings {
        throw MockError.notImplemented
    }

    func purchase(package: Package, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        purchasedPackageIdentifier = package.identifier
        purchaseEntitlementID = entitlementID
        onPurchase?()
        return try purchaseResult.get()
    }

    func restorePurchases(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        restoreEntitlementID = entitlementID
        onRestore?()
        return try restoreResult.get()
    }
}

final class AuthLegacyStorageMigrationTests: XCTestCase {
    func testMigrateLegacyAuthStorageRemovesSensitiveDefaultsOnly() {
        let suiteName = "auth-legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("legacy-access", forKey: Constants.authTokenKey)
        defaults.set("legacy-refresh", forKey: "refreshToken")
        defaults.set("legacy-session", forKey: "clerkSession")
        defaults.set("legacy-user-json", forKey: Constants.currentUserKey)
        defaults.set(true, forKey: Constants.hasCompletedOnboardingKey)

        let removedKeys = AuthManager.migrateLegacyAuthStorage(in: defaults)

        XCTAssertTrue(removedKeys.contains(Constants.authTokenKey))
        XCTAssertTrue(removedKeys.contains("refreshToken"))
        XCTAssertTrue(removedKeys.contains("clerkSession"))
        XCTAssertTrue(removedKeys.contains(Constants.currentUserKey))
        XCTAssertNil(defaults.object(forKey: Constants.authTokenKey))
        XCTAssertNil(defaults.object(forKey: "refreshToken"))
        XCTAssertNil(defaults.object(forKey: "clerkSession"))
        XCTAssertNil(defaults.object(forKey: Constants.currentUserKey))
        XCTAssertEqual(defaults.bool(forKey: Constants.hasCompletedOnboardingKey), true)
    }
}

final class StubSupabaseManager: SupabaseManager {
    private(set) var bodyMetricsBatches: [[[String: Any]]] = []
    private(set) var dailyMetricsBatches: [[[String: Any]]] = []
    private(set) var profilePayloads: [[String: Any]] = []
    private(set) var dexaPayloads: [[String: Any]] = []
    private(set) var glp1DoseLogPayloads: [[String: Any]] = []
    private(set) var glp1MedicationPayloads: [[String: Any]] = []
    private(set) var endedActiveMedicationRequests: [(userId: String, endedAt: Date)] = []
    private(set) var deletedRecords: [(table: String, id: String)] = []

    override func upsertBodyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        bodyMetricsBatches.append(metrics)
        return metrics.compactMap { metric in
            guard let id = metric["id"] as? String else { return [:] }
            return ["id": id]
        }
    }

    override func upsertDailyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        dailyMetricsBatches.append(metrics)
        return metrics.compactMap { metric in
            guard let id = metric["id"] as? String else { return [:] }
            return ["id": id]
        }
    }

    override func updateProfile(_ profile: [String: Any], token: String) async throws {
        profilePayloads.append(profile)
    }

    override func upsertData(table: String, data: Data, token: String) async throws -> [[String: Any]] {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let array = jsonObject as? [[String: Any]] ?? []

        switch table {
        case "dexa_results":
            dexaPayloads.append(contentsOf: array)
        case "glp1_dose_logs":
            glp1DoseLogPayloads.append(contentsOf: array)
        case "glp1_medications":
            glp1MedicationPayloads.append(contentsOf: array)
        default:
            return []
        }

        return array.compactMap { payload in
            guard let id = payload["id"] as? String else { return nil }
            return ["id": id]
        }
    }

    override func deleteData(table: String, id: String, token: String) async throws {
        deletedRecords.append((table: table, id: id))
    }

    override func endActiveGlp1Medications(userId: String, endedAt: Date) async throws {
        endedActiveMedicationRequests.append((userId: userId, endedAt: endedAt))
    }
}

final class StubBodySpecDexaAPI: BodySpecDexaAPIClient {
    var pages: [Int: BodySpecResultsListResponse] = [:]
    var scanInfos: [String: BodySpecDexaScanInfoResponse] = [:]
    var compositions: [String: BodySpecDexaCompositionResponse] = [:]

    private(set) var compositionRequests: [String] = []

    func listResults(page: Int, pageSize: Int) async throws -> BodySpecResultsListResponse {
        pages[page] ?? BodySpecResultsListResponse(results: [])
    }

    func getDexaScanInfo(resultId: String) async throws -> BodySpecDexaScanInfoResponse {
        guard let scanInfo = scanInfos[resultId] else {
            throw BodySpecAPIError.invalidResponse
        }

        return scanInfo
    }

    func getDexaComposition(resultId: String) async throws -> BodySpecDexaCompositionResponse {
        compositionRequests.append(resultId)

        guard let composition = compositions[resultId] else {
            throw BodySpecAPIError.invalidResponse
        }

        return composition
    }
}

@MainActor
final class SyncIntegrationTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    private func wholeSecondDate(_ offset: TimeInterval = 0) -> Date {
        Date(timeIntervalSince1970: 1_735_000_000 + offset)
    }

    private func cachedBodyMetric(id: String) async -> CachedBodyMetrics? {
        let context = CoreDataManager.shared.viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

    private func cachedProfiles(id: String) async -> [CachedProfile] {
        let context = CoreDataManager.shared.viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)

            return (try? context.fetch(request)) ?? []
        }
    }

    private func makeBodySpecSummary(
        resultId: String,
        startTime: Date,
        serviceId: String = "svc-dxa"
    ) -> BodySpecResultSummary {
        BodySpecResultSummary(
            resultId: resultId,
            startTime: startTime,
            location: BodySpecLocation(locationId: "loc-santa-monica", name: "Santa Monica"),
            service: BodySpecService(
                name: "DEXA",
                description: "DEXA scan",
                serviceId: serviceId,
                serviceCode: "DXA"
            )
        )
    }

    private func makeBodySpecComposition(resultId: String) -> BodySpecDexaCompositionResponse {
        BodySpecDexaCompositionResponse(
            resultId: resultId,
            total: BodySpecBodyRegion(
                fatMassKg: 14.0,
                leanMassKg: 62.0,
                boneMassKg: 3.2,
                totalMassKg: 79.2,
                tissueFatPct: 18.4,
                regionFatPct: 17.7
            )
        )
    }

    func testCleanupOldDataDeletesOnlyOldTombstonedBodyMetrics() async throws {
        let coreData = CoreDataManager.shared

        let userId = "cleanup_user_\(UUID().uuidString)"
        let oldDeletedId = UUID().uuidString
        let recentDeletedId = UUID().uuidString
        let oldLiveId = UUID().uuidString
        let now = Date()
        let oldDate = now.addingTimeInterval(-370 * 24 * 60 * 60)
        let recentDate = now.addingTimeInterval(-10 * 24 * 60 * 60)

        let oldDeletedMetric = BodyMetrics(
            id: oldDeletedId,
            userId: userId,
            date: oldDate,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: oldDate,
            updatedAt: oldDate
        )
        let recentDeletedMetric = BodyMetrics(
            id: recentDeletedId,
            userId: userId,
            date: recentDate,
            weight: 81.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: recentDate,
            updatedAt: recentDate
        )
        let oldLiveMetric = BodyMetrics(
            id: oldLiveId,
            userId: userId,
            date: oldDate,
            weight: 82.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: oldDate,
            updatedAt: oldDate
        )

        try await coreData.saveBodyMetricsAndWait(oldDeletedMetric, userId: userId, markAsSynced: true)
        try await coreData.saveBodyMetricsAndWait(recentDeletedMetric, userId: userId, markAsSynced: true)
        try await coreData.saveBodyMetricsAndWait(oldLiveMetric, userId: userId, markAsSynced: true)

        let didMarkOldDeleted = await coreData.markBodyMetricDeleted(id: oldDeletedId)
        let didMarkRecentDeleted = await coreData.markBodyMetricDeleted(id: recentDeletedId)
        XCTAssertTrue(didMarkOldDeleted)
        XCTAssertTrue(didMarkRecentDeleted)

        await coreData.cleanupOldData()

        let context = coreData.viewContext
        let remainingIds = await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", userId)

            let metrics = (try? context.fetch(request)) ?? []
            return Set(metrics.compactMap(\.id))
        }

        XCTAssertFalse(remainingIds.contains(oldDeletedId))
        XCTAssertTrue(remainingIds.contains(recentDeletedId))
        XCTAssertTrue(remainingIds.contains(oldLiveId))
    }

    func testBodySpecDexaImporter_AddsProvenanceWithoutOverwritingManualOrHealthKit() async throws {
        let coreData = CoreDataManager.shared
        let authManager = AuthManager()

        let userId = "bodyspec_import_user_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "bodyspec@example.com",
            name: "BodySpec Import",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        authManager.currentUser = user

        let scanDate = wholeSecondDate(20_000)
        let manualMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: scanDate,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: 20.0,
            bodyFatMethod: "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: "same-day manual entry",
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: scanDate,
            updatedAt: scanDate
        )
        try await coreData.saveBodyMetricsAndWait(manualMetric, userId: userId, markAsSynced: false)

        let healthKitMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: scanDate.addingTimeInterval(600),
            weight: 80.4,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "same-day HealthKit entry",
            photoUrl: nil,
            dataSource: BodyMetricSource.healthKit.rawValue,
            sourceMetadata: BodyMetricSourceMetadata(vendor: "apple_health", sampleId: "hk-sample"),
            createdAt: scanDate,
            updatedAt: scanDate
        )
        try await coreData.saveBodyMetricsAndWait(healthKitMetric, userId: userId, markAsSynced: false)

        let resultId = "bodyspec-result-123"
        let stubAPI = StubBodySpecDexaAPI()
        stubAPI.pages[1] = BodySpecResultsListResponse(results: [
            makeBodySpecSummary(resultId: resultId, startTime: scanDate)
        ])
        stubAPI.scanInfos[resultId] = BodySpecDexaScanInfoResponse(
            resultId: resultId,
            scannerModel: "Hologic Horizon A",
            acquireTime: scanDate.addingTimeInterval(1_200),
            analyzeTime: scanDate.addingTimeInterval(1_500)
        )
        stubAPI.compositions[resultId] = makeBodySpecComposition(resultId: resultId)

        let importer = BodySpecDexaImporter(
            api: stubAPI,
            authManager: authManager,
            coreDataManager: coreData
        )

        let importResult = await importer.importDexaResults()

        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertEqual(importResult.skippedCount, 0)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 3)

        let manual = try XCTUnwrap(metrics.first { $0.id == manualMetric.id })
        XCTAssertEqual(manual.dataSource, "manual")
        XCTAssertEqual(try XCTUnwrap(manual.weight), 80.0, accuracy: 0.001)

        let healthKit = try XCTUnwrap(metrics.first { $0.id == healthKitMetric.id })
        XCTAssertEqual(healthKit.dataSource, "healthkit")
        XCTAssertEqual(try XCTUnwrap(healthKit.weight), 80.4, accuracy: 0.001)

        let dexa = try XCTUnwrap(metrics.first { $0.dataSource == BodyMetricSource.bodySpecDexa.rawValue })
        XCTAssertEqual(dexa.bodyFatMethod, "DEXA (BodySpec)")
        XCTAssertEqual(try XCTUnwrap(dexa.weight), 79.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(dexa.bodyFatPercentage), 17.7, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(dexa.muscleMass), 62.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(dexa.boneMass), 3.2, accuracy: 0.001)

        let sourceMetadata = try XCTUnwrap(dexa.sourceMetadata)
        XCTAssertEqual(sourceMetadata.vendor, "bodyspec")
        XCTAssertEqual(sourceMetadata.sourceName, "BodySpec DEXA")
        XCTAssertEqual(sourceMetadata.externalId, "svc-dxa")
        XCTAssertEqual(sourceMetadata.externalResultId, resultId)
        XCTAssertEqual(sourceMetadata.scannerModel, "Hologic Horizon A")
        XCTAssertEqual(sourceMetadata.locationId, "loc-santa-monica")
        XCTAssertEqual(sourceMetadata.locationName, "Santa Monica")
        XCTAssertNotNil(sourceMetadata.importedAt)

        let dexaResults = await coreData.fetchDexaResults(for: userId, limit: 10)
        XCTAssertEqual(dexaResults.count, 1)
        XCTAssertEqual(dexaResults.first?.bodyMetricsId, dexa.id)
        XCTAssertEqual(dexaResults.first?.externalSource, "bodyspec")
        XCTAssertEqual(dexaResults.first?.externalResultId, resultId)
    }

    func testBodySpecDexaImporter_SkipsExistingExternalResultId() async throws {
        let coreData = CoreDataManager.shared
        let authManager = AuthManager()

        let userId = "bodyspec_duplicate_user_\(UUID().uuidString)"
        authManager.currentUser = LocalUser(
            id: userId,
            email: "bodyspec-duplicate@example.com",
            name: "BodySpec Duplicate",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )

        let scanDate = wholeSecondDate(30_000)
        let resultId = "bodyspec-result-duplicate"
        let stubAPI = StubBodySpecDexaAPI()
        stubAPI.pages[1] = BodySpecResultsListResponse(results: [
            makeBodySpecSummary(resultId: resultId, startTime: scanDate)
        ])
        stubAPI.scanInfos[resultId] = BodySpecDexaScanInfoResponse(
            resultId: resultId,
            scannerModel: "Hologic Horizon A",
            acquireTime: scanDate,
            analyzeTime: scanDate.addingTimeInterval(300)
        )
        stubAPI.compositions[resultId] = makeBodySpecComposition(resultId: resultId)

        let importer = BodySpecDexaImporter(
            api: stubAPI,
            authManager: authManager,
            coreDataManager: coreData
        )

        let firstImport = await importer.importDexaResults()
        let secondImport = await importer.importDexaResults()

        XCTAssertEqual(firstImport.importedCount, 1)
        XCTAssertEqual(firstImport.skippedCount, 0)
        XCTAssertEqual(secondImport.importedCount, 0)
        XCTAssertEqual(secondImport.skippedCount, 1)
        XCTAssertEqual(stubAPI.compositionRequests.filter { $0 == resultId }.count, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.filter { $0.dataSource == BodyMetricSource.bodySpecDexa.rawValue }.count, 1)
    }

    func testUpdateOrCreateBodyMetric_MapsSupabasePayload() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_\(UUID().uuidString)"
        let date = wholeSecondDate()
        let createdAt = date.addingTimeInterval(-60)
        let updatedAt = date
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight": 80.5,
            "weight_unit": "kg",
            "body_fat_percentage": 18.2,
            "body_fat_method": "health_kit",
            "muscle_mass": 35.0,
            "bone_mass": 4.2,
            "photo_url": "https://example.com/photo.jpg",
            "notes": "supabase-mapped",
            "data_source": "HealthKit",
            "source_metadata": [
                "sample_id": "hk-sample-123",
                "device_model": "Withings Body Scan"
            ],
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: updatedAt)
        ]

        coreData.updateOrCreateBodyMetric(from: payload)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.id, id)
        XCTAssertEqual(metric.userId, userId)

        let weight = try XCTUnwrap(metric.weight)
        XCTAssertEqual(weight, 80.5, accuracy: 0.001)
        XCTAssertEqual(metric.weightUnit, "kg")

        let bodyFat = try XCTUnwrap(metric.bodyFatPercentage)
        XCTAssertEqual(bodyFat, 18.2, accuracy: 0.001)
        XCTAssertEqual(metric.bodyFatMethod, "health_kit")

        let muscle = try XCTUnwrap(metric.muscleMass)
        XCTAssertEqual(muscle, 35.0, accuracy: 0.001)

        let bone = try XCTUnwrap(metric.boneMass)
        XCTAssertEqual(bone, 4.2, accuracy: 0.001)

        XCTAssertEqual(metric.photoUrl, "https://example.com/photo.jpg")
        XCTAssertEqual(metric.notes, "supabase-mapped")
        XCTAssertEqual(metric.dataSource, "healthkit")
        XCTAssertEqual(metric.sourceMetadata?.sampleId, "hk-sample-123")
        XCTAssertEqual(metric.sourceMetadata?.deviceModel, "Withings Body Scan")

        XCTAssertEqual(metric.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(metric.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)
    }

    func testUpdateOrCreateDailyMetric_MapsSupabasePayload() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_\(UUID().uuidString)"
        let date = wholeSecondDate(1_000)
        let createdAt = date.addingTimeInterval(-120)
        let updatedAt = date
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "steps": 10_000,
            "notes": "daily-metrics-mapped",
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: updatedAt)
        ]

        coreData.updateOrCreateDailyMetric(from: payload)

        let logs = await coreData.fetchAllDailyLogs(for: userId)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.id, id)
        XCTAssertEqual(log.userId, userId)
        XCTAssertEqual(log.date.timeIntervalSince(date), 0, accuracy: 0.001)
        XCTAssertEqual(log.stepCount, 10_000)
        XCTAssertEqual(log.notes, "daily-metrics-mapped")
        XCTAssertEqual(log.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(log.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)
    }

    func testUpdateOrCreateProfile_IsIdempotentForSameId() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_profile_\(UUID().uuidString)"
        let firstPayload: [String: Any] = [
            "id": userId,
            "full_name": "First Name",
            "username": "first_name",
            "height": 178.0,
            "height_unit": "cm",
            "gender": "male",
            "activity_level": "active",
            "date_of_birth": "1990-01-01T00:00:00Z"
        ]
        let secondPayload: [String: Any] = [
            "id": userId,
            "full_name": "Updated Name",
            "username": "updated_name",
            "height": 181.0,
            "height_unit": "cm",
            "gender": "male",
            "activity_level": "active",
            "date_of_birth": "1990-01-01T00:00:00Z"
        ]

        coreData.updateOrCreateProfile(from: firstPayload)
        coreData.updateOrCreateProfile(from: secondPayload)

        let profiles = await cachedProfiles(id: userId)
        XCTAssertEqual(profiles.count, 1)

        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profile.id, userId)
        XCTAssertEqual(profile.fullName, "Updated Name")
        XCTAssertEqual(profile.username, "updated_name")
        XCTAssertEqual(profile.height, 181.0, accuracy: 0.001)
        XCTAssertEqual(profile.syncStatus, "synced")
        XCTAssertTrue(profile.isSynced)
    }

    func testSyncLocalChanges_OmitsMissingProfileHeight() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_profile_no_height_\(UUID().uuidString)"
        let profile = UserProfile(
            id: userId,
            email: "profile-no-height@example.com",
            username: "profile_no_height",
            fullName: "Profile No Height",
            dateOfBirth: nil,
            height: nil,
            heightUnit: "cm",
            gender: "male",
            activityLevel: "active",
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: true
        )

        coreData.saveProfile(
            profile,
            userId: userId,
            email: "profile-no-height@example.com",
            markSynced: false
        )

        let snapshot = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        let pendingProfile = try XCTUnwrap(snapshot.profiles.first { $0.id == userId })
        XCTAssertNil(pendingProfile.height)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        let payload = try XCTUnwrap(stubSupabase.profilePayloads.first)
        XCTAssertEqual(payload["id"] as? String, userId)
        XCTAssertNil(payload["height"])
        XCTAssertEqual(payload["height_unit"] as? String, "cm")

        let profiles = await cachedProfiles(id: userId)
        let cachedProfile = try XCTUnwrap(profiles.first)
        XCTAssertTrue(cachedProfile.isSynced)
        XCTAssertEqual(cachedProfile.syncStatus, "synced")
    }

    func testUpdateOrCreateBodyMetric_IsIdempotentForSameId() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_idempotent_\(UUID().uuidString)"
        let date = wholeSecondDate(2_000)
        let createdAt = date.addingTimeInterval(-300)
        let updatedAt1 = date.addingTimeInterval(-120)
        let updatedAt2 = date
        let formatter = ISO8601DateFormatter()

        let basePayload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight_unit": "kg",
            "created_at": formatter.string(from: createdAt)
        ]

        var firstPayload = basePayload
        firstPayload["weight"] = 75.0
        firstPayload["updated_at"] = formatter.string(from: updatedAt1)

        var secondPayload = basePayload
        secondPayload["weight"] = 82.0
        secondPayload["updated_at"] = formatter.string(from: updatedAt2)

        coreData.updateOrCreateBodyMetric(from: firstPayload)
        coreData.updateOrCreateBodyMetric(from: secondPayload)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.id, id)
        XCTAssertEqual(metric.userId, userId)

        let weight = try XCTUnwrap(metric.weight)
        XCTAssertEqual(weight, 82.0, accuracy: 0.001)
        XCTAssertEqual(metric.weightUnit, "kg")
        XCTAssertEqual(metric.updatedAt.timeIntervalSince(updatedAt2), 0, accuracy: 0.001)
    }

    func testUpdateOrCreateBodyMetric_DoesNotOverwriteDeletedLocalTombstone() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_deleted_payload_\(UUID().uuidString)"
        let date = wholeSecondDate(2_500)
        let createdAt = date.addingTimeInterval(-300)
        let updatedAt = date.addingTimeInterval(-120)

        let metricModel = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 81.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "local-tombstone",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try await coreData.saveBodyMetricsAndWait(metricModel, userId: userId, markAsSynced: true)
        let didMarkDeleted = await coreData.markBodyMetricDeleted(id: id)
        XCTAssertTrue(didMarkDeleted)

        let formatter = ISO8601DateFormatter()
        let serverDate = date.addingTimeInterval(60)
        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: serverDate),
            "weight": 99.0,
            "weight_unit": "kg",
            "notes": "server-resurrection",
            "data_source": "manual",
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: serverDate)
        ]

        coreData.updateOrCreateBodyMetric(from: payload)

        let tombstoneResult = await cachedBodyMetric(id: id)
        let tombstone = try XCTUnwrap(tombstoneResult)
        XCTAssertTrue(tombstone.isMarkedDeleted)
        XCTAssertFalse(tombstone.isSynced)
        XCTAssertEqual(tombstone.syncStatus, "pending")
        XCTAssertEqual(tombstone.notes, "local-tombstone")
        XCTAssertEqual(tombstone.weight, 81.0, accuracy: 0.001)
        let tombstoneDate = try XCTUnwrap(tombstone.date)
        XCTAssertEqual(tombstoneDate.timeIntervalSince(date), 0, accuracy: 0.001)

        let visibleMetrics = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertFalse(visibleMetrics.contains { $0.id == id })

        let unsynced = await coreData.fetchUnsyncedEntries(for: userId)
        XCTAssertEqual(unsynced.bodyMetrics.map(\.id), [id])
        XCTAssertTrue(unsynced.bodyMetrics.allSatisfy(\.isMarkedDeleted))
    }

    func testUpdateOrCreateDailyMetric_IsIdempotentForSameId() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_idempotent_\(UUID().uuidString)"
        let date = wholeSecondDate(3_000)
        let createdAt = date.addingTimeInterval(-300)
        let updatedAt1 = date.addingTimeInterval(-120)
        let updatedAt2 = date
        let formatter = ISO8601DateFormatter()

        let basePayload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "created_at": formatter.string(from: createdAt)
        ]

        var firstPayload = basePayload
        firstPayload["steps"] = 5_000
        firstPayload["notes"] = "first"
        firstPayload["updated_at"] = formatter.string(from: updatedAt1)

        var secondPayload = basePayload
        secondPayload["steps"] = 12_000
        secondPayload["notes"] = "second"
        secondPayload["updated_at"] = formatter.string(from: updatedAt2)

        coreData.updateOrCreateDailyMetric(from: firstPayload)
        coreData.updateOrCreateDailyMetric(from: secondPayload)

        let logs = await coreData.fetchAllDailyLogs(for: userId)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.id, id)
        XCTAssertEqual(log.userId, userId)
        XCTAssertEqual(log.stepCount, 12_000)
        XCTAssertEqual(log.notes, "second")
        XCTAssertEqual(log.updatedAt.timeIntervalSince(updatedAt2), 0, accuracy: 0.001)
    }

    func testProcessBatchHealthKitData_RespectsExistingEntriesWithinSameHour() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_existing_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_existing@example.com",
            name: "HK Existing",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let existingDate = calendar.date(byAdding: DateComponents(hour: 10, minute: 45), to: day) ?? day

        let existingMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: existingDate,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "existing-healthkit",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: existingDate,
            updatedAt: existingDate
        )

        try await coreData.saveBodyMetricsAndWait(existingMetric, userId: userId)

        let sameHourDate = calendar.date(byAdding: DateComponents(hour: 10, minute: 15), to: day) ?? day
        let nextHourDate = calendar.date(byAdding: DateComponents(hour: 11, minute: 5), to: day) ?? day

        let weightHistory: [(weight: Double, date: Date)] = [
            (weight: 81.0, date: sameHourDate),
            (weight: 82.0, date: nextHourDate)
        ]

        let bodyFatHistory: [(percentage: Double, date: Date)] = []

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics.filter { $0.dataSource == "manual" }.count, 1)
        XCTAssertEqual(metrics.filter { $0.dataSource == "healthkit" }.count, 1)

        let manualMetric = try XCTUnwrap(metrics.first { $0.dataSource == "manual" })
        XCTAssertEqual(manualMetric.weight, 80.0)
        XCTAssertEqual(manualMetric.notes, "existing-healthkit")
    }

    func testProcessBatchHealthKitData_DeduplicatesMultipleWeightsInSameHour() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_batch_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_batch@example.com",
            name: "HK Batch",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let firstDate = calendar.date(byAdding: DateComponents(hour: 9, minute: 5), to: day) ?? day
        let secondDate = calendar.date(byAdding: DateComponents(hour: 9, minute: 50), to: day) ?? day

        let weightHistory: [(weight: Double, date: Date)] = [
            (weight: 70.0, date: firstDate),
            (weight: 71.0, date: secondDate)
        ]

        let bodyFatHistory: [(percentage: Double, date: Date)] = []

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)
    }

    func testProcessBatchHealthKitData_AssignsBodyFatForMatchingDate() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_bodyfat_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_bodyfat@example.com",
            name: "HK BodyFat",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let weightDate = calendar.date(byAdding: DateComponents(hour: 8, minute: 0), to: day) ?? day
        let bodyFatDate = calendar.date(byAdding: DateComponents(hour: 6, minute: 30), to: day) ?? day

        let weightHistory: [(weight: Double, date: Date)] = [
            (weight: 75.0, date: weightDate)
        ]

        let bodyFatHistory: [(percentage: Double, date: Date)] = [
            (percentage: 19.5, date: bodyFatDate)
        ]

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 0)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        let bodyFat = try XCTUnwrap(metric.bodyFatPercentage)
        XCTAssertEqual(bodyFat, 19.5, accuracy: 0.001)
        XCTAssertEqual(metric.bodyFatMethod, "HealthKit")
        XCTAssertEqual(metric.dataSource, "healthkit")
    }

    func testProcessBatchHealthKitData_AttachesSourceMetadataToImportedMetrics() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_metadata_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_metadata@example.com",
            name: "HK Metadata",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let weightDate = calendar.date(byAdding: DateComponents(hour: 7, minute: 10), to: day) ?? day
        let bodyFatDate = calendar.date(byAdding: DateComponents(hour: 7, minute: 12), to: day) ?? day

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: [
                HealthKitWeightImportSample(
                    weight: 76.5,
                    date: weightDate,
                    sourceMetadata: BodyMetricSourceMetadata(
                        vendor: "apple_health",
                        sourceName: "Apple Health",
                        sourceBundleId: "com.apple.Health",
                        deviceId: "scale-local-id",
                        deviceManufacturer: "Withings",
                        deviceModel: "Body Scan",
                        sampleId: "weight-sample-123",
                        quantityType: "HKQuantityTypeIdentifierBodyMass"
                    )
                )
            ],
            bodyFatHistory: [
                HealthKitBodyFatImportSample(
                    percentage: 18.4,
                    date: bodyFatDate,
                    sourceMetadata: BodyMetricSourceMetadata(
                        vendor: "apple_health",
                        sourceName: "Apple Health",
                        sourceBundleId: "com.apple.Health",
                        sampleId: "body-fat-sample-456",
                        quantityType: "HKQuantityTypeIdentifierBodyFatPercentage"
                    )
                )
            ]
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 0)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        let metric = try XCTUnwrap(metrics.first)
        let sourceMetadata = try XCTUnwrap(metric.sourceMetadata)
        XCTAssertEqual(metric.dataSource, "healthkit")
        XCTAssertEqual(metric.bodyFatPercentage, 18.4)
        XCTAssertEqual(sourceMetadata.vendor, "apple_health")
        XCTAssertEqual(sourceMetadata.sourceName, "Apple Health")
        XCTAssertEqual(sourceMetadata.sourceBundleId, "com.apple.Health")
        XCTAssertEqual(sourceMetadata.deviceId, "scale-local-id")
        XCTAssertEqual(sourceMetadata.deviceManufacturer, "Withings")
        XCTAssertEqual(sourceMetadata.deviceModel, "Body Scan")
        XCTAssertEqual(sourceMetadata.sampleId, "weight-sample-123")
        XCTAssertEqual(sourceMetadata.bodyFatSampleId, "body-fat-sample-456")
        XCTAssertEqual(sourceMetadata.quantityType, "HKQuantityTypeIdentifierBodyMass")
    }

    func testProcessBatchHealthKitData_DeduplicatesLateNightWeightsAndPreservesLocalDate() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_late_night_dedup_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_late_night@example.com",
            name: "HK Late Night",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let firstDate = calendar.date(byAdding: DateComponents(hour: 23, minute: 30), to: day) ?? day
        let duplicateDate = calendar.date(byAdding: DateComponents(hour: 23, minute: 55), to: day) ?? day
        let expectedLocalDate = BodyMetricLocalDate.key(for: firstDate)

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: [
                (weight: 84.0, date: firstDate),
                (weight: 84.3, date: duplicateDate)
            ],
            bodyFatHistory: []
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.weight, 84.0)
        XCTAssertEqual(metric.localDate, expectedLocalDate)
        XCTAssertEqual(BodyMetricLocalDate.hourKey(for: metric.date), "23")
    }

    func testProcessBatchHealthKitData_PairsBodyFatByLocalDateAcrossMidnight() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_midnight_pairing_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_midnight_pairing@example.com",
            name: "HK Midnight Pairing",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let lateNightWeight = calendar.date(byAdding: DateComponents(hour: 23, minute: 30), to: day) ?? day
        let duplicateLateNightWeight = calendar.date(byAdding: DateComponents(hour: 23, minute: 55), to: day) ?? day
        let sameLocalDateBodyFat = calendar.date(byAdding: DateComponents(hour: 23, minute: 45), to: day) ?? day
        let nextDayWeight = calendar.date(byAdding: DateComponents(day: 1, hour: 0, minute: 10), to: day) ?? day
        let nextLocalDateBodyFat = calendar.date(byAdding: DateComponents(day: 1, hour: 0, minute: 5), to: day) ?? day

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: [
                (weight: 84.0, date: lateNightWeight),
                (weight: 84.3, date: duplicateLateNightWeight),
                (weight: 83.8, date: nextDayWeight)
            ],
            bodyFatHistory: [
                (percentage: 18.2, date: sameLocalDateBodyFat),
                (percentage: 22.5, date: nextLocalDateBodyFat)
            ]
        )

        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 2)

        let lateNightLocalDate = BodyMetricLocalDate.key(for: lateNightWeight)
        let nextLocalDate = BodyMetricLocalDate.key(for: nextDayWeight)

        let lateNightMetric = try XCTUnwrap(metrics.first { $0.localDate == lateNightLocalDate })
        XCTAssertEqual(lateNightMetric.weight, 84.0)
        XCTAssertEqual(lateNightMetric.bodyFatPercentage, 18.2)
        XCTAssertEqual(lateNightMetric.bodyFatMethod, "HealthKit")

        let nextDayMetric = try XCTUnwrap(metrics.first { $0.localDate == nextLocalDate })
        XCTAssertEqual(nextDayMetric.weight, 83.8)
        XCTAssertEqual(nextDayMetric.bodyFatPercentage, 22.5)
        XCTAssertEqual(nextDayMetric.bodyFatMethod, "HealthKit")
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksBodyMetricSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_realtime_\(UUID().uuidString)"
        let date = Date()
        let createdAt = date.addingTimeInterval(-60)
        let updatedAt = date

        let metricModel = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 80.5,
            weightUnit: "kg",
            bodyFatPercentage: 18.2,
            bodyFatMethod: "manual",
            muscleMass: 35.0,
            boneMass: 4.2,
            notes: "unsynced-local",
            photoUrl: "https://example.com/photo.jpg",
            dataSource: "Manual",
            sourceMetadata: BodyMetricSourceMetadata(
                legacyDataSource: "Manual"
            ),
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try await coreData.saveBodyMetricsAndWait(metricModel, userId: userId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await Task.detached {
            try await manager.syncLocalChanges(token: "test-token")
        }.value

        // Verify Supabase payload
        XCTAssertEqual(stubSupabase.bodyMetricsBatches.count, 1)
        guard let batch = stubSupabase.bodyMetricsBatches.first,
              let payload = batch.first else {
            XCTFail("No body metrics batch captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)

        let payloadWeight = try XCTUnwrap(payload["weight"] as? Double)
        XCTAssertEqual(payloadWeight, 80.5, accuracy: 0.001)

        XCTAssertEqual(payload["weight_unit"] as? String, "kg")
        XCTAssertEqual(payload["photo_url"] as? String, "https://example.com/photo.jpg")
        XCTAssertEqual(payload["notes"] as? String, "unsynced-local")
        XCTAssertEqual(payload["data_source"] as? String, "manual")

        let sourceMetadata = try XCTUnwrap(payload["source_metadata"] as? [String: String])
        XCTAssertEqual(sourceMetadata["legacy_data_source"], "Manual")

        if let dateString = payload["date"] as? String {
            let formatter = ISO8601DateFormatter()
            let sentDate = formatter.date(from: dateString)
            XCTAssertNotNil(sentDate)
        } else {
            XCTFail("Expected date field in payload")
        }

        // Verify Core Data entry for this user is no longer unsynced
        let unsynced = await coreData.fetchUnsyncedEntries()
        let unsyncedForUser = unsynced.bodyMetrics.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testSyncLocalChangesScopesUnsyncedRowsToActiveUser() async throws {
        let coreData = CoreDataManager.shared

        let activeUserId = "sync_active_user_\(UUID().uuidString)"
        let otherUserId = "sync_other_user_\(UUID().uuidString)"
        let activeMetricId = UUID().uuidString
        let otherMetricId = UUID().uuidString
        let date = Date()

        let activeMetric = BodyMetrics(
            id: activeMetricId,
            userId: activeUserId,
            date: date,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
        let otherMetric = BodyMetrics(
            id: otherMetricId,
            userId: otherUserId,
            date: date,
            weight: 82.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )

        try await coreData.saveBodyMetricsAndWait(activeMetric, userId: activeUserId)
        try await coreData.saveBodyMetricsAndWait(otherMetric, userId: otherUserId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(for: activeUserId, token: "test-token")

        let syncedPayloads = stubSupabase.bodyMetricsBatches.flatMap { $0 }
        XCTAssertEqual(syncedPayloads.count, 1)
        XCTAssertEqual(syncedPayloads.first?["id"] as? String, activeMetricId)
        XCTAssertEqual(syncedPayloads.first?["user_id"] as? String, activeUserId)

        let activeUnsynced = await coreData.fetchUnsyncedEntries(for: activeUserId)
        XCTAssertTrue(activeUnsynced.bodyMetrics.isEmpty)

        let otherUnsynced = await coreData.fetchUnsyncedEntries(for: otherUserId)
        XCTAssertEqual(otherUnsynced.bodyMetrics.map(\.id), [otherMetricId])
    }

    func testPendingSyncOperationsAreScopedToActiveUser() async throws {
        UserDefaults.standard.removeObject(forKey: "pendingSyncOperations")
        defer {
            UserDefaults.standard.removeObject(forKey: "pendingSyncOperations")
        }

        let activeUserId = "pending_active_user_\(UUID().uuidString)"
        let otherUserId = "pending_other_user_\(UUID().uuidString)"
        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: activeUserId,
            email: "pending-active@example.com",
            name: "Pending Active",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        authManager.isAuthenticated = true

        let manager = RealtimeSyncManager(
            coreDataManager: CoreDataManager.shared,
            authManager: authManager,
            supabaseManager: StubSupabaseManager()
        )
        manager.isOnline = false

        manager.queueOperation(
            RealtimeSyncManager.SyncOperation(
                id: UUID().uuidString,
                userId: otherUserId,
                type: .delete,
                data: Data(),
                tableName: "body_metrics",
                timestamp: Date()
            )
        )
        let hasOtherUserPendingOperations = await manager.hasPendingSyncOperations()
        XCTAssertFalse(hasOtherUserPendingOperations)

        manager.queueOperation(
            RealtimeSyncManager.SyncOperation(
                id: UUID().uuidString,
                userId: activeUserId,
                type: .delete,
                data: Data(),
                tableName: "body_metrics",
                timestamp: Date()
            )
        )
        let hasActiveUserPendingOperations = await manager.hasPendingSyncOperations()
        XCTAssertTrue(hasActiveUserPendingOperations)
    }

    func testSyncLocalChangesDeletesMarkedBodyMetricInsteadOfUpserting() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_deleted_realtime_\(UUID().uuidString)"
        let date = Date()

        let metricModel = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 81.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date.addingTimeInterval(-60),
            updatedAt: date
        )

        try await coreData.saveBodyMetricsAndWait(metricModel, userId: userId, markAsSynced: true)
        let didMarkDeleted = await coreData.markBodyMetricDeleted(id: id)
        XCTAssertTrue(didMarkDeleted)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertTrue(stubSupabase.bodyMetricsBatches.isEmpty)
        XCTAssertEqual(stubSupabase.deletedRecords.count, 1)
        XCTAssertEqual(stubSupabase.deletedRecords.first?.table, "body_metrics")
        XCTAssertEqual(stubSupabase.deletedRecords.first?.id, id)

        let unsynced = await coreData.fetchUnsyncedEntries()
        let unsyncedForUser = unsynced.bodyMetrics.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksDailyMetricSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_realtime_\(UUID().uuidString)"
        let date = Date()
        let createdAt = date.addingTimeInterval(-60)
        let updatedAt = date

        let dailyModel = DailyMetrics(
            id: id,
            userId: userId,
            date: date,
            steps: 10_000,
            notes: "unsynced-daily",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try await coreData.saveDailyMetricsAndWait(dailyModel, userId: userId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        // Verify Supabase payload
        XCTAssertEqual(stubSupabase.dailyMetricsBatches.count, 1)
        guard let batch = stubSupabase.dailyMetricsBatches.first,
              let payload = batch.first else {
            XCTFail("No daily metrics batch captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)

        if let stepsValue = payload["steps"] as? Int32 {
            XCTAssertEqual(stepsValue, 10_000)
        } else if let stepsValue = payload["steps"] as? Int {
            XCTAssertEqual(stepsValue, 10_000)
        } else {
            XCTFail("Expected steps field as Int or Int32")
        }

        XCTAssertEqual(payload["notes"] as? String, "unsynced-daily")

        if let dateString = payload["date"] as? String {
            let formatter = ISO8601DateFormatter()
            let sentDate = formatter.date(from: dateString)
            XCTAssertNotNil(sentDate)
        } else {
            XCTFail("Expected date field in payload")
        }

        // Verify Core Data entry for this user is no longer unsynced
        let unsynced = await coreData.fetchUnsyncedEntries()
        let unsyncedForUser = unsynced.dailyMetrics.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksGlp1DoseLogSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_glp1_log_\(UUID().uuidString)"
        let medicationId = UUID().uuidString
        let now = Date(timeIntervalSince1970: 1_780_100_000)
        let log = Glp1DoseLog(
            id: id,
            userId: userId,
            takenAt: now,
            medicationId: medicationId,
            doseAmount: 2.5,
            doseUnit: "mg",
            drugClass: "semaglutide",
            brand: "Ozempic",
            isCompounded: false,
            supplierType: "pharmacy",
            supplierName: "Test Pharmacy",
            notes: "weekly dose",
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now
        )

        try await coreData.saveGlp1DoseLogsAndWait([log], userId: userId, markAsSynced: false)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertEqual(stubSupabase.glp1DoseLogPayloads.count, 1)
        let payload = try XCTUnwrap(stubSupabase.glp1DoseLogPayloads.first)
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["medication_id"] as? String, medicationId)
        XCTAssertEqual(payload["dose_amount"] as? Double, 2.5)
        XCTAssertEqual(payload["dose_unit"] as? String, "mg")
        XCTAssertEqual(payload["brand"] as? String, "Ozempic")

        let remaining = await coreData.fetchUnsyncedGlp1DoseLogs(for: userId)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksGlp1MedicationSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_glp1_med_\(UUID().uuidString)"
        let now = Date(timeIntervalSince1970: 1_780_200_000)
        let endedAt = now.addingTimeInterval(3_600)

        let context = coreData.viewContext
        await context.perform {
            let medication = CachedGlp1Medication(context: context)
            medication.id = id
            medication.userId = userId
            medication.displayName = "Semaglutide"
            medication.genericName = "semaglutide"
            medication.drugClass = "glp1"
            medication.brand = "Ozempic"
            medication.route = "injection"
            medication.frequency = "weekly"
            medication.doseUnit = "mg"
            medication.isCompounded = false
            medication.hkIdentifier = "hk-med-\(UUID().uuidString)"
            medication.startedAt = now
            medication.endedAt = endedAt
            medication.notes = "medication note"
            medication.createdAt = now.addingTimeInterval(-120)
            medication.updatedAt = endedAt
            medication.isSynced = false
            medication.syncStatus = "pending"

            if context.hasChanges {
                try? context.save()
            }
        }

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertEqual(stubSupabase.endedActiveMedicationRequests.count, 1)
        XCTAssertEqual(stubSupabase.endedActiveMedicationRequests.first?.userId, userId)
        XCTAssertEqual(stubSupabase.glp1MedicationPayloads.count, 1)
        let payload = try XCTUnwrap(stubSupabase.glp1MedicationPayloads.first)
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["display_name"] as? String, "Semaglutide")
        XCTAssertEqual(payload["brand"] as? String, "Ozempic")
        XCTAssertEqual(payload["ended_at"] as? String, ISO8601DateFormatter().string(from: endedAt))

        let remaining = await coreData.fetchUnsyncedGlp1Medications(for: userId)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksDexaResultsSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_dexa_realtime_\(UUID().uuidString)"
        let bodyMetricsId = UUID().uuidString
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let createdAt = now.addingTimeInterval(-120)
        let updatedAt = now
        let acquireTime = now.addingTimeInterval(-3_600)
        let analyzeTime = now.addingTimeInterval(-1_800)

        let context = coreData.viewContext
        await context.perform {
            let result = CachedDexaResult(context: context)
            result.id = id
            result.userId = userId
            result.bodyMetricsId = bodyMetricsId
            result.externalSource = "BodySpec"
            result.externalResultId = "result-\(UUID().uuidString)"
            result.externalUpdateTime = now
            result.scannerModel = "TestScanner"
            result.locationId = "loc-123"
            result.locationName = "Test Location"
            result.acquireTime = acquireTime
            result.analyzeTime = analyzeTime
            result.vatMassKg = 1.23
            result.vatVolumeCm3 = 456.0
            result.resultPdfUrl = "https://example.com/result.pdf"
            result.resultPdfName = "result.pdf"
            result.createdAt = createdAt
            result.updatedAt = updatedAt
            result.isSynced = false
            result.syncStatus = "pending"

            if context.hasChanges {
                try? context.save()
            }
        }

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        // Verify Supabase payload
        XCTAssertEqual(stubSupabase.dexaPayloads.count, 1)
        guard let payload = stubSupabase.dexaPayloads.first else {
            XCTFail("No Dexa payload captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["body_metrics_id"] as? String, bodyMetricsId)
        XCTAssertEqual(payload["external_source"] as? String, "BodySpec")
        XCTAssertEqual(payload["result_pdf_url"] as? String, "https://example.com/result.pdf")
        XCTAssertEqual(payload["result_pdf_name"] as? String, "result.pdf")

        if let vatMass = payload["vat_mass_kg"] as? Double {
            XCTAssertEqual(vatMass, 1.23, accuracy: 0.001)
        } else {
            XCTFail("Expected vat_mass_kg in payload")
        }

        if let vatVolume = payload["vat_volume_cm3"] as? Double {
            XCTAssertEqual(vatVolume, 456.0, accuracy: 0.001)
        } else {
            XCTFail("Expected vat_volume_cm3 in payload")
        }

        let formatter = ISO8601DateFormatter()
        let acquireTimeString = try XCTUnwrap(payload["acquire_time"] as? String)
        XCTAssertTrue(acquireTimeString.hasSuffix("Z"))
        XCTAssertEqual(acquireTimeString, formatter.string(from: acquireTime))
        let parsedAcquireTime = try XCTUnwrap(formatter.date(from: acquireTimeString))
        XCTAssertEqual(parsedAcquireTime.timeIntervalSince1970, acquireTime.timeIntervalSince1970, accuracy: 0.001)

        // Verify there are no remaining unsynced Dexa results for this user
        let unsyncedDexa = await coreData.fetchUnsyncedDexaResults()
        let unsyncedForUser = unsyncedDexa.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testCachedDexaResult_toDexaResultMapsFieldsAndNormalizesVatValues() async throws {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext

        let id = UUID().uuidString
        let userId = "mapping_test_user_\(UUID().uuidString)"
        let externalSource = "BodySpec"
        let externalResultId = "result-\(UUID().uuidString)"
        let now = Date()
        let createdAt = now.addingTimeInterval(-300)
        let updatedAt = now

        var mappedWithVat: DexaResult?
        var mappedWithoutVat: DexaResult?

        await context.perform {
            // Case 1: VAT values > 0 should be preserved
            let withVat = CachedDexaResult(context: context)
            withVat.id = id
            withVat.userId = userId
            withVat.bodyMetricsId = "bm-\(UUID().uuidString)"
            withVat.externalSource = externalSource
            withVat.externalResultId = externalResultId
            withVat.externalUpdateTime = now
            withVat.scannerModel = "TestScanner"
            withVat.locationId = "loc-123"
            withVat.locationName = "Test Location"
            withVat.acquireTime = now.addingTimeInterval(-3_600)
            withVat.analyzeTime = now.addingTimeInterval(-1_800)
            withVat.vatMassKg = 2.5
            withVat.vatVolumeCm3 = 789.0
            withVat.resultPdfUrl = "https://example.com/result.pdf"
            withVat.resultPdfName = "result.pdf"
            withVat.createdAt = createdAt
            withVat.updatedAt = updatedAt

            mappedWithVat = withVat.toDexaResult()

            // Case 2: VAT values <= 0 should map to nil
            let withoutVat = CachedDexaResult(context: context)
            withoutVat.id = UUID().uuidString
            withoutVat.userId = userId
            withoutVat.bodyMetricsId = nil
            withoutVat.externalSource = externalSource
            withoutVat.externalResultId = externalResultId
            withoutVat.externalUpdateTime = nil
            withoutVat.scannerModel = nil
            withoutVat.locationId = nil
            withoutVat.locationName = nil
            withoutVat.acquireTime = nil
            withoutVat.analyzeTime = nil
            withoutVat.vatMassKg = 0.0
            withoutVat.vatVolumeCm3 = -10.0
            withoutVat.resultPdfUrl = nil
            withoutVat.resultPdfName = nil
            withoutVat.createdAt = createdAt
            withoutVat.updatedAt = updatedAt

            mappedWithoutVat = withoutVat.toDexaResult()
        }

        let withVat = try XCTUnwrap(mappedWithVat)
        XCTAssertEqual(withVat.id, id)
        XCTAssertEqual(withVat.userId, userId)
        XCTAssertEqual(withVat.externalSource, externalSource)
        XCTAssertEqual(withVat.externalResultId, externalResultId)

        let vatMass = try XCTUnwrap(withVat.vatMassKg)
        XCTAssertEqual(vatMass, 2.5, accuracy: 0.001)

        let vatVolume = try XCTUnwrap(withVat.vatVolumeCm3)
        XCTAssertEqual(vatVolume, 789.0, accuracy: 0.001)

        XCTAssertEqual(withVat.resultPdfUrl, "https://example.com/result.pdf")
        XCTAssertEqual(withVat.resultPdfName, "result.pdf")
        XCTAssertEqual(withVat.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(withVat.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)

        let withoutVat = try XCTUnwrap(mappedWithoutVat)
        XCTAssertEqual(withoutVat.userId, userId)
        XCTAssertEqual(withoutVat.externalSource, externalSource)
        XCTAssertEqual(withoutVat.externalResultId, externalResultId)
        XCTAssertNil(withoutVat.vatMassKg)
        XCTAssertNil(withoutVat.vatVolumeCm3)
    }
}

final class GlobalTimelineServiceTests: XCTestCase {
    private var calendar: Calendar!
    private var service: GlobalTimelineService!

    override func setUp() {
        super.setUp()

        calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        service = GlobalTimelineService(calendar: calendar)
    }

    func testBuildsWeekMonthYearBucketsWithDirectMetricsPhotosStepsAndFFMI() throws {
        let januaryPhoto = "https://example.com/january.jpg"
        let februaryPhoto = "https://example.com/february.jpg"
        let metrics = [
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 2),
                weight: 80,
                bodyFatPercentage: 20,
                photoUrl: januaryPhoto
            ),
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 7),
                weight: 82,
                bodyFatPercentage: 18
            ),
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 2, day: 5),
                weight: 78,
                bodyFatPercentage: 17,
                photoUrl: februaryPhoto
            )
        ]
        let dailyMetrics = [
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 1, day: 3), steps: 5_000),
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 1, day: 4), steps: 7_000),
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 2, day: 6), steps: 10_000)
        ]

        let monthlyBuckets = service.makeBuckets(
            for: .month,
            metrics: metrics,
            dailyMetrics: dailyMetrics,
            heightInches: 70
        )
        let yearlyBuckets = service.makeBuckets(
            for: .year,
            metrics: metrics,
            dailyMetrics: dailyMetrics,
            heightInches: 70
        )

        let january = try XCTUnwrap(monthlyBuckets.first { $0.id == "2026-M01" })
        XCTAssertEqual(january.metrics.weight.presence, .present)
        XCTAssertEqual(try XCTUnwrap(january.metrics.weight.value), 81, accuracy: 0.001)
        XCTAssertEqual(january.metrics.bodyFat.presence, .present)
        XCTAssertEqual(try XCTUnwrap(january.metrics.bodyFat.value), 19, accuracy: 0.001)
        XCTAssertEqual(january.metrics.ffmi.presence, .present)
        XCTAssertNotNil(january.metrics.ffmi.value)
        XCTAssertEqual(january.metrics.steps.presence, .present)
        XCTAssertEqual(try XCTUnwrap(january.metrics.steps.value), 12_000, accuracy: 0.001)
        XCTAssertEqual(january.metrics.canonicalPhotoId, januaryPhoto)
        XCTAssertEqual(january.metrics.photoCount, 1)

        let february = try XCTUnwrap(monthlyBuckets.first { $0.id == "2026-M02" })
        XCTAssertEqual(february.metrics.weight.presence, .present)
        XCTAssertEqual(february.metrics.canonicalPhotoId, februaryPhoto)
        XCTAssertEqual(try XCTUnwrap(february.metrics.steps.value), 10_000, accuracy: 0.001)

        let year = try XCTUnwrap(yearlyBuckets.first { $0.id == "2026" })
        XCTAssertEqual(year.metrics.weight.presence, .present)
        XCTAssertEqual(try XCTUnwrap(year.metrics.weight.value), 80, accuracy: 0.001)
        XCTAssertEqual(year.metrics.bodyFat.presence, .present)
        XCTAssertEqual(try XCTUnwrap(year.metrics.bodyFat.value), 18, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(year.metrics.steps.value), 22_000, accuracy: 0.001)
        XCTAssertEqual(year.metrics.photoCount, 2)
    }

    func testSparseBucketsSurfaceInterpolatedAndLastKnownWithoutMeasuredPresence() throws {
        let metrics = [
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 1),
                weight: 80,
                bodyFatPercentage: 20
            ),
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 15),
                weight: 82,
                bodyFatPercentage: 18
            )
        ]
        let dailyMetrics = [
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 2, day: 10), steps: 3_000)
        ]

        let weeklyBuckets = service.makeBuckets(
            for: .week,
            metrics: metrics,
            dailyMetrics: dailyMetrics,
            heightInches: 70
        )

        let interpolatedWeek = try XCTUnwrap(weeklyBuckets.first { $0.id == "2026-W02" })
        XCTAssertEqual(interpolatedWeek.metrics.weight.presence, .interpolated)
        XCTAssertEqual(interpolatedWeek.metrics.weight.confidence, .medium)
        XCTAssertEqual(try XCTUnwrap(interpolatedWeek.metrics.weight.value), 81, accuracy: 0.2)
        XCTAssertEqual(interpolatedWeek.metrics.bodyFat.presence, .interpolated)
        XCTAssertEqual(interpolatedWeek.metrics.bodyFat.confidence, .medium)
        XCTAssertEqual(interpolatedWeek.metrics.ffmi.presence, .interpolated)

        let lastKnownWeek = try XCTUnwrap(weeklyBuckets.first { $0.id == "2026-W07" })
        XCTAssertEqual(lastKnownWeek.metrics.weight.presence, .lastKnown)
        XCTAssertEqual(try XCTUnwrap(lastKnownWeek.metrics.weight.value), 82, accuracy: 0.001)
        XCTAssertEqual(lastKnownWeek.metrics.bodyFat.presence, .lastKnown)
        XCTAssertEqual(try XCTUnwrap(lastKnownWeek.metrics.bodyFat.value), 18, accuracy: 0.001)
        XCTAssertEqual(lastKnownWeek.metrics.ffmi.presence, .lastKnown)
        XCTAssertEqual(lastKnownWeek.metrics.steps.presence, .present)
        XCTAssertEqual(try XCTUnwrap(lastKnownWeek.metrics.steps.value), 3_000, accuracy: 0.001)
    }

    func testMissingValuesStayMissingWhenInterpolationGapIsTooWide() throws {
        let metrics = [
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 1),
                weight: 80,
                bodyFatPercentage: 20
            ),
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 3, day: 15),
                weight: 85,
                bodyFatPercentage: 18
            )
        ]
        let dailyMetrics = [
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 2, day: 15), steps: 9_000)
        ]

        let monthlyBuckets = service.makeBuckets(
            for: .month,
            metrics: metrics,
            dailyMetrics: dailyMetrics,
            heightInches: 70
        )

        let february = try XCTUnwrap(monthlyBuckets.first { $0.id == "2026-M02" })
        XCTAssertEqual(february.metrics.weight.presence, .missing)
        XCTAssertNil(february.metrics.weight.value)
        XCTAssertEqual(february.metrics.bodyFat.presence, .missing)
        XCTAssertNil(february.metrics.bodyFat.value)
        XCTAssertEqual(february.metrics.ffmi.presence, .missing)
        XCTAssertEqual(february.metrics.steps.presence, .present)
        XCTAssertEqual(try XCTUnwrap(february.metrics.steps.value), 9_000, accuracy: 0.001)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }

    private func makeTimelineMetric(
        date: Date,
        weight: Double? = nil,
        bodyFatPercentage: Double? = nil,
        photoUrl: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: "timeline-user",
            date: date,
            weight: weight,
            weightUnit: weight == nil ? nil : "kg",
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatPercentage == nil ? nil : "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoUrl,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private func makeTimelineDailyMetric(date: Date, steps: Int) -> DailyMetrics {
        DailyMetrics(
            id: UUID().uuidString,
            userId: "timeline-user",
            date: date,
            steps: steps,
            notes: nil,
            createdAt: date,
            updatedAt: date
        )
    }
}

final class MockHealthSyncCoordinator: HealthSyncCoordinating {
    private(set) var didCallBootstrapIfNeeded = false
    private(set) var lastBootstrapSyncEnabled: Bool?

    private(set) var didCallResetForCurrentUser = false
    private(set) var didCallConfigureWeightOnly = false
    private(set) var didCallConfigureWeightAndSteps = false
    private(set) var didCallWarmUpAfterLogin = false
    private(set) var didCallPerformInitialConnectSync = false
    private(set) var didCallRunDeferredOnboardingWeightSync = false
    private(set) var didCallSyncWeightFromHealthKit = false
    private(set) var didCallSyncStepsFromHealthKit = false
    private(set) var didCallForceFullHealthKitSync = false

    var performInitialConnectSyncError: Error?
    var syncWeightError: Error?
    var syncStepsError: Error?

    func bootstrapIfNeeded(syncEnabled: Bool) {
        didCallBootstrapIfNeeded = true
        lastBootstrapSyncEnabled = syncEnabled
    }

    func resetForCurrentUser() async {
        didCallResetForCurrentUser = true
    }

    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync() async {
        didCallConfigureWeightOnly = true
    }

    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync() async {
        didCallConfigureWeightAndSteps = true
    }

    func warmUpAfterLoginIfNeeded() async {
        didCallWarmUpAfterLogin = true
    }

    func performInitialConnectSync() async throws {
        didCallPerformInitialConnectSync = true
        if let error = performInitialConnectSyncError {
            throw error
        }
    }

    func runDeferredOnboardingWeightSync() async {
        didCallRunDeferredOnboardingWeightSync = true
    }

    func syncWeightFromHealthKit() async throws {
        didCallSyncWeightFromHealthKit = true
        if let error = syncWeightError {
            throw error
        }
    }

    func syncStepsFromHealthKit() async throws {
        didCallSyncStepsFromHealthKit = true
        if let error = syncStepsError {
            throw error
        }
    }

    func forceFullHealthKitSync() async {
        didCallForceFullHealthKitSync = true
    }
}

final class MockHealthKitSyncManager: HealthKitSyncManaging {
    var isHealthKitAvailable = true
    var isAuthorized = true

    private(set) var didCallCheckAuthorizationStatus = false
    private(set) var didCallObserveWeightChanges = false
    private(set) var didCallObserveBodyFatChanges = false
    private(set) var didCallObserveStepChanges = false
    private(set) var setupBackgroundDeliveryCallCount = 0
    private(set) var setupStepCountBackgroundDeliveryCallCount = 0
    private(set) var didCallResetForCurrentUser = false
    private(set) var syncWeightFromHealthKitCallCount = 0
    private(set) var syncStepsFromHealthKitCallCount = 0
    private(set) var fetchTodayStepCountCallCount = 0
    private(set) var didCallForceFullHealthKitSync = false

    func checkAuthorizationStatus() {
        didCallCheckAuthorizationStatus = true
    }

    func observeWeightChanges() {
        didCallObserveWeightChanges = true
    }

    func observeBodyFatChanges() {
        didCallObserveBodyFatChanges = true
    }

    func observeStepChanges() {
        didCallObserveStepChanges = true
    }

    func setupBackgroundDelivery() async throws {
        setupBackgroundDeliveryCallCount += 1
    }

    func setupStepCountBackgroundDelivery() async throws {
        setupStepCountBackgroundDeliveryCallCount += 1
    }

    func resetForCurrentUser() async {
        didCallResetForCurrentUser = true
    }

    func syncWeightFromHealthKit() async throws {
        syncWeightFromHealthKitCallCount += 1
    }

    func syncStepsFromHealthKit() async throws {
        syncStepsFromHealthKitCallCount += 1
    }

    func fetchTodayStepCount() async throws -> Int {
        fetchTodayStepCountCallCount += 1
        return 123
    }

    func forceFullHealthKitSync() async {
        didCallForceFullHealthKitSync = true
    }
}

@MainActor
final class HealthSyncCoordinatorPipelineTests: XCTestCase {
    func testBootstrapSkipsHealthKitWhenSyncIsDisabled() async {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        coordinator.bootstrapIfNeeded(syncEnabled: false)
        await Task.yield()

        XCTAssertFalse(manager.didCallCheckAuthorizationStatus)
        XCTAssertFalse(manager.didCallObserveWeightChanges)
        XCTAssertFalse(manager.didCallObserveBodyFatChanges)
        XCTAssertFalse(manager.didCallObserveStepChanges)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 0)
        XCTAssertEqual(manager.setupStepCountBackgroundDeliveryCallCount, 0)
    }

    func testBootstrapConfiguresBodyMetricAndStepObserversWithBackgroundDelivery() async throws {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        coordinator.bootstrapIfNeeded(syncEnabled: true)
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(manager.didCallCheckAuthorizationStatus)
        XCTAssertTrue(manager.didCallObserveWeightChanges)
        XCTAssertTrue(manager.didCallObserveBodyFatChanges)
        XCTAssertTrue(manager.didCallObserveStepChanges)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 1)
        XCTAssertEqual(manager.setupStepCountBackgroundDeliveryCallCount, 1)
    }

    func testDeferredOnboardingWeightSyncBootstrapsBodyMetricPipelineBeforeImport() async {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        await coordinator.runDeferredOnboardingWeightSync()
        await Task.yield()

        XCTAssertTrue(manager.didCallObserveWeightChanges)
        XCTAssertTrue(manager.didCallObserveBodyFatChanges)
        XCTAssertTrue(manager.didCallObserveStepChanges)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 1)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
    }

    func testInitialConnectSyncBootstrapsObserversAndRunsInitialImports() async throws {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        try await coordinator.performInitialConnectSync()
        await Task.yield()

        XCTAssertTrue(manager.didCallObserveWeightChanges)
        XCTAssertTrue(manager.didCallObserveBodyFatChanges)
        XCTAssertTrue(manager.didCallObserveStepChanges)
        XCTAssertGreaterThanOrEqual(manager.setupBackgroundDeliveryCallCount, 1)
        XCTAssertGreaterThanOrEqual(manager.setupStepCountBackgroundDeliveryCallCount, 1)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
        XCTAssertEqual(manager.fetchTodayStepCountCallCount, 1)
    }
}

@MainActor
final class DashboardViewModelHealthSyncWiringTests: XCTestCase {
    func testCanInitializeWithMockHealthSyncCoordinator() {
        let viewModel = DashboardViewModel(
            healthKitManager: HealthKitManager.shared,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )

        XCTAssertNotNil(viewModel)
    }

    func testRefreshSkipsHealthKitSyncWhenDeniedAndKeepsLocalMetrics() async throws {
        let userId = "dashboard_healthkit_denied_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_denied@example.com",
            name: "HealthKit Denied",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        let authManager = AuthManager()
        authManager.currentUser = user
        authManager.isAuthenticated = true

        let localMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: Date(),
            weight: 82.1,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "manual still works",
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        CoreDataManager.shared.saveBodyMetrics(localMetric, userId: userId, markAsSynced: false)

        let healthKitManager = HealthKitManager.shared
        healthKitManager.isAuthorized = false
        let mockCoordinator = MockHealthSyncCoordinator()
        let viewModel = DashboardViewModel(
            healthKitManager: healthKitManager,
            healthSyncCoordinator: mockCoordinator
        )

        await viewModel.refreshData(
            authManager: authManager,
            realtimeSyncManager: RealtimeSyncManager.shared
        )

        XCTAssertFalse(mockCoordinator.didCallSyncWeightFromHealthKit)
        XCTAssertTrue(viewModel.hasLoadedInitialData)
        XCTAssertEqual(viewModel.bodyMetrics.first?.id, localMetric.id)
        XCTAssertEqual(viewModel.bodyMetrics.first?.dataSource, "manual")
    }
}

@MainActor
final class LoadingManagerHealthSyncTests: XCTestCase {
    func testStartLoadingCompletesBlockingPhase() async {
        let authManager = AuthManager()
        authManager.isAuthenticated = false

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )

        await manager.startLoading()

        XCTAssertFalse(manager.isLoading)
        XCTAssertEqual(manager.progress, 1.0, accuracy: 0.001)
        XCTAssertEqual(manager.loadingStatus, "Ready!")
        XCTAssertFalse(mockCoordinator.didCallWarmUpAfterLogin)
    }

    func testRunWarmUpTasksInvokesHealthSyncWhenAuthenticated() async {
        let authManager = AuthManager()
        authManager.isAuthenticated = true

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )

        await manager.runWarmUpTasks()

        XCTAssertTrue(mockCoordinator.didCallWarmUpAfterLogin)
    }

    func testRunWarmUpTasksSkipsWhenNotAuthenticated() async {
        let authManager = AuthManager()
        authManager.isAuthenticated = false

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )

        await manager.runWarmUpTasks()

        XCTAssertFalse(mockCoordinator.didCallWarmUpAfterLogin)
    }
}

final class MetricChartDataPointPresenceTests: XCTestCase {
    func testEstimatedInitializerMapsToInterpolatedPresence() {
        let point = MetricChartDataPoint(
            date: Date(timeIntervalSince1970: 100),
            value: 15.2,
            isEstimated: true
        )

        XCTAssertEqual(point.presence, .interpolated)
        XCTAssertTrue(point.isEstimated)
    }

    func testExplicitPresenceSupportsLastKnownAndMissingStates() {
        let lastKnownPoint = MetricChartDataPoint(
            date: Date(timeIntervalSince1970: 200),
            value: 181.0,
            presence: .lastKnown
        )
        let measuredPoint = MetricChartDataPoint(
            date: Date(timeIntervalSince1970: 300),
            value: 180.5
        )

        XCTAssertEqual(lastKnownPoint.presence, .lastKnown)
        XCTAssertTrue(lastKnownPoint.isEstimated)
        XCTAssertEqual(measuredPoint.presence, .present)
        XCTAssertFalse(measuredPoint.isEstimated)
        XCTAssertTrue(MetricPresence.allCases.contains(.missing))
    }
}

// swiftlint:enable single_test_class
