//
// AuthLegacyStorageMigrationTests.swift
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
