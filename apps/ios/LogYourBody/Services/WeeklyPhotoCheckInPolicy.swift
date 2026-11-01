//
// WeeklyPhotoCheckInPolicy.swift
// LogYourBody
//
import CryptoKit
import Foundation
import UIKit

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

enum WeeklyPhotoCheckInPolicy {
    struct Prompt: Equatable {
        var weekKey: String
        var title: String
        var message: String
        var actionTitle: String
        var dismissTitle: String
    }

    struct Guidance: Equatable {
        var showsPreviousOutline: Bool
        var distanceCue: String
        var poseCue: String
        var blocksSave: Bool
    }

    struct Attempt: Equatable {
        var outcome: WeeklyPhotoSaveOutcome?
        var metrics: [WeeklyPhotoHabitMetric]
    }

    static let dismissedWeekDefaultsKey = "lyb.weeklyPhotoCheckIn.dismissedWeek"
    static let killSwitchKey = "weekly_photo_check_in_kill_switch"
    static let releaseDescriptor = FeatureReleaseDescriptor(
        flagKey: "weekly_photo_check_in",
        killSwitchKey: killSwitchKey,
        stage: .graduated,
        minimumBuild: nil
    )

    /// Habit denominators. Duplicate submission ids, identical same-week bytes,
    /// and backfills are outside every numerator and denominator.
    static let denominators: [String: String] = [
        "capture_save_rate": "Habit-eligible starts. Excludes duplicates, backfills and abandoned attempts.",
        "capture_save_numerator": "Habit-eligible durable saves. Same-week identical bytes do not count.",
        "time_to_first_usable": "First habit save with no earlier habit photo. Elapsed is bucketed. Backfills excluded.",
        "second_photo_return": "Habit-eligible saves whose prior habit-photo count is one.",
        "weekly_retention": "Habit-eligible saves that follow a habit photo in an earlier week."
    ]

    static let captureStarted = "weekly_photo_capture_started"
    static let captureSaved = "weekly_photo_capture_saved"
    static let captureFailed = "weekly_photo_capture_failed"
    static let firstUsable = "weekly_photo_first_usable"
    static let secondReturn = "weekly_photo_second_return"
    static let weekRetained = "weekly_photo_week_retained"

