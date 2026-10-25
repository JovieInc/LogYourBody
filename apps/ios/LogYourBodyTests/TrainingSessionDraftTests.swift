import XCTest
@testable import LogYourBody

@MainActor
private final class TrainingHeldResponse {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class TrainingSessionDraftTests: XCTestCase {
    private let exercise = TrainingExercisePrescription(
        id: "fixture_press", name: "Fixture press", primaryMuscle: "chest", muscleContribution: ["chest": 1],
        sets: 2, repRange: .init(min: 8, max: 12), targetReps: 10, targetRir: 3, targetLoadKg: 60,
        loadInstruction: "Repeat last session's load.", progression: "hold", evidenceIds: []
    )

    private func session(id: String = "fixture-session", saved: [TrainingSavedSet] = []) -> TrainingSession {
        TrainingSession(
            id: id, week: 2, slot: 0, pattern: "A", title: "Fixture session", exercises: [exercise],
            safetyStop: false, explanation: nil, evidenceIds: [], loggedSets: saved
        )
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LYB-TrainingDraft-Test-" + UUID().uuidString)
    }

    private func model(_ store: TrainingDraftStore, owner: String = "owner-A") -> TrainingSessionDraft {
        TrainingSessionDraft(session: session(), ownerId: owner, store: store, isCurrent: { true })
    }

    func testFeedbackRequestEncodesOptionalMuscleDetailAndTouchSource() throws {
        let request = TrainingFeedbackRequest(
            sessionId: "fixture-session",
            jointPain: 0,
            muscles: [
                "chest": TrainingMuscleFeedbackRequest(
                    soreness: 5,
                    recovery: "limited",
                    pump: 8,
                    workload: "as_expected",
                    performance: "down"
                )
            ]
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        XCTAssertEqual(object["source"] as? String, "touch")
        let muscles = try XCTUnwrap(object["muscles"] as? [String: Any])
        let chest = try XCTUnwrap(muscles["chest"] as? [String: Any])
        XCTAssertEqual(chest["soreness"] as? Int, 5)
        XCTAssertEqual(chest["recovery"] as? String, "limited")
        XCTAssertEqual(chest["workload"] as? String, "as_expected")
        XCTAssertNil(object["soreness"])
        XCTAssertNil(object["pump"])
        XCTAssertNil(object["performance"])
    }

    private func feedbackProposal(
        _ intent: TrainingWorkoutFeedback.Intent, set: Int = 1, statement: String = "reported observation"
    ) -> TrainingWorkoutFeedback {
        TrainingWorkoutFeedback(
            sessionId: "fixture-session", exerciseId: exercise.id, setNumber: set,
            intent: intent, originalStatement: statement
        )
    }

    func testReadinessVoiceWireContractAndFlattenedCanonicalReceiptDecode() throws {
        let data = Data("""
        {"version":1,"kind":"workout_feedback","requiresConfirmation":true,
         "feedback":{"sessionId":"fixture-session","exerciseId":"fixture_press","setNumber":1,
                     "intent":"breathing_limited","originalStatement":"still out of breath"}}
        """.utf8)
        let voice = try JSONDecoder().decode(VoiceIntentResponse.self, from: data)
        XCTAssertEqual(voice.feedback?.intent, .breathingLimited)
        XCTAssertEqual(voice.feedback?.setNumber, 1)
        var request = TrainingFeedbackRequest(sessionId: "fixture-session", source: "voice")
        request.breathingReadiness = "limited"
        request.sourceObservationId = "utterance-1"
        request.context = TrainingFeedbackContext(exerciseId: exercise.id, setNumber: 1)
        let encoded = try JSONEncoder().encode(feedbackResponse(request, action: .extendRest))
        let decoded = try JSONDecoder().decode(TrainingFeedbackResponse.self, from: encoded)
        XCTAssertTrue(decoded.matches(request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let receipt = try XCTUnwrap(object["feedback"] as? [String: Any])
        XCTAssertEqual(receipt["breathingReadiness"] as? String, "limited")
        XCTAssertNil(receipt["observation"], "Native storage and the server use the same flat feedback shape")
    }

    func testRestRequestDoesNotInventAReadinessSignal() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let draft = model(TrainingDraftStore(rootURL: directory))
        for intent in [TrainingWorkoutFeedback.Intent.moreRest, .unknown] {
            await draft.recordWorkoutFeedback(feedbackProposal(intent), source: "touch") { request in
                XCTAssertEqual(request.targetMuscleReadiness, "unknown")
                XCTAssertNil(request.breathingReadiness)
                XCTAssertNil(request.supportingReadiness)
                return self.feedbackResponse(request, action: .clarify)
            }
            XCTAssertEqual(draft.nextSetRecommendation?.action, .clarify)
            XCTAssertEqual(draft.currentPosition?.setNumber, 1)
        }
    }

    private func feedbackResponse(
        _ request: TrainingFeedbackRequest, action: TrainingNextSetRecommendation.Action
    ) -> TrainingFeedbackResponse {
        TrainingFeedbackResponse(
            version: 1, feedback: .init(id: "observation-1", observation: request),
            nextSetRecommendation: .init(
                scope: "between_set", action: action, reasons: ["Canonical decision"], uncertainty: "moderate",
                observationIds: ["observation-1"], weeklyPlanChanged: false, safetyCertified: false
            )
        )
    }

    func testReadinessSurvivesExpiredTimerOfflineRetryAndDoesNotAdvanceTheSet() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        var time = Date()
        let draft = TrainingSessionDraft(
            session: session(), ownerId: "owner-A", store: store, isCurrent: { true }, now: { time }
        )
        await draft.save(exercise, setNumber: 1) { _ in }
        let intended = try XCTUnwrap(draft.currentPosition)
        time = time.addingTimeInterval(120)
        XCTAssertLessThan(try XCTUnwrap(draft.restUntil), time)
        XCTAssertNil(draft.nextSetRecommendation, "Timer expiry cannot establish readiness")
        var attempts: [TrainingFeedbackRequest] = []
        await draft.recordWorkoutFeedback(feedbackProposal(.breathingLimited, set: 2), source: "voice") { request in
            attempts.append(request)
            XCTAssertEqual(try store.loadFeedback(ownerId: "owner-A", sessionId: "fixture-session")?.request, request)
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(draft.currentPosition, intended)
        XCTAssertNil(draft.feedback?.response)
        let restored = TrainingSessionDraft(
            session: session(saved: Array(draft.loggedSets.values)), ownerId: "owner-A", store: store,
            isCurrent: { true }, now: { time }
        )
        XCTAssertEqual(restored.currentPosition, intended)
        XCTAssertNotNil(restored.restUntil, "An expired timer stays advisory on relaunch")
        await restored.retryFeedback { request in
            attempts.append(request)
            return self.feedbackResponse(request, action: .extendRest)
        }
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts.first, attempts.last, "Retry retains the observation identity and timestamp")
        XCTAssertEqual(restored.nextSetRecommendation?.action, .extendRest)
        XCTAssertEqual(restored.currentPosition, intended)
        var submissions = 0
        await restored.save(exercise, setNumber: 2) { _ in submissions += 1 }
        await restored.save(exercise, setNumber: 2) { _ in submissions += 1 }
        XCTAssertEqual(submissions, 1, "A limitation never prevents truthful logging of what happened")
        XCTAssertEqual(restored.completedCount, 2)
        XCTAssertNil(restored.nextSetRecommendation, "A receipt cannot certify the following set")
    }

    func testReadinessRejectsWrongSetReceiptStaleControllerAndWrongAccount() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let draft = model(store)
        var sends = 0
        await draft.recordWorkoutFeedback(feedbackProposal(.ready, set: 2), source: "text") { request in
            sends += 1
            return self.feedbackResponse(request, action: .proceed)
        }
        XCTAssertEqual(sends, 0)
        await draft.recordWorkoutFeedback(feedbackProposal(.ready), source: "text") { request in
            var wrong = request
            wrong.context = TrainingFeedbackContext(exerciseId: "stale-exercise", setNumber: 1)
            return self.feedbackResponse(wrong, action: .proceed)
        }
        XCTAssertNil(draft.nextSetRecommendation)
        XCTAssertNotNil(draft.errorMessage)
        XCTAssertNil(draft.feedback?.response)
        XCTAssertNil(try store.loadFeedback(ownerId: "owner-B", sessionId: "fixture-session"))
        let stale = model(store)
        await draft.retryFeedback { request in self.feedbackResponse(request, action: .proceed) }
        await stale.retryFeedback { request in self.feedbackResponse(request, action: .extendRest) }
        XCTAssertNil(stale.feedback?.response, "A stale controller must not replace an acknowledged journal")
        XCTAssertNotNil(stale.errorMessage)
        XCTAssertEqual(draft.nextSetRecommendation?.action, .proceed)
    }

