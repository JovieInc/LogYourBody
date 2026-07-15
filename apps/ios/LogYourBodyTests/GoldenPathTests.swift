//
// GoldenPathTests.swift
// LogYourBodyTests
//
// THE GOLDEN PATH GATE.
//
// The one journey that must always work for a paying user:
//   Launch → Sign in (email OTP) → Subscribe (Premium) → Log today's weight
//   → See it on the timeline → It survives offline and syncs.
//
// Canonical definition: docs/GOLDEN_PATH.md. Every test maps to a stage
// contract; a failure here means a paying user cannot complete the core
// value loop and must be treated as a P0. If a product decision changes a
// contract, update the test AND docs/GOLDEN_PATH.md in the same PR.
//
// These tests are deterministic and pure: no network, no simulator state,
// no time-of-day dependence (fixed epoch dates throughout).
//
import XCTest
import UIKit
@testable import LogYourBody

final class GoldenPathTests: XCTestCase {
    // Fixed "today" so the suite never depends on wall-clock time.
    private let today = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Stage 1 · Launch: pinned surface, sign-in method, entitlement

    func testGP1_PaidSurfaceIsPhotoTimelineHUD() {
        XCTAssertEqual(
            PaidAppSurfacePolicy.surface(),
            .photoTimelineHUD,
            "Paid home surface is pinned to the photo timeline HUD; changing it must update docs/GOLDEN_PATH.md"
        )
    }

    func testGP1_PrimarySignInMethodIsApple() {
        XCTAssertEqual(
            AuthSurfacePolicy.primarySignInMethod,
            "apple",
            "Apple is the launch-premise primary sign-in method"
        )
    }

    func testGP1_ProEntitlementIDMatchesRevenueCatDashboard() {
        XCTAssertEqual(
            Constants.proEntitlementID,
            "Premium",
            "Entitlement ID must match the RevenueCat dashboard exactly; a drift here silently locks out every paying customer"
        )
    }

    // MARK: - Stage 2 · Sign in: the auth gate is absolute

