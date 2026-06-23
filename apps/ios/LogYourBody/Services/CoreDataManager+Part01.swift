import Foundation
import CoreData
import HealthKit

extension CoreDataManager {
var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

// MARK: - Save Context
    func save(completion: (() -> Void)? = nil) {
        saveQueue.async { [weak self] in
            guard let self = self else {
                completion?()
                return
            }

            // Prevent recursive saves
            guard !self.isSaving else {
                // print("⚠️ Prevented recursive Core Data save")
                completion?()
                return
            }

            self.isSaving = true
            defer { self.isSaving = false }

            let context = self.viewContext

            // Perform save asynchronously on the context's queue
            context.perform {
                if context.hasChanges {
                    do {
                        try context.save()
                        // print("✅ Core Data context saved successfully")
                    } catch {
                        let appError = AppError.coreData(operation: "saveContext", underlying: error)
                        let contextInfo = ErrorContext(
                            feature: "coreData",
                            operation: "save",
                            screen: nil,
                            userId: nil
                        )
                        ErrorReporter.shared.capture(appError, context: contextInfo)
                        // print("Failed to save Core Data context: \(error)")
                    }
                }
                completion?()
            }
        }
    }

func saveDailyMetrics(
        _ metrics: DailyMetrics,
        userId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let context = viewContext

        context.perform {
            let fetchRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", metrics.id)
            fetchRequest.fetchLimit = 1

            let cached: CachedDailyMetrics

            if let existing = try? context.fetch(fetchRequest).first {
                cached = existing
            } else {
                cached = CachedDailyMetrics(context: context)
                cached.id = metrics.id
                cached.createdAt = metrics.createdAt
            }

            cached.userId = userId
            cached.date = metrics.date
            cached.steps = Int32(metrics.steps ?? 0)
            cached.notes = metrics.notes
            cached.updatedAt = metrics.updatedAt
            cached.lastModified = Date()
            cached.isSynced = false
            cached.syncStatus = "pending"
            cached.isMarkedDeleted = false

            do {
                if context.hasChanges {
                    try context.save()
                }
                completion?(.success(()))
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "saveDailyMetrics", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "saveDailyMetrics",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Failed to save daily metrics: \(error)")
                #endif
                completion?(.failure(error))
            }
        }
    }

func saveDailyMetricsAndWait(_ metrics: DailyMetrics, userId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            saveDailyMetrics(metrics, userId: userId) { result in
                continuation.resume(with: result)
            }
        }
    }

@available(*, unavailable, message: "Use async fetchDailyMetrics(for:date:) instead")
    func fetchDailyMetricsSync(
        for userId: String,
        date: Date
    ) -> CachedDailyMetrics? {
        nil
    }

@available(*, unavailable, message: "Use async fetchDailyMetrics(for:from:to:) instead")
    func fetchDailyMetricsSync(
        for userId: String,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) -> [CachedDailyMetrics] {
        []
    }

// MARK: - Daily Metrics Fetch Helpers

    func fetchDailyMetrics(
        for userId: String,
        date: Date
    ) async -> CachedDailyMetrics? {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            let startOfDay = Calendar.current.startOfDay(for: date)
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

            request.predicate = NSPredicate(
                format: "userId == %@ AND date >= %@ AND date < %@ AND isMarkedDeleted == %@",
                userId,
                startOfDay as NSDate,
                endOfDay as NSDate,
                NSNumber(value: false)
            )
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

func fetchDailyMetrics(
        for userId: String,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) async -> [CachedDailyMetrics] {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            var predicates: [NSPredicate] = [
                NSPredicate(format: "userId == %@", userId),
                NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false))
            ]

            if let startDate {
                predicates.append(NSPredicate(format: "date >= %@", startDate as NSDate))
            }

            if let endDate {
                predicates.append(NSPredicate(format: "date <= %@", endDate as NSDate))
            }

            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

            do {
                return try context.fetch(request)
            } catch {
                #if DEBUG
                // print("Failed to fetch daily metrics: \(error)")
                #endif
                return []
            }
        }
    }

func fetchUnsyncedDexaResults(for userId: String? = nil) async -> [CachedDexaResult] {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedDexaResult> = CachedDexaResult.fetchRequest()
            var predicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
            if let userId {
                predicates.append(NSPredicate(format: "userId == %@", userId))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            do {
                return try context.fetch(request)
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchUnsyncedDexaResults", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchUnsyncedDexaResults",
                    screen: nil,
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return []
            }
        }
    }

func fetchDexaResults(for userId: String, limit: Int) async -> [DexaResult] {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedDexaResult> = CachedDexaResult.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", userId)
            request.sortDescriptors = [
                NSSortDescriptor(key: "acquireTime", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]
            request.fetchLimit = limit

            do {
                let cached = try context.fetch(request)
                return cached.compactMap { $0.toDexaResult() }
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchDexaResults", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchDexaResults",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return []
            }
        }
    }