    func testPerformanceOnlyFeedbackRetainsCanonicalLimitationThroughOfflineRelaunch() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let draft = model(store)
        await draft.save(exercise, setNumber: 1) { _ in }
        await draft.recordWorkoutFeedback(feedbackProposal(.breathingLimited, set: 2), source: "voice") { request in
            self.feedbackResponse(request, action: .extendRest)
        }
        await draft.recordWorkoutFeedback(feedbackProposal(.unusuallyWeak), source: "text") { _ in
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(draft.nextSetRecommendation?.action, .extendRest)
        let restored = TrainingSessionDraft(
            session: session(saved: Array(draft.loggedSets.values)), ownerId: "owner-A", store: store,
            isCurrent: { true }
        )
        XCTAssertEqual(restored.nextSetRecommendation?.action, .extendRest)
        await restored.retryFeedback { request in
            TrainingFeedbackResponse(
                version: 1, feedback: .init(id: "weak-set-observation", observation: request),
                nextSetRecommendation: self.feedbackResponse(request, action: .extendRest).nextSetRecommendation
            )
        }
        XCTAssertEqual(restored.feedback?.response?.feedback.id, "weak-set-observation")
        XCTAssertEqual(restored.nextSetRecommendation?.action, .extendRest,
                       "A performance receipt must retain the readiness evidence named by the canonical decision")
        XCTAssertEqual(restored.currentPosition?.setNumber, 2)
    }

    func testPendingLimitationCannotRetainEarlierProceedRecommendation() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let draft = model(TrainingDraftStore(rootURL: directory))
        await draft.recordWorkoutFeedback(feedbackProposal(.ready), source: "touch") { request in
            self.feedbackResponse(request, action: .proceed)
        }
        XCTAssertEqual(draft.nextSetRecommendation?.action, .proceed)
        await draft.recordWorkoutFeedback(feedbackProposal(.gripLimited), source: "voice") { _ in
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertNil(draft.nextSetRecommendation, "Pending limitation cannot reuse earlier readiness clearance")
        XCTAssertNil(draft.feedback?.response)
        XCTAssertEqual(draft.currentPosition?.setNumber, 1)
    }

    func testWeakSetFeedbackRetainsActualValuesAndCorrectionLinksWithoutChangingPrescription() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let draft = model(store)
        draft.update(exercise, setNumber: 1) { $0.repsText = "9"; $0.rir = 1 }
        await draft.save(exercise, setNumber: 1) { _ in }
        await draft.recordWorkoutFeedback(feedbackProposal(.unusuallyWeak), source: "text") { request in
            XCTAssertEqual(request.performance, "down")
            XCTAssertEqual(request.context?.reps, 9)
            XCTAssertEqual(request.context?.loadKg, 60)
            XCTAssertEqual(request.context?.rir, 1)
            XCTAssertNil(request.soreness, "Unreported signals must stay unknown")
            return self.feedbackResponse(request, action: .clarify)
        }
        await draft.recordWorkoutFeedback(feedbackProposal(.gripLimited, set: 2), source: "touch") { request in
            XCTAssertEqual(request.supportingReadiness?.grip, "limited")
            XCTAssertNil(request.breathingReadiness)
            return self.feedbackResponse(request, action: .adjustOrSkip)
        }
        await draft.recordWorkoutFeedback(
            feedbackProposal(.ready, set: 2, statement: "actually I am ready now"), source: "voice"
        ) { request in
            XCTAssertEqual(request.correctsObservationId, "observation-1")
            return self.feedbackResponse(request, action: .proceed)
        }
        XCTAssertEqual(draft.session.exercises, session().exercises)
        XCTAssertEqual(draft.currentPosition?.setNumber, 2)
    }

