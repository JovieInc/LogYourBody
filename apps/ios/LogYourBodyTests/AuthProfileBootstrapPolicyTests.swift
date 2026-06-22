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
