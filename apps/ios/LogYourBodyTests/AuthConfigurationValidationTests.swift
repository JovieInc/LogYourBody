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

    func testValidClerkLiveKeyIsNotTreatedAsPlaceholder() {
        // Regression guard: a real pk_live_ key must survive stringValue()
        // and not be treated as a placeholder by the URL/host fallback.
        let snapshot = Configuration.AuthEnvironmentSnapshot(
            environment: .production,
            clerkPublishableKey: "pk_live_Y2xlcmsua292YXNpay5haS5hcHBfMTAy",
            supabaseURL: "https://prod-project.supabase.co",
            supabaseExpectedHost: "prod-project.supabase.co",
            apiBaseURL: "https://www.logyourbody.com",
            apiExpectedHost: "www.logyourbody.com",
            revenueCatAPIKey: "appl_prod_123",
            sentryEnvironment: "production",
            statsigEnvironmentTier: "production",
            allowProductionServicesInDevelopment: false
        )

        // The key must NOT be flagged as a placeholder by the generic check.
        XCTAssertFalse(
            Configuration.isPlaceholder(snapshot.clerkPublishableKey),
            "A valid pk_live_ key must not be treated as a placeholder"
        )

        // The key must NOT be flagged as an invalid URL value
        // (it is not a URL, so URL validation is not applicable).
        XCTAssertFalse(
            Configuration.isInvalidURLValue(snapshot.clerkPublishableKey),
            "A valid pk_live_ key must not be treated as an invalid URL value"
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        // No Clerk-related error should be emitted for a valid pk_live_ key.
        XCTAssertTrue(result.isValid, "Validation should pass: \(result.messages)")
        XCTAssertFalse(
            result.messages.contains(where: { $0.contains("Clerk") }),
            "No Clerk-related errors should appear: \(result.messages)"
        )
    }
}
