import XCTest
@testable import LogYourBody

@MainActor
final class TrainingProgressTests: XCTestCase {
    private func payload(version: Int = 1) -> Data {
        Data("""
        {"version":\(version),"progress":{"enrolled":true,"completedSessions":2,
        "setsLast7Days":4,"exercises":[],"latestCheckIn":null,"sessions":[]}}
        """.utf8)
    }

    private func response() throws -> TrainingProgressResponse {
        try JSONDecoder().decode(TrainingProgressResponse.self, from: payload())
    }

    func testRecordedSetRetainsIdentityAndCorrectedPerformance() throws {
        let data = Data("""
        {"id":"set-a","sessionId":"session-a","exerciseId":"variant-a","setNumber":1,
        "reps":8,"loadKg":12.5,"rir":2,"completedAt":"2026-10-25T10:00:00.000Z","revision":1,
        "corrections":[{"id":"correction-a","correctedAt":"2026-10-25T11:00:00.000Z",
        "previous":{"reps":10,"loadKg":125,"rir":3}}]}
        """.utf8)
        let set = try JSONDecoder().decode(TrainingProgress.RecordedSet.self, from: data)
        XCTAssertEqual(set.id, "set-a")
        XCTAssertEqual(set.sessionId, "session-a")
        XCTAssertEqual(set.exerciseId, "variant-a")
        XCTAssertEqual(set.loadKg, 12.5)
        XCTAssertEqual(set.revision, 1)
        XCTAssertEqual(set.corrections?.first?.previous.loadKg, 125)
        XCTAssertTrue(set.performanceText.contains("8 reps"))
        XCTAssertTrue(set.performanceText.contains("2 RIR"))
    }

    func testFeedbackRetainsCorrectionAndSourceProvenanceWithoutInferringGrowth() throws {
        let data = Data("""
        {"id":"feedback-a","sessionId":"session-a","pump":9,"trunkFatigue":1,
        "source":"voice","sourceObservationId":"voice-a","correctsObservationId":"feedback-old",
        "originalStatement":"Less back fatigue today","createdAt":"2026-10-25T10:00:00.000Z",
        "context":{"exerciseId":"variant-a","setId":"set-a","setNumber":1}}
        """.utf8)
        let feedback = try JSONDecoder().decode(TrainingProgress.Feedback.self, from: data)
        XCTAssertEqual(feedback.pump, 9)
        XCTAssertEqual(feedback.trunkFatigue, 1)
        XCTAssertEqual(feedback.sourceObservationId, "voice-a")
        XCTAssertEqual(feedback.correctsObservationId, "feedback-old")
        XCTAssertEqual(feedback.context?.setId, "set-a")
        XCTAssertEqual(feedback.originalStatement, "Less back fatigue today")
    }