    func testReadinessDuplicateReceiptRetainsOriginalAgeAndSymptomsOverrideReady() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let draft = model(TrainingDraftStore(rootURL: directory))
        await draft.recordWorkoutFeedback(feedbackProposal(.ready), source: "text") { request in
            var original = request
            original.sourceObservationId = "original-duplicate"
            original.observedAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3_600))
            let response = self.feedbackResponse(original, action: .proceed)
            XCTAssertTrue(response.matches(request), "The server may return the original exact-duplicate receipt")
            return response
        }
        XCTAssertNotNil(draft.feedback?.response)
        XCTAssertNil(draft.nextSetRecommendation, "An exact replay must not refresh old readiness")
        await draft.recordWorkoutFeedback(feedbackProposal(.ready), source: "text") { request in
            self.feedbackResponse(request, action: .symptomSafety)
        }
        XCTAssertEqual(draft.nextSetRecommendation?.action, .symptomSafety)
        await draft.recordWorkoutFeedback(feedbackProposal(.unknown), source: "text") { _ in
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(draft.nextSetRecommendation?.action, .symptomSafety, "Pending feedback cannot clear symptoms")
        let restored = model(TrainingDraftStore(rootURL: directory))
        XCTAssertEqual(restored.nextSetRecommendation?.action, .symptomSafety, "The safety hold must survive relaunch")
    }

    func testFeedbackDiskFailureAndAccountChangeNeverAcknowledgeReadiness() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let brokenStore = TrainingDraftStore(rootURL: directory) { _, _, _ in throw TrainingDraftError.unavailable }
        let broken = model(brokenStore)
        await broken.recordWorkoutFeedback(feedbackProposal(.ready), source: "touch") { _ in
            XCTFail("Persistence must precede transport")
            throw TrainingDraftError.unavailable
        }
        XCTAssertNil(broken.feedback)
        var current = true
        let draft = TrainingSessionDraft(
            session: session(), ownerId: "owner-A", store: TrainingDraftStore(rootURL: directory), isCurrent: { current }
        )
        await draft.recordWorkoutFeedback(feedbackProposal(.ready), source: "voice") { request in
            current = false
            return self.feedbackResponse(request, action: .proceed)
        }
        XCTAssertNil(draft.feedback?.response)
        XCTAssertEqual(draft.completedCount, 0)
    }

    func testCompletionMotionBecomesImmediateWhenReduceMotionIsEnabled() {
        XCTAssertTrue(TrainingCompletionMotionPolicy.shouldAnimate(reduceMotion: false))
        XCTAssertFalse(TrainingCompletionMotionPolicy.shouldAnimate(reduceMotion: true))
    }

    func testRawEditsSurviveFileReconstructionWithoutSubmitting() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        var writeOptions: [Data.WritingOptions] = []
        let store = TrainingDraftStore(rootURL: directory) { data, url, options in
            writeOptions.append(options)
            try data.write(to: url, options: options)
        }
        let original = model(store)
        original.update(exercise, setNumber: 1) { $0.repsText = "13"; $0.loadText = "22,5"; $0.rir = 4 }
        original.update(exercise, setNumber: 2) { $0.repsText = ""; $0.loadText = "22,,5"; $0.rir = 0 }
        let restored = model(TrainingDraftStore(rootURL: directory))
        XCTAssertEqual(restored.row(for: exercise, setNumber: 1).repsText, "13")
        XCTAssertEqual(restored.row(for: exercise, setNumber: 1).loadText, "22,5")
        XCTAssertEqual(restored.row(for: exercise, setNumber: 1).rir, 4)
        XCTAssertEqual(restored.row(for: exercise, setNumber: 2).repsText, "")
        XCTAssertEqual(restored.row(for: exercise, setNumber: 2).loadText, "22,,5")
        XCTAssertEqual(restored.row(for: exercise, setNumber: 2).rir, 0)
        XCTAssertTrue(restored.loggedSets.isEmpty)
        XCTAssertTrue(restored.rows.values.allSatisfy { $0.pendingRequest == nil })
        let resources = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(resources.isExcludedFromBackup, true)
        XCTAssertEqual(writeOptions.count, 2)
        XCTAssertTrue(writeOptions.allSatisfy { $0.contains(.atomic) })
        XCTAssertTrue(writeOptions.allSatisfy { $0.contains(.completeFileProtectionUntilFirstUserAuthentication) })
        #if !targetEnvironment(simulator)
        // Simulator storage does not implement the device file-protection attribute.
        let owner = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: owner, includingPropertiesForKeys: nil).first)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        #endif
    }

    func testExplicitBlankAndZeroAreDistinctFromUntouchedEngineLoad() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let original = model(store)
        XCTAssertEqual(original.row(for: exercise, setNumber: 1).loadText, "60")
        original.update(exercise, setNumber: 1) { $0.loadText = "" }
        original.update(exercise, setNumber: 2) { $0.loadText = "0" }
        let restored = model(TrainingDraftStore(rootURL: directory))
        XCTAssertEqual(restored.row(for: exercise, setNumber: 1).loadText, "")
        XCTAssertEqual(restored.row(for: exercise, setNumber: 2).loadText, "0")
        XCTAssertEqual(model(store, owner: "owner-B").row(for: exercise, setNumber: 1).loadText, "60")
    }

    func testResponseLossRelaunchAndManualRetryKeepExactAttemptAndOneLogicalSet() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let original = model(store)
        original.update(exercise, setNumber: 1) { $0.repsText = "13"; $0.loadText = "22,5"; $0.rir = 4 }
        var attempts: [TrainingSetLogRequest] = []
        var serverRows: [String: TrainingSetLogRequest] = [:]
        await original.save(exercise, setNumber: 1) { request in
            let pending = try store.load(ownerId: "owner-A", sessionId: "fixture-session")["fixture_press-1"]
            XCTAssertEqual(pending?.pendingRequest, request)
            attempts.append(request)
            serverRows["fixture_press-1"] = request
            throw URLError(.networkConnectionLost)
        }
        XCTAssertTrue(original.loggedSets.isEmpty)
        XCTAssertNotNil(original.errorMessage)
        let restored = model(TrainingDraftStore(rootURL: directory))
        restored.update(exercise, setNumber: 1) { $0.repsText = "99"; $0.loadText = "35" }
        XCTAssertEqual(restored.row(for: exercise, setNumber: 1).loadText, "22,5", "Attempted values stay immutable until ACK")
        XCTAssertEqual(attempts.count, 1, "Reconstruction must not send automatically")
        await restored.save(exercise, setNumber: 1) { request in
            attempts.append(request)
            XCTAssertEqual(serverRows["fixture_press-1"], request, "Completed sessions permit exact replay only")
            serverRows["fixture_press-1"] = request
        }
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0], attempts[1])
        XCTAssertEqual(serverRows.count, 1)
        XCTAssertEqual(restored.loggedSets.count, 1)
        XCTAssertTrue(try store.load(ownerId: "owner-A", sessionId: "fixture-session").isEmpty)
        var extraSends = 0
        await restored.save(exercise, setNumber: 1) { _ in extraSends += 1 }
        XCTAssertEqual(extraSends, 0)
    }

    func testFailedLocalJournalWritePreventsTransport() async {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory) { _, _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        let draft = model(store)
        var sends = 0
        await draft.save(exercise, setNumber: 1) { _ in sends += 1 }
        XCTAssertEqual(sends, 0)
        XCTAssertTrue(draft.loggedSets.isEmpty)
        XCTAssertNotNil(draft.errorMessage)
    }

    func testCorruptJournalIsPreservedAndCannotSubmit() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        model(store).update(exercise, setNumber: 1) { $0.loadText = "22,5" }
        let owner = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: owner, includingPropertiesForKeys: nil).first)
        let corrupt = Data("invalid-journal".utf8)
        try corrupt.write(to: file, options: .atomic)
        let draft = model(store)
        XCTAssertNotNil(draft.errorMessage)
        var sends = 0
        await draft.save(exercise, setNumber: 1) { _ in sends += 1 }
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testInvalidInputNeverBecomesPendingOrSends() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let draft = model(store)
        draft.update(exercise, setNumber: 1) { $0.loadText = "501" }
        var sends = 0
        await draft.save(exercise, setNumber: 1) { _ in sends += 1 }
        XCTAssertEqual(sends, 0)
        XCTAssertNil(try store.load(ownerId: "owner-A", sessionId: "fixture-session")["fixture_press-1"]?.pendingRequest)
    }

    func testAcknowledgementCannotRemoveNewerRevisionOrOtherOwner() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let draft = model(store)
        model(store, owner: "owner-B").update(exercise, setNumber: 1) { $0.loadText = "80" }
        await draft.save(exercise, setNumber: 1) { _ in
            var newer = try XCTUnwrap(store.load(ownerId: "owner-A", sessionId: "fixture-session")["fixture_press-1"])
            newer.revision = UUID()
            newer.pendingRequest = nil
            newer.loadText = "75"
            try store.put(newer, ownerId: "owner-A", sessionId: "fixture-session")
        }
        XCTAssertTrue(draft.loggedSets.isEmpty)
        XCTAssertEqual(try store.load(ownerId: "owner-A", sessionId: "fixture-session")["fixture_press-1"]?.loadText, "75")
        XCTAssertEqual(try store.load(ownerId: "owner-B", sessionId: "fixture-session")["fixture_press-1"]?.loadText, "80")
    }

    func testDifferentNextSessionRetainsOldPendingWithoutReplayingOrRetargeting() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        var sends = 0
        await model(store).save(exercise, setNumber: 1) { _ in sends += 1; throw URLError(.networkConnectionLost) }
        let next = TrainingSessionDraft(
            session: session(id: "next-session"), ownerId: "owner-A", store: store, isCurrent: { true }
        )
        XCTAssertTrue(next.loggedSets.isEmpty)
        XCTAssertTrue(next.rows.isEmpty)
        XCTAssertEqual(sends, 1)
        let oldAttempt = try store.load(ownerId: "owner-A", sessionId: "fixture-session")["fixture_press-1"]?.pendingRequest
        XCTAssertEqual(oldAttempt?.sessionId, "fixture-session")
    }

    func testAuthoritativeSavedSetWinsAndUnknownPrescriptionRowsDoNotRestore() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        model(store).update(exercise, setNumber: 1) { $0.loadText = "22,5" }
        let unknown = TrainingSetDraft(
            exerciseId: "obsolete", setNumber: 1, repsText: "10", loadText: "35", rir: 3
        )
        try store.put(unknown, ownerId: "owner-A", sessionId: "fixture-session")
        let saved = TrainingSavedSet(
            sessionId: "fixture-session",
            exerciseId: exercise.id,
            setNumber: 1,
            reps: 12,
            loadKg: 45,
            rir: 2
        )
        let restored = TrainingSessionDraft(
            session: session(saved: [saved]), ownerId: "owner-A", store: store, isCurrent: { true }
        )
        XCTAssertEqual(restored.row(for: exercise, setNumber: 1).loadText, "45")
        XCTAssertEqual(restored.loggedSets["fixture_press-1"], saved)
        XCTAssertTrue(restored.rows.isEmpty)
        XCTAssertNil(try store.load(ownerId: "owner-A", sessionId: "fixture-session")["fixture_press-1"])
        let remaining = try store.load(ownerId: "owner-A", sessionId: "fixture-session")
        XCTAssertNotNil(remaining["obsolete-1"], "Unresolved rows are not silently deleted")
    }

    func testOwnerPurgePreservesOtherAccountAndIsRepeatable() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        model(store).update(exercise, setNumber: 1) { $0.loadText = "22,5" }
        model(store, owner: "owner-B").update(exercise, setNumber: 1) { $0.loadText = "80" }
        try store.purge(ownerId: "owner-A")
        try store.purge(ownerId: "owner-A")
        XCTAssertTrue(try store.load(ownerId: "owner-A", sessionId: "fixture-session").isEmpty)
        XCTAssertEqual(try store.load(ownerId: "owner-B", sessionId: "fixture-session")["fixture_press-1"]?.loadText, "80")
    }

    func testStalePrepareCannotOverwriteNewerDraftIncludingInitiallyAbsentRow() async throws {
        for initiallyAbsent in [false, true] {
            let directory = root()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = TrainingDraftStore(rootURL: directory)
            if !initiallyAbsent { model(store).update(exercise, setNumber: 1) { $0.loadText = "22,5" } }
            let stale = model(store)
            let newer = model(store)
            newer.update(exercise, setNumber: 1) { $0.loadText = "75" }
            let before = try store.load(ownerId: "owner-A", sessionId: "fixture-session")
            var sends = 0
            await stale.save(exercise, setNumber: 1) { _ in sends += 1 }
            XCTAssertEqual(sends, 0)
            XCTAssertEqual(try store.load(ownerId: "owner-A", sessionId: "fixture-session"), before)
            XCTAssertNotNil(stale.errorMessage)
            XCTAssertTrue(stale.loggedSets.isEmpty)
        }
    }

    func testStaleControllerCannotEditAwayAnotherControllersImmutableAttempt() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        model(store).update(exercise, setNumber: 1) { $0.loadText = "22,5" }
        let saving = model(store)
        let stale = model(store)
        await saving.save(exercise, setNumber: 1) { _ in throw URLError(.networkConnectionLost) }
        let pending = try store.load(ownerId: "owner-A", sessionId: "fixture-session")
        stale.update(exercise, setNumber: 1) { $0.loadText = "75" }
        XCTAssertEqual(try store.load(ownerId: "owner-A", sessionId: "fixture-session"), pending)
        XCTAssertEqual(stale.row(for: exercise, setNumber: 1).loadText, "22,5")
        XCTAssertNotNil(stale.errorMessage)
        var sends = 0
        await stale.save(exercise, setNumber: 1) { _ in sends += 1 }
        XCTAssertEqual(sends, 0)
    }

    func testCorruptJournalDoesNotHideValidServerAcknowledgement() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        model(store).update(exercise, setNumber: 1) { $0.loadText = "22,5" }
        let owner = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: owner, includingPropertiesForKeys: nil).first)
        let corrupt = Data("invalid-journal".utf8)
        try corrupt.write(to: file, options: .atomic)
        let saved = TrainingSavedSet(
            sessionId: "fixture-session", exerciseId: exercise.id, setNumber: 1, reps: 12, loadKg: 45, rir: 2
        )
        let restored = TrainingSessionDraft(
            session: session(saved: [saved]), ownerId: "owner-A", store: store, isCurrent: { true }
        )
        XCTAssertEqual(restored.loggedSets["fixture_press-1"], saved)
        XCTAssertEqual(restored.row(for: exercise, setNumber: 1).loadText, "45")
        XCTAssertNotNil(restored.errorMessage)
        var sends = 0
        await restored.save(exercise, setNumber: 1) { _ in sends += 1 }
        await restored.save(exercise, setNumber: 2) { _ in sends += 1 }
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testCleanupWriteFailureCannotHideLaterServerAcknowledgements() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let draft = model(store)
        draft.update(exercise, setNumber: 1) { $0.loadText = "22,5" }
        draft.update(exercise, setNumber: 2) { $0.loadText = "35" }
        let before = try store.load(ownerId: "owner-A", sessionId: "fixture-session")
        let saved = (1...2).map { number in
            TrainingSavedSet(
                sessionId: "fixture-session",
                exerciseId: exercise.id,
                setNumber: number,
                reps: 12,
                loadKg: 45,
                rir: 2
            )
        }
        var cleanupWrites = 0
        let failing = TrainingDraftStore(rootURL: directory) { _, _, _ in
            cleanupWrites += 1
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let restored = TrainingSessionDraft(
            session: session(saved: saved), ownerId: "owner-A", store: failing, isCurrent: { true }
        )
        XCTAssertEqual(restored.loggedSets.count, 2)
        XCTAssertEqual(restored.row(for: exercise, setNumber: 1).loadText, "45")
        XCTAssertEqual(restored.row(for: exercise, setNumber: 2).loadText, "45")
        XCTAssertEqual(cleanupWrites, 2, "A failed cleanup must not interrupt the remaining acknowledgements")
        XCTAssertEqual(try store.load(ownerId: "owner-A", sessionId: "fixture-session"), before)
        XCTAssertNotNil(restored.errorMessage)
    }

    func testRestoredMatchingPendingAcknowledgementClearsAttemptButDifferentValuesRetainIt() async throws {
        for matches in [true, false] {
            let directory = root()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = TrainingDraftStore(rootURL: directory)
            let draft = model(store)
            draft.update(exercise, setNumber: 1) { $0.loadText = "22,5" }
            await draft.save(exercise, setNumber: 1) { _ in throw URLError(.networkConnectionLost) }
            let before = try store.load(ownerId: "owner-A", sessionId: "fixture-session")
            let saved = TrainingSavedSet(
                sessionId: "fixture-session", exerciseId: exercise.id, setNumber: 1, reps: 10,
                loadKg: matches ? 22.5 : 75, rir: 3
            )
            let restored = TrainingSessionDraft(
                session: session(saved: [saved]), ownerId: "owner-A", store: store, isCurrent: { true }
            )
            XCTAssertEqual(restored.loggedSets["fixture_press-1"], saved)
            let after = try store.load(ownerId: "owner-A", sessionId: "fixture-session")
            if matches { XCTAssertTrue(after.isEmpty) } else {
                XCTAssertEqual(after, before, "A different payload does not acknowledge the immutable attempted values")
                XCTAssertNotNil(restored.errorMessage)
            }
        }
    }

    func testAccountSwitchDuringTokenLookupPreventsTransport() async {
        var current = "owner-A"
        var sends = 0
        do {
            try await TrainingOwnedRequest.perform(
                isCurrent: { current == "owner-A" },
                getToken: {
                    current = "owner-B"
                    return "fixture-B-token"
                },
                send: { _ in sends += 1 }
            )
            XCTFail("Old owner must not use the new owner's token")
        } catch { XCTAssertEqual(error as? TrainingServiceError, .authenticationExpired) }
        XCTAssertEqual(sends, 0)
    }

    func testReturningAcknowledgementAfterABAOrCancellationKeepsPendingAttempt() async throws {
        for interruption in ["owner-B", "ABA", "cancelled"] {
            let directory = root()
            defer { try? FileManager.default.removeItem(at: directory) }
            let owner = AuthManager.ProfileSessionOwnership(subject: "owner-A", generation: 1)
            var current = owner
            let store = TrainingDraftStore(rootURL: directory)
            let draft = TrainingSessionDraft(session: session(), ownerId: owner.subject, store: store, isCurrent: {
                current == owner && !Task.isCancelled
            })
            let started = expectation(description: "Synthetic request held")
            let response = TrainingHeldResponse()
            var sends = 0
            let operation = Task {
                await draft.save(exercise, setNumber: 1) { _ in
                    sends += 1
                    started.fulfill()
                    await response.wait()
                }
            }
            await fulfillment(of: [started], timeout: 3)
            await draft.save(exercise, setNumber: 1) { _ in sends += 1 }
            XCTAssertEqual(sends, 1, "Repeated taps must not send while the first acknowledgement is held")
            if interruption == "cancelled" { operation.cancel() } else {
                current = AuthManager.ProfileSessionOwnership(subject: "owner-B", generation: 2)
                if interruption == "ABA" {
                    current = AuthManager.ProfileSessionOwnership(subject: "owner-A", generation: 3)
                }
            }
            response.release()
            await operation.value
            XCTAssertTrue(draft.loggedSets.isEmpty)
            XCTAssertNotNil(try store.load(ownerId: "owner-A", sessionId: "fixture-session")["fixture_press-1"]?.pendingRequest)
        }
    }

    func testValidatedTokenRotationWithinSameOwnershipAdmitsAcknowledgement() async throws {
        let owner = AuthManager.ProfileSessionOwnership(subject: "owner-A", generation: 1)
        var current = owner
        var token = "fixture-old-token"
        var sentToken: String?
        try await TrainingOwnedRequest.perform(
            isCurrent: { current == owner },
            getToken: {
                token = "fixture-rotated-token"
                current = owner
                return token
            },
            send: { sentToken = $0 }
        )
        XCTAssertEqual(sentToken, "fixture-rotated-token")
    }

    func testNowAndUpNextAdvanceOnlyAfterDurableAcknowledgementAndResumeWithoutReplayAnimation() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let draft = model(store)
        XCTAssertEqual(draft.currentPosition?.id, "fixture_press-1")
        XCTAssertEqual(draft.upNextPosition?.id, "fixture_press-2")

        let held = TrainingHeldResponse()
        let started = expectation(description: "Save reached transport")
        let operation = Task {
            await draft.save(exercise, setNumber: 1) { _ in
                started.fulfill()
                await held.wait()
            }
        }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(draft.currentPosition?.id, "fixture_press-1", "UI must not advance before ACK")
        XCTAssertNil(draft.lastSaveReceipt)
        held.release()
        await operation.value
        XCTAssertEqual(draft.currentPosition?.id, "fixture_press-2")
        XCTAssertEqual(draft.lastSaveReceipt?.position.id, "fixture_press-1")

        let saved = try XCTUnwrap(draft.loggedSets["fixture_press-1"])
        let restored = TrainingSessionDraft(
            session: session(saved: [saved]), ownerId: "owner-A", store: store, isCurrent: { true }
        )
        XCTAssertEqual(restored.currentPosition?.id, "fixture_press-2")
        XCTAssertNil(restored.lastSaveReceipt, "Relaunch must not replay earned completion motion")
    }

    func testCorrectionKeepsIdentityAndRetriesExactAuditRequestAfterInterruption() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let original = TrainingSavedSet(
            sessionId: "fixture-session", exerciseId: exercise.id, setNumber: 1,
            reps: 10, loadKg: 60, rir: 3, revision: 0, corrections: []
        )
        let draft = TrainingSessionDraft(
            session: session(saved: [original]), ownerId: "owner-A", store: store, isCurrent: { true }
        )
        let position = try XCTUnwrap(draft.lastCompletedPosition)
        draft.beginCorrection(position)
        draft.update(exercise, setNumber: 1) { $0.repsText = "9"; $0.rir = 1 }
        var attempts: [TrainingSetCorrectionRequest] = []
        await draft.correct(position) { request in
            attempts.append(request)
            throw URLError(.networkConnectionLost)
        }
        XCTAssertEqual(draft.loggedSets[position.id], original)
        XCTAssertNotNil(draft.rows[position.id]?.pendingCorrection)

        let restored = TrainingSessionDraft(
            session: session(saved: [original]), ownerId: "owner-A", store: store, isCurrent: { true }
        )
        await restored.correct(position) { request in
            attempts.append(request)
            return TrainingSavedSet(
                sessionId: request.sessionId,
                exerciseId: request.exerciseId,
                setNumber: request.setNumber,
                reps: request.reps,
                loadKg: request.loadKg,
                rir: request.rir,
                revision: request.expectedRevision + 1,
                corrections: [
                    TrainingSetCorrectionAudit(
                        id: request.correctionId,
                        correctedAt: "2026-10-12T00:00:00.000Z",
                        previous: .init(reps: 10, loadKg: 60, rir: 3)
                    )
                ]
            )
        }
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0], attempts[1])
        XCTAssertEqual(restored.loggedSets[position.id]?.reps, 9)
        XCTAssertEqual(restored.loggedSets[position.id]?.revision, 1)
        XCTAssertTrue(try store.load(ownerId: "owner-A", sessionId: "fixture-session").isEmpty)
    }

    func testFreshLogHasNoUndoAndALaterAcknowledgementCannotEraseACorrection() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        let draft = model(store)
        var undoSends = 0
        await draft.undo { _ in
            undoSends += 1
            throw URLError(.cancelled)
        }
        XCTAssertEqual(undoSends, 0)
        XCTAssertNil(draft.undoAffordance)

        draft.update(exercise, setNumber: 1) { $0.repsText = "12"; $0.loadText = "60"; $0.rir = 2 }
        let audited = TrainingSavedSet(
            sessionId: "fixture-session", exerciseId: exercise.id, setNumber: 1,
            reps: 12, loadKg: 60, rir: 2, revision: 2,
            corrections: [
                TrainingSetCorrectionAudit(
                    id: UUID().uuidString,
                    correctedAt: "2026-10-12T00:00:00.000Z",
                    previous: .init(reps: 10, loadKg: 60, rir: 3)
                )
            ]
        )
        await draft.saveAcknowledged(exercise, setNumber: 1) { request in
            TrainingSavedSet(
                sessionId: request.sessionId, exerciseId: request.exerciseId, setNumber: request.setNumber,
                reps: request.reps, loadKg: request.loadKg, rir: request.rir,
                revision: audited.revision, corrections: audited.corrections
            )
        }
        XCTAssertEqual(draft.loggedSets["fixture_press-1"]?.revision, 2)
        XCTAssertEqual(draft.loggedSets["fixture_press-1"]?.corrections?.count, 1)

        let again = model(TrainingDraftStore(rootURL: directory))
        again.update(exercise, setNumber: 2) { $0.repsText = "8"; $0.loadText = "60"; $0.rir = 1 }
        let corrected = TrainingSavedSet(
            sessionId: "fixture-session", exerciseId: exercise.id, setNumber: 2,
            reps: 10, loadKg: 60, rir: 1, revision: 2, corrections: audited.corrections
        )
        await again.saveAcknowledged(exercise, setNumber: 2) { request in
            again.replaceSession(self.session(saved: [corrected]))
            return TrainingSavedSet(
                sessionId: request.sessionId, exerciseId: request.exerciseId, setNumber: request.setNumber,
                reps: request.reps, loadKg: request.loadKg, rir: request.rir, revision: 0, corrections: []
            )
        }
        XCTAssertEqual(again.loggedSets["fixture_press-2"]?.revision, 2)
        XCTAssertEqual(again.loggedSets["fixture_press-2"]?.reps, 10)
    }

    func testUndoReceiptSurvivesRelaunchUntilExpiryAndRetriesOneId() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingDraftStore(rootURL: directory)
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let original = TrainingSavedSet(
            sessionId: "fixture-session", exerciseId: exercise.id, setNumber: 1,
            reps: 12, loadKg: 60, rir: 2, revision: 0, corrections: []
        )
        let draft = TrainingSessionDraft(
            session: session(saved: [original]), ownerId: "owner-A", store: store,
            isCurrent: { true }, now: { clock }
        )
        let position = try XCTUnwrap(draft.lastCompletedPosition)
        draft.beginCorrection(position)
        draft.update(exercise, setNumber: 1) { $0.repsText = "10" }
        await draft.correct(position) { request in
            TrainingSavedSet(
                sessionId: request.sessionId, exerciseId: request.exerciseId, setNumber: request.setNumber,
                reps: request.reps, loadKg: request.loadKg, rir: request.rir,
                revision: request.expectedRevision + 1,
                corrections: [
                    TrainingSetCorrectionAudit(
                        id: request.correctionId,
                        correctedAt: "2026-10-12T00:00:00.000Z",
                        previous: .init(reps: 12, loadKg: 60, rir: 2)
                    )
                ]
            )
        }
        let corrected = try XCTUnwrap(draft.loggedSets[position.id])
        let receipt = try XCTUnwrap(draft.undoAffordance)
        XCTAssertEqual(receipt.reps, 12)
        XCTAssertEqual(receipt.expectedRevision, 1)
        XCTAssertFalse(receipt.submitted)

        clock = clock.addingTimeInterval(31)
        let hidden = TrainingSessionDraft(
            session: session(saved: [corrected]), ownerId: "owner-A", store: store,
            isCurrent: { true }, now: { clock }
        )
        XCTAssertNil(hidden.undoAffordance)
        var hiddenSends = 0
        await hidden.undo { _ in
            hiddenSends += 1
            throw URLError(.cancelled)
        }
        XCTAssertEqual(hiddenSends, 0)
        clock = clock.addingTimeInterval(-31)

        let reloaded = TrainingSessionDraft(
            session: session(saved: [corrected]), ownerId: "owner-A", store: store,
            isCurrent: { true }, now: { clock }
        )
        XCTAssertEqual(reloaded.undoAffordance?.id, receipt.id)
        XCTAssertNil(
            TrainingSessionDraft(
                session: session(saved: [corrected]), ownerId: "owner-B", store: store,
                isCurrent: { true }, now: { clock }
            ).undoAffordance
        )

        var ids: [String] = []
        await reloaded.undo { request in
            ids.append(request.undoId)
            throw URLError(.networkConnectionLost)
        }
        XCTAssertEqual(ids, [receipt.id])
        XCTAssertEqual(reloaded.undoAffordance?.submitted, true)
        clock = clock.addingTimeInterval(31)
        let expired = TrainingSessionDraft(
            session: session(saved: [corrected]), ownerId: "owner-A", store: store,
            isCurrent: { true }, now: { clock }
        )
        XCTAssertEqual(expired.undoAffordance?.id, receipt.id, "A queued undo still retries after the fuse")
        await expired.undo { request in
            ids.append(request.undoId)
            return TrainingSavedSet(
                sessionId: request.sessionId, exerciseId: request.exerciseId, setNumber: request.setNumber,
                reps: 12, loadKg: 60, rir: 2, revision: request.expectedRevision + 1,
                corrections: corrected.corrections! + [
                    TrainingSetCorrectionAudit(
                        id: request.undoId,
                        correctedAt: "2026-10-12T00:00:01.000Z",
                        previous: .init(reps: 10, loadKg: 60, rir: 2)
                    )
                ]
            )
        }
        XCTAssertEqual(ids, [receipt.id, receipt.id])
        XCTAssertEqual(expired.loggedSets[position.id]?.reps, 12)
        XCTAssertEqual(expired.loggedSets[position.id]?.revision, 2)
        XCTAssertNil(expired.undoAffordance)
        var extra = 0
        await expired.undo { _ in
            extra += 1
            throw URLError(.cancelled)
        }
        XCTAssertEqual(extra, 0)

        let undone = try XCTUnwrap(expired.loggedSets[position.id])
        let unsent = TrainingSessionDraft(
            session: session(saved: [undone]), ownerId: "owner-A", store: store,
            isCurrent: { true }, now: { clock }
        )
        XCTAssertNil(unsent.undoAffordance, "A successful undo does not leave a second compact receipt")
    }
}

