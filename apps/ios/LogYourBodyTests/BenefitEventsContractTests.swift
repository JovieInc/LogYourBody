//
// BenefitEventsContractTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

private struct BenefitEventSnapshot: Decodable {
    let events: [String: BenefitEventDefinition]
}

private final class BenefitAnalyticsClient: AnalyticsClient {
    private(set) var tracked: [(String, [String: String]?)] = []

    func start() {}

    func identify(userId: String?, properties: [String: String]?) {}

    func track(event: String, properties: [String: String]?) {
        tracked.append((event, properties))
    }

    func reset() {}

    func isFeatureEnabled(flagKey: String) -> Bool { false }
}

private final class BenefitEventRecorder: AnalyticsTracking {
    private(set) var events: [(String, [String: String]?)] = []

    func start() {}

    func identify(userId: String?, properties: [String: String]?) {}

    func track(event: String, properties: [String: String]?) {
        events.append((event, properties))
    }

    func reset() {}

    func isFeatureEnabled(flagKey: String) -> Bool { false }
}

@MainActor
private final class BenefitPlanningFixture: DelegatedTrainingServicing {
    var commitReadback = true
    var failNextProposal = false
    var responseJSON: String
    private var committed = false

    init(id: String = "proposal", includeTransition: Bool = false) throws {
        responseJSON = Self.proposalJSON(id: id, includeTransition: includeTransition)
        _ = try JSONDecoder().decode(TrainingPlanProposalResponse.self, from: Data(responseJSON.utf8))
    }

    func useQuestionResponse() {
        responseJSON = #"{"question":"How many days can you realistically train?"}"#
    }

    func planningContext(accessToken: String) async throws -> TrainingPlanContext {
        let setup = committed && commitReadback ? #"{"programRevisionId":"committed-revision"}"# : "null"
        return try JSONDecoder().decode(TrainingPlanContext.self, from: Data("""
        {"generation":0,"delegatedProgramming":true,"knownInputs":{"goal":"Build muscle"},"currentSetup":\(setup)}
        """.utf8))
    }

    func proposePlan(
        accessToken: String, request: TrainingPlanProposalRequest
    ) async throws -> TrainingPlanProposalResponse {
        if failNextProposal {
            failNextProposal = false
            throw URLError(.timedOut)
        }
        return try JSONDecoder().decode(TrainingPlanProposalResponse.self, from: Data(responseJSON.utf8))
    }

    func decidePlan(
        accessToken: String, request: TrainingPlanDecisionRequest
    ) async throws -> TrainingPlanDecisionResponse {
        committed = true
        let receipt: [String: Any] = [
            "proposalId": request.proposalId, "requestId": request.requestId, "status": "applied",
            "revisionId": "committed-revision", "setup": ["programRevisionId": "committed-revision"]
        ]
        return try JSONDecoder().decode(
            TrainingPlanDecisionResponse.self, from: JSONSerialization.data(withJSONObject: ["receipt": receipt])
        )
    }

    private static func proposalJSON(id: String, includeTransition: Bool) -> String {
        let transition = includeTransition
            ? #","transition":{"staying":["Curl"],"changing":["Add a day"],"why":"Next block","expiring":[]}"#
            : ""
        let plan = #"{"revision":1,"sessions":[{"id":"monday","day":"monday","slot":"single","title":"Monday","#
            + #""exercises":[{"instanceId":"curl","variantId":"cable_curl","name":"Cable curl","sets":2,"#
            + #""targetReps":10,"priority":"standard"}]}]}"#
        return #"{"stored":{"status":"proposed","proposal":{"id":""# + id
            + #"","reason":"Start training","actor":{"kind":"coach","subject":"lyb-coach"},"#
            + #""summary":["Two days each week"],"assumptions":["Conservative baseline"],"plan":"#
            + plan + transition + "}}}"
    }
}

@MainActor
final class BenefitEventsContractTests: XCTestCase {
    private var recorder: BenefitEventRecorder!

    override func setUp() {
        super.setUp()
        recorder = BenefitEventRecorder()
        BenefitEvents.trackerOverride = recorder
    }

    override func tearDown() {
        BenefitEvents.resetVisitLedgerForTesting()
        recorder = nil
        super.tearDown()
    }

