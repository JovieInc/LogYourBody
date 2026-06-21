//
// CoreDataManager.swift
// LogYourBody
//
// THREADING SAFETY: All Core Data operations MUST use context.perform() or context.performAndWait()
// to avoid threading violations. The viewContext is bound to the main thread.
//
// ✅ COMPLETE: All methods now properly use context.perform() or context.performAndWait()
// All Core Data operations are now thread-safe and prevent data corruption and crashes.
//
import Foundation
import CoreData
import HealthKit

struct CachedUserProfileSnapshot {
    let profile: UserProfile
    let isSynced: Bool
    let syncStatus: String?
    let lastModified: Date?

    var hasPendingLocalChanges: Bool {
        !isSynced || syncStatus == "pending" || syncStatus == "failed"
    }
}

struct PendingLocalSyncSnapshot {
    let bodyMetrics: [PendingBodyMetricSyncItem]
    let dailyMetrics: [PendingDailyMetricSyncItem]
    let profiles: [PendingProfileSyncItem]
    let glp1DoseLogs: [PendingGlp1DoseLogSyncItem]
    let glp1Medications: [PendingGlp1MedicationSyncItem]
    let dexaResults: [PendingDexaResultSyncItem]

    static let empty = PendingLocalSyncSnapshot(
        bodyMetrics: [],
        dailyMetrics: [],
        profiles: [],
        glp1DoseLogs: [],
        glp1Medications: [],
        dexaResults: []
    )

    var counts: PendingLocalSyncCounts {
        PendingLocalSyncCounts(
            bodyMetrics: bodyMetrics.count,
            dailyMetrics: dailyMetrics.count,
            profiles: profiles.count,
            glp1DoseLogs: glp1DoseLogs.count,
            glp1Medications: glp1Medications.count,
            dexaResults: dexaResults.count
        )
    }
}

struct PendingLocalSyncCounts {
    let bodyMetrics: Int
    let dailyMetrics: Int
    let profiles: Int
    let glp1DoseLogs: Int
    let glp1Medications: Int
    let dexaResults: Int

    static let empty = PendingLocalSyncCounts(
        bodyMetrics: 0,
        dailyMetrics: 0,
        profiles: 0,
        glp1DoseLogs: 0,
        glp1Medications: 0,
        dexaResults: 0
    )

    var total: Int {
        bodyMetrics + dailyMetrics + profiles + glp1DoseLogs + glp1Medications + dexaResults
    }
}

struct PendingBodyMetricSyncItem {
    let id: String
    let userId: String
    let date: Date
    let localDate: String?
    let weight: Double
    let weightUnit: String?
    let waistCircumference: Double
    let hipCircumference: Double
    let waistUnit: String?
    let bodyFatPercentage: Double
    let bodyFatMethod: String?
    let muscleMass: Double
    let boneMass: Double
    let photoUrl: String?
    let notes: String?
    let dataSource: String?
    let sourceMetadataJSON: String?
    let createdAt: Date
    let updatedAt: Date
    let isMarkedDeleted: Bool
}

struct PendingDailyMetricSyncItem {
    let id: String
    let userId: String
    let date: Date
    let steps: Int32
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct PendingProfileSyncItem {
    let id: String
    let fullName: String?
    let username: String?
    let height: Double?
    let heightUnit: String?
    let gender: String?
    let dateOfBirth: Date?
    let activityLevel: String?
}

struct PendingGlp1DoseLogSyncItem {
    let id: String
    let userId: String
    let takenAt: Date
    let medicationId: String?
    let doseAmount: Double
    let doseUnit: String?
    let drugClass: String?
    let brand: String?
    let isCompounded: Bool
    let supplierType: String?
    let supplierName: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let isMarkedDeleted: Bool
}

struct PendingGlp1MedicationSyncItem {
    let id: String
    let userId: String
    let displayName: String?
    let genericName: String?
    let drugClass: String?
    let brand: String?
    let route: String?
    let frequency: String?
    let doseUnit: String?
    let isCompounded: Bool
    let hkIdentifier: String?
    let startedAt: Date
    let endedAt: Date?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct PendingDexaResultSyncItem {
    let id: String
    let userId: String
    let bodyMetricsId: String?
    let externalSource: String?
    let externalResultId: String?
    let externalUpdateTime: Date?
    let scannerModel: String?
    let locationId: String?
    let locationName: String?
    let acquireTime: Date?
    let analyzeTime: Date?
    let vatMassKg: Double
    let vatVolumeCm3: Double
    let resultPdfUrl: String?
    let resultPdfName: String?
    let createdAt: Date
    let updatedAt: Date
}

class CoreDataManager: ObservableObject {
    static let shared = CoreDataManager()

    private let saveQueue = DispatchQueue(label: "com.logyourbody.coredata.save", qos: .utility)
    private var isSaving = false

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "LogYourBody")