@MainActor
private final class TrainingCycleServiceFixture: TrainingCycleServicing {
    var requests: [TrainingCycleProposalRequest] = []
    var decisions: [TrainingCycleDecisionRequest] = []
    var failure: Error?
    var hold: TrainingHeldResponse?

    func cycleContext(accessToken: String) async throws -> TrainingCycleContext {
        try JSONDecoder().decode(TrainingCycleContext.self, from: Data("""
        {"version":1,"generation":3,"setup":null,"cycle":null,"reuseOptions":[]}
        """.utf8))
    }

    func proposeCycle(accessToken: String, request: TrainingCycleProposalRequest) async throws -> TrainingCycleDraft {
        requests.append(request)
        if let hold { await hold.wait() }
        if let failure { throw failure }
        return try JSONDecoder().decode(TrainingCycleDraft.self, from: Data("""
        {"id":"draft","reason":"Review length","assumptions":[],"schedule":[],"plan":{"sessions":[]}}
        """.utf8))
    }

    func decideCycle(accessToken: String, request: TrainingCycleDecisionRequest) async throws {
        decisions.append(request)
        if let failure { throw failure }
    }
}

extension TrainingSessionDraftTests {
    func testCycleDraftRequiresExplicitApplyAndRetainsRetryIdentity() async throws {
        let service = TrainingCycleServiceFixture()
        let model = TrainingCycleReviewModel(service: service, isCurrent: { true }, accessToken: { "fixture" })
        await model.load()
        let intent = TrainingCycleIntent(kind: "initial_enrollment", weekCount: 6)
        service.failure = URLError(.networkConnectionLost)
        await model.propose(intent: intent)
        XCTAssertNil(model.draft)
        XCTAssertTrue(service.decisions.isEmpty)
        service.failure = nil
        await model.propose(intent: intent)
        XCTAssertEqual(service.requests[0].requestId, service.requests[1].requestId)
        XCTAssertNotNil(model.draft)
        XCTAssertTrue(service.decisions.isEmpty)
        service.failure = URLError(.networkConnectionLost)
        let failed = await model.decide("apply")
        XCTAssertFalse(failed)
        XCTAssertNotNil(model.draft)
        service.failure = nil
        let applied = await model.decide("apply")
        XCTAssertTrue(applied)
        XCTAssertEqual(service.decisions[0].requestId, service.decisions[1].requestId)
        XCTAssertNil(model.draft)
    }

