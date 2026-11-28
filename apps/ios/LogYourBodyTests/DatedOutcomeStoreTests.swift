import CoreData
import XCTest
@testable import LogYourBody

@MainActor
final class DatedOutcomeStoreTests: DatedOutcomeStoreFixtureCase {
    func testPresentationSaveAndRelaunchRestoreOwnerScopedContext() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("timeline-\(UUID()).sqlite")
        defer { removeStore(url) }
        let first = try coordinator(url: url)
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = first
        try await store(background).saveForPresentation(value, isCurrent: { true })
        try close(first)
        let reopened = try coordinator(url: url)
        defer { try? close(reopened) }
        let restored = store(context(reopened))
        let loaded = try await restored.loadForPresentation(isCurrent: { true })
        XCTAssertEqual(loaded?.value, value)
        owner = "owner-b"
        let other = try await restored.loadForPresentation(isCurrent: { true })
        XCTAssertNil(other)
        XCTAssertTrue(try restored.pendingEdits().isEmpty)
    }

    func testReconciliationKeepsBaselineOnlyForComparableMetric() async throws {
        let journal = store(context(try coordinator()))
        let edit = try XCTUnwrap(journal.save(value))
        let baseline = DatedOutcome.PlanBaseline(date: Date(), metric: value.outcome.metric, value: 22)
        try await journal.retainPlanBaselineForPresentation(baseline, revision: edit.requestId, isCurrent: { true })
        var revised = value
        revised.outcomeDate = "2028-01-01"
        let remote = DatedOutcomeSnapshot(revision: UUID(), value: revised)
        try await journal.acceptRemoteForPresentation(remote, expectedRevision: edit.requestId, isCurrent: { true })
        XCTAssertEqual(try journal.load()?.value, revised)
        XCTAssertEqual(try journal.load()?.revision, remote.revision)
        XCTAssertEqual(try journal.load()?.planBaseline, baseline)
        XCTAssertTrue(try journal.pendingEdits().isEmpty)
        revised.outcome.metric = .weightKg
        revised.outcome.targetValue = 76
        try await journal.acceptRemoteForPresentation(
            .init(revision: UUID(), value: revised), expectedRevision: remote.revision, isCurrent: { true }
        )
        XCTAssertNil(try journal.load()?.planBaseline, "A different metric cannot reuse the previous baseline")
        XCTAssertTrue(try journal.pendingEdits().isEmpty)
        XCTAssertEqual(emitted, [edit], "Reconciliation cannot enqueue a new user edit")
    }

    func testEditorSaveIsAtomicAndUnchangedSaveCreatesNoRequest() async throws {
        let journal = store(context(try coordinator()))
        let editor = DatedOutcomeEditorModel(store: journal, isCurrent: { true })
        await editor.load()
        let saved = await editor.save(value)
        XCTAssertTrue(saved)
        let reopened = DatedOutcomeEditorModel(store: journal, isCurrent: { true })
        await reopened.load()
        XCTAssertEqual(reopened.snapshot?.value, value)
        XCTAssertTrue(reopened.hasPending)
        let unchanged = await reopened.save(value)
        XCTAssertTrue(unchanged)
        XCTAssertEqual(emitted.count, 1)
        var edit = value
        edit.outcomeDate = "2027-07-01"
        edit.constraints.travel = []
        let changed = await reopened.save(edit)
        XCTAssertTrue(changed)
        XCTAssertEqual(try journal.pendingEdits().count, 2)
        let count = try await journal.pendingCountForPresentation(isCurrent: { true })
        XCTAssertEqual(count, 2)
        XCTAssertEqual(try journal.load()?.value, edit)
    }

    func testRawEditorDraftPreservesConstraintsAndRejectsInvalidTextWithoutFallback() throws {
        var draft = DatedOutcomeEditorDraft(
            metric: value.outcome.metric, targetText: "20", dateText: value.outcomeDate,
            constraints: value.constraints, sessionsText: "3", minutesText: "45"
        )
        XCTAssertEqual(draft.resolve(), value)
        draft.dateText = "2027-02-30"
        XCTAssertEqual(draft.resolve().outcomeDate, "2027-02-30")
        XCTAssertThrowsError(try draft.resolve().validate())
        draft.dateText = value.outcomeDate
        draft.sessionsText = "invalid"
        XCTAssertThrowsError(try draft.resolve().validate())
        draft.sessionsText = ""
        XCTAssertNil(draft.resolve().constraints.availability.sessionsPerWeek)
        XCTAssertEqual(draft.resolve().constraints.travel, value.constraints.travel)
        draft.targetText = "invalid"
        XCTAssertThrowsError(try draft.resolve().validate())
    }

    func testEditorInvalidAndFailedSaveKeepOpeningRevisionForRetry() async throws {
        let failing = FailingOutcomeContext(concurrencyType: .mainQueueConcurrencyType)
        failing.persistentStoreCoordinator = try coordinator()
        let journal = store(failing)
        try journal.save(value)
        let editor = DatedOutcomeEditorModel(store: journal, isCurrent: { true })
        await editor.load()
        let revision = editor.snapshot?.revision
        var draft = value
        draft.outcomeDate = "2027-02-30"
        let invalid = await editor.save(draft)
        XCTAssertFalse(invalid)
        XCTAssertNotNil(editor.errorText)
        draft.outcomeDate = "2027-05-01"
        failing.failSave = true
        let failed = await editor.save(draft)
        XCTAssertFalse(failed)
        XCTAssertEqual(editor.snapshot?.revision, revision)
        XCTAssertEqual(emitted.count, 1)
        failing.failSave = false
        let retried = await editor.save(draft)
        XCTAssertTrue(retried)
        XCTAssertEqual(try journal.load()?.value, draft)
        XCTAssertEqual(emitted.count, 2)
    }

    func testStaleEditorCannotReplaceNewerValueOrDuplicateItsPendingRequest() async throws {
        let journal = store(context(try coordinator()))
        try journal.save(value)
        let editor = DatedOutcomeEditorModel(store: journal, isCurrent: { true })
        await editor.load()
        var newer = value
        newer.outcomeDate = "2027-08-01"
        let pending = try XCTUnwrap(journal.save(newer))
        await editor.load()
        XCTAssertEqual(editor.snapshot?.value, value, "A reappearing sheet keeps its opening revision")
        let saved = await editor.save(value)
        XCTAssertFalse(saved)
        XCTAssertTrue(editor.hasLocalConflict)
        XCTAssertEqual(editor.snapshot?.value, value, "The opening value must not be silently replaced")
        await editor.reviewAccountValue { XCTFail("Local reconciliation needs no network"); return nil }
        let reconciled = await editor.useAccountValue()
        XCTAssertTrue(reconciled)
        XCTAssertEqual(try journal.load()?.value, newer)
        XCTAssertEqual(try journal.pendingEdits().last, pending)
        XCTAssertEqual(emitted.count, 2)
    }

    func testConflictRetryKeepsIdentityAndExplicitReconciliationEmitsNoRequest() async throws {
        let journal = store(context(try coordinator()))
        let first = try XCTUnwrap(journal.save(value))
        let remote = OutcomeRemoteFixture()
        remote.conflicts = true
        for _ in 0..<2 {
            do {
                try await journal.synchronize(remote: remote, token: "synthetic", isCurrent: { true })
                XCTFail("A conflict must remain pending")
            } catch { }
        }
        XCTAssertEqual(journal.syncIssue, .conflict)
        XCTAssertEqual(remote.requests, [first, first])
        let editor = DatedOutcomeEditorModel(store: journal, isCurrent: { true })
        await editor.load()
        var draft = value
        draft.outcomeDate = "2028-01-01"
        let blocked = await editor.save(draft)
        XCTAssertFalse(blocked, "Saving cannot enqueue more writes onto a conflicting revision")
        let account = DatedOutcomeSnapshot(revision: UUID(), value: draft)
        await editor.reviewAccountValue { account }
        XCTAssertEqual(try journal.load()?.value, value, "Review alone cannot discard the user's input")
        let reconciled = await editor.useAccountValue()
        XCTAssertTrue(reconciled)
        XCTAssertEqual(try journal.load(), account)
        XCTAssertTrue(try journal.pendingEdits().isEmpty)
        XCTAssertEqual(emitted, [first])
    }

    func testEditorAndReconciliationCannotCrossAccountSessions() async throws {
        let journal = store(context(try coordinator()))
        try journal.save(value)
        var current = true
        let editor = DatedOutcomeEditorModel(store: journal, isCurrent: { current })
        await editor.load()
        await editor.reviewAccountValue { .init(revision: UUID(), value: self.value) }
        owner = "owner-b"
        current = false
        XCTAssertFalse(editor.isPresentationCurrent, "A reused sheet must hide its opening account's snapshot")
        let saved = await editor.save(value)
        let reconciled = await editor.useAccountValue()
        XCTAssertFalse(saved)
        XCTAssertFalse(reconciled)
        XCTAssertNil(try journal.load())
        XCTAssertTrue(try journal.pendingEdits().isEmpty)
        owner = "owner-a"
        XCTAssertEqual(try journal.load()?.value, value)
        XCTAssertEqual(emitted.count, 1)
    }

    func testStalePresentationCannotSaveIntoAnotherAccount() async throws {
        let journal = store(context(try coordinator()))
        owner = "owner-b"
        do {
            try await journal.saveForPresentation(value, isCurrent: { false })
            XCTFail("A stale editor must be rejected before writing")
        } catch DatedOutcomeError.unauthenticated { }
        XCTAssertNil(try journal.load())
        XCTAssertTrue(try journal.pendingEdits().isEmpty)
        XCTAssertTrue(emitted.isEmpty)
    }

    func testCoachActionAndNextCheckInSurviveSQLiteReopenWithoutSyncEdit() async throws {
        try await assertCoachActionAndNextCheckInSurviveSQLiteReopenWithoutSyncEdit()
    }

    func testPlanBaselineSurvivesEditsAcknowledgementAndRelaunchWithoutWireChanges() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("baseline-\(UUID()).sqlite")
        defer { removeStore(url) }
        let first = try coordinator(url: url)
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = first
        let journal = store(background)
        var goal = value
        goal.outcome.metric = .weightKg
        goal.outcome.targetValue = 76
        let edit = try XCTUnwrap(journal.save(goal))
        let baseline = DatedOutcome.PlanBaseline(date: Date(timeIntervalSince1970: 1_793_491_200), metric: .weightKg, value: 80)
        try await journal.retainPlanBaselineForPresentation(baseline, revision: edit.requestId, isCurrent: { true })
        XCTAssertEqual(try journal.load()?.planBaseline, baseline)
        XCTAssertEqual(try journal.pendingEdits(), [edit])
        XCTAssertEqual(emitted.count, 1, "Baseline metadata is not a user edit or recompute")
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: Any])
        XCTAssertNil(wire["planBaseline"])
        goal.outcomeDate = "2027-06-01"
        let changed = try XCTUnwrap(journal.save(goal))
        try journal.acknowledge(edit, receipt: .init(revision: edit.requestId, value: edit.value))
        try journal.acknowledge(changed, receipt: .init(revision: changed.requestId, value: changed.value))
        XCTAssertEqual(try journal.load()?.planBaseline, baseline)
        try close(first)
        let reopened = try coordinator(url: url)
        defer { try? close(reopened) }
        let restored = store(context(reopened))
        XCTAssertEqual(try restored.load()?.planBaseline, baseline)
        XCTAssertEqual(try restored.load()?.value, goal)
        owner = "owner-b"
        XCTAssertNil(try restored.load())
    }

    func testBaselineCannotReplaceExistingRevisionOrCrossAccountSession() async throws {
        let journal = store(context(try coordinator()))
        let edit = try XCTUnwrap(journal.save(value))
        let baseline = DatedOutcome.PlanBaseline(date: Date(), metric: .bodyFatPercentage, value: 22)
        try await journal.retainPlanBaselineForPresentation(baseline, revision: UUID(), isCurrent: { true })
        XCTAssertNil(try journal.load()?.planBaseline)
        try await journal.retainPlanBaselineForPresentation(baseline, revision: edit.requestId, isCurrent: { true })
        var replacement = baseline
        replacement.value = 23
        try await journal.retainPlanBaselineForPresentation(replacement, revision: edit.requestId, isCurrent: { true })
        XCTAssertEqual(try journal.load()?.planBaseline, baseline)
        owner = "owner-b"
        do {
            try await journal.retainPlanBaselineForPresentation(baseline, revision: edit.requestId, isCurrent: { false })
            XCTFail("A late task cannot write into the new session")
        } catch DatedOutcomeError.unauthenticated { }
        XCTAssertNil(try journal.load())
        owner = "owner-a"
        var changed = value
        changed.outcome.metric = .ffmi
        try journal.save(changed)
        XCTAssertNil(try journal.load()?.planBaseline, "A metric edit requires its own comparable baseline")
    }

    func testPresentationReadAfterSessionChangeIsDiscarded() async throws {
        let journal = store(context(try coordinator()))
        try journal.save(value)
        var checks = 0
        do {
            _ = try await journal.loadForPresentation {
                checks += 1
                if checks > 1 { self.owner = "owner-b" }
                return checks == 1
            }
            XCTFail("A delayed read must not publish the previous account's outcome")
        } catch DatedOutcomeError.unauthenticated { }
        XCTAssertNil(try journal.load())
    }

    func testOutcomeConstraintsAndPendingRequestSurviveSQLiteReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("outcome-\(UUID()).sqlite")
        defer { removeStore(url) }
        let first = try coordinator(url: url)
        let edit = try XCTUnwrap(store(context(first)).save(value))
        try close(first)
        let reopened = try coordinator(url: url)
        defer { try? close(reopened) }
        let restored = store(context(reopened))
        XCTAssertEqual(try restored.load(), .init(revision: edit.requestId, value: value))
        XCTAssertEqual(try restored.pendingEdits(), [edit])
        XCTAssertEqual(emitted.count, 1)
    }

    func testSignOutAndAccountSwitchKeepValuesAndRequestsIsolated() throws {
        let store = store(context(try coordinator()))
        let first = try XCTUnwrap(store.save(value))
        owner = nil
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(value))
        owner = "owner-b"
        XCTAssertNil(try store.load())
        XCTAssertTrue(try store.pendingEdits().isEmpty)
        var other = value
        other.outcomeDate = "2027-06-01"
        try store.save(other)
        owner = "owner-a"
        XCTAssertEqual(try store.load()?.value, value)
        XCTAssertEqual(try store.pendingEdits(), [first])
    }

    func testEachDateOrConstraintsEditEmitsExactlyOneRecomputeAndNoOpEmitsNone() throws {
        let store = store(context(try coordinator()))
        let first = try XCTUnwrap(store.save(value))
        XCTAssertNil(try store.save(value))
        var changed = value
        changed.outcomeDate = "2027-05-01"
        let dateEdit = try XCTUnwrap(store.save(changed))
        XCTAssertEqual(dateEdit.previousRevision, first.requestId)
        changed.constraints.availability.sessionsPerWeek = 2
        changed.constraints.travel.append(.init(start: "2027-03-01", end: "2027-03-03"))
        let constraintsEdit = try XCTUnwrap(store.save(changed))
        XCTAssertEqual(constraintsEdit.previousRevision, dateEdit.requestId)
        XCTAssertNil(try store.save(changed))
        XCTAssertEqual(emitted, [first, dateEdit, constraintsEdit])
        XCTAssertEqual(try store.pendingEdits(), emitted)
        XCTAssertEqual(constraintsEdit.value.planInputs.goalDate, "2027-05-01T00:00:00Z")
        XCTAssertEqual(constraintsEdit.value.planInputs.sessionsPerWeek, 2)
    }

    func testSimultaneousDateAndConstraintsSaveEmitsOneRequest() throws {
        let store = store(context(try coordinator()))
        try store.save(value)
        emitted.removeAll()
        var changed = value
        changed.outcomeDate = "2027-05-01"
        changed.constraints.maintenance = []
        try store.save(changed)
        XCTAssertEqual(emitted.count, 1)
    }

    func testFailedSaveRollsBackValueAndRequestWithoutPublishing() throws {
        let context = FailingOutcomeContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = try coordinator()
        let store = store(context)
        try store.save(value)
        context.failSave = true
        var changed = value
        changed.outcomeDate = "2027-05-01"
        XCTAssertThrowsError(try store.save(changed))
        XCTAssertEqual(try store.load()?.value, value)
        XCTAssertEqual(try store.pendingEdits().count, 1)
        XCTAssertEqual(emitted.count, 1)
    }

    func testDefaultOffGateAndInvalidDataCannotWriteRequests() async throws {
        let store = store(context(try coordinator()))
        gate = false
        let saved = try XCTUnwrap(store.save(value))
        XCTAssertEqual(try store.load()?.value, value)
        XCTAssertEqual(try store.pendingEdits(), [saved])
        let remote = OutcomeRemoteFixture()
        try await store.synchronize(remote: remote, token: "synthetic", isCurrent: { true })
        XCTAssertTrue(remote.requests.isEmpty, "Cloud sync stays gated while the local value survives")
        XCTAssertEqual(try store.pendingEdits(), [saved])
        gate = true
        var invalid = value
        invalid.outcomeDate = "2027-02-30"
        XCTAssertThrowsError(try store.save(invalid))
        invalid = value
        invalid.outcome.targetValue = .nan
        XCTAssertThrowsError(try store.save(invalid))
        invalid = value
        invalid.constraints.availability.sessionsPerWeek = 7
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load()?.value, value)
        XCTAssertEqual(emitted, [saved])
    }

    func testRemoteApplyNeverOverwritesPendingEditOrEmitsRequest() throws {
        let store = store(context(try coordinator()))
        let edit = try XCTUnwrap(store.save(value))
        var remote = value
        remote.outcomeDate = "2028-01-01"
        let snapshot = DatedOutcomeSnapshot(revision: UUID(), value: remote)
        try store.applyRemote(snapshot)
        XCTAssertEqual(try store.load()?.value, value)
        try store.acknowledge(edit, receipt: .init(revision: edit.requestId, value: edit.value))
        try store.applyRemote(snapshot)
        XCTAssertEqual(try store.load(), snapshot)
        XCTAssertTrue(try store.pendingEdits().isEmpty)
        XCTAssertEqual(emitted.count, 1)
    }

    func testCleanDevicePullRestoresSyncedValueWithoutEmittingRequest() async throws {
        let store = store(context(try coordinator()))
        let remote = OutcomeRemoteFixture()
        remote.latest = .init(revision: UUID(), value: value)
        try await store.synchronize(remote: remote, token: "synthetic", isCurrent: { true })
        owner = nil
        XCTAssertThrowsError(try store.load())
        owner = "owner-a"
        XCTAssertEqual(try store.load(), remote.latest)
        XCTAssertTrue(try store.pendingEdits().isEmpty)
        XCTAssertTrue(remote.requests.isEmpty)
        XCTAssertTrue(emitted.isEmpty)
    }

    func testRetryReusesRequestAndDoesNotAcknowledgeNewerEdit() async throws {
        let store = store(context(try coordinator()))
        let first = try XCTUnwrap(store.save(value))
        let remote = OutcomeRemoteFixture()
        remote.failNextSave = true
        do {
            try await store.synchronize(remote: remote, token: "synthetic", isCurrent: { true })
            XCTFail("Injected failure must propagate")
        } catch { }
        XCTAssertEqual(try store.pendingEdits(), [first])
        var changed = value
        changed.outcomeDate = "2027-06-01"
        let second = try XCTUnwrap(store.save(changed))
        try await store.synchronize(remote: remote, token: "synthetic", isCurrent: { true })
        XCTAssertEqual(remote.requests, [first, first, second])
        XCTAssertTrue(try store.pendingEdits().isEmpty)
        XCTAssertEqual(try store.load()?.revision, second.requestId)
    }

    func testLateReceiptAfterSignOutAndBackCannotAcknowledge() async throws {
        let store = store(context(try coordinator()))
        let edit = try XCTUnwrap(store.save(value))
        let remote = OutcomeRemoteFixture()
        var lifetimeIsCurrent = true
        remote.onSave = { self.owner = nil; self.owner = "owner-a"; lifetimeIsCurrent = false }
        do {
            try await store.synchronize(remote: remote, token: "synthetic", isCurrent: { lifetimeIsCurrent })
            XCTFail("A late receipt must fail closed")
        } catch { }
        XCTAssertEqual(try store.pendingEdits(), [edit])
        XCTAssertEqual(remote.reads, 0)
    }

    func testMismatchedReceiptDoesNotLoseRequest() throws {
        let store = store(context(try coordinator()))
        let edit = try XCTUnwrap(store.save(value))
        XCTAssertThrowsError(try store.acknowledge(edit, receipt: .init(revision: UUID(), value: value)))
        XCTAssertEqual(try store.pendingEdits(), [edit])
    }

    func testExistingV4StoreMigratesWithoutChangingMeasurementsOrCreatingOutcome() throws {
        try assertExistingStoreMigrates(version: "LogYourBodyV4")
    }

    func testExistingV5StoreMigratesWithoutLosingWorkoutReconciliationOrCreatingOutcome() throws {
        try assertExistingStoreMigrates(version: "LogYourBodyV5")
    }

    func testWireFieldsAndLYB130InputsConsumeExternalContractFixtureWhenSupplied() throws {
        let encoded = try JSONEncoder().encode(value)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), Set(["outcome", "outcomeDate", "constraints"]))
        // The native runner can supply the JSON read from Jovie main without vendoring policy.
        if let path = ProcessInfo.processInfo.environment["LYB_LAUNCH_CONTRACT_PATH"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(fixture["schema"] as? String, "lyb-launch-contract/v1")
            let promise = try XCTUnwrap(fixture["promise"] as? [String: Any])
            let inputs = try XCTUnwrap(promise["requiredInputs"] as? [String])
            XCTAssertEqual(Set(fields.keys), Set(inputs))
        }
        XCTAssertEqual(value.planInputs.goal, "body_fat_percentage: 20")
        XCTAssertNil(value.planInputs.experience)
        XCTAssertEqual(value.planInputs.equipment, "dumbbells")
        let edit = DatedOutcomeEdit(requestId: UUID(), previousRevision: nil, value: value)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: Any])
        XCTAssertTrue(wire["previousRevision"] is NSNull)
    }
}
