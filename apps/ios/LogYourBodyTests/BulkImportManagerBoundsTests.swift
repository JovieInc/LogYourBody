//
// BulkImportManagerBoundsTests.swift
// LogYourBodyTests
//
// Regression coverage for a confirmed crash: `importPhoto(at:)` bounds-checks the
// index only once, before its first `await`. If the user cancels an in-flight
// bulk import and starts a smaller one, `importTasks` shrinks while the old task
// is still suspended; on resume its captured index pointed past the array and
// `importTasks[index]` trapped with "Index out of range". `updateImportTask`
// re-validates the index on every mutation.
//
import CoreData
import Photos
import UIKit
import XCTest
@testable import LogYourBody

@MainActor
final class BulkImportManagerBoundsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var auth: AuthManager!
    private var coreData: CoreDataManager!
    private var uploads = 0
    private var syncTriggers = 0

    override func setUpWithError() throws {
        suiteName = "PhotoImportOwnershipTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        auth = AuthManager(userDefaults: defaults, urlSession: URLSession(configuration: configuration))
        setAccount("synthetic-photo-A")
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        coreData = CoreDataManager(persistentStoreDescriptions: [store])
        uploads = 0
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

    func test_updateImportTask_indexPastEnd_isSafeNoOp() {
        let manager = BulkImportManager.shared
        let original = manager.importTasks
        defer { manager.importTasks = original }

        manager.importTasks = []

        // Would previously crash: importTasks[5] on an empty array.
        manager.updateImportTask(at: 5) { $0.status = .completed }
        XCTAssertTrue(manager.importTasks.isEmpty)

        // A negative index is also a safe no-op.
        manager.updateImportTask(at: -1) { $0.status = .failed }
        XCTAssertTrue(manager.importTasks.isEmpty)
    }

    private func setAccount(_ subject: String) {
        auth.authSession = .localFixture(subject: subject, email: "photo@example.invalid", accessToken: "synthetic")
        auth.currentUser = LocalUser(
            id: subject, email: "photo@example.invalid", name: "Synthetic Photo",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
    }

    private func assertHeldPhotoImportIsRejected(replace: () -> Void) async {
        let gate = HeldPhotoImageLoad()
        let manager = BulkImportManager(
            accountOwner: auth,
            metricsStore: coreData,
            loadFullImage: { _ in await gate.load() },
            uploadPhoto: { _, _ in
                self.uploads += 1
                return "synthetic://photo"
            },
            syncImportedPhoto: { self.syncTriggers += 1 }
        )
        let photo = ScannedPhoto(
            asset: SyntheticImportAsset(),
            date: Date(),
            confidence: 1,
            metadata: ScannedPhoto.PhotoMetadata(
                location: nil, cameraType: .unknown, isScreenshot: false, hasBeenEdited: false
            )
        )
        let task = Task { await manager.importPhotos([photo]) }
        defer { gate.complete() }
        await fulfillment(of: [gate.started], timeout: 3)
        replace()
        gate.complete()
        await task.value
        let recordsA = await coreData.fetchBodyMetrics(for: "synthetic-photo-A")
        let recordsB = await coreData.fetchBodyMetrics(for: "synthetic-photo-B")
        XCTAssertTrue(recordsA.isEmpty, "In-flight photo import must not land for the starting account")
        XCTAssertTrue(recordsB.isEmpty, "In-flight photo import must not land for the replacement account")
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(syncTriggers, 0)
    }

    func testCurrentOwnerPhotoImportSavesOnlyThatAccount() async {
        let manager = BulkImportManager(
            accountOwner: auth,
            metricsStore: coreData,
            loadFullImage: { _ in
                UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
            },
            uploadPhoto: { _, _ in
                self.uploads += 1
                return "synthetic://photo"
            },
            syncImportedPhoto: { self.syncTriggers += 1 }
        )
        let photo = ScannedPhoto(
            asset: SyntheticImportAsset(),
            date: Date(),
            confidence: 1,
            metadata: ScannedPhoto.PhotoMetadata(
                location: nil, cameraType: .unknown, isScreenshot: false, hasBeenEdited: false
            )
        )
        await manager.importPhotos([photo])
        let records = await coreData.fetchBodyMetrics(for: "synthetic-photo-A")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.userId, "synthetic-photo-A")
        XCTAssertEqual(records.first?.notes, "Imported from photo library")
        let recordsB = await coreData.fetchBodyMetrics(for: "synthetic-photo-B")
        XCTAssertTrue(recordsB.isEmpty)
        XCTAssertEqual(uploads, 1)
        XCTAssertEqual(syncTriggers, 1)
    }

    /// Opt-in bulk deletion must remove only verified imports (completed uploads)
    /// from the camera roll, never failed or pending tasks.
    func testDeleteAfterImportRemovesOnlySuccessfullyImportedAssets() async {
        var deletedIdentifiers: [String] = []
        var uploadCalls = 0
        let manager = BulkImportManager(
            accountOwner: auth,
            metricsStore: coreData,
            loadFullImage: { _ in
                UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
            },
            uploadPhoto: { _, _ in
                uploadCalls += 1
                if uploadCalls == 2 {
                    throw NSError(domain: "BulkImportTests", code: 1)
                }
                return "synthetic://photo"
            },
            syncImportedPhoto: { self.syncTriggers += 1 },
            shouldDeleteAfterImport: { true },
            deleteAssets: { identifiers in deletedIdentifiers = identifiers }
        )
        let successfulPhoto = makeScannedPhoto(assetIdentifier: "imported-asset")
        let failedPhoto = makeScannedPhoto(assetIdentifier: "failed-asset")

        await manager.importPhotos([successfulPhoto, failedPhoto])

        XCTAssertEqual(manager.failedCount, 1)
        XCTAssertEqual(deletedIdentifiers, ["imported-asset"])
    }

    func testDeleteAfterImportDisabledSkipsDeletion() async {
        var deletedIdentifiers: [String] = []
        let manager = BulkImportManager(
            accountOwner: auth,
            metricsStore: coreData,
            loadFullImage: { _ in
                UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
            },
            uploadPhoto: { _, _ in "synthetic://photo" },
            syncImportedPhoto: { self.syncTriggers += 1 },
            shouldDeleteAfterImport: { false },
            deleteAssets: { identifiers in deletedIdentifiers = identifiers }
        )

        await manager.importPhotos([makeScannedPhoto(assetIdentifier: "imported-asset")])

        XCTAssertEqual(manager.failedCount, 0)
        XCTAssertTrue(deletedIdentifiers.isEmpty)
    }

    private func makeScannedPhoto(assetIdentifier: String) -> ScannedPhoto {
        ScannedPhoto(
            asset: SyntheticImportAsset(localIdentifier: assetIdentifier),
            date: Date(),
            confidence: 1,
            metadata: ScannedPhoto.PhotoMetadata(
                location: nil, cameraType: .unknown, isScreenshot: false, hasBeenEdited: false
            )
        )
    }

    func testHeldPhotoImportCannotSaveUnderReplacementAccount() async {
        await assertHeldPhotoImportIsRejected { setAccount("synthetic-photo-B") }
    }

    func testHeldPhotoImportCannotSaveAfterSameAccountRelogin() async {
        let originalSession = auth.authSession
        let originalUser = auth.currentUser
        await assertHeldPhotoImportIsRejected {
            auth.authSession = nil
            auth.currentUser = nil
            auth.authSession = originalSession
            auth.currentUser = originalUser
        }
    }
    func testTwoPhotoBatchStopsWhenAccountChangesDuringFirstImageLoad() async throws {
        try await assertTwoPhotoBatchStopsAfterReplacement(replace: { setAccount("synthetic-photo-B") })
    }

    func testTwoPhotoBatchStopsAfterSameAccountReloginDuringFirstImageLoad() async throws {
        try await assertTwoPhotoBatchStopsAfterReplacement(replace: {
            let session = auth.authSession
            let user = auth.currentUser
            auth.authSession = nil
            auth.currentUser = nil
            auth.authSession = session
            auth.currentUser = user
        })
    }

    private func assertTwoPhotoBatchStopsAfterReplacement(replace: () -> Void) async throws {
        let gate = HeldPhotoImageLoad()
        var loadedAssets: [String] = []
        var deletedAssets: [String] = []
        let manager = BulkImportManager(
            accountOwner: auth, metricsStore: coreData,
            loadFullImage: { asset in
                let first = await MainActor.run {
                    loadedAssets.append(asset.localIdentifier)
                    return loadedAssets.count == 1
                }
                if first { return await gate.load() }
                return await MainActor.run { self.batchImage() }
            },
            uploadPhoto: { _, _ in
                self.uploads += 1
                return "synthetic://photo"
            },
            syncImportedPhoto: { self.syncTriggers += 1 },
            shouldDeleteAfterImport: { true },
            deleteAssets: { deletedAssets = $0 }
        )
        let task = Task { await manager.importPhotos(twoBatchPhotos()) }
        defer { gate.complete() }
        await fulfillment(of: [gate.started], timeout: 3)
        replace()
        gate.complete()
        await task.value
        XCTAssertEqual(loadedAssets, ["batch-first"], "A replacement cannot admit the next selected photo")
        XCTAssertTrue(try freshBatchRows().isEmpty)
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(syncTriggers, 0)
        XCTAssertTrue(deletedAssets.isEmpty)
        XCTAssertFalse(manager.isImporting)
    }

    func testTwoPhotoBatchCompletesForItsUnchangedOwner() async throws {
        var deletedAssets: [String] = []
        let manager = BulkImportManager(
            accountOwner: auth, metricsStore: coreData,
            loadFullImage: { _ in await MainActor.run { self.batchImage() } },
            uploadPhoto: { _, _ in
                self.uploads += 1
                return "synthetic://photo"
            },
            syncImportedPhoto: { self.syncTriggers += 1 },
            shouldDeleteAfterImport: { true },
            deleteAssets: { deletedAssets = $0 }
        )
        await manager.importPhotos(twoBatchPhotos())
        let rows = try freshBatchRows()
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.owner == "synthetic-photo-A" && !$0.deleted })
        XCTAssertEqual(Set(rows.map(\.day)).count, 2)
        XCTAssertEqual(uploads, 2)
        XCTAssertEqual(syncTriggers, 2)
        XCTAssertEqual(deletedAssets, ["batch-first", "batch-second"])
        XCTAssertFalse(manager.isImporting)
    }

    func testTwoPhotoBatchPreservesAdmittedFirstPhotoAndStopsAfterAccountReplacement() async throws {
        let gate = HeldPhotoImageLoad()
        var loadedAssets: [String] = []
        var deletedAssets: [String] = []
        let manager = BulkImportManager(
            accountOwner: auth, metricsStore: coreData,
            loadFullImage: { asset in
                await MainActor.run {
                    loadedAssets.append(asset.localIdentifier)
                    return self.batchImage()
                }
            },
            uploadPhoto: { _, _ in
                let first = await MainActor.run { self.uploads += 1; return self.uploads == 1 }
                if first { _ = await gate.load() }
                return "synthetic://photo"
            },
            syncImportedPhoto: { self.syncTriggers += 1 },
            shouldDeleteAfterImport: { true },
            deleteAssets: { deletedAssets = $0 }
        )
        let task = Task { await manager.importPhotos(twoBatchPhotos()) }
        defer { gate.complete() }
        await fulfillment(of: [gate.started], timeout: 3)
        let admitted = try freshBatchRows()
        XCTAssertEqual(admitted.count, 1)
        XCTAssertEqual(admitted.first?.owner, "synthetic-photo-A")
        setAccount("synthetic-photo-B")
        gate.complete()
        await task.value
        XCTAssertEqual(try freshBatchRows(), admitted, "Already admitted original-owner metadata is retained")
        XCTAssertEqual(loadedAssets, ["batch-first"])
        XCTAssertEqual(uploads, 1)
        XCTAssertEqual(syncTriggers, 0)
        XCTAssertTrue(deletedAssets.isEmpty)
        XCTAssertFalse(manager.isImporting)
    }

    private func twoBatchPhotos() -> [ScannedPhoto] {
        ["batch-first", "batch-second"].enumerated().map { index, identifier in
            ScannedPhoto(
                asset: SyntheticImportAsset(localIdentifier: identifier),
                date: Date(timeIntervalSince1970: 1_760_000_000 + Double(index) * 86_400),
                confidence: 1,
                metadata: ScannedPhoto.PhotoMetadata(
                    location: nil, cameraType: .unknown, isScreenshot: false, hasBeenEdited: false
                )
            )
        }
    }

    private func batchImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
    }

    private func freshBatchRows() throws -> [BulkBatchStoredRow] {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coreData.viewContext.persistentStoreCoordinator
        return try context.fetch(CachedBodyMetrics.fetchRequest()).map {
            BulkBatchStoredRow(id: $0.id, owner: $0.userId, day: $0.localDate, deleted: $0.isMarkedDeleted)
        }.sorted { ($0.id ?? "") < ($1.id ?? "") }
    }
}

/// Synthetic photos and an in-memory store. The image load is the suspension point;
/// no photo library, network upload, or personal HealthKit store is used.
@MainActor
final class HeldPhotoImageLoad {
    let started = XCTestExpectation(description: "Synthetic photo image load started")
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var result: UIImage??

    func load() async -> UIImage? {
        started.fulfill()
        return await withCheckedContinuation { continuation in
            if let result {
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func complete() {
        guard result == nil else { return }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        result = .some(image)
        continuation?.resume(returning: image)
        continuation = nil
    }
}

private final class SyntheticImportAsset: PHAsset, @unchecked Sendable {
    private let identifier: String

    init(localIdentifier: String = "synthetic-asset") {
        identifier = localIdentifier
        super.init()
    }

    override var localIdentifier: String {
        identifier
    }
}

private struct BulkBatchStoredRow: Equatable {
    let id: String?
    let owner: String?
    let day: String?
    let deleted: Bool
}
