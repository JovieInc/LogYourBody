//
// SyncQueueRetentionPreparedTests.swift
// LogYourBodyTests
//
import XCTest
import CoreData
@testable import LogYourBody

@MainActor
private final class PreparedSyncDeleteClient: ProductAPIClient {
    let started = XCTestExpectation(description: "Synthetic delete request started")
    var holdsResponse = false
    var heldRecordID: String?
    var deleteResults: [String: Result<Void, Error>] = [:]
    var upsertResponse: [[String: Any]] = []
    private(set) var deletedIDs: [String] = []
    private(set) var tokens: [String] = []
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    override func deleteData(table: String, id: String, token: String) async throws {
        deletedIDs.append(id)
        tokens.append(token)
        guard holdsResponse, heldRecordID == nil || heldRecordID == id else {
            try (deleteResults[id] ?? .failure(URLError(.networkConnectionLost))).get()
            return
        }
        started.fulfill()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if let result {
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func failHeldResponse() {
        complete(.failure(URLError(.networkConnectionLost)))
    }

    func succeedHeldResponse() {
        complete(.success(()))
    }

    private func complete(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
    }

    override func upsertData(table: String, data: Data, token: String) async throws -> [[String: Any]] {
        upsertResponse
    }
}

private final class PreparedSyncAnalyticsClient: AnalyticsClient {
    private(set) var events: [String] = []
    func start() {}
    func identify(userId: String?, properties: [String: String]?) {}
    func track(event: String, properties: [String: String]?) { events.append(event) }
    func reset() {}
    func isFeatureEnabled(flagKey: String) -> Bool { false }
}

private final class PreparedSyncNoNetworkProtocol: URLProtocol {
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let paths = [
            "/api/auth/mobile/sync/v1/body-metrics",
            "/api/auth/mobile/sync/v1/daily-metrics",
            "/api/auth/mobile/profile"
        ]
        guard request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token-A",
              let url = request.url, paths.contains(url.path),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let body = url.path.hasSuffix("/profile")
            ? "{\"profile\":{\"id\":\"synthetic-sync-A\"}}" : "{\"records\":[]}"
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Returns one stale sync payload. The first body-metrics read can switch accounts
/// before `pullLatestData` applies that payload.
private final class StalePullAccountSwitchProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var switchAccount: (@MainActor () -> Void)?
    private static var armed = false

    static func armSwitch(_ handler: @escaping @MainActor () -> Void) {
        lock.lock()
        switchAccount = handler
        armed = true
        lock.unlock()
    }

    static func disarm() {
        lock.lock()
        switchAccount = nil
        armed = false
        lock.unlock()
    }

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        if request.httpMethod == "GET", path.hasSuffix("/body-metrics"), let handler = Self.takeSwitch() {
            if Thread.isMainThread {
                MainActor.assumeIsolated(handler)
            } else {
                DispatchQueue.main.sync { MainActor.assumeIsolated(handler) }
            }
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let body = Self.payload(for: path)
        guard !body.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func takeSwitch() -> (@MainActor () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        guard armed else { return nil }
        armed = false
        return switchAccount
    }

    private static func payload(for path: String) -> String {
        if path.hasSuffix("/body-metrics") {
            return """
            {"records":[{"id":"stale-body-a","user_id":"synthetic-sync-A",\
            "weight":91.5,"weight_unit":"kg","notes":"stale-pull",\
            "date":"2026-01-15T12:00:00Z","data_source":"manual"}]}
            """
        }
        if path.hasSuffix("/daily-metrics") {
            return """
            {"records":[{"id":"stale-daily-a","user_id":"synthetic-sync-A",\
            "steps":4321,"notes":"stale-steps","date":"2026-01-15T12:00:00Z"}]}
            """
        }
        if path.hasSuffix("/profile") {
            return #"{"profile":{"id":"synthetic-sync-A","full_name":"Stolen Name"}}"#
        }
        return ""
    }
}

/// Uses isolated stores, synthetic auth and a transport that never reaches the network.
@MainActor
final class SyncQueueRetentionPreparedTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var coreData: CoreDataManager!
    private var storeDirectory: URL!
    private var auth: AuthManager!
    private var analytics: PreparedSyncAnalyticsClient!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "SyncQueueRetentionPreparedTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        storeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let store = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("fixture.sqlite"))
        store.type = NSSQLiteStoreType
        store.shouldAddStoreAsynchronously = false
        coreData = CoreDataManager(persistentStoreDescriptions: [store])
        // Successful sync exercises the real SQLite batch cleanup and an existing valid profile.
        try coreData.viewContext.performAndWait {
            let profile = CachedProfile(context: coreData.viewContext)
            profile.id = "synthetic-sync-A"
            profile.email = "sync-a@example.invalid"
            profile.createdAt = Date()
            profile.updatedAt = Date()
            profile.lastModified = Date()
            profile.isSynced = true
            profile.syncStatus = "synced"
            try coreData.viewContext.save()
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreparedSyncNoNetworkProtocol.self]
        auth = AuthManager(userDefaults: defaults, urlSession: URLSession(configuration: configuration))
        auth.authSession = .localFixture(
            subject: "synthetic-sync-A", email: "sync-a@example.invalid", accessToken: "synthetic-token-A"
        )
        auth.currentUser = LocalUser(
            id: "synthetic-sync-A", email: "sync-a@example.invalid", name: "Synthetic Sync",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        analytics = PreparedSyncAnalyticsClient()
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        if let coreData {
            coreData.viewContext.performAndWait { coreData.viewContext.reset() }
            let coordinator = coreData.persistentContainer.persistentStoreCoordinator
            for store in coordinator.persistentStores { try coordinator.remove(store) }
        }
        auth = nil
        coreData = nil
        defaults = nil
        analytics = nil
        if let storeDirectory { try FileManager.default.removeItem(at: storeDirectory) }
        storeDirectory = nil
        try super.tearDownWithError()
    }

    private func makeManager(_ client: PreparedSyncDeleteClient) -> RealtimeSyncManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreparedSyncNoNetworkProtocol.self]
        client.session = URLSession(configuration: configuration)
        return RealtimeSyncManager(
            coreDataManager: coreData, authManager: auth, productAPIClient: client,
            userDefaults: defaults, analyticsService: AnalyticsService(client: analytics)
        )
    }