    @MainActor
    static func promptsAreEnabled(
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return FeatureReleaseEvaluator.evaluate(
            releaseDescriptor,
            context: FeatureReleaseContext(
                actor: .ordinaryCustomer,
                installedBuild: 1,
                configState: .fresh,
                enableGate: false,
                killSwitch: checkGate(killSwitchKey)
            )
        ).isEnabled
    }

    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: date)
    }

    static func weekKey(for date: Date, calendar: Calendar) -> String {
        let start = weekInterval(containing: date, calendar: calendar)?.start ?? date
        let day = calendar.dateComponents([.year, .month, .day], from: start)
        let year = day.year ?? 0
        let month = day.month ?? 0
        let value = day.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, value)
    }

    static func contentType(for data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpeg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        guard data.count >= 12 else { return "unknown" }
        let brand = String(data: data, encoding: .ascii) ?? ""
        if brand.contains("ftyp"),
           brand.contains("heic") || brand.contains("heif") || brand.contains("mif1") {
            return "heic"
        }
        return "unknown"
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func retainsLocally(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet, .timedOut, .networkConnectionLost, .dataNotAllowed,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    static func guidance(hasPreviousPhoto: Bool, guideEnabled: Bool) -> Guidance {
        Guidance(
            showsPreviousOutline: hasPreviousPhoto && guideEnabled,
            distanceCue: hasPreviousPhoto
                ? "About the same distance as last time."
                : "A comfortable distance is enough.",
            poseCue: "Front view is enough. Side and back are optional.",
            blocksSave: false
        )
    }

    static func viewpointsMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "unspecified" || rhs == "unspecified" { return true }
        return lhs == rhs
    }

    static func prompt(
        metrics: [BodyMetrics],
        now: Date = Date(),
        dismissedWeekKey: String?,
        calendar: Calendar = .current,
        enabled: Bool = true
    ) -> Prompt? {
        guard enabled else { return nil }
        let key = weekKey(for: now, calendar: calendar)
        if dismissedWeekKey == key { return nil }
        let hasEvidence = metrics.contains { metric in
            guard !metric.isExcluded, PhotoTimelineHUDPolicy.hasUsablePhoto(metric) else { return false }
            let moment = metric.sourceMetadata?.weeklyPhotoProvenance?.effectiveAt ?? metric.date
            return weekKey(for: moment, calendar: calendar) == key
        }
        guard !hasEvidence else { return nil }
        return Prompt(
            weekKey: key,
            title: "Add this week’s photo",
            message: "One mirror selfie is enough.",
            actionTitle: "Add photo",
            dismissTitle: "Not now"
        )
    }

    static func provenances(in metrics: [BodyMetrics]) -> [WeeklyPhotoProvenance] {
        metrics.compactMap { $0.sourceMetadata?.weeklyPhotoProvenance }
    }

    /// Stored check-ins, plus a synthetic backfill for a photo that has no
    /// provenance yet. Backfill still counts as a photo for comparison.
    static func history(from metrics: [BodyMetrics]) -> [WeeklyPhotoProvenance] {
        metrics.compactMap { metric in
            metric.sourceMetadata?.weeklyPhotoProvenance ?? backfill(metric: metric)
        }
    }

    static func isRetainedOffline(_ error: Error) -> Bool {
        if let photoError = error as? PhotoUploadManager.PhotoError {
            if case .networkError = photoError { return true }
            return false
        }
        if let urlError = error as? URLError {
            return retainsLocally(urlError.code)
        }
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? URLError {
            return retainsLocally(underlying.code)
        }
        return false
    }

    static func habitPhotos(_ history: [WeeklyPhotoProvenance]) -> [WeeklyPhotoProvenance] {
        history.filter { $0.countsTowardHabit && !$0.isBackfill && !$0.isDuplicate }
    }

    static func historyBucket(_ count: Int) -> String {
        switch count {
        case 0: return "zero"
        case 1: return "one"
        default: return "two_or_more"
        }
    }

    static func elapsedBucket(_ elapsed: TimeInterval) -> String {
        if elapsed < 2 { return "under_2s" }
        if elapsed < 10 { return "under_10s" }
        if elapsed < 60 { return "under_60s" }
        return "over_60s"
    }

    static func captureStartedMetric(
        source: String,
        access: String,
        history: [WeeklyPhotoProvenance]
    ) -> WeeklyPhotoHabitMetric {
        let prior = habitPhotos(history).count
        return WeeklyPhotoHabitMetric(
            event: captureStarted,
            properties: [
                "source": source == "library" ? "library" : "camera",
                "history": historyBucket(prior),
                "access": ["authorized", "limited", "unknown"].contains(access) ? access : "unknown"
            ],
            countsTowardHabit: true,
            denominator: "capture_save_rate"
        )
    }

    static func failureMetric(source: String, outcome: String) -> WeeklyPhotoHabitMetric {
        let counted = outcome == "permission_denied" || outcome == "offline" || outcome == "empty"
        return WeeklyPhotoHabitMetric(
            event: captureFailed,
            properties: [
                "source": ["camera", "library", "unknown"].contains(source) ? source : "unknown",
                "outcome": outcome
            ],
            countsTowardHabit: counted,
            denominator: counted ? "capture_save_rate" : "abandoned"
        )
    }

    static func backfill(
        metric: BodyMetrics,
        originalSHA256: String = "",
        originalByteCount: Int = 0,
        contentType: String = "unknown",
        exifOrientation: Int = 1,
        timeZone: TimeZone = .current
    ) -> WeeklyPhotoProvenance? {
        guard PhotoTimelineHUDPolicy.hasUsablePhoto(metric),
              metric.sourceMetadata?.weeklyPhotoProvenance == nil else {
            return nil
        }
        let importedAt = metric.sourceMetadata?.importedAt.flatMap(WeeklyPhotoTime.date(from:))
        return WeeklyPhotoProvenance(
            submissionId: "backfill-\(metric.id)",
            originalSHA256: originalSHA256,
            originalByteCount: originalByteCount,
            contentType: contentType,
            capturedAt: nil,
            timeZoneIdentifier: timeZone.identifier,
            effectiveAt: metric.date,
            dateWasCorrected: false,
            importedAt: importedAt,
            exifOrientation: exifOrientation,
            mirror: "unknown",
            viewpoint: "unspecified",
            importSource: "backfill",
            isBackfill: true,
            isDuplicate: false,
            fitSupportsGeometry: false,
            isPartialOrOccluded: false,
            countsTowardHabit: false
        )
    }

    static func resolve(
        _ draft: WeeklyPhotoDraft,
        history: [WeeklyPhotoProvenance],
        elapsed: TimeInterval = 0,
        calendar: Calendar = .current
    ) -> Attempt {
        if draft.libraryAccess == .denied || draft.libraryAccess == .restricted,
           draft.importSource == "library" {
            return Attempt(outcome: nil, metrics: [failureMetric(source: "library", outcome: "permission_denied")])
        }
        if draft.originalBytes.isEmpty {
            return Attempt(outcome: nil, metrics: [failureMetric(source: draft.importSource, outcome: "empty")])
        }

        let digest = sha256Hex(draft.originalBytes)
        let contentType = draft.contentType == "unknown" ? contentType(for: draft.originalBytes) : draft.contentType
        if let existing = history.first(where: { $0.submissionId == draft.submissionId }) {
            var duplicate = existing
            duplicate.isDuplicate = true
            duplicate.countsTowardHabit = false
            let outcome = WeeklyPhotoSaveOutcome(
                durable: true,
                selectedMoment: existing.effectiveAt,
                offersComparison: false,
                originalImageUsable: true,
                waitsForReconstruction: false,
                provenance: duplicate
            )
            return Attempt(
                outcome: outcome,
                metrics: [savedMetric(duplicate, source: draft.importSource, history: history, uploaded: draft.uploaded)]
            )
        }

        let week = weekKey(for: draft.effectiveAt, calendar: calendar)
        let sameWeekBytes = history.contains { prior in
            prior.originalSHA256 == digest && !digest.isEmpty && !prior.isDuplicate &&
                weekKey(for: prior.effectiveAt, calendar: calendar) == week
        }
        let priorHabit = habitPhotos(history)
        let counts = draft.persisted && !sameWeekBytes
        let capturedAt = draft.capturedAt
        let corrected = draft.dateWasCorrected || (
            capturedAt.map { !calendar.isDate($0, inSameDayAs: draft.effectiveAt) } ?? false
        )
        let provenance = WeeklyPhotoProvenance(
            submissionId: draft.submissionId,
            originalSHA256: digest,
            originalByteCount: draft.originalBytes.count,
            contentType: contentType,
            capturedAt: capturedAt,
            timeZoneIdentifier: draft.timeZone.identifier,
            effectiveAt: draft.effectiveAt,
            dateWasCorrected: corrected,
            importedAt: draft.importedAt,
            exifOrientation: draft.exifOrientation,
            mirror: draft.mirror,
            viewpoint: draft.viewpoint,
            importSource: draft.importSource,
            isBackfill: false,
            isDuplicate: sameWeekBytes,
            fitSupportsGeometry: draft.fitSupportsGeometry,
            isPartialOrOccluded: draft.isPartialOrOccluded,
            countsTowardHabit: counts,
            localFileName: draft.localFileName
        )
        guard draft.persisted else {
            return Attempt(outcome: nil, metrics: [failureMetric(source: draft.importSource, outcome: "offline")])
        }
        let comparable = !sameWeekBytes && history.contains { prior in
            prior.submissionId != provenance.submissionId && !prior.isDuplicate &&
                viewpointsMatch(prior.viewpoint, provenance.viewpoint)
        }
        let outcome = WeeklyPhotoSaveOutcome(
            durable: true,
            selectedMoment: provenance.effectiveAt,
            offersComparison: comparable,
            originalImageUsable: true,
            waitsForReconstruction: false,
            provenance: provenance
        )
        var metrics = [savedMetric(provenance, source: draft.importSource, history: history, uploaded: draft.uploaded)]
        if counts && priorHabit.isEmpty {
            metrics.append(WeeklyPhotoHabitMetric(
                event: firstUsable,
                properties: ["elapsed_bucket": elapsedBucket(elapsed)],
                countsTowardHabit: true,
                denominator: "time_to_first_usable"
            ))
        }
        if counts && priorHabit.count == 1 {
            metrics.append(WeeklyPhotoHabitMetric(
                event: secondReturn,
                properties: ["history": "one"],
                countsTowardHabit: true,
                denominator: "second_photo_return"
            ))
        }
        if counts && priorHabit.contains(where: { weekKey(for: $0.effectiveAt, calendar: calendar) != week }) {
            metrics.append(WeeklyPhotoHabitMetric(
                event: weekRetained,
                properties: ["habit": "true"],
                countsTowardHabit: true,
                denominator: "weekly_retention"
            ))
        }
        return Attempt(outcome: outcome, metrics: metrics)
    }

    private static func savedMetric(
        _ provenance: WeeklyPhotoProvenance,
        source: String,
        history: [WeeklyPhotoProvenance],
        uploaded: Bool
    ) -> WeeklyPhotoHabitMetric {
        WeeklyPhotoHabitMetric(
            event: captureSaved,
            properties: [
                "source": source == "library" ? "library" : "camera",
                "history": historyBucket(habitPhotos(history).count),
                "delivery": uploaded ? "uploaded" : "local",
                "habit": provenance.countsTowardHabit ? "true" : "false"
            ],
            countsTowardHabit: provenance.countsTowardHabit,
            denominator: provenance.countsTowardHabit ? "capture_save_numerator" : "excluded_duplicate_or_backfill"
        )
    }
}