    func testHeldCycleDraftCannotCrossAccountBoundary() async {
        let service = TrainingCycleServiceFixture()
        service.hold = TrainingHeldResponse()
        var ownsAccount = true
        let model = TrainingCycleReviewModel(service: service, isCurrent: { ownsAccount }, accessToken: { "fixture" })
        await model.load()
        let pending = Task { await model.propose(intent: TrainingCycleIntent(kind: "revise_cycle", weekCount: 5)) }
        while service.requests.isEmpty { await Task.yield() }
        ownsAccount = false
        service.hold?.release()
        await pending.value
        XCTAssertNil(model.context)
        XCTAssertNil(model.draft)
        XCTAssertTrue(service.decisions.isEmpty)
    }

    func testCycleApplyReceiptMustIdentifyTheReviewedDraftAndRevision() throws {
        let data = Data("""
        {"version":1,"receipt":{"proposalId":"other","requestId":"request","status":"applied",
          "decision":"apply","revisionId":"revision","setup":{"id":"program","equipment":"dumbbells","sessionsPerWeek":2}}}
        """.utf8)
        let response = try JSONDecoder().decode(TrainingCycleDecisionResponse.self, from: data)
        XCTAssertFalse(response.matches(.init(requestId: "request", proposalId: "reviewed", decision: "apply")))
        XCTAssertTrue(response.matches(.init(requestId: "request", proposalId: "other", decision: "apply")))
    }

    func testCycleIntentKeepsVariantIdentityAndReasonsWithoutAuthoringPrescriptions() throws {
        let intent = TrainingCycleIntent(
            kind: "repeat_cycle", weekCount: 5,
            keepVariants: [.init(
                fromExerciseId: "machine_chest_press", toVariantId: "smith_incline_press", reason: "Comfortable setup"
            )],
            renewPriorities: false, renewConstraints: true
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        XCTAssertEqual(object["weekCount"] as? Int, 5)
        XCTAssertEqual(object["renewPriorities"] as? Bool, false)
        let variants = try XCTUnwrap(object["keepVariants"] as? [[String: String]])
        XCTAssertEqual(variants.first?["toVariantId"], "smith_incline_press")
        XCTAssertEqual(variants.first?["reason"], "Comfortable setup")
        XCTAssertNil(object["sets"])
        XCTAssertNil(object["targetRir"])
    }
}
