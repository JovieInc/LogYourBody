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

    // MARK: - API Configuration

    static var apiBaseURL: String {
        do {
            return try Configuration.value(for: "API_BASE_URL")
        } catch {
            #if DEBUG
            // print("⚠️ API_BASE_URL not configured in Config.xcconfig")
            #endif
            return "https://www.logyourbody.com"
        }
    }

    // MARK: - Clerk Authentication

    static var clerkPublishableKey: String {
        do {
            return try Configuration.value(for: "CLERK_PUBLISHABLE_KEY")
        } catch {
            #if DEBUG
            // print("⚠️ CLERK_PUBLISHABLE_KEY not configured in Config.xcconfig")
            #endif
            return ""
        }
    }

    static var clerkFrontendAPI: String {
        do {
            return try Configuration.value(for: "CLERK_FRONTEND_API")
        } catch {
            #if DEBUG
            // print("⚠️ CLERK_FRONTEND_API not configured in Config.xcconfig")
            #endif
            return "https://clerk.logyourbody.com"
        }
    }

    // MARK: - Supabase Configuration

    static var supabaseURL: String {
        do {
            return try Configuration.value(for: "SUPABASE_URL")
        } catch {
            #if DEBUG
            // print("⚠️ SUPABASE_URL not configured in Config.xcconfig")
            #endif
            return ""
        }
    }

    static var supabaseAnonKey: String {
        do {
            return try Configuration.value(for: "SUPABASE_ANON_KEY")
        } catch {
            #if DEBUG
            // print("⚠️ SUPABASE_ANON_KEY not configured in Config.xcconfig")
            #endif
            return ""
        }
    }

    // MARK: - RevenueCat Configuration

    static var revenueCatAPIKey: String {
        do {
            return try Configuration.value(for: "REVENUE_CAT_API_KEY")
        } catch {
            #if DEBUG
            // print("⚠️ REVENUE_CAT_API_KEY not configured in Config.xcconfig")
            // print("⚠️ Add REVENUE_CAT_API_KEY = your_api_key_here to Config.xcconfig")
            #endif
            return ""
        }
    }

    // MARK: - Statsig Analytics Configuration

    static var statsigClientSDKKey: String {
        do {
            return try Configuration.value(for: "STATSIG_CLIENT_SDK_KEY")
        } catch {
            return ""
        }
    }

    static var statsigEnvironmentTier: String {
        do {
            return try Configuration.value(for: "STATSIG_ENVIRONMENT_TIER")
        } catch {
            return "development"
        }
    }

    // MARK: - BodySpec Configuration

    static var bodySpecClientId: String {
        do {
            return try Configuration.value(for: "BODYSPEC_CLIENT_ID")
        } catch {
            #if DEBUG
            // print("⚠️ BODYSPEC_CLIENT_ID not configured in Config.xcconfig")
            #endif
            return ""
        }
    }

    static var bodySpecRedirectURI: String {
        do {
            return try Configuration.value(for: "BODYSPEC_REDIRECT_URI")
        } catch {
            #if DEBUG
            // print("⚠️ BODYSPEC_REDIRECT_URI not configured in Config.xcconfig")
            #endif
            return ""
        }
    }

    static var sentryDSN: String {
        do {
            return try Configuration.value(for: "SENTRY_DSN")
        } catch {
            return ""
        }
    }

    static var sentryEnvironment: String {
        do {
            return try Configuration.value(for: "SENTRY_ENVIRONMENT")
        } catch {
            return "development"
        }
    }

    static var sentryTracesSampleRate: Double {
        do {
            return try Configuration.value(for: "SENTRY_TRACES_SAMPLE_RATE")
        } catch {
            return 0
        }
    }

    // MARK: - Validation

    static var isClerkConfigured: Bool {
        let key = clerkPublishableKey
        return !key.isEmpty && key.hasPrefix("pk_")
    }
}