    private func operation(
        retryCount: Int = 0, id: String = "synthetic-record-1", userId: String? = "synthetic-sync-A",
        type: RealtimeSyncManager.SyncOperation.OperationType = .delete
    ) -> RealtimeSyncManager.SyncOperation {
        RealtimeSyncManager.SyncOperation(
            id: id, userId: userId, type: type,
            data: Data(), tableName: "body_metrics",
            timestamp: Date(timeIntervalSince1970: 1_735_000_000), retryCount: retryCount
        )
    }

    func testQueuedOperationRemainsInMemoryWhileRequestHasNoAcknowledgment() async throws {
        let client = PreparedSyncDeleteClient()
        client.holdsResponse = true
        defer { client.failHeldResponse() }
        let manager = makeManager(client)
        manager.isOnline = false
        manager.queueOperation(operation())
        manager.isOnline = true
        let completed = expectation(description: "Synthetic sync completed")
        manager.syncAll { completed.fulfill() }
        await fulfillment(of: [client.started], timeout: 3)
        XCTAssertEqual(manager.pendingOperations.map(\.id), ["synthetic-record-1"])
        client.failHeldResponse()
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(manager.pendingOperations.map(\.id), ["synthetic-record-1"])
        manager.stopAutoSync()
    }

    func testManagerRecreationBeforeAcknowledgmentRetainsDurableOperation() async throws {
        let client = PreparedSyncDeleteClient()
        client.holdsResponse = true
        defer { client.failHeldResponse() }
        let manager = makeManager(client)
        manager.isOnline = false
        manager.queueOperation(operation())
        manager.isOnline = true
        let completed = expectation(description: "Synthetic sync completed")
        manager.syncAll { completed.fulfill() }
        await fulfillment(of: [client.started], timeout: 3)
        let recreated = makeManager(PreparedSyncDeleteClient())
        recreated.loadPendingOperations()
        XCTAssertEqual(recreated.pendingOperations.map(\.id), ["synthetic-record-1"])
        XCTAssertEqual(recreated.pendingOperations.first?.timestamp, operation().timestamp)
        client.failHeldResponse()
        await fulfillment(of: [completed], timeout: 3)
        manager.stopAutoSync()
    }

