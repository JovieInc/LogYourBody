import CoreData
import XCTest
@testable import LogYourBody

@MainActor
final class DatedOutcomeStoreTests: XCTestCase {
    private var owner: String? = "owner-a"
    private var gate = true
    private var emitted: [DatedOutcomeEdit] = []

    private var value: DatedOutcome {
        DatedOutcome(
            outcome: .init(metric: .bodyFatPercentage, targetValue: 20), outcomeDate: "2027-04-01",
            constraints: .init(
                availability: .init(sessionsPerWeek: 3, minutesPerSession: 45, equipment: "dumbbells"),
                travel: [.init(start: "2027-01-01", end: "2027-01-07")],
                maintenance: [.init(start: "2027-02-01", end: "2027-02-14")]
            )
        )
    }

    private func store(_ context: NSManagedObjectContext) -> DatedOutcomeStore {
        DatedOutcomeStore(
            context: context, currentOwner: { self.owner }, enabled: { self.gate },
            didSave: { self.emitted.append($0) }
        )
    }

    private func coordinator(version: String? = nil, url: URL? = nil) throws -> NSPersistentStoreCoordinator {
        let model: NSManagedObjectModel
        if let version {
            let bundle = try XCTUnwrap(Bundle(for: CoreDataManager.self).url(forResource: "LogYourBody", withExtension: "momd"))
            model = try XCTUnwrap(NSManagedObjectModel(contentsOf: bundle.appendingPathComponent("\(version).mom")))
        } else {
            model = CoreDataManager.makeManagedObjectModel()
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: url == nil ? NSInMemoryStoreType : NSSQLiteStoreType, configurationName: nil, at: url,
            options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
        )
        return coordinator
    }

    private func context(_ coordinator: NSPersistentStoreCoordinator) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func close(_ coordinator: NSPersistentStoreCoordinator) throws {
        for persistentStore in coordinator.persistentStores { try coordinator.remove(persistentStore) }
    }

