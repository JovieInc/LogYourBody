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

        XCTAssertEqual(sanitized["fullName"] as? String, "Profile User")
        XCTAssertEqual(sanitized["dateOfBirth"] as? String, "1990-01-01")
        XCTAssertEqual(sanitized["heightUnit"] as? String, "cm")
        XCTAssertEqual(sanitized["onboardingCompleted"] as? Bool, true)
        XCTAssertEqual(sanitized["activityLevel"] as? String, "active")
        XCTAssertNil(sanitized["id"])
        XCTAssertNil(sanitized["email"])
        XCTAssertNil(sanitized["full_name"])
        XCTAssertNil(sanitized["date_of_birth"])
        XCTAssertNil(sanitized["onboarding_completed"])
        XCTAssertNil(sanitized["avatar_url"])
    }

    func testFirstPartyProfilePatchMapsLegacyNameAndDropsUnknownKeys() throws {
        let payload = try SupabaseManager.firstPartyProfilePatchBody([
            "name": "Tim White",
            "goalWeightUnit": "lbs",
            "avatarUrl": "https://example.com/avatar.png",
            "unknown": "drop-me"
        ])

        XCTAssertEqual(payload["fullName"] as? String, "Tim White")
        XCTAssertEqual(payload["goalWeightUnit"] as? String, "lb")
        XCTAssertNil(payload["name"])
        XCTAssertNil(payload["unknown"])
        XCTAssertNil(payload["avatarUrl"])
    }

    func testAuthManagerNormalizedPayloadUsesFirstPartyAllowlist() throws {
        let payload = try AuthManager.normalizedProductProfilePayload([
            "name": "Settings User",
            "dateOfBirth": Date(timeIntervalSince1970: 631_152_000),
            "height": 180.0,
            "heightUnit": "cm"
        ])

        XCTAssertEqual(payload["fullName"] as? String, "Settings User")
        XCTAssertEqual(payload["dateOfBirth"] as? String, "1990-01-01")
        XCTAssertEqual(payload["height"] as? Double, 180.0)
        XCTAssertNil(payload["name"])
    }
}
