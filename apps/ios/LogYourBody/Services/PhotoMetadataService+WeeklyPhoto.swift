//
// PhotoMetadataService+WeeklyPhoto.swift
// LogYourBody
//
import CoreData
import Foundation
import ImageIO

extension PhotoMetadataService {
    /// Capture facts from the original bytes. A missing EXIF instant stays nil
    /// so import time is never presented as capture time.
    func weeklyPhotoFacts(from data: Data, deviceZone: TimeZone = .current) -> WeeklyPhotoSourceFacts {
        var capturedAt: Date?
        var zone = deviceZone
        var orientation = 1
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            if let raw = properties[kCGImagePropertyOrientation as String] as? Int {
                orientation = raw
            } else if let number = properties[kCGImagePropertyOrientation as String] as? NSNumber {
                orientation = number.intValue
            }
            let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
            let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal as String] as? String
            if let seconds = Self.exifOffsetSeconds(offset), let offsetZone = TimeZone(secondsFromGMT: seconds) {
                zone = offsetZone
            }
            let stamp = (exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String)
                ?? (exif?[kCGImagePropertyExifDateTimeDigitized as String] as? String)
            capturedAt = stamp.flatMap { Self.exifInstant($0, zone: zone) }
        }
        return WeeklyPhotoSourceFacts(
            capturedAt: capturedAt,
            timeZone: zone,
            exifOrientation: orientation,
            contentType: WeeklyPhotoCheckInPolicy.contentType(for: data)
        )
    }

    func recordWeeklyPhotoProvenance(
        id: String,
        userId: String,
        provenance: WeeklyPhotoProvenance,
        coreDataManager: CoreDataManager = .shared,
        writeAdmission: CoreDataManager.WriteAdmission? = nil
    ) async throws -> Bool {
        try await commitWeeklyPhoto(
            id: id,
            userId: userId,
            provenance: provenance,
            localDisplayURL: nil,
            coreDataManager: coreDataManager,
            writeAdmission: writeAdmission
        )
    }

    /// Records provenance. A local display URL keeps the original visible offline
    /// and is not marked pending, so a file URL is not pushed as the remote photo.
    func commitWeeklyPhoto(
        id: String,
        userId: String,
        provenance: WeeklyPhotoProvenance,
        localDisplayURL: String?,
        coreDataManager: CoreDataManager = .shared,
        writeAdmission: CoreDataManager.WriteAdmission? = nil
    ) async throws -> Bool {
        try writeAdmission?()
        let saved = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let wrote = try Self.writeWeeklyPhotoCommit(
                        id: id,
                        userId: userId,
                        provenance: provenance,
                        localDisplayURL: localDisplayURL,
                        in: context
                    )
                    continuation.resume(returning: wrote)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        await MainActor.run {
            coreDataManager.viewContext.refreshAllObjects()
        }
        return saved
    }

    /// Marks photos that predate this check-in. Capture time stays empty when
    /// the original instant was not stored. Import time is not copied into it.
    func backfillWeeklyPhotoProvenance(
        userId: String,
        coreDataManager: CoreDataManager = .shared
    ) async -> Int {
        let changed: Int = await withCheckedContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
                request.predicate = NSPredicate(
                    format: "userId == %@ AND photoUrl != nil AND isMarkedDeleted == %@",
                    userId, NSNumber(value: false)
                )
                let rows = (try? context.fetch(request)) ?? []
                var changed = 0
                for row in rows {
                    guard let id = row.id, let date = row.date else { continue }
                    let previous = BodyMetricSourceMetadata(jsonString: row.sourceMetadataJSON)
                    if previous?.weeklyPhotoProvenance != nil { continue }
                    let digest = Self.localDigest(row.originalPhotoUrl) ?? Self.localDigest(row.photoUrl)
                    let provenance = WeeklyPhotoProvenance(
                        submissionId: "backfill-\(id)",
                        originalSHA256: digest?.sha256 ?? "",
                        originalByteCount: digest?.count ?? 0,
                        contentType: digest?.contentType ?? "unknown",
                        capturedAt: nil,
                        timeZoneIdentifier: TimeZone.current.identifier,
                        effectiveAt: date,
                        dateWasCorrected: false,
                        importedAt: previous?.importedAt.flatMap(WeeklyPhotoTime.date(from:)),
                        exifOrientation: digest?.orientation ?? 1,
                        mirror: "unknown",
                        viewpoint: "unspecified",
                        importSource: "backfill",
                        isBackfill: true,
                        isDuplicate: false,
                        fitSupportsGeometry: false,
                        isPartialOrOccluded: false,
                        countsTowardHabit: false
                    )
                    row.sourceMetadataJSON = (previous ?? BodyMetricSourceMetadata())
                        .recordingWeeklyPhoto(provenance)
                        .jsonString
                    changed += 1
                }
                if changed > 0, context.hasChanges {
                    try? context.save()
                }
                continuation.resume(returning: changed)
            }
        }
        if changed > 0 {
            await MainActor.run {
                coreDataManager.viewContext.refreshAllObjects()
            }
        }
        return changed
    }

    private static func writeWeeklyPhotoCommit(
        id: String,
        userId: String,
        provenance: WeeklyPhotoProvenance,
        localDisplayURL: String?,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND userId == %@", id, userId)
        request.fetchLimit = 1
        guard let row = try context.fetch(request).first else { return false }
        let previous = BodyMetricSourceMetadata(jsonString: row.sourceMetadataJSON) ?? BodyMetricSourceMetadata()
        row.sourceMetadataJSON = previous.recordingWeeklyPhoto(provenance).jsonString
        let now = Date()
        row.updatedAt = now
        row.lastModified = now
        if let localDisplayURL {
            row.photoUrl = localDisplayURL
            let existingOriginal = row.originalPhotoUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingOriginal?.isEmpty != false {
                row.originalPhotoUrl = localDisplayURL
            }
            row.isSynced = true
            row.syncStatus = "local_weekly_photo"
        } else {
            row.isSynced = false
            row.syncStatus = "pending"
        }
        if context.hasChanges { try context.save() }
        return true
    }

    private static func localDigest(_ value: String?) -> (sha256: String, count: Int, contentType: String, orientation: Int)? {
        guard let value, let url = URL(string: value), url.isFileURL,
              let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return (
            WeeklyPhotoCheckInPolicy.sha256Hex(data),
            data.count,
            WeeklyPhotoCheckInPolicy.contentType(for: data),
            1
        )
    }

    private static func exifOffsetSeconds(_ value: String?) -> Int? {
        guard let value, value.count >= 6,
              let sign = value.first, sign == "+" || sign == "-" else { return nil }
        let digits = value.dropFirst().split(separator: ":")
        guard digits.count == 2, let hours = Int(digits[0]), let minutes = Int(digits[1]) else { return nil }
        let magnitude = (hours * 60 + minutes) * 60
        return sign == "-" ? -magnitude : magnitude
    }

    private static func exifInstant(_ string: String, zone: TimeZone) -> Date? {
        let parts = string.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let day = parts[0].split(separator: ":")
        let time = parts[1].split(separator: ":")
        guard day.count == 3, time.count >= 2,
              let year = Int(day[0]), let month = Int(day[1]), let dayValue = Int(day[2]),
              let hour = Int(time[0]), let minute = Int(time[1]) else { return nil }
        let second = time.count > 2 ? Int(time[2]) ?? 0 : 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(
            year: year, month: month, day: dayValue, hour: hour, minute: minute, second: second
        ))
    }
}

struct WeeklyPhotoSourceFacts: Equatable {
    var capturedAt: Date?
    var timeZone: TimeZone
    var exifOrientation: Int
    var contentType: String
}
