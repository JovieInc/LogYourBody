//
// AnalyticsService.swift
// LogYourBody
//
// App-wide analytics facade using a vendor-specific adapter (Statsig).
//

import Foundation

#if canImport(Statsig)
import Statsig

protocol AnalyticsClient {
    func start()
    func identify(userId: String?, properties: [String: String]?)
    func track(event: String, properties: [String: String]?)
    func reset()
    func isFeatureEnabled(flagKey: String) -> Bool
}

/// Central analytics service used throughout the app.
///
/// This exposes a vendor-agnostic API and delegates to a concrete client
/// implementation (currently Statsig) so that vendor details remain
/// isolated from product code.
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let client: AnalyticsClient
    private var hasStarted = false

    private convenience init() {
        self.init(client: StatsigAnalyticsClient())
    }

    /// Test seam: allows injecting a fake analytics client.
    init(client: AnalyticsClient) {
        self.client = client
    }

    func start() {
        client.start()
        hasStarted = true
        notifyFeatureGatesDidChange()
    }

    func identify(userId: String?, properties: [String: String]? = nil) {
        // No app-supplied account identity or traits are approved for analytics.
        // Keep the existing API and gate notification without linking an account.
        client.identify(userId: nil, properties: nil)
        notifyFeatureGatesDidChange()
    }

    func track(event: String, properties: [String: String]? = nil) {
        guard let payload = AnalyticsEventPolicy.payload(event: event, properties: properties) else { return }
        client.track(event: payload.event, properties: payload.properties)
    }

    func reset() {
        client.reset()
        notifyFeatureGatesDidChange()
    }

    func isFeatureEnabled(flagKey: String) -> Bool {
        guard hasStarted else { return false }
        return client.isFeatureEnabled(flagKey: flagKey)
    }

    private func notifyFeatureGatesDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .featureGatesDidChange, object: nil)
        }
    }
}

// MARK: - Product Event Policy

/// Filters app-supplied events only. SDK metadata, exposures, consent and
/// user-initiated support feedback require separate lifecycle/disclosure work.
private enum AnalyticsEventPolicy {
    struct Payload {
        let event: String
        let properties: [String: String]?
    }

    private static let booleans: Set<String> = ["true", "false"]
    private static let entryContext: Set<String> = ["pre_auth", "authenticated"]
    private static let steps: Set<String> = [
        "hook", "basics", "height", "healthConnect", "healthConfirmation", "manualWeight",
        "bodyFatChoice", "bodyFatNumeric", "bodyFatVisual", "loading", "bodyScore",
        "defaultHomeMode", "emailCapture", "account", "profileDetails", "firstPhoto", "paywall"
    ]
    private static let accountMethod: [String: Set<String>] = ["method": ["apple"]]
    private static let context: [String: Set<String>] = ["entry_context": entryContext]
    private static let subscription: [String: Set<String>] = [
        "previous_phase": ["none", "trial", "paid", "expired_unpaid"],
        "current_phase": ["none", "trial", "paid", "expired_unpaid"],
        "is_active": booleans,
        "will_renew": booleans,
        "period_type": ["normal", "intro", "trial", "prepaid", "unknown"]
    ]

    // Values must be fixed app-level enums, never user content or identifiers.
    private static let rules: [String: [String: Set<String>]] = [
        "add_entry_view": [:],
        "app_open": [:],
        "bug_report_form_opened": ["has_screenshot": booleans],
        "bug_report_submitted": ["has_screenshot": booleans],
        "chat_first_answer_cancelled": [:],
        "chat_first_answer_completed": [:],
        "chat_first_answer_failed": ["retryable": booleans],
        "chat_first_conversation_deleted": [:],
        "chat_first_message_sent": [:],
        "dashboard_view": [:],
        "entry_saved": [:],
        "login_attempt": accountMethod,
        "login_completed": accountMethod,
        "login_failed": accountMethod,
        "login_view": [:],
        "mvp_weight_logged": [:],
        "notification_permission_granted": ["notification_type": ["daily_weigh_in"]],
        "onboarding_account_created": ["entry_context": entryContext, "method": ["apple"]],
        "onboarding_account_creation_failed": context,
        "onboarding_body_score_calculation_attempt": context,
        "onboarding_body_score_calculation_failed": context,
        "onboarding_body_score_calculation_succeeded": context,
        "onboarding_completed": ["version": ["1"]],
        "onboarding_email_captured": context,
        "onboarding_health_import_attempt": [:],
        "onboarding_health_import_authorized": [:],
        "onboarding_health_import_denied": [:],
        "onboarding_health_import_unavailable": [:],
        "onboarding_pre_auth_completed": [:],
        "onboarding_started": context,
        "onboarding_step_advanced": ["from_step": steps, "to_step": steps, "entry_context": entryContext],
        "onboarding_view": [:],
        "paywall_logout": [:],
        "paywall_view": [:],
        "photos_tab_opened": [:],
        "purchase_failed": [:],
        "purchase_start": [:],
        "purchase_success": [:],
        "restore_failed": [:],
        "restore_success": [:],
        "sync_failed": [:],
        "trial_converted_to_paid": subscription,
        "trial_expired_unpaid": subscription,
        "trial_start": subscription
    ]

    static func payload(event: String, properties: [String: String]?) -> Payload? {
        guard let allowed = rules[event] else { return nil }

        if event == "entry_saved" {
            // Removing medication IDs alone would still disclose a medication
            // interaction. Only established non-medication paths keep a generic marker.
            guard let type = properties?["type"], ["weight", "body_fat", "photos"].contains(type) else { return nil }
        }

        let filtered = properties?.filter { key, value in allowed[key]?.contains(value) == true } ?? [:]
        return Payload(event: event, properties: filtered.isEmpty ? nil : filtered)
    }
}

// MARK: - Statsig Adapter

private final class StatsigAnalyticsClient: AnalyticsClient {
    func start() {
        let sdkKey = Configuration.statsigClientSDKKey
        guard !sdkKey.isEmpty else {
            return
        }

        let tierString = Configuration.statsigEnvironmentTier.lowercased()
        let environment: StatsigEnvironment?

        switch tierString {
        case "production":
            environment = StatsigEnvironment(tier: .Production)
        case "staging":
            environment = StatsigEnvironment(tier: .Staging)
        case "development":
            environment = StatsigEnvironment(tier: .Development)
        default:
            environment = nil
        }

        let options: StatsigOptions
        if let environment {
            options = StatsigOptions(environment: environment)
        } else {
            options = StatsigOptions()
        }

        Statsig.initialize(sdkKey: sdkKey, user: nil, options: options)
    }

    func identify(userId: String?, properties: [String: String]?) {
        reset()
    }

    func track(event: String, properties: [String: String]?) {
        if let properties {
            Statsig.logEvent(event, metadata: properties)
        } else {
            Statsig.logEvent(event)
        }
    }

    func reset() {
        let user = StatsigUser(
            userID: nil,
            email: nil,
            ip: nil,
            country: nil,
            locale: nil,
            appVersion: AppVersion.current,
            custom: nil,
            privateAttributes: nil,
            optOutNonSdkMetadata: false,
            customIDs: nil,
            userAgent: nil
        )

        Statsig.updateUserWithResult(user)
    }

    func isFeatureEnabled(flagKey: String) -> Bool {
        Statsig.checkGate(flagKey)
    }
}
#endif