func saveDexaResults(
        _ results: [DexaResult],
        userId: String,
        markAsSynced: Bool = false,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard !results.isEmpty else {
            completion?(.success(()))
            return
        }

        let context = viewContext

        context.perform {
            let fetchRequest: NSFetchRequest<CachedDexaResult> = CachedDexaResult.fetchRequest()

            for result in results {
                fetchRequest.predicate = NSPredicate(format: "id == %@", result.id)
                fetchRequest.fetchLimit = 1

                let cached: CachedDexaResult
                if let existing = try? context.fetch(fetchRequest).first {
                    cached = existing
                } else {
                    cached = CachedDexaResult(context: context)
                    cached.id = result.id
                    cached.createdAt = result.createdAt
                }

                cached.userId = userId
                cached.bodyMetricsId = result.bodyMetricsId
                cached.externalSource = result.externalSource
                cached.externalResultId = result.externalResultId
                cached.externalUpdateTime = result.externalUpdateTime
                cached.scannerModel = result.scannerModel
                cached.locationId = result.locationId
                cached.locationName = result.locationName
                cached.acquireTime = result.acquireTime
                cached.analyzeTime = result.analyzeTime
                cached.vatMassKg = result.vatMassKg ?? 0
                cached.vatVolumeCm3 = result.vatVolumeCm3 ?? 0
                cached.resultPdfUrl = result.resultPdfUrl
                cached.resultPdfName = result.resultPdfName
                cached.updatedAt = result.updatedAt
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
                let appError = AppError.coreData(operation: "saveDexaResults", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "saveDexaResults",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                completion?(.failure(error))
            }
        }
    }

func saveDexaResultsAndWait(_ results: [DexaResult], userId: String, markAsSynced: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            saveDexaResults(results, userId: userId, markAsSynced: markAsSynced) { result in
                continuation.resume(with: result)
            }
        }
    }

func upsertDevice(withId id: String, update: @escaping (CachedDevice) -> Void) async -> CachedDevice? {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedDevice> = CachedDevice.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            let device: CachedDevice
            if let existing = try? context.fetch(request).first {
                device = existing
            } else {
                device = CachedDevice(context: context)
                device.id = id
                device.createdAt = Date()
            }

            update(device)
            device.updatedAt = Date()

            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                // print("Failed to upsert device: \(error)")
                #endif
            }

            return device
        }
    }

func upsertUserDevice(withId id: String, update: @escaping (CachedUserDevice) -> Void) async -> CachedUserDevice? {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedUserDevice> = CachedUserDevice.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            let userDevice: CachedUserDevice
            if let existing = try? context.fetch(request).first {
                userDevice = existing
            } else {
                userDevice = CachedUserDevice(context: context)
                userDevice.id = id
                userDevice.createdAt = Date()
            }

            update(userDevice)
            userDevice.updatedAt = Date()

            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                // print("Failed to upsert user device: \(error)")
                #endif
            }

            return userDevice
        }
    }

func saveAsync() async {
        let context = viewContext

        await context.perform {
            if context.hasChanges {
                do {
                    try context.save()
                    // print("✅ Core Data context saved asynchronously")
                } catch {
                    let appError = AppError.coreData(operation: "saveAsync", underlying: error)
                    let contextInfo = ErrorContext(
                        feature: "coreData",
                        operation: "saveAsync",
                        screen: nil,
                        userId: nil
                    )
                    ErrorReporter.shared.capture(appError, context: contextInfo)
                    // print("Failed to save Core Data context: \(error)")
                }
            }
        }
    }

func saveAndWait() {
        save()
    }

