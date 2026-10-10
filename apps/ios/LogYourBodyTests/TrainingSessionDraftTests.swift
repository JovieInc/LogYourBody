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
        let unknown = TrainingSetDraft(exerciseId: "obsolete", setNumber: 1, repsText: "10", loadText: "35", rir: 3)
        try store.put(unknown, ownerId: "owner-A", sessionId: "fixture-session")
        let saved = TrainingSavedSet(sessionId: "fixture-session", exerciseId: exercise.id, setNumber: 1, reps: 12, loadKg: 45, rir: 2)
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
            TrainingSavedSet(sessionId: "fixture-session", exerciseId: exercise.id, setNumber: number, reps: 12, loadKg: 45, rir: 2)
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
}
