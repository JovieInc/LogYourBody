//
// Configuration.swift
// LogYourBody
//
// Secure configuration manager that reads values from Config.xcconfig (via Info.plist)
// This ensures API keys and secrets are never hardcoded in source files
//
import Foundation

enum Configuration {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }

    enum AppEnvironment: String {
        case development
        case production

        static func from(rawValue: String?) -> AppEnvironment {
            switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "production", "prod", "release":
                return .production
            default:
                return .development
            }
        }
    }

    struct AuthEnvironmentSnapshot {
        let environment: AppEnvironment
        let clerkPublishableKey: String
        let supabaseURL: String
        let supabaseExpectedHost: String
        let apiBaseURL: String
        let apiExpectedHost: String
        let revenueCatAPIKey: String
        let sentryEnvironment: String
        let statsigEnvironmentTier: String
        let allowProductionServicesInDevelopment: Bool
    }

    struct AuthEnvironmentValidationResult {
        let messages: [String]

        var isValid: Bool {
            messages.isEmpty
        }

        var userMessage: String {
            guard !messages.isEmpty else { return "" }
            return "Authentication configuration error: \(messages.joined(separator: " "))"
        }
    }

    // MARK: - Generic Value Reader

    static func value<T>(for key: String) throws -> T where T: LosslessStringConvertible {
        guard let object = Bundle.main.object(forInfoDictionaryKey: key) else {
            throw Error.missingKey
        }

        switch object {
        case let value as T:
            return value
        case let string as String:
            if let value = T(string) {
                return value
            } else {
                throw Error.invalidValue
            }
        default:
            throw Error.invalidValue
        }
    }

    private static func stringValue(for key: String, default defaultValue: String = "") -> String {
        do {
            let value: String = try Configuration.value(for: key)
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return isPlaceholder(trimmed) ? defaultValue : trimmed
        } catch {
            return defaultValue
        }
    }

    private static func boolValue(for key: String, default defaultValue: Bool = false) -> Bool {
        let value = stringValue(for: key).lowercased()

        switch value {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return defaultValue
        }
    }

    static func isPlaceholder(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.isEmpty ||
            normalized.contains("$(") ||
            normalized.contains("your-") ||
            normalized.contains("placeholder") ||
            normalized.contains("replace") ||
            normalized.contains("todo") ||
            normalized.contains("changeme") ||
            normalized.contains("xxx") {
            return true
        }

        // Corrupt/redacted xcconfig values (e.g. "***)") must not reach URLSession.
        if normalized.contains("*") {
            return true
        }

        if let host = URL(string: normalized)?.host ?? URL(string: "https://\(normalized)")?.host {
            return !SupabaseURLBuilder.isValidServiceHost(host)
        }

        return true
    }

    // MARK: - API Configuration

    static var apiBaseURL: String {
        stringValue(for: "API_BASE_URL", default: "https://www.logyourbody.com")
    }

    static var apiExpectedHost: String {
        stringValue(for: "API_EXPECTED_HOST")
    }

    // MARK: - Clerk Authentication

    static var clerkPublishableKey: String {
        stringValue(for: "CLERK_PUBLISHABLE_KEY")
    }

    static var clerkFrontendAPI: String {
        stringValue(for: "CLERK_FRONTEND_API", default: "https://clerk.logyourbody.com")
    }

    // MARK: - Supabase Configuration

    static var supabaseURL: String {
        stringValue(for: "SUPABASE_URL")
    }

    static var supabaseExpectedHost: String {
        stringValue(for: "SUPABASE_EXPECTED_HOST")
    }

    static var supabaseAnonKey: String {
        stringValue(for: "SUPABASE_ANON_KEY")
    }

    // MARK: - RevenueCat Configuration

    static var revenueCatAPIKey: String {
        stringValue(for: "REVENUE_CAT_API_KEY")
    }

    // MARK: - Statsig Analytics Configuration

    static var statsigClientSDKKey: String {
        stringValue(for: "STATSIG_CLIENT_SDK_KEY")
    }

    static var statsigEnvironmentTier: String {
        stringValue(for: "STATSIG_ENVIRONMENT_TIER", default: "development")
    }

    // MARK: - BodySpec Configuration

    static var bodySpecClientId: String {
        stringValue(for: "BODYSPEC_CLIENT_ID")
    }

    static var bodySpecRedirectURI: String {
        stringValue(for: "BODYSPEC_REDIRECT_URI")
    }

    static var sentryDSN: String {
        stringValue(for: "SENTRY_DSN")
    }

    static var sentryEnvironment: String {
        stringValue(for: "SENTRY_ENVIRONMENT", default: "development")
    }

    static var sentryTracesSampleRate: Double {
        do {
            return try Configuration.value(for: "SENTRY_TRACES_SAMPLE_RATE")
        } catch {
            return 0
        }
    }

    // MARK: - Validation

    static var appEnvironment: AppEnvironment {
        AppEnvironment.from(rawValue: stringValue(for: "APP_ENVIRONMENT"))
    }

    static var allowProductionServicesInDevelopment: Bool {
        boolValue(for: "ALLOW_PRODUCTION_SERVICES_IN_DEBUG")
    }

    static var isClerkConfigured: Bool {
        let key = clerkPublishableKey
        return !key.isEmpty && key.hasPrefix("pk_")
    }

    static var currentAuthEnvironmentSnapshot: AuthEnvironmentSnapshot {
        AuthEnvironmentSnapshot(
            environment: appEnvironment,
            clerkPublishableKey: clerkPublishableKey,
            supabaseURL: supabaseURL,
            supabaseExpectedHost: supabaseExpectedHost,
            apiBaseURL: apiBaseURL,
            apiExpectedHost: apiExpectedHost,
            revenueCatAPIKey: revenueCatAPIKey,
            sentryEnvironment: sentryEnvironment,
            statsigEnvironmentTier: statsigEnvironmentTier,
            allowProductionServicesInDevelopment: allowProductionServicesInDevelopment
        )
    }

    static var currentAuthEnvironmentValidation: AuthEnvironmentValidationResult {
        validateAuthEnvironment(currentAuthEnvironmentSnapshot)
    }

    static func validateAuthEnvironment(_ snapshot: AuthEnvironmentSnapshot) -> AuthEnvironmentValidationResult {
        var messages: [String] = []
        let clerkKey = snapshot.clerkPublishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let revenueCatKey = snapshot.revenueCatAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentryEnvironment = snapshot.sentryEnvironment.lowercased()
        let statsigTier = snapshot.statsigEnvironmentTier.lowercased()

        if isPlaceholder(clerkKey) || !clerkKey.hasPrefix("pk_") {
            messages.append("Clerk publishable key must be configured with a publishable pk_ key.")
        }

        let supabaseURL = URL(string: snapshot.supabaseURL)
        if supabaseURL == nil || isPlaceholder(snapshot.supabaseURL) {
            messages.append("Supabase URL must be configured.")
        }

        let apiBaseURL = URL(string: snapshot.apiBaseURL)
        if apiBaseURL == nil || isPlaceholder(snapshot.apiBaseURL) {
            messages.append("API base URL must be configured.")
        }

        if let supabaseURL {
            if supabaseURL.scheme != "https" {
                messages.append("Supabase URL must use HTTPS.")
            }

            if let host = supabaseURL.host,
               !snapshot.supabaseExpectedHost.isEmpty,
               host != snapshot.supabaseExpectedHost {
                messages.append("Supabase URL host must match SUPABASE_EXPECTED_HOST for this environment.")
            }
        }

        if let apiBaseURL,
           let host = apiBaseURL.host,
           !snapshot.apiExpectedHost.isEmpty,
           host != snapshot.apiExpectedHost {
            messages.append("API base URL host must match API_EXPECTED_HOST for this environment.")
        }

        switch snapshot.environment {
        case .production:
            if clerkKey.hasPrefix("pk_test_") {
                messages.append("Production builds cannot use Clerk test publishable keys.")
            }

            if snapshot.supabaseExpectedHost.isEmpty {
                messages.append("Supabase expected host must be configured for production.")
            }

            if apiBaseURL?.scheme != "https" {
                messages.append("Production API base URL must use HTTPS.")
            }

            if isPlaceholder(revenueCatKey) {
                messages.append("Production RevenueCat API key must be configured.")
            }

            if sentryEnvironment != "production" {
                messages.append("Production Sentry environment must be production.")
            }

            if statsigTier != "production" {
                messages.append("Production Statsig tier must be production.")
            }

        case .development:
            if clerkKey.hasPrefix("pk_live_") && !snapshot.allowProductionServicesInDevelopment {
                messages.append("Development builds cannot use Clerk live publishable keys unless explicitly allowed.")
            }
        }

        return AuthEnvironmentValidationResult(messages: messages)
    }
}
