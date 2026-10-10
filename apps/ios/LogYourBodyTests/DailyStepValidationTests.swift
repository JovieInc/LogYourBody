import CoreData
import XCTest
@testable import LogYourBody

@MainActor
final class DailyStepValidationTests: XCTestCase {
    private var coreData: CoreDataManager!
    private let userId = "step-validation-owner"
    private let date = Date(timeIntervalSince1970: 1_735_000_000)

    override func setUp() async throws {
        try await super.setUp()
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        coreData = CoreDataManager(persistentStoreDescriptions: [store])
    }

    override func tearDown() async throws {
        coreData = nil
        try await super.tearDown()
    }

    func testLocalNegativeStepsPreserveEveryStoredFieldAndSyncState() async throws {
        try await assertLocalRejected(-1)
    }

    func testLocalOutOfRangeStepsPreserveEveryStoredFieldAndSyncState() async throws {
        for steps in [Int(Int32.max) + 1, Int.max, Int.min] {
            try await assertLocalRejected(steps)
        }
    }

    func testInvalidLocalStepsDoNotInsertPartialRows() async throws {
        for steps in [-1, Int(Int32.max) + 1, Int.max] {
            let metric = model(steps: steps)
            do {
                try await coreData.saveDailyMetricsAndWait(metric, userId: userId)
                XCTFail("Invalid steps must fail before insertion")
            } catch {}
            let row = try await row(id: metric.id)
            XCTAssertNil(row)
            XCTAssertFalse(coreData.viewContext.hasChanges)
        }
    }

    func testLocalMissingZeroAndMaximumStepsKeepStorageContract() async throws {
        for steps: Int? in [nil, 0, 8_421, Int(Int32.max)] {
            let metric = model(steps: steps)
            try await coreData.saveDailyMetricsAndWait(metric, userId: userId)
            let fetched = try await row(id: metric.id)
            let cached = try XCTUnwrap(fetched)
            XCTAssertEqual(Int(cached.steps), steps ?? 0)
            XCTAssertFalse(cached.isSynced)
            XCTAssertEqual(cached.syncStatus, "pending")
        }
    }

    func testRemoteBooleanStepsPreserveEveryStoredFieldAndSyncState() async throws {
        for steps in [true, false] { try await assertRemoteRejected(steps) }
    }

    func testRemoteFractionalStepsPreserveEveryStoredFieldAndSyncState() async throws {
        try await assertRemoteRejected(NSNumber(value: 1.5))
    }

    func testRemoteNegativeStepsPreserveEveryStoredFieldAndSyncState() async throws {
        try await assertRemoteRejected(-1)
    }

    func testRemoteOutOfRangeAndNonfiniteStepsPreserveStoredRows() async throws {
        let values: [Any] = [Int(Int32.max) + 1, Int.max, UInt64.max, 1e100, Double.nan, Double.infinity]
        for value in values { try await assertRemoteRejected(value) }
    }

    func testRemoteDecimalFractionIsNotRoundedIntoAnInteger() async throws {
        try await assertRemoteRejected(NSDecimalNumber(string: "1.000000000000000000001"))
    }

    func testRemoteMalformedStepsDoNotBecomeZero() async throws {
        let values: [Any] = ["8421", [1], ["value": 1]]
        for value in values { try await assertRemoteRejected(value) }
    }

    func testInvalidRemoteStepsDoNotInsertPartialRows() async throws {
        let values: [Any] = [true, 1.5, -1, Int(Int32.max) + 1, "8421"]
        for value in values {
            let id = UUID().uuidString
            coreData.updateOrCreateDailyMetric(from: payload(id: id, steps: value))
            let fetched = try await row(id: id)
            XCTAssertNil(fetched, "Invalid steps must fail before insertion")
            XCTAssertFalse(coreData.viewContext.hasChanges)
        }
    }

    func testRemoteMissingNullZeroAndMaximumStepsKeepStorageContract() async throws {
        let values: [Any?] = [nil, NSNull(), 0, NSNumber(value: 8_421.0), Int(Int32.max)]
        let expected: [Int32] = [0, 0, 0, 8_421, Int32.max]
        for (index, value) in values.enumerated() {
            let id = UUID().uuidString
            coreData.updateOrCreateDailyMetric(from: payload(id: id, steps: value))
            let fetched = try await row(id: id)
            let cached = try XCTUnwrap(fetched)
            XCTAssertEqual(cached.steps, expected[index])
            XCTAssertTrue(cached.isSynced)
            XCTAssertEqual(cached.syncStatus, "synced")
        }
    }

    func testJSONSerializationNumbersUseTheSameValidationBoundary() async throws {
        for token in ["true", "false", "1.5", "-1", "2147483648", "9007199254740991", "1e100"] {
            let data = Data("{\"steps\":\(token)}".utf8)
            let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            try await assertRemoteRejected(try XCTUnwrap(decoded["steps"]))
        }
    }

