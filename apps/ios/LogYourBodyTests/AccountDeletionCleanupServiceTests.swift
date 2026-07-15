//
// AccountDeletionAndShareCardTests.swift
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


final class AccountDeletionCleanupServiceTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case productDeletionFailed
        case coreDataCleanupFailed
    }

    func testPerformDeletionRunsProviderAndLocalCleanupInOrder() async throws {
        var events: [String] = []
        let service = AccountDeletionCleanupService(
            dependencies: .init(
                logoutSubscriptionProvider: {
                    events.append("revenuecat")
                },
                resetHealthKitAnchors: {
                    events.append("healthkit")
                },
                deleteProductAccount: {
                    events.append("product")
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
                "product",
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
                logoutSubscriptionProvider: {
                    events.append("revenuecat")
                },
                resetHealthKitAnchors: {
                    events.append("healthkit")
                },
                deleteProductAccount: {
                    events.append("product")
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
                "product",
                "coredata",
                "keychain",
                "defaults",
                "spotlight",
                "auth"
            ]
        )
    }

    func testPerformDeletionStopsBeforeLocalCleanupWhenProductDeletionFails() async {
        var events: [String] = []
        let service = AccountDeletionCleanupService(
            dependencies: .init(
                logoutSubscriptionProvider: {
                    events.append("revenuecat")
                },
                resetHealthKitAnchors: {
                    events.append("healthkit")
                },
                deleteProductAccount: {
                    events.append("product")
                    throw TestError.productDeletionFailed
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
            XCTFail("Expected product deletion failure to be rethrown")
        } catch {
            XCTAssertEqual(error as? TestError, .productDeletionFailed)
        }

        XCTAssertEqual(events, ["revenuecat", "healthkit", "product"])
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
