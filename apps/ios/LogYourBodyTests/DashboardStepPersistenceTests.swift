import CoreData
import XCTest
@testable import LogYourBody

@MainActor
private final class HeldDashboardStepOperation<Value> {
    let started = XCTestExpectation(description: "Synthetic dashboard step operation started")
    private var continuation: CheckedContinuation<Value, Never>?
    private var completed: Value?

    func wait() async -> Value {
        started.fulfill()
        return await withCheckedContinuation { continuation in
            if let completed { continuation.resume(returning: completed) } else { self.continuation = continuation }
        }
    }

    func complete(_ value: Value) {
        guard completed == nil else { return }
        completed = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@MainActor
final class DashboardStepPersistenceTests: XCTestCase {
    private var ownedDefaults: UserDefaults!
    private var ownedAuth: AuthManager!
    private var ownedStore: CoreDataManager!
    private var ownedURLSession: URLSession!
    private var ownedSuite = ""
    private var syncTriggers = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        ownedSuite = "DashboardStepOwnership.\(UUID().uuidString)"
        ownedDefaults = try XCTUnwrap(UserDefaults(suiteName: ownedSuite))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        ownedURLSession = URLSession(configuration: configuration)
        ownedAuth = AuthManager(userDefaults: ownedDefaults, urlSession: ownedURLSession)
        setOwnedAccount("dashboard-owner-A")
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        ownedStore = CoreDataManager(persistentStoreDescriptions: [store])
        syncTriggers = 0
    }

    override func tearDown() {
        ownedURLSession?.invalidateAndCancel()
        ownedDefaults?.removePersistentDomain(forName: ownedSuite)
        ownedAuth = nil
        ownedStore = nil
        ownedURLSession = nil
        ownedDefaults = nil
        super.tearDown()
    }

    private func setOwnedAccount(_ subject: String) {
        ownedAuth.authSession = .localFixture(subject: subject, email: "steps@example.invalid", accessToken: "synthetic")
        ownedAuth.currentUser = LocalUser(
            id: subject, email: "steps@example.invalid", name: "Synthetic Steps",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
    }

    private func ownedDashboard(
        todayLoader: (() async throws -> Int)? = nil,
        loader: (@MainActor (String, Date) async -> DailyMetrics?)? = nil,
        writer: (@MainActor (DailyMetrics, @escaping CoreDataManager.WriteAdmission) async throws -> Void)? = nil
    ) -> DashboardViewModel {
        let store = ownedStore!
        return DashboardViewModel(
            healthSyncCoordinator: MockHealthSyncCoordinator(),
            todayStepCountLoader: todayLoader,
            dailyStepLoader: loader ?? { owner, date in
                await store.fetchDailyMetrics(for: owner, date: date)?.toDailyMetrics()
            },
            dailyStepWriter: writer ?? { metrics, admission in
                try await store.saveDailyMetricsAndWait(metrics, userId: metrics.userId, writeAdmission: admission)
            },
            stepSyncTrigger: { self.syncTriggers += 1 }
        )
    }

    private func ownedSync() -> RealtimeSyncManager {
        let sync = RealtimeSyncManager(
            coreDataManager: ownedStore, authManager: ownedAuth, productAPIClient: ProductAPIClient()
        )
        sync.isOnline = false
        return sync
    }

    private func seedOwnedRow() async throws -> CachedDailyMetrics {
        let date = Date()
        let metrics = DailyMetrics(
            id: "owned-step-row", userId: "dashboard-owner-A", date: date, steps: 111,
            notes: "keep-note", createdAt: date, updatedAt: date
        )
        try await ownedStore.saveDailyMetricsAndWait(metrics, userId: metrics.userId)
        let fetched = await ownedStore.fetchDailyMetrics(for: metrics.userId, date: date)
        let row = try XCTUnwrap(fetched)
        row.isSynced = true
        row.syncStatus = "synced"
        try ownedStore.viewContext.save()
        return row
    }

    private func snapshot(_ row: CachedDailyMetrics) -> NSDictionary {
        row.dictionaryWithValues(forKeys: Array(row.entity.attributesByName.keys)) as NSDictionary
    }

    func testLateDashboardTodayResultCannotBeRelabelledForReplacementAccount() async throws {
        let gate = HeldDashboardStepOperation<Int>()
        let dashboard = ownedDashboard(todayLoader: { await gate.wait() })
        let task = Task { await dashboard.syncStepsFromHealthKit(authManager: ownedAuth, realtimeSyncManager: ownedSync()) }
        defer { gate.complete(0) }
        await fulfillment(of: [gate.started], timeout: 3)
        setOwnedAccount("dashboard-owner-B")
        gate.complete(4_321)
        await task.value
        let rowsA = await ownedStore.fetchDailyMetrics(for: "dashboard-owner-A")
        let rowsB = await ownedStore.fetchDailyMetrics(for: "dashboard-owner-B")
        XCTAssertTrue(rowsA.isEmpty)
        XCTAssertTrue(rowsB.isEmpty)
        XCTAssertNil(dashboard.dailyMetrics)
        XCTAssertEqual(syncTriggers, 0)
    }

    private func assertHeldDashboardLoadIsRejected(replace: () -> Void) async throws {
        let row = try await seedOwnedRow()
        let before = snapshot(row)
        let gate = HeldDashboardStepOperation<DailyMetrics>()
        let dashboard = ownedDashboard(loader: { _, _ in await gate.wait() })
        let task = Task {
            try await dashboard.updateStepCount(steps: 4_321, authManager: ownedAuth, realtimeSyncManager: ownedSync())
        }
        defer { gate.complete(row.toDailyMetrics()) }
        await fulfillment(of: [gate.started], timeout: 3)
        replace()
        gate.complete(row.toDailyMetrics())
        await assertRejected(task)
        XCTAssertEqual(snapshot(row), before)
        let rowsB = await ownedStore.fetchDailyMetrics(for: "dashboard-owner-B")
        XCTAssertTrue(rowsB.isEmpty)
        XCTAssertFalse(ownedStore.viewContext.hasChanges)
        XCTAssertNil(dashboard.dailyMetrics)
        XCTAssertEqual(syncTriggers, 0)
    }

    func testHeldDashboardLoadCannotWriteAfterAccountSwitch() async throws {
        try await assertHeldDashboardLoadIsRejected { setOwnedAccount("dashboard-owner-B") }
    }

    func testHeldDashboardLoadCannotWriteAfterSameAccountRelogin() async throws {
        try await assertHeldDashboardLoadIsRejected { setOwnedAccount("dashboard-owner-A") }
    }

    private func assertHeldDashboardSaveIsRejected(replace: () -> Void, cancel: Bool = false) async throws {
        let row = try await seedOwnedRow()
        let before = snapshot(row)
        let gate = HeldDashboardStepOperation<Bool>()
        let store = try XCTUnwrap(ownedStore)
        let dashboard = ownedDashboard(writer: { metrics, admission in
            _ = await gate.wait()
            try await store.saveDailyMetricsAndWait(metrics, userId: metrics.userId, writeAdmission: admission)
        })
        let task = Task {
            try await dashboard.updateStepCount(steps: 4_321, authManager: ownedAuth, realtimeSyncManager: ownedSync())
        }
        defer { gate.complete(true) }
        await fulfillment(of: [gate.started], timeout: 3)
        replace()
        if cancel { task.cancel() }
        gate.complete(true)
        await assertRejected(task)
        XCTAssertEqual(snapshot(row), before)
        let rowsB = await store.fetchDailyMetrics(for: "dashboard-owner-B")
        XCTAssertTrue(rowsB.isEmpty)
        XCTAssertFalse(store.viewContext.hasChanges)
        XCTAssertNil(dashboard.dailyMetrics)
        XCTAssertEqual(syncTriggers, 0)
    }

    private func assertRejected(_ task: Task<Void, Error>) async {
        do {
            try await task.value
            XCTFail("A stale or cancelled dashboard operation must be rejected")
        } catch {
            XCTAssertTrue(error is HealthKitError || error is CancellationError)
        }
    }

    func testHeldDashboardSaveCannotMutateAfterAccountSwitch() async throws {
        try await assertHeldDashboardSaveIsRejected { setOwnedAccount("dashboard-owner-B") }
    }

    func testHeldDashboardSaveCannotMutateAfterLogout() async throws {
        try await assertHeldDashboardSaveIsRejected {
            ownedAuth.authSession = nil
            ownedAuth.currentUser = nil
        }
    }

    func testHeldDashboardSaveCannotMutateAfterSameAccountRelogin() async throws {
        try await assertHeldDashboardSaveIsRejected { setOwnedAccount("dashboard-owner-A") }
    }

    func testCancelledDashboardSaveCannotMutate() async throws {
        try await assertHeldDashboardSaveIsRejected(replace: {}, cancel: true)
    }

    func testDashboardDoesNotPublishAfterOwnershipChangesFollowingSave() async throws {
        let gate = HeldDashboardStepOperation<Bool>()
        let store = try XCTUnwrap(ownedStore)
        let dashboard = ownedDashboard(writer: { metrics, admission in
            try await store.saveDailyMetricsAndWait(metrics, userId: metrics.userId, writeAdmission: admission)
            _ = await gate.wait()
        })
        let task = Task {
            try await dashboard.updateStepCount(steps: 4_321, authManager: ownedAuth, realtimeSyncManager: ownedSync())
        }
        defer { gate.complete(true) }
        await fulfillment(of: [gate.started], timeout: 3)
        setOwnedAccount("dashboard-owner-B")
        gate.complete(true)
        await assertRejected(task)
        let rowsA = await store.fetchDailyMetrics(for: "dashboard-owner-A")
        XCTAssertEqual(rowsA.first?.steps, 4_321, "The save was admitted while A still owned the session")
        let rowsB = await store.fetchDailyMetrics(for: "dashboard-owner-B")
        XCTAssertTrue(rowsB.isEmpty)
        XCTAssertNil(dashboard.dailyMetrics)
        XCTAssertEqual(syncTriggers, 0)
    }

    func testCurrentDashboardTodayResultPersistsBeforePublishingAndSync() async throws {
        let dashboard = ownedDashboard(todayLoader: { 4_321 })
        await dashboard.syncStepsFromHealthKit(authManager: ownedAuth, realtimeSyncManager: ownedSync())
        let rows = await ownedStore.fetchDailyMetrics(for: "dashboard-owner-A")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.steps, 4_321)
        XCTAssertEqual(rows.first?.userId, "dashboard-owner-A")
        XCTAssertEqual(dashboard.dailyMetrics?.steps, 4_321)
        XCTAssertEqual(dashboard.dailyMetrics?.id, rows.first?.id)
        XCTAssertEqual(syncTriggers, 1)
    }

    func testFailedDashboardStepSaveDoesNotPublishOrSync() async throws {
        let failure = NSError(domain: "SyntheticStepStore", code: 1)
        let dashboard = ownedDashboard(writer: { _, _ in throw failure })
        do {
            try await dashboard.updateStepCount(steps: 4_321, authManager: ownedAuth, realtimeSyncManager: ownedSync())
            XCTFail("A failed save must remain an error")
        } catch {
            XCTAssertEqual(error as NSError, failure)
        }
        XCTAssertNil(dashboard.dailyMetrics)
        XCTAssertEqual(syncTriggers, 0)
    }

    func testExistingDailyStepsRemainAfterDashboardRefresh() async throws {
        let userId = "synthetic-dashboard-steps-\(UUID().uuidString)"
        let metricId = "synthetic-dashboard-steps-row-\(UUID().uuidString)"
        let auth = isolatedAuth(userId: userId)
        let seeded = DailyMetrics(
            id: metricId,
            userId: userId,
            date: Date(),
            steps: 111,
            notes: "seed-steps",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await CoreDataManager.shared.saveDailyMetricsAndWait(seeded, userId: userId)
        let context = CoreDataManager.shared.viewContext
        let fetched = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        let saved = try XCTUnwrap(fetched)
        try await context.perform {
            saved.isSynced = true
            saved.syncStatus = "synced"
            if context.hasChanges {
                try context.save()
            }
        }
        await context.perform {
            context.reset()
        }

        let viewModel = dashboard()
        try await viewModel.updateStepCount(
            steps: 4_321,
            authManager: auth,
            realtimeSyncManager: offlineSync(auth: auth)
        )
        await context.perform {
            context.reset()
        }

        let reloaded = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        let stored = try XCTUnwrap(reloaded)
        XCTAssertEqual(stored.steps, 4_321, "dashboard refresh must persist today's steps")
        XCTAssertFalse(stored.isSynced, "updated steps must stay pending for sync")
        XCTAssertEqual(stored.userId, userId)
        XCTAssertEqual(stored.notes, "seed-steps")
        XCTAssertEqual(stored.id, metricId)
    }

    func testMissingDailyRowSavesStepsFromDashboardRefresh() async throws {
        let userId = "synthetic-dashboard-steps-new-\(UUID().uuidString)"
        let auth = isolatedAuth(userId: userId)
        let context = CoreDataManager.shared.viewContext
        let viewModel = dashboard()
        try await viewModel.updateStepCount(
            steps: 900,
            authManager: auth,
            realtimeSyncManager: offlineSync(auth: auth)
        )
        await context.perform {
            context.reset()
        }

        let created = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        let stored = try XCTUnwrap(created)
        XCTAssertEqual(stored.steps, 900)
        XCTAssertFalse(stored.isSynced)
        XCTAssertEqual(stored.userId, userId)
    }

    private func dashboard() -> DashboardViewModel {
        DashboardViewModel(
            healthKitManager: HealthKitManager.shared,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )
    }

    private func offlineSync(auth: AuthManager) -> RealtimeSyncManager {
        let sync = RealtimeSyncManager(
            coreDataManager: CoreDataManager.shared,
            authManager: auth,
            productAPIClient: ProductAPIClient()
        )
        sync.isOnline = false
        return sync
    }

    private func isolatedAuth(userId: String) -> AuthManager {
        let defaults = UserDefaults(suiteName: "lyb.dashboard.step.\(userId)") ?? .standard
        let auth = AuthManager(userDefaults: defaults)
        auth.authSession = .localFixture(subject: userId, email: "steps@example.invalid", accessToken: "synthetic")
        auth.currentUser = LocalUser(
            id: userId,
            email: "steps@example.invalid",
            name: "Step Fixture",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        return auth
    }
}