    func testWriteAdmissionStillRejectsBeforeAnyMutation() async throws {
        let metric = model(steps: 123)
        do {
            try await coreData.saveDailyMetricsAndWait(metric, userId: userId, writeAdmission: {
                throw NSError(domain: "StepValidationAdmission", code: 1)
            })
            XCTFail("Admission must still reject the write")
        } catch {
            XCTAssertEqual((error as NSError).domain, "StepValidationAdmission")
        }
        let fetched = try await row(id: metric.id)
        XCTAssertNil(fetched)
        XCTAssertFalse(coreData.viewContext.hasChanges)
    }

    func testDashboardNegativeStepsPreserveStoredAndDisplayedMetrics() async throws {
        try await assertDashboardRejected(-1)
    }

    func testDashboardOutOfRangeStepsPreserveStoredAndDisplayedMetrics() async throws {
        try await assertDashboardRejected(Int.max)
    }

    private func assertLocalRejected(_ steps: Int) async throws {
        for isSynced in [false, true] {
            let cached = try await seed(isSynced: isSynced)
            let before = snapshot(cached)
            let candidate = model(id: try XCTUnwrap(cached.id), steps: steps, notes: "must not replace")
            do {
                try await coreData.saveDailyMetricsAndWait(candidate, userId: userId)
                XCTFail("Invalid steps must be rejected")
            } catch {}
            XCTAssertEqual(snapshot(cached), before)
            XCTAssertFalse(coreData.viewContext.hasChanges)
        }
    }

    private func assertRemoteRejected(_ steps: Any) async throws {
        for isSynced in [false, true] {
            let cached = try await seed(isSynced: isSynced)
            let before = snapshot(cached)
            var incoming = payload(id: try XCTUnwrap(cached.id), steps: steps)
            incoming["notes"] = "must not replace"
            incoming["date"] = "2026-10-10T12:00:00Z"
            incoming["updated_at"] = "2026-10-10T12:00:00Z"
            coreData.updateOrCreateDailyMetric(from: incoming)
            _ = try await row(id: try XCTUnwrap(cached.id))
            XCTAssertEqual(snapshot(cached), before)
            XCTAssertFalse(coreData.viewContext.hasChanges)
        }
    }

    private func seed(isSynced: Bool) async throws -> CachedDailyMetrics {
        let metric = model(steps: 8_421)
        try await coreData.saveDailyMetricsAndWait(metric, userId: userId)
        let fetched = try await row(id: metric.id)
        let cached = try XCTUnwrap(fetched)
        cached.isSynced = isSynced
        cached.syncStatus = isSynced ? "synced" : "pending"
        try coreData.viewContext.save()
        return cached
    }

    private func row(id: String) async throws -> CachedDailyMetrics? {
        let context = coreData.viewContext
        return try await context.perform {
            let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            return try context.fetch(request).first
        }
    }

    private func snapshot(_ row: CachedDailyMetrics) -> NSDictionary {
        row.dictionaryWithValues(forKeys: Array(row.entity.attributesByName.keys)) as NSDictionary
    }

    private func model(id: String = UUID().uuidString, steps: Int?, notes: String = "original") -> DailyMetrics {
        DailyMetrics(id: id, userId: userId, date: date, steps: steps, notes: notes, createdAt: date, updatedAt: date)
    }

    private func payload(id: String, steps: Any?) -> [String: Any] {
        var value: [String: Any] = [
            "id": id, "user_id": userId, "date": "2024-12-23T10:00:00Z",
            "created_at": "2024-12-23T10:00:00Z", "updated_at": "2024-12-23T10:00:00Z"
        ]
        value["steps"] = steps
        return value
    }

    private func assertDashboardRejected(_ steps: Int) async throws {
        let owner = "step-dashboard-\(UUID().uuidString)"
        let metric = DailyMetrics(id: UUID().uuidString, userId: owner, date: Date(), steps: 8_421,
                                  notes: "original", createdAt: date, updatedAt: date)
        let shared = CoreDataManager.shared
        try await shared.saveDailyMetricsAndWait(metric, userId: owner)
        let fetched = await shared.fetchDailyMetrics(for: owner, date: Date())
        let cached = try XCTUnwrap(fetched)
        cached.isSynced = true
        cached.syncStatus = "synced"
        try shared.viewContext.save()
        let before = snapshot(cached)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: owner))
        defer { defaults.removePersistentDomain(forName: owner) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let auth = AuthManager(userDefaults: defaults, urlSession: session)
        auth.currentUser = LocalUser(
            id: owner, email: "steps@example.invalid", name: "Steps",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        let sync = RealtimeSyncManager(coreDataManager: shared, authManager: auth, productAPIClient: ProductAPIClient())
        sync.isOnline = false
        let dashboard = DashboardViewModel(healthSyncCoordinator: MockHealthSyncCoordinator())
        dashboard.dailyMetrics = metric
        do {
            try await dashboard.updateStepCount(steps: steps, authManager: auth, realtimeSyncManager: sync)
            XCTFail("Invalid steps must not reach the direct Dashboard write")
        } catch {}
        XCTAssertEqual(snapshot(cached), before)
        XCTAssertEqual(dashboard.dailyMetrics?.steps, metric.steps)
        XCTAssertEqual(dashboard.dailyMetrics?.updatedAt, metric.updatedAt)
    }
}
