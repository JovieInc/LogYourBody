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

    func testDefaultOffGateAndInvalidDataCannotWriteRequests() throws {
        let store = store(context(try coordinator()))
        gate = false
        XCTAssertThrowsError(try store.save(value))
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
        XCTAssertNil(try store.load())
        XCTAssertTrue(emitted.isEmpty)
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

private final class FailingOutcomeContext: NSManagedObjectContext {
    var failSave = false
    override func save() throws {
        if failSave { throw DatedOutcomeError.unavailable }
        try super.save()
    }
}

@MainActor
private final class OutcomeRemoteFixture: DatedOutcomeRemote {
    var requests: [DatedOutcomeEdit] = []
    var latest: DatedOutcomeSnapshot?
    var failNextSave = false
    var onSave: (() -> Void)?
    var reads = 0

    func saveDatedOutcome(_ edit: DatedOutcomeEdit, token: String) async throws -> DatedOutcomeSnapshot {
        requests.append(edit)
        onSave?()
        if failNextSave { failNextSave = false; throw DatedOutcomeError.unavailable }
        let receipt = DatedOutcomeSnapshot(revision: edit.requestId, value: edit.value)
        latest = receipt
        return receipt
    }

    func fetchDatedOutcome(token: String) async throws -> DatedOutcomeSnapshot? {
        reads += 1
        return latest
    }
}
