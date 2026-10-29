import CoreData
import Foundation

extension CoreDataManager {
    /// Commit an overlay in isolation, without saving unrelated view-context edits.
    /// The identity, owner and expected version must still match at commit time.
    func updateMetricOverlayAndWait(
        expected: BodyMetrics, excluded: Bool, correctedValue: MetricCorrectedValue?,
        writeAdmission: @escaping WriteAdmission,
        commit: @escaping (NSManagedObjectContext) throws -> Void = { try $0.save() }
    ) async throws -> PhotoMetricsUpdateResult {
        guard correctedValue == nil || correctedValue?.isValid == true else { throw MetricCorrectionError.invalidValue }
        let shared = viewContext
        return try await shared.perform {
            try MainActor.assumeIsolated { try writeAdmission() }
            let dirty = shared.insertedObjects.union(shared.updatedObjects).union(shared.deletedObjects)
            guard !dirty.contains(where: {
                guard let row = $0 as? CachedBodyMetrics else { return false }
                return row.id == expected.id ||
                    row.committedValues(forKeys: ["id"])["id"] as? String == expected.id
            }) else { throw PhotoMetricsEditError.pendingEdit }
            let transaction = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            transaction.persistentStoreCoordinator = shared.persistentStoreCoordinator
            transaction.mergePolicy = NSErrorMergePolicy
            transaction.undoManager = nil
            return try transaction.performAndWait {
                let request = CachedBodyMetrics.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", expected.id)
                let rows = try transaction.fetch(request)
                guard rows.count == 1, let row = rows.first, row.userId == expected.userId, !row.isMarkedDeleted,
                      row.toBodyMetrics() == expected else { throw MetricCorrectionError.entryChanged }
                do {
                    row.isExcluded = excluded
                    row.correctedValueJSON = correctedValue?.jsonString
                    if transaction.hasChanges {
                        let now = Date()
                        row.updatedAt = now
                        row.lastModified = now
                        row.isSynced = false
                        row.syncStatus = "pending"
                        try MainActor.assumeIsolated { try writeAdmission() }
                        try commit(transaction)
                        guard !transaction.hasChanges else { throw PhotoMetricsEditError.uncommittedWrite }
                        NSManagedObjectContext.mergeChanges(
                            fromRemoteContextSave: [NSUpdatedObjectsKey: [row.objectID]], into: [shared]
                        )
                    }
                    guard let updated = row.toBodyMetrics() else { throw MetricCorrectionError.entryChanged }
                    return PhotoMetricsUpdateResult(metrics: updated, createdNewEntry: false, previousMetric: expected)
                } catch {
                    transaction.rollback()
                    throw error
                }
            }
        }
    }
}
