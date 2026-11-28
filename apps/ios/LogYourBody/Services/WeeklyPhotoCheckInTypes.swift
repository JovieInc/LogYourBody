//
// WeeklyPhotoCheckInTypes.swift
// LogYourBody
//
import Foundation

/// One ordinary weekly mirror selfie. Side, back, scale, DEXA, body-fat and
/// pose fitting stay optional. A valid diary photo is never rejected because
/// it cannot support geometric fitting.
enum WeeklyPhotoLibraryAccess: String, Equatable {
    case authorized
    case limited
    case denied
    case restricted
    case notDetermined
    case unknown
}

struct WeeklyPhotoProvenance: Equatable {
    var submissionId: String
    var originalSHA256: String
    var originalByteCount: Int
    var contentType: String
    var capturedAt: Date?
    var timeZoneIdentifier: String
    var effectiveAt: Date
    var dateWasCorrected: Bool
    var importedAt: Date?
    var exifOrientation: Int
    var mirror: String
    var viewpoint: String
    var importSource: String
    var isBackfill: Bool
    var isDuplicate: Bool
    var fitSupportsGeometry: Bool
    var isPartialOrOccluded: Bool
    var countsTowardHabit: Bool
    /// File name only. An absolute path would publish a device location.
    var localFileName: String?

    static let storageKey = "weekly_photo_v1"
    static let viewpoints = ["front", "side", "back", "unspecified"]
    static let mirrors = ["mirrored", "original", "unknown"]
    static let sources = ["camera", "library", "backfill", "unknown"]

    var storageFields: [String: String] {
        var fields = [
            "submission_id": submissionId,
            "original_sha256": originalSHA256,
            "original_byte_count": String(originalByteCount),
            "content_type": contentType,
            "time_zone": timeZoneIdentifier,
            "effective_at": WeeklyPhotoTime.string(from: effectiveAt),
            "date_was_corrected": dateWasCorrected ? "true" : "false",
            "exif_orientation": String(exifOrientation),
            "mirror": mirror,
            "viewpoint": viewpoint,
            "import_source": importSource,
            "is_backfill": isBackfill ? "true" : "false",
            "is_duplicate": isDuplicate ? "true" : "false",
            "fit_supports_geometry": fitSupportsGeometry ? "true" : "false",
            "is_partial_or_occluded": isPartialOrOccluded ? "true" : "false",
            "counts_toward_habit": countsTowardHabit ? "true" : "false"
        ]
        if let localFileName = Self.fileName(localFileName) {
            fields["local_file"] = localFileName
        }
        if let capturedAt {
            fields["captured_at"] = WeeklyPhotoTime.string(from: capturedAt)
        }
        if let importedAt {
            fields["imported_at"] = WeeklyPhotoTime.string(from: importedAt)
        }
        return fields
    }

    init(
        submissionId: String,
        originalSHA256: String,
        originalByteCount: Int,
        contentType: String,
        capturedAt: Date?,
        timeZoneIdentifier: String,
        effectiveAt: Date,
        dateWasCorrected: Bool,
        importedAt: Date?,
        exifOrientation: Int,
        mirror: String,
        viewpoint: String,
        importSource: String,
        isBackfill: Bool,
        isDuplicate: Bool,
        fitSupportsGeometry: Bool,
        isPartialOrOccluded: Bool,
        countsTowardHabit: Bool,
        localFileName: String? = nil
    ) {
        self.submissionId = submissionId
        self.originalSHA256 = originalSHA256
        self.originalByteCount = originalByteCount
        self.contentType = contentType
        self.capturedAt = capturedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.effectiveAt = effectiveAt
        self.dateWasCorrected = dateWasCorrected
        self.importedAt = importedAt
        self.exifOrientation = exifOrientation
        self.mirror = mirror
        self.viewpoint = viewpoint
        self.importSource = importSource
        self.isBackfill = isBackfill
        self.isDuplicate = isDuplicate
        self.fitSupportsGeometry = fitSupportsGeometry
        self.isPartialOrOccluded = isPartialOrOccluded
        self.countsTowardHabit = countsTowardHabit
        self.localFileName = Self.fileName(localFileName)
    }

    /// Keeps a bare file name. Slashes and URL schemes never enter storage.
    static func fileName(_ value: String?) -> String? {
        guard let value else { return nil }
        let base = value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? value
        let cleaned = base.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
        guard !cleaned.isEmpty, cleaned.count <= 80, !cleaned.contains(":") else { return nil }
        return cleaned
    }

    init?(storage: [String: String]) {
        guard let submissionId = storage["submission_id"],
              let effectiveAt = storage["effective_at"].flatMap(WeeklyPhotoTime.date(from:)) else {
            return nil
        }
        self.submissionId = submissionId
        originalSHA256 = storage["original_sha256"] ?? ""
        originalByteCount = Int(storage["original_byte_count"] ?? "") ?? 0
        contentType = storage["content_type"] ?? "unknown"
        capturedAt = storage["captured_at"].flatMap(WeeklyPhotoTime.date(from:))
        timeZoneIdentifier = storage["time_zone"] ?? TimeZone.current.identifier
        self.effectiveAt = effectiveAt
        dateWasCorrected = storage["date_was_corrected"] == "true"
        importedAt = storage["imported_at"].flatMap(WeeklyPhotoTime.date(from:))
        exifOrientation = Int(storage["exif_orientation"] ?? "") ?? 1
        mirror = storage["mirror"] ?? "unknown"
        viewpoint = storage["viewpoint"] ?? "unspecified"
        importSource = storage["import_source"] ?? "unknown"
        isBackfill = storage["is_backfill"] == "true"
        isDuplicate = storage["is_duplicate"] == "true"
        fitSupportsGeometry = storage["fit_supports_geometry"] == "true"
        isPartialOrOccluded = storage["is_partial_or_occluded"] == "true"
        countsTowardHabit = storage["counts_toward_habit"] == "true"
        localFileName = Self.fileName(storage["local_file"])
    }
}

enum WeeklyPhotoTime {
    private static let precise = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func string(from date: Date) -> String {
        date.formatted(precise)
    }

    static func date(from string: String) -> Date? {
        if let date = try? Date(string, strategy: precise) { return date }
        return try? Date(string, strategy: wholeSeconds)
    }
}

struct WeeklyPhotoDraft: Equatable {
    var submissionId: String
    var originalBytes: Data
    var contentType: String
    var capturedAt: Date?
    var timeZone: TimeZone
    var effectiveAt: Date
    var dateWasCorrected: Bool
    var importedAt: Date?
    var exifOrientation: Int
    var mirror: String
    var viewpoint: String
    var importSource: String
    var fitSupportsGeometry: Bool
    var isPartialOrOccluded: Bool
    var libraryAccess: WeeklyPhotoLibraryAccess
    var persisted: Bool
    var uploaded: Bool
    var localFileName: String?
}

struct WeeklyPhotoSaveOutcome: Equatable {
    var durable: Bool
    var selectedMoment: Date
    var offersComparison: Bool
    var originalImageUsable: Bool
    /// Heavy plate or reconstruction work must not gate the original image.
    var waitsForReconstruction: Bool
    var provenance: WeeklyPhotoProvenance
}

struct WeeklyPhotoHabitMetric: Equatable {
    var event: String
    var properties: [String: String]
    var countsTowardHabit: Bool
    var denominator: String
}
