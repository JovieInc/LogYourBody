import XCTest
@testable import LogYourBody

extension TrainingSessionDraftTests {
    private var sessionId: String { "11111111-1111-4111-8111-000000000001" }

    func testNativeCardsRequireBothDefaultOffPlatformGates() {
        XCTAssertFalse(TrainingNativeCardsPolicy.isEnabled { _ in false })
        XCTAssertFalse(TrainingNativeCardsPolicy.isEnabled { $0 == TrainingCoachPolicy.featureGate })
        XCTAssertTrue(TrainingNativeCardsPolicy.isEnabled { _ in true })
    }

    func testAllApprovedComponentsRoundTripWithDurableReferences() throws {
        for component in TrainingCardComponent.allCases {
            let reference = TrainingCardReference(
                component: component, objectId: sessionId, revision: 2,
                exerciseId: component == .exerciseSwap ? "cable_curl" : nil
            )
            let decoded = try JSONDecoder().decode(TrainingCardReference.self, from: JSONEncoder().encode(reference))
            XCTAssertEqual(decoded, reference)
        }
    }

    func testUnknownComponentsPropertiesVersionsIDsAndGeneratedCodeAreRejected() {
        for json in [
            #"{"version":1,"component":"WebView","objectId":"ID","revision":0}"#,
            #"{"version":2,"component":"WorkoutSessionCard","objectId":"ID","revision":0}"#,
            #"{"version":1,"component":"WorkoutSessionCard","objectId":"not-a-domain-id","revision":0}"#,
            #"{"version":1,"component":"WorkoutSessionCard","objectId":"ID","revision":-1}"#,
            #"{"version":1,"component":"WorkoutSessionCard","objectId":"ID","revision":0,"code":"run()"}"#,
            #"{"version":1,"component":"ExerciseSwapCard","objectId":"ID","revision":0}"#,
            #"{"version":1,"component":"ExerciseSwapCard","objectId":"ID","revision":0,"exerciseId":"../curl"}"#
        ] {
            let payload = json.replacingOccurrences(of: "\"ID\"", with: "\"\(sessionId)\"")
            XCTAssertThrowsError(try JSONDecoder().decode(TrainingCardReference.self, from: Data(payload.utf8)))
        }
    }

