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
        let authProviderID: String
        let authRedirectURI: String
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

    /// Checks whether a value is a generic placeholder or default (keyword/empty only).
    /// Used in `stringValue()` for all configuration reads.
    /// Does NOT apply URL/host validation — that belongs in `isInvalidURLValue()`.
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

        return false
    }

    /// Checks whether a URL-shaped value is invalid (corrupt/redacted or bad host).
    /// Applied ONLY where a URL/host is expected (SUPABASE_URL, API_BASE_URL).
    static func isInvalidURLValue(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Corrupt/redacted xcconfig values (e.g. "***)") must not reach URLSession.
        if normalized.contains("*") {
            return true
        }

        // Host validation: treat as invalid if the host fails service-host checks.
        if let url = URL(string: normalized),
           let scheme = url.scheme,
           ["http", "https"].contains(scheme),
           let host = url.host {
            return !SupabaseURLBuilder.isValidServiceHost(host)
        }

        return false
    }

    // MARK: - API Configuration

    static var apiBaseURL: String {
        stringValue(for: "API_BASE_URL", default: "https://www.logyourbody.com")
    }

    static var apiExpectedHost: String {
        stringValue(for: "API_EXPECTED_HOST")
    }

    // MARK: - First-party authentication

    static var authProviderID: String {
        stringValue(for: "AUTH_PROVIDER_ID", default: "custom:jovie")
    }

    static var authRedirectURI: String {
        stringValue(for: "AUTH_REDIRECT_URI", default: "logyourbody://oauth")
    }

    static var authCallbackScheme: String {
        URL(string: authRedirectURI)?.scheme ?? "logyourbody"
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

    static var isAuthConfigured: Bool {
        authProviderID.hasPrefix("custom:") &&
            URL(string: authRedirectURI)?.scheme == "logyourbody"
    }

    static var currentAuthEnvironmentSnapshot: AuthEnvironmentSnapshot {
        AuthEnvironmentSnapshot(
            environment: appEnvironment,
            authProviderID: authProviderID,
            authRedirectURI: authRedirectURI,
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
        let revenueCatKey = snapshot.revenueCatAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentryEnvironment = snapshot.sentryEnvironment.lowercased()
        let statsigTier = snapshot.statsigEnvironmentTier.lowercased()

        if isPlaceholder(snapshot.authProviderID) || !snapshot.authProviderID.hasPrefix("custom:") {
            messages.append("Authentication provider must be a configured custom OIDC provider.")
        }

        let redirectURL = URL(string: snapshot.authRedirectURI)
        if redirectURL?.scheme != "logyourbody" || redirectURL?.host != "oauth" {
            messages.append("Authentication redirect URI must be logyourbody://oauth.")
        }

        let supabaseURL = URL(string: snapshot.supabaseURL)
        if supabaseURL == nil || isInvalidURLValue(snapshot.supabaseURL) {
            messages.append("Supabase URL must be configured.")
        }

        let apiBaseURL = URL(string: snapshot.apiBaseURL)
        if apiBaseURL == nil || isInvalidURLValue(snapshot.apiBaseURL) {
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
            if snapshot.authProviderID != "custom:jovie" {
                messages.append("Production authentication must use the Jovie identity provider.")
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
            break
        }

        return AuthEnvironmentValidationResult(messages: messages)
    }
}
