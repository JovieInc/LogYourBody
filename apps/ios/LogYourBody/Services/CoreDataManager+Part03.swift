import Foundation
import CoreData
import HealthKit

extension CoreDataManager {
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
        (bodyMetrics: [], dailyMetrics: [], profiles: [])
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

func fetchOrCreateSyncMetadata(entityName: String, entityId: String) -> SyncMetadata {
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
}
