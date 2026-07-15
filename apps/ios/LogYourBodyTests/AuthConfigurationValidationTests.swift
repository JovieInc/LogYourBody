import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody

final class AuthConfigurationValidationTests: XCTestCase {
    func testProductionRejectsWrongIdentityIssuerAndTelemetryConfig() {
        let snapshot = makeSnapshot(
            environment: .production,
            authIssuer: "https://identity.example.com",
            apiBaseURL: "http" + "://localhost:3000",
            revenueCatAPIKey: "replace_with_prod_revenuecat_public_key",
            sentryEnvironment: "development",
            statsigEnvironmentTier: "development"
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.messages.contains("Production authentication must use the Jovie identity issuer."))
        XCTAssertTrue(result.messages.contains("Production API base URL must use HTTPS."))
        XCTAssertTrue(result.messages.contains("Production RevenueCat API key must be configured."))
        XCTAssertTrue(result.messages.contains("Production Sentry environment must be production."))
        XCTAssertTrue(result.messages.contains("Production Statsig tier must be production."))
    }

    func testRejectsWrongNativeOAuthClient() {
        let snapshot = makeSnapshot(authClientID: "some-other-client")
        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.messages.contains("Authentication client must be logyourbody-ios."))
    }

    func testRejectsInvalidNativeRedirectURI() {
        let snapshot = makeSnapshot(authRedirectURI: "https://jov.ie/callback")
        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertTrue(result.messages.contains("Authentication redirect URI must be logyourbody://oauth."))
    }

    func testValidProductionSharedIdentityConfigurationPasses() {
        let result = Configuration.validateAuthEnvironment(makeSnapshot(environment: .production))

        XCTAssertTrue(result.isValid, "Validation should pass: \(result.messages)")
    }

    private func makeSnapshot(
        environment: LogYourBody.Configuration.AppEnvironment = .development,
        authIssuer: String = "https://jov.ie/api/auth",
        authClientID: String = "logyourbody-ios",
        authRedirectURI: String = "logyourbody://oauth",
        apiBaseURL: String = "https://logyourbody.com",
        revenueCatAPIKey: String = "appl_prod_123",
        sentryEnvironment: String = "production",
        statsigEnvironmentTier: String = "production"
    ) -> LogYourBody.Configuration.AuthEnvironmentSnapshot {
        LogYourBody.Configuration.AuthEnvironmentSnapshot(
            environment: environment,
            authIssuer: authIssuer,
            authClientID: authClientID,
            authRedirectURI: authRedirectURI,
            apiBaseURL: apiBaseURL,
            apiExpectedHost: apiBaseURL.contains("localhost") ? "localhost" : "logyourbody.com",
            revenueCatAPIKey: revenueCatAPIKey,
            sentryEnvironment: sentryEnvironment,
            statsigEnvironmentTier: statsigEnvironmentTier,
            allowProductionServicesInDevelopment: false
        )
    }
}
