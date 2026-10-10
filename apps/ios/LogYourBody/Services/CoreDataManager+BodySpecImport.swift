import CoreData
import Foundation

enum BodySpecPairCommitOutcome: Equatable {
    case inserted
    case repaired
    case duplicate
}

enum BodySpecImportPersistenceError: Error, Equatable {
    case invalidPair
    case conflictingRecords
}

extension CoreDataManager {
    @MainActor
    func hasCompleteBodySpecImportPair(
        externalID: String, userId: String, writeAdmission: WriteAdmission
    ) throws -> Bool {
        try Task.checkCancellation()
        try writeAdmission()
        return try BodySpecImportTransaction(
            context: makeBodySpecImportContext(), viewContext: viewContext, owner: userId
        ).hasCompletePair(externalID: externalID)
    }

    /// Admission, duplicate lookup and the single durable save cannot suspend between one another.
    @MainActor
    func commitBodySpecImportPair(
        metric: BodyMetrics, result: DexaResult, userId: String,
        writeAdmission: WriteAdmission
    ) throws -> BodySpecPairCommitOutcome {
        try Task.checkCancellation()
        try writeAdmission()
        let context = makeBodySpecImportContext()
        let transaction = BodySpecImportTransaction(context: context, viewContext: viewContext, owner: userId)
        do {
            let outcome = try transaction.prepare(metric: metric, result: result)
            guard context.hasChanges else { return outcome }
            let inserted = Array(context.insertedObjects)
            try context.save()
            // Only new objects are merged. Existing rows and their unsaved edits are never rewritten.
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSInsertedObjectsKey: inserted.map(\.objectID)], into: [viewContext]
            )
            return outcome
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    private func makeBodySpecImportContext() -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = persistentContainer.persistentStoreCoordinator
        return context
    }
}

@MainActor
private struct BodySpecImportTransaction {
    let context: NSManagedObjectContext
    let viewContext: NSManagedObjectContext
    let owner: String

    func hasCompletePair(externalID: String) throws -> Bool {
        let results: [CachedDexaResult] = try fetch(
            "CachedDexaResult", predicate: NSPredicate(
                format: "userId == %@ AND externalSource == %@ AND externalResultId == %@",
                owner, "bodyspec", externalID
            )
        )
        guard results.count <= 1 else { throw conflict }
        guard let result = results.first, let link = result.bodyMetricsId else {
            if !results.isEmpty { throw conflict }
            return false
        }
        let metrics: [CachedBodyMetrics] = try fetch(
            "CachedBodyMetrics", predicate: NSPredicate(format: "id == %@", link)
        )
        guard metrics.count == 1, let date = result.acquireTime ?? metrics.first?.date else { throw conflict }
        try rejectUnsavedIdentityChanges(metricID: link, resultID: result.id ?? "", externalID: externalID)
        let matches = try matchingMetrics(externalID: externalID, date: date)
        guard matches.count == 1 else { throw conflict }
        try validateCompletePair(result, matches: matches, externalID: externalID)
        return true
    }

    func prepare(metric: BodyMetrics, result: DexaResult) throws -> BodySpecPairCommitOutcome {
        guard !owner.isEmpty, metric.userId == owner, result.userId == owner,
              !metric.id.isEmpty, !result.id.isEmpty,
              result.bodyMetricsId == metric.id, result.externalSource == "bodyspec",
              !result.externalResultId.isEmpty,
              metric.sourceMetadata?.externalResultId == result.externalResultId,
              BodyMetricSource.normalizedRawValue(metric.dataSource) == BodyMetricSource.bodySpecDexa.rawValue else {
            throw BodySpecImportPersistenceError.invalidPair
        }
        try rejectOccupiedCandidateIDs(metric: metric, result: result)
        try rejectUnsavedIdentityChanges(
            metricID: metric.id, resultID: result.id, externalID: result.externalResultId
        )
        let results: [CachedDexaResult] = try fetch(
            "CachedDexaResult", predicate: NSPredicate(
                format: "userId == %@ AND externalSource == %@ AND externalResultId == %@",
                owner, "bodyspec", result.externalResultId
            )
        )
        let metrics = try matchingMetrics(externalID: result.externalResultId, date: metric.date)
        guard results.count <= 1, metrics.count <= 1 else { throw conflict }
        if let existing = results.first {
            try validateCompletePair(existing, matches: metrics, externalID: result.externalResultId)
            return .duplicate
        }
        let existing = metrics.first
        if let existing {
            try rejectUnsavedIdentityChanges(
                metricID: existing.id ?? "", resultID: result.id, externalID: result.externalResultId
            )
            try validateMetric(existing, externalID: result.externalResultId)
            try validateReverseLink(metricID: existing.id ?? "", expected: nil)
        }
        let metricID = existing?.id ?? metric.id
        if existing == nil { insertMetric(metric) }
        insertResult(result, metricID: metricID)
        return existing == nil ? .inserted : .repaired
    }

