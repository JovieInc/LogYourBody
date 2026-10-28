import Combine
import CoreData
import XCTest
@testable import LogYourBody

@MainActor
private final class ReconciliationMemoryStore: WorkoutReconciliationStoring {
    var records: [String: WorkoutReconciliationDay] = [:]
    var failWrites = false

    func load(ownerId: String, day: String) throws -> WorkoutReconciliationDay? {
        records[ownerId + "/" + day]
    }

    func save(_ record: WorkoutReconciliationDay, ownerId: String, day: String) throws {
        if failWrites { throw WorkoutReconciliationError.invalidStoredRecord }
        records[ownerId + "/" + day] = record
    }
}

@MainActor
private final class ReconciliationFixture {
    var ownerId = "owner-A"
    var gymName = "Example Gym"
    var probable = true
    var hasLog = false
    var permission = true
    var enabled = true
    var date = Date(timeIntervalSince1970: 1_793_001_600) // 2026-10-26 08:00 UTC
    var calendar = Calendar(identifier: .gregorian)
    let store = ReconciliationMemoryStore()

    init() {
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func model(store: WorkoutReconciliationStoring? = nil) -> WorkoutReconciliationViewModel {
        WorkoutReconciliationViewModel(
            store: store ?? self.store,
            context: {
                WorkoutReconciliationPolicy.Context(
                    ownerId: self.ownerId, gymName: self.gymName, hasProbableAttendance: self.probable,
                    hasWorkoutLog: self.hasLog, permissionGranted: self.permission
                )
            },
            checkGate: { self.enabled && $0 == WorkoutReconciliationPolicy.featureGate },
            now: { self.date }, calendar: { self.calendar }
        )
    }

    var record: WorkoutReconciliationDay? { store.records.values.first }
}

@MainActor
final class WorkoutReconciliationPromptTests: XCTestCase {
    func testEligibilityAndResponseTable() throws {
        let cases: [(name: String, log: Bool, permission: Bool, response: String?, expectedPrompt: Bool)] = [
            ("probable+no log", false, true, nil, true),
            ("probable+log", true, true, nil, false),
            ("denied", false, true, "no", false),
            ("ignored", false, true, "ignored", false),
            ("revoked", false, false, nil, false)
        ]
        for scenario in cases {
            let fixture = ReconciliationFixture()
            fixture.hasLog = scenario.log
            fixture.permission = scenario.permission
            let model = fixture.model()
            try model.refresh()
            if scenario.response == "no" {
                try model.deny()
                XCTAssertEqual(fixture.record?.response, .denied)
            } else if scenario.response == "ignored" {
                let before = fixture.store.records
                model.ignore()
                XCTAssertEqual(fixture.store.records, before, "Ignoring writes nothing")
                XCTAssertNil(fixture.record?.response)
            }
            try model.refresh()
            XCTAssertEqual(model.prompt != nil, scenario.expectedPrompt, scenario.name)
            XCTAssertNil(fixture.record?.session, scenario.name)
            let recreated = fixture.model()
            try recreated.refresh()
            XCTAssertNil(recreated.prompt, "No second offer after recreating the model: \(scenario.name)")
        }
    }

    func testQuestionCopyAndOneOfferAcrossGymsAndModels() throws {
        let fixture = ReconciliationFixture()
        let model = fixture.model()
        var offers: [WorkoutReconciliationViewModel.Prompt] = []
        let observation = model.$prompt.compactMap { $0 }.sink { offers.append($0) }
        defer { observation.cancel() }
        try model.refresh()
        let first = try XCTUnwrap(model.prompt)
        XCTAssertEqual(first.question, "Looks like you trained at Example Gym. Was that today's session?")
        try model.refresh()
        XCTAssertEqual(model.prompt, first)
        XCTAssertEqual(offers, [first], "Refresh cannot publish a second presentation event")
        let secondModel = fixture.model()
        try secondModel.refresh()
        XCTAssertNil(secondModel.prompt)
        fixture.gymName = "Another Gym"
        try model.refresh()
        XCTAssertNil(model.prompt)
        fixture.date = try XCTUnwrap(fixture.calendar.date(byAdding: .day, value: 1, to: fixture.date))
        try model.refresh()
        XCTAssertEqual(model.prompt?.gymName, "Another Gym")
        XCTAssertEqual(fixture.store.records.count, 2)
    }