    func testMovementResponsePreservesIndependentDimensionsAndUnknownValues() throws {
        var request = TrainingFeedbackRequest(sessionId: "session-a")
        request.context = .init(exerciseId: "cable_curl", setNumber: 1, gymId: "Gym", romRestriction: "blocked")
        request.trunkFatigue = 6
        request.generalExhaustion = 1
        request.targetMuscleQuality = "good"
        request.stability = "unstable"
        let data = try JSONEncoder().encode(request)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["trunkFatigue"] as? Int, 6)
        XCTAssertEqual(payload["generalExhaustion"] as? Int, 1)
        XCTAssertNil(payload["jointPain"])
        XCTAssertNil(payload["symptomFlags"])
        XCTAssertEqual(try JSONDecoder().decode(TrainingFeedbackRequest.self, from: data), request)
    }

    func testSelectionReviewUsesAuthenticatedRequestAndRejectsMismatchedContext() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TrainingProgressURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        defer { urlSession.invalidateAndCancel() }
        let service = URLSessionTrainingService(urlSession: urlSession, baseURL: URL(string: "https://training.example"))
        let context = TrainingSelectionContext(gymId: "Gym", availableEquipment: ["cable"], excludedConcerns: [])
        let request = TrainingSelectionRequest(sessionId: "session-a", exerciseId: "cable_curl", context: context)
        func payload(gym: String = "Gym", version: Int = 1, sessionId: String = "session-a",
                     exerciseId: String = "cable_curl", optionCount: Int = 0) -> Data {
            let option = """
            {"variantId":"supported_cable_curl","reason":"supported_setup_trial","name":"Supported curl",
            "setup":{"requires":["cable"],"bodyPosition":"seated","torsoSupport":"bench",
            "trunkDemand":{"level":"low","basis":"setup","note":"Supported"},"cues":[]}}
            """
            let options = Array(repeating: option, count: optionCount).joined(separator: ",")
            let status = optionCount == 0 ? "no_eligible_alternative" : "suggested"
            return Data("""
            {"version":\(version),"review":{"sessionId":"\(sessionId)","exerciseId":"\(exerciseId)","revision":0,
            "status":"\(status)","context":{"gymId":"\(gym)","availableEquipment":["cable"],
            "excludedConcerns":[]},"options":[\(options)],"message":"Check the current station."}}
            """.utf8)
        }
        let response = payload()
        TrainingProgressURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, TrainingAPIContract.rootPath + "/alternatives")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            return (200, response)
        }
        let loaded = try await service.reviewSelection(accessToken: "test-token", request: request)
        XCTAssertTrue(loaded.review.options.isEmpty)
        XCTAssertEqual(loaded.review.context, context)
        let suggested = payload(optionCount: 2)
        TrainingProgressURLProtocol.install { _ in (200, suggested) }
        let options = try await service.reviewSelection(accessToken: "test-token", request: request)
        XCTAssertEqual(options.review.options.count, 2)
        for invalid in [payload(gym: "Old gym"), payload(version: 2), payload(sessionId: "other"),
                        payload(exerciseId: "other"), payload(optionCount: 3)] {
            TrainingProgressURLProtocol.install { _ in (200, invalid) }
            do {
                _ = try await service.reviewSelection(accessToken: "test-token", request: request)
                XCTFail("Only a current version, matching context and at most two options can authorize a review")
            } catch { XCTAssertEqual(error as? TrainingServiceError, .invalidResponse) }
        }
    }

    func testSharedTransportValidatesVersionOutsideThePlanningPayload() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TrainingProgressURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        defer { urlSession.invalidateAndCancel() }
        let service = URLSessionTrainingService(urlSession: urlSession, baseURL: URL(string: "https://training.example"))
        let response = Data(#"{"version":1,"generation":3}"#.utf8)
        TrainingProgressURLProtocol.install { _ in (200, response) }
        let context = try await service.planningContext(accessToken: "test-token")
        XCTAssertEqual(context.generation, 3)
        let unsupported = Data(#"{"version":2,"generation":3}"#.utf8)
        TrainingProgressURLProtocol.install { _ in (200, unsupported) }
        do {
            _ = try await service.planningContext(accessToken: "test-token")
            XCTFail("Payloads without a version property still require the supported API envelope")
        } catch { XCTAssertEqual(error as? TrainingServiceError, .invalidResponse) }
    }

    func testSessionReviewRetainsOriginalVariantAndExplicitSkip() {
        let exercise = TrainingExercisePrescription(
            id: "exact-variant", name: "Recorded curl", primaryMuscle: "biceps",
            muscleContribution: ["biceps": 1], sets: 2, repRange: .init(min: 8, max: 12),
            targetReps: 10, targetRir: 3, targetLoadKg: 12, loadInstruction: nil,
            progression: "hold", evidenceIds: []
        )
        let initial = TrainingSession(
            id: "session-a", week: 1, slot: 0, pattern: "A", title: "Recorded session",
            exercises: [exercise], safetyStop: false, explanation: nil, evidenceIds: [], loggedSets: nil
        )
        let current = TrainingSession(
            id: "session-a", week: 1, slot: 0, pattern: "A", title: "Recorded session",
            exercises: [], safetyStop: false, explanation: nil, evidenceIds: [], loggedSets: nil,
            executionEvents: [.init(id: "skip-a", kind: "skipped", createdAt: "2026-10-25T10:00:00Z",
                                    exerciseId: "exact-variant", replacementExerciseId: nil, minutes: nil)]
        )
        let history = TrainingProgress.SessionHistory(
            sessionId: "session-a", programSetupId: "setup-a", programRevisionId: "revision-a", blockId: "block-a",
            status: "paused", startedAt: nil, completedAt: nil, initialPrescription: initial,
            prescription: current, sets: [], feedback: []
        )
        XCTAssertEqual(history.initialPrescription?.exercises.first?.id, "exact-variant")
        XCTAssertEqual(history.programRevisionId, "revision-a")
        XCTAssertEqual(history.skippedExerciseNames, ["Recorded curl"])
        XCTAssertEqual(history.statusText, "Session paused")
    }

    func testOnlyMeaningfulEngineChangesHaveBeforeAndAfterExplanations() throws {
        for (kind, before, after, expected) in [
            ("hold", "same", "same", false),
            ("ask_question", "plan", "pending answer", false),
            ("recovery_proposal", "plan", "proposed deload", true),
            ("adjust_training", "plan", "plan", false)
        ] {
            let data = try JSONSerialization.data(withJSONObject: [
                "decision": ["kind": kind], "before": before, "after": after,
                "rationale": "Engine reason", "nextAction": "Engine action",
                "reviewPoint": "Next session", "evidenceIds": ["k:engine"]
            ])
            let receipt = try JSONDecoder().decode(TrainingProgressDecision.self, from: data)
            XCTAssertEqual(receipt.hasMeaningfulChange, expected)
            XCTAssertEqual(receipt.nextAction, "Engine action")
        }
    }

    func testHistoryFailureCanRetryWithoutLosingTheWorkout() async throws {
        let model = TrainingProgressModel(isCurrent: { true })
        await model.load { throw URLError(.notConnectedToInternet) }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.response)
        XCTAssertFalse(model.isLoading)
        let expected = try response()
        await model.load { expected }
        XCTAssertEqual(model.response, expected)
        XCTAssertNil(model.errorMessage)
        await model.load { throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(model.response, expected)
        XCTAssertNotNil(model.errorMessage)
    }

    func testHistoryFromAnExpiredOwnerIsDiscarded() async throws {
        var current = true
        let model = TrainingProgressModel(isCurrent: { current })
        let expected = try response()
        await model.load {
            current = false
            return expected
        }
        XCTAssertNil(model.response)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testOlderHistoryResponseCannotOverwriteACompletedRefresh() async throws {
        let model = TrainingProgressModel(isCurrent: { true })
        let expected = try response()
        let older = try JSONDecoder().decode(TrainingProgressResponse.self, from: Data("""
        {"version":1,"progress":{"enrolled":true,"completedSessions":0,
        "setsLast7Days":0,"exercises":[],"latestCheckIn":null,"sessions":[]}}
        """.utf8))
        await model.load {
            await model.load { expected }
            return older
        }
        XCTAssertEqual(model.response, expected)
        XCTAssertFalse(model.isLoading)
    }

    func testProgressServiceUsesAuthenticatedReadAndValidatesResponseVersion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TrainingProgressURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = URLSessionTrainingService(urlSession: session, baseURL: URL(string: "https://training.example"))
        let body = payload()
        TrainingProgressURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, TrainingAPIContract.rootPath + "/progress")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertNil(request.httpBody)
            return (200, body)
        }
        let loaded = try await service.loadProgress(accessToken: "test-token")
        XCTAssertEqual(loaded.progress.completedSessions, 2)
        let invalid = payload(version: 2)
        TrainingProgressURLProtocol.install { _ in (200, invalid) }
        do {
            _ = try await service.loadProgress(accessToken: "test-token")
            XCTFail("Unsupported versions must be rejected")
        } catch {
            XCTAssertEqual(error as? TrainingServiceError, .invalidResponse)
        }
        TrainingProgressURLProtocol.install { _ in (401, Data()) }
        do {
            _ = try await service.loadProgress(accessToken: "test-token")
            XCTFail("Expired authentication must be rejected")
        } catch {
            XCTAssertEqual(error as? TrainingServiceError, .authenticationExpired)
        }
    }
}

private final class TrainingProgressURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> (Int, Data))?

    static func install(_ value: @escaping (URLRequest) -> (Int, Data)) {
        lock.lock()
        handler = value
        lock.unlock()
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let respond = Self.handler
        Self.lock.unlock()
        guard let respond, let url = request.url else { return }
        let (status, body) = respond(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