    func testThirdFailureRemainsRetryableWithoutAcknowledgment() async {
        let manager = makeManager(PreparedSyncDeleteClient())
        let failed = await manager.processPendingOperations([operation(retryCount: 2)], token: "synthetic-token")
        XCTAssertEqual(failed.map(\.id), ["synthetic-record-1"])
        XCTAssertEqual(failed.first?.retryCount, 3)
    }

    func testFirstFailureRetainsExistingRetryBehavior() async {
        let manager = makeManager(PreparedSyncDeleteClient())
        let failed = await manager.processPendingOperations([operation()], token: "synthetic-token")
        XCTAssertEqual(failed.map(\.id), ["synthetic-record-1"])
        XCTAssertEqual(failed.first?.retryCount, 1)
    }

    func testAcknowledgmentPreservesOtherAccountsAndUnownedOperations() async {
        let client = PreparedSyncDeleteClient()
        client.deleteResults["synthetic-record-1"] = .success(())
        let manager = makeManager(client)
        manager.isOnline = false
        manager.queueOperation(operation())
        manager.queueOperation(operation(id: "B-record", userId: "synthetic-sync-B"))
        manager.queueOperation(operation(id: "legacy-record", userId: nil))
        manager.isOnline = true
        await manager.syncAllAwaitingCompletion()
        XCTAssertEqual(manager.pendingOperations.map(\.id), ["B-record", "legacy-record"])
        XCTAssertEqual(client.deletedIDs, ["synthetic-record-1"])
        let recreated = makeManager(PreparedSyncDeleteClient())
        recreated.loadPendingOperations()
        XCTAssertEqual(recreated.pendingOperations.map(\.id), ["B-record", "legacy-record"])
    }

    func testPartialAcknowledgmentIsDurableBeforeLaterRequestReturns() async throws {
        let client = PreparedSyncDeleteClient()
        client.deleteResults["synthetic-record-1"] = .success(())
        client.holdsResponse = true
        client.heldRecordID = "second-record"
        defer { client.failHeldResponse() }
        let manager = makeManager(client)
        manager.isOnline = false
        manager.queueOperation(operation())
        manager.queueOperation(operation(id: "second-record"))
        manager.isOnline = true
        let completed = expectation(description: "Partial sync completed")
        manager.syncAll { completed.fulfill() }
        await fulfillment(of: [client.started], timeout: 3)
        let recreated = makeManager(PreparedSyncDeleteClient())
        recreated.loadPendingOperations()
        XCTAssertEqual(recreated.pendingOperations.map(\.id), ["second-record"])
        client.failHeldResponse()
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(manager.pendingOperations.map(\.id), ["second-record"])
        XCTAssertEqual(manager.pendingOperations.first?.retryCount, 1)
    }

    func testCapturedAcknowledgmentPreservesIdenticalNewSubmission() async throws {
        let client = PreparedSyncDeleteClient()
        client.holdsResponse = true
        defer { client.failHeldResponse() }
        let manager = makeManager(client)
        manager.isOnline = false
        let submitted = operation()
        manager.queueOperation(submitted)
        let capturedID = manager.pendingOperations.first?.queueID
        manager.isOnline = true
        let completed = expectation(description: "Captured acknowledgment completed")
        manager.syncAll { completed.fulfill() }
        await fulfillment(of: [client.started], timeout: 3)
        manager.isOnline = false
        manager.queueOperation(submitted)
        let newID = manager.pendingOperations.last?.queueID
        XCTAssertNotEqual(capturedID, newID)
        client.succeedHeldResponse()
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(manager.pendingOperations.count, 1)
        XCTAssertEqual(manager.pendingOperations.first?.queueID, newID)
    }