    func testYesWithoutTimestampsConfirmsOnlyAttendanceWithNilVolume() throws {
        let fixture = ReconciliationFixture()
        let model = fixture.model()
        try model.refresh()
        let session = try XCTUnwrap(model.confirm())
        XCTAssertEqual(session.gymName, fixture.gymName)
        XCTAssertEqual(session.confirmedAt, fixture.date)
        XCTAssertNil(session.userConfirmedStart)
        XCTAssertNil(session.userConfirmedEnd)
        XCTAssertNil(session.duration)
        XCTAssertNil(session.setLevelVolume, "Unknown volume must never become zero")
        XCTAssertEqual(fixture.record?.response, .confirmed)
        XCTAssertEqual(fixture.record?.session, session)
        XCTAssertNil(try model.confirm(), "A repeated tap cannot create another session")
        try model.refresh()
        XCTAssertNil(model.prompt)
    }

    func testDurationRequiresBothUserConfirmedTimestamps() throws {
        let base = ReconciliationFixture().date
        let cases: [(Date?, Date?, TimeInterval?)] = [
            (nil, nil, nil), (base, nil, nil), (nil, base, nil),
            (base, base.addingTimeInterval(2_700), 2_700)
        ]
        for (start, end, duration) in cases {
            let fixture = ReconciliationFixture()
            let model = fixture.model()
            try model.refresh()
            fixture.date = fixture.date.addingTimeInterval(60) // Answer time is never a workout boundary.
            let session = try XCTUnwrap(model.confirm(userConfirmedStart: start, userConfirmedEnd: end))
            XCTAssertEqual(session.userConfirmedStart, start)
            XCTAssertEqual(session.userConfirmedEnd, end)
            XCTAssertEqual(session.duration, duration)
            XCTAssertNil(session.setLevelVolume)
        }
    }

    func testInvalidConfirmedTimesDoNotSaveAResponse() throws {
        let fixture = ReconciliationFixture()
        let model = fixture.model()
        try model.refresh()
        let before = fixture.store.records
        for end in [fixture.date, fixture.date.addingTimeInterval(-1), Date(timeIntervalSince1970: .infinity)] {
            XCTAssertThrowsError(try model.confirm(userConfirmedStart: fixture.date, userConfirmedEnd: end))
            XCTAssertEqual(fixture.store.records, before)
            XCTAssertNotNil(model.prompt, "The user can correct the supplied times")
        }
    }

    func testDisabledGateAndNonProbableAttendanceCannotOfferAQuestion() throws {
        let fixture = ReconciliationFixture()
        let model = fixture.model()
        fixture.enabled = false
        try model.refresh()
        XCTAssertNil(model.prompt)
        XCTAssertTrue(fixture.store.records.isEmpty)
        fixture.enabled = true
        fixture.probable = false
        try model.refresh()
        XCTAssertNil(model.prompt)
        XCTAssertTrue(fixture.store.records.isEmpty)
        fixture.probable = true
        try model.refresh()
        XCTAssertNotNil(model.prompt)
    }

    func testRevocationClearsQuestionAndBlocksBothAnswersWithoutRefresh() throws {
        for answerYes in [true, false] {
            let fixture = ReconciliationFixture()
            let model = fixture.model()
            try model.refresh()
            let before = fixture.store.records
            fixture.permission = false
            if answerYes {
                XCTAssertNil(try model.confirm())
            } else {
                try model.deny()
            }
            XCTAssertNil(model.prompt)
            XCTAssertEqual(fixture.store.records, before)
            try model.refresh()
            XCTAssertNil(model.prompt)
            fixture.permission = true
            try model.refresh()
            XCTAssertNil(model.prompt, "Reauthorizing cannot produce another offer that day")
        }
        let fixture = ReconciliationFixture()
        let model = fixture.model()
        try model.refresh()
        fixture.permission = false
        try model.refresh()
        XCTAssertNil(model.prompt)
    }

