import XCTest
@testable import LogYourBody

@MainActor
final class DelegatedTrainingTests: XCTestCase {
    func testRecommendedDraftStartsOnlyAfterMatchingCommittedReadback() async throws {
        let service = try PlanningServiceFixture()
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        XCTAssertEqual(model.inputs.goal, "Build muscle")
        await model.propose()
        XCTAssertEqual(model.proposal?.status, "proposed")
        XCTAssertTrue(service.decisions.isEmpty)
        let applied = await model.decide("apply")
        XCTAssertTrue(applied)
        XCTAssertEqual(model.context?.currentSetup?.programRevisionId, "committed-revision")
        XCTAssertEqual(service.decisions.first?.proposalId, "proposal")
    }

    func testApprovedCardApplyUsesCanonicalDecisionAndCommittedReadback() async throws {
        let service = try PlanningServiceFixture(proposalId: "11111111-1111-4111-8111-000000000001")
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        let reference = try XCTUnwrap(model.proposal?.cardReference)
        let applied = await model.decideCard(TrainingCardAction(reference: reference, name: .apply))
        XCTAssertTrue(applied)
        XCTAssertEqual(service.decisions.count, 1)
        XCTAssertEqual(service.decisions.first?.proposalId, reference.objectId)
        XCTAssertEqual(model.context?.currentSetup?.programRevisionId, "committed-revision")
    }

    func testCardRejectsNoOpProgramReadbackEvenWithMatchingRevisionReceipt() async throws {
        let service = try PlanningServiceFixture(proposalId: "11111111-1111-4111-8111-000000000001")
        service.noOpPlanReadback = true
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        let reference = try XCTUnwrap(model.proposal?.cardReference)
        let applied = await model.decideCard(TrainingCardAction(reference: reference, name: .apply))
        XCTAssertFalse(applied)
        XCTAssertEqual(service.decisions.count, 1)
        XCTAssertEqual(model.message, "The saved program does not match the reviewed draft. Refresh before starting.")
    }

    func testStaleCardAndWrongActionCannotWrite() async throws {
        let service = try PlanningServiceFixture(proposalId: "11111111-1111-4111-8111-000000000001")
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        let reference = try XCTUnwrap(model.proposal?.cardReference)
        let stale = TrainingCardReference(component: .planChange, objectId: reference.objectId, revision: 99)
        let staleApplied = await model.decideCard(TrainingCardAction(reference: stale, name: .apply))
        XCTAssertFalse(staleApplied)
        let wrongApplied = await model.decideCard(TrainingCardAction(reference: reference, name: .logSet))
        XCTAssertFalse(wrongApplied)
        XCTAssertTrue(service.decisions.isEmpty)
    }

    func testMissingInputQuestionDoesNotFabricateOrApplyAPlan() async throws {
        let service = try PlanningServiceFixture()
        service.proposalResponse = try JSONDecoder().decode(
            TrainingPlanProposalResponse.self,
            from: Data(#"{"question":"How many days can you realistically train?"}"#.utf8)
        )
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        XCTAssertNil(model.proposal)
        XCTAssertEqual(model.message, "How many days can you realistically train?")
        XCTAssertTrue(service.decisions.isEmpty)
    }

    func testFailedProposalRetryKeepsItsRequestIdentity() async throws {
        let service = try PlanningServiceFixture()
        service.failNextProposal = true
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        XCTAssertNil(model.proposal)
        await model.propose()
        XCTAssertEqual(service.requests.count, 2)
        XCTAssertEqual(service.requests[0].requestId, service.requests[1].requestId)
    }

    func testMismatchedReadbackCannotClaimStart() async throws {
        let service = try PlanningServiceFixture()
        service.commitReadback = false
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { true })
        await model.refresh()
        await model.propose()
        let applied = await model.decide("apply")
        XCTAssertFalse(applied)
        XCTAssertNotNil(model.message)
        XCTAssertNotNil(model.proposal)
    }

    func testAccountChangeWhileProposingCannotInstallAnotherOwnersDraft() async throws {
        let service = try PlanningServiceFixture()
        var current = true
        let model = DelegatedTrainingModel(service: service, accessToken: { "token" }, isCurrent: { current })
        await model.refresh()
        service.onPropose = { current = false }
        await model.propose()
        XCTAssertNil(model.proposal)
        XCTAssertTrue(service.decisions.isEmpty)
    }
}

@MainActor
private final class PlanningServiceFixture: DelegatedTrainingServicing {
    var requests: [TrainingPlanProposalRequest] = []
    var decisions: [TrainingPlanDecisionRequest] = []
    var failNextProposal = false
    var commitReadback = true
    var noOpPlanReadback = false
    var onPropose: (() -> Void)?
    var proposalResponse: TrainingPlanProposalResponse
    private var committed = false

    init(proposalId: String = "proposal") throws {
        proposalResponse = try JSONDecoder().decode(TrainingPlanProposalResponse.self, from: Data(#"""
        {"stored":{"status":"proposed","proposal":{"id":"proposal","reason":"Start training",
        "actor":{"kind":"coach","subject":"lyb-coach"},"summary":["Two days each week"],
        "assumptions":["Conservative baseline"],"plan":{"revision":1,"sessions":[{"id":"monday",
        "day":"monday","slot":"single","title":"Monday","exercises":[{"instanceId":"curl",
        "variantId":"cable_curl","name":"Cable curl","sets":2,"targetReps":10,"priority":"standard"}]}]}}}}
        """#.replacingOccurrences(of: "\"proposal\"", with: "\"\(proposalId)\"").utf8))
    }

    func planningContext(accessToken: String) async throws -> TrainingPlanContext {
        let plan = try proposalResponse.stored.map { try JSONEncoder().encode($0.proposal.plan) } ?? Data("{}".utf8)
        var program = try JSONSerialization.jsonObject(with: plan) as! [String: Any]
        if noOpPlanReadback { program["sessions"] = [] }
        let planJSON = String(data: try JSONSerialization.data(withJSONObject: program), encoding: .utf8)!
        let setup = committed && commitReadback
            ? "{\"programRevisionId\":\"committed-revision\",\"delegated\":{\"plan\":\(planJSON)}}"
            : "null"
        return try JSONDecoder().decode(TrainingPlanContext.self, from: Data("""
        {"generation":0,"delegatedProgramming":true,"knownInputs":{"goal":"Build muscle"},"currentSetup":\(setup)}
        """.utf8))
    }

    func proposePlan(
        accessToken: String, request: TrainingPlanProposalRequest
    ) async throws -> TrainingPlanProposalResponse {
        requests.append(request)
        onPropose?()
        if failNextProposal { failNextProposal = false; throw URLError(.timedOut) }
        return proposalResponse
    }

    func decidePlan(
        accessToken: String, request: TrainingPlanDecisionRequest
    ) async throws -> TrainingPlanDecisionResponse {
        decisions.append(request)
        committed = true
        let receipt: [String: Any] = [
            "proposalId": request.proposalId, "requestId": request.requestId, "status": "applied",
            "revisionId": "committed-revision", "setup": ["programRevisionId": "committed-revision"]
        ]
        return try JSONDecoder().decode(
            TrainingPlanDecisionResponse.self, from: JSONSerialization.data(withJSONObject: ["receipt": receipt])
        )
    }
}