    private func switchToB() {
        auth.authSession = .localFixture(
            subject: "synthetic-sync-B", email: "sync-b@example.invalid", accessToken: "synthetic-token-B"
        )
        auth.currentUser = LocalUser(
            id: "synthetic-sync-B", email: "sync-b@example.invalid", name: "Synthetic B",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
    }

    func testScheduledSyncCannotBorrowReplacementAccountToken() async {
        let client = PreparedSyncDeleteClient()
        let manager = makeManager(client)
        manager.isOnline = false
        manager.queueOperation(operation())
        manager.isOnline = true
        let completed = expectation(description: "Scheduled stale sync completed")
        manager.syncAll { completed.fulfill() }
        switchToB()
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertTrue(client.deletedIDs.isEmpty)
        XCTAssertEqual(manager.pendingOperations.count, 1)
        XCTAssertEqual(auth.authSession?.accessToken, "synthetic-token-B")
        XCTAssertTrue(analytics.events.isEmpty)
        XCTAssertFalse(manager.isSyncing)
    }

    func testDepartingAccountAcknowledgmentStopsFurtherRequestsAndPreservesBState() async throws {
        let client = PreparedSyncDeleteClient()
        client.holdsResponse = true
        defer { client.failHeldResponse() }
        let manager = makeManager(client)
        manager.isOnline = false
        manager.queueOperation(operation())
        manager.queueOperation(operation(id: "second-record"))
        manager.queueOperation(operation(id: "B-record", userId: "synthetic-sync-B"))
        manager.isOnline = true
        let completed = expectation(description: "Departing account sync completed")
        manager.syncAll { completed.fulfill() }
        await fulfillment(of: [client.started], timeout: 3)
        switchToB()
        manager.syncStatus = .error("B-owned status")
        manager.error = "B-owned status"
        client.succeedHeldResponse()
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(client.deletedIDs, ["synthetic-record-1"])
        XCTAssertEqual(client.tokens, ["synthetic-token-A"])
        XCTAssertEqual(manager.pendingOperations.map(\.id), ["second-record", "B-record"])
        XCTAssertEqual(manager.syncStatus, .error("B-owned status"))
        XCTAssertEqual(manager.error, "B-owned status")
        XCTAssertNil(manager.lastSyncDate)
        XCTAssertTrue(analytics.events.isEmpty)
    }

    func testOldFailureAcrossExactSameSessionABADoesNotMutateReplacementState() async throws {
        let originalSession = auth.authSession
        let originalUser = auth.currentUser
        let client = PreparedSyncDeleteClient()
        client.holdsResponse = true
        defer { client.failHeldResponse() }
        let manager = makeManager(client)
        manager.isOnline = false
        manager.queueOperation(operation())
        manager.queueOperation(operation(id: "second-record"))
        manager.isOnline = true
        let completed = expectation(description: "ABA sync completed")
        manager.syncAll { completed.fulfill() }
        await fulfillment(of: [client.started], timeout: 3)
        switchToB()
        auth.authSession = originalSession
        auth.currentUser = originalUser
        manager.error = "Fresh A-owned status"
        client.failHeldResponse()
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(client.deletedIDs, ["synthetic-record-1"])
        XCTAssertEqual(manager.pendingOperations.count, 2)
        XCTAssertEqual(manager.error, "Fresh A-owned status")
        XCTAssertEqual(manager.consecutiveFailures, 0)
        XCTAssertTrue(analytics.events.isEmpty)
    }

    func testLegacyQueueMigrationPreservesOwnerAndStableQueueIdentifiers() async throws {
        let legacy = [operation(), operation(id: "B-record", userId: "synthetic-sync-B"),
                      operation(id: "legacy-record", userId: nil)]
        let encoded = try JSONEncoder().encode(legacy)
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        for index in rows.indices { rows[index].removeValue(forKey: "queueID") }
        defaults.set(try JSONSerialization.data(withJSONObject: rows), forKey: Constants.pendingSyncOperationsKey)
        let first = makeManager(PreparedSyncDeleteClient())
        first.loadPendingOperations()
        let identifiers = first.pendingOperations.compactMap(\.queueID)
        XCTAssertEqual(Set(identifiers).count, 3)
        XCTAssertEqual(first.pendingOperations.map(\.userId), legacy.map(\.userId))
        let recreated = makeManager(PreparedSyncDeleteClient())
        recreated.loadPendingOperations()
        XCTAssertEqual(recreated.pendingOperations.compactMap(\.queueID), identifiers)
    }

    func testThirdDispatchFailureRetainsDurableOperationAndRetryMetadata() async {
        let manager = makeManager(PreparedSyncDeleteClient())
        manager.isOnline = false
        manager.queueOperation(operation(retryCount: 2))
        let identifier = manager.pendingOperations.first?.queueID
        manager.isOnline = true
        await manager.syncAllAwaitingCompletion()
        let recreated = makeManager(PreparedSyncDeleteClient())
        recreated.loadPendingOperations()
        XCTAssertEqual(recreated.pendingOperations.count, 1)
        XCTAssertEqual(recreated.pendingOperations.first?.retryCount, 3)
        XCTAssertEqual(recreated.pendingOperations.first?.queueID, identifier)
        XCTAssertEqual(analytics.events, ["sync_failed"])
    }

    func testWrongRecordUpsertResponseDoesNotAcknowledgeQueuedChange() async throws {
        let client = PreparedSyncDeleteClient()
        client.upsertResponse = [["id": "other-record"]]
        let manager = makeManager(client)
        manager.isOnline = false
        manager.queueOperation(operation(type: .update))
        let queued = try XCTUnwrap(manager.pendingOperations.first)
        let failed = await manager.processPendingOperations([queued], token: "synthetic-token-A")
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(manager.pendingOperations.first?.queueID, queued.queueID)
        XCTAssertEqual(manager.pendingOperations.first?.retryCount, 1)
    }

    func testMatchingUpsertResponseAcknowledgesOnlyCapturedChange() async throws {
        let client = PreparedSyncDeleteClient()
        client.upsertResponse = [["id": "synthetic-record-1"]]
        let manager = makeManager(client)
        manager.isOnline = false
        manager.queueOperation(operation(type: .update))
        let queued = try XCTUnwrap(manager.pendingOperations.first)
        manager.queueOperation(operation(type: .update))
        let newerID = manager.pendingOperations.last?.queueID
        let failed = await manager.processPendingOperations([queued], token: "synthetic-token-A")
        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(manager.pendingOperations.count, 1)
        XCTAssertEqual(manager.pendingOperations.first?.queueID, newerID)
    }

    func testRetryCounterAtMaximumRemainsRetryableWithoutOverflow() async {
        let manager = makeManager(PreparedSyncDeleteClient())
        let failed = await manager.processPendingOperations([operation(retryCount: Int.max)], token: "synthetic-token")
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed.first?.retryCount, Int.max)
    }