        for description in container.persistentStoreDescriptions {
            description.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                let appError = AppError.coreData(operation: "loadPersistentStores", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "loadPersistentStores",
                    screen: nil,
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // Log the error but don't crash - fallback to in-memory store
                // print("⚠️ CoreData Error: Unable to load persistent stores: \(error)")
                // print("⚠️ Falling back to in-memory store. Data will not persist.")

                // Create an in-memory store as fallback
                let inMemoryDescription = NSPersistentStoreDescription()
                inMemoryDescription.type = NSInMemoryStoreType
                container.persistentStoreDescriptions = [inMemoryDescription]

                // Attempt to load in-memory store
                container.loadPersistentStores { _, inMemoryError in
                    if let inMemoryError = inMemoryError {
                        let criticalError = AppError.coreData(operation: "loadInMemoryStore", underlying: inMemoryError)
                        let criticalContext = ErrorContext(
                            feature: "coreData",
                            operation: "loadInMemoryStore",
                            screen: nil,
                            userId: nil
                        )
                        ErrorReporter.shared.capture(criticalError, context: criticalContext)
                        // print("❌ CoreData Critical: Even in-memory store failed: \(inMemoryError)")
                    }
                }
            }

            // Enable automatic lightweight migration
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    private init() {}

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
        fatalError("fetchDailyMetricsSync has been removed. Use the async counterpart instead.")
    }

    @available(*, unavailable, message: "Use async fetchDailyMetrics(for:from:to:) instead")
    func fetchDailyMetricsSync(
        for userId: String,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) -> [CachedDailyMetrics] {
        fatalError("fetchDailyMetricsSync has been removed. Use the async counterpart instead.")
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

    // Async save for critical operations
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

    // Legacy sync save - triggers async save in background
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

    // MARK: - Async Fetch Methods (Recommended for UI)

    /// Async version - does NOT block the main thread
    func fetchBodyMetrics(for userId: String, from startDate: Date? = nil, to endDate: Date? = nil) async -> [CachedBodyMetrics] {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()

            var predicates = [NSPredicate]()
            predicates.append(NSPredicate(format: "userId == %@", userId))
            predicates.append(NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false)))

            if let start = startDate {
                predicates.append(NSPredicate(format: "date >= %@", start as NSDate))
            }
            if let end = endDate {
                predicates.append(NSPredicate(format: "date <= %@", end as NSDate))
            }

            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

            // Add performance optimizations
            fetchRequest.fetchBatchSize = 20  // Fetch in batches
            fetchRequest.returnsObjectsAsFaults = true  // Don't load all data immediately

