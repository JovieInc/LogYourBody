import XCTest
@testable import LogYourBody

@MainActor
private final class SyntheticBodySpecBrowser: BodySpecAuthorizationSession {
    let url: URL
    let callback: (URL?, Error?) -> Void
    var starts = true
    var cancelCount = 0
    var onStart: (() -> Void)?

    init(url: URL, callback: @escaping (URL?, Error?) -> Void) { self.url = url; self.callback = callback }
    func start() -> Bool { onStart?(); return starts }
    func cancel() { cancelCount += 1; callback(nil, CancellationError()) }
    func complete() {
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
        var result = URLComponents(string: "lyb-test://oauth")!
        result.queryItems = [URLQueryItem(name: "state", value: state), URLQueryItem(name: "code", value: "synthetic-code")]
        callback(result.url, nil)
    }
}

@MainActor
private final class SyntheticBodySpecExchange {
    var continuation: CheckedContinuation<BodySpecStoredToken, Never>?
    let started: XCTestExpectation
    init(started: XCTestExpectation) { self.started = started }
    func run() async -> BodySpecStoredToken {
        await withCheckedContinuation { continuation in self.continuation = continuation; started.fulfill() }
    }
    func finish() { continuation?.resume(returning: syntheticBodySpecToken(owner: nil)); continuation = nil }
}

@MainActor
final class BodySpecConnectionLifecycleTests: XCTestCase {
    private var store: BodySpecMemoryTokenStore!
    private var account: BodySpecSyntheticAccount!
    private var browsers: [SyntheticBodySpecBrowser] = []
    private var started: XCTestExpectation!
    private var browserStarts = true
    private var exchangeCount = 0

    override func setUp() {
        super.setUp()
        store = BodySpecMemoryTokenStore()
        account = BodySpecSyntheticAccount()
        browsers = []
        started = nil
        browserStarts = true
        exchangeCount = 0
    }

    func testBrowserStartFalseCompletesWithoutInstallingConnection() async {
        browserStarts = false
        let manager = makeManager()
        let finished = expectation(description: "Failed start completed")
        let task = Task { @MainActor in
            defer { finished.fulfill() }
            do { try await manager.connect(); XCTFail("A browser that did not start cannot connect") } catch {}
        }
        await fulfillment(of: [started, finished], timeout: 2)
        // Also resolves the deliberate-red old behavior without leaving a suspended test task.
        browsers.first?.callback(nil, CancellationError())
        await task.value
        XCTAssertFalse(manager.isConnected)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(exchangeCount, 0)
    }

    func testAccountReplacementDuringBrowserCannotInstallToken() async {
        let manager = makeManager()
        let task = Task { try await manager.connect() }
        await fulfillment(of: [started], timeout: 2)
        account.ownership = .init(subject: "other-owner", generation: 2)
        browsers[0].complete()
        if case .success = await task.result { XCTFail("Old owner authorization must be rejected") }
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(exchangeCount, 0)
        XCTAssertFalse(manager.isConnected)
    }

    func testAccountReplacementDuringExchangeCannotInstallToken() async {
        let exchange = SyntheticBodySpecExchange(started: expectation(description: "Exchange waiting"))
        let manager = makeManager(exchange: { _, _, _ in await exchange.run() })
        let task = Task { try await manager.connect() }
        await fulfillment(of: [started], timeout: 2)
        browsers[0].complete()
        await fulfillment(of: [exchange.started], timeout: 2)
        account.ownership = .init(subject: "synthetic-owner", generation: 2)
        exchange.finish()
        if case .success = await task.result { XCTFail("A replaced account lifetime cannot install a token") }
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertFalse(manager.isConnected)
    }