    func testStaleQuestionCannotWriteAfterLogAccountDayGateOrAttendanceChange() throws {
        let changes: [(ReconciliationFixture) -> Void] = [
            { $0.hasLog = true }, { $0.ownerId = "owner-B" },
            { $0.date = $0.date.addingTimeInterval(86_400) },
            { $0.enabled = false }, { $0.probable = false }
        ]
        for change in changes {
            let fixture = ReconciliationFixture()
            let model = fixture.model()
            try model.refresh()
            let before = fixture.store.records
            change(fixture)
            XCTAssertNil(try model.confirm())
            XCTAssertEqual(fixture.store.records, before)
            XCTAssertNil(model.prompt)
        }
    }

    func testFailureToSaveSuppressionNeverPublishesAndResponseFailureCanRetry() throws {
        let fixture = ReconciliationFixture()
        let model = fixture.model()
        fixture.store.failWrites = true
        XCTAssertThrowsError(try model.refresh())
        XCTAssertNil(model.prompt)
        fixture.store.failWrites = false
        try model.refresh()
        fixture.store.failWrites = true
        XCTAssertThrowsError(try model.confirm())
        XCTAssertNotNil(model.prompt)
        XCTAssertNil(fixture.record?.response)
        fixture.store.failWrites = false
        XCTAssertNotNil(try model.confirm())
    }

    func testDayUsesLocalCalendarIncludingDaylightSavingBoundary() throws {
        let fixture = ReconciliationFixture()
        fixture.calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        fixture.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T04:30:00Z"))
        let model = fixture.model()
        try model.refresh()
        model.ignore()
        fixture.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-02T04:30:00Z"))
        try model.refresh()
        XCTAssertNil(model.prompt, "Both instants are November 1 locally, across the 25-hour day")
        fixture.date = fixture.date.addingTimeInterval(3_600)
        try model.refresh()
        XCTAssertNotNil(model.prompt)
    }

    func testCoreDataRetainsDeniedIgnoredAndConfirmedDaysAcrossReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reconciliation.sqlite")
        let container = try openContainer(at: url)
        let store = CoreDataWorkoutReconciliationStore(container: container)
        for response in ["denied", "ignored", "confirmed"] {
            let fixture = ReconciliationFixture()
            fixture.ownerId = response
            let model = fixture.model(store: store)
            try model.refresh()
            switch response {
            case "denied": try model.deny()
            case "confirmed": try model.confirm(userConfirmedStart: fixture.date, userConfirmedEnd: nil)
            default: model.ignore()
            }
        }
        try close(container)
        let reopened = try openContainer(at: url)
        defer { try? close(reopened) }
        let reopenedStore = CoreDataWorkoutReconciliationStore(container: reopened)
        for response in ["denied", "ignored", "confirmed"] {
            let fixture = ReconciliationFixture()
            fixture.ownerId = response
            let model = fixture.model(store: reopenedStore)
            try model.refresh()
            XCTAssertNil(model.prompt)
            let day = WorkoutReconciliationPolicy.dayKey(for: fixture.date, calendar: fixture.calendar)
            let record = try XCTUnwrap(reopenedStore.load(ownerId: response, day: day))
            XCTAssertEqual(record.response?.rawValue, response == "ignored" ? nil : response)
            XCTAssertEqual(record.session != nil, response == "confirmed")
            XCTAssertNil(record.session?.setLevelVolume)
            XCTAssertNil(record.session?.duration)
        }
        let otherOwner = ReconciliationFixture()
        let model = otherOwner.model(store: reopenedStore)
        try model.refresh()
        XCTAssertNotNil(model.prompt, "Another account has independent suppression")
    }

