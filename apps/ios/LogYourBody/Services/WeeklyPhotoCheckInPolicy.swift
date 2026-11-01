//
// WeeklyPhotoCheckInPolicy.swift
// LogYourBody
//
import CryptoKit
import Foundation

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
