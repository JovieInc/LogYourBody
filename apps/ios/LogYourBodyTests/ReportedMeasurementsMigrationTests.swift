import XCTest
import CoreData
@testable import LogYourBody

final class ReportedMeasurementsMigrationTests: XCTestCase {
    func testV1ScanMigratesWithoutInventingMeasurements() throws {
        try verifyMigration(version: "LogYourBody", hasScanScalars: false)
    }

    func testV2ScanMigratesWithoutInventingMeasurements() throws {
        try verifyMigration(version: "LogYourBodyV2", hasScanScalars: false)
    }

    func testV3ScanMigratesAndRetainsHistoricalMuscleScalar() throws {
        try verifyMigration(version: "LogYourBodyV3", hasScanScalars: true)
    }

    private func verifyMigration(version: String, hasScanScalars: Bool) throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Typed-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let bundle = Bundle(for: CoreDataManager.self)
        let modelBundle = try XCTUnwrap(bundle.url(forResource: "LogYourBody", withExtension: "momd"))
        let oldModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelBundle.appendingPathComponent("\(version).mom")))
        XCTAssertNil(oldModel.entitiesByName["CachedDexaResult"]?.attributesByName["reportedMeasurementsJSON"])
        try seed(model: oldModel, at: url, hasScanScalars: hasScanScalars)

        let currentModel = CoreDataManager.makeManagedObjectModel(in: bundle)
        let attribute = try XCTUnwrap(
            currentModel.entitiesByName["CachedDexaResult"]?.attributesByName["reportedMeasurementsJSON"]
        )
        XCTAssertTrue(attribute.isOptional)
        XCTAssertEqual(attribute.attributeType, .stringAttributeType)
        // Opening twice proves the migrated data is durable, not just available in memory.
        for _ in 0..<2 {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: currentModel)
            let store = try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                options: [NSMigratePersistentStoresAutomaticallyOption: true,
                          NSInferMappingModelAutomaticallyOption: true]
            )
            defer { try? coordinator.remove(store) }
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            try context.performAndWait {
                let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "CachedDexaResult"))
                XCTAssertEqual(rows.count, 1)
                let row = try XCTUnwrap(rows.first)
                XCTAssertEqual(row.value(forKey: "id") as? String, "scan-id")
                XCTAssertEqual(row.value(forKey: "userId") as? String, "scan-owner")
                XCTAssertEqual(row.value(forKey: "externalSource") as? String, "legacy-report-source")
                XCTAssertEqual(row.value(forKey: "externalResultId") as? String, "external-scan-id")
                XCTAssertEqual(row.value(forKey: "bodyMetricsId") as? String, "metric-id")
                XCTAssertEqual(row.value(forKey: "createdAt") as? Date, fixtureDate)
                XCTAssertEqual(row.value(forKey: "acquireTime") as? Date, fixtureDate)
                XCTAssertEqual(row.value(forKey: "vatMassKg") as? Double, 1.2)
                XCTAssertEqual(row.value(forKey: "isSynced") as? Bool, false)
                XCTAssertEqual(row.value(forKey: "syncStatus") as? String, "pending")
                XCTAssertNil(row.value(forKey: "reportedMeasurementsJSON"))
                if hasScanScalars {
                    XCTAssertEqual(row.value(forKey: "scanWeight") as? Double, 80)
                    XCTAssertEqual(row.value(forKey: "muscleMass") as? Double, 12.5)
                    XCTAssertEqual(row.value(forKey: "bodyFatPercentage") as? Double, 20)
                }
                let metrics = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "CachedBodyMetrics"))
                XCTAssertEqual(metrics.count, 1)
                XCTAssertEqual(metrics.first?.value(forKey: "id") as? String, row.value(forKey: "bodyMetricsId") as? String)
                XCTAssertEqual(metrics.first?.value(forKey: "weight") as? Double, 80)
            }
        }
    }

    private var fixtureDate: Date { Date(timeIntervalSince1970: 1_735_200_000) }

    private func seed(model: NSManagedObjectModel, at url: URL, hasScanScalars: Bool) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let row = NSEntityDescription.insertNewObject(forEntityName: "CachedDexaResult", into: context)
            let fields: [String: Any] = [
                "id": "scan-id", "userId": "scan-owner", "externalSource": "legacy-report-source",
                "externalResultId": "external-scan-id", "bodyMetricsId": "metric-id",
                "createdAt": fixtureDate, "updatedAt": fixtureDate, "acquireTime": fixtureDate,
                "vatMassKg": 1.2, "isSynced": false, "syncStatus": "pending"
            ]
            fields.forEach { row.setValue($0.value, forKey: $0.key) }
            if hasScanScalars {
                row.setValue(80, forKey: "scanWeight")
                row.setValue(12.5, forKey: "muscleMass")
                row.setValue(20, forKey: "bodyFatPercentage")
            }
            let metric = NSEntityDescription.insertNewObject(forEntityName: "CachedBodyMetrics", into: context)
            metric.setValue("metric-id", forKey: "id")
            metric.setValue("scan-owner", forKey: "userId")
            for field in ["date", "createdAt", "updatedAt", "lastModified"] {
                metric.setValue(fixtureDate, forKey: field)
            }
            metric.setValue(80, forKey: "weight")
            try context.save()
        }
    }
}
