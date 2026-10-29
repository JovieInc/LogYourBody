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

// MARK: - Benefit event schema

/// Closed LYB-173 benefit events. Properties are ids, kinds, and counts.
/// Names and types that could carry a measurement, photo, or free text are not
/// representable here; `BenefitEventsContractTests` fails if one is added.
enum BenefitPropertyType: String, Codable, Equatable {
    case id
    case kind
    case count
}

struct BenefitEventDefinition: Equatable, Codable {
    var properties: [String: BenefitPropertyType]
    var kinds: [String: [String]]
}

enum BenefitEventSchema {
    static let manualLogAvoided = "manual_log_avoided"
    static let homeDecisionShown = "home_decision_shown"
    static let homeDecisionAccepted = "home_decision_accepted"
    static let homeDecisionDeferred = "home_decision_deferred"
    static let homeDecisionRejected = "home_decision_rejected"
    static let planOverride = "plan_override"
    static let reversal = "reversal"

    static let events: [String: BenefitEventDefinition] = [
        manualLogAvoided: BenefitEventDefinition(
            properties: ["ask_id": .id, "ask_kind": .kind, "avoided_count": .count],
            kinds: ["ask_kind": ["composition_log", "mixed_log", "scale_log"]]
        ),
        homeDecisionShown: BenefitEventDefinition(
            properties: ["decision_count": .count, "decision_id": .id, "decision_kind": .kind],
            kinds: ["decision_kind": ["next_block"]]
        ),
        homeDecisionAccepted: BenefitEventDefinition(
            properties: ["decision_count": .count, "decision_id": .id, "decision_kind": .kind],
            kinds: ["decision_kind": ["next_block"]]
        ),
        homeDecisionDeferred: BenefitEventDefinition(
            properties: ["decision_count": .count, "decision_id": .id, "decision_kind": .kind],
            kinds: ["decision_kind": ["next_block"]]
        ),
        homeDecisionRejected: BenefitEventDefinition(
            properties: ["decision_count": .count, "decision_id": .id, "decision_kind": .kind],
            kinds: ["decision_kind": ["next_block"]]
        ),
        planOverride: BenefitEventDefinition(
            properties: ["override_count": .count, "override_kind": .kind, "proposal_id": .id],
            kinds: ["override_kind": ["steering"]]
        ),
        reversal: BenefitEventDefinition(
            properties: ["proposal_id": .id, "reversal_count": .count, "reversal_kind": .kind],
            kinds: ["reversal_kind": ["restore"]]
        )
    ]

    static func sanitized(event: String, properties: [String: String]?) -> [String: String]? {
        guard let definition = events[event] else { return nil }
        let filtered = (properties ?? [:]).filter { key, value in
            guard let type = definition.properties[key] else { return false }
            return allows(value, as: type, key: key, definition: definition)
        }
        return filtered.isEmpty ? nil : filtered
    }

    /// True when a property name or declared type could carry a measurement,
    /// a photo, or free text. Count is the only numeric type, and only by name.
    static func couldCarryMeasurement(name: String, type: String) -> Bool {
        let normalized = name.lowercased().replacingOccurrences(of: "-", with: "_")
        if measurementPhrases.contains(where: { normalized.contains($0) }) { return true }
        let parts = Set(normalized.split(separator: "_").map(String.init))
        if !parts.isDisjoint(with: measurementWords) { return true }
        return type != BenefitPropertyType.id.rawValue
            && type != BenefitPropertyType.kind.rawValue
            && type != BenefitPropertyType.count.rawValue
    }

    static func kindValueCouldCarryMeasurement(_ value: String) -> Bool {
        guard value.range(of: #"^[a-z][a-z0-9_]{0,32}$"#, options: .regularExpression) != nil else {
            return true
        }
        return couldCarryMeasurement(name: value, type: BenefitPropertyType.kind.rawValue)
    }

    private static let measurementPhrases = [
        "weight", "body_fat", "bodyfat", "height", "waist", "lean", "muscle", "ffmi", "fmi", "bmi",
        "load", "reps", "rir", "percent", "percentage", "photo", "image", "pixel", "note", "notes",
        "message", "transcript", "comment", "measurement", "calorie", "dose", "bpm", "mass", "value",
        "free_text", "freetext"
    ]
    private static let measurementWords: Set<String> = ["kg", "lb", "lbs", "fat", "bf", "text"]

