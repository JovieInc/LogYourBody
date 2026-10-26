import Foundation
import CoreData
import HealthKit

extension CoreDataManager {
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
                Self.legacyBodyMetricDatePredicate(userId: userId, localDate: normalizedLocalDate)
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

static func legacyBodyMetricDatePredicate(userId: String, localDate: String) -> NSPredicate {
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

            predicates.append(NSPredicate(format: "isExcluded == NO"))
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
        let metrics = await CachedBodyMetrics.bodyMetricsInBatches(from: cached)
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

    /// Identity lookup, admission and mutation share one context turn. Include
    /// tombstones so an anchor reset cannot resurrect a deliberately deleted import.
    func saveHealthKitBodyMetricsAndWait(
        _ metric: BodyMetrics, allowStandaloneBodyFat: Bool = true, writeAdmission: @escaping WriteAdmission
    ) async throws {
        let context = viewContext
        try await context.perform {
            try MainActor.assumeIsolated { try writeAdmission() }
            guard let incoming = metric.sourceMetadata, incoming.healthKitSampleKey != nil else {
                throw HealthKitImportIdentityError.alreadyRecorded
            }
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            let recordID = incoming.healthKitRecordID(userId: metric.userId) ?? metric.id
            var identities = [incoming.sampleId, incoming.healthKitContext["sync_identifier"]].compactMap { $0 }
            identities.append(recordID)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "userId == %@ AND dataSource == %@", metric.userId, BodyMetricSource.healthKit.rawValue),
                NSCompoundPredicate(orPredicateWithSubpredicates: identities.map {
                    // Match the stored JSON representation even for quoted/escaped sync IDs.
                    NSPredicate(
                        format: "sourceMetadataJSON CONTAINS %@ OR id == %@",
                        BodyMetricSourceMetadata.jsonFragment(for: $0), $0
                    )
                })
            ])
            let rows = try context.fetch(request)
            let match = rows.first { row in
                guard let metadata = BodyMetricSourceMetadata(jsonString: row.sourceMetadataJSON) else { return false }
                return Self.matchesHealthKitImport(incoming, previous: metadata) ||
                    (metric.weight == nil && metadata.pairedHealthKitBodyFat.map {
                        Self.matchesHealthKitImport(incoming, previous: $0)
                    } == true)
            }
            if match == nil, rows.contains(where: { $0.id == recordID }) {
                // Corrupt provenance must not create a second row with the same stable ID.
                throw HealthKitImportIdentityError.alreadyRecorded
            }
            if match == nil, metric.weight == nil, !allowStandaloneBodyFat {
                throw HealthKitImportIdentityError.alreadyRecorded
            }
            let cached = match ?? CachedBodyMetrics(context: context)
            let previous = BodyMetricSourceMetadata(jsonString: cached.sourceMetadataJSON)
            let editsPairedFat = metric.weight == nil && previous?.pairedHealthKitBodyFat.map {
                Self.matchesHealthKitImport(incoming, previous: $0)
            } == true
            let priorSample = editsPairedFat ? previous?.pairedHealthKitBodyFat : previous
            if let priorSample {
                guard !cached.isMarkedDeleted, priorSample.sampleId != incoming.sampleId,
                      !priorSample.replacedHealthKitSampleIDs.contains(incoming.sampleId ?? ""),
                      incoming.healthKitSyncVersion >= priorSample.healthKitSyncVersion else {
                    throw HealthKitImportIdentityError.alreadyRecorded
                }
            }
            var metadata = priorSample.map { incoming.replacingHealthKitSample($0) } ?? incoming
            if match == nil {
                cached.id = recordID
                cached.userId = metric.userId
                cached.createdAt = metric.createdAt
                cached.dataSource = BodyMetricSource.healthKit.rawValue
                cached.notes = metric.notes
            }
            if editsPairedFat, let previous {
                metadata = previous.pairingHealthKitBodyFat(metadata)
            } else {
                cached.date = metric.date
                cached.localDate = metric.localDate
                if let weight = metric.weight, previous?.entrySource(for: .weight) != .manual {
                    cached.weight = weight
                    cached.weightUnit = metric.weightUnit
                }
                if metadata.pairedHealthKitBodyFat == nil, let paired = previous?.pairedHealthKitBodyFat {
                    metadata = metadata.pairingHealthKitBodyFat(paired)
                }
                metadata = metadata.restoringEntrySources(from: previous, fields: Set(BodyMetricField.allCases))
            }
            if let fat = metric.bodyFatPercentage, previous?.entrySource(for: .bodyFat) != .manual {
                cached.bodyFatPercentage = fat
                cached.bodyFatMethod = metric.bodyFatMethod
            }
            cached.sourceMetadataJSON = metadata.jsonString
            cached.updatedAt = metric.updatedAt
            cached.lastModified = Date()
            cached.isSynced = false
            cached.syncStatus = "pending"
            try context.save()
        }
    }

    private static func matchesHealthKitImport(
        _ incoming: BodyMetricSourceMetadata, previous: BodyMetricSourceMetadata
    ) -> Bool {
        guard incoming.sourceBundleId == previous.sourceBundleId else { return false }
        return incoming.healthKitSampleKey == previous.healthKitSampleKey ||
            previous.replacedHealthKitSampleIDs.contains(incoming.sampleId ?? "") ||
            (incoming.healthKitSyncKey != nil && incoming.healthKitSyncKey == previous.healthKitSyncKey)
    }

    func hkSampleExists(hkUUID: String, sourceBundleId: String, userId: String) async -> Bool {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedHKSample> = CachedHKSample.fetchRequest()
            request.predicate = NSPredicate(
                format: "hkUUID == %@ AND sourceBundleId == %@ AND userId == %@", hkUUID, sourceBundleId, userId
            )
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

        // Keep raw imports off the main queue while serializing lookup and save.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            saveQueue.async {
                let context = self.persistentContainer.newBackgroundContext()
                context.performAndWait {
                    for sample in samples {
                        let request: NSFetchRequest<CachedHKSample> = CachedHKSample.fetchRequest()
                        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                            NSPredicate(format: "userId == %@ AND quantityType == %@", sample.userId, sample.quantityType),
                            sample.sourceBundleId.map { NSPredicate(format: "sourceBundleId == %@", $0) }
                                ?? NSPredicate(format: "sourceBundleId == nil")
                        ])
                        let syncID = sample.metadata?[HKMetadataKeySyncIdentifier].flatMap { $0.isEmpty ? nil : $0 }
                        let existing = (try? context.fetch(request))?.first { row in
                            if row.hkUUID == sample.hkUUID { return true }
                            guard let syncID, let data = row.metadataJSON,
                                  let metadata = try? JSONDecoder().decode([String: String].self, from: data) else {
                                return false
                            }
                            return metadata[HKMetadataKeySyncIdentifier] == syncID ||
                                metadata["LYBReplacedSampleUUIDs"]?.components(separatedBy: ",").contains(sample.hkUUID) == true
                        }

                        let cached: CachedHKSample
                        var metadata = sample.metadata ?? [:]

                        if let existing {
                            if existing.hkUUID == sample.hkUUID { continue }
                            let prior = existing.metadataJSON.flatMap {
                                try? JSONDecoder().decode([String: String].self, from: $0)
                            } ?? [:]
                            let retired = (prior["LYBReplacedSampleUUIDs"] ?? "").components(separatedBy: ",")
                            guard !retired.contains(sample.hkUUID),
                                  (Int(metadata[HKMetadataKeySyncVersion] ?? "") ?? 0) >=
                                    (Int(prior[HKMetadataKeySyncVersion] ?? "") ?? 0) else { continue }
                            metadata["LYBReplacedSampleUUIDs"] = (retired + [existing.hkUUID].compactMap { $0 })
                                .filter { !$0.isEmpty }.joined(separator: ",")
                            cached = existing
                        } else {
                            cached = CachedHKSample(context: context)
                            cached.id = BodyMetricSourceMetadata(
                                sourceBundleId: sample.sourceBundleId, sampleId: sample.hkUUID, quantityType: sample.quantityType
                            ).recordingHealthKitContext([
                                "sync_identifier": syncID ?? ""
                            ]).healthKitRecordID(userId: sample.userId) ?? sample.id
                            cached.createdAt = sample.createdAt
                        }

                        cached.hkUUID = sample.hkUUID
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

                        if !metadata.isEmpty, let data = try? JSONEncoder().encode(metadata) {
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
                continuation.resume()
            }
        }
    }

