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

private final class SyntheticImportAsset: PHAsset, @unchecked Sendable {}

@MainActor
final class PhotoImportOwnershipTests: XCTestCase {
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
}
