import XCTest
@testable import LogYourBody

@MainActor
final class NativeTrainingCardContractTests: XCTestCase {
    private let owner = "user-subject-1"
    private let sessionId = "11111111-1111-4111-8111-111111111111"
    private let exerciseId = "33333333-3333-4333-8333-333333333333"
    private let variantId = "44444444-4444-4444-8444-444444444444"
    private let proposalId = "22222222-2222-4222-8222-222222222222"

    func testGateStaysOffUnlessThePlatformEnablesIt() {
        XCTAssertFalse(NativeTrainingCardPolicy.jsonRenderSupported)
        XCTAssertEqual(NativeTrainingCardPolicy.renderConsumer, "swiftui-owned-views")
        XCTAssertFalse(NativeTrainingCardPolicy.isEnabled { _ in false })
        XCTAssertTrue(NativeTrainingCardPolicy.isEnabled { $0 == NativeTrainingCardPolicy.featureGate })
    }

    func testLoggingStaysEnabledWhileChatIsBusyOrOffline() {
        XCTAssertTrue(NativeTrainingCardInteractionPolicy.loggingEnabled(chatBusy: true, offline: true))
        XCTAssertFalse(NativeTrainingCardInteractionPolicy.planWriteEnabled(pending: true))
        XCTAssertNil(NativeTrainingCardDispatch.savedRevisionDecision("run_code"))
        XCTAssertEqual(NativeTrainingCardDispatch.savedRevisionDecision("apply_saved_revision"), "apply")
        XCTAssertFalse(NativeTrainingCardDispatch.adjustmentUtteranceIsValid("javascript:alert(1)"))
    }

    func testProjectorUsesDurableIdsAndRejectsTranscriptOnlyCards() {
        let cards = NativeTrainingCardProjector.renderable(
            response: response(), plan: nil, planRevisionId: nil, ownerSubject: owner,
            transcriptText: #"{"component":"PlanChangeCard","objectId":"99999999-9999-4999-8999-999999999999"}"#
        )
        let workout = cards.first { $0.component == "WorkoutSessionCard" }
        XCTAssertEqual(workout?.objectId, sessionId)
        XCTAssertEqual(workout?.revision, "3")
        XCTAssertTrue(workout?.actions.contains { $0.kind == "log_set" && $0.operation == "session_log" } == true)
        XCTAssertTrue(cards.contains { $0.component == "ExerciseSwapCard" })
        XCTAssertFalse(cards.contains { $0.objectId == "99999999-9999-4999-8999-999999999999" })
        let echoed = NativeTrainingCardContract.approveTranscriptText(
            #"{"schemaVersion":1,"component":"WorkoutSessionCard","objectId":"\#(sessionId)","revision":"4","ownerSubject":"\#(owner)","props":{"sessionId":"\#(sessionId)","exercises":[]},"actions":[]}"#,
            ownerSubject: owner, durable: cards
        )
        XCTAssertEqual(echoed?.reason, .transcriptOnly)
    }

    func testValidationRejectsUnknownComponentsInvalidIdsUnauthorizedWritesAndCode() {
        let unknown = NativeTrainingCardContract.validate(planChange(component: "WebWorkoutApp"), ownerSubject: owner)
        XCTAssertEqual(unknown.reason, .unknownComponent)
        let invalid = NativeTrainingCardContract.validate(planChange(objectId: "transcript-9"), ownerSubject: owner)
        XCTAssertEqual(invalid.reason, .invalidId)
        let foreign = NativeTrainingCardContract.validate(planChange(), ownerSubject: "someone-else")
        XCTAssertEqual(foreign.reason, .unauthorized)
        var coded = planChange()
        coded["code"] = "process.exit(1)"
        XCTAssertEqual(NativeTrainingCardContract.validate(coded, ownerSubject: owner).reason, .generatedCode)
        var scored = planChange()
        scored["readinessScore"] = 88
        XCTAssertEqual(NativeTrainingCardContract.validate(scored, ownerSubject: owner).reason, .inventedScore)
        let approved = NativeTrainingCardContract.validate(planChange(), ownerSubject: owner)
        XCTAssertEqual(approved.card?.actions.first?.operation, "saved_revision")
        let injected = NativeTrainingCardContract.approveTranscript(
            planChange(), ownerSubject: owner, durable: [approved.card].compactMap { $0 }.map {
                ApprovedNativeTrainingCard(
                    component: $0.component, objectId: $0.objectId, revision: $0.revision,
                    ownerSubject: $0.ownerSubject, actions: []
                )
            }
        )
        XCTAssertEqual(injected.reason, .unauthorized)
    }