    private var conflict: BodySpecImportPersistenceError { .conflictingRecords }

    private func fetch<T: NSManagedObject>(_ entity: String, predicate: NSPredicate) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: entity)
        request.predicate = predicate
        return try context.fetch(request)
    }

    private func rejectOccupiedCandidateIDs(metric: BodyMetrics, result: DexaResult) throws {
        let metrics: [CachedBodyMetrics] = try fetch(
            "CachedBodyMetrics", predicate: NSPredicate(format: "id == %@", metric.id)
        )
        let results: [CachedDexaResult] = try fetch(
            "CachedDexaResult", predicate: NSPredicate(format: "id == %@", result.id)
        )
        guard metrics.count <= 1, results.count <= 1,
              metrics.allSatisfy({ $0.userId == owner &&
                  BodyMetricSourceMetadata(jsonString: $0.sourceMetadataJSON)?.externalResultId ==
                      result.externalResultId }),
              results.allSatisfy({ $0.userId == owner && $0.externalSource == "bodyspec" &&
                  $0.externalResultId == result.externalResultId }) else { throw conflict }
    }

    private func matchingMetrics(externalID: String, date: Date) throws -> [CachedBodyMetrics] {
        let rows: [CachedBodyMetrics] = try fetch(
            "CachedBodyMetrics", predicate: NSPredicate(format: "userId == %@", owner)
        )
        return rows.filter { row in
            let rowExternalID = BodyMetricSourceMetadata(jsonString: row.sourceMetadataJSON)?.externalResultId
            if rowExternalID == externalID { return true }
            guard rowExternalID == nil, let rowDate = row.date,
                  abs(rowDate.timeIntervalSince(date)) < 60 else { return false }
            return BodyMetricSource.normalizedRawValue(row.dataSource) == BodyMetricSource.bodySpecDexa.rawValue ||
                row.notes?.localizedCaseInsensitiveContains("BodySpec") == true
        }
    }

    private func validateMetric(_ metric: CachedBodyMetrics, externalID: String) throws {
        guard metric.userId == owner, metric.id != nil, !metric.isMarkedDeleted,
              BodyMetricSource.normalizedRawValue(metric.dataSource) == BodyMetricSource.bodySpecDexa.rawValue,
              BodyMetricSourceMetadata(jsonString: metric.sourceMetadataJSON)?.externalResultId == externalID else {
            throw conflict
        }
        let sameID: [CachedBodyMetrics] = try fetch(
            "CachedBodyMetrics", predicate: NSPredicate(format: "id == %@", metric.id ?? "")
        )
        guard sameID.count == 1 else { throw conflict }
        // Inspect the registered view object too: a pending local tombstone must not be resurrected.
        if let visible = viewContext.registeredObject(for: metric.objectID) as? CachedBodyMetrics {
            guard !visible.isDeleted, !visible.isMarkedDeleted, visible.userId == owner,
                  visible.id == metric.id,
                  BodyMetricSource.normalizedRawValue(visible.dataSource) == BodyMetricSource.bodySpecDexa.rawValue,
                  BodyMetricSourceMetadata(jsonString: visible.sourceMetadataJSON)?.externalResultId == externalID else {
                throw conflict
            }
        }
    }

    private func validateCompletePair(
        _ existing: CachedDexaResult, matches: [CachedBodyMetrics], externalID: String
    ) throws {
        guard let link = existing.bodyMetricsId, let metric = matches.first, metric.id == link else {
            throw conflict
        }
        let sameID: [CachedDexaResult] = try fetch(
            "CachedDexaResult", predicate: NSPredicate(format: "id == %@", existing.id ?? "")
        )
        guard sameID.count == 1 else { throw conflict }
        try validateMetric(metric, externalID: externalID)
        try validateReverseLink(metricID: link, expected: existing.objectID)
        if let visible = viewContext.registeredObject(for: existing.objectID) as? CachedDexaResult {
            guard !visible.isDeleted, visible.id == existing.id, visible.userId == owner, visible.bodyMetricsId == link,
                  visible.externalSource == "bodyspec", visible.externalResultId == externalID else {
                throw conflict
            }
        }
    }

    private func validateReverseLink(metricID: String, expected: NSManagedObjectID?) throws {
        let links: [CachedDexaResult] = try fetch(
            "CachedDexaResult", predicate: NSPredicate(format: "bodyMetricsId == %@", metricID)
        )
        if let expected {
            guard links.count == 1, links.first?.objectID == expected else { throw conflict }
        } else {
            guard links.isEmpty else { throw conflict }
        }
    }

    private func rejectUnsavedIdentityChanges(metricID: String, resultID: String, externalID: String) throws {
        let pending = viewContext.insertedObjects.union(viewContext.deletedObjects).union(viewContext.updatedObjects)
        for object in pending {
            let keys: [String]
            if object is CachedBodyMetrics {
                keys = ["id", "userId", "dataSource", "sourceMetadataJSON"]
            } else if object is CachedDexaResult {
                keys = ["id", "userId", "externalSource", "externalResultId", "bodyMetricsId"]
            } else { continue }
            let current = object.dictionaryWithValues(forKeys: keys)
            let committed = object.committedValues(forKeys: keys)
            let relevant = [current, committed].contains { values in
                if object is CachedBodyMetrics {
                    return values["id"] as? String == metricID ||
                        (values["userId"] as? String == owner && externalMetricID(values) == externalID)
                }
                return values["id"] as? String == resultID || values["bodyMetricsId"] as? String == metricID ||
                    (values["userId"] as? String == owner && values["externalSource"] as? String == "bodyspec" &&
                        values["externalResultId"] as? String == externalID)
            }
            guard relevant else { continue }
            let identityChanged = keys.contains { key in
                if key == "sourceMetadataJSON" { return externalMetricID(current) != externalMetricID(committed) }
                return current[key] as? String != committed[key] as? String
            }
            if object.isInserted || object.isDeleted || identityChanged { throw conflict }
        }
    }

    private func externalMetricID(_ values: [String: Any]) -> String? {
        BodyMetricSourceMetadata(jsonString: values["sourceMetadataJSON"] as? String)?.externalResultId
    }

    private func insertMetric(_ metric: BodyMetrics) {
        let row = CachedBodyMetrics(context: context)
        row.id = metric.id
        row.userId = owner
        row.date = metric.date
        row.localDate = metric.localDate
        row.weight = metric.weight ?? 0
        row.weightUnit = metric.weightUnit
        row.waistCircumference = metric.waistCm ?? 0
        row.hipCircumference = metric.hipCm ?? 0
        row.waistUnit = metric.waistUnit
        row.bodyFatPercentage = metric.bodyFatPercentage ?? 0
        row.bodyFatMethod = metric.bodyFatMethod
        row.muscleMass = metric.muscleMass ?? 0
        row.boneMass = metric.boneMass ?? 0
        row.notes = metric.notes
        row.photoUrl = metric.photoUrl
        row.dataSource = metric.dataSource
        row.sourceMetadataJSON = metric.sourceMetadata?.jsonString
        row.createdAt = metric.createdAt
        row.updatedAt = metric.updatedAt
        row.lastModified = metric.updatedAt
        row.isSynced = false
        row.syncStatus = "pending"
        row.isMarkedDeleted = false
    }

    private func insertResult(_ result: DexaResult, metricID: String) {
        let row = CachedDexaResult(context: context)
        row.id = result.id
        row.userId = owner
        row.bodyMetricsId = metricID
        row.externalSource = result.externalSource
        row.externalResultId = result.externalResultId
        row.externalUpdateTime = result.externalUpdateTime
        row.scannerModel = result.scannerModel
        row.locationId = result.locationId
        row.locationName = result.locationName
        row.acquireTime = result.acquireTime
        row.analyzeTime = result.analyzeTime
        row.vatMassKg = result.vatMassKg ?? 0
        row.vatVolumeCm3 = result.vatVolumeCm3 ?? 0
        row.scanWeight = result.scanWeight ?? 0
        row.scanWeightUnit = result.scanWeightUnit
        row.bodyFatPercentage = result.bodyFatPercentage ?? 0
        row.muscleMass = result.muscleMass ?? 0
        row.boneMass = result.boneMass ?? 0
        row.resultPdfUrl = result.resultPdfUrl
        row.resultPdfName = result.resultPdfName
        row.createdAt = result.createdAt
        row.updatedAt = result.updatedAt
        row.isSynced = false
        row.syncStatus = "pending"
    }
}