    private static func allows(
        _ value: String, as type: BenefitPropertyType, key: String, definition: BenefitEventDefinition
    ) -> Bool {
        switch type {
        case .id:
            guard value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"#, options: .regularExpression) != nil else {
                return false
            }
            return value.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) == nil
        case .kind:
            return definition.kinds[key]?.contains(value) == true
        case .count:
            return value.range(of: #"^(?:0|[1-9][0-9]{0,2})$"#, options: .regularExpression) != nil
        }
    }
}

/// One emission function per benefit event. Call sites pass ids, kinds, and
/// counts; `AnalyticsService` drops anything else before it leaves the device.
@MainActor
enum BenefitEvents {
    static var trackerOverride: AnalyticsTracking?
    private static var shownDecisionIds: Set<String> = []
    private static var deferredDecisionIds: Set<String> = []

    static func resetVisitLedgerForTesting() {
        shownDecisionIds.removeAll()
        deferredDecisionIds.removeAll()
        trackerOverride = nil
    }

    static func manualLogAvoided(askId: String, askKind: String, avoidedCount: Int) {
        emit(BenefitEventSchema.manualLogAvoided, [
            "ask_id": askId,
            "ask_kind": askKind,
            "avoided_count": String(avoidedCount)
        ])
    }

    static func homeDecisionShown(decisionId: String, decisionKind: String) {
        guard shownDecisionIds.insert(decisionId).inserted else { return }
        emit(BenefitEventSchema.homeDecisionShown, decisionProperties(decisionId, decisionKind))
    }

    static func homeDecisionAccepted(decisionId: String, decisionKind: String) {
        shownDecisionIds.remove(decisionId)
        deferredDecisionIds.remove(decisionId)
        emit(BenefitEventSchema.homeDecisionAccepted, decisionProperties(decisionId, decisionKind))
    }

    static func homeDecisionDeferred(decisionId: String, decisionKind: String) {
        guard deferredDecisionIds.insert(decisionId).inserted else { return }
        shownDecisionIds.remove(decisionId)
        emit(BenefitEventSchema.homeDecisionDeferred, decisionProperties(decisionId, decisionKind))
    }

    static func homeDecisionRejected(decisionId: String, decisionKind: String) {
        shownDecisionIds.remove(decisionId)
        deferredDecisionIds.remove(decisionId)
        emit(BenefitEventSchema.homeDecisionRejected, decisionProperties(decisionId, decisionKind))
    }

    static func planOverride(proposalId: String, overrideKind: String) {
        emit(BenefitEventSchema.planOverride, [
            "proposal_id": proposalId,
            "override_kind": overrideKind,
            "override_count": "1"
        ])
    }

    static func reversal(proposalId: String, reversalKind: String) {
        emit(BenefitEventSchema.reversal, [
            "proposal_id": proposalId,
            "reversal_kind": reversalKind,
            "reversal_count": "1"
        ])
    }

    private static func decisionProperties(_ decisionId: String, _ decisionKind: String) -> [String: String] {
        ["decision_id": decisionId, "decision_kind": decisionKind, "decision_count": "1"]
    }

    private static func emit(_ event: String, _ properties: [String: String]) {
        let tracker = trackerOverride ?? AppServicePorts.analyticsTracker
        tracker.track(event: event, properties: properties)
    }
}

// MARK: - Product Event Policy

/// Filters app-supplied events only. SDK metadata, exposures, consent and
/// user-initiated support feedback require separate lifecycle/disclosure work.
enum AnalyticsEventPolicy {
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
        "first_insight_rendered": [:],
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
        "onboarding_health_import_no_samples": [:],
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

    static var legacyEventNames: Set<String> { Set(rules.keys) }

    static func payload(event: String, properties: [String: String]?) -> Payload? {
        if BenefitEventSchema.events[event] != nil {
            return Payload(
                event: event,
                properties: BenefitEventSchema.sanitized(event: event, properties: properties)
            )
        }
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
