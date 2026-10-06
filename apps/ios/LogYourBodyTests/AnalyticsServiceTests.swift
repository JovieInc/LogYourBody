//
// AnalyticsServiceTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class AnalyticsServiceTests: XCTestCase {
    // Source-audited current callsites, including RevenueCat and paywall helpers.
    private let currentProductEvents = [
        "add_entry_view", "app_open", "bug_report_form_opened", "bug_report_submitted",
        "chat_first_answer_cancelled", "chat_first_answer_completed", "chat_first_answer_failed",
        "chat_first_conversation_deleted", "chat_first_message_sent", "dashboard_view", "entry_saved",
        "login_attempt", "login_completed", "login_failed", "login_view", "mvp_weight_logged",
        "notification_permission_granted", "onboarding_account_created", "onboarding_account_creation_failed",
        "onboarding_body_score_calculation_attempt", "onboarding_body_score_calculation_failed",
        "onboarding_body_score_calculation_succeeded", "onboarding_completed", "onboarding_email_captured",
        "onboarding_health_import_attempt", "onboarding_health_import_authorized", "onboarding_health_import_denied",
        "onboarding_health_import_unavailable", "onboarding_pre_auth_completed", "onboarding_started",
        "onboarding_step_advanced", "onboarding_view", "paywall_logout", "paywall_view", "photos_tab_opened",
        "purchase_failed", "purchase_start", "purchase_success", "restore_failed", "restore_success",
        "sync_failed", "trial_converted_to_paid", "trial_expired_unpaid", "trial_start"
    ]

    private let sensitiveProperties = [
        "user_id": "synthetic-account", "app_user_id": "synthetic-customer", "userID": "synthetic-account",
        "email": "synthetic@e.test", "name": "Synthetic Person", "country": "US", "locale": "en_US",
        "medication_id": "synthetic-medication", "dose_unit": "mg", "dose_amount": "1",
        "weight": "70", "body_fat": "20", "height": "170", "health_data": "synthetic-health",
        "workout": "synthetic-workout", "notes": "synthetic note", "message": "synthetic message",
        "transcript": "synthetic transcript", "answer": "synthetic answer", "free_text": "synthetic text",
        "token": "synthetic-token", "authorization": "synthetic-token", "url": "https://e",
        "error": "synthetic error", "package_id": "synthetic-package", "product_identifier": "synthetic-product",
        "entitlement_id": "synthetic-entitlement", "expiration_at": "2026-10-06T00:00:00Z",
        "unsubscribe_detected_at": "2026-10-06T00:00:00Z", "unit": "kg", "count": "3", "pending_count": "2"
    ]

    private final class FakeAnalyticsClient: AnalyticsClient {
        private(set) var startCallCount = 0
        private(set) var resetCallCount = 0
        private(set) var identifiedUserIds: [String?] = []
        private(set) var identifiedProperties: [[String: String]?] = []
        private(set) var trackedEvents: [String] = []
        private(set) var trackedProperties: [[String: String]?] = []
        private(set) var queriedFlags: [String] = []
        var gateResult = true

        func start() {
            startCallCount += 1
        }

        func identify(userId: String?, properties: [String: String]?) {
            identifiedUserIds.append(userId)
            identifiedProperties.append(properties)
        }

        func track(event: String, properties: [String: String]?) {
            trackedEvents.append(event)
            trackedProperties.append(properties)
        }

        func reset() {
            resetCallCount += 1
        }

        func isFeatureEnabled(flagKey: String) -> Bool {
            queriedFlags.append(flagKey)
            return gateResult
        }
    }

    private func makeService() -> (AnalyticsService, FakeAnalyticsClient) {
        let client = FakeAnalyticsClient()
        return (AnalyticsService(client: client), client)
    }

    func testStartDelegatesToClientAndPostsGateChangeNotification() async {
        let (service, client) = makeService()
        let notification = expectation(forNotification: .featureGatesDidChange, object: nil)

        service.start()

        await fulfillment(of: [notification], timeout: 5)
        XCTAssertEqual(client.startCallCount, 1)
    }

    func testIdentifyDropsAccountAndTraitsAndPostsNotification() async throws {
        let (service, client) = makeService()
        let notification = expectation(forNotification: .featureGatesDidChange, object: nil)

        service.identify(userId: "synthetic-account", properties: sensitiveProperties)

        await fulfillment(of: [notification], timeout: 5)
        XCTAssertEqual(client.identifiedUserIds.count, 1)
        XCTAssertNil(client.identifiedUserIds[0])
        XCTAssertNil(try XCTUnwrap(client.identifiedProperties.first))
    }

    func testIdentifyWithoutPropertiesForwardsNil() throws {
        let (service, client) = makeService()

        service.identify(userId: nil)

        XCTAssertEqual(client.identifiedUserIds.count, 1)
        XCTAssertNil(client.identifiedUserIds[0])
        XCTAssertNil(try XCTUnwrap(client.identifiedProperties.first))
    }

    func testIdentifyRejectsEveryAppSuppliedPrincipalAndTrait() {
        let (service, client) = makeService()
        let principals = ["synthetic-account", "synthetic@e.test", "https://e", "synthetic-token", "", " "]

        for principal in principals {
            service.identify(userId: principal, properties: ["platform": "ios", "email": "synthetic@e.test"])
        }

        XCTAssertEqual(client.identifiedUserIds.count, principals.count)
        XCTAssertTrue(client.identifiedUserIds.allSatisfy { $0 == nil })
        XCTAssertTrue(client.identifiedProperties.allSatisfy { $0 == nil })
    }

    func testEveryCurrentProductEventHasAnApprovedMarker() {
        let (service, client) = makeService()

        for event in currentProductEvents {
            service.track(event: event, properties: event == "entry_saved" ? ["type": "weight"] : nil)
        }

        XCTAssertEqual(client.trackedEvents, currentProductEvents)
        XCTAssertEqual(client.trackedProperties.count, currentProductEvents.count)
        XCTAssertTrue(client.trackedProperties.allSatisfy { $0 == nil })
    }

    func testUnknownAndMalformedEventNamesNeverReachClient() {
        let (service, client) = makeService()
        let events = ["", "app_opened", "APP_OPEN", " app_open", "app_open\n", "synthetic@e.test", "synthetic free text"]

        for event in events {
            service.track(event: event, properties: ["method": "apple"])
        }

        XCTAssertTrue(client.trackedEvents.isEmpty)
    }

    func testSensitivePayloadsAreRejectedAcrossEveryCurrentEvent() {
        let (service, client) = makeService()

        for event in currentProductEvents {
            var properties = sensitiveProperties
            if event == "entry_saved" { properties["type"] = "weight" }
            service.track(event: event, properties: properties)
        }

        XCTAssertEqual(client.trackedEvents, currentProductEvents)
        XCTAssertTrue(client.trackedProperties.allSatisfy { $0 == nil })
    }

    func testTrackKeepsOnlyEventSpecificFixedValues() throws {
        let (service, client) = makeService()

        service.track(event: "login_attempt", properties: ["method": "apple", "email": "synthetic@e.test"])

        XCTAssertEqual(client.trackedEvents, ["login_attempt"])
        XCTAssertEqual(try XCTUnwrap(client.trackedProperties.first), ["method": "apple"])
    }

    func testTrackWithoutPropertiesForwardsNilProperties() throws {
        let (service, client) = makeService()

        service.track(event: "app_open")

        XCTAssertEqual(client.trackedEvents, ["app_open"])
        XCTAssertNil(try XCTUnwrap(client.trackedProperties.first))
    }

    func testCrossEventKeysAndMalformedValuesAreDropped() {
        let (service, client) = makeService()
        let inputs: [(String, [String: String])] = [
            ("app_open", ["method": "apple", "has_screenshot": "true"]),
            ("login_attempt", ["method": "synthetic@e.test", "entry_context": "pre_auth"]),
            ("onboarding_started", ["entry_context": "pre_auth\n", "method": "apple"]),
            ("bug_report_submitted", ["has_screenshot": "TRUE", "retryable": "true"]),
            ("chat_first_answer_failed", ["retryable": "synthetic-token"]),
            ("onboarding_completed", ["version": "2"]),
            ("trial_start", ["previous_phase": "synthetic-account", "period_type": "synthetic medication"])
        ]

        for (event, properties) in inputs { service.track(event: event, properties: properties) }

        XCTAssertEqual(client.trackedEvents, inputs.map { $0.0 })
        XCTAssertTrue(client.trackedProperties.allSatisfy { $0 == nil })
    }

    func testOnboardingUsesClosedContextAndStepLabelsWithoutInputValues() throws {
        let (service, client) = makeService()
        let approved = ["entry_context": "pre_auth", "from_step": "manualWeight", "to_step": "bodyFatChoice"]
        var properties = approved
        properties["weight"] = "70"
        properties["body_fat"] = "20"

        service.track(event: "onboarding_step_advanced", properties: properties)

        XCTAssertEqual(try XCTUnwrap(client.trackedProperties.first), approved)
        service.track(event: "onboarding_step_advanced", properties: ["from_step": "synthetic measurement"])
        XCTAssertNil(client.trackedProperties[1])
    }

    func testFixedInteractionPropertiesRemainAvailable() throws {
        let (service, client) = makeService()
        let inputs: [(String, [String: String])] = [
            ("login_completed", ["method": "apple"]),
            ("login_failed", ["method": "apple"]),
            ("onboarding_account_created", ["entry_context": "authenticated", "method": "apple"]),
            ("onboarding_email_captured", ["entry_context": "pre_auth"]),
            ("onboarding_completed", ["version": "1"]),
            ("notification_permission_granted", ["notification_type": "daily_weigh_in"]),
            ("bug_report_form_opened", ["has_screenshot": "false"]),
            ("bug_report_submitted", ["has_screenshot": "true"]),
            ("chat_first_answer_failed", ["retryable": "false"])
        ]

        for (event, properties) in inputs { service.track(event: event, properties: properties) }

        XCTAssertEqual(client.trackedEvents, inputs.map { $0.0 })
        for (index, input) in inputs.enumerated() {
            XCTAssertEqual(try XCTUnwrap(client.trackedProperties[index]), input.1)
        }
    }

    func testMedicationAndUnknownEntryPathsNeverReachClient() {
        let (service, client) = makeService()
        let types = ["glp1", "medication", "synthetic@e.test", "weight\n", "", "unknown"]

        for type in types {
            service.track(event: "entry_saved", properties: ["type": type, "medication_id": "synthetic-medication"])
        }
        service.track(event: "entry_saved")
        service.track(event: "entry_saved", properties: [:])

        XCTAssertTrue(client.trackedEvents.isEmpty)
    }

    func testApprovedEntryPathsKeepOnlyGenericMarkers() {
        let (service, client) = makeService()

        for type in ["weight", "body_fat", "photos"] {
            var properties = sensitiveProperties
            properties["type"] = type
            service.track(event: "entry_saved", properties: properties)
        }

        XCTAssertEqual(client.trackedEvents, ["entry_saved", "entry_saved", "entry_saved"])
        XCTAssertTrue(client.trackedProperties.allSatisfy { $0 == nil })
    }

    func testTrialTransitionsKeepEnumsWithoutIdentifiersOrDates() throws {
        let (service, client) = makeService()
        let approved = [
            "previous_phase": "trial", "current_phase": "paid", "is_active": "true",
            "will_renew": "false", "period_type": "normal"
        ]
        var properties = sensitiveProperties
        properties.merge(approved) { _, newValue in newValue }

        for event in ["trial_start", "trial_converted_to_paid", "trial_expired_unpaid"] {
            service.track(event: event, properties: properties)
        }

        for properties in client.trackedProperties { XCTAssertEqual(try XCTUnwrap(properties), approved) }
    }

    func testEmptyPropertiesAreNormalizedWithoutStartingClient() {
        let (service, client) = makeService()

        service.track(event: "app_open", properties: [:])
        service.track(event: "login_attempt", properties: ["method": ""])

        XCTAssertEqual(client.startCallCount, 0)
        XCTAssertEqual(client.trackedEvents, ["app_open", "login_attempt"])
        XCTAssertTrue(client.trackedProperties.allSatisfy { $0 == nil })
    }

    func testResetDelegatesToClientAndPostsNotification() async {
        let (service, client) = makeService()
        let notification = expectation(forNotification: .featureGatesDidChange, object: nil)

        service.reset()

        await fulfillment(of: [notification], timeout: 5)
        XCTAssertEqual(client.resetCallCount, 1)
    }

    func testFeatureGateReturnsFalseBeforeStart() {
        let (service, client) = makeService()
        client.gateResult = true

        XCTAssertFalse(service.isFeatureEnabled(flagKey: "new_onboarding_v2"))
        XCTAssertTrue(client.queriedFlags.isEmpty)
    }

    func testFeatureGateForwardsToClientAfterStart() async {
        let (service, client) = makeService()
        client.gateResult = true

        service.start()
        XCTAssertTrue(service.isFeatureEnabled(flagKey: "strict_reminders"))
        XCTAssertEqual(client.queriedFlags, ["strict_reminders"])

        client.gateResult = false
        XCTAssertFalse(service.isFeatureEnabled(flagKey: "strict_reminders"))
    }
}