    func testSnapshotMatchesTheClosedBenefitSchema() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("BenefitEventsSchema.snapshot.json")
        let snapshot = try JSONDecoder().decode(BenefitEventSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(snapshot.events, BenefitEventSchema.events)
        XCTAssertEqual(Set(snapshot.events.keys), [
            "home_decision_accepted", "home_decision_deferred", "home_decision_rejected",
            "home_decision_shown", "manual_log_avoided", "plan_override", "reversal"
        ])
    }

    func testSchemaRejectsPropertiesThatCouldCarryAMeasurement() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("BenefitEventsSchema.snapshot.json")
        let snapshot = try JSONDecoder().decode(BenefitEventSnapshot.self, from: Data(contentsOf: url))
        for events in [snapshot.events, BenefitEventSchema.events] {
            for (event, definition) in events {
                for (name, type) in definition.properties {
                    XCTAssertFalse(
                        BenefitEventSchema.couldCarryMeasurement(name: name, type: type.rawValue),
                        "\(event).\(name) \(type.rawValue)"
                    )
                }
                for (key, values) in definition.kinds {
                    XCTAssertEqual(definition.properties[key], BenefitPropertyType.kind, "\(event).\(key)")
                    for value in values {
                        XCTAssertFalse(
                            BenefitEventSchema.kindValueCouldCarryMeasurement(value),
                            "\(event) kind \(value)"
                        )
                    }
                }
            }
        }