@available(*, unavailable, message: "Use async fetchBodyMetrics(for:from:to:) instead")
    func fetchBodyMetricsSync(for userId: String, from startDate: Date? = nil, to endDate: Date? = nil) -> [CachedBodyMetrics] {
        []
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

                guard let updated = cachedMetric.toBodyMetrics() else {
                    return nil
                }

                // Schedule background body score recalculation when weight/body fat entries change.
                BodyScoreCache.shared.invalidate(for: updated.userId)
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

@discardableResult
    func markPhotoPlaceholderUploadInFlight(id: String, userId: String) async -> Bool {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@ AND userId == %@", id, userId)
            fetchRequest.fetchLimit = 1

            do {
                guard let cachedMetric = try context.fetch(fetchRequest).first,
                      Self.isUploadPlaceholderCandidate(cachedMetric, userId: userId) else {
                    return false
                }

                let now = Date()
                cachedMetric.syncStatus = Self.photoUploadInFlightSyncStatus
                cachedMetric.updatedAt = now
                cachedMetric.lastModified = now
                cachedMetric.isSynced = false

                if context.hasChanges {
                    try context.save()
                }

                return true
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "markPhotoPlaceholderUploadInFlight", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "markPhotoPlaceholderUploadInFlight",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return false
            }
        }
    }