// MARK: - Body Metrics Operations
    func saveBodyMetrics(
        _ metrics: BodyMetrics,
        userId: String,
        markAsSynced: Bool = false,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let context = viewContext

        // Ensure all Core Data operations happen on the context's queue
        context.perform {
            // Check if entry already exists
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", metrics.id)

            do {
                let results = try context.fetch(fetchRequest)
                let cached: CachedBodyMetrics

                if let existing = results.first {
                    cached = existing
                } else {
                    cached = CachedBodyMetrics(context: context)
                    cached.id = metrics.id
                    cached.createdAt = metrics.createdAt
                }

                // Update values
                cached.userId = userId
                cached.date = metrics.date
                cached.localDate = metrics.localDate
                cached.weight = metrics.weight ?? 0
                cached.weightUnit = metrics.weightUnit
                cached.waistCircumference = metrics.waistCm ?? 0
                cached.hipCircumference = metrics.hipCm ?? 0
                cached.waistUnit = metrics.waistUnit
                cached.bodyFatPercentage = metrics.bodyFatPercentage ?? 0
                cached.bodyFatMethod = metrics.bodyFatMethod
                cached.muscleMass = metrics.muscleMass ?? 0
                cached.boneMass = metrics.boneMass ?? 0
                cached.notes = metrics.notes
                cached.photoUrl = metrics.photoUrl
                cached.dataSource = BodyMetricSource.normalizedRawValue(metrics.dataSource)
                if let sourceMetadataJSON = metrics.sourceMetadata?.jsonString {
                    cached.sourceMetadataJSON = sourceMetadataJSON
                } else if cached.sourceMetadataJSON == nil,
                          let legacyDataSource = metrics.dataSource,
                          BodyMetricSource.normalizedRawValue(legacyDataSource) != legacyDataSource {
                    cached.sourceMetadataJSON = BodyMetricSourceMetadata(
                        legacyDataSource: legacyDataSource
                    ).jsonString
                }
                cached.updatedAt = Date()
                cached.lastModified = Date()
                cached.isSynced = markAsSynced
                cached.syncStatus = markAsSynced ? "synced" : "pending"
                cached.isMarkedDeleted = false

                // Save immediately within the perform block
                if context.hasChanges {
                    try context.save()
                }
                completion?(.success(()))
            } catch {
                // Use OSLog for production-safe logging
                #if DEBUG
                let appError = AppError.coreData(operation: "saveBodyMetrics", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "saveBodyMetrics",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Failed to save body metrics: \(error)")
                #endif
                completion?(.failure(error))
            }
        }
    }

func saveBodyMetricsAndWait(_ metrics: BodyMetrics, userId: String, markAsSynced: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            saveBodyMetrics(metrics, userId: userId, markAsSynced: markAsSynced) { result in
                continuation.resume(with: result)
            }
        }
    }

func createOrUpdatePhotoUploadMetricsPlaceholder(
        for date: Date,
        userId: String
    ) async throws -> PhotoMetricsUpdateResult {
        let context = viewContext
        let startOfDay = Calendar.current.startOfDay(for: date)
        let localDate = BodyMetricLocalDate.key(for: date)
        let normalizedLocalDate = BodyMetricLocalDate.normalized(localDate, fallback: date)

        return try await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "userId == %@", userId),
                    NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false)),
                    NSPredicate(format: "localDate == %@", normalizedLocalDate)
                ]),
                Self.legacyBodyMetricDatePredicate(userId: userId, localDate: normalizedLocalDate)
            ])
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            fetchRequest.fetchLimit = 1

            let cached: CachedBodyMetrics
            let createdNewEntry: Bool
            let now = Date()

            if let existing = try context.fetch(fetchRequest).first {
                cached = existing
                createdNewEntry = false
            } else {
                cached = CachedBodyMetrics(context: context)
                cached.id = UUID().uuidString
                cached.userId = userId
                cached.date = startOfDay
                cached.localDate = normalizedLocalDate
                cached.weight = 0
                cached.weightUnit = "kg"
                cached.waistCircumference = 0
                cached.hipCircumference = 0
                cached.bodyFatPercentage = 0
                cached.muscleMass = 0
                cached.boneMass = 0
                cached.dataSource = BodyMetricSource.photo.rawValue
                cached.createdAt = now
                cached.updatedAt = now
                cached.lastModified = now
                cached.isMarkedDeleted = false
                cached.isSynced = false
                createdNewEntry = true
            }

            if Self.isUploadPlaceholderCandidate(cached, userId: userId),
               !Self.isPhotoUploadStorageCommittedSyncStatus(cached.syncStatus) {
                cached.syncStatus = Self.photoUploadInFlightSyncStatus
                cached.updatedAt = now
                cached.lastModified = now
                cached.isSynced = false
            }

            if context.hasChanges {
                try context.save()
            }

            guard let metrics = cached.toBodyMetrics() else {
                throw NSError(
                    domain: "CoreDataManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create photo upload metrics placeholder"]
                )
            }

            return PhotoMetricsUpdateResult(metrics: metrics, createdNewEntry: createdNewEntry)
        }
    }

func prepareExistingPhotoUploadMetrics(id: String, userId: String) async throws -> BodyMetrics {
        let context = viewContext

        return try await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", id),
                NSPredicate(format: "userId == %@", userId),
                NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false))
            ])
            fetchRequest.fetchLimit = 1

            guard let cached = try context.fetch(fetchRequest).first else {
                throw NSError(
                    domain: "CoreDataManager",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Could not find selected photo upload metrics"]
                )
            }

            if Self.isUploadPlaceholderCandidate(cached, userId: userId),
               !Self.isPhotoUploadStorageCommittedSyncStatus(cached.syncStatus) {
                let now = Date()
                cached.syncStatus = Self.photoUploadInFlightSyncStatus
                cached.updatedAt = now
                cached.lastModified = now
                cached.isSynced = false

                if context.hasChanges {
                    try context.save()
                }
            }

            guard let metrics = cached.toBodyMetrics() else {
                throw NSError(
                    domain: "CoreDataManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not prepare selected photo upload metrics"]
                )
            }

            return metrics
        }
    }
}
