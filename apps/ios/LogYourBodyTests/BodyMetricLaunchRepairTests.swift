import XCTest
import CoreData
@testable import LogYourBody

@MainActor
final class BodyMetricLaunchRepairTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var manager: CoreDataManager!
    private let repairedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let metricID = "launch-repair-corrupt"

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "BodyMetricLaunchRepairTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        manager = CoreDataManager(persistentStoreDescriptions: [store])
        BodyMetricLaunchRepair.bodyMetricFetchCount = 0
    }

    override func tearDown() {
        if let manager {
            for store in manager.persistentContainer.persistentStoreCoordinator.persistentStores {
                try? manager.persistentContainer.persistentStoreCoordinator.remove(store)
            }
        }
        manager = nil
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        BodyMetricLaunchRepair.bodyMetricFetchCount = 0
        super.tearDown()
    }

    func testCleanRelaunchSkipsFetchAndGenerationChangeRepairsOffViewContext() async throws {
        try await insertCorruptMetric()
        let viewContext = manager.persistentContainer.viewContext

        let first = await launch()
        XCTAssertEqual(BodyMetricLaunchRepair.bodyMetricFetchCount, 1)
        XCTAssertTrue(first.didFetchBodyMetrics)
        XCTAssertEqual(first.repairedCount, 1)
        XCTAssertFalse(first.repairContextIsViewContext)
        XCTAssertNotEqual(first.repairContextID, Optional(ObjectIdentifier(viewContext)))
        XCTAssertEqual(first.repairConcurrency, Optional(.privateQueueConcurrencyType))

        let storedAfterFirst = try await storedMetric()
        let repaired = try XCTUnwrap(storedAfterFirst)
        XCTAssertEqual(repaired.date, Optional(repairedAt))
        XCTAssertEqual(repaired.createdAt, Optional(repairedAt))
        XCTAssertEqual(repaired.updatedAt, Optional(repairedAt))
        XCTAssertEqual(repaired.localDate, Optional(BodyMetricLocalDate.key(for: repairedAt)))
        XCTAssertEqual(repaired.weight, 81.5, accuracy: 0.001)
        let receipt = try storedReceipt()
        XCTAssertEqual(receipt.generation, BodyMetricLaunchRepair.storeRepairGeneration)
        XCTAssertEqual(receipt.completedAt.timeIntervalSince1970, repairedAt.timeIntervalSince1970, accuracy: 0.001)

        let second = await launch()
        XCTAssertEqual(BodyMetricLaunchRepair.bodyMetricFetchCount, 1)
        XCTAssertFalse(second.didFetchBodyMetrics)
        XCTAssertNil(second.repairContextID)
        XCTAssertFalse(second.repairContextIsViewContext)
        let storedAfterSkip = try await storedMetric()
        let afterSkip = try XCTUnwrap(storedAfterSkip)
        XCTAssertEqual(afterSkip.updatedAt, Optional(repairedAt))
        XCTAssertEqual(afterSkip.localDate, repaired.localDate)
        let receiptAfterSkip = try storedReceipt()
        XCTAssertEqual(receiptAfterSkip, receipt)

        try await clearLocalDate()
        let nextGeneration = BodyMetricLaunchRepair.storeRepairGeneration + 1
        let third = await launch(generation: nextGeneration)
        XCTAssertEqual(BodyMetricLaunchRepair.bodyMetricFetchCount, 2)
        XCTAssertTrue(third.didFetchBodyMetrics)
        XCTAssertEqual(third.repairedCount, 1)
        XCTAssertFalse(third.repairContextIsViewContext)
        XCTAssertNotEqual(third.repairContextID, Optional(ObjectIdentifier(viewContext)))
        XCTAssertEqual(third.repairConcurrency, Optional(.privateQueueConcurrencyType))
        let storedAfterRerun = try await storedMetric()
        let rerun = try XCTUnwrap(storedAfterRerun)
        XCTAssertEqual(rerun.localDate, Optional(BodyMetricLocalDate.key(for: repairedAt)))
        XCTAssertEqual(try storedReceipt().generation, nextGeneration)
    }

    private func launch(generation: Int? = nil) async -> BodyMetricLaunchRepair.RunResult {
        if let generation {
            return await BodyMetricLaunchRepair.runOnBackgroundContext(
                container: manager.persistentContainer,
                defaults: defaults,
                generation: generation,
                now: repairedAt
            )
        }
        return await BodyMetricLaunchRepair.runOnBackgroundContext(
            container: manager.persistentContainer,
            defaults: defaults,
            now: repairedAt
        )
    }

    private func insertCorruptMetric() async throws {
        let context = manager.persistentContainer.newBackgroundContext()
        let metricID = metricID
        let repairedAt = repairedAt
        try await context.perform {
            let row = CachedBodyMetrics(context: context)
            row.id = metricID
            row.userId = "launch-repair-owner"
            row.weight = 81.5
            row.date = nil
            row.createdAt = nil
            row.updatedAt = nil
            row.localDate = nil
            row.lastModified = repairedAt
            try context.save()
        }
    }

    private func clearLocalDate() async throws {
        let context = manager.persistentContainer.newBackgroundContext()
        let metricID = metricID
        try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", metricID)
            request.fetchLimit = 1
            let row = try XCTUnwrap(context.fetch(request).first)
            row.localDate = nil
            try context.save()
        }
    }

    private func storedMetric() async throws -> StoredMetric? {
        let context = manager.persistentContainer.newBackgroundContext()
        let metricID = metricID
        return try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", metricID)
            request.fetchLimit = 1
            guard let row = try context.fetch(request).first else { return nil }
            return StoredMetric(
                date: row.date,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                localDate: row.localDate,
                weight: row.weight
            )
        }
    }

    private func storedReceipt() throws -> BodyMetricLaunchRepair.Receipt {
        let data = try XCTUnwrap(defaults.data(forKey: BodyMetricLaunchRepair.receiptDefaultsKey))
        return try JSONDecoder().decode(BodyMetricLaunchRepair.Receipt.self, from: data)
    }
}

private struct StoredMetric {
    var date: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var localDate: String?
    var weight: Double
}
