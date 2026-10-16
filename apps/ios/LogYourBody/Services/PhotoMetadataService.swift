//
// PhotoMetadataService.swift
// LogYourBody
//
import Foundation
import Photos
import ImageIO
import CoreData

struct PhotoMetricsUpdateResult {
    let metrics: BodyMetrics
    let createdNewEntry: Bool
    let previousMetric: BodyMetrics?

    init(metrics: BodyMetrics, createdNewEntry: Bool, previousMetric: BodyMetrics? = nil) {
        self.metrics = metrics
        self.createdNewEntry = createdNewEntry
        self.previousMetric = previousMetric
    }
}

enum PhotoMetricsRestoreError: Error {
    case entryNotFound
    #if DEBUG
    case simulatedSaveFailure
    #endif
}

enum PhotoMetricsEditError: Error {
    case entryNotFound
    case pendingEdit
    case uncommittedWrite
}

class PhotoMetadataService {
    static let shared = PhotoMetadataService()

    private init() {}

    /// Extract EXIF orientation from photo metadata
    func extractOrientation(from data: Data) -> CGImagePropertyOrientation {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return .up
        }

        // Get orientation value (1-8)
        if let orientationValue = properties[kCGImagePropertyOrientation as String] as? UInt32 {
            return CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        }

        return .up
    }

    /// Extract date from photo metadata or PHAsset
    func extractDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        // Try to get EXIF date
        if let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            // Try DateTimeOriginal first (when photo was taken)
            if let dateString = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                return parseExifDate(dateString)
            }
            // Fall back to DateTimeDigitized
            if let dateString = exifDict[kCGImagePropertyExifDateTimeDigitized as String] as? String {
                return parseExifDate(dateString)
            }
        }

        // Try TIFF date
        if let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
           let dateString = tiffDict[kCGImagePropertyTIFFDateTime as String] as? String {
            return parseExifDate(dateString)
        }

        return nil
    }

    /// Extract date from PHAsset
    func extractDate(from asset: PHAsset) -> Date {
        // PHAsset.creationDate is when the photo was taken
        return asset.creationDate ?? Date()
    }

    /// Parse EXIF date string format: "yyyy:MM:dd HH:mm:ss"
    private func parseExifDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString)
    }

    /// Find closest body metrics entry for a given date
    func findClosestMetrics(for date: Date, in metrics: [BodyMetrics], maxDaysDifference: Int = 7) -> BodyMetrics? {
        guard !metrics.isEmpty else { return nil }

        let calendar = Calendar.current
        let targetStartOfDay = calendar.startOfDay(for: date)

        // Find metrics within the max days difference
        let closeMetrics = metrics.filter { metric in
            let metricStartOfDay = BodyMetricLocalDate.startOfDay(for: metric.localDate, calendar: calendar) ??
                calendar.startOfDay(for: metric.date)
            let daysDifference = abs(calendar.dateComponents([.day], from: targetStartOfDay, to: metricStartOfDay).day ?? Int.max)
            return daysDifference <= maxDaysDifference
        }

        // Return the closest one
        return closeMetrics.min { metric1, metric2 in
            abs(metric1.date.timeIntervalSince(date)) < abs(metric2.date.timeIntervalSince(date))
        }
    }

    /// Create or update body metrics for a specific date
    func createOrUpdateMetrics(
        for date: Date,
        photoUrl: String? = nil,
        weight: Double? = nil,
        bodyFatPercentage: Double? = nil,
        bodyFatMethod: String? = nil,
        userId: String,
        dataSource: String? = nil,
        preserveExistingMeasurements: Bool = false
    ) async throws -> BodyMetrics {
        try await createOrUpdateMetricsWithResult(
            for: date,
            photoUrl: photoUrl,
            weight: weight,
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatMethod,
            userId: userId,
            dataSource: dataSource,
            preserveExistingMeasurements: preserveExistingMeasurements
        ).metrics
    }

    /// Create or update body metrics and report whether this call created a new local row.
    /// Persists to Core Data before returning so a dismissed log sheet cannot
    /// race the store (the paid Golden Path write).
    func createOrUpdateMetricsWithResult(
        for date: Date,
        photoUrl: String? = nil,
        weight: Double? = nil,
        bodyFatPercentage: Double? = nil,
        bodyFatMethod: String? = nil,
        userId: String,
        dataSource: String? = nil,
        preserveExistingMeasurements: Bool = false
    ) async throws -> PhotoMetricsUpdateResult {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let localDate = BodyMetricLocalDate.key(for: date)

        // Check if metrics already exist for this date
        let existingMetrics = await CoreDataManager.shared.fetchBodyMetrics(
            for: userId,
            localDate: localDate
        )
        .first?.toBodyMetrics()

        if let existing = existingMetrics {
            let updatedWeight = preserveExistingMeasurements ? existing.weight ?? weight : weight ?? existing.weight
            let updatedBodyFat = preserveExistingMeasurements
                ? existing.bodyFatPercentage ?? bodyFatPercentage
                : bodyFatPercentage ?? existing.bodyFatPercentage
            let updatedBodyFatMethod = if preserveExistingMeasurements,
                                          existing.bodyFatPercentage != nil {
                existing.bodyFatMethod
            } else if bodyFatPercentage != nil {
                bodyFatMethod ?? existing.bodyFatMethod
            } else {
                existing.bodyFatMethod
            }

            // Update existing metrics
            let updated = BodyMetrics(
                id: existing.id,
                userId: userId,
                date: existing.date,
                localDate: existing.localDate,
                weight: updatedWeight,
                weightUnit: existing.weightUnit ?? "kg",
                bodyFatPercentage: updatedBodyFat,
                bodyFatMethod: updatedBodyFatMethod,
                muscleMass: existing.muscleMass,
                boneMass: existing.boneMass,
                waistCm: existing.waistCm,
                hipCm: existing.hipCm,
                waistUnit: existing.waistUnit,
                notes: existing.notes,
                photoUrl: photoUrl ?? existing.photoUrl,
                dataSource: existing.dataSource,
                sourceMetadata: existing.sourceMetadata,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )

            try await persistMetricsBeforeReturning(updated, userId: userId)
            return PhotoMetricsUpdateResult(metrics: updated, createdNewEntry: false, previousMetric: existing)
        } else {
            // Create new metrics
            let new = BodyMetrics(
                id: UUID().uuidString,
                userId: userId,
                date: startOfDay,
                localDate: localDate,
                weight: weight,
                weightUnit: "kg",
                bodyFatPercentage: bodyFatPercentage,
                bodyFatMethod: bodyFatMethod,
                muscleMass: nil,
                boneMass: nil,
                notes: nil,
                photoUrl: photoUrl,
                dataSource: resolvedDataSource(
                    explicitDataSource: dataSource,
                    photoUrl: photoUrl,
                    weight: weight,
                    bodyFatPercentage: bodyFatPercentage
                ),
                createdAt: Date(),
                updatedAt: Date()
            )

            if dataSource == nil, !preserveExistingMeasurements, photoUrl == nil,
               weight != nil || bodyFatPercentage != nil {
                try await BodyRecordReviewConsumer.shared.saveNewManualRecord(recordID: new.id, ownerID: userId) {
                    try await self.persistMetricsBeforeReturning(new, userId: userId)
                }
            } else {
                try await persistMetricsBeforeReturning(new, userId: userId)
            }
            return PhotoMetricsUpdateResult(metrics: new, createdNewEntry: true)
        }
    }

    /// Only generic Edit uses this path. Day-based log/create keeps its existing API.
    @MainActor
    func updateExistingMeasurementsWithResult(
        id: String, userId: String, weight: Double?, bodyFatPercentage: Double?,
        bodyFatMethod: String?, clearBodyFat: Bool = false, markManualCorrection: Bool = false,
        writeAdmission: @escaping CoreDataManager.WriteAdmission,
        coreDataManager: CoreDataManager = .shared
    ) async throws -> PhotoMetricsUpdateResult {
        try writeAdmission()
        let result = try await coreDataManager.updateExistingMetricMeasurementsAndWait(
            id: id, userId: userId, weight: weight, bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatMethod, clearBodyFat: clearBodyFat,
            markManualCorrection: markManualCorrection, writeAdmission: writeAdmission
        )
        try writeAdmission()
        return result
    }

    /// The Add Entry sheet dismisses as soon as this method returns. A fire-and-
    /// forget `saveBodyMetrics` lets the sheet close before the row exists, so
    /// the timeline can miss today's measured log and sync can skip it.
    private func persistMetricsBeforeReturning(_ metrics: BodyMetrics, userId: String) async throws {
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metrics, userId: userId)
    }

    /// Restore exactly the measurements replaced by a log, including absent values.
    /// Unlike createOrUpdate, nil means clear; unrelated photo/source fields stay intact.
    func restoreMeasurements(
        id: String,
        userId: String,
        previous: BodyMetrics,
        context: NSManagedObjectContext? = nil
    ) async throws {
        guard previous.id == id, previous.userId == userId else {
            throw PhotoMetricsRestoreError.entryNotFound
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestHomeV2UndoFailureFixture") {
            throw PhotoMetricsRestoreError.simulatedSaveFailure
        }
        #endif
        let context = context ?? CoreDataManager.shared.viewContext
        try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(
                format: "id == %@ AND userId == %@ AND isMarkedDeleted == NO", id, userId
            )
            request.fetchLimit = 1
            guard let cached = try context.fetch(request).first else {
                throw PhotoMetricsRestoreError.entryNotFound
            }

            let previousValues = cached.dictionaryWithValues(forKeys: [
                "weight", "weightUnit", "bodyFatPercentage", "bodyFatMethod", "updatedAt",
                "lastModified", "isSynced", "syncStatus"
            ])
            cached.weight = previous.weight ?? 0
            cached.weightUnit = previous.weightUnit
            cached.bodyFatPercentage = previous.bodyFatPercentage ?? 0
            cached.bodyFatMethod = previous.bodyFatMethod
            let now = Date()
            cached.updatedAt = now
            cached.lastModified = now
            cached.isSynced = false
            cached.syncStatus = "pending"
            do {
                try context.save()
            } catch {
                // Do not leave a failed Undo visible as an unsaved local edit.
                cached.setValuesForKeys(previousValues)
                throw error
            }
        }
    }

    /// Create or reuse the metrics row for an upload and mark empty placeholders in flight atomically.
    func createOrUpdateMetricsForPhotoUpload(
        for date: Date,
        userId: String,
        writeAdmission: CoreDataManager.WriteAdmission? = nil
    ) async throws -> PhotoMetricsUpdateResult {
        try await CoreDataManager.shared.createOrUpdatePhotoUploadMetricsPlaceholder(
            for: date,
            userId: userId,
            writeAdmission: writeAdmission
        )
    }

    func prepareExistingMetricsForPhotoUpload(
        id: String,
        userId: String,
        writeAdmission: CoreDataManager.WriteAdmission? = nil
    ) async throws -> PhotoMetricsUpdateResult {
        let metrics = try await CoreDataManager.shared.prepareExistingPhotoUploadMetrics(
            id: id,
            userId: userId,
            writeAdmission: writeAdmission
        )
        return PhotoMetricsUpdateResult(metrics: metrics, createdNewEntry: false)
    }

    /// Estimate weight based on nearby entries
    func estimateWeight(for date: Date, metrics: [BodyMetrics]) -> (value: Double, isEstimated: Bool)? {
        let sortedMetrics = metrics.filter { $0.weight != nil }.sorted { $0.date < $1.date }
        guard !sortedMetrics.isEmpty else { return nil }

        // Find metrics before and after the date
        let before = sortedMetrics.last { $0.date <= date }
        let after = sortedMetrics.first { $0.date > date }

        if let beforeMetric = before, let afterMetric = after,
           let beforeWeight = beforeMetric.weight, let afterWeight = afterMetric.weight {
            // Linear interpolation between two points
            let totalInterval = afterMetric.date.timeIntervalSince(beforeMetric.date)
            let progressInterval = date.timeIntervalSince(beforeMetric.date)
            let progress = progressInterval / totalInterval

            let estimatedWeight = beforeWeight + (afterWeight - beforeWeight) * progress
            return (round(estimatedWeight * 10) / 10, true)
        } else if let closestMetric = before ?? after {
            // Use the closest available metric
            return (closestMetric.weight ?? 0, true)
        }

        return nil
    }

    private func resolvedDataSource(
        explicitDataSource: String?,
        photoUrl: String?,
        weight: Double?,
        bodyFatPercentage: Double?
    ) -> String {
        if let explicitDataSource {
            return BodyMetricSource.normalizedRawValue(explicitDataSource)
        }

        if weight != nil || bodyFatPercentage != nil {
            return BodyMetricSource.manual.rawValue
        }

        if photoUrl != nil {
            return BodyMetricSource.photo.rawValue
        }

        return BodyMetricSource.photo.rawValue
    }

    /// Estimate from the current measurements without retaining results across edits or accounts.
    func estimateBodyFat(for date: Date, metrics: [BodyMetrics]) -> (value: Double, isEstimated: Bool)? {
        var before: BodyMetrics?
        var after: BodyMetrics?
        for metric in metrics where metric.bodyFatPercentage != nil {
            if metric.date <= date {
                // Match stable chronological sorting: the last equal-date entry wins before.
                if let previous = before, previous.date > metric.date { continue }
                before = metric
            } else {
                if let following = after, following.date <= metric.date { continue }
                after = metric
            }
        }

        if let before, let after,
           let beforeValue = before.bodyFatPercentage, let afterValue = after.bodyFatPercentage {
            let interval = after.date.timeIntervalSince(before.date)
            let progress = date.timeIntervalSince(before.date) / interval
            return (round((beforeValue + (afterValue - beforeValue) * progress) * 10) / 10, true)
        }
        guard let value = (before ?? after)?.bodyFatPercentage else { return nil }
        return (value, true)
    }
}
