import Foundation
import CoreData
import HealthKit

extension CoreDataManager {
// MARK: - Update from Server Data

    func updateOrCreateBodyMetric(from data: [String: Any]) {
        let context = viewContext

        context.perform {
            let id = data["id"] as? String ?? UUID().uuidString

            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            do {
                let results = try context.fetch(request)
                if results.first?.isMarkedDeleted == true {
                    return
                }

                let metric = results.first ?? CachedBodyMetrics(context: context)

                let formatter = ISO8601DateFormatter()

                // Update fields
                metric.id = id
                metric.userId = data["user_id"] as? String

                let rawWeight = data["weight"] as? Double ?? 0
                let rawWeightUnit = data["weight_unit"] as? String
                let weightUnitLower = rawWeightUnit?.lowercased()
                let weightKg: Double
                if rawWeight > 0 {
                    if weightUnitLower == "lbs" {
                        weightKg = rawWeight * 0.45359237
                    } else {
                        weightKg = rawWeight
                    }
                } else {
                    weightKg = 0
                }

                let rawWaistValue = (data["waist_circumference"] ?? data["waist"]) as? Double ?? 0
                let rawHipValue = (data["hip_circumference"] ?? data["hip"]) as? Double ?? 0
                let rawWaistUnit = data["waist_unit"] as? String
                let waistUnitLower = rawWaistUnit?.lowercased()

                let waistCm: Double
                if rawWaistValue > 0 {
                    if waistUnitLower == "in" {
                        waistCm = rawWaistValue * 2.54
                    } else {
                        waistCm = rawWaistValue
                    }
                } else {
                    waistCm = 0
                }

                let hipCm: Double
                if rawHipValue > 0 {
                    if waistUnitLower == "in" {
                        hipCm = rawHipValue * 2.54
                    } else {
                        hipCm = rawHipValue
                    }
                } else {
                    hipCm = 0
                }

                metric.weight = weightKg
                metric.weightUnit = rawWeightUnit
                metric.waistCircumference = waistCm
                metric.hipCircumference = hipCm
                metric.waistUnit = rawWaistUnit
                metric.bodyFatPercentage = data["body_fat_percentage"] as? Double ?? 0
                metric.bodyFatMethod = data["body_fat_method"] as? String
                metric.muscleMass = data["muscle_mass"] as? Double ?? 0
                metric.boneMass = data["bone_mass"] as? Double ?? 0
                metric.notes = data["notes"] as? String
                metric.photoUrl = data["photo_url"] as? String
                let rawDataSource = data["data_source"] as? String
                metric.dataSource = BodyMetricSource.normalizedRawValue(rawDataSource)
                if let sourceMetadata = BodyMetricSourceMetadata(jsonObject: data["source_metadata"]) {
                    metric.sourceMetadataJSON = sourceMetadata.jsonString
                } else if let rawDataSource,
                          BodyMetricSource.normalizedRawValue(rawDataSource) != rawDataSource {
                    metric.sourceMetadataJSON = BodyMetricSourceMetadata(
                        legacyDataSource: rawDataSource
                    ).jsonString
                } else {
                    metric.sourceMetadataJSON = nil
                }

                if let dateString = data["date"] as? String {
                    metric.date = formatter.date(from: dateString)
                }
                metric.localDate = BodyMetricLocalDate.normalized(
                    data["local_date"] as? String,
                    fallback: metric.date ?? Date()
                )

                if let createdString = data["created_at"] as? String,
                   let createdAt = formatter.date(from: createdString) {
                    metric.createdAt = createdAt
                }

                if let updatedString = data["updated_at"] as? String,
                   let updatedAt = formatter.date(from: updatedString) {
                    metric.updatedAt = updatedAt
                }

                metric.syncStatus = "synced"
                metric.isSynced = true
                metric.lastModified = Date()

                self.save()
            } catch {
                let appError = AppError.coreData(operation: "updateOrCreateBodyMetric", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "updateOrCreateBodyMetric",
                    screen: nil,
                    userId: data["user_id"] as? String
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Error updating body metric from server: \(error)")
            }
        }
    }

func updateOrCreateDailyMetric(from data: [String: Any]) {
        let context = viewContext

        context.perform {
            let id = data["id"] as? String ?? UUID().uuidString

            let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            do {
                let results = try context.fetch(request)
                let metric = results.first ?? CachedDailyMetrics(context: context)

                let formatter = ISO8601DateFormatter()

                // Update fields
                metric.id = id
                metric.userId = data["user_id"] as? String
                metric.steps = Int32(data["steps"] as? Int ?? 0)
                metric.notes = data["notes"] as? String

                if let dateString = data["date"] as? String {
                    metric.date = formatter.date(from: dateString)
                }

                if let createdString = data["created_at"] as? String,
                   let createdAt = formatter.date(from: createdString) {
                    metric.createdAt = createdAt
                }

                if let updatedString = data["updated_at"] as? String,
                   let updatedAt = formatter.date(from: updatedString) {
                    metric.updatedAt = updatedAt
                }

                metric.syncStatus = "synced"
                metric.isSynced = true
                metric.lastModified = Date()

                self.save()
            } catch {
                let appError = AppError.coreData(operation: "updateOrCreateDailyMetric", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "updateOrCreateDailyMetric",
                    screen: nil,
                    userId: data["user_id"] as? String
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Error updating daily metric from server: \(error)")
            }
        }
    }

func updateOrCreateProfile(from data: [String: Any]) {
        let context = viewContext

        context.perform {
            let userId = data["id"] as? String ?? ""

            let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", userId)
            request.fetchLimit = 1

            do {
                let results = try context.fetch(request)
                let profile = results.first ?? CachedProfile(context: context)

                // Update fields
                // profile.userId = userId // Using id field instead
                profile.id = userId
                profile.fullName = data["full_name"] as? String
                profile.username = data["username"] as? String
                // profile.avatarUrl = data["avatar_url"] as? String // avatarUrl field not in Core Data model
                profile.height = data["height"] as? Double ?? 0
                profile.heightUnit = data["height_unit"] as? String
                profile.gender = data["gender"] as? String
                profile.activityLevel = data["activity_level"] as? String

                if let dateString = data["date_of_birth"] as? String {
                    profile.dateOfBirth = ISO8601DateFormatter().date(from: dateString)
                }

                profile.syncStatus = "synced"
                profile.isSynced = true
                profile.lastModified = Date()

                self.save()
            } catch {
                let appError = AppError.coreData(operation: "updateOrCreateProfile", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "updateOrCreateProfile",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Error updating profile from server: \(error)")
            }
        }
    }

// MARK: - Export Methods

    /// Async version - does NOT block the main thread
    func fetchAllBodyMetrics(for userId: String) async -> [BodyMetrics] {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

            do {
                let cachedMetrics = try context.fetch(fetchRequest)
                return cachedMetrics.compactMap { $0.toBodyMetrics() }
            } catch {
                #if DEBUG
                // print("Error fetching all body metrics: \(error)")
                #endif
                return []
            }
        }
    }

@available(*, unavailable, message: "Use async fetchAllBodyMetrics(for:) instead")
    func fetchAllBodyMetricsSync(for userId: String) -> [BodyMetrics] {
        fatalError("fetchAllBodyMetricsSync has been removed. Use the async counterpart instead.")
    }

/// Async version - does NOT block the main thread
    func fetchAllDailyLogs(for userId: String) async -> [DailyLog] {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

            do {
                let cachedLogs = try context.fetch(fetchRequest)
                return cachedLogs.map { log in
                    // Extract values with explicit types to help compiler
                    let logId: String = log.id ?? UUID().uuidString
                    let logUserId: String = log.userId ?? ""
                    let logDate: Date = log.date ?? Date()
                    let logStepCount: Int? = Int(log.steps)
                    let logCreatedAt: Date = log.createdAt ?? Date()
                    let logUpdatedAt: Date = log.updatedAt ?? Date()

                    return DailyLog(
                        id: logId,
                        userId: logUserId,
                        date: logDate,
                        weight: nil,  // DailyMetrics doesn't store weight
                        weightUnit: nil,
                        stepCount: logStepCount,
                        notes: log.notes,
                        createdAt: logCreatedAt,
                        updatedAt: logUpdatedAt
                    )
                }
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchAllDailyLogs", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchAllDailyLogs",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Error fetching all daily logs: \(error)")
                #endif
                return []
            }
        }
    }

@available(*, unavailable, message: "Use async fetchAllDailyLogs(for:) instead")
    func fetchAllDailyLogsSync(for userId: String) -> [DailyLog] {
        fatalError("fetchAllDailyLogsSync has been removed. Use the async counterpart instead.")
    }

// MARK: - Debug Methods

    func debugPrintAllBodyMetrics() {
        let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()

        do {
            let allMetrics = try viewContext.fetch(fetchRequest)
            // print("🔍 DEBUG: Total body metrics in Core Data: \(allMetrics.count)")
            if let metric = allMetrics.first {
                _ = metric
                // print("  [\(index)] ID: \(metric.id ?? \"nil\"), UserId: \(metric.userId ?? \"nil\"), Weight: \(metric.weight), Date: \(metric.date ?? Date()), isSynced: \(metric.isSynced), syncStatus: \(metric.syncStatus ?? \"nil\")")
                // Commented out - only first 5 metrics would be logged
            }
        } catch {
            // print("Failed to fetch all body metrics: \(error)")
        }
    }

// MARK: - Cleanup

    func cleanupOldData() async {
        let context = viewContext

        await context.perform {
            // Delete body metrics older than 1 year
            let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)

            let bodyMetricsRequest: NSFetchRequest<NSFetchRequestResult> = CachedBodyMetrics.fetchRequest()
            bodyMetricsRequest.predicate = NSPredicate(
                format: "date < %@ AND isMarkedDeleted == true",
                oneYearAgo as NSDate
            )

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: bodyMetricsRequest)
            deleteRequest.resultType = .resultTypeObjectIDs

            do {
                if let result = try context.execute(deleteRequest) as? NSBatchDeleteResult,
                   let objectIDs = result.result as? [NSManagedObjectID],
                   !objectIDs.isEmpty {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                        into: [context]
                    )
                }
            } catch {
                // print("Error cleaning up old data: \(error)")
            }
        }
    }

