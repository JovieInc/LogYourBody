import CoreData
import HealthKit
import XCTest
@testable import LogYourBody

@MainActor
final class MetricSourceAdapterTests: XCTestCase {
    private let suiteName = "MetricSourceAdapterTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!
    private var auth: AuthManager!
    private var store: CoreDataManager!
    private var syncCount = 0
    private var guardAllowed = true

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        auth = AuthManager()
        setAccount("synthetic-adapter-A")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        store = CoreDataManager(persistentStoreDescriptions: [description])
        syncCount = 0
        guardAllowed = true
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        auth = nil
        store = nil
        try super.tearDownWithError()
    }

    func testCapabilitiesDefaultToFalseIncludingProtocolDefault() {
        XCTAssertEqual(DefaultMetricSourceAdapter().capabilities, MetricSourceCapabilities())
        for trigger in MetricSourceSyncTrigger.allCases {
            XCTAssertFalse(MetricSourceCapabilities().supports(trigger))
        }
    }

    func testSchedulerUsesOnlyEachCapabilityFlagForEveryCombination() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for mask in 0..<16 {
            let flags = (0..<4).map { mask & (1 << $0) != 0 }
            let capabilities = MetricSourceCapabilities(
                pushEvents: flags[0], incrementalPull: flags[1], scheduledPoll: flags[2], manualUpload: flags[3]
            )
            for (index, trigger) in MetricSourceSyncTrigger.allCases.enumerated() {
                let adapter = FakeMetricSourceAdapter(capabilities: capabilities)
                let result = try await MetricSourceScheduler.replay(adapter, triggeredBy: trigger, from: start)
                XCTAssertEqual(result, flags[index] ? true : nil)
                XCTAssertEqual(adapter.starts, flags[index] ? [start] : [])
                XCTAssertEqual(adapter.guardChecks, flags[index] ? 1 : 0)
            }
        }
    }

    func testSchedulerDeniesEntitlementOrCostBeforeReplay() async throws {
        let adapter = FakeMetricSourceAdapter(capabilities: MetricSourceCapabilities(scheduledPoll: true))
        adapter.denied = true
        do {
            _ = try await MetricSourceScheduler.replay(adapter, triggeredBy: .scheduledPoll)
            XCTFail("Denied polling must not run")
        } catch AdapterFixtureError.denied {
            XCTAssertTrue(adapter.starts.isEmpty)
        }
    }

    func testBodySpecOnlyDeclaresPullAndPollingAndRejectsPushWithoutRequests() async throws {
        let api = try FixtureMetricSourceBodySpecAPI()
        let adapter = bodySpec(api)
        XCTAssertEqual(adapter.capabilities, MetricSourceCapabilities(incrementalPull: true, scheduledPoll: true))
        let pushed = try await MetricSourceScheduler.replay(adapter, triggeredBy: .pushEvent)
        let uploaded = try await MetricSourceScheduler.replay(adapter, triggeredBy: .manualUpload)
        XCTAssertNil(pushed)
        XCTAssertNil(uploaded)
        let requests = await api.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testBodySpecReplayTwiceUsesPersistedReportKeyWithoutRewritingOrSyncingAgain() async throws {
        let api = try FixtureMetricSourceBodySpecAPI()
        let adapter = bodySpec(api)
        let initialSync = await adapter.lastSuccessfulSync
        XCTAssertNil(initialSync)
        let first = try await MetricSourceScheduler.replay(adapter, triggeredBy: .scheduledPoll)
        XCTAssertEqual(first?.importedCount, 1)
        let originalMetrics = await store.fetchAllBodyMetrics(for: "synthetic-adapter-A")
        let originalResults = await store.fetchDexaResults(for: "synthetic-adapter-A", limit: 10)
        let original = try XCTUnwrap(originalMetrics.first)
        let originalResult = try XCTUnwrap(originalResults.first)
        let summary = try FixtureMetricSourceBodySpecAPI.decode(
            BodySpecResultsListResponse.self, BodySpecAPIFixture.resultsJSON
        ).results[0]
        XCTAssertEqual(adapter.idempotencyKey(for: summary), originalResult.externalResultId)
        XCTAssertEqual(original.sourceMetadata?.externalResultId, adapter.idempotencyKey(for: summary))

        // A new importer has no in-memory dedup state. It must use the existing atomic storage transaction.
        let second = try await bodySpec(api).replay(from: nil)
        XCTAssertEqual(second.importedCount, 0)
        XCTAssertEqual(second.skippedCount, 1)
        XCTAssertEqual(second.failedCount, 0)
        let metrics = await store.fetchAllBodyMetrics(for: "synthetic-adapter-A")
        let results = await store.fetchDexaResults(for: "synthetic-adapter-A", limit: 10)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(metrics.first?.id, original.id)
        XCTAssertEqual(metrics.first?.updatedAt, original.updatedAt)
        XCTAssertEqual(results.first?.id, originalResult.id)
        XCTAssertEqual(results.first?.updatedAt, originalResult.updatedAt)
        XCTAssertEqual(syncCount, 1)
        let requests = await api.requests
        XCTAssertEqual(requests.filter { $0 == "composition" }.count, 1)
        let completed = await adapter.lastSuccessfulSync
        XCTAssertNotNil(completed)
    }

    func testBodySpecReplayBoundaryIsInclusiveAndDoesNotStopAtAnOlderPage() async throws {
        let api = try FixtureMetricSourceBodySpecAPI()
        let older = try FixtureMetricSourceBodySpecAPI.decode(
            BodySpecResultsListResponse.self, BodySpecAPIFixture.resultsNullOptionalsJSON
        ).results[0]
        let current = try FixtureMetricSourceBodySpecAPI.decode(
            BodySpecResultsListResponse.self, BodySpecAPIFixture.resultsJSON
        ).results[0]
        await api.setFirstPage(Array(repeating: older, count: 50))
        let result = try await bodySpec(api).replay(from: current.startTime)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        let requests = await api.requests
        XCTAssertEqual(requests.filter { $0.hasPrefix("list:") }, ["list:1", "list:2"])
    }

    func testBodySpecSameReportKeyCanImportForSeparateAccounts() async throws {
        let api = try FixtureMetricSourceBodySpecAPI()
        let adapter = bodySpec(api)
        _ = try await adapter.replay(from: nil)
        setAccount("synthetic-adapter-B")
        let secondAccount = try await adapter.replay(from: nil)
        XCTAssertEqual(secondAccount.importedCount, 1)
        let first = await store.fetchDexaResults(for: "synthetic-adapter-A", limit: 10)
        let second = await store.fetchDexaResults(for: "synthetic-adapter-B", limit: 10)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(first.first?.externalResultId, second.first?.externalResultId)
        XCTAssertNotEqual(first.first?.bodyMetricsId, second.first?.bodyMetricsId)
        XCTAssertEqual(syncCount, 2)
    }

    func testBodySpecCancellationAfterProviderResponseCannotWriteOrStampSync() async throws {
        let api = try FixtureMetricSourceBodySpecAPI(afterComposition: {
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let adapter = bodySpec(api)
        let task = Task { try await adapter.replay(from: nil) }
        let result = try await task.value
        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(syncCount, 0)
        let lastSync = await adapter.lastSuccessfulSync
        XCTAssertNil(lastSync)
        let metrics = await store.fetchAllBodyMetrics(for: "synthetic-adapter-A")
        XCTAssertTrue(metrics.isEmpty)
    }

    func testBodySpecGuardDeniesDirectReplayBeforeAnyProviderWork() async throws {
        let api = try FixtureMetricSourceBodySpecAPI()
        guardAllowed = false
        do {
            _ = try await bodySpec(api).replay(from: nil)
            XCTFail("Direct replay must enforce admission")
        } catch AdapterFixtureError.denied {
            let requests = await api.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testBodySpecGuardRevocationBeforeCommitWritesNoRowsOrSyncReceipt() async throws {
        let api = try FixtureMetricSourceBodySpecAPI(afterComposition: { self.guardAllowed = false })
        let adapter = bodySpec(api)
        let result = try await adapter.replay(from: nil)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.importedCount, 0)
        let metrics = await store.fetchAllBodyMetrics(for: "synthetic-adapter-A")
        let results = await store.fetchDexaResults(for: "synthetic-adapter-A", limit: 10)
        XCTAssertTrue(metrics.isEmpty)
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(syncCount, 0)
        let lastSync = await adapter.lastSuccessfulSync
        XCTAssertNil(lastSync)
    }

    func testBodySpecFailedReplayPreservesSuccessfulReceiptAndScopesItToAccount() async throws {
        let api = try FixtureMetricSourceBodySpecAPI()
        let adapter = bodySpec(api)
        _ = try await adapter.replay(from: nil)
        let completed = await adapter.lastSuccessfulSync
        XCTAssertNotNil(completed)
        await api.failListing()
        let failed = try await adapter.replay(from: nil)
        XCTAssertEqual(failed.failedCount, 1)
        let afterFailure = await adapter.lastSuccessfulSync
        XCTAssertEqual(afterFailure, completed)
        let recreated = await bodySpec(api).lastSuccessfulSync
        XCTAssertEqual(recreated, completed)
        setAccount("synthetic-adapter-B")
        let otherAccount = await adapter.lastSuccessfulSync
        XCTAssertNil(otherAccount)
        auth.currentUser = nil
        auth.authSession = nil
        let signedOut = await adapter.lastSuccessfulSync
        XCTAssertNil(signedOut)
    }

    func testBodySpecAccountSwitchDuringReplayDoesNotCompleteOrStampEitherAccount() async throws {
        let api = try FixtureMetricSourceBodySpecAPI(afterComposition: { self.setAccount("synthetic-adapter-B") })
        let adapter = bodySpec(api)
        let result = try await adapter.replay(from: nil)
        XCTAssertTrue(result.wasCancelled)
        let accountB = await adapter.lastSuccessfulSync
        XCTAssertNil(accountB)
        setAccount("synthetic-adapter-A")
        let accountA = await adapter.lastSuccessfulSync
        XCTAssertNil(accountA)
        XCTAssertEqual(syncCount, 0)
    }

    func testHealthKitDeclaresObserverDeliveryAndUsesSampleUUID() throws {
        let adapter = healthKit()
        XCTAssertEqual(adapter.capabilities, MetricSourceCapabilities(pushEvents: true, incrementalPull: true))
        let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .bodyMass))
        let sample = HKQuantitySample(
            type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80),
            start: Date(), end: Date()
        )
        XCTAssertEqual(adapter.idempotencyKey(for: sample), sample.uuid.uuidString)
        XCTAssertEqual(adapter.sourceMetadata(from: sample).sampleId, adapter.idempotencyKey(for: sample))
    }

    func testHealthKitReplayUsesRequestedBoundaryAndRecordsAccountScopedCompletion() async throws {
        var requestedStart: Date?
        let start = Date().addingTimeInterval(-60)
        let adapter = healthKit { from, _ in requestedStart = from; return [] }
        let result = try await adapter.replay(from: start)
        XCTAssertTrue(result)
        XCTAssertEqual(requestedStart, start)
        let completed = await adapter.lastSuccessfulSync
        XCTAssertNotNil(completed)
        setAccount("synthetic-adapter-B")
        let otherAccount = await adapter.lastSuccessfulSync
        XCTAssertNil(otherAccount)
    }

    func testHealthKitDeniedGuardNeverQueriesOrStampsSync() async throws {
        var queried = false
        let adapter = healthKit { _, _ in queried = true; return [] }
        adapter.metricSourceSyncGuard = { throw AdapterFixtureError.denied }
        do {
            _ = try await adapter.replay(from: Date())
            XCTFail("HealthKit must enforce admission")
        } catch AdapterFixtureError.denied {
            XCTAssertFalse(queried)
            let lastSync = await adapter.lastSuccessfulSync
            XCTAssertNil(lastSync)
        }
    }

    func testHealthKitObserverPullRecordsCompletionAndPreservesItOnQueryFailure() async throws {
        var queryFails = false
        let adapter = healthKit { _, _ in
            if queryFails { throw AdapterFixtureError.denied }
            return []
        }
        try await adapter.syncWeightFromHealthKitIncremental()
        let completed = await adapter.lastSuccessfulSync
        XCTAssertNotNil(completed)
        queryFails = true
        do {
            try await adapter.syncWeightFromHealthKitIncremental()
            XCTFail("Failed query must not complete")
        } catch AdapterFixtureError.denied {
            let afterFailure = await adapter.lastSuccessfulSync
            XCTAssertEqual(afterFailure, completed)
        }
    }

    func testHealthKitWriteFailureCannotProduceSuccessfulReplayReceipt() async throws {
        let start = Date().addingTimeInterval(-60)
        let adapter = HealthKitManager(
            userDefaults: defaults, authManager: auth, coreDataManager: store,
            weightImportQuery: { _, _ in [HealthKitWeightImportSample(weight: 80, date: start)] },
            bodyFatImportQuery: { _ in [] }, earliestImportDateQuery: { start },
            metricImportStore: { _, _ in throw AdapterFixtureError.denied }, rawImportStore: { _ in },
            bodyFatOnlyImportEnabled: { false }
        )
        adapter.isAuthorized = true
        do {
            _ = try await adapter.replay(from: start)
            XCTFail("Persistence failure must fail replay")
        } catch HealthKitError.syncFailed {
            let lastSync = await adapter.lastSuccessfulSync
            XCTAssertNil(lastSync)
        }
        do {
            try await adapter.syncWeightFromHealthKitIncremental()
            XCTFail("Observer pull must propagate persistence failure too")
        } catch HealthKitError.syncFailed {
            let lastSync = await adapter.lastSuccessfulSync
            XCTAssertNil(lastSync)
        }
    }

    func testHealthKitBodyFatWriteFailureCannotProduceSuccessfulReplayReceipt() async throws {
        let start = Date().addingTimeInterval(-60)
        let adapter = HealthKitManager(
            userDefaults: defaults, authManager: auth, coreDataManager: store,
            weightImportQuery: { _, _ in [] },
            bodyFatImportQuery: { _ in
                [HealthKitBodyFatImportSample(
                    percentage: 20, date: start, sourceMetadata: BodyMetricSourceMetadata(
                        vendor: "apple_health", sampleId: "synthetic-fat-sample",
                        quantityType: HKQuantityTypeIdentifier.bodyFatPercentage.rawValue
                    )
                )]
            },
            metricImportStore: { _, _ in throw AdapterFixtureError.denied }, rawImportStore: { _ in },
            bodyFatOnlyImportEnabled: { true }
        )
        adapter.isAuthorized = true
        do {
            _ = try await adapter.replay(from: start)
            XCTFail("Body-fat persistence failure must fail replay")
        } catch HealthKitError.syncFailed {
            let lastSync = await adapter.lastSuccessfulSync
            XCTAssertNil(lastSync)
        }
    }

    private func bodySpec(_ api: FixtureMetricSourceBodySpecAPI) -> BodySpecDexaImporter {
        BodySpecDexaImporter(
            api: api, authManager: auth, coreDataManager: store, userDefaults: defaults,
            syncGuard: { if !self.guardAllowed { throw AdapterFixtureError.denied } },
            syncTrigger: { self.syncCount += 1 }
        )
    }

    private func healthKit(
        query: @escaping (Date, Date) async throws -> [HealthKitWeightImportSample] = { _, _ in [] }
    ) -> HealthKitManager {
        let adapter = HealthKitManager(
            userDefaults: defaults, authManager: auth, coreDataManager: store,
            weightImportQuery: query, bodyFatImportQuery: { _ in [] }, earliestImportDateQuery: { Date() },
            bodyFatOnlyImportEnabled: { false }
        )
        adapter.isAuthorized = true
        return adapter
    }

    private func setAccount(_ subject: String) {
        auth.authSession = .localFixture(subject: subject, email: "adapter@example.invalid", accessToken: "synthetic")
        auth.currentUser = LocalUser(
            id: subject, email: "adapter@example.invalid", name: "Synthetic Adapter", avatarUrl: nil,
            profile: nil, onboardingCompleted: true
        )
    }
}

