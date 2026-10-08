import XCTest
import CoreData
import HealthKit
@testable import LogYourBody

final class HealthImportNoNetworkProtocol: URLProtocol {
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    }
    override func stopLoading() {}
}

@MainActor
final class HeldWeightImportQuery {
    let started = XCTestExpectation(description: "Synthetic weight query started")
    private(set) var hasStarted = false
    private var continuation: CheckedContinuation<[HealthKitWeightImportSample], Never>?
    private var result: [HealthKitWeightImportSample]?

    func fetch() async -> [HealthKitWeightImportSample] {
        hasStarted = true
        started.fulfill()
        return await withCheckedContinuation { continuation in
            if let result { continuation.resume(returning: result) } else { self.continuation = continuation }
        }
    }

    func complete(_ samples: [HealthKitWeightImportSample]) {
        guard result == nil else { return }
        result = samples
        continuation?.resume(returning: samples)
        continuation = nil
    }
}

@MainActor
final class HeldStepHistoryQuery {
    let started = XCTestExpectation(description: "Synthetic step history query started")
    private var continuation: CheckedContinuation<[(stepCount: Int, date: Date)], Never>?
    private var result: [(stepCount: Int, date: Date)]?

    func fetch() async throws -> [(stepCount: Int, date: Date)] {
        started.fulfill()
        return await withCheckedContinuation { continuation in
            if let result {
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func complete(_ samples: [(stepCount: Int, date: Date)]) {
        guard result == nil else { return }
        result = samples
        continuation?.resume(returning: samples)
        continuation = nil
    }
}

/// Synthetic samples use an isolated in-memory store; no live HealthKit or provider transport executes.
@MainActor
final class HealthKitImportOwnershipTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var auth: AuthManager!
    private var coreData: CoreDataManager!
    private var completedOwners: [String] = []
    private var syncTriggers = 0

    override func setUpWithError() throws {
        suiteName = "HealthKitImportOwnershipTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        auth = AuthManager(userDefaults: defaults, urlSession: URLSession(configuration: configuration))
        setAccount("synthetic-health-A")
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        coreData = CoreDataManager(persistentStoreDescriptions: [store])
        completedOwners = []
        syncTriggers = 0
        try super.setUpWithError()
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        auth = nil
        coreData = nil
        defaults = nil
        super.tearDown()
    }

    private func setAccount(_ subject: String) {
        auth.authSession = .localFixture(subject: subject, email: "health@example.invalid", accessToken: "synthetic")
        auth.currentUser = LocalUser(
            id: subject, email: "health@example.invalid", name: "Synthetic Health",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
    }

    private func manager(
        query: HeldWeightImportQuery? = nil,
        stepQuery: HeldStepHistoryQuery? = nil,
        earliestQuery: (() async throws -> Date?)? = nil,
        metricStore: ((BodyMetrics, @escaping CoreDataManager.WriteAdmission) async throws -> Void)? = nil,
        rawStore: (([HKRawSample]) async -> Void)? = nil
    ) -> HealthKitManager {
        let manager = HealthKitManager(
            userDefaults: defaults, authManager: auth, coreDataManager: coreData,
            weightImportQuery: { _, _ in
                if let query { return await query.fetch() }
                return []
            },
            bodyFatImportQuery: { _ in [] },
            stepHistoryQuery: stepQuery.map { held in { _ in try await held.fetch() } },
            earliestImportDateQuery: earliestQuery,
            syncTrigger: { self.syncTriggers += 1 },
            importCompletion: { owner in self.completedOwners.append(owner) },
            metricImportStore: metricStore,
            rawImportStore: rawStore ?? { _ in XCTFail("Injected query cannot create raw SDK samples") }
        )
        manager.isAuthorized = true
        return manager
    }

    private func assertHeldImportIsRejected(replace: () -> Void) async {
        let query = HeldWeightImportQuery()
        let manager = manager(query: query)
        let sample = HealthKitWeightImportSample(weight: 70, date: Date())
        let task = Task { try await manager.syncWeightFromHealthKitIncremental(days: 30) }
        defer { query.complete([]) }
        await fulfillment(of: [query.started], timeout: 3)
        replace()
        query.complete([sample])
        do { try await task.value } catch {
            XCTAssertTrue(error is HealthKitError || error is CancellationError)
        }
        let recordsA = await coreData.fetchBodyMetrics(for: "synthetic-health-A")
        let recordsB = await coreData.fetchBodyMetrics(for: "synthetic-health-B")
        XCTAssertTrue(recordsA.isEmpty)
        XCTAssertTrue(recordsB.isEmpty)
        XCTAssertEqual(syncTriggers, 0)
        XCTAssertTrue(completedOwners.isEmpty)
    }

    private func assertHeldStepImportIsRejected(replace: () -> Void) async {
        let query = HeldStepHistoryQuery()
        let manager = manager(stepQuery: query)
        let task = Task { try await manager.syncStepsFromHealthKit() }
        defer { query.complete([]) }
        await fulfillment(of: [query.started], timeout: 3)
        replace()
        query.complete([(stepCount: 4_321, date: Date())])
        do { try await task.value } catch {
            XCTAssertTrue(error is HealthKitError || error is CancellationError)
        }
        let recordsA = await coreData.fetchDailyMetrics(for: "synthetic-health-A")
        let recordsB = await coreData.fetchDailyMetrics(for: "synthetic-health-B")
        XCTAssertTrue(recordsA.isEmpty, "In-flight step import must not land for the starting account")
        XCTAssertTrue(recordsB.isEmpty, "In-flight step import must not land for the replacement account")
        XCTAssertEqual(syncTriggers, 0)
    }

    func testCurrentOwnerStepImportPreservesCountAndAccount() async throws {
        let query = HeldStepHistoryQuery()
        let manager = manager(stepQuery: query)
        let day = Date()
        let task = Task { try await manager.syncStepsFromHealthKit() }
        await fulfillment(of: [query.started], timeout: 3)
        query.complete([
            (stepCount: 4_321, date: day),
            (stepCount: 0, date: day.addingTimeInterval(-86_400))
        ])
        try await task.value
        let records = await coreData.fetchDailyMetrics(for: "synthetic-health-A")
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.userId, "synthetic-health-A")
        XCTAssertEqual(record.steps, 4_321)
        XCTAssertEqual(record.notes, "Imported from HealthKit")
        let recordsB = await coreData.fetchDailyMetrics(for: "synthetic-health-B")
        XCTAssertTrue(recordsB.isEmpty)
        XCTAssertEqual(syncTriggers, 1)
    }

    func testStepImportDoesNotLandWhenAnotherAccountOwnsHealthSync() async {
        defaults.set("synthetic-health-A", forKey: HealthKitAccountSyncPolicy.accountIdKey)
        setAccount("synthetic-health-B")
        let query = HeldStepHistoryQuery()
        query.complete([(stepCount: 4_321, date: Date())])
        let manager = manager(stepQuery: query)

        do {
            try await manager.syncStepsFromHealthKit()
            XCTFail("A different account must not import HealthKit steps")
        } catch {
            XCTAssertTrue(error is HealthKitError)
        }

        let recordsA = await coreData.fetchDailyMetrics(for: "synthetic-health-A")
        let recordsB = await coreData.fetchDailyMetrics(for: "synthetic-health-B")
        XCTAssertTrue(recordsA.isEmpty)
        XCTAssertTrue(recordsB.isEmpty)
        XCTAssertEqual(syncTriggers, 0)
    }

    func testBoundAccountCanStillImportItsOwnSteps() async throws {
        defaults.set("synthetic-health-A", forKey: HealthKitAccountSyncPolicy.accountIdKey)
        let query = HeldStepHistoryQuery()
        let manager = manager(stepQuery: query)
        let day = Date()
        let task = Task { try await manager.syncStepsFromHealthKit() }
        await fulfillment(of: [query.started], timeout: 3)
        query.complete([(stepCount: 2_048, date: day)])
        try await task.value
        let records = await coreData.fetchDailyMetrics(for: "synthetic-health-A")
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.userId, "synthetic-health-A")
        XCTAssertEqual(record.steps, 2_048)
        let recordsB = await coreData.fetchDailyMetrics(for: "synthetic-health-B")
        XCTAssertTrue(recordsB.isEmpty)
    }

    func testHeldStepHistoryCannotImportUnderReplacementAccount() async {
        await assertHeldStepImportIsRejected { setAccount("synthetic-health-B") }
    }

    func testHeldStepHistoryCannotImportAfterSameAccountRelogin() async {
        let originalSession = auth.authSession
        let originalUser = auth.currentUser
        await assertHeldStepImportIsRejected {
            auth.authSession = nil
            auth.currentUser = nil
            auth.authSession = originalSession
            auth.currentUser = originalUser
        }
    }

    func testHeldWeightQueryCannotImportUnderReplacementAccount() async {
        await assertHeldImportIsRejected { setAccount("synthetic-health-B") }
    }

    func testHeldWeightQueryCannotImportAfterSameAccountRelogin() async {
        let originalSession = auth.authSession
        let originalUser = auth.currentUser
        await assertHeldImportIsRejected {
            auth.authSession = nil
            auth.currentUser = nil
            auth.authSession = originalSession
            auth.currentUser = originalUser
        }
    }

    func testSaveCannotRelabelDepartingMetricForReplacementAccount() async {
        let date = Date()
        let metrics = BodyMetrics(
            id: "synthetic-health-record", userId: "synthetic-health-A", date: date,
            weight: 70, weightUnit: "kg", bodyFatPercentage: nil, bodyFatMethod: nil,
            muscleMass: nil, boneMass: nil, notes: nil, photoUrl: nil,
            dataSource: BodyMetricSource.healthKit.rawValue, createdAt: date, updatedAt: date
        )
        let manager = manager()
        setAccount("synthetic-health-B")
        do {
            try await manager.saveBodyMetrics(metrics)
            XCTFail("A metric must not be saved after B replaces its owner")
        } catch {
            XCTAssertTrue(error is HealthKitError || error is CancellationError)
        }
        let recordsB = await coreData.fetchBodyMetrics(for: "synthetic-health-B")
        XCTAssertTrue(recordsB.isEmpty)
        XCTAssertEqual(syncTriggers, 0)
    }

    func testCurrentOwnerImportPreservesMetadataAndDeduplicatesWithinLoggedHour() async throws {
        let manager = manager()
        let date = Date()
        let metadata = BodyMetricSourceMetadata(vendor: "apple_health", sampleId: "synthetic-weight")
        let sample = HealthKitWeightImportSample(weight: 70, date: date, sourceMetadata: metadata)
        let bodyFat = HealthKitBodyFatImportSample(
            percentage: 20, date: date,
            sourceMetadata: BodyMetricSourceMetadata(vendor: "apple_health", sampleId: "synthetic-fat")
        )
        let first = await manager.processBatchHealthKitData(weightHistory: [sample, sample], bodyFatHistory: [bodyFat])
        let second = await manager.processBatchHealthKitData(weightHistory: [sample], bodyFatHistory: [bodyFat])
        XCTAssertEqual(first.imported, 1)
        XCTAssertEqual(first.skipped, 1)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.skipped, 1)
        let records = await coreData.fetchAllBodyMetrics(for: "synthetic-health-A")
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.userId, "synthetic-health-A")
        XCTAssertEqual(record.weight, 70)
        XCTAssertEqual(record.bodyFatPercentage, 20)
        XCTAssertEqual(record.localDate, BodyMetricLocalDate.key(for: date))
        XCTAssertEqual(record.sourceMetadata?.sampleId, "synthetic-weight")
        XCTAssertEqual(record.sourceMetadata?.bodyFatSampleId, "synthetic-fat")
        XCTAssertEqual(completedOwners, ["synthetic-health-A"])
        XCTAssertEqual(syncTriggers, 1)
    }

    private func metric() -> BodyMetrics {
        let date = Date()
        return BodyMetrics(
            id: UUID().uuidString, userId: "synthetic-health-A", date: date,
            weight: 70, weightUnit: "kg", bodyFatPercentage: nil, bodyFatMethod: nil,
            muscleMass: nil, boneMass: nil, notes: nil, photoUrl: nil,
            dataSource: BodyMetricSource.healthKit.rawValue, createdAt: date, updatedAt: date
        )
    }

    private func assertQueuedStoreRejects(replace: () -> Void, cancel: Bool = false) async throws {
        let gate = HeldWeightImportQuery()
        let store = try XCTUnwrap(coreData)
        let manager = manager(metricStore: { metrics, admission in
            _ = await gate.fetch()
            try await store.saveBodyMetricsAndWait(
                metrics, userId: metrics.userId, writeAdmission: admission
            )
        })
        let metrics = metric()
        let task = Task { try await manager.saveBodyMetrics(metrics) }
        defer { gate.complete([]) }
        await fulfillment(of: [gate.started], timeout: 3)
        replace()
        if cancel { task.cancel() }
        gate.complete([])
        do {
            try await task.value
            XCTFail("Queued write must reject stale or cancelled admission")
        } catch {
            XCTAssertTrue(error is HealthKitError || error is CancellationError)
        }
        let recordsA = await store.fetchBodyMetrics(for: "synthetic-health-A")
        let recordsB = await store.fetchBodyMetrics(for: "synthetic-health-B")
        XCTAssertTrue(recordsA.isEmpty)
        XCTAssertTrue(recordsB.isEmpty)
        XCTAssertEqual(syncTriggers, 0)
    }

    func testReplacementBeforeRealCoreDataWriteRejectsWithoutMutation() async throws {
        try await assertQueuedStoreRejects { setAccount("synthetic-health-B") }
    }

    func testCancellationBeforeRealCoreDataWriteRejectsWithoutMutation() async throws {
        try await assertQueuedStoreRejects(replace: {}, cancel: true)
    }

    func testCancelledHeldWeightQueryCannotImportForCurrentAccount() async {
        let query = HeldWeightImportQuery()
        let manager = manager(query: query)
        let task = Task { try await manager.syncWeightFromHealthKitIncremental(days: 30) }
        defer { query.complete([]) }
        await fulfillment(of: [query.started], timeout: 3)
        task.cancel()
        query.complete([HealthKitWeightImportSample(weight: 70, date: Date())])
        do {
            try await task.value
            XCTFail("Cancelled query must reject its import")
        } catch {
            XCTAssertTrue(error is CancellationError || error is HealthKitError)
        }
        let records = await coreData.fetchBodyMetrics(for: "synthetic-health-A")
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(syncTriggers, 0)
        XCTAssertTrue(completedOwners.isEmpty)
    }

    private func sdkSample() -> HKQuantitySample {
        let date = Date()
        return HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 70),
            start: date, end: date, metadata: ["synthetic_metadata": "retained"]
        )
    }

    func testRawTaskCannotRelabelCapturedSamplesAfterReplacement() async throws {
        var received: [HKRawSample] = []
        let manager = manager(rawStore: { samples in await MainActor.run { received += samples } })
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        let task = try XCTUnwrap(manager.persistHealthKitSamples(
            [sdkSample()], unit: .gramUnit(with: .kilo), ownership: ownership
        ))
        setAccount("synthetic-health-B")
        await task.value
        XCTAssertTrue(received.isEmpty)
    }

    func testCurrentOwnerRawConversionPreservesOwnerUUIDAndMetadata() async throws {
        var received: [HKRawSample] = []
        let manager = manager(rawStore: { samples in await MainActor.run { received += samples } })
        let sample = sdkSample()
        let task = try XCTUnwrap(manager.persistHealthKitSamples(
            [sample], unit: .gramUnit(with: .kilo), ownership: try XCTUnwrap(auth.captureAccountSession())
        ))
        await task.value
        let raw = try XCTUnwrap(received.first)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(raw.userId, "synthetic-health-A")
        XCTAssertEqual(raw.hkUUID, sample.uuid.uuidString)
        XCTAssertEqual(raw.value, 70)
        XCTAssertEqual(raw.metadata?["synthetic_metadata"], "retained")
    }

    func testRawDeduplicationPreservesOtherAccountsSharingHealthKitUUID() async throws {
        let date = Date()
        func raw(owner: String) -> HKRawSample {
            HKRawSample(
                id: UUID().uuidString, userId: owner, hkUUID: "synthetic-shared-hk-uuid",
                quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue, value: 70, unit: "kg",
                startDate: date, endDate: date, sourceName: "Synthetic", sourceBundleId: nil,
                deviceManufacturer: nil, deviceModel: nil, deviceHardwareVersion: nil,
                deviceFirmwareVersion: nil, deviceSoftwareVersion: nil, deviceLocalIdentifier: nil,
                deviceUDI: nil, metadata: nil, createdAt: date, updatedAt: date
            )
        }
        await coreData.saveHKSamples([raw(owner: "synthetic-health-B")])
        await coreData.saveHKSamples([raw(owner: "synthetic-health-A")])
        let rows = try await coreData.viewContext.perform { [coreData] in
            try coreData!.viewContext.fetch(CachedHKSample.fetchRequest()).map { $0.userId ?? "" }
        }
        XCTAssertEqual(Set(rows), ["synthetic-health-A", "synthetic-health-B"])
        XCTAssertEqual(rows.count, 2)
    }

    func testHeldHistoryCannotCompleteOrClearReplacementImport() async throws {
        let first = HeldWeightImportQuery()
        let replacement = HeldWeightImportQuery()
        var queries = 0
        let manager = manager(earliestQuery: {
            queries += 1
            _ = await (queries == 1 ? first : replacement).fetch()
            return Date()
        })
        let scheduled = await manager.triggerFullHealthKitSyncIfNeeded(imported: 0)
        let firstTask = try XCTUnwrap(scheduled)
        defer { first.complete([]); replacement.complete([]) }
        // Register a priority-inheriting waiter before observing the detached background import.
        let joinerStarted = expectation(description: "Scheduled history waiter registered")
        let firstJoiner = Task(priority: .userInitiated) {
            joinerStarted.fulfill()
            await firstTask.value
        }
        await fulfillment(of: [joinerStarted], timeout: 3)
        await fulfillment(of: [first.started], timeout: 3)
        guard first.hasStarted else {
            firstTask.cancel()
            first.complete([])
            await firstJoiner.value
            return
        }
        setAccount("synthetic-health-B")
        let replacementTask = Task(priority: .userInitiated) { await manager.syncAllHistoricalHealthKitData() }
        await fulfillment(of: [replacement.started], timeout: 3)
        guard replacement.hasStarted else {
            firstTask.cancel()
            replacementTask.cancel()
            first.complete([])
            replacement.complete([])
            await firstJoiner.value
            _ = await replacementTask.value
            return
        }
        let replacementOperation = manager.historicalImportOperation
        first.complete([])
        await firstJoiner.value
        XCTAssertTrue(manager.isImporting)
        XCTAssertEqual(manager.historicalImportOperation, replacementOperation)
        XCTAssertEqual(manager.importStatus, "Starting import...")
        XCTAssertFalse(defaults.bool(forKey: HealthKitDefaultsKey.fullSyncCompleted.scoped(with: "synthetic-health-A")))
        XCTAssertFalse(defaults.bool(forKey: HealthKitDefaultsKey.fullSyncCompleted.scoped(with: "synthetic-health-B")))
        replacement.complete([])
        let succeeded = await replacementTask.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(syncTriggers, 0)
    }

    func testCancelledHeldHistoryReleasesItsOwnImportIndicator() async {
        let gate = HeldWeightImportQuery()
        let manager = manager(earliestQuery: { _ = await gate.fetch(); return Date() })
        let task = Task { await manager.syncAllHistoricalHealthKitData() }
        defer { gate.complete([]) }
        await fulfillment(of: [gate.started], timeout: 3)
        XCTAssertTrue(manager.isImporting)
        task.cancel()
        gate.complete([])
        let succeeded = await task.value
        XCTAssertFalse(succeeded)
        XCTAssertFalse(manager.isImporting)
        XCTAssertNil(manager.historicalImportOperation)
        XCTAssertEqual(manager.importStatus, "")
        XCTAssertEqual(syncTriggers, 0)
    }

    func testCancelledOlderHistoryCannotClearNewerSameAccountImport() async {
        let first = HeldWeightImportQuery()
        let next = HeldWeightImportQuery()
        var queries = 0
        let manager = manager(earliestQuery: {
            queries += 1
            _ = await (queries == 1 ? first : next).fetch()
            return Date()
        })
        let firstTask = Task { await manager.syncAllHistoricalHealthKitData() }
        defer { first.complete([]); next.complete([]) }
        await fulfillment(of: [first.started], timeout: 3)
        let nextTask = Task { await manager.syncAllHistoricalHealthKitData() }
        await fulfillment(of: [next.started], timeout: 3)
        let nextOperation = manager.historicalImportOperation
        firstTask.cancel()
        first.complete([])
        let firstSucceeded = await firstTask.value
        XCTAssertFalse(firstSucceeded)
        XCTAssertTrue(manager.isImporting)
        XCTAssertEqual(manager.historicalImportOperation, nextOperation)
        next.complete([])
        let nextSucceeded = await nextTask.value
        XCTAssertTrue(nextSucceeded)
    }

    func testCurrentHistoryMarksOnlyItsCapturedOwnerCompleted() async throws {
        let manager = manager(earliestQuery: { Date() })
        let scheduled = await manager.triggerFullHealthKitSyncIfNeeded(imported: 0)
        let task = try XCTUnwrap(scheduled)
        await task.value
        XCTAssertTrue(defaults.bool(forKey: HealthKitDefaultsKey.fullSyncCompleted.scoped(with: "synthetic-health-A")))
        XCTAssertFalse(defaults.bool(forKey: HealthKitDefaultsKey.fullSyncCompleted.scoped(with: "synthetic-health-B")))
        XCTAssertEqual(manager.importProgress, 1)
        XCTAssertEqual(syncTriggers, 0)
    }

    func testStaleHistoryAdmissionCannotStartEarliestQuery() async throws {
        var queries = 0
        let manager = manager(earliestQuery: { queries += 1; return Date() })
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        setAccount("synthetic-health-B")
        let succeeded = await manager.syncAllHistoricalHealthKitData(ownership: ownership)
        XCTAssertFalse(succeeded)
        XCTAssertEqual(queries, 0)
        XCTAssertFalse(manager.isImporting)
    }
}