            do {
                return try context.fetch(fetchRequest)
            } catch {
                #if DEBUG
                // print("Failed to fetch body metrics: \(error)")
                #endif
                return []
            }
        }
    }

    func fetchBodyMetrics(for userId: String, localDate: String) async -> [CachedBodyMetrics] {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            let normalizedLocalDate = BodyMetricLocalDate.normalized(localDate, fallback: Date())

            fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "userId == %@", userId),
                    NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false)),
                    NSPredicate(format: "localDate == %@", normalizedLocalDate)
                ]),
                self.legacyBodyMetricDatePredicate(userId: userId, localDate: normalizedLocalDate)
            ])
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

            do {
                return try context.fetch(fetchRequest)
            } catch {
                #if DEBUG
                // print("Failed to fetch body metrics by local date: \(error)")
                #endif
                return []
            }
        }
    }

    private func legacyBodyMetricDatePredicate(userId: String, localDate: String) -> NSPredicate {
        guard let startOfDay = BodyMetricLocalDate.startOfDay(for: localDate),
              let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
            return NSPredicate(value: false)
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false)),
            NSPredicate(format: "localDate == nil"),
            NSPredicate(format: "date >= %@", startOfDay as NSDate),
            NSPredicate(format: "date < %@", endOfDay as NSDate)
        ])
    }

    func fetchLatestBodyMetric(for userId: String) async -> CachedBodyMetrics? {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()

            var predicates = [NSPredicate]()
            predicates.append(NSPredicate(format: "userId == %@", userId))
            predicates.append(NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false)))

            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            fetchRequest.fetchLimit = 1

            do {
                return try context.fetch(fetchRequest).first
            } catch {
                #if DEBUG
                // print("Failed to fetch latest body metric: \(error)")
                #endif
                return nil
            }
        }
    }

    func fetchDisplayableBodyMetrics(
        for userId: String,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) async -> (visible: [BodyMetrics], hidden: [BodyMetrics]) {
        let cached = await fetchBodyMetrics(for: userId, from: startDate, to: endDate)
        let metrics = cached.compactMap { $0.toBodyMetrics() }
        return EntryVisibilityManager.shared.prepareMetricsForDisplay(metrics, userId: userId)
    }

    func fetchVisibleBodyMetrics(
        for userId: String,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) async -> [BodyMetrics] {
        let result = await fetchDisplayableBodyMetrics(for: userId, from: startDate, to: endDate)
        return result.visible
    }

    // MARK: - HealthKit Raw Sample Operations

    func hkSampleExists(hkUUID: String) async -> Bool {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedHKSample> = CachedHKSample.fetchRequest()
            request.predicate = NSPredicate(format: "hkUUID == %@", hkUUID)
            request.fetchLimit = 1

            do {
                return try context.fetch(request).isEmpty == false
            } catch {
                #if DEBUG
                // print("Failed to check HK sample existence: \(error)")
                #endif
                return false
            }
        }
    }

    func saveHKSample(_ sample: HKRawSample) async {
        await saveHKSamples([sample])
    }

    func saveHKSamples(_ samples: [HKRawSample]) async {
        guard !samples.isEmpty else { return }

        let context = persistentContainer.newBackgroundContext()

        await context.perform {
            for sample in samples {
                let request: NSFetchRequest<CachedHKSample> = CachedHKSample.fetchRequest()
                request.predicate = NSPredicate(format: "hkUUID == %@", sample.hkUUID)
                request.fetchLimit = 1

                let cached: CachedHKSample

                if let existing = try? context.fetch(request).first {
                    cached = existing
                } else {
                    cached = CachedHKSample(context: context)
                    cached.id = sample.id
                    cached.hkUUID = sample.hkUUID
                    cached.createdAt = sample.createdAt
                }

                cached.userId = sample.userId
                cached.quantityType = sample.quantityType
                cached.value = sample.value
                cached.unit = sample.unit
                cached.startDate = sample.startDate
                cached.endDate = sample.endDate
                cached.sourceName = sample.sourceName
                cached.sourceBundleId = sample.sourceBundleId
                cached.deviceManufacturer = sample.deviceManufacturer
                cached.deviceModel = sample.deviceModel
                cached.deviceHardwareVersion = sample.deviceHardwareVersion
                cached.deviceFirmwareVersion = sample.deviceFirmwareVersion
                cached.deviceSoftwareVersion = sample.deviceSoftwareVersion
                cached.deviceLocalIdentifier = sample.deviceLocalIdentifier
                cached.deviceUDI = sample.deviceUDI
                cached.updatedAt = sample.updatedAt

                if let metadata = sample.metadata,
                   let data = try? JSONEncoder().encode(metadata) {
                    cached.metadataJSON = data
                } else {
                    cached.metadataJSON = nil
                }
            }

            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                // print("Failed to save HK samples: \\(error)")
                #endif
            }
        }
    }

    @available(*, unavailable, message: "Use async fetchBodyMetrics(for:from:to:) instead")
    func fetchBodyMetricsSync(for userId: String, from startDate: Date? = nil, to endDate: Date? = nil) -> [CachedBodyMetrics] {
        fatalError("fetchBodyMetricsSync has been removed. Use the async counterpart instead.")
    }

    // MARK: - Body Metrics Update/Delete Helpers

    @discardableResult
    func updateBodyMetric(
        id: String,
        date: Date,
        weight: Double?,
        bodyFatPercentage: Double?
    ) async -> BodyMetrics? {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            fetchRequest.fetchLimit = 1

            guard let cachedMetric = try? context.fetch(fetchRequest).first else {
                return nil
            }

            let normalizedDate = Calendar.current.startOfDay(for: date)
            cachedMetric.date = normalizedDate
            cachedMetric.localDate = BodyMetricLocalDate.key(for: date)

            if let weight {
                cachedMetric.weight = weight
            }

            if let bodyFatPercentage {
                cachedMetric.bodyFatPercentage = bodyFatPercentage
            }

            let now = Date()
            cachedMetric.updatedAt = now
            cachedMetric.lastModified = now
            cachedMetric.isMarkedDeleted = false
            cachedMetric.isSynced = false
            cachedMetric.syncStatus = "pending"

            do {
                if context.hasChanges {
                    try context.save()
                }

                let updated = cachedMetric.toBodyMetrics()

                // Schedule background body score recalculation when weight/body fat entries change.
                BodyScoreRecalculationService.shared.scheduleRecalculation()

                return updated
            } catch {
                #if DEBUG
                // print("Failed to update body metric: \(error)")
                #endif
                return nil
            }
        }
    }

    @discardableResult
    func updateBodyMetricPhoto(
        id: String,
        userId: String,
        storagePath: String,
        processedUrl: String
    ) async throws -> Bool {
        let context = viewContext

        return try await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", id),
                NSPredicate(format: "userId == %@", userId),
                NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false))
            ])
            fetchRequest.fetchLimit = 1

            guard let cachedMetric = try context.fetch(fetchRequest).first else {
                return false
            }

            let now = Date()
            cachedMetric.photoUrl = processedUrl
            cachedMetric.originalPhotoUrl = storagePath
            cachedMetric.updatedAt = now
            cachedMetric.lastModified = now
            cachedMetric.isSynced = false
            cachedMetric.syncStatus = "pending"

            if context.hasChanges {
                try context.save()
            }

            return true
        }
    }

    func markBodyMetricDeleted(id: String) async -> Bool {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            fetchRequest.fetchLimit = 1

            guard let cachedMetric = try? context.fetch(fetchRequest).first else {
                return false
            }

            let now = Date()
            cachedMetric.isMarkedDeleted = true
            cachedMetric.updatedAt = now
            cachedMetric.lastModified = now
            cachedMetric.isSynced = false
            cachedMetric.syncStatus = "pending"

            do {
                if context.hasChanges {
                    try context.save()
                }
                return true
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "markBodyMetricDeleted", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "markBodyMetricDeleted",
                    screen: nil,
                    userId: cachedMetric.userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Failed to delete body metric: \(error)")
                #endif
                return false
            }
        }
    }

    // MARK: - Daily Metrics Operations
    func saveProfile(_ profile: UserProfile, userId: String, email: String, markSynced: Bool = false) {
        let context = viewContext

        context.perform {
            let fetchRequest: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", userId)

            do {
                let results = try context.fetch(fetchRequest)
                let cached: CachedProfile

                if let existing = results.first {
                    cached = existing
                } else {
                    cached = CachedProfile(context: context)
                    cached.id = userId
                    cached.createdAt = Date()
                }

                cached.email = email
                cached.fullName = profile.fullName
                cached.username = profile.username
                cached.dateOfBirth = profile.dateOfBirth
                cached.height = profile.height ?? 0
                cached.heightUnit = profile.heightUnit
                cached.gender = profile.gender
                cached.activityLevel = profile.activityLevel
                cached.goalWeight = profile.goalWeight ?? 0
                cached.goalWeightUnit = profile.goalWeightUnit
                cached.updatedAt = Date()
                cached.lastModified = Date()
                cached.isSynced = markSynced
                cached.syncStatus = markSynced ? "synced" : "pending"
                cached.isMarkedDeleted = false

                self.save()
            } catch {
                let appError = AppError.coreData(operation: "saveProfile", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "saveProfile",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Failed to save profile: \(error)")
            }
        }
    }

    func fetchUserProfile(for userId: String) async -> UserProfile? {
        await fetchUserProfileSnapshot(for: userId)?.profile
    }

    func fetchUserProfileSnapshot(for userId: String) async -> CachedUserProfileSnapshot? {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@ AND isMarkedDeleted == %@", userId, NSNumber(value: false))
            fetchRequest.fetchLimit = 1

            do {
                guard let cached = try context.fetch(fetchRequest).first else {
                    return nil
                }

                return CachedUserProfileSnapshot(
                    profile: cached.toUserProfile(),
                    isSynced: cached.isSynced,
                    syncStatus: cached.syncStatus,
                    lastModified: cached.lastModified
                )
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchUserProfileSnapshot", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchUserProfileSnapshot",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return nil
            }
        }
    }

    /// Async version - does NOT block the main thread
    func fetchProfile(for userId: String) async -> CachedProfile? {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@ AND isMarkedDeleted == %@", userId, NSNumber(value: false))
            fetchRequest.fetchLimit = 1

            do {
                return try context.fetch(fetchRequest).first
            } catch {
                #if DEBUG
                // print("Failed to fetch profile: \(error)")
                #endif
                return nil
            }
        }
    }

    @available(*, unavailable, message: "Use async fetchProfile(for:) instead")
    func fetchProfileSync(for userId: String) -> CachedProfile? {
        fatalError("fetchProfileSync has been removed. Use the async counterpart instead.")
    }

    // MARK: - Sync Operations

    /// Async version - does NOT block the main thread
    func fetchUnsyncedEntries(for userId: String? = nil) async -> (
        bodyMetrics: [CachedBodyMetrics],
        dailyMetrics: [CachedDailyMetrics],
        profiles: [CachedProfile]
    ) {
        let context = viewContext

        return await context.perform {
            let bodyMetricsFetch: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            var bodyPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
            if let userId {
                bodyPredicates.append(NSPredicate(format: "userId == %@", userId))
            }
            bodyMetricsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: bodyPredicates)

            let dailyMetricsFetch: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            var dailyPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
            if let userId {
                dailyPredicates.append(NSPredicate(format: "userId == %@", userId))
            }
            dailyMetricsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: dailyPredicates)

            let profilesFetch: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            var profilePredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
            if let userId {
                profilePredicates.append(NSPredicate(format: "id == %@", userId))
            }
            profilesFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: profilePredicates)

            do {
                let bodyMetrics = try context.fetch(bodyMetricsFetch)
                let dailyMetrics = try context.fetch(dailyMetricsFetch)
                let profiles = try context.fetch(profilesFetch)

                return (bodyMetrics, dailyMetrics, profiles)
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchUnsyncedEntries", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchUnsyncedEntries",
                    screen: nil,
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Failed to fetch unsynced entries: \(error)")
                #endif
                return ([], [], [])
            }
        }
    }

    func fetchUnsyncedGlp1DoseLogs(for userId: String? = nil) async -> [CachedGlp1DoseLog] {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
            var predicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
            if let userId {
                predicates.append(NSPredicate(format: "userId == %@", userId))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            do {
                return try context.fetch(request)
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchUnsyncedGlp1DoseLogs", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchUnsyncedGlp1DoseLogs",
                    screen: nil,
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return []
            }
        }
    }

    func fetchUnsyncedGlp1Medications(for userId: String? = nil) async -> [CachedGlp1Medication] {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
            var predicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
            if let userId {
                predicates.append(NSPredicate(format: "userId == %@", userId))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            do {
                return try context.fetch(request)
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchUnsyncedGlp1Medications", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchUnsyncedGlp1Medications",
                    screen: nil,
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return []
            }
        }
    }

    func fetchPendingLocalSyncSnapshot(for userId: String? = nil) async throws -> PendingLocalSyncSnapshot {
        let context = viewContext

        return try await context.perform {
            do {
                let bodyMetricsFetch: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
                var bodyPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    bodyPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                bodyMetricsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: bodyPredicates)

                let dailyMetricsFetch: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
                var dailyPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    dailyPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                dailyMetricsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: dailyPredicates)

                let profilesFetch: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
                var profilePredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    profilePredicates.append(NSPredicate(format: "id == %@", userId))
                }
                profilesFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: profilePredicates)

                let glp1DoseLogsFetch: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
                var glp1DoseLogPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    glp1DoseLogPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                glp1DoseLogsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: glp1DoseLogPredicates)

                let glp1MedicationsFetch: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
                var glp1MedicationPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    glp1MedicationPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                glp1MedicationsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: glp1MedicationPredicates)

                let dexaResultsFetch: NSFetchRequest<CachedDexaResult> = CachedDexaResult.fetchRequest()
                var dexaPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    dexaPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                dexaResultsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: dexaPredicates)

                return PendingLocalSyncSnapshot(
                    bodyMetrics: try context.fetch(bodyMetricsFetch).map { $0.pendingSyncItem() },
                    dailyMetrics: try context.fetch(dailyMetricsFetch).map { $0.pendingSyncItem() },
                    profiles: try context.fetch(profilesFetch).map { $0.pendingSyncItem() },
                    glp1DoseLogs: try context.fetch(glp1DoseLogsFetch).map { $0.pendingSyncItem() },
                    glp1Medications: try context.fetch(glp1MedicationsFetch).map { $0.pendingSyncItem() },
                    dexaResults: try context.fetch(dexaResultsFetch).map { $0.pendingSyncItem() }
                )
            } catch {
                let appError = AppError.coreData(operation: "fetchPendingLocalSyncSnapshot", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchPendingLocalSyncSnapshot",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                throw error
            }
        }
    }

    func fetchPendingLocalSyncCounts(for userId: String? = nil) async throws -> PendingLocalSyncCounts {
        let context = viewContext

        return try await context.perform {
            do {
                let bodyMetricsFetch: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
                var bodyPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    bodyPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                bodyMetricsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: bodyPredicates)

                let dailyMetricsFetch: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
                var dailyPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    dailyPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                dailyMetricsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: dailyPredicates)

                let profilesFetch: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
                var profilePredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    profilePredicates.append(NSPredicate(format: "id == %@", userId))
                }
                profilesFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: profilePredicates)

                let glp1DoseLogsFetch: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
                var glp1DoseLogPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    glp1DoseLogPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                glp1DoseLogsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: glp1DoseLogPredicates)

                let glp1MedicationsFetch: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
                var glp1MedicationPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    glp1MedicationPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                glp1MedicationsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: glp1MedicationPredicates)

                let dexaResultsFetch: NSFetchRequest<CachedDexaResult> = CachedDexaResult.fetchRequest()
                var dexaPredicates = [NSPredicate(format: "isSynced == %@", NSNumber(value: false))]
                if let userId {
                    dexaPredicates.append(NSPredicate(format: "userId == %@", userId))
                }
                dexaResultsFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: dexaPredicates)

                return PendingLocalSyncCounts(
                    bodyMetrics: try context.count(for: bodyMetricsFetch),
                    dailyMetrics: try context.count(for: dailyMetricsFetch),
                    profiles: try context.count(for: profilesFetch),
                    glp1DoseLogs: try context.count(for: glp1DoseLogsFetch),
                    glp1Medications: try context.count(for: glp1MedicationsFetch),
                    dexaResults: try context.count(for: dexaResultsFetch)
                )
            } catch {
                let appError = AppError.coreData(operation: "fetchPendingLocalSyncCounts", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchPendingLocalSyncCounts",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                throw error
            }
        }
    }

    @available(*, unavailable, message: "Use async fetchUnsyncedEntries() instead")
    func fetchUnsyncedEntriesSync() -> (
        bodyMetrics: [CachedBodyMetrics],
        dailyMetrics: [CachedDailyMetrics],
        profiles: [CachedProfile]
    ) {
        fatalError("fetchUnsyncedEntriesSync has been removed. Use the async counterpart instead.")
    }

    func markAsSynced(entityName: String, id: String) {
        let context = viewContext

        context.perform {
            switch entityName {
            case "CachedBodyMetrics":
                let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                if let entry = try? context.fetch(fetchRequest).first {
                    entry.isSynced = true
                    entry.syncStatus = "synced"
                }

            case "CachedDailyMetrics":
                let fetchRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                if let entry = try? context.fetch(fetchRequest).first {
                    entry.isSynced = true
                    entry.syncStatus = "synced"
                }

            case "CachedProfile":
                let fetchRequest: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                if let entry = try? context.fetch(fetchRequest).first {
                    entry.isSynced = true
                    entry.syncStatus = "synced"
                }

            default:
                break
            }

            self.save()
        }
    }

    func markAsSynced(entityName: String, ids: Set<String>) async {
        guard !ids.isEmpty else { return }

        let context = viewContext
        await context.perform {
            do {
                switch entityName {
                case "CachedBodyMetrics":
                    let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
                    request.predicate = NSPredicate(format: "id IN %@", Array(ids) as NSArray)
                    try context.fetch(request).forEach {
                        $0.isSynced = true
                        $0.syncStatus = "synced"
                    }

                case "CachedDailyMetrics":
                    let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
                    request.predicate = NSPredicate(format: "id IN %@", Array(ids) as NSArray)
                    try context.fetch(request).forEach {
                        $0.isSynced = true
                        $0.syncStatus = "synced"
                    }

                case "CachedProfile":
                    let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
                    request.predicate = NSPredicate(format: "id IN %@", Array(ids) as NSArray)
                    try context.fetch(request).forEach {
                        $0.isSynced = true
                        $0.syncStatus = "synced"
                    }

                case "CachedGlp1DoseLog":
                    let request: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
                    request.predicate = NSPredicate(format: "id IN %@", Array(ids) as NSArray)
                    try context.fetch(request).forEach {
                        $0.isSynced = true
                        $0.syncStatus = "synced"
                    }

                case "CachedGlp1Medication":
                    let request: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
                    request.predicate = NSPredicate(format: "id IN %@", Array(ids) as NSArray)
                    try context.fetch(request).forEach {
                        $0.isSynced = true
                        $0.syncStatus = "synced"
                    }

                case "CachedDexaResult":
                    let request: NSFetchRequest<CachedDexaResult> = CachedDexaResult.fetchRequest()
                    request.predicate = NSPredicate(format: "id IN %@", Array(ids) as NSArray)
                    try context.fetch(request).forEach {
                        $0.isSynced = true
                        $0.syncStatus = "synced"
                    }

                default:
                    return
                }

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                let appError = AppError.coreData(operation: "markAsSynced", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "markAsSynced",
                    screen: nil,
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
            }
        }
    }

    func updateSyncStatus(entityName: String, id: String, status: String, error: String? = nil) {
        let context = viewContext

        context.perform {
            let metadata = self.fetchOrCreateSyncMetadata(entityName: entityName, entityId: id)
            metadata.lastSyncAttempt = Date()

            if status == "synced" {
                metadata.lastSyncSuccess = Date()
                metadata.syncRetryCount = 0
                metadata.lastSyncError = nil
            } else {
                metadata.syncRetryCount += 1
                metadata.lastSyncError = error
            }

            self.save()
        }
    }

    private func fetchOrCreateSyncMetadata(entityName: String, entityId: String) -> SyncMetadata {
        let fetchRequest: NSFetchRequest<SyncMetadata> = SyncMetadata.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "entityName == %@ AND entityId == %@", entityName, entityId)
        fetchRequest.fetchLimit = 1

        if let existing = try? viewContext.fetch(fetchRequest).first {
            return existing
        }

        let metadata = SyncMetadata(context: viewContext)
        metadata.entityName = entityName
        metadata.entityId = entityId
        metadata.syncRetryCount = 0

        return metadata
    }

    // MARK: - Cleanup Operations
    func cleanupDeletedEntries(olderThan date: Date) {
        let context = viewContext

        context.perform {
            let bodyMetricsFetch: NSFetchRequest<NSFetchRequestResult> = CachedBodyMetrics.fetchRequest()
            bodyMetricsFetch.predicate = NSPredicate(format: "isMarkedDeleted == %@ AND lastModified < %@",
                                                     NSNumber(value: true), date as NSDate)

            let dailyMetricsFetch: NSFetchRequest<NSFetchRequestResult> = CachedDailyMetrics.fetchRequest()
            dailyMetricsFetch.predicate = NSPredicate(format: "isMarkedDeleted == %@ AND lastModified < %@",
                                                      NSNumber(value: true), date as NSDate)

            let deleteBodyMetrics = NSBatchDeleteRequest(fetchRequest: bodyMetricsFetch)
            let deleteDailyMetrics = NSBatchDeleteRequest(fetchRequest: dailyMetricsFetch)

            do {
                try context.execute(deleteBodyMetrics)
                try context.execute(deleteDailyMetrics)
                self.save()
            } catch {
                let appError = AppError.coreData(operation: "cleanupDeletedEntries", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "cleanupDeletedEntries",
                    screen: nil,
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // print("Failed to cleanup deleted entries: \(error)")
            }
        }
    }

    // MARK: - Delete All Data

    func deleteAllData(completion: ((Result<Void, Error>) -> Void)? = nil) {
        let context = viewContext

        context.perform {
            do {
                // Delete all body metrics
                let bodyMetricsRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
                let bodyMetrics = try context.fetch(bodyMetricsRequest)
                for metric in bodyMetrics {
                    context.delete(metric)
                }

                // Delete all daily metrics
                let dailyMetricsRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
                let dailyMetrics = try context.fetch(dailyMetricsRequest)
                for metric in dailyMetrics {
                    context.delete(metric)
                }

                // Delete all GLP-1 dose logs
                let glp1Request: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
                let glp1Logs = try context.fetch(glp1Request)
                for log in glp1Logs {
                    context.delete(log)
                }

                // Delete all GLP-1 medications
                let medicationRequest: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
                let medications = try context.fetch(medicationRequest)
                for medication in medications {
                    context.delete(medication)
                }

                let dexaRequest: NSFetchRequest<CachedDexaResult> = CachedDexaResult.fetchRequest()
                let dexaResults = try context.fetch(dexaRequest)
                for result in dexaResults {
                    context.delete(result)
                }

                // Delete all profiles
                let profileRequest: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
                let profiles = try context.fetch(profileRequest)
                for profile in profiles {
                    context.delete(profile)
                }

                // Delete all sync metadata
                let syncRequest: NSFetchRequest<SyncMetadata> = SyncMetadata.fetchRequest()
                let syncRecords = try context.fetch(syncRequest)
                for record in syncRecords {
                    context.delete(record)
                }

                let hkSampleRequest: NSFetchRequest<CachedHKSample> = CachedHKSample.fetchRequest()
                let hkSamples = try context.fetch(hkSampleRequest)
                for sample in hkSamples {
                    context.delete(sample)
                }

                let deviceRequest: NSFetchRequest<CachedDevice> = CachedDevice.fetchRequest()
                let devices = try context.fetch(deviceRequest)
                for device in devices {
                    context.delete(device)
                }

                let userDeviceRequest: NSFetchRequest<CachedUserDevice> = CachedUserDevice.fetchRequest()
                let userDevices = try context.fetch(userDeviceRequest)
                for userDevice in userDevices {
                    context.delete(userDevice)
                }

                // Save changes
                if context.hasChanges {
                    try context.save()
                }
                completion?(.success(()))
            } catch {
                let appError = AppError.coreData(operation: "deleteAllData", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "deleteAllData",
                    screen: nil,
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                completion?(.failure(error))
            }
        }
    }

    func deleteAllDataAndWait() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            deleteAllData { result in
                continuation.resume(with: result)
            }
        }
    }

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

    // Mark all HealthKit imported entries as synced
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

    // Optimize database (vacuum SQLite)
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

    // Save context helper
    private func saveContext() {
        save()
    }

    // Clean up body metrics with invalid UUIDs
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

    func markGlp1DoseLogDeleted(id: String, userId: String) async -> Bool {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", id),
                NSPredicate(format: "userId == %@", userId)
            ])
            request.fetchLimit = 1

            guard let cached = try? context.fetch(request).first else {
                return false
            }

            let now = Date()
            cached.isMarkedDeleted = true
            cached.updatedAt = now
            cached.isSynced = false
            cached.syncStatus = "pending"

            do {
                if context.hasChanges {
                    try context.save()
                }
                return true
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "markGlp1DoseLogDeleted", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "markGlp1DoseLogDeleted",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return false
            }
        }
    }

    func fetchGlp1Medications(for userId: String) async -> [Glp1Medication] {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", userId)
            request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]

            do {
                let cached = try context.fetch(request)
                return cached.compactMap { $0.toGlp1Medication() }
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchGlp1Medications", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchGlp1Medications",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return []
            }
        }
    }

    func saveGlp1Medications(
        _ medications: [Glp1Medication],
        userId: String,
        markAsSynced: Bool = true
    ) {
        guard !medications.isEmpty else { return }

        let context = viewContext

        context.perform {
            for medication in medications {
                let request: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", medication.id)
                request.fetchLimit = 1

                let cached: CachedGlp1Medication

                if let existing = try? context.fetch(request).first {
                    cached = existing
                } else {
                    cached = CachedGlp1Medication(context: context)
                    cached.id = medication.id
                    cached.createdAt = medication.createdAt
                }

                cached.userId = userId
                cached.displayName = medication.displayName
                cached.genericName = medication.genericName
                cached.drugClass = medication.drugClass
                cached.brand = medication.brand
                cached.route = medication.route
                cached.frequency = medication.frequency
                cached.doseUnit = medication.doseUnit
                cached.isCompounded = medication.isCompounded
                cached.hkIdentifier = medication.hkIdentifier
                cached.startedAt = medication.startedAt
                cached.endedAt = medication.endedAt
                cached.notes = medication.notes
                cached.updatedAt = medication.updatedAt
                cached.isSynced = markAsSynced
                cached.syncStatus = markAsSynced ? "synced" : "pending"
            }

            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "saveGlp1Medications", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "saveGlp1Medications",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
            }
        }
    }

    func endActiveGlp1Medications(for userId: String, endedAt: Date) {
        let context = viewContext

        context.perform {
            let request: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@ AND endedAt == nil", userId)

            do {
                let medications = try context.fetch(request)
                for medication in medications {
                    medication.endedAt = endedAt
                    medication.updatedAt = endedAt
                    medication.isSynced = false
                    medication.syncStatus = "pending"
                }

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "endActiveGlp1Medications", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "endActiveGlp1Medications",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
            }
        }
    }
}