private enum AdapterFixtureError: Error { case denied }

private struct DefaultMetricSourceAdapter: MetricSourceAdapter {
    var lastSuccessfulSync: Date? { nil }
    func idempotencyKey(for report: String) -> String { report }
    func checkEntitlementAndCost() async throws {}
    func replay(from startDate: Date?) async throws -> Bool { true }
}

private final class FakeMetricSourceAdapter: MetricSourceAdapter {
    let capabilities: MetricSourceCapabilities
    var lastSuccessfulSync: Date? { nil }
    var denied = false
    var guardChecks = 0
    var starts: [Date?] = []

    init(capabilities: MetricSourceCapabilities) { self.capabilities = capabilities }
    func idempotencyKey(for report: String) -> String { report }
    func checkEntitlementAndCost() async throws {
        guardChecks += 1
        if denied { throw AdapterFixtureError.denied }
    }
    func replay(from startDate: Date?) async throws -> Bool {
        starts.append(startDate)
        return true
    }
}

/// Reuses the recorded REST-shape fixtures from the API tests. No URLSession or provider account is used.
private actor FixtureMetricSourceBodySpecAPI: BodySpecDexaAPIClient {
    private let results: BodySpecResultsListResponse
    private let scan: BodySpecDexaScanInfoResponse
    private let composition: BodySpecDexaCompositionResponse
    private let afterComposition: @MainActor () -> Void
    private var firstPage: [BodySpecResultSummary]?
    private var listingFails = false
    private(set) var requests: [String] = []

    init(afterComposition: @escaping @MainActor () -> Void = {}) throws {
        results = try Self.decode(BodySpecResultsListResponse.self, BodySpecAPIFixture.resultsJSON)
        scan = try Self.decode(BodySpecDexaScanInfoResponse.self, BodySpecAPIFixture.scanInfoJSON)
        composition = try Self.decode(BodySpecDexaCompositionResponse.self, BodySpecAPIFixture.compositionJSON)
        self.afterComposition = afterComposition
    }

    nonisolated static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(json.utf8))
    }

    func setFirstPage(_ results: [BodySpecResultSummary]) { firstPage = results }
    func failListing() { listingFails = true }
    func importSession(for ownership: AuthManager.ProfileSessionOwnership) -> BodySpecDexaImportSession {
        requests.append("session")
        return BodySpecDexaImportSession(api: self, admission: {})
    }
    func listResults(page: Int, pageSize: Int) throws -> BodySpecResultsListResponse {
        requests.append("list:\(page)")
        if listingFails { throw AdapterFixtureError.denied }
        if page == 1, let firstPage { return BodySpecResultsListResponse(results: firstPage) }
        return results
    }
    func getDexaScanInfo(resultId: String) -> BodySpecDexaScanInfoResponse {
        requests.append("scan")
        return scan
    }
    func getDexaComposition(resultId: String) async -> BodySpecDexaCompositionResponse {
        requests.append("composition")
        await afterComposition()
        return composition
    }
}