    func testSeparateCoreDataStoresObserveTheSavedResponse() throws {
        let container = try openContainer(at: URL(fileURLWithPath: "/dev/null"), type: NSInMemoryStoreType)
        defer { try? close(container) }
        let first = CoreDataWorkoutReconciliationStore(container: container)
        let second = CoreDataWorkoutReconciliationStore(container: container)
        let fixture = ReconciliationFixture()
        let model = fixture.model(store: first)
        try model.refresh()
        let day = WorkoutReconciliationPolicy.dayKey(for: fixture.date, calendar: fixture.calendar)
        XCTAssertNil(try second.load(ownerId: fixture.ownerId, day: day)?.response)
        try model.deny()
        XCTAssertEqual(try second.load(ownerId: fixture.ownerId, day: day)?.response, .denied)
    }

    func testDeletingLocalAccountDataRemovesSessionsAndSuppression() async throws {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        let manager = CoreDataManager(persistentStoreDescriptions: [description])
        XCTAssertEqual(manager.persistentContainer.persistentStoreCoordinator.persistentStores.count, 1)
        let store = CoreDataWorkoutReconciliationStore(container: manager.persistentContainer)
        let fixture = ReconciliationFixture()
        let model = fixture.model(store: store)
        try model.refresh()
        XCTAssertNotNil(try model.confirm())
        let day = WorkoutReconciliationPolicy.dayKey(for: fixture.date, calendar: fixture.calendar)
        XCTAssertNotNil(try store.load(ownerId: fixture.ownerId, day: day)?.session)

        try await manager.deleteAllDataAndWait()

        XCTAssertNil(try store.load(ownerId: fixture.ownerId, day: day))
        try close(manager.persistentContainer)
    }

    func testV4MigrationPreservesExistingEntitiesAndAddsReconciliationStorage() throws {
        let bundle = Bundle(for: CoreDataManager.self)
        let modelURL = try XCTUnwrap(bundle.url(forResource: "LogYourBody", withExtension: "momd"))
        let old = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("LogYourBodyV4.mom")))
        let current = CoreDataManager.makeManagedObjectModel()
        XCTAssertNil(old.entitiesByName["CachedWorkoutReconciliationDay"])
        XCTAssertNotNil(current.entitiesByName["CachedWorkoutReconciliationDay"])
        for entity in old.entities {
            XCTAssertEqual(entity.versionHash, current.entitiesByName[try XCTUnwrap(entity.name)]?.versionHash)
        }
        XCTAssertNoThrow(try NSMappingModel.inferredMappingModel(forSourceModel: old, destinationModel: current))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("v4.sqlite")
        let legacy = NSPersistentContainer(name: "LogYourBody", managedObjectModel: old)
        try legacy.persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
        let row = NSEntityDescription.insertNewObject(forEntityName: "CachedDailyMetrics", into: legacy.viewContext)
        row.setValue("retained-id", forKey: "id")
        row.setValue("owner-A", forKey: "userId")
        for key in ["date", "createdAt", "updatedAt", "lastModified"] {
            row.setValue(ReconciliationFixture().date, forKey: key)
        }
        row.setValue(1_234, forKey: "steps")
        try legacy.viewContext.save()
        try close(legacy)

        let migrated = try openContainer(at: url)
        defer { try? close(migrated) }
        let retained = try XCTUnwrap(migrated.viewContext.fetch(
            NSFetchRequest<NSManagedObject>(entityName: "CachedDailyMetrics")
        ).first)
        XCTAssertEqual(retained.value(forKey: "id") as? String, "retained-id")
        XCTAssertEqual(retained.value(forKey: "steps") as? Int, 1_234)
        let store = CoreDataWorkoutReconciliationStore(container: migrated)
        let fixture = ReconciliationFixture()
        let model = fixture.model(store: store)
        try model.refresh()
        XCTAssertNotNil(model.prompt)
        XCTAssertNotNil(try model.confirm())
    }

    private func openContainer(at url: URL, type: String = NSSQLiteStoreType) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "LogYourBody", managedObjectModel: CoreDataManager.makeManagedObjectModel())
        try container.persistentStoreCoordinator.addPersistentStore(
            ofType: type, configurationName: nil, at: url,
            options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
        )
        return container
    }

    private func close(_ container: NSPersistentContainer) throws {
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