    private func removeStore(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coach-\(UUID()).sqlite")
        defer { removeStore(url) }
        let first = try coordinator(url: url)
        let background = FailingOutcomeContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = first
        let journal = store(background)
        var goal = value
        goal.outcome = .init(metric: .weightKg, targetValue: 76)
        let edit = try XCTUnwrap(journal.save(goal))
        let now = try XCTUnwrap(DatedOutcome.calendarDate("2026-11-01"))
        let baseline = DatedOutcome.PlanBaseline(date: now.addingTimeInterval(-8 * 7 * 86_400), metric: .weightKg, value: 80)
        let records = [("baseline", baseline.date, 80.0), ("latest", now, 78.0)].map { id, date, weight in
            BodyMetrics(id: id, userId: "owner-a", date: date, weight: weight, weightUnit: "kg",
                        bodyFatPercentage: nil, bodyFatMethod: nil, muscleMass: nil, boneMass: nil, notes: nil,
                        photoUrl: nil, dataSource: "manual", createdAt: date, updatedAt: date)
        }
        // Arithmetic examples only; production policy remains unavailable.
        let input = LaunchJourney.Input(
            now: now, outcome: goal, freshnessWindow: 365 * 86_400,
            thresholds: [.weightKg: .init(
                minimumTarget: 40, maximumTarget: 250, minimumWeeklyChange: -1, maximumWeeklyChange: 1)],
            safeWeeklyChangeKg: -1...1)
        let projection = await DatedTimelineProjector().project(
            owner: "owner-a", metrics: records, input: input, savedOutcome: try journal.load())
        let action = try XCTUnwrap(projection.coach.actionToSave)
        try await journal.retainPlanBaselineForPresentation(baseline, revision: edit.requestId, isCurrent: { true })
        try await journal.retainCoachActionForPresentation(action, isCurrent: { true })
        XCTAssertEqual(try journal.load()?.coachAction, action)
        await background.perform { background.failSave = true }
        var failedReview = action
        failedReview.id = UUID()
        failedReview.reviewedAt = now.addingTimeInterval(1)
        failedReview.nextCheckIn = action.nextCheckIn.addingTimeInterval(1)
        do {
            try await journal.retainCoachActionForPresentation(failedReview, isCurrent: { true })
            XCTFail("A failed write must not acknowledge a weekly review")
        } catch DatedOutcomeError.unavailable { }
        XCTAssertEqual(try journal.load()?.coachAction, action)
        await background.perform { background.failSave = false }
        XCTAssertEqual(try journal.pendingEdits(), [edit])
        XCTAssertEqual(emitted.count, 1)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: Any])
        XCTAssertNil(wire["coachAction"])
        try journal.acknowledge(edit, receipt: .init(revision: edit.requestId, value: goal))
        try close(first)
        let reopened = try coordinator(url: url)
        defer { try? close(reopened) }
        let restored = store(context(reopened))
        XCTAssertEqual(try restored.load()?.coachAction, action)
        let returned = await DatedTimelineProjector().project(
            owner: "owner-a", metrics: records, input: input, savedOutcome: try restored.load())
        XCTAssertNil(returned.coach.actionToSave)
        XCTAssertEqual(returned.coach.presentation, projection.coach.presentation)
        XCTAssertEqual(returned.coach.nextCheckIn, action.nextCheckIn)
        owner = nil
        XCTAssertThrowsError(try restored.load())
        owner = "owner-b"
        XCTAssertNil(try restored.load())
        owner = "owner-a"
        var revised = goal
        revised.outcomeDate = "2027-05-01"
        try restored.save(revised)
        XCTAssertNil(try restored.load()?.coachAction, "An edited date must recompute the action")
        do {
            try await restored.retainCoachActionForPresentation(action, isCurrent: { true })
            XCTFail("An old revision cannot restore an action after a date edit")
        } catch DatedOutcomeError.invalidReceipt { }
        owner = "owner-b"
        do {
            try await restored.retainCoachActionForPresentation(action, isCurrent: { false })
            XCTFail("An old account presentation cannot save an action")
        } catch DatedOutcomeError.unauthenticated { }
        XCTAssertNil(try restored.load())
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

    private func assertExistingStoreMigrates(version: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("outcome-migration-\(UUID()).sqlite")
        defer { removeStore(url) }
        let legacy = try coordinator(version: version, url: url)
        let legacyContext = context(legacy)
        let profile = NSEntityDescription.insertNewObject(forEntityName: "CachedProfile", into: legacyContext)
        profile.setValue("owner-a", forKey: "id")
        profile.setValue("synthetic@example.invalid", forKey: "email")
        for key in ["createdAt", "updatedAt", "lastModified"] { profile.setValue(Date(), forKey: key) }
        profile.setValue(80, forKey: "goalWeight")
        let metric = NSEntityDescription.insertNewObject(forEntityName: "CachedBodyMetrics", into: legacyContext)
        metric.setValue("measurement-a", forKey: "id")
        metric.setValue("owner-a", forKey: "userId")
        for key in ["createdAt", "updatedAt", "lastModified", "date"] { metric.setValue(Date(), forKey: key) }
        metric.setValue(85.5, forKey: "weight")
        let reconciliationPayload = Data("retained-reconciliation".utf8)
        if version == "LogYourBodyV5" {
            XCTAssertNotNil(legacy.managedObjectModel.entitiesByName["CachedWorkoutReconciliationDay"])
            let day = NSEntityDescription.insertNewObject(
                forEntityName: "CachedWorkoutReconciliationDay", into: legacyContext
            )
            day.setValue("owner-a", forKey: "ownerId")
            day.setValue("2027-01-01", forKey: "day")
            day.setValue(reconciliationPayload, forKey: "payload")
        }
        try legacyContext.save()
        try close(legacy)
        let migrated = try coordinator(url: url)
        defer { try? close(migrated) }
        let migratedContext = context(migrated)
        let profiles = try migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "CachedProfile"))
        XCTAssertEqual(profiles.first?.value(forKey: "goalWeight") as? Double, 80)
        let metrics = try migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "CachedBodyMetrics"))
        XCTAssertEqual(metrics.first?.value(forKey: "weight") as? Double, 85.5)
        if version == "LogYourBodyV5" {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CachedWorkoutReconciliationDay")
            let days = try migratedContext.fetch(request)
            XCTAssertEqual(days.count, 1)
            XCTAssertEqual(days.first?.value(forKey: "ownerId") as? String, "owner-a")
            XCTAssertEqual(days.first?.value(forKey: "day") as? String, "2027-01-01")
            XCTAssertEqual(days.first?.value(forKey: "payload") as? Data, reconciliationPayload)
        }
        let store = store(migratedContext)
        XCTAssertNil(try store.load())
        try store.save(value)
        XCTAssertEqual(try store.load()?.value, value)
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