    func testDisconnectDuringExchangeCannotReinstallToken() async throws {
        let exchange = SyntheticBodySpecExchange(started: expectation(description: "Exchange waiting"))
        let manager = makeManager(exchange: { _, _, _ in await exchange.run() })
        let task = Task { try await manager.connect() }
        await fulfillment(of: [started], timeout: 2)
        browsers[0].complete()
        await fulfillment(of: [exchange.started], timeout: 2)
        try manager.disconnect()
        exchange.finish()
        if case .success = await task.result { XCTFail("Disconnected authorization cannot reinstall itself") }
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertFalse(manager.isConnected)
    }

    func testTaskCancellationResolvesBrowserOnceAndDoesNotExchange() async {
        let manager = makeManager()
        let finished = expectation(description: "Cancelled authorization completed")
        let task = Task { @MainActor in
            defer { finished.fulfill() }
            do { try await manager.connect(); XCTFail("Cancelled authorization must fail") } catch {}
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [finished], timeout: 2)
        browsers[0].complete() // Late provider callback must not resume the continuation again.
        await task.value
        XCTAssertEqual(browsers[0].cancelCount, 1)
        XCTAssertEqual(exchangeCount, 0)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testOldBrowserCallbackCannotClearReplacementAuthorization() async throws {
        let manager = makeManager()
        let first = Task { try await manager.connect() }
        await fulfillment(of: [started], timeout: 2)
        started = expectation(description: "Replacement browser started")
        let second = Task { try await manager.connect() }
        await fulfillment(of: [started], timeout: 2)
        if case .success = await first.result { XCTFail("Superseded authorization cannot succeed") }
        XCTAssertEqual(browsers[0].cancelCount, 1)
        browsers[0].complete()
        browsers[1].complete()
        try await second.value
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(exchangeCount, 1)
        XCTAssertTrue(manager.isConnected)
        XCTAssertEqual(store.token?.lybOwnerId, account.ownership?.subject)
    }

    func testFailedDurableTokenSaveCannotReportConnected() async {
        store.saveError = URLError(.cannotWriteToFile)
        let manager = makeManager()
        let task = Task { try await manager.connect() }
        await fulfillment(of: [started], timeout: 2)
        browsers[0].complete()
        if case .success = await task.result { XCTFail("A failed durable installation cannot succeed") }
        XCTAssertNil(store.token)
        XCTAssertFalse(manager.isConnected)
        XCTAssertNil(manager.connectedEmail)
        XCTAssertThrowsError(try manager.connectionSnapshot())
    }

    func testFailedReconnectRestoresPriorConnectionConsistentlyWithReload() async throws {
        store.token = syntheticBodySpecToken()
        store.saveError = URLError(.cannotWriteToFile)
        let manager = makeManager()
        let oldSnapshot = try manager.connectionSnapshot()
        let task = Task { try await manager.connect() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertFalse(manager.isConnected)
        browsers[0].complete()
        if case .success = await task.result { XCTFail("Failed replacement cannot report success") }
        XCTAssertTrue(manager.isConnected)
        XCTAssertThrowsError(try oldSnapshot.validate())
        let reloaded = BodySpecAuthManager(
            tokenStore: store, account: account.access, configuration: { ("synthetic-client", "lyb-test://oauth") }
        )
        XCTAssertEqual(manager.isConnected, reloaded.isConnected)
        XCTAssertEqual(manager.connectedEmail, reloaded.connectedEmail)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testCancelledReconnectRestoresPriorConnectionButNotItsOldSnapshot() async throws {
        store.token = syntheticBodySpecToken()
        let manager = makeManager()
        let oldSnapshot = try manager.connectionSnapshot()
        let task = Task { try await manager.connect() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        if case .success = await task.result { XCTFail("Cancelled replacement cannot report success") }
        XCTAssertTrue(manager.isConnected)
        XCTAssertThrowsError(try oldSnapshot.validate())
        XCTAssertEqual(store.saveCount, 0)
    }

    func testAccountStateResetClearsOwnedDataAndInvalidatesSameSubjectOldOperations() throws {
        let first = AuthManager.ProfileSessionOwnership(subject: "synthetic-owner", generation: 1)
        var state = BodySpecIntegrationState()
        state.reset(for: first)
        let operation = state.operationID
        state.isConnected = true
        state.connectedEmail = "scan@example.invalid"
        state.isConnecting = true
        state.isSyncing = true
        state.isLoadingScans = true
        state.lastSyncSummary = "Synthetic old summary"
        state.lastSyncFailed = true
        state.errorMessage = "Synthetic old error"
        state.recentScansError = "Synthetic old history error"
        state.recoveryAction = .disconnect
        state.recentScans = [DexaResult(
            id: "synthetic-scan", userId: first.subject, bodyMetricsId: nil, externalSource: "bodyspec",
            externalResultId: "synthetic-result", externalUpdateTime: nil, scannerModel: nil,
            locationId: nil, locationName: nil, acquireTime: nil, analyzeTime: nil,
            vatMassKg: nil, vatVolumeCm3: nil, resultPdfUrl: nil, resultPdfName: nil,
            createdAt: .distantPast, updatedAt: .distantPast
        )]
        let replacement = AuthManager.ProfileSessionOwnership(subject: first.subject, generation: 2)
        state.reset(for: replacement)
        XCTAssertFalse(state.owns(operation, account: first))
        XCTAssertTrue(state.owns(state.operationID, account: replacement))
        XCTAssertFalse(state.isConnected || state.isConnecting || state.isSyncing || state.isLoadingScans)
        XCTAssertNil(state.connectedEmail)
        XCTAssertNil(state.lastSyncSummary)
        XCTAssertFalse(state.lastSyncFailed)
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(state.recentScansError)
        XCTAssertNil(state.recoveryAction)
        XCTAssertTrue(state.recentScans.isEmpty)
        state.isSyncing = true
        if state.owns(operation, account: first) { state.isSyncing = false }
        XCTAssertTrue(state.isSyncing, "Old completion must not clear the replacement's operation")
        state.reset(for: nil)
        XCTAssertNil(state.owner)
        XCTAssertFalse(state.isSyncing)
    }

    func testConnectionOperationReplacementClearsAbandonedLoadingFlags() {
        let owner = AuthManager.ProfileSessionOwnership(subject: "synthetic-owner", generation: 1)
        var state = BodySpecIntegrationState()
        state.reset(for: owner)
        let oldOperation = state.operationID
        state.isConnecting = true
        state.isSyncing = true
        state.isLoadingScans = true
        let newOperation = state.replaceConnectionOperation()
        XCTAssertFalse(state.owns(oldOperation, account: owner))
        XCTAssertTrue(state.owns(newOperation, account: owner))
        XCTAssertFalse(state.isConnecting || state.isSyncing || state.isLoadingScans)
        state.isLoadingScans = true
        if state.owns(oldOperation, account: owner) { state.isLoadingScans = false }
        XCTAssertTrue(state.isLoadingScans)
    }

    func testDisconnectFailurePresentationRetainsAnActualRetryAction() {
        var state = BodySpecIntegrationState()
        state.disconnectFailed()
        XCTAssertEqual(state.recoveryAction, .disconnect)
        XCTAssertNotNil(state.errorMessage)
    }

    private func makeManager(exchange: BodySpecAuthManager.TokenExchange? = nil) -> BodySpecAuthManager {
        if started == nil { started = expectation(description: "Synthetic browser started") }
        return BodySpecAuthManager(tokenStore: store, account: account.access,
                                   makeAuthorizationSession: { [weak self] url, _, _, callback in
            let browser = SyntheticBodySpecBrowser(url: url, callback: callback)
            browser.starts = self?.browserStarts ?? false
            browser.onStart = { [weak self] in self?.started.fulfill() }
            self?.browsers.append(browser)
            return browser
        }, tokenExchange: exchange ?? { [weak self] _, _, _ in
            self?.exchangeCount += 1
            return syntheticBodySpecToken(owner: nil)
        }, configuration: { ("synthetic-client", "lyb-test://oauth") })
    }
}