        let forbidden = [
            ("weight", "count"), ("body_fat", "double"), ("load_kg", "number"),
            ("photo_data", "id"), ("note", "kind"), ("avoided_count", "double")
        ]
        for (name, type) in forbidden {
            XCTAssertTrue(
                BenefitEventSchema.couldCarryMeasurement(name: name, type: type),
                "\(name) \(type) must fail the contract"
            )
        }
        XCTAssertFalse(BenefitEventSchema.couldCarryMeasurement(name: "avoided_count", type: "count"))
        XCTAssertTrue(BenefitEventSchema.kindValueCouldCarryMeasurement("182.4"))
        XCTAssertTrue(BenefitEventSchema.kindValueCouldCarryMeasurement("weight"))
        XCTAssertFalse(BenefitEventSchema.kindValueCouldCarryMeasurement("scale_log"))
    }

    func testSanitizerDropsNumericHealthValuesAndKeepsTheEvent() {
        let client = BenefitAnalyticsClient()
        let service = AnalyticsService(client: client)
        let poison = [
            "weight": "182.4", "body_fat": "21.5", "height_cm": "178", "load_kg": "60.5",
            "reps": "8", "photo": "pixels", "note": "free text"
        ]

        for event in BenefitEventSchema.events.keys.sorted() {
            guard let definition = BenefitEventSchema.events[event] else {
                XCTFail(event)
                continue
            }
            var properties = poison
            for (key, type) in definition.properties {
                switch type {
                case .id:
                    properties[key] = "onboarding_import"
                case .kind:
                    properties[key] = definition.kinds[key]?.first ?? "scale_log"
                case .count:
                    properties[key] = "1"
                }
            }
            service.track(event: event, properties: properties)
            let forwarded = client.tracked.last?.1 ?? [:]
            XCTAssertEqual(client.tracked.last?.0, event)
            XCTAssertTrue(Set(forwarded.keys).isDisjoint(with: Set(poison.keys)), event)
            XCTAssertEqual(Set(forwarded.keys), Set(definition.properties.keys), event)
            for value in forwarded.values {
                XCTAssertFalse(value.contains("182"), event)
                XCTAssertFalse(value.contains("21.5"), event)
            }
        }

        service.track(event: "manual_log_avoided", properties: [
            "ask_id": "onboarding_import", "ask_kind": "scale_log", "avoided_count": "2.5", "weight": "182.4"
        ])
        XCTAssertEqual(client.tracked.last?.1, ["ask_id": "onboarding_import", "ask_kind": "scale_log"])

        service.track(event: "manual_log_avoided", properties: [
            "ask_id": "182", "ask_kind": "weight", "avoided_count": "1"
        ])
        XCTAssertEqual(client.tracked.last?.1, ["avoided_count": "1"])

        service.track(event: "manual_log_avoided", properties: [
            "ask_id": "182.4", "ask_kind": "not_a_kind", "weight": "80"
        ])
        XCTAssertEqual(client.tracked.last?.0, "manual_log_avoided")
        XCTAssertNil(client.tracked.last?.1)

        service.track(event: "home_decision_shown", properties: [
            "decision_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
            "decision_kind": "next_block",
            "decision_count": "1",
            "weight": "182.4"
        ])
        XCTAssertEqual(client.tracked.last?.1?["decision_id"], "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        XCTAssertNil(client.tracked.last?.1?["weight"])

        service.track(event: "app_open", properties: ["count": "3", "weight": "70"])
        XCTAssertEqual(client.tracked.last?.0, "app_open")
        XCTAssertNil(client.tracked.last?.1)

        let beforeUnknown = client.tracked.count
        service.track(event: "renamed_app_open", properties: ["method": "apple"])
        XCTAssertEqual(client.tracked.count, beforeUnknown)
    }

    func testLegacyEventNamesStayUnchanged() {
        let frozen: Set<String> = [
            "add_entry_view", "app_open", "bug_report_form_opened", "bug_report_submitted",
            "chat_first_answer_cancelled", "chat_first_answer_completed", "chat_first_answer_failed",
            "chat_first_conversation_deleted", "chat_first_message_sent", "dashboard_view", "entry_saved",
            "first_insight_rendered", "login_attempt", "login_completed", "login_failed", "login_view",
            "mvp_weight_logged", "notification_permission_granted", "onboarding_account_created",
            "onboarding_account_creation_failed", "onboarding_body_score_calculation_attempt",
            "onboarding_body_score_calculation_failed", "onboarding_body_score_calculation_succeeded",
            "onboarding_completed", "onboarding_email_captured", "onboarding_health_import_attempt",
            "onboarding_health_import_authorized", "onboarding_health_import_denied",
            "onboarding_health_import_no_samples", "onboarding_health_import_unavailable",
            "onboarding_pre_auth_completed", "onboarding_started", "onboarding_step_advanced",
            "onboarding_view", "paywall_logout", "paywall_view", "photos_tab_opened",
            "purchase_failed", "purchase_start", "purchase_success", "restore_failed", "restore_success",
            "sync_failed", "trial_converted_to_paid", "trial_expired_unpaid", "trial_start"
        ]
        XCTAssertEqual(AnalyticsEventPolicy.legacyEventNames, frozen)
        XCTAssertTrue(Set(BenefitEventSchema.events.keys).isDisjoint(with: frozen))
    }

    func testEachBenefitEventIsEmittedFromOnePlace() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LogYourBody", isDirectory: true)
        let calls = [
            "BenefitEvents.manualLogAvoided(",
            "BenefitEvents.homeDecisionShown(",
            "BenefitEvents.homeDecisionAccepted(",
            "BenefitEvents.homeDecisionDeferred(",
            "BenefitEvents.homeDecisionRejected(",
            "BenefitEvents.planOverride(",
            "BenefitEvents.reversal("
        ]
        var counts = Dictionary(uniqueKeysWithValues: calls.map { ($0, 0) })
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            XCTFail("Missing app sources at \(root.path)")
            return
        }
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for call in calls {
                counts[call, default: 0] += text.components(separatedBy: call).count - 1
            }
        }
        for (call, count) in counts {
            XCTAssertEqual(count, 1, call)
        }
    }

    func testHomeDecisionShownCountsOncePerVisitUntilTheDecisionChanges() {
        BenefitEvents.homeDecisionShown(decisionId: "next-block", decisionKind: "next_block")
        BenefitEvents.homeDecisionShown(decisionId: "next-block", decisionKind: "next_block")
        BenefitEvents.homeDecisionAccepted(decisionId: "next-block", decisionKind: "next_block")
        BenefitEvents.homeDecisionShown(decisionId: "next-block", decisionKind: "next_block")
        BenefitEvents.homeDecisionShown(decisionId: "other-block", decisionKind: "next_block")
        XCTAssertEqual(recorder.events.map(\.0), [
            "home_decision_shown", "home_decision_accepted", "home_decision_shown", "home_decision_shown"
        ])
        XCTAssertEqual(recorder.events[0].1?["decision_count"], "1")
        XCTAssertEqual(recorder.events[0].1?["decision_kind"], "next_block")
    }

    func testImportedHealthConfirmationAvoidsTheManualAskWithoutSendingNumbers() {
        let viewModel = OnboardingFlowViewModel(healthKitManager: HealthKitManager())
        viewModel.currentStep = .healthConfirmation
        viewModel.bodyScoreInput.weight = WeightValue(value: 80.4, unit: .kilograms)
        viewModel.bodyScoreInput.weightSource = .healthKit
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 21.5, source: .healthKit)

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .loading)
        XCTAssertEqual(recorder.events.map(\.0), ["manual_log_avoided"])
        XCTAssertEqual(recorder.events[0].1, [
            "ask_id": "onboarding_import", "ask_kind": "mixed_log", "avoided_count": "2"
        ])
        assertNoHealthNumbers(recorder.events[0].1)
    }

    func testImportedScaleOnlyAvoidsOneAsk() {
        let viewModel = OnboardingFlowViewModel(healthKitManager: HealthKitManager())
        viewModel.currentStep = .healthConfirmation
        viewModel.bodyScoreInput.weight = WeightValue(value: 80.4, unit: .kilograms)
        viewModel.bodyScoreInput.weightSource = .healthKit

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .bodyFatChoice)
        XCTAssertEqual(recorder.events.map(\.0), ["manual_log_avoided"])
        XCTAssertEqual(recorder.events[0].1?["ask_kind"], "scale_log")
        XCTAssertEqual(recorder.events[0].1?["avoided_count"], "1")
        assertNoHealthNumbers(recorder.events[0].1)
    }

    func testManualWeightAndAMissingWeightDoNotCountAsAvoided() {
        let manual = OnboardingFlowViewModel(healthKitManager: HealthKitManager())
        manual.currentStep = .healthConfirmation
        manual.bodyScoreInput.weight = WeightValue(value: 80.4, unit: .kilograms)
        manual.bodyScoreInput.weightSource = .manual
        manual.goToNextStep()
        XCTAssertEqual(manual.currentStep, .bodyFatChoice)
        XCTAssertTrue(recorder.events.isEmpty)

        let missing = OnboardingFlowViewModel(healthKitManager: HealthKitManager())
        missing.currentStep = .healthConfirmation
        missing.goToNextStep()
        XCTAssertEqual(missing.currentStep, .manualWeight)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testScanImportAvoidsTheAsksItAlreadyAnswered() {
        let withFat = OnboardingFlowViewModel(healthKitManager: HealthKitManager())
        withFat.applyImportedScans([
            DexaPDFScan(
                date: "2026-09-01", weight: 80.4, weightUnit: "kg", bodyFatPercentage: 21.5,
                muscleMass: nil, boneMass: nil, source: "BodySpec"
            )
        ])
        XCTAssertEqual(withFat.currentStep, .loading)
        XCTAssertEqual(recorder.events.map(\.0), ["manual_log_avoided"])
        XCTAssertEqual(recorder.events[0].1?["ask_kind"], "mixed_log")
        XCTAssertEqual(recorder.events[0].1?["avoided_count"], "2")
        assertNoHealthNumbers(recorder.events[0].1)

        BenefitEvents.resetVisitLedgerForTesting()
        recorder = BenefitEventRecorder()
        BenefitEvents.trackerOverride = recorder

        let scaleOnly = OnboardingFlowViewModel(healthKitManager: HealthKitManager())
        scaleOnly.applyImportedScans([
            DexaPDFScan(
                date: "2026-09-01", weight: 82, weightUnit: "kg", bodyFatPercentage: nil,
                muscleMass: nil, boneMass: nil, source: "InBody"
            )
        ])
        XCTAssertEqual(scaleOnly.currentStep, .bodyFatChoice)
        XCTAssertEqual(recorder.events.map(\.0), ["manual_log_avoided"])
        XCTAssertEqual(recorder.events[0].1?["ask_kind"], "scale_log")
        XCTAssertEqual(recorder.events[0].1?["avoided_count"], "1")
        assertNoHealthNumbers(recorder.events[0].1)
    }

    func testSteeringEmitsPlanOverrideWithoutTheUtterance() async throws {
        let service = try BenefitPlanningFixture()
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose(utterance: "keep the 80.4 kg curl")

        XCTAssertEqual(recorder.events.map(\.0), ["plan_override"])
        XCTAssertEqual(recorder.events[0].1, [
            "proposal_id": "proposal", "override_kind": "steering", "override_count": "1"
        ])
        assertNoHealthNumbers(recorder.events[0].1)
        let blob = recorder.events[0].1?.values.joined(separator: " ") ?? ""
        XCTAssertFalse(blob.contains("curl"))
        XCTAssertFalse(blob.contains("kg"))
    }

    func testRecommendAndBlankSteeringDoNotOverrideThePlan() async throws {
        let service = try BenefitPlanningFixture()
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        await model.propose(utterance: "   ")
        XCTAssertTrue(recorder.events.isEmpty)

        service.useQuestionResponse()
        model.inputsChanged()
        await model.propose(utterance: "keep the curl")
        XCTAssertNil(model.proposal)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testFailedProposalDoesNotEmit() async throws {
        let service = try BenefitPlanningFixture()
        service.failNextProposal = true
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose(utterance: "keep the curl")
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertNil(model.proposal)
    }

    func testNextBlockDecisionsAndAFailedApply() async throws {
        let service = try BenefitPlanningFixture(id: "next-block", includeTransition: true)
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        model.noteHomeDecisionDeferred()
        model.noteHomeDecisionDeferred()
        XCTAssertEqual(recorder.events.map(\.0), ["home_decision_deferred"])
        XCTAssertEqual(recorder.events[0].1?["decision_id"], "next-block")

        service.commitReadback = false
        let failed = await model.decide("apply")
        XCTAssertFalse(failed)
        XCTAssertEqual(recorder.events.map(\.0), ["home_decision_deferred"])

        service.commitReadback = true
        let applied = await model.decide("apply")
        XCTAssertTrue(applied)
        XCTAssertEqual(recorder.events.map(\.0), ["home_decision_deferred", "home_decision_accepted"])
        XCTAssertEqual(recorder.events[1].1?["decision_kind"], "next_block")
        XCTAssertEqual(recorder.events[1].1?["decision_count"], "1")
    }

    func testRejectingANextBlockEmitsRejectedOnly() async throws {
        let service = try BenefitPlanningFixture(id: "next-block", includeTransition: true)
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        let applied = await model.decide("reject")
        XCTAssertFalse(applied)
        XCTAssertEqual(recorder.events.map(\.0), ["home_decision_rejected"])
        XCTAssertEqual(recorder.events[0].1?["decision_id"], "next-block")
        XCTAssertEqual(recorder.events[0].1?["decision_kind"], "next_block")
    }

    func testFirstRunApplyAndRejectAreNotHomeDecisions() async throws {
        let service = try BenefitPlanningFixture()
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        model.noteHomeDecisionDeferred()
        let applied = await model.decide("apply")
        XCTAssertTrue(applied)
        XCTAssertTrue(recorder.events.isEmpty)

        let rejecting = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await rejecting.refresh()
        await rejecting.propose()
        _ = await rejecting.decide("reject")
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testRestoreApplyEmitsReversalAndANextBlockAcceptWhenBothApply() async throws {
        let plain = try BenefitPlanningFixture()
        let model = DelegatedTrainingModel(service: plain, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose(restoreRevision: "prior-revision")
        XCTAssertTrue(recorder.events.isEmpty)
        let applied = await model.decide("apply")
        XCTAssertTrue(applied)
        XCTAssertEqual(recorder.events.map(\.0), ["reversal"])
        XCTAssertEqual(recorder.events[0].1, [
            "proposal_id": "proposal", "reversal_kind": "restore", "reversal_count": "1"
        ])

        BenefitEvents.resetVisitLedgerForTesting()
        recorder = BenefitEventRecorder()
        BenefitEvents.trackerOverride = recorder

        let nextBlock = try BenefitPlanningFixture(id: "next-block", includeTransition: true)
        let restoring = DelegatedTrainingModel(service: nextBlock, accessToken: { "token" }, isCurrent: { true })
        await restoring.refresh()
        await restoring.propose(restoreRevision: "prior-revision")
        _ = await restoring.decide("apply")
        XCTAssertEqual(recorder.events.map(\.0), ["home_decision_accepted", "reversal"])
        XCTAssertEqual(recorder.events[1].1?["reversal_kind"], "restore")
        XCTAssertEqual(recorder.events[1].1?["proposal_id"], "next-block")
    }

    private func assertNoHealthNumbers(
        _ properties: [String: String]?, file: StaticString = #filePath, line: UInt = #line
    ) {
        let blob = properties?.map { "\($0.key)=\($0.value)" }.joined(separator: " ") ?? ""
        for fragment in ["80.4", "21.5", "182.4", "60.5", "weight", "body_fat", "photo", "note"] {
            XCTAssertFalse(blob.contains(fragment), blob, file: file, line: line)
        }
    }
}