    func testStaleUnauthorizedHandlerCannotRefreshOrClearReplacementSession() async throws {
        let ownership = try XCTUnwrap(auth.captureRequestSession())
        switchToB()
        await auth.handleProductAPIUnauthorized(for: ownership)
        XCTAssertEqual(auth.authSession?.accessToken, "synthetic-token-B")
        XCTAssertEqual(auth.currentUser?.id, "synthetic-sync-B")
    }

    func testOriginatingSessionExpiryReportsErrorWithoutDroppingQueuedWork() async throws {
        let client = PreparedSyncDeleteClient()
        let manager = makeManager(client)
        auth.authSession = ProductAuthSession(
            accessToken: "synthetic-expired", refreshToken: "synthetic-refresh",
            expiresAt: Date().addingTimeInterval(-120), subject: "synthetic-sync-A",
            email: "sync-a@example.invalid", name: "Synthetic Sync", issuedAt: Date()
        )
        let ownership = try XCTUnwrap(auth.captureRequestSession())
        manager.isOnline = false
        manager.queueOperation(operation())
        manager.isOnline = true
        await manager.syncAllAwaitingCompletion()
        guard case .error = manager.syncStatus else {
            return XCTFail("Originating session expiry must report the authentication failure")
        }
        XCTAssertTrue(auth.didExpireRequestSession(ownership))
        XCTAssertNil(auth.authSession)
        XCTAssertEqual(manager.pendingOperations.count, 1)
        XCTAssertEqual(manager.pendingOperations.first?.retryCount, 0)
        XCTAssertTrue(client.deletedIDs.isEmpty)
        XCTAssertEqual(analytics.events, ["sync_failed"])
        switchToB()
        XCTAssertFalse(auth.didExpireRequestSession(ownership))
    }