enum WeeklyPhotoOriginalStore {
    static func applicationDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("weekly-photo-originals", isDirectory: true)
    }

    static func retain(_ data: Data, submissionId: String, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let allowed = submissionId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let name = allowed.isEmpty ? "photo" : allowed
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func encodedJPEG(_ image: UIImage) -> Data? {
        image.jpegData(compressionQuality: 0.95)
    }

    /// Library bytes stay intact, including HEIC. A camera frame is encoded here,
    /// off any SwiftUI view, because the camera only hands back a bitmap.
    static func originalBytes(library: Data?, image: UIImage) -> Data? {
        if let library, !library.isEmpty { return library }
        return encodedJPEG(image)
    }
}

enum WeeklyPhotoPrepareResult: Sendable {
    case ready(WeeklyPhotoAttachPreparation)
    case empty
    case unavailable
}

struct WeeklyPhotoAttachPreparation: Sendable {
    var bytes: Data
    var fileURL: URL
    var orientation: Int

    /// Retains original bytes before any upload. Empty bytes are not a photo.
    /// A store failure keeps the attempt retryable without dropping the bytes.
    static func make(library: Data?, image: UIImage, submissionId: String) -> WeeklyPhotoPrepareResult {
        guard let bytes = WeeklyPhotoOriginalStore.originalBytes(library: library, image: image),
              !bytes.isEmpty else {
            return .empty
        }
        let orientation = PhotoMetadataService.shared.weeklyPhotoFacts(from: bytes).exifOrientation
        do {
            let url = try WeeklyPhotoOriginalStore.retain(
                bytes,
                submissionId: submissionId,
                directory: WeeklyPhotoOriginalStore.applicationDirectory()
            )
            return .ready(WeeklyPhotoAttachPreparation(bytes: bytes, fileURL: url, orientation: orientation))
        } catch {
            return .unavailable
        }
    }
}

enum WeeklyPhotoCheckInTelemetry {
    static func emit(
        _ metrics: [WeeklyPhotoHabitMetric],
        tracker: AnalyticsTracking = AppServicePorts.analyticsTracker
    ) {
        for metric in metrics where metric.countsTowardHabit || metric.event == WeeklyPhotoCheckInPolicy.captureSaved ||
            metric.event == WeeklyPhotoCheckInPolicy.captureFailed {
            tracker.track(event: metric.event, properties: metric.properties)
        }
    }
}
