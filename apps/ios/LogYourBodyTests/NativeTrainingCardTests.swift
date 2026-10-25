import XCTest
@testable import LogYourBody

final class NativeTrainingCardTests: XCTestCase {
    private let proposalId = "33333333-3333-4333-8333-333333333333"
    private let sessionId = "11111111-1111-4111-8111-111111111111"

    func testUnknownComponentGeneratedCodeAndUnauthorizedActionAreRejected() throws {
        let unknown = try jsonObject("""
        {"schemaVersion":1,"component":"WebViewCard","object":{"kind":"proposal","id":"\(proposalId)","revisionId":null},"properties":{}}
        """)
        XCTAssertEqual(NativeTrainingCardContract.parse(unknown), .failure(.unknownComponent))

        let generated = try jsonObject("""
        {"schemaVersion":1,"component":"PlanChangeCard","object":{"kind":"proposal","id":"\(proposalId)","revisionId":null},"properties":{"reason":"eval(1)","diff":[],"reasons":[],"evidenceIds":[],"status":"pending"}}
        """)
        XCTAssertEqual(NativeTrainingCardContract.parse(generated), .failure(.generatedCode))

        let card = try planCard()
        let request = try jsonObject("""
        {"schemaVersion":1,"action":"apply_revision","component":"PlanChangeCard","object":{"kind":"proposal","id":"\(proposalId)","revisionId":null},"actorSubject":"someone-else","payload":{}}
        """)
        XCTAssertEqual(
            NativeTrainingCardContract.admit(card: card, request: request, ownerSubject: "owner-a"),
            .failure(.unauthorized)
        )
        XCTAssertEqual(
            NativeTrainingCardContract.admit(card: card, action: "delete_account", ownerSubject: "owner-a"),
            .failure(.unknownAction)
        )
        XCTAssertEqual(
            NativeTrainingCardContract.admit(card: card, action: "apply_revision", ownerSubject: "owner-a"),
            .success(.decideRevision(proposalId: proposalId, decision: "apply"))
        )
    }

    func testSwapRejectsARebuiltPlanAndKeepsTheEligibleVariant() throws {
        let card = try swapCard()
        let rebuilt = try jsonObject(
            #"{"schemaVersion":1,"action":"swap_exercise","component":"ExerciseSwapCard","# +
            #"object":{"kind":"exercise_swap","id":"44444444-4444-4444-8444-444444444444","# +
            #"revisionId":null},"actorSubject":"owner-a","payload":{"# +
            #"toVariantId":"incline_dumbbell_curl","plan":"rebuilt"}}"#
        )
        XCTAssertEqual(
            NativeTrainingCardContract.admit(card: card, request: rebuilt, ownerSubject: "owner-a"),
            .failure(.unknownField)
        )
        XCTAssertEqual(
            NativeTrainingCardContract.admit(
                card: card, action: "swap_exercise", ownerSubject: "owner-a",
                payload: ["toVariantId": "incline_dumbbell_curl"]
            ),
            .success(.swapExercise(
                sessionId: sessionId, exerciseId: "dumbbell_curl", toVariantId: "incline_dumbbell_curl"
            ))
        )
    }

    func testWorkoutNavigationAndLoggingDoNotRequireAPlanRebuild() throws {
        let card = try workoutCard()
        XCTAssertEqual(
            NativeTrainingCardContract.admit(
                card: card, action: "navigate_exercise", ownerSubject: "owner-a", payload: ["exerciseIndex": 0]
            ),
            .success(.navigate(sessionId: sessionId, exerciseIndex: 0))
        )
        XCTAssertEqual(
            NativeTrainingCardContract.admit(
                card: card, action: "log_set", ownerSubject: "owner-a",
                payload: ["exerciseId": "dumbbell_curl", "setNumber": 1, "reps": 10, "loadKg": NSNull(), "rir": 2]
            ),
            .success(.logSet(TrainingSetLogRequest(
                sessionId: sessionId, exerciseId: "dumbbell_curl", setNumber: 1, reps: 10, loadKg: nil, rir: 2
            )))
        )
    }