    func testUnknownActionsAndNestedCodeAreRejected() throws {
        let reference = TrainingCardReference(component: .workoutSession, objectId: sessionId, revision: 2)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reference))
        let actions: [[String: Any]] = [
            ["reference": encoded, "name": "execute"],
            ["reference": encoded, "name": "logSet", "code": "run()"],
            ["reference": encoded, "name": "apply"],
            ["reference": encoded, "name": "expand", "alternativeId": "curl"]
        ]
        for action in actions {
            let data = try JSONSerialization.data(withJSONObject: action)
            XCTAssertThrowsError(try JSONDecoder().decode(TrainingCardAction.self, from: data))
        }
    }

    func testAdmissionRejectsForeignReadOnlyStaleAndIneligibleWrites() throws {
        let reference = TrainingCardReference(
            component: .exerciseSwap, objectId: sessionId, revision: 2, exerciseId: "cable_curl"
        )
        let action = TrainingCardAction(reference: reference, name: .swap, alternativeId: "dumbbell_curl")
        for (owner, writable, revision, alternatives) in [
            (false, true, 2, Set(["dumbbell_curl"])),
            (true, false, 2, Set(["dumbbell_curl"])),
            (true, true, 3, Set(["dumbbell_curl"])),
            (true, true, 2, Set(["barbell_curl"]))
        ] {
            let current = TrainingCardReference(
                component: .exerciseSwap, objectId: sessionId, revision: revision, exerciseId: "cable_curl"
            )
            XCTAssertThrowsError(try TrainingCardAdapter.authorize(
                action, current: current, ownsSession: owner, canWrite: writable, eligibleAlternativeIds: alternatives
            ))
        }
        XCTAssertNoThrow(try TrainingCardAdapter.authorize(
            action, current: reference, ownsSession: true, canWrite: true, eligibleAlternativeIds: ["dumbbell_curl"]
        ))
    }

    func testOfflineSessionAndPendingSetSurviveStoreRecreationWithoutChangingIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrainingDraftStore(rootURL: root)
        let session = try fixtureSession()
        try store.cacheActiveSession(session, ownerId: "owner-a")
        let draft = TrainingSessionDraft(session: session, ownerId: "owner-a", store: store, isCurrent: { true })
        await draft.save(session.exercises[0], setNumber: 1) { _ in throw URLError(.notConnectedToInternet) }
        let pending = try XCTUnwrap(draft.rows["cable_curl-1"]?.pendingRequest)
        let reopenedStore = TrainingDraftStore(rootURL: root)
        let cached = try XCTUnwrap(reopenedStore.activeSession(ownerId: "owner-a"))
        XCTAssertEqual(cached, session)
        XCTAssertNil(try reopenedStore.activeSession(ownerId: "owner-b"))
        let reopened = TrainingSessionDraft(session: cached, ownerId: "owner-a", store: reopenedStore, isCurrent: { true })
        XCTAssertEqual(reopened.rows["cable_curl-1"]?.pendingRequest, pending)
        await reopened.save(cached.exercises[0], setNumber: 1) { request in XCTAssertEqual(request, pending) }
        let receipt = try XCTUnwrap(reopenedStore.activeSession(ownerId: "owner-a")?.loggedSets?.first)
        XCTAssertEqual(receipt.sessionId, session.id)
        XCTAssertEqual(receipt.exerciseId, pending.exerciseId)
        XCTAssertEqual(receipt.setNumber, 1)
        await reopened.saveAcknowledged(cached.exercises[0], setNumber: 2) { request in
            TrainingSavedSet(
                sessionId: request.sessionId, exerciseId: request.exerciseId, setNumber: request.setNumber,
                reps: request.reps, loadKg: request.loadKg, rir: request.rir, revision: 2
            )
        }
        let acknowledged = try XCTUnwrap(reopenedStore.activeSession(ownerId: "owner-a")?.loggedSets?.last)
        XCTAssertEqual(acknowledged.setNumber, 2)
        XCTAssertEqual(acknowledged.revision, 2, "Offline cards retain the acknowledged revision")
        XCTAssertEqual(try reopenedStore.activeSession(ownerId: "owner-a")?.loggedSets?.count, 2)
        XCTAssertTrue(try reopenedStore.load(ownerId: "owner-a", sessionId: session.id).isEmpty)
    }

    func testDelayedReceiptCannotReplaceNewerWorkoutAndPurgeRemovesCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrainingDraftStore(rootURL: root)
        let original = try fixtureSession()
        let newer = try fixtureSession(id: "11111111-1111-4111-8111-000000000002")
        try store.cacheActiveSession(newer, ownerId: "owner-a")
        try store.updateCachedSession(original, ownerId: "owner-a")
        XCTAssertEqual(try store.activeSession(ownerId: "owner-a"), newer)
        try store.purge(ownerId: "owner-a")
        XCTAssertNil(try store.activeSession(ownerId: "owner-a"))
    }

    func testDelayedSnapshotCannotDropOtherSetsOrDowngradeACorrection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrainingDraftStore(rootURL: root)
        var current = try fixtureSession()
        let corrected = TrainingSavedSet(
            sessionId: current.id, exerciseId: "cable_curl", setNumber: 1,
            reps: 10, loadKg: 12.5, rir: 3, revision: 1
        )
        let second = TrainingSavedSet(
            sessionId: current.id, exerciseId: "cable_curl", setNumber: 2,
            reps: 8, loadKg: 12.5, rir: 3, revision: 0
        )
        current.loggedSets = [corrected, second]
        try store.cacheActiveSession(current, ownerId: "owner-a")
        var stale = try fixtureSession()
        stale.loggedSets = [TrainingSavedSet(
            sessionId: current.id, exerciseId: "cable_curl", setNumber: 1,
            reps: 12, loadKg: 12.5, rir: 3, revision: 0
        )]
        try store.updateCachedSession(stale, ownerId: "owner-a")
        let cached = try XCTUnwrap(store.activeSession(ownerId: "owner-a"))
        XCTAssertEqual(cached.loggedSets, [corrected, second])
        var revised = current
        revised.executionRevision = 1
        try store.cacheActiveSession(revised, ownerId: "owner-a")
        try store.updateCachedSession(current, ownerId: "owner-a")
        XCTAssertEqual(try store.activeSession(ownerId: "owner-a")?.executionRevision, 1)
    }

    func testFailedSnapshotWriteCannotClaimDurableSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrainingDraftStore(rootURL: root, writeData: { _, _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try store.cacheActiveSession(fixtureSession(), ownerId: "owner-a"))
        XCTAssertNil(try store.activeSession(ownerId: "owner-a"))
    }

    private func fixtureSession(id: String? = nil) throws -> TrainingSession {
        try JSONDecoder().decode(TrainingSession.self, from: Data("""
        {"id":"\(id ?? sessionId)","week":1,"slot":0,"pattern":"A","title":"Biceps priority",
        "safetyStop":false,"evidenceIds":[],"executionRevision":0,"exercises":[{
        "id":"cable_curl","name":"Cable curl","primaryMuscle":"biceps","muscleContribution":{"biceps":1},
        "sets":2,"repRange":{"min":8,"max":12},"targetReps":8,"targetRir":3,
        "progression":"hold","evidenceIds":[],"substitutions":[]}]}
        """.utf8))
    }
}