    func testSnapshotSurvivesRelaunchForTheOwningAccountOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NativeTrainingCardStore(rootURL: root)
        let snapshot = NativeTrainingCardSnapshot(
            schemaVersion: NativeTrainingCardPolicy.schemaVersion, ownerSubject: owner,
            response: response(), plan: nil, planRevisionId: nil
        )
        try store.save(snapshot)
        let reloaded = NativeTrainingCardStore(rootURL: root).load(ownerSubject: owner)
        XCTAssertEqual(reloaded?.response.session?.id, sessionId)
        XCTAssertEqual(reloaded?.response.session?.executionRevision, 3)
        XCTAssertNil(store.load(ownerSubject: "other-subject"))
        try? FileManager.default.removeItem(at: root)
    }

    private func response() -> TrainingNextResponse {
        let exercise = TrainingExercisePrescription(
            id: exerciseId, name: "Incline curl", primaryMuscle: "biceps",
            muscleContribution: ["biceps": 0.8], sets: 3,
            repRange: .init(min: 8, max: 12), targetReps: 10, targetRir: 2, targetLoadKg: 12,
            loadInstruction: "Seat supported", progression: "hold", evidenceIds: ["evidence-1"],
            substitutions: [
                TrainingExerciseSubstitution(
                    id: variantId, name: "Bayesian curl", primaryMuscle: "biceps",
                    muscleContribution: ["biceps": 0.9], sets: 3, repRange: .init(min: 8, max: 12),
                    targetReps: 10, targetRir: 2, targetLoadKg: nil, loadInstruction: nil,
                    progression: "hold", evidenceIds: ["evidence-2"]
                )
            ]
        )
        let session = TrainingSession(
            id: sessionId, week: 1, slot: 1, pattern: "A", title: "Upper A", exercises: [exercise],
            safetyStop: false, explanation: nil, evidenceIds: [], loggedSets: [
                TrainingSavedSet(
                    sessionId: sessionId, exerciseId: exerciseId, setNumber: 1, reps: 10,
                    loadKg: 12, rir: 2, completedAt: nil, revision: 1, corrections: nil
                )
            ],
            executionRevision: 3, executionPaused: false, executionEvents: nil
        )
        return TrainingNextResponse(
            version: 1, error: nil, session: session, week: 1, weekCount: 4,
            weeklyFractionalVolume: nil, decision: TrainingProgressDecision(
                decision: .init(kind: "adjust_training", requiresConfirmation: true),
                rationale: "Recorded sets support one more set.", evidenceIds: ["evidence-1"],
                before: "3 sets", after: "4 sets", reviewPoint: "next session", nextAction: "Confirm the change."
            ),
            nextBlock: TrainingPlanStoredProposal(
                status: "proposed",
                proposal: .init(
                    id: proposalId, reason: "Biceps priority",
                    actor: .init(kind: "self", subject: owner),
                    summary: ["Low-trunk curl stays"], assumptions: ["Equipment is unchanged"],
                    plan: CanvasPlan(revision: 7, sessions: []),
                    transition: .init(
                        staying: ["Incline curl"], changing: ["Add one set"],
                        why: "The last recorded set was inside the target.", expiring: []
                    )
                )
            )
        )
    }

    private func planChange(component: String = "PlanChangeCard", objectId: String? = nil) -> [String: Any] {
        let id = objectId ?? proposalId
        return [
            "schemaVersion": 1,
            "component": component,
            "objectId": id,
            "revision": "7",
            "ownerSubject": owner,
            "props": ["proposalId": id],
            "actions": [[
                "kind": "apply_saved_revision",
                "operation": "saved_revision",
                "proposalId": id,
                "expectedRevision": "7"
            ]]
        ]
    }
}