@discardableResult
    func markPhotoUploadStorageCommitted(id: String, userId: String, storagePath: String) async -> Bool {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@ AND userId == %@", id, userId)
            fetchRequest.fetchLimit = 1

            do {
                guard let cachedMetric = try context.fetch(fetchRequest).first,
                      Self.isUploadPlaceholderCandidate(cachedMetric, userId: userId) else {
                    return false
                }

                let now = Date()
                cachedMetric.originalPhotoUrl = storagePath
                cachedMetric.syncStatus = Self.photoUploadStorageCommittedSyncStatus
                cachedMetric.updatedAt = now
                cachedMetric.lastModified = now
                cachedMetric.isSynced = false

                if context.hasChanges {
                    try context.save()
                }

                return true
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "markPhotoUploadStorageCommitted", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "markPhotoUploadStorageCommitted",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return false
            }
        }
    }

func markBodyMetricDeleted(id: String, userId: String) async -> Bool {
        let context = viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@ AND userId == %@", id, userId)
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

func deleteEmptyPhotoPlaceholder(
        id: String,
        userId: String,
        writeAdmission: WriteAdmission? = nil
    ) async -> Bool {
        let context = viewContext

        return await context.perform {
            do {
                try MainActor.assumeIsolated { try writeAdmission?() }
            } catch {
                return false
            }
            let fetchRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@ AND userId == %@", id, userId)
            fetchRequest.fetchLimit = 1

            do {
                guard let cachedMetric = try context.fetch(fetchRequest).first,
                      Self.isDeletableEmptyPhotoPlaceholder(cachedMetric, userId: userId) else {
                    return false
                }

                context.delete(cachedMetric)

                if context.hasChanges {
                    try context.save()
                }

                return true
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "deleteEmptyPhotoPlaceholder", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "deleteEmptyPhotoPlaceholder",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return false
            }
        }
    }

static func isDeletableEmptyPhotoPlaceholder(_ metric: CachedBodyMetrics, userId: String) -> Bool {
        isUploadPlaceholderCandidate(metric, userId: userId) &&
            !isPhotoUploadStorageCommittedSyncStatus(metric.syncStatus) &&
            Self.isBlank(metric.notes) &&
            Self.isBlank(metric.sourceMetadataJSON)
    }

static func isUploadPlaceholderCandidate(_ metric: CachedBodyMetrics, userId: String) -> Bool {
        metric.userId == userId &&
            !metric.isSynced &&
            !metric.isMarkedDeleted &&
            BodyMetricSource.normalizedRawValue(metric.dataSource) == BodyMetricSource.photo.rawValue &&
            metric.weight <= 0 &&
            metric.bodyFatPercentage <= 0 &&
            metric.muscleMass <= 0 &&
            metric.boneMass <= 0 &&
            metric.waistCircumference <= 0 &&
            metric.hipCircumference <= 0 &&
            Self.isBlank(metric.photoUrl)
    }

static func isPhotoUploadPlaceholderSyncStatus(_ value: String?) -> Bool {
        isPhotoUploadInFlightSyncStatus(value) || isPhotoUploadStorageCommittedSyncStatus(value)
    }

static func isPhotoUploadInFlightSyncStatus(_ value: String?) -> Bool {
        value == photoUploadInFlightSyncStatus
    }

static func isPhotoUploadStorageCommittedSyncStatus(_ value: String?) -> Bool {
        value == photoUploadStorageCommittedSyncStatus
    }

static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
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
        nil
    }
}
