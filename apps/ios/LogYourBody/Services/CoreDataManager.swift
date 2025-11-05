//
// CoreDataManager.swift
// LogYourBody
//
// THREADING SAFETY: All Core Data operations MUST use context.perform() or context.performAndWait()
// to avoid threading violations. The viewContext is bound to the main thread.
//
// FIXED: saveBodyMetrics, fetchBodyMetrics, saveDailyMetrics now use context.perform()
// TODO: Remaining methods (saveProfile, fetchProfile, markAsSynced, deleteAllData, etc.) should be
//       updated to use the same pattern for complete thread safety.
//
import Foundation
import CoreData

class CoreDataManager: ObservableObject {
    static let shared = CoreDataManager()
    
    private let saveQueue = DispatchQueue(label: "com.logyourbody.coredata.save", qos: .utility)
    private var isSaving = false
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "LogYourBody")
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
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
                        // print("Failed to save Core Data context: \(error)")
                    }
                }
                completion?()
            }
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
    func saveBodyMetrics(_ metrics: BodyMetrics, userId: String, markAsSynced: Bool = false) {
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
                cached.weight = metrics.weight ?? 0
                cached.weightUnit = metrics.weightUnit
                cached.bodyFatPercentage = metrics.bodyFatPercentage ?? 0
                cached.bodyFatMethod = metrics.bodyFatMethod
                cached.muscleMass = metrics.muscleMass ?? 0
                cached.boneMass = metrics.boneMass ?? 0
                cached.notes = metrics.notes
                cached.photoUrl = metrics.photoUrl
                cached.dataSource = metrics.dataSource ?? "Manual"
                cached.updatedAt = Date()
                cached.lastModified = Date()
                cached.isSynced = markAsSynced
                cached.syncStatus = markAsSynced ? "synced" : "pending"
                cached.isMarkedDeleted = false

                // Save immediately within the perform block
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                // Use OSLog for production-safe logging
                #if DEBUG
                print("Failed to save body metrics: \(error)")
                #endif
            }
        }
    }
    
    func fetchBodyMetrics(for userId: String, from startDate: Date? = nil, to endDate: Date? = nil) -> [CachedBodyMetrics] {
        let context = viewContext
        var result: [CachedBodyMetrics] = []

        // Perform fetch on context's queue to avoid threading issues
        context.performAndWait {
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
                result = try context.fetch(fetchRequest)
            } catch {
                #if DEBUG
                print("Failed to fetch body metrics: \(error)")
                #endif
            }
        }

        return result
    }
    
    // MARK: - Daily Metrics Operations
    func saveDailyMetrics(_ metrics: DailyMetrics, userId: String) {
        let context = viewContext

        // Ensure all Core Data operations happen on the context's queue
        context.perform {
            let fetchRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@ OR (userId == %@ AND date == %@)",
                                               metrics.id, userId, metrics.date as NSDate)

            do {
                let results = try context.fetch(fetchRequest)
                let cached: CachedDailyMetrics

                if let existing = results.first {
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
                cached.updatedAt = Date()
                cached.lastModified = Date()
                cached.isSynced = false
                cached.syncStatus = "pending"
                cached.isMarkedDeleted = false

                // Save immediately within the perform block
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                print("Failed to save daily metrics: \(error)")
                #endif
            }
        }
    }
    
    func fetchDailyMetrics(for userId: String, date: Date) -> CachedDailyMetrics? {
        let fetchRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        fetchRequest.predicate = NSPredicate(format: "userId == %@ AND date >= %@ AND date < %@ AND isMarkedDeleted == %@",
                                           userId, startOfDay as NSDate, endOfDay as NSDate, NSNumber(value: false))
        fetchRequest.fetchLimit = 1
        
        do {
            return try viewContext.fetch(fetchRequest).first
        } catch {
            // print("Failed to fetch daily metrics: \(error)")
            return nil
        }
    }
    
    // MARK: - Profile Operations
    func saveProfile(_ profile: UserProfile, userId: String, email: String) {
        let context = viewContext
        
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
            cached.isSynced = false
            cached.syncStatus = "pending"
            cached.isMarkedDeleted = false
            
            saveAndWait()  // Use synchronous save to ensure data is persisted before sync
        } catch {
            // print("Failed to save profile: \(error)")
        }
    }
    
    func fetchProfile(for userId: String) -> CachedProfile? {
        let fetchRequest: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@ AND isMarkedDeleted == %@", userId, NSNumber(value: false))
        fetchRequest.fetchLimit = 1
        
        do {
            return try viewContext.fetch(fetchRequest).first
        } catch {
            // print("Failed to fetch profile: \(error)")
            return nil
        }
    }
    
    // MARK: - Sync Operations
    func fetchUnsyncedEntries() -> (bodyMetrics: [CachedBodyMetrics], dailyMetrics: [CachedDailyMetrics], profiles: [CachedProfile]) {
        let bodyMetricsFetch: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        bodyMetricsFetch.predicate = NSPredicate(format: "isSynced == %@", NSNumber(value: false))
        
        let dailyMetricsFetch: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
        dailyMetricsFetch.predicate = NSPredicate(format: "isSynced == %@", NSNumber(value: false))
        
        let profilesFetch: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
        profilesFetch.predicate = NSPredicate(format: "isSynced == %@", NSNumber(value: false))
        
        do {
            let bodyMetrics = try viewContext.fetch(bodyMetricsFetch)
            let dailyMetrics = try viewContext.fetch(dailyMetricsFetch)
            let profiles = try viewContext.fetch(profilesFetch)
            
            // Debug logging
            // print("🔍 Fetched unsynced entries:")
            // print("  - Body Metrics: \(bodyMetrics.count)")
            for metric in bodyMetrics.prefix(3) {
                // print("    • ID: \(metric.id ?? "nil"), Weight: \(metric.weight), Date: \(metric.date ?? Date()), isSynced: \(metric.isSynced)")
            }
            // print("  - Daily Metrics: \(dailyMetrics.count)")
            // print("  - Profiles: \(profiles.count)")
            
            return (bodyMetrics, dailyMetrics, profiles)
        } catch {
            // print("Failed to fetch unsynced entries: \(error)")
            return ([], [], [])
        }
    }
    
    func markAsSynced(entityName: String, id: String) {
        let context = viewContext
        
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
        
        save()
    }
    
    func updateSyncStatus(entityName: String, id: String, status: String, error: String? = nil) {
        let metadata = fetchOrCreateSyncMetadata(entityName: entityName, entityId: id)
        metadata.lastSyncAttempt = Date()
        
        if status == "synced" {
            metadata.lastSyncSuccess = Date()
            metadata.syncRetryCount = 0
            metadata.lastSyncError = nil
        } else {
            metadata.syncRetryCount += 1
            metadata.lastSyncError = error
        }
        
        save()
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
        let bodyMetricsFetch: NSFetchRequest<NSFetchRequestResult> = CachedBodyMetrics.fetchRequest()
        bodyMetricsFetch.predicate = NSPredicate(format: "isMarkedDeleted == %@ AND lastModified < %@",
                                                NSNumber(value: true), date as NSDate)
        
        let dailyMetricsFetch: NSFetchRequest<NSFetchRequestResult> = CachedDailyMetrics.fetchRequest()
        dailyMetricsFetch.predicate = NSPredicate(format: "isMarkedDeleted == %@ AND lastModified < %@",
                                                 NSNumber(value: true), date as NSDate)
        
        let deleteBodyMetrics = NSBatchDeleteRequest(fetchRequest: bodyMetricsFetch)
        let deleteDailyMetrics = NSBatchDeleteRequest(fetchRequest: dailyMetricsFetch)
        
        do {
            try viewContext.execute(deleteBodyMetrics)
            try viewContext.execute(deleteDailyMetrics)
            save()
        } catch {
            // print("Failed to cleanup deleted entries: \(error)")
        }
    }
    
    // MARK: - Delete All Data
    
    func deleteAllData() {
        let context = viewContext
        
        // Delete all body metrics
        let bodyMetricsRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        if let bodyMetrics = try? context.fetch(bodyMetricsRequest) {
            for metric in bodyMetrics {
                context.delete(metric)
            }
        }
        
        // Delete all daily metrics
        let dailyMetricsRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
        if let dailyMetrics = try? context.fetch(dailyMetricsRequest) {
            for metric in dailyMetrics {
                context.delete(metric)
            }
        }
        
        // Delete all profiles
        let profileRequest: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
        if let profiles = try? context.fetch(profileRequest) {
            for profile in profiles {
                context.delete(profile)
            }
        }
        
        // Delete all sync metadata
        let syncRequest: NSFetchRequest<SyncMetadata> = SyncMetadata.fetchRequest()
        if let syncRecords = try? context.fetch(syncRequest) {
            for record in syncRecords {
                context.delete(record)
            }
        }
        
        // Save changes
        save()
    }
    
    // MARK: - Update from Server Data
    
    func updateOrCreateBodyMetric(from data: [String: Any]) {
        let id = data["id"] as? String ?? UUID().uuidString
        
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        
        do {
            let results = try viewContext.fetch(request)
            let metric = results.first ?? CachedBodyMetrics(context: viewContext)
            
            // Update fields
            metric.id = id
            metric.userId = data["user_id"] as? String
            metric.weight = data["weight"] as? Double ?? 0
            metric.bodyFatPercentage = data["body_fat_percentage"] as? Double ?? 0
            metric.muscleMass = data["muscle_mass"] as? Double ?? 0
            metric.notes = data["notes"] as? String
            // metric.source = data["source"] as? String ?? "manual" // source field not in Core Data model
            
            if let dateString = data["logged_at"] as? String {
                metric.date = ISO8601DateFormatter().date(from: dateString)
            }
            
            metric.syncStatus = "synced"
            metric.isSynced = true
            metric.lastModified = Date()
            
            save()
        } catch {
            // print("Error updating body metric from server: \(error)")
        }
    }
    
    func updateOrCreateDailyMetric(from data: [String: Any]) {
        let id = data["id"] as? String ?? UUID().uuidString
        
        let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        
        do {
            let results = try viewContext.fetch(request)
            let metric = results.first ?? CachedDailyMetrics(context: viewContext)
            
            // Update fields
            metric.id = id
            metric.userId = data["user_id"] as? String
            metric.steps = Int32(data["steps"] as? Int ?? 0)
            metric.notes = data["notes"] as? String
            
            if let dateString = data["date"] as? String {
                metric.date = ISO8601DateFormatter().date(from: dateString)
            }
            
            metric.syncStatus = "synced"
            metric.isSynced = true
            metric.lastModified = Date()
            
            save()
        } catch {
            // print("Error updating daily metric from server: \(error)")
        }
    }
    
    func updateOrCreateProfile(from data: [String: Any]) {
        let userId = data["id"] as? String ?? ""
        
        let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.fetchLimit = 1
        
        do {
            let results = try viewContext.fetch(request)
            let profile = results.first ?? CachedProfile(context: viewContext)
            
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
            
            save()
        } catch {
            // print("Error updating profile from server: \(error)")
        }
    }
    
    // MARK: - Export Methods
    
    func fetchAllBodyMetrics(for userId: String) -> [BodyMetrics] {
        let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        
        do {
            let cachedMetrics = try viewContext.fetch(fetchRequest)
            return cachedMetrics.compactMap { $0.toBodyMetrics() }
        } catch {
            // print("Error fetching all body metrics: \(error)")
            return []
        }
    }
    
    func fetchAllDailyLogs(for userId: String) -> [DailyLog] {
        let fetchRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        
        do {
            let cachedLogs = try viewContext.fetch(fetchRequest)
            return cachedLogs.map { log in
                // Extract values with explicit types to help compiler
                let logId: String = log.id ?? UUID().uuidString
                let logUserId: String = log.userId ?? ""
                let logDate: Date = log.date ?? Date()
                let logStepCount: Int? = log.steps != nil ? Int(log.steps) : nil
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
            // print("Error fetching all daily logs: \(error)")
            return []
        }
    }
    
    // MARK: - Debug Methods
    
    func debugPrintAllBodyMetrics() {
        let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        
        do {
            let allMetrics = try viewContext.fetch(fetchRequest)
            // print("🔍 DEBUG: Total body metrics in Core Data: \(allMetrics.count)")
            for (index, metric) in allMetrics.enumerated() {
                // print("  [\(index)] ID: \(metric.id ?? "nil"), UserId: \(metric.userId ?? "nil"), Weight: \(metric.weight), Date: \(metric.date ?? Date()), isSynced: \(metric.isSynced), syncStatus: \(metric.syncStatus ?? "nil")")
                if index >= 5 {
                    // print("  ... and \(allMetrics.count - 5) more")
                    break
                }
            }
        } catch {
            // print("Failed to fetch all body metrics: \(error)")
        }
    }
    
    // MARK: - Cleanup
    
    func cleanupOldData() {
        // Delete body metrics older than 1 year
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)
        
        let bodyMetricsRequest: NSFetchRequest<NSFetchRequestResult> = CachedBodyMetrics.fetchRequest()
        bodyMetricsRequest.predicate = NSPredicate(format: "date < %@ AND isMarkedDeleted == true", oneYearAgo as NSDate)
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: bodyMetricsRequest)
        deleteRequest.resultType = .resultTypeCount
        
        do {
            let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
            // print("Deleted \(result?.result ?? 0) old body metrics")
        } catch {
            // print("Error cleaning up old data: \(error)")
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
                
                if shouldDelete {
                    // print("🗑️ Deleting invalid body metric: \(reasons.joined(separator: ", "))")
                    context.delete(metric)
                    deletedCount += 1
                }
            }
            
            if deletedCount > 0 {
                try context.save()
            }
            
            return deletedCount
        } catch {
            // print("❌ Error cleaning invalid body metrics: \(error)")
            return 0
        }
    }
    
    func repairCorruptedEntries() -> Int {
        let context = persistentContainer.viewContext
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        
        do {
            let allMetrics = try context.fetch(request)
            var repairedCount = 0
            
            for metric in allMetrics {
                var wasRepaired = false
                
                // Repair missing dates with default values
                if metric.date == nil {
                    metric.date = Date()
                    wasRepaired = true
                    // print("🔧 Repaired missing date for metric ID: \(metric.id ?? "unknown")")
                }
                
                if metric.createdAt == nil {
                    metric.createdAt = metric.date ?? Date()
                    wasRepaired = true
                    // print("🔧 Repaired missing createdAt for metric ID: \(metric.id ?? "unknown")")
                }
                
                if metric.updatedAt == nil {
                    metric.updatedAt = metric.lastModified ?? metric.date ?? Date()
                    wasRepaired = true
                    // print("🔧 Repaired missing updatedAt for metric ID: \(metric.id ?? "unknown")")
                }
                
                if wasRepaired {
                    repairedCount += 1
                }
            }
            
            if repairedCount > 0 {
                try context.save()
                // print("✅ Repaired \(repairedCount) corrupted entries")
            }
            
            return repairedCount
        } catch {
            // print("❌ Error repairing corrupted entries: \(error)")
            return 0
        }
    }
}

// MARK: - Model Extensions for Conversion
extension CachedBodyMetrics {
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
            weight: weight > 0 ? weight : nil,
            weightUnit: weightUnit,
            bodyFatPercentage: bodyFatPercentage > 0 ? bodyFatPercentage : nil,
            bodyFatMethod: bodyFatMethod,
            muscleMass: muscleMass > 0 ? muscleMass : nil,
            boneMass: boneMass > 0 ? boneMass : nil,
            notes: notes,
            photoUrl: photoUrl,
            dataSource: dataSource ?? "Manual",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension CachedDailyMetrics {
    func toDailyMetrics() -> DailyMetrics {
        return DailyMetrics(
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
    func toUserProfile() -> UserProfile {
        return UserProfile(
            id: id ?? "",
            email: email ?? "",
            username: username,
            fullName: fullName,
            dateOfBirth: dateOfBirth,
            height: height > 0 ? height : nil,
            heightUnit: heightUnit,
            gender: gender,
            activityLevel: activityLevel,
            goalWeight: goalWeight > 0 ? goalWeight : nil,
            goalWeightUnit: goalWeightUnit
        )
    }
}
