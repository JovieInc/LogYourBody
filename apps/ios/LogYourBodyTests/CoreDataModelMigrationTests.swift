//
// CoreDataModelMigrationTests.swift
// LogYourBodyTests
//
import XCTest
import CoreData
import SQLite3
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

    func testKilledMidMigrationKeepsCommittedMeasurementOnIsolatedStore() throws {
        let seededURL = try seedRepresentativeV1Store()
        defer { removeSQLiteFamily(seededURL) }

        let snapshotURL = try interruptedUncommittedWriteSnapshot(of: seededURL)
        defer { removeSQLiteFamily(snapshotURL) }
        let walSize = sqliteFileSize(snapshotURL.path + "-wal")
        XCTAssertGreaterThan(
            walSize,
            32,
            "The isolated snapshot needs a real WAL frame from the killed write"
        )

        let description = NSPersistentStoreDescription(url: snapshotURL)
        let manager = CoreDataManager(persistentStoreDescriptions: [description])
        let settled = NSPredicate { _, _ in
            manager.persistentStoreLoadState != .loading
        }
        wait(
            for: [expectation(for: settled, evaluatedWith: manager, handler: nil)],
            timeout: 15
        )

        guard manager.persistentStoreLoadState == .ready else {
            XCTFail("Killed store did not recover: \(manager.persistentStoreLoadState)")
            return
        }
        let stores = manager.persistentContainer.persistentStoreCoordinator.persistentStores
        XCTAssertEqual(stores.map(\.url), [snapshotURL])
        assertCommittedMeasurement(in: manager.persistentContainer.viewContext)
        for store in stores {
            try manager.persistentContainer.persistentStoreCoordinator.remove(store)
        }
    }

    private func seedRepresentativeV1Store() throws -> URL {
        let isolatedURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KilledMidMigration-seed-\(UUID().uuidString).sqlite")
        let appBundle = Bundle(for: CoreDataManager.self)
        let modelBundle = try XCTUnwrap(
            appBundle.url(forResource: "LogYourBody", withExtension: "momd")
        )
        let v1Model = try XCTUnwrap(
            NSManagedObjectModel(contentsOf: modelBundle.appendingPathComponent("LogYourBody.mom"))
        )
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v1Model)
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: isolatedURL
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let legacyDate = Date(timeIntervalSince1970: 1_700_000_000)
        var saveError: Error?
        context.performAndWait {
            do {
                let syncMetadata = NSEntityDescription.insertNewObject(
                    forEntityName: "SyncMetadata",
                    into: context
                )
                syncMetadata.setPrimitiveValue("CachedBodyMetrics", forKey: "entityName")
                syncMetadata.setValue("legacy-id", forKey: "entityId")

                let bodyMetric = NSEntityDescription.insertNewObject(
                    forEntityName: "CachedBodyMetrics",
                    into: context
                )
                bodyMetric.setValue(Self.committedMeasurementID, forKey: "id")
                bodyMetric.setValue(Self.committedUserID, forKey: "userId")
                bodyMetric.setValue(legacyDate, forKey: "createdAt")
                bodyMetric.setValue(legacyDate, forKey: "date")
                bodyMetric.setValue(legacyDate, forKey: "lastModified")
                bodyMetric.setValue(legacyDate, forKey: "updatedAt")
                bodyMetric.setValue(Self.committedWeight, forKey: "weight")
                bodyMetric.setValue(Self.committedWeightUnit, forKey: "weightUnit")
                bodyMetric.setValue(Self.committedSource, forKey: "dataSource")
                bodyMetric.setValue(Self.committedLocalDate, forKey: "localDate")
                bodyMetric.setValue(Self.committedNote, forKey: "notes")
                try context.save()
            } catch {
                saveError = error
            }
        }
        try coordinator.remove(store)
        if let saveError {
            throw saveError
        }
        return isolatedURL
    }

    private func interruptedUncommittedWriteSnapshot(of storeURL: URL) throws -> URL {
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE, nil)
        guard opened == SQLITE_OK, let database else {
            throw MigrationFixtureError.message("sqlite open failed \(opened)")
        }

        do {
            try executeSQL(database, "PRAGMA journal_mode=WAL")
            try executeSQL(database, "PRAGMA synchronous=FULL")
            try executeSQL(database, "PRAGMA wal_autocheckpoint=0")
            try executeSQL(database, "PRAGMA cache_size=1")
            try executeSQL(database, "PRAGMA wal_checkpoint(TRUNCATE)")
            try executeSQL(database, "BEGIN IMMEDIATE")
            let changed = try writeTornMeasurement(database)
            guard changed == 1 else {
                throw MigrationFixtureError.message("torn update changed \(changed) rows")
            }
            let flushed = sqlite3_db_cacheflush(database)
            guard flushed == SQLITE_OK else {
                throw MigrationFixtureError.message("cache flush failed \(flushed)")
            }
            let walBytes = sqliteFileSize(storeURL.path + "-wal")
            guard walBytes > 32 else {
                throw MigrationFixtureError.message(
                    "uncommitted write stayed in memory (\(walBytes) WAL bytes)"
                )
            }
            let snapshotURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("KilledMidMigration-\(UUID().uuidString).sqlite")
            try copySQLiteFamily(from: storeURL, to: snapshotURL)
            try executeSQL(database, "ROLLBACK")
            sqlite3_close(database)
            return snapshotURL
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    private func writeTornMeasurement(_ database: OpaquePointer) throws -> Int {
        var catalog: OpaquePointer?
        let catalogSQL = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        guard sqlite3_prepare_v2(database, catalogSQL, -1, &catalog, nil) == SQLITE_OK, let catalog else {
            throw MigrationFixtureError.message("unable to list sqlite tables")
        }
        defer { sqlite3_finalize(catalog) }

        while sqlite3_step(catalog) == SQLITE_ROW {
            guard let rawName = sqlite3_column_text(catalog, 0) else { continue }
            let table = String(cString: rawName)
            guard Self.isSafeSQLIdentifier(table) else { continue }
            let names = try columnNames(database, table: table)
            guard let target = try measurementColumns(database, table: table, names: names) else {
                continue
            }
            let sql = """
            UPDATE \(table)
            SET \(target.weight) = 1.0, \(target.notes) = 'torn-write'
            WHERE \(target.id) = '\(Self.committedMeasurementID)'
            """
            try executeSQL(database, sql)
            return Int(sqlite3_changes(database))
        }
        return 0
    }

    private func columnNames(_ database: OpaquePointer, table: String) throws -> [String] {
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MigrationFixtureError.message("unable to read columns for \(table)")
        }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawName = sqlite3_column_text(statement, 1) else { continue }
            names.append(String(cString: rawName))
        }
        return names
    }

    private func measurementColumns(
        _ database: OpaquePointer,
        table: String,
        names: [String]
    ) throws -> (id: String, weight: String, notes: String)? {
        var statement: OpaquePointer?
        let sql = "SELECT * FROM \(table)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MigrationFixtureError.message("unable to read \(table)")
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            var idColumn: String?
            var weightColumn: String?
            var notesColumn: String?
            for index in names.indices {
                let name = names[index]
                let column = Int32(index)
                if sqlite3_column_type(statement, column) == SQLITE_TEXT,
                   let raw = sqlite3_column_text(statement, column) {
                    let text = String(cString: raw)
                    if text == Self.committedMeasurementID {
                        idColumn = name
                    } else if text == Self.committedNote {
                        notesColumn = name
                    }
                } else if sqlite3_column_type(statement, column) == SQLITE_FLOAT {
                    let value = sqlite3_column_double(statement, column)
                    if abs(value - Self.committedWeight) < 0.000001 {
                        weightColumn = name
                    }
                }
            }
            if let idColumn, let weightColumn, let notesColumn,
               Self.isSafeSQLIdentifier(idColumn),
               Self.isSafeSQLIdentifier(weightColumn),
               Self.isSafeSQLIdentifier(notesColumn) {
                return (idColumn, weightColumn, notesColumn)
            }
        }
        return nil
    }

    private func assertCommittedMeasurement(in context: NSManagedObjectContext) {
        var fetched: [NSManagedObject] = []
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CachedBodyMetrics")
            fetched = (try? context.fetch(request)) ?? []
        }
        XCTAssertEqual(fetched.count, 1)
        guard let row = fetched.first else { return }
        XCTAssertEqual(row.value(forKey: "id") as? String, Self.committedMeasurementID)
        XCTAssertEqual(row.value(forKey: "userId") as? String, Self.committedUserID)
        XCTAssertEqual(row.value(forKey: "notes") as? String, Self.committedNote)
        XCTAssertEqual(row.value(forKey: "weightUnit") as? String, Self.committedWeightUnit)
        XCTAssertEqual(row.value(forKey: "dataSource") as? String, Self.committedSource)
        XCTAssertEqual(row.value(forKey: "localDate") as? String, Self.committedLocalDate)
        let weight = (row.value(forKey: "weight") as? Double)
            ?? (row.value(forKey: "weight") as? NSNumber)?.doubleValue
        XCTAssertEqual(weight ?? -1, Self.committedWeight, accuracy: 0.000001)
        XCTAssertEqual(row.value(forKey: "date") as? Date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNotEqual(row.value(forKey: "notes") as? String, "torn-write")
    }

    private func executeSQL(_ database: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let detail = errorMessage.map { String(cString: $0) } ?? "sqlite \(result)"
            sqlite3_free(errorMessage)
            throw MigrationFixtureError.message(detail)
        }
    }

    private func copySQLiteFamily(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        try manager.copyItem(at: source, to: destination)
        for suffix in ["-wal", "-shm", "-journal"] {
            let side = URL(fileURLWithPath: source.path + suffix)
            guard manager.fileExists(atPath: side.path) else { continue }
            try manager.copyItem(at: side, to: URL(fileURLWithPath: destination.path + suffix))
        }
    }

    private func removeSQLiteFamily(_ storeURL: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    private func sqliteFileSize(_ path: String) -> Int {
        let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
        return size?.intValue ?? 0
    }

    private static func isSafeSQLIdentifier(_ value: String) -> Bool {
        value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "_"
        }
    }

    private static let committedMeasurementID = "body-metric-id"
    private static let committedUserID = "user-id"
    private static let committedWeight = 80.5
    private static let committedWeightUnit = "kg"
    private static let committedSource = "Manual"
    private static let committedLocalDate = "2026-03-08"
    private static let committedNote = "committed-note"
}

private enum MigrationFixtureError: Error {
    case message(String)
}