    @MainActor
    func testShelfRoundTripSurvivesANewInstance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let card = try planCard()
        let first = NativeTrainingCardShelf(rootURL: root)
        try first.save(
            ownerId: "owner-a",
            record: NativeTrainingCardRecord(cards: [card], exerciseIndexes: [:], sessions: [:])
        )
        let reopened = NativeTrainingCardShelf(rootURL: root)
        XCTAssertEqual(reopened.load(ownerId: "owner-a").cards, [card])
        XCTAssertEqual(reopened.load(ownerId: "someone-else").cards, [])
    }

    func testTrainingCardsEventParsesThePlanAndDropsAnInvalidPayload() throws {
        var parser = ChatSSEParser()
        XCTAssertNil(try parser.consume(line: "event: training_cards"))
        XCTAssertNil(try parser.consume(line: "data: \(trainingCardsData(planJSON))"))
        guard case .trainingCards(let cards) = try parser.consume(line: "") else {
            return XCTFail("Expected a training card event")
        }
        XCTAssertEqual(cards.first?.component, "PlanChangeCard")
        XCTAssertEqual(cards.first?.object.id, proposalId)
        if case .planChange(let change) = cards.first?.properties {
            XCTAssertEqual(change.reason, "Keep the cable curl.")
            XCTAssertEqual(change.reasons, ["Biceps stay the priority."])
            XCTAssertEqual(change.evidenceIds, ["k:81c218db"])
            XCTAssertEqual(change.status, "pending")
        } else {
            XCTFail("Expected a plan change")
        }

        var invalid = ChatSSEParser()
        XCTAssertNil(try invalid.consume(line: "event: training_cards"))
        let invalidPayload = #"{"version":1,"schemaVersion":1,"cards":["# +
            #"{"component":"WebViewCard","code":"eval(1)"}]}"#
        XCTAssertNil(try invalid.consume(line: "data: \(invalidPayload)"))
        XCTAssertNil(try invalid.consume(line: ""))

        var mismatched = ChatSSEParser()
        XCTAssertNil(try mismatched.consume(line: "event: training_cards"))
        XCTAssertNil(try mismatched.consume(line: #"data: {"version":1,"schemaVersion":2,"cards":[]}"#))
        XCTAssertThrowsError(try mismatched.consume(line: "")) { error in
            XCTAssertEqual(error as? ChatServiceError, .invalidResponse)
        }
    }

    private var planJSON: String {
        """
        {"schemaVersion":1,"component":"PlanChangeCard","object":{"kind":"proposal","id":"\(proposalId)","revisionId":null},"properties":{"reason":"Keep the cable curl.","diff":[],"reasons":["Biceps stay the priority."],"evidenceIds":["k:81c218db"],"status":"pending"}}
        """
    }

    private func planCard() throws -> NativeTrainingCard {
        guard case .success(let card) = NativeTrainingCardContract.parse(try jsonObject(planJSON)) else {
            struct FixtureError: Error {}
            throw FixtureError()
        }
        return card
    }

    private func swapCard() throws -> NativeTrainingCard {
        let text = """
        {"schemaVersion":1,"component":"ExerciseSwapCard","object":{"kind":"exercise_swap","id":"44444444-4444-4444-8444-444444444444","revisionId":null},"properties":{"sessionId":"\(sessionId)","exerciseId":"dumbbell_curl","alternatives":[{"id":"incline_dumbbell_curl","name":"Incline dumbbell curl","tradeoff":"Lower trunk demand than a standing curl."}]}}
        """
        guard case .success(let card) = NativeTrainingCardContract.parse(try jsonObject(text)) else {
            struct FixtureError: Error {}
            throw FixtureError()
        }
        return card
    }

    private func workoutCard() throws -> NativeTrainingCard {
        let text = """
        {"schemaVersion":1,"component":"WorkoutSessionCard","object":{"kind":"session","id":"\(sessionId)","revisionId":null},"properties":{"title":"Arms","week":1,"slot":0,"exercises":[{"id":"dumbbell_curl","name":"Dumbbell curl","setup":"Use the prescribed setup for Dumbbell curl.","sets":3,"repRange":{"min":8,"max":12},"targetReps":10,"targetRir":2,"targetLoadKg":null,"completedSets":0}],"previous":[]}}
        """
        guard case .success(let card) = NativeTrainingCardContract.parse(try jsonObject(text)) else {
            struct FixtureError: Error {}
            throw FixtureError()
        }
        return card
    }

    private func trainingCardsData(_ card: String) -> String {
        #"{"version":1,"schemaVersion":1,"cards":["# + card + "]}"
    }

    private func jsonObject(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8))
    }
}