    func testStalePullDropsBodyDailyAndProfileAfterAccountSwitch() async throws {
        let manager = makeStalePullManager(switchAccounts: true)
        defer { StalePullAccountSwitchProtocol.disarm() }
        try await manager.pullLatestData(
            userId: "synthetic-sync-A",
            lastSync: Date(timeIntervalSince1970: 0),
            token: "synthetic-token-A"
        )
        let stored = await storedStalePull()
        XCTAssertNil(stored.body, "A stale body-metric response must not land after the account switch")
        XCTAssertNil(stored.daily, "A stale daily-metric response must not land after the account switch")
        XCTAssertNil(stored.profile, "A stale profile response must not rename the previous account")
        XCTAssertEqual(auth.currentUser?.id, "synthetic-sync-B")
    }

    func testOwningPullStillSavesBodyDailyAndProfile() async throws {
        let manager = makeStalePullManager(switchAccounts: false)
        defer { StalePullAccountSwitchProtocol.disarm() }
        try await manager.pullLatestData(
            userId: "synthetic-sync-A",
            lastSync: Date(timeIntervalSince1970: 0),
            token: "synthetic-token-A"
        )
        let stored = await storedStalePull()
        XCTAssertEqual(stored.body, "stale-pull")
        XCTAssertEqual(stored.daily, "stale-steps")
        XCTAssertEqual(stored.profile, "Stolen Name")
        XCTAssertEqual(auth.currentUser?.id, "synthetic-sync-A")
    }

    private func makeStalePullManager(switchAccounts: Bool) -> RealtimeSyncManager {
        let client = ProductAPIClient()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StalePullAccountSwitchProtocol.self]
        client.session = URLSession(configuration: configuration)
        if switchAccounts {
            StalePullAccountSwitchProtocol.armSwitch { self.switchToB() }
        } else {
            StalePullAccountSwitchProtocol.disarm()
        }
        let manager = RealtimeSyncManager(
            coreDataManager: coreData, authManager: auth, productAPIClient: client,
            userDefaults: defaults, analyticsService: AnalyticsService(client: analytics)
        )
        manager.isOnline = true
        return manager
    }

    private func storedStalePull() async -> (body: String?, daily: String?, profile: String?) {
        await coreData.viewContext.perform {
            let context = self.coreData.viewContext
            let bodyRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            bodyRequest.predicate = NSPredicate(format: "id == %@", "stale-body-a")
            bodyRequest.fetchLimit = 1
            let body = (try? context.fetch(bodyRequest))?.first?.notes
            let dailyRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            dailyRequest.predicate = NSPredicate(format: "id == %@", "stale-daily-a")
            dailyRequest.fetchLimit = 1
            let daily = (try? context.fetch(dailyRequest))?.first?.notes
            let profileRequest: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            profileRequest.predicate = NSPredicate(format: "id == %@", "synthetic-sync-A")
            profileRequest.fetchLimit = 1
            let profile = (try? context.fetch(profileRequest))?.first?.fullName
            return (body, daily, profile)
        }
    }
}