func markHealthKitEntriesAsSynced() {
        let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "notes CONTAINS[c] %@", "HealthKit")

        do {
            let entries = try viewContext.fetch(fetchRequest)
            for entry in entries {
                entry.isSynced = true
                entry.syncStatus = "synced"
            }
            save()
            // print("✅ Marked \(entries.count) HealthKit entries as synced")
        } catch {
            // print("Failed to mark HealthKit entries as synced: \(error)")
        }
    }

func optimizeDatabase() {
        guard let storeURL = persistentContainer.persistentStoreDescriptions.first?.url else { return }

        do {
            let options = [NSSQLitePragmasOption: ["journal_mode": "WAL", "auto_vacuum": "FULL"]]
            try persistentContainer.persistentStoreCoordinator.replacePersistentStore(
                at: storeURL,
                destinationOptions: options,
                withPersistentStoreFrom: storeURL,
                sourceOptions: nil,
                ofType: NSSQLiteStoreType
            )
            // print("✅ Database optimized")
        } catch {
            // print("Failed to optimize database: \(error)")
        }
    }

func saveContext() {
        save()
    }

func cleanInvalidBodyMetrics() -> Int {
        let context = persistentContainer.viewContext
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()

        do {
            let allMetrics = try context.fetch(request)
            var deletedCount = 0

            for metric in allMetrics {
                var shouldDelete = false
                var reasons: [String] = []

                // Check for invalid ID
                if let id = metric.id {
                    if id.hasPrefix("test-") || UUID(uuidString: id) == nil {
                        shouldDelete = true
                        reasons.append("invalid ID: \(id)")
                    }
                } else {
                    shouldDelete = true
                    reasons.append("missing ID")
                }

                // Check for missing required fields
                if metric.date == nil {
                    shouldDelete = true
                    reasons.append("missing date")
                }

                if metric.createdAt == nil {
                    shouldDelete = true
                    reasons.append("missing createdAt")
                }

                if metric.updatedAt == nil {
                    shouldDelete = true
                    reasons.append("missing updatedAt")
                }

                if !shouldDelete, metric.localDate == nil, let date = metric.date {
                    metric.localDate = BodyMetricLocalDate.key(for: date)
                }

                if shouldDelete {
                    // print("🗑️ Deleting invalid body metric: \(reasons.joined(separator: ", "))")
                    context.delete(metric)
                    deletedCount += 1
                }
            }

            if context.hasChanges {
                try context.save()
            }

            return deletedCount
        } catch {
            // print("❌ Error cleaning invalid body metrics: \(error)")
            return 0
        }
    }

