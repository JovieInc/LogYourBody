import CoreData
import XCTest
@testable import LogYourBody

@MainActor
class DatedOutcomeStoreFixtureCase: XCTestCase {
    var owner: String? = "owner-a"
    var gate = true
    var emitted: [DatedOutcomeEdit] = []

    var value: DatedOutcome {
        DatedOutcome(
            outcome: .init(metric: .bodyFatPercentage, targetValue: 20), outcomeDate: "2027-04-01",
            constraints: .init(
                availability: .init(sessionsPerWeek: 3, minutesPerSession: 45, equipment: "dumbbells"),
                travel: [.init(start: "2027-01-01", end: "2027-01-07")],
                maintenance: [.init(start: "2027-02-01", end: "2027-02-14")]
            )
        )
    }

    func store(_ context: NSManagedObjectContext) -> DatedOutcomeStore {
        DatedOutcomeStore(
            context: context, currentOwner: { self.owner }, enabled: { self.gate },
            didSave: { self.emitted.append($0) }
        )
    }

    func coordinator(version: String? = nil, url: URL? = nil) throws -> NSPersistentStoreCoordinator {
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

    func context(_ coordinator: NSPersistentStoreCoordinator) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    func close(_ coordinator: NSPersistentStoreCoordinator) throws {
        for persistentStore in coordinator.persistentStores { try coordinator.remove(persistentStore) }
    }

    func removeStore(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    func assertExistingStoreMigrates(version: String) throws {
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

    func assertCoachActionAndNextCheckInSurviveSQLiteReopenWithoutSyncEdit() async throws {
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

}