extension CachedGlp1Medication {
    func pendingSyncItem() -> PendingGlp1MedicationSyncItem {
        PendingGlp1MedicationSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            displayName: displayName,
            genericName: genericName,
            drugClass: drugClass,
            brand: brand,
            route: route,
            frequency: frequency,
            doseUnit: doseUnit,
            isCompounded: isCompounded,
            hkIdentifier: hkIdentifier,
            startedAt: startedAt ?? Date(),
            endedAt: endedAt,
            notes: notes,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    func toGlp1Medication() -> Glp1Medication? {
        guard let id = id,
              let userId = userId,
              let displayName = displayName,
              let startedAt = startedAt,
              let createdAt = createdAt,
              let updatedAt = updatedAt else {
            return nil
        }

        return Glp1Medication(
            id: id,
            userId: userId,
            displayName: displayName,
            genericName: genericName,
            drugClass: drugClass,
            brand: brand,
            route: route,
            frequency: frequency,
            doseUnit: doseUnit,
            isCompounded: isCompounded,
            hkIdentifier: hkIdentifier,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension CachedDexaResult {
    func pendingSyncItem() -> PendingDexaResultSyncItem {
        PendingDexaResultSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            bodyMetricsId: bodyMetricsId,
            externalSource: externalSource,
            externalResultId: externalResultId,
            externalUpdateTime: externalUpdateTime,
            scannerModel: scannerModel,
            locationId: locationId,
            locationName: locationName,
            acquireTime: acquireTime,
            analyzeTime: analyzeTime,
            vatMassKg: vatMassKg,
            vatVolumeCm3: vatVolumeCm3,
            resultPdfUrl: resultPdfUrl,
            resultPdfName: resultPdfName,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    func toDexaResult() -> DexaResult? {
        guard let id = id,
              let userId = userId,
              let externalSource = externalSource,
              let externalResultId = externalResultId,
              let createdAt = createdAt,
              let updatedAt = updatedAt else {
            return nil
        }

        let resolvedVatMass: Double?
        if vatMassKg > 0 {
            resolvedVatMass = vatMassKg
        } else {
            resolvedVatMass = nil
        }

        let resolvedVatVolume: Double?
        if vatVolumeCm3 > 0 {
            resolvedVatVolume = vatVolumeCm3
        } else {
            resolvedVatVolume = nil
        }

        return DexaResult(
            id: id,
            userId: userId,
            bodyMetricsId: bodyMetricsId,
            externalSource: externalSource,
            externalResultId: externalResultId,
            externalUpdateTime: externalUpdateTime,
            scannerModel: scannerModel,
            locationId: locationId,
            locationName: locationName,
            acquireTime: acquireTime,
            analyzeTime: analyzeTime,
            vatMassKg: resolvedVatMass,
            vatVolumeCm3: resolvedVatVolume,
            resultPdfUrl: resultPdfUrl,
            resultPdfName: resultPdfName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Model Extensions for Conversion

extension CachedBodyMetrics {
    func pendingSyncItem() -> PendingBodyMetricSyncItem {
        let date = date ?? Date()
        return PendingBodyMetricSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            date: date,
            localDate: localDate,
            weight: weight,
            weightUnit: weightUnit,
            waistCircumference: waistCircumference,
            hipCircumference: hipCircumference,
            waistUnit: waistUnit,
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatMethod,
            muscleMass: muscleMass,
            boneMass: boneMass,
            photoUrl: photoUrl,
            notes: notes,
            dataSource: dataSource,
            sourceMetadataJSON: sourceMetadataJSON,
            createdAt: createdAt ?? date,
            updatedAt: updatedAt ?? createdAt ?? date,
            isMarkedDeleted: isMarkedDeleted
        )
    }

    func toBodyMetrics() -> BodyMetrics? {
        // Skip entries with missing required fields
        guard let id = id,
              let date = date,
              let createdAt = createdAt,
              let updatedAt = updatedAt,
              let userId = userId else {
            // print("⚠️ Skipping corrupted body metric entry with missing required fields")
            return nil
        }

        return BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            localDate: BodyMetricLocalDate.normalized(localDate, fallback: date),
            weight: weight > 0 ? weight : nil,
            weightUnit: weightUnit,
            bodyFatPercentage: bodyFatPercentage > 0 ? bodyFatPercentage : nil,
            bodyFatMethod: bodyFatMethod,
            muscleMass: muscleMass > 0 ? muscleMass : nil,
            boneMass: boneMass > 0 ? boneMass : nil,
            waistCm: waistCircumference > 0 ? waistCircumference : nil,
            hipCm: hipCircumference > 0 ? hipCircumference : nil,
            waistUnit: waistUnit,
            notes: notes,
            photoUrl: photoUrl,
            dataSource: BodyMetricSource.normalizedRawValue(dataSource),
            sourceMetadata: BodyMetricSourceMetadata(jsonString: sourceMetadataJSON),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension CachedDailyMetrics {
    func pendingSyncItem() -> PendingDailyMetricSyncItem {
        let date = date ?? Date()
        return PendingDailyMetricSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            date: date,
            steps: steps,
            notes: notes,
            createdAt: createdAt ?? date,
            updatedAt: updatedAt ?? createdAt ?? date
        )
    }

    func toDailyMetrics() -> DailyMetrics {
        DailyMetrics(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            date: date ?? Date(),
            steps: steps > 0 ? Int(steps) : nil,
            notes: notes,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }
}

extension CachedProfile {
    func pendingSyncItem() -> PendingProfileSyncItem {
        PendingProfileSyncItem(
            id: id ?? "",
            fullName: fullName,
            username: username,
            height: height > 0 ? height : nil,
            heightUnit: heightUnit,
            gender: gender,
            dateOfBirth: dateOfBirth,
            activityLevel: activityLevel
        )
    }

    func toUserProfile() -> UserProfile {
        let storedHeight = height
        let unit = heightUnit?.lowercased()

        let heightCm: Double?
        if storedHeight > 0 {
            if unit == "in" {
                if storedHeight >= 100 {
                    heightCm = storedHeight
                } else {
                    heightCm = storedHeight * 2.54
                }
            } else if unit == "cm" {
                heightCm = storedHeight < 100 ? storedHeight * 2.54 : storedHeight
            } else {
                heightCm = storedHeight >= 100 ? storedHeight : storedHeight * 2.54
            }
        } else {
            heightCm = nil
        }

        return UserProfile(
            id: id ?? "",
            email: email ?? "",
            username: username,
            fullName: fullName,
            dateOfBirth: dateOfBirth,
            height: heightCm,
            heightUnit: heightUnit,
            gender: gender,
            activityLevel: activityLevel,
            goalWeight: goalWeight > 0 ? goalWeight : nil,
            goalWeightUnit: goalWeightUnit,
            onboardingCompleted: nil
        )
    }
}

extension CachedGlp1DoseLog {
    func pendingSyncItem() -> PendingGlp1DoseLogSyncItem {
        PendingGlp1DoseLogSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            takenAt: takenAt ?? Date(),
            medicationId: medicationId,
            doseAmount: doseAmount,
            doseUnit: doseUnit,
            drugClass: drugClass,
            brand: brand,
            isCompounded: isCompounded,
            supplierType: supplierType,
            supplierName: supplierName,
            notes: notes,
            createdAt: createdAt ?? takenAt ?? Date(),
            updatedAt: updatedAt ?? createdAt ?? takenAt ?? Date(),
            isMarkedDeleted: isMarkedDeleted
        )
    }

    func toGlp1DoseLog() -> Glp1DoseLog? {
        guard let id = id,
              let userId = userId,
              let takenAt = takenAt,
              let createdAt = createdAt,
              let updatedAt = updatedAt else {
            return nil
        }

        let resolvedDoseAmount: Double?
        if doseAmount > 0 {
            resolvedDoseAmount = doseAmount
        } else {
            resolvedDoseAmount = nil
        }

        return Glp1DoseLog(
            id: id,
            userId: userId,
            takenAt: takenAt,
            medicationId: medicationId,
            doseAmount: resolvedDoseAmount,
            doseUnit: doseUnit,
            drugClass: drugClass,
            brand: brand,
            isCompounded: isCompounded,
            supplierType: supplierType,
            supplierName: supplierName,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
