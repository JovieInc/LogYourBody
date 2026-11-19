//
// LocalExportAndPurchaseAdmissionTests.swift
// LogYourBodyTests
//
import CoreData
import RevenueCat
import XCTest
@testable import LogYourBody

@MainActor
final class LocalExportAndPurchaseAdmissionTests: XCTestCase {
    private static let weightSentinel = 812.345
    private static let noteSentinel = "lyb383-sentinel"
    private static let userId = "lyb-383-user"

    func testSecondExportTapStartsNoSecondFetchOrEncode() async {
        let flight = LocalExportFlight()
        let started = expectation(description: "export work started")
        let hold = AdmissionHold()
        var fetches = 0
        var encodes = 0
        let first = LocalExportCoordinator.start(flight: flight) {
            fetches += 1
            encodes += 1
            started.fulfill()
            await hold.park()
        }

        XCTAssertNotNil(first)
        XCTAssertTrue(flight.isExporting)
        XCTAssertEqual(fetches, 0)
        XCTAssertEqual(encodes, 0)

        let beforeWork = LocalExportCoordinator.start(flight: flight) {
            fetches += 1
            encodes += 1
        }
        XCTAssertNil(beforeWork)

        await fulfillment(of: [started], timeout: 2)
        let duringWork = LocalExportCoordinator.start(flight: flight) {
            fetches += 1
            encodes += 1
        }
        XCTAssertNil(duringWork)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(encodes, 1)

        hold.release()
        await first?.value
        XCTAssertFalse(flight.isExporting)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(encodes, 1)
    }

    func testExportSnapshotsComeFromABackgroundContext() async throws {
        let recorder = installSignposts()
        defer { InteractionSignpost.testLines = nil }
        let store = makeStore()
        try await seed(store)
        let read = await store.fetchExportValueSnapshots(for: Self.userId)

        XCTAssertTrue(read.probe.isPrivateQueue)
        XCTAssertFalse(read.probe.isViewContext)
        XCTAssertFalse(read.probe.isMainThread)
        let metric = try XCTUnwrap(read.snapshots.bodyMetrics.first)
        XCTAssertEqual(metric.id, "metric-lyb-383")
        XCTAssertEqual(metric.weight, Self.weightSentinel)
        XCTAssertEqual(metric.notes, Self.noteSentinel)
        let log = try XCTUnwrap(read.snapshots.dailyLogs.first)
        XCTAssertEqual(log.id, "log-lyb-383")
        XCTAssertEqual(log.notes, Self.noteSentinel)
        XCTAssertTrue(recorder.lines.isEmpty)
        XCTAssertFalse(recorder.text.contains(Self.noteSentinel))
        XCTAssertFalse(recorder.text.contains(String(Self.weightSentinel)))
    }

    func testExportEncodeRunsOffTheMainActorWithoutLoggingValues() async throws {
        let recorder = installSignposts()
        defer { InteractionSignpost.testLines = nil }
        XCTAssertEqual(InteractionSignpost.registered, ["export_encode", "purchase_admit"])

        let snapshots = ExportValueSnapshots(
            bodyMetrics: [sampleMetric()],
            dailyLogs: []
        )
        let json = try await LocalExportWork.write(LocalExportRequest(
            user: sampleUser(),
            snapshots: snapshots,
            formats: [.json],
            includePhotos: false,
            heightCm: nil
        ))
        let csv = try await LocalExportWork.write(LocalExportRequest(
            user: sampleUser(heightCm: 180),
            snapshots: snapshots,
            formats: [.csv],
            includePhotos: false,
            heightCm: 180
        ))
        guard case .file(let jsonFile) = json, case .file(let csvFile) = csv else {
            return XCTFail("expected one encoded file for each format")
        }
        defer {
            removeExportDirectory(jsonFile.url)
            removeExportDirectory(csvFile.url)
        }

        XCTAssertTrue(jsonFile.encodedOffMainActor)
        XCTAssertTrue(csvFile.encodedOffMainActor)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonFile.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: csvFile.url.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportData.self, from: Data(contentsOf: jsonFile.url))
        XCTAssertEqual(decoded.bodyMetrics.first?.weight, Self.weightSentinel)
        XCTAssertEqual(decoded.bodyMetrics.first?.notes, Self.noteSentinel)
        let csvText = try String(contentsOf: csvFile.url, encoding: .utf8)
        XCTAssertTrue(csvText.contains(Self.noteSentinel))
        XCTAssertTrue(csvText.contains(String(Self.weightSentinel)))

