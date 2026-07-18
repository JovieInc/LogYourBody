//
// CoreDataModelMigrationTests.swift
// LogYourBodyTests
//
import XCTest
import CoreData
@testable import LogYourBody

final class CoreDataModelMigrationTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SyncMetadata-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    func testV1StoreMigratesRetainedDataAndSyncMetadata() throws {
        let appBundle = Bundle(for: CoreDataManager.self)
        let modelBundle = try XCTUnwrap(
            appBundle.url(forResource: "LogYourBody", withExtension: "momd")
        )
        let v1Model = try XCTUnwrap(
            NSManagedObjectModel(contentsOf: modelBundle.appendingPathComponent("LogYourBody.mom"))
        )
        XCTAssertNotNil(v1Model.entitiesByName["SyncMetadata"]?.attributesByName["entityName"])

        let legacyCoordinator = NSPersistentStoreCoordinator(managedObjectModel: v1Model)
        let legacyStore = try legacyCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL
        )
        let legacyContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        legacyContext.persistentStoreCoordinator = legacyCoordinator
        let legacyDate = Date(timeIntervalSince1970: 1_700_000_000)
        var saveError: Error?
        legacyContext.performAndWait {
            do {
                let syncMetadata = NSEntityDescription.insertNewObject(
                    forEntityName: "SyncMetadata",
                    into: legacyContext
                )
                // `entityName` collides with NSManagedObject. Primitive access seeds the
                // actual legacy column rather than the inherited Objective-C accessor.
                syncMetadata.setPrimitiveValue("CachedBodyMetrics", forKey: "entityName")
                syncMetadata.setValue("legacy-id", forKey: "entityId")
                syncMetadata.setValue(2, forKey: "syncRetryCount")
                syncMetadata.setValue("legacy failure", forKey: "lastSyncError")

                let bodyMetric = NSEntityDescription.insertNewObject(
                    forEntityName: "CachedBodyMetrics",
                    into: legacyContext
                )
                bodyMetric.setValue("body-metric-id", forKey: "id")
                bodyMetric.setValue("user-id", forKey: "userId")
                bodyMetric.setValue(legacyDate, forKey: "createdAt")
                bodyMetric.setValue(legacyDate, forKey: "date")
                bodyMetric.setValue(legacyDate, forKey: "lastModified")
                bodyMetric.setValue(legacyDate, forKey: "updatedAt")
                bodyMetric.setValue(80.5, forKey: "weight")
                try legacyContext.save()
            } catch {
                saveError = error
            }
        }
        if let saveError {
            XCTFail("Unable to save V1 fixture: \(saveError)")
            return
        }

        try legacyCoordinator.remove(legacyStore)

        let verificationCoordinator = NSPersistentStoreCoordinator(managedObjectModel: v1Model)
        let verificationStore = try verificationCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL
        )
        let verificationContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        verificationContext.persistentStoreCoordinator = verificationCoordinator
        var legacyEntityName: String?
        var legacyBodyMetricID: String?
        verificationContext.performAndWait {
            let syncRequest = NSFetchRequest<NSManagedObject>(entityName: "SyncMetadata")
            let bodyMetricRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedBodyMetrics")
            legacyEntityName = (try? verificationContext.fetch(syncRequest).first)?
                .primitiveValue(forKey: "entityName") as? String
            legacyBodyMetricID = (try? verificationContext.fetch(bodyMetricRequest).first)?
                .value(forKey: "id") as? String
        }
        XCTAssertEqual(legacyEntityName, "CachedBodyMetrics")
        XCTAssertEqual(legacyBodyMetricID, "body-metric-id")
        try verificationCoordinator.remove(verificationStore)

        let currentModel = CoreDataManager.makeManagedObjectModel(in: appBundle)
        XCTAssertEqual(
            currentModel.entitiesByName["SyncMetadata"]?
                .attributesByName["syncEntityName"]?.renamingIdentifier,
            "entityName"
        )
        let container = NSPersistentContainer(
            name: "LogYourBody",
            managedObjectModel: currentModel
        )
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        let loaded = expectation(description: "V1 store migrates")
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 10)
        if let loadError {
            XCTFail("Unable to migrate V1 store: \(loadError)")
            return
        }

        var bodyMetrics: [NSManagedObject] = []
        var syncMetadata: [NSManagedObject] = []
        container.viewContext.performAndWait {
            let bodyMetricRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedBodyMetrics")
            let syncRequest = NSFetchRequest<NSManagedObject>(entityName: "SyncMetadata")
            bodyMetrics = (try? container.viewContext.fetch(bodyMetricRequest)) ?? []
            syncMetadata = (try? container.viewContext.fetch(syncRequest)) ?? []
        }

        XCTAssertEqual(bodyMetrics.count, 1)
        guard let bodyMetric = bodyMetrics.first else {
            XCTFail("Expected migrated CachedBodyMetrics row")
            return
        }
        XCTAssertEqual(bodyMetric.value(forKey: "id") as? String, "body-metric-id")
        XCTAssertEqual(bodyMetric.value(forKey: "userId") as? String, "user-id")
        XCTAssertEqual(bodyMetric.value(forKey: "weight") as? Double, 80.5)

        XCTAssertEqual(syncMetadata.count, 1)
        guard let migratedSyncMetadata = syncMetadata.first else {
            XCTFail("Expected migrated SyncMetadata row")
            return
        }
        XCTAssertEqual(
            migratedSyncMetadata.value(forKey: "syncEntityName") as? String,
            "CachedBodyMetrics"
        )
        XCTAssertEqual(migratedSyncMetadata.value(forKey: "entityId") as? String, "legacy-id")
        XCTAssertEqual(migratedSyncMetadata.value(forKey: "syncRetryCount") as? Int16, 2)
        XCTAssertEqual(migratedSyncMetadata.value(forKey: "lastSyncError") as? String, "legacy failure")

        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }

        let reopenedCoordinator = NSPersistentStoreCoordinator(
            managedObjectModel: CoreDataManager.makeManagedObjectModel(in: appBundle)
        )
        let reopenedStore = try reopenedCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL
        )
        let reopenedContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        reopenedContext.persistentStoreCoordinator = reopenedCoordinator
        var reopenedSyncEntityName: String?
        reopenedContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "SyncMetadata")
            reopenedSyncEntityName = (try? reopenedContext.fetch(request).first)?
                .value(forKey: "syncEntityName") as? String
        }
        XCTAssertEqual(reopenedSyncEntityName, "CachedBodyMetrics")
        try reopenedCoordinator.remove(reopenedStore)
    }

    func testPersistentStoreFailureDoesNotCreateWritableInMemoryFallback() {
        let storeDescription = NSPersistentStoreDescription(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("LogYourBody-test-store.sqlite")
        )
        let expectedError = NSError(
            domain: "CoreDataModelMigrationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Injected persistent store load failure"]
        )
        let manager = CoreDataManager(
            persistentStoreDescriptions: [storeDescription],
            persistentStoreLoader: { container, completion in
                completion(container.persistentStoreDescriptions[0], expectedError)
            }
        )
        let failurePredicate = NSPredicate { _, _ in
            if case .failed = manager.persistentStoreLoadState {
                return true
            }
            return false
        }

        wait(
            for: [expectation(for: failurePredicate, evaluatedWith: manager, handler: nil)],
            timeout: 10
        )

        guard case let .failed(message) = manager.persistentStoreLoadState else {
            XCTFail("Expected persistent store loading to fail")
            return
        }
        XCTAssertEqual(message, expectedError.localizedDescription)
        XCTAssertEqual(
            manager.persistentContainer.persistentStoreDescriptions.first?.type,
            NSSQLiteStoreType
        )
        XCTAssertTrue(manager.persistentContainer.persistentStoreCoordinator.persistentStores.isEmpty)
    }

    func testPersistentStoreRetryRecoversAfterInitialLoadFailure() throws {
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LogYourBody-retry-\(UUID().uuidString).sqlite")
        let storeDescription = NSPersistentStoreDescription(url: storeURL)
        let expectedError = NSError(
            domain: "CoreDataModelMigrationTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Injected one-time load failure"]
        )
        var loadAttempts = 0
        let unexpectedReload = expectation(description: "ready store is not loaded again")
        unexpectedReload.isInverted = true
        let manager = CoreDataManager(
            persistentStoreDescriptions: [storeDescription],
            persistentStoreLoader: { container, completion in
                loadAttempts += 1
                if loadAttempts > 2 {
                    unexpectedReload.fulfill()
                }
                if loadAttempts == 1 {
                    completion(container.persistentStoreDescriptions[0], expectedError)
                } else {
                    container.loadPersistentStores(completionHandler: completion)
                }
            }
        )
        let failedPredicate = NSPredicate { _, _ in
            if case .failed = manager.persistentStoreLoadState {
                return true
            }
            return false
        }
        wait(
            for: [expectation(for: failedPredicate, evaluatedWith: manager, handler: nil)],
            timeout: 10
        )

        manager.retryPersistentStoreLoad()

        let readyPredicate = NSPredicate { _, _ in
            manager.persistentStoreLoadState == .ready
        }
        wait(
            for: [expectation(for: readyPredicate, evaluatedWith: manager, handler: nil)],
            timeout: 10
        )
        XCTAssertEqual(loadAttempts, 2)
        XCTAssertEqual(manager.persistentContainer.persistentStoreCoordinator.persistentStores.count, 1)

        manager.retryPersistentStoreLoad()
        wait(for: [unexpectedReload], timeout: 0.2)
        XCTAssertEqual(loadAttempts, 2)

        if let store = manager.persistentContainer.persistentStoreCoordinator.persistentStores.first {
            try manager.persistentContainer.persistentStoreCoordinator.remove(store)
        }
    }

    func testPersistentStoreRetryRemainsFailedWhenReloadFailsAgain() {
        let storeDescription = NSPersistentStoreDescription(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("LogYourBody-repeat-failure-\(UUID().uuidString).sqlite")
        )
        let expectedError = NSError(
            domain: "CoreDataModelMigrationTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Injected repeated load failure"]
        )
        var loadAttempts = 0
        let secondAttempt = expectation(description: "persistent store reload attempted")
        let manager = CoreDataManager(
            persistentStoreDescriptions: [storeDescription],
            persistentStoreLoader: { container, completion in
                loadAttempts += 1
                completion(container.persistentStoreDescriptions[0], expectedError)
                if loadAttempts == 2 {
                    secondAttempt.fulfill()
                }
            }
        )
        let initiallyFailed = NSPredicate { _, _ in
            if case .failed = manager.persistentStoreLoadState {
                return true
            }
            return false
        }
        wait(
            for: [expectation(for: initiallyFailed, evaluatedWith: manager, handler: nil)],
            timeout: 10
        )

        manager.retryPersistentStoreLoad()
        wait(for: [secondAttempt], timeout: 10)

        let failedAgain = NSPredicate { _, _ in
            manager.persistentStoreLoadState == .failed(message: expectedError.localizedDescription)
        }
        wait(
            for: [expectation(for: failedAgain, evaluatedWith: manager, handler: nil)],
            timeout: 10
        )
        XCTAssertEqual(loadAttempts, 2)
        XCTAssertTrue(manager.persistentContainer.persistentStoreCoordinator.persistentStores.isEmpty)
    }
}