func repairCorruptedEntries() async -> Int {
        let context = persistentContainer.viewContext
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()

        return await context.perform {
            do {
                let allMetrics = try context.fetch(request)
                var repairedCount = 0

                for metric in allMetrics {
                    var wasRepaired = false

                    if metric.date == nil {
                        metric.date = Date()
                        wasRepaired = true
                    }

                    if metric.createdAt == nil {
                        metric.createdAt = metric.date ?? Date()
                        wasRepaired = true
                    }

                    if metric.updatedAt == nil {
                        metric.updatedAt = metric.lastModified ?? metric.date ?? Date()
                        wasRepaired = true
                    }

                    if metric.localDate == nil, let date = metric.date {
                        metric.localDate = BodyMetricLocalDate.key(for: date)
                        wasRepaired = true
                    }

                    if wasRepaired {
                        repairedCount += 1
                    }
                }

                if context.hasChanges {
                    try context.save()
                }

                return repairedCount
            } catch {
                return 0
            }
        }
    }

func saveGlp1DoseLogs(
        _ logs: [Glp1DoseLog],
        userId: String,
        markAsSynced: Bool = true,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard !logs.isEmpty else {
            completion?(.success(()))
            return
        }

        let context = viewContext

        context.perform {
            for log in logs {
                let request: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", log.id)
                request.fetchLimit = 1

                let cached: CachedGlp1DoseLog

                if let existing = try? context.fetch(request).first {
                    cached = existing
                } else {
                    cached = CachedGlp1DoseLog(context: context)
                    cached.id = log.id
                    cached.createdAt = log.createdAt
                }

                if markAsSynced, cached.isMarkedDeleted {
                    continue
                }

                cached.userId = userId
                cached.takenAt = log.takenAt
                cached.medicationId = log.medicationId
                cached.doseAmount = log.doseAmount ?? 0
                cached.doseUnit = log.doseUnit
                cached.drugClass = log.drugClass
                cached.brand = log.brand
                cached.isCompounded = log.isCompounded
                cached.supplierType = log.supplierType
                cached.supplierName = log.supplierName
                cached.notes = log.notes
                cached.updatedAt = log.updatedAt
                cached.isMarkedDeleted = false
                cached.isSynced = markAsSynced
                cached.syncStatus = markAsSynced ? "synced" : "pending"
            }

            do {
                if context.hasChanges {
                    try context.save()
                }
                completion?(.success(()))
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "saveGlp1DoseLogs", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "saveGlp1DoseLogs",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                completion?(.failure(error))
            }
        }
    }

func saveGlp1DoseLogsAndWait(
        _ logs: [Glp1DoseLog],
        userId: String,
        markAsSynced: Bool = true
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            saveGlp1DoseLogs(logs, userId: userId, markAsSynced: markAsSynced) { result in
                continuation.resume(with: result)
            }
        }
    }

func fetchGlp1DoseLogs(for userId: String) async -> [Glp1DoseLog] {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "userId == %@", userId),
                NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false))
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "takenAt", ascending: true)]

            do {
                let cachedLogs = try context.fetch(request)
                return cachedLogs.compactMap { $0.toGlp1DoseLog() }
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchGlp1DoseLogs", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchGlp1DoseLogs",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return []
            }
        }
    }
}