        XCTAssertEqual(recorder.lines, ["export_encode", "export_encode"])
        XCTAssertFalse(recorder.text.contains(Self.noteSentinel))
        XCTAssertFalse(recorder.text.contains(String(Self.weightSentinel)))
    }

    func testAdmissionSharesOneCallAndRejectsTheOtherOperation() async {
        let admission = BillingProviderAdmission()
        let started = expectation(description: "purchase work started")
        let hold = AdmissionHold()
        var ran = false
        let decision = admission.admit(.purchase) {
            ran = true
            started.fulfill()
            await hold.park()
            return true
        }
        XCTAssertFalse(ran)
        XCTAssertTrue(admission.isInFlight)
        guard case .started(let task) = decision else {
            return XCTFail("expected a started purchase")
        }

        let shared = admission.admit(.purchase) { () async -> Bool in false }
        guard case .shared = shared else { return XCTFail("expected the purchase to be shared") }
        XCTAssertEqual(admission.shareCount, 1)
        let busy = admission.admit(.restore) { () async -> Bool in false }
        guard case .busy = busy else { return XCTFail("expected restore to be busy") }

        await fulfillment(of: [started], timeout: 2)
        hold.release()
        XCTAssertTrue(await task.value)
        XCTAssertFalse(admission.isInFlight)

        let next = admission.admit(.restore) { () async -> Bool in true }
        guard case .started(let fresh) = next else { return XCTFail("expected a new flight after abandon") }
        XCTAssertTrue(await fresh.value)
        XCTAssertFalse(admission.isInFlight)
    }

    func testSecondPurchaseTapSharesOneProviderCall() async {
        let recorder = installSignposts()
        defer { InteractionSignpost.testLines = nil }
        let client = HoldingPurchasesClient()
        client.purchaseStarted.assertForOverFulfill = true
        let fixture = makeManager(client: client)
        defer { fixture.cleanup() }

        let first = Task { await fixture.manager.purchase(package: RevenueCatPurchaseRestoreFlowTests.makeAnnualPackage()) }
        await fulfillment(of: [client.purchaseStarted], timeout: 2)
        XCTAssertTrue(fixture.manager.isPurchasing)
        XCTAssertEqual(client.purchaseCalls, 1)

        let second = Task { await fixture.manager.purchase(package: RevenueCatPurchaseRestoreFlowTests.makeAnnualPackage()) }
        await waitUntilShared(fixture.manager)
        XCTAssertEqual(fixture.manager.billingAdmission.shareCount, 1)
        XCTAssertEqual(client.purchaseCalls, 1)
        XCTAssertEqual(client.restoreCalls, 0)

        client.releasePurchase(activeCustomer())
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual([firstResult, secondResult], [true, true])
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertEqual(recorder.lines, ["purchase_admit"])
        XCTAssertFalse(recorder.text.contains("$rc_annual"))
        XCTAssertFalse(recorder.text.contains("synthetic.annual"))
    }

    func testSecondRestoreTapSharesOneProviderCall() async {
        let recorder = installSignposts()
        defer { InteractionSignpost.testLines = nil }
        let client = HoldingPurchasesClient()
        client.restoreStarted.assertForOverFulfill = true
        let fixture = makeManager(client: client)
        defer { fixture.cleanup() }

        let first = Task { await fixture.manager.restorePurchases() }
        await fulfillment(of: [client.restoreStarted], timeout: 2)
        XCTAssertTrue(fixture.manager.isPurchasing)
        XCTAssertEqual(client.restoreCalls, 1)

        let second = Task { await fixture.manager.restorePurchases() }
        await waitUntilShared(fixture.manager)
        XCTAssertEqual(fixture.manager.billingAdmission.shareCount, 1)
        XCTAssertEqual(client.restoreCalls, 1)

        client.releaseRestore(activeCustomer())
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual([firstResult, secondResult], [true, true])
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertEqual(recorder.lines, ["purchase_admit"])
        XCTAssertFalse(recorder.text.contains("synthetic.annual"))
    }

    func testRestoreDuringPurchaseDoesNotCallTheProvider() async {
        let client = HoldingPurchasesClient()
        let fixture = makeManager(client: client)
        defer {
            client.releasePurchase(activeCustomer())
            fixture.cleanup()
        }

        let purchase = Task {
            await fixture.manager.purchase(package: RevenueCatPurchaseRestoreFlowTests.makeAnnualPackage())
        }
        await fulfillment(of: [client.purchaseStarted], timeout: 2)
        let restored = await fixture.manager.restorePurchases()

        XCTAssertFalse(restored)
        XCTAssertNil(fixture.manager.errorMessage)
        XCTAssertEqual(client.purchaseCalls, 1)
        XCTAssertEqual(client.restoreCalls, 0)
        client.releasePurchase(activeCustomer())
        XCTAssertTrue(await purchase.value)
    }

    private func installSignposts() -> SignpostRecorder {
        let recorder = SignpostRecorder()
        InteractionSignpost.testLines = { recorder.record($0) }
        return recorder
    }

    private func waitUntilShared(_ manager: RevenueCatManager) async {
        var spins = 0
        while manager.billingAdmission.shareCount == 0 && spins < 50 {
            await Task.yield()
            spins += 1
        }
    }

    private func makeStore() -> CoreDataManager {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        return CoreDataManager(persistentStoreDescriptions: [description])
    }

    private func seed(_ store: CoreDataManager) async throws {
        let context = store.persistentContainer.newBackgroundContext()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try await context.perform {
            let metric = CachedBodyMetrics(context: context)
            metric.id = "metric-lyb-383"
            metric.userId = Self.userId
            metric.date = date
            metric.weight = Self.weightSentinel
            metric.weightUnit = "kg"
            metric.notes = Self.noteSentinel
            metric.createdAt = date
            metric.updatedAt = date
            let log = CachedDailyMetrics(context: context)
            log.id = "log-lyb-383"
            log.userId = Self.userId
            log.date = date
            log.steps = 1_234
            log.notes = Self.noteSentinel
            log.createdAt = date
            log.updatedAt = date
            try context.save()
        }
    }

    private func sampleMetric() -> BodyMetrics {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return BodyMetrics(
            id: "metric-lyb-383",
            userId: Self.userId,
            date: date,
            weight: Self.weightSentinel,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: Self.noteSentinel,
            photoUrl: nil,
            dataSource: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private func sampleUser(heightCm: Double? = nil) -> User {
        let profile = heightCm.map { height in
            UserProfile(
                id: "profile-lyb-383",
                email: "export@example.com",
                username: nil,
                fullName: nil,
                dateOfBirth: nil,
                height: height,
                heightUnit: "cm",
                gender: nil,
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: nil,
                onboardingCompleted: nil
            )
        }
        return User(
            id: Self.userId,
            email: "export@example.com",
            name: nil,
            avatarUrl: nil,
            profile: profile
        )
    }

    private func activeCustomer() -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(
            originalAppUserId: "unit-test-user",
            entitlement: RevenueCatEntitlementSnapshot(
                isActive: true,
                expirationDate: Date(timeIntervalSinceNow: 86_400),
                periodType: .normal,
                willRenew: true,
                productIdentifier: "synthetic.annual",
                unsubscribeDetectedAt: nil
            )
        )
    }

    private func makeManager(client: HoldingPurchasesClient) -> AdmissionFixture {
        let suiteName = "lyb-383-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("unit-test-user", forKey: RevenueCatManager.DefaultsKey.subscriptionOwner)
        let manager = RevenueCatManager(
            purchasesClient: client,
            userDefaults: defaults,
            purchaseVerificationEnabled: { true }
        )
        let owner = manager.beginBillingSession(subject: "unit-test-user")
        manager.finishBillingSession(owner)
        manager.restoreCachedBillingAccess(for: "unit-test-user")
        manager.markAsConfigured()
        return AdmissionFixture(manager: manager, defaults: defaults, suiteName: suiteName)
    }

    private func removeExportDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

private struct AdmissionFixture {
    let manager: RevenueCatManager
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class AdmissionHold {
    private var continuation: CheckedContinuation<Void, Never>?

    func park() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private final class SignpostRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func record(_ line: String) {
        lock.lock()
        stored.append(line)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    var text: String { lines.joined(separator: "\n") }
}

@MainActor
private final class HoldingPurchasesClient: RevenueCatPurchasesProtocol {
    let purchaseStarted = XCTestExpectation(description: "purchase provider call started")
    let restoreStarted = XCTestExpectation(description: "restore provider call started")
    private(set) var purchaseCalls = 0
    private(set) var restoreCalls = 0
    private var purchaseContinuation: CheckedContinuation<RevenueCatCustomerSnapshot, Error>?
    private var restoreContinuation: CheckedContinuation<RevenueCatCustomerSnapshot, Error>?
    private var purchaseResult: Result<RevenueCatCustomerSnapshot, Error>?
    private var restoreResult: Result<RevenueCatCustomerSnapshot, Error>?

    func configure(apiKey: String, delegate: PurchasesDelegate) {}

    func logIn(userId: String, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        throw HoldError.unused
    }

    func logOut() async throws { throw HoldError.unused }

    func customerInfo(
        entitlementID: String,
        read: RevenueCatCustomerInfoRead
    ) async throws -> RevenueCatCustomerSnapshot {
        throw HoldError.unused
    }

    func offerings() async throws -> Offerings { throw HoldError.unused }

    func purchase(
        package: Package,
        entitlementID: String,
        verifiesOutcome: Bool
    ) async throws -> RevenueCatCustomerSnapshot {
        purchaseCalls += 1
        purchaseStarted.fulfill()
        if let purchaseResult { return try purchaseResult.get() }
        return try await withCheckedThrowingContinuation { purchaseContinuation = $0 }
    }

    func restorePurchases(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        restoreCalls += 1
        restoreStarted.fulfill()
        if let restoreResult { return try restoreResult.get() }
        return try await withCheckedThrowingContinuation { restoreContinuation = $0 }
    }

    func releasePurchase(_ customer: RevenueCatCustomerSnapshot) {
        let result: Result<RevenueCatCustomerSnapshot, Error> = .success(customer)
        purchaseResult = result
        let pending = purchaseContinuation
        purchaseContinuation = nil
        pending?.resume(with: result)
    }

    func releaseRestore(_ customer: RevenueCatCustomerSnapshot) {
        let result: Result<RevenueCatCustomerSnapshot, Error> = .success(customer)
        restoreResult = result
        let pending = restoreContinuation
        restoreContinuation = nil
        pending?.resume(with: result)
    }
}

private enum HoldError: Error { case unused }
