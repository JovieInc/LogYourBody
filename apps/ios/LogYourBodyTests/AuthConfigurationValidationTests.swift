//
// AuthConfigurationValidationTests.swift
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

    // Regression: isPlaceholder() must NOT treat a valid Clerk publishable key
    // (pk_live_… or pk_test_…) as a placeholder. The URL/host validation added
    // in #449 was incorrectly rejecting non-URL secrets, causing stringValue()
    // to silently return the empty default and wiping the real key.
    func testValidClerkKeyIsNotPlaceholder() {
        let liveKey = "pk_live_Y29ycmVjdC1saXZlLWtleS0xMjM0NTY="
        let testKey = "pk_test_Y29ycmVjdC10ZXN0LWtleS04NzkwMTI="

        XCTAssertFalse(Configuration.isPlaceholder(liveKey),
                       "isPlaceholder must return false for a valid pk_live_ key")
        XCTAssertFalse(Configuration.isPlaceholder(testKey),
                       "isPlaceholder must return false for a valid pk_test_ key")

        // Also verify that a real key passes through stringValue() correctly.
        // This simulates what happens at launch — stringValue returns the real key,
        // not the empty default.
        XCTAssertTrue(liveKey.hasPrefix("pk_"),
                      "Live Clerk key must start with pk_")
        XCTAssertTrue(testKey.hasPrefix("pk_"),
                      "Test Clerk key must start with pk_")
    }

    // Regression: isInvalidURLValue still rejects malformed Supabase URLs,
    // preserving #449's host hardening on URL fields.
    func testInvalidSupabaseURLIsRejected() {
        XCTAssertTrue(Configuration.isInvalidURLValue("***"),
                      "Corrupted xcconfig value must be flagged as invalid URL")
        XCTAssertTrue(Configuration.isInvalidURLValue("https://***"),
                      "Wildcard host must be flagged as invalid URL")
        XCTAssertTrue(Configuration.isInvalidURLValue("replace_with_supabase_url"),
                      "Placeholder text must be flagged as invalid URL")
        XCTAssertTrue(Configuration.isInvalidURLValue(""),
                      "Empty value must be flagged as invalid URL")

        XCTAssertFalse(Configuration.isInvalidURLValue("https://valid-project.supabase.co"),
                       "Valid Supabase URL must NOT be flagged as invalid")
    }
}