    func testGP2_UnauthenticatedUserNeverReachesPaidSurface() {
        XCTAssertFalse(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: false,
                user: makeCompleteUser(),
                hasCompletedOnboarding: true,
                isSubscribed: true
            ),
            "No amount of onboarding or subscription may bypass authentication"
        )
    }

    func testGP2_ProfileCompletionRequiresCoreIdentityFields() {
        XCTAssertFalse(ProfileCompletionPolicy.isComplete(user: nil))

        // A complete profile: name + DOB + height + gender.
        XCTAssertTrue(ProfileCompletionPolicy.isComplete(user: makeCompleteUser()))

        // Missing height -> incomplete.
        let missingHeight = makeCompleteUser(height: nil)
        XCTAssertFalse(ProfileCompletionPolicy.isComplete(user: missingHeight))

        // Whitespace-only name with no fallback -> incomplete.
        XCTAssertFalse(
            ProfileCompletionPolicy.isComplete(
                profile: makeProfile(fullName: "   ", height: 180),
                fallbackName: "  "
            )
        )
    }

    // MARK: - Stage 3 · Subscribe: the paywall gates, and only the paywall

    func testGP3_UnsubscribedUserIsGated() {
        XCTAssertFalse(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true,
                user: makeCompleteUser(),
                hasCompletedOnboarding: true,
                isSubscribed: false
            ),
            "This is a paid app: an authenticated, onboarded user without the Premium entitlement stays at the paywall"
        )
    }

    func testGP3_FullyQualifiedUserPassesEveryGate() {
        XCTAssertTrue(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true,
                user: makeCompleteUser(),
                hasCompletedOnboarding: true,
                isSubscribed: true
            ),
            "Authed + onboarded + complete profile + subscribed must open the paid surface, or paying customers are locked out"
        )
    }

    func testGP3_TrialTransitionsEmitTheRightAnalyticsEvents() {
        XCTAssertEqual(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .none, to: .trial),
            .trialStart
        )
        XCTAssertEqual(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .trial, to: .paid),
            .trialConvertedToPaid
        )
        XCTAssertEqual(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .trial, to: .expiredUnpaid),
            .trialExpiredUnpaid
        )
        XCTAssertNil(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .paid, to: .paid),
            "Steady state must not re-emit conversion events"
        )
    }

    // MARK: - Stage 4 · Log weight: the atomic act of value

    func testGP4_ValidWeightsAreAcceptedInBothUnits() {
        XCTAssertTrue(
            PaidWeightLoggerMVPPolicy.canSaveWeight(weightText: "182.4", unit: "lbs", isSaving: false)
        )
        XCTAssertTrue(
            PaidWeightLoggerMVPPolicy.canSaveWeight(weightText: "82.5", unit: "kg", isSaving: false)
        )
        XCTAssertNil(PaidWeightLoggerMVPPolicy.validationMessage(weightText: "182.4", unit: "lbs"))
        XCTAssertNil(PaidWeightLoggerMVPPolicy.validationMessage(weightText: "82.5", unit: "kg"))
    }

    func testGP4_GarbageAndOutOfRangeInputIsRejectedWithPlainLanguage() {
        // Empty and non-numeric input can never save.
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(weightText: "", unit: "lbs", isSaving: false)
        )
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(weightText: "abc", unit: "lbs", isSaving: false)
        )

        // Out-of-range input is rejected and the message names the exact rule.
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(weightText: "12", unit: "lbs", isSaving: false)
        )
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.validationMessage(weightText: "12", unit: "lbs"),
            "Enter a weight between 70 and 660 lbs"
        )
        XCTAssertNotNil(
            PaidWeightLoggerMVPPolicy.validationMessage(weightText: "999", unit: "kg"),
            "Out-of-range kg input must produce a validation message"
        )
    }

    func testGP4_NoDoubleSubmitWhileSaving() {
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(weightText: "182.4", unit: "lbs", isSaving: true),
            "An in-flight save must disable the save action"
        )
    }

    // MARK: - Stage 5 · See it: the log appears on the timeline, today, as measured

    func testGP5_TodaysLogAppearsOnTimelineAsMeasured() {
        let provider = TimelineDataProvider()
        provider.loadMetrics([
            makeMetric(id: "gp-yesterweek", date: today.addingTimeInterval(-86_400 * 9), weight: 183.1),
            makeMetric(id: "gp-today", date: today, weight: 182.4)
        ])

        let result = provider.findDataForPhotoMode(scrubDate: today)
        XCTAssertEqual(
            result.metrics?.bodyMetrics.id,
            "gp-today",
            "The weight logged today must resolve at today's scrub position"
        )
        XCTAssertEqual(
            result.metrics?.isInterpolated,
            false,
            "A real log must surface as measured data, never interpolated"
        )
        XCTAssertEqual(result.metrics?.bodyMetrics.weight, 182.4)

        // And the HUD must label measured data as such.
        XCTAssertEqual(PhotoTimelineHUDPolicy.stateText(presence: .present), "Measured")
    }

    func testGP5_TimelineSnapsToTheLoggedDate() {
        let provider = TimelineDataProvider()
        let loggedDate = today.addingTimeInterval(-86_400 * 3)
        provider.loadMetrics([
            makeMetric(id: "gp-old", date: today.addingTimeInterval(-86_400 * 30), weight: 185.0),
            makeMetric(id: "gp-logged", date: loggedDate, weight: 182.4)
        ])

        // Scrubbing near (not exactly on) the log must snap to it.
        XCTAssertEqual(
            provider.findNearestDataDate(to: loggedDate.addingTimeInterval(86_400)),
            loggedDate,
            "The scrubber must snap to the nearest real data point"
        )
    }

    // MARK: - Stage 6 · It survives: offline saves, honest status, lossless sync batching

    func testGP6_OfflineSaveIsHonestAndReassuring() {
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.syncStatusText(status: .offline, pendingCount: 1),
            "Saved offline"
        )
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.syncStatusText(status: .idle, pendingCount: 1),
            "Pending sync"
        )
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.savedConfirmationText(isOnline: false),
            "Saved locally. Will sync when online."
        )
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.savedConfirmationText(isOnline: true),
            "Saved locally. Pending sync."
        )
    }

    func testGP6_SyncBatchingNeverDropsOrReordersEntries() {
        let entries = Array(0..<137)
        let chunks = entries.chunked(into: 50)
        XCTAssertEqual(
            chunks.flatMap { $0 },
            entries,
            "Sync batching must preserve every logged entry in order; silent data loss is the worst failure"
        )
    }

    func testGP6_BatteryPolicyThrottlesButNeverStopsSync() {
        // Charging syncs aggressively…
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .charging, level: 0.1), 60)
        // …and even a nearly dead battery still syncs on a finite interval.
        let lowBatteryInterval = BatterySyncIntervalPolicy.interval(state: .unplugged, level: 0.05)
        XCTAssertGreaterThan(lowBatteryInterval, 0)
        XCTAssertLessThanOrEqual(
            lowBatteryInterval,
            3_600,
            "Sync must never be deferred beyond an hour — the log has to reach the server the same session where possible"
        )
    }

    // MARK: - Stage 7 · The full journey, end to end

    func testGP7_FullGoldenPathEndToEnd() {
        // 1. Launch: the paid surface is the photo timeline HUD.
        XCTAssertEqual(PaidAppSurfacePolicy.surface(), .photoTimelineHUD)

        // 2-3. Sign in + subscribe: gates open only when every requirement is met.
        let user = makeCompleteUser()
        XCTAssertFalse(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true, user: user, hasCompletedOnboarding: true, isSubscribed: false
            )
        )
        XCTAssertTrue(
            EntryDeepLinkPolicy.canOpenEntrySheet(
                isAuthenticated: true, user: user, hasCompletedOnboarding: true, isSubscribed: true
            )
        )

        // 4. Log today's weight.
        let weightText = "182.4"
        XCTAssertTrue(
            PaidWeightLoggerMVPPolicy.canSaveWeight(weightText: weightText, unit: "lbs", isSaving: false)
        )

        // 5. See it on the timeline, today, as measured.
        let provider = TimelineDataProvider()
        provider.loadMetrics([makeMetric(id: "gp7-today", date: today, weight: 182.4)])
        let shown = provider.findDataForPhotoMode(scrubDate: today)
        XCTAssertEqual(shown.metrics?.bodyMetrics.weight, 182.4)
        XCTAssertEqual(shown.metrics?.isInterpolated, false)

        // 6. It survives: offline status is honest while the entry waits to sync.
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.syncStatusText(status: .offline, pendingCount: 1),
            "Saved offline"
        )
    }

    // MARK: - Helpers

    private func makeProfile(
        fullName: String? = "Golden Path",
        dateOfBirth: Date? = Date(timeIntervalSince1970: 631_152_000),
        height: Double? = 180,
        gender: String? = "male"
    ) -> UserProfile {
        UserProfile(
            id: "golden-path-user",
            email: "golden@path.test",
            username: nil,
            fullName: fullName,
            dateOfBirth: dateOfBirth,
            height: height,
            heightUnit: "cm",
            gender: gender,
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: true
        )
    }

    private func makeCompleteUser(height: Double? = 180) -> User {
        User(
            id: "golden-path-user",
            email: "golden@path.test",
            name: "Golden Path",
            avatarUrl: nil,
            profile: makeProfile(height: height),
            onboardingCompleted: true
        )
    }

    private func makeMetric(
        id: String,
        date: Date,
        weight: Double?,
        bodyFat: Double? = nil,
        photoUrl: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "golden-path-user",
            date: date,
            localDate: nil,
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
            updatedAt: date
        )
    }
}
