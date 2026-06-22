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
