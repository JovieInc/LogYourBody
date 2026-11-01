//
// WeeklyPhotoCheckInPolicyTests.swift
// LogYourBodyTests
//
import XCTest
import CoreData
@testable import LogYourBody

final class WeeklyPhotoCheckInPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }

    func testOneSelfieIsEnoughAndNeverBlocksOnFit() {
        let saved = WeeklyPhotoCheckInPolicy.resolve(
            draft(bytes: Data([0xFF, 0xD8, 0xFF, 0x10]), viewpoint: "front"),
            history: [],
            calendar: calendar
        )
        let outcome = saved.outcome
        XCTAssertEqual(outcome?.durable, true)
        XCTAssertEqual(outcome?.originalImageUsable, true)
        XCTAssertEqual(outcome?.waitsForReconstruction, false)
        XCTAssertEqual(outcome?.offersComparison, false)
        XCTAssertEqual(outcome?.provenance.countsTowardHabit, true)
        XCTAssertEqual(outcome?.provenance.fitSupportsGeometry, false)
        XCTAssertEqual(outcome?.provenance.contentType, "jpeg")
        XCTAssertFalse(WeeklyPhotoCheckInPolicy.guidance(hasPreviousPhoto: true, guideEnabled: true).blocksSave)
        XCTAssertFalse(WeeklyPhotoCheckInPolicy.guidance(hasPreviousPhoto: false, guideEnabled: false).blocksSave)

        var partial = draft(bytes: Data([0xFF, 0xD8, 0xFF, 0x11]), viewpoint: "front")
        partial.isPartialOrOccluded = true
        partial.fitSupportsGeometry = false
        XCTAssertEqual(
            WeeklyPhotoCheckInPolicy.resolve(partial, history: [], calendar: calendar).outcome?.durable,
            true
        )
    }

    func testPromptIsContextualDismissibleAndSuppressedByCurrentEvidence() {
        let now = date(2_026, 11, 4)
        let open = WeeklyPhotoCheckInPolicy.prompt(
            metrics: [], now: now, dismissedWeekKey: nil, calendar: calendar, enabled: true
        )
        XCTAssertEqual(open?.title, "Add this week’s photo")
        XCTAssertEqual(open?.message, "One mirror selfie is enough.")
        XCTAssertEqual(open?.actionTitle, "Add photo")
        XCTAssertNil(WeeklyPhotoCheckInPolicy.prompt(
            metrics: [], now: now, dismissedWeekKey: open?.weekKey, calendar: calendar
        ))
        XCTAssertNil(WeeklyPhotoCheckInPolicy.prompt(
            metrics: [], now: now, dismissedWeekKey: nil, calendar: calendar, enabled: false
        ))
        let thisWeek = metric(date: now, photoUrl: "synthetic://this-week")
        XCTAssertNil(WeeklyPhotoCheckInPolicy.prompt(
            metrics: [thisWeek], now: now, dismissedWeekKey: nil, calendar: calendar
        ))
        let older = metric(date: date(2_026, 10, 20), photoUrl: "synthetic://older")
        XCTAssertNotNil(WeeklyPhotoCheckInPolicy.prompt(
            metrics: [older], now: now, dismissedWeekKey: nil, calendar: calendar
        ))
    }

    func testLimitedAccessSavesAndDeniedLibraryDoesNot() throws {
        var limited = draft(bytes: Data([0xFF, 0xD8, 0xFF, 0x12]))
        limited.libraryAccess = .limited
        limited.importSource = "library"
        XCTAssertEqual(
            WeeklyPhotoCheckInPolicy.resolve(limited, history: [], calendar: calendar).outcome?.durable,
            true
        )

        var denied = limited
        denied.libraryAccess = .denied
        let blocked = WeeklyPhotoCheckInPolicy.resolve(denied, history: [], calendar: calendar)
        XCTAssertNil(blocked.outcome)
        XCTAssertEqual(blocked.metrics.first?.properties["outcome"], "permission_denied")
        XCTAssertEqual(blocked.metrics.first?.countsTowardHabit, true)

        var heic = Data(count: 16)
        heic.replaceSubrange(4..<12, with: Data("ftypheic".utf8))
        XCTAssertEqual(WeeklyPhotoCheckInPolicy.contentType(for: heic), "heic")
        var heicDraft = draft(bytes: heic)
        heicDraft.importSource = "library"
        heicDraft.libraryAccess = .limited
        let saved = try XCTUnwrap(
            WeeklyPhotoCheckInPolicy.resolve(heicDraft, history: [], calendar: calendar).outcome
        )
        XCTAssertEqual(saved.provenance.contentType, "heic")
        XCTAssertEqual(saved.provenance.capturedAt, nil)
    }

    func testInterruptionsAreOutsideTheHabitRateAndOfflineIsInside() {
        let cancelled = WeeklyPhotoCheckInPolicy.failureMetric(source: "camera", outcome: "cancelled")
        let interrupted = WeeklyPhotoCheckInPolicy.failureMetric(source: "camera", outcome: "interrupted")
        XCTAssertFalse(cancelled.countsTowardHabit)
        XCTAssertFalse(interrupted.countsTowardHabit)
        XCTAssertEqual(cancelled.denominator, "abandoned")
        XCTAssertEqual(
            WeeklyPhotoCheckInPolicy.failureMetric(source: "library", outcome: "offline").countsTowardHabit,
            true
        )
        XCTAssertTrue(WeeklyPhotoCheckInPolicy.retainsLocally(.notConnectedToInternet))
        XCTAssertTrue(WeeklyPhotoCheckInPolicy.isRetainedOffline(URLError(.timedOut)))
        XCTAssertTrue(WeeklyPhotoCheckInPolicy.isRetainedOffline(PhotoUploadManager.PhotoError.networkError))
        XCTAssertFalse(WeeklyPhotoCheckInPolicy.retainsLocally(.cancelled))
        XCTAssertFalse(WeeklyPhotoCheckInPolicy.isRetainedOffline(URLError(.cancelled)))

        var unsaved = draft(bytes: Data([0xFF, 0xD8, 0xFF, 0x13]))
        unsaved.persisted = false
        let offline = WeeklyPhotoCheckInPolicy.resolve(unsaved, history: [], calendar: calendar)
        XCTAssertNil(offline.outcome)
        XCTAssertEqual(offline.metrics.first?.properties["outcome"], "offline")

        let empty = WeeklyPhotoCheckInPolicy.resolve(
            draft(bytes: Data()), history: [], calendar: calendar
        )
        XCTAssertNil(empty.outcome)
        XCTAssertEqual(empty.metrics.first?.properties["outcome"], "empty")
    }

    func testDuplicatesDoNotCountTwiceAndBackfillStillOffersCompare() throws {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0x21])
        let first = try XCTUnwrap(
            WeeklyPhotoCheckInPolicy.resolve(draft(bytes: bytes, submission: "sub-1"), history: [], calendar: calendar).outcome
        )
        let replay = WeeklyPhotoCheckInPolicy.resolve(
            draft(bytes: bytes, submission: "sub-1"),
            history: [first.provenance],
            calendar: calendar
        )
        XCTAssertEqual(replay.outcome?.durable, true)
        XCTAssertEqual(replay.outcome?.offersComparison, false)
        XCTAssertEqual(replay.outcome?.provenance.countsTowardHabit, false)
        XCTAssertFalse(replay.metrics.contains { $0.event == WeeklyPhotoCheckInPolicy.secondReturn })

        var second = draft(bytes: bytes, submission: "sub-2")
        let duplicateBytes = try XCTUnwrap(
            WeeklyPhotoCheckInPolicy.resolve(second, history: [first.provenance], calendar: calendar).outcome
        )
        XCTAssertTrue(duplicateBytes.provenance.isDuplicate)
        XCTAssertFalse(duplicateBytes.provenance.countsTowardHabit)
        XCTAssertFalse(duplicateBytes.offersComparison)

        let backfill = try XCTUnwrap(WeeklyPhotoCheckInPolicy.backfill(metric: metric(
            date: date(2_026, 10, 12), photoUrl: "synthetic://backfill"
        )))
        XCTAssertTrue(backfill.isBackfill)
        XCTAssertFalse(backfill.countsTowardHabit)
        XCTAssertNil(backfill.capturedAt)
        var fresh = draft(bytes: Data([0xFF, 0xD8, 0xFF, 0x22]), submission: "sub-3", viewpoint: "front")
        fresh.effectiveAt = date(2_026, 11, 4)
        let compared = try XCTUnwrap(
            WeeklyPhotoCheckInPolicy.resolve(fresh, history: [backfill], calendar: calendar).outcome
        )
        XCTAssertTrue(compared.offersComparison)
        XCTAssertTrue(compared.provenance.countsTowardHabit)
        XCTAssertFalse(compared.provenance.isBackfill)
        let events = WeeklyPhotoCheckInPolicy.resolve(fresh, history: [backfill], calendar: calendar).metrics
        XCTAssertTrue(events.contains { $0.event == WeeklyPhotoCheckInPolicy.firstUsable })
        XCTAssertFalse(events.contains { $0.event == WeeklyPhotoCheckInPolicy.weekRetained })
        XCTAssertFalse(events.contains { $0.event == WeeklyPhotoCheckInPolicy.secondReturn })
    }

    func testSecondPhotoReturnAndWeeklyRetentionUseHabitPhotosOnly() throws {
        let earlier = provenance(effectiveAt: date(2_026, 10, 12), viewpoint: "front")
        let current = draft(bytes: Data([0xFF, 0xD8, 0xFF, 0x31]), submission: "return")
        var returning = current
        returning.effectiveAt = date(2_026, 11, 4)
        let attempt = WeeklyPhotoCheckInPolicy.resolve(returning, history: [earlier], calendar: calendar)
        XCTAssertTrue(attempt.metrics.contains { $0.event == WeeklyPhotoCheckInPolicy.secondReturn })
        XCTAssertTrue(attempt.metrics.contains { $0.event == WeeklyPhotoCheckInPolicy.weekRetained })
        XCTAssertEqual(attempt.outcome?.offersComparison, true)
        XCTAssertEqual(attempt.metrics.first { $0.event == WeeklyPhotoCheckInPolicy.captureSaved }?.properties["history"], "one")

        let side = provenance(effectiveAt: date(2_026, 10, 5), viewpoint: "side")
        var front = returning
        front.viewpoint = "front"
        front.submissionId = "front-after-side"
        XCTAssertEqual(
            WeeklyPhotoCheckInPolicy.resolve(front, history: [side], calendar: calendar).outcome?.offersComparison,
            false
        )
        XCTAssertEqual(WeeklyPhotoCheckInPolicy.historyBucket(0), "zero")
        XCTAssertEqual(WeeklyPhotoCheckInPolicy.historyBucket(1), "one")
        XCTAssertEqual(WeeklyPhotoCheckInPolicy.historyBucket(2), "two_or_more")
        XCTAssertEqual(WeeklyPhotoCheckInPolicy.elapsedBucket(1), "under_2s")
        XCTAssertEqual(WeeklyPhotoCheckInPolicy.elapsedBucket(9), "under_10s")
        XCTAssertEqual(WeeklyPhotoCheckInPolicy.elapsedBucket(30), "under_60s")
        XCTAssertEqual(WeeklyPhotoCheckInPolicy.elapsedBucket(90), "over_60s")
    }

    func testDateCorrectionPreservesCaptureAndNeverCopiesImportTime() throws {
        let captured = date(2_026, 11, 2)
        let effective = date(2_026, 11, 4)
        let imported = date(2_026, 11, 6)
        var corrected = draft(bytes: Data([0xFF, 0xD8, 0xFF, 0x41]), submission: "dated")
        corrected.capturedAt = captured
        corrected.effectiveAt = effective
        corrected.importedAt = imported
        corrected.dateWasCorrected = true
        corrected.localFileName = "/private/device/original-abc.jpg"
        let outcome = try XCTUnwrap(
            WeeklyPhotoCheckInPolicy.resolve(corrected, history: [], calendar: calendar).outcome
        )
        XCTAssertEqual(outcome.provenance.capturedAt, captured)
        XCTAssertEqual(outcome.provenance.effectiveAt, effective)
        XCTAssertEqual(outcome.provenance.importedAt, imported)
        XCTAssertTrue(outcome.provenance.dateWasCorrected)
        XCTAssertNotEqual(outcome.provenance.capturedAt, outcome.provenance.importedAt)
        XCTAssertEqual(outcome.provenance.localFileName, "original-abc.jpg")
        XCTAssertFalse(outcome.provenance.storageFields.values.contains { $0.contains("/") })
        XCTAssertNotNil(outcome.provenance.storageFields["captured_at"])
        let stored = try XCTUnwrap(WeeklyPhotoProvenance(storage: outcome.provenance.storageFields))
        XCTAssertEqual(stored.capturedAt, outcome.provenance.capturedAt)
        XCTAssertEqual(stored.importedAt, imported)
        XCTAssertNil(WeeklyPhotoProvenance(
            submissionId: "missing-capture",
            originalSHA256: "",
            originalByteCount: 1,
            contentType: "jpeg",
            capturedAt: nil,
            timeZoneIdentifier: "UTC",
            effectiveAt: effective,
            dateWasCorrected: false,
            importedAt: imported,
            exifOrientation: 1,
            mirror: "unknown",
            viewpoint: "unspecified",
            importSource: "library",
            isBackfill: false,
            isDuplicate: false,
            fitSupportsGeometry: false,
            isPartialOrOccluded: false,
            countsTowardHabit: true
        ).storageFields["captured_at"])
    }

    func testAnalyticsKeepsHabitEnumsAndDropsPrivateValues() {
        XCTAssertFalse(AnalyticsEventPolicy.legacyEventNames.contains(WeeklyPhotoCheckInPolicy.captureSaved))
        XCTAssertFalse(AnalyticsEventPolicy.legacyEventNames.contains(WeeklyPhotoCheckInPolicy.captureStarted))
        let payload = AnalyticsEventPolicy.payload(
            event: WeeklyPhotoCheckInPolicy.captureSaved,
            properties: [
                "source": "camera",
                "history": "zero",
                "delivery": "local",
                "habit": "true",
                "weight": "80",
                "captured_at": "2_026-11-04T00:00:00Z",
                "photo_url": "file:///private/photo.jpg"
            ]
        )
        XCTAssertEqual(payload?.properties?["source"], "camera")
        XCTAssertEqual(payload?.properties?["delivery"], "local")
        XCTAssertNil(payload?.properties?["weight"])
        XCTAssertNil(payload?.properties?["captured_at"])
        XCTAssertNil(payload?.properties?["photo_url"])
        let started = WeeklyPhotoCheckInPolicy.captureStartedMetric(
            source: "library", access: "limited", history: []
        )
        XCTAssertEqual(started.properties["history"], "zero")
        XCTAssertEqual(started.properties["access"], "limited")
        XCTAssertEqual(started.denominator, "capture_save_rate")
        XCTAssertEqual(WeeklyPhotoCheckInPolicy.denominators["weekly_retention"]?.isEmpty, false)
    }

    @MainActor
    func testBackfillDoesNotTreatImportTimeAsCaptureTime() async throws {
        let store = makeStore()
        let owner = "weekly-backfill-owner"
        let effective = date(2_026, 10, 12)
        let imported = date(2_026, 11, 1)
        let row = metric(
            userId: owner,
            date: effective,
            photoUrl: "https://example.com/synthetic-weekly.jpg",
            source: BodyMetricSourceMetadata(importedAt: WeeklyPhotoTime.string(from: imported))
        )
        try await store.saveBodyMetricsAndWait(row, userId: owner, markAsSynced: true)
        let changed = await PhotoMetadataService.shared.backfillWeeklyPhotoProvenance(
            userId: owner, coreDataManager: store
        )
        XCTAssertEqual(changed, 1)
        store.viewContext.reset()
        let saved = try XCTUnwrap(await store.fetchBodyMetrics(for: owner, localDate: row.localDate).first)
        let provenance = try XCTUnwrap(saved.toBodyMetrics()?.sourceMetadata?.weeklyPhotoProvenance)
        XCTAssertNil(provenance.capturedAt)
        XCTAssertEqual(provenance.importedAt, imported)
        XCTAssertTrue(provenance.isBackfill)
        XCTAssertFalse(provenance.countsTowardHabit)
        XCTAssertEqual(provenance.viewpoint, "unspecified")
        XCTAssertFalse(saved.sourceMetadataJSON?.contains("captured_at") ?? true)
        let again = await PhotoMetadataService.shared.backfillWeeklyPhotoProvenance(
            userId: owner, coreDataManager: store
        )
        XCTAssertEqual(again, 0)
    }

    @MainActor
    func testCommittedCheckInRoundTripsProvenanceWithoutPublishingAFileURL() async throws {
        let store = makeStore()
        let owner = "weekly-commit-owner"
        let captured = date(2_026, 11, 2)
        let effective = date(2_026, 11, 4)
        let imported = date(2_026, 11, 6)
        let created = try await store.createOrUpdatePhotoUploadMetricsPlaceholder(
            for: effective, userId: owner
        )
        let provenance = WeeklyPhotoProvenance(
            submissionId: "commit-1",
            originalSHA256: "abc123",
            originalByteCount: 4,
            contentType: "jpeg",
            capturedAt: captured,
            timeZoneIdentifier: "UTC",
            effectiveAt: effective,
            dateWasCorrected: true,
            importedAt: imported,
            exifOrientation: 6,
            mirror: "mirrored",
            viewpoint: "front",
            importSource: "library",
            isBackfill: false,
            isDuplicate: false,
            fitSupportsGeometry: false,
            isPartialOrOccluded: true,
            countsTowardHabit: true,
            localFileName: "commit-1.jpg"
        )
        let localURL = "file:///tmp/commit-1.jpg"
        let linked = try await PhotoMetadataService.shared.commitWeeklyPhoto(
            id: created.metrics.id,
            userId: owner,
            provenance: provenance,
            localDisplayURL: localURL,
            coreDataManager: store
        )
        XCTAssertTrue(linked)
        store.viewContext.reset()
        let row = try XCTUnwrap(
            await store.fetchBodyMetrics(for: owner, localDate: BodyMetricLocalDate.key(for: effective)).first
        )
        XCTAssertEqual(row.photoUrl, localURL)
        XCTAssertEqual(row.syncStatus, "local_weekly_photo")
        XCTAssertTrue(row.isSynced)
        let stored = try XCTUnwrap(row.toBodyMetrics()?.sourceMetadata?.weeklyPhotoProvenance)
        XCTAssertEqual(stored.capturedAt, captured)
        XCTAssertEqual(stored.importedAt, imported)
        XCTAssertNotEqual(stored.capturedAt, stored.importedAt)
        XCTAssertEqual(stored.localFileName, "commit-1.jpg")
        XCTAssertEqual(stored.mirror, "mirrored")
        XCTAssertEqual(stored.exifOrientation, 6)
        XCTAssertTrue(stored.isPartialOrOccluded)
        XCTAssertFalse(row.sourceMetadataJSON?.contains(localURL) ?? true)
    }

    private func makeStore() -> CoreDataManager {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        return CoreDataManager(persistentStoreDescriptions: [description])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    private func metric(
        userId: String = "weekly-photo-owner",
        date: Date,
        photoUrl: String?,
        source: BodyMetricSourceMetadata? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: nil,
            weightUnit: nil,
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoUrl,
            dataSource: photoUrl == nil ? "manual" : BodyMetricSource.photo.rawValue,
            sourceMetadata: source,
            createdAt: date,
            updatedAt: date
        )
    }

    private func draft(
        bytes: Data,
        submission: String = "submission",
        viewpoint: String = "unspecified"
    ) -> WeeklyPhotoDraft {
        WeeklyPhotoDraft(
            submissionId: submission,
            originalBytes: bytes,
            contentType: "unknown",
            capturedAt: nil,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt,
            effectiveAt: date(2_026, 11, 4),
            dateWasCorrected: false,
            importedAt: date(2_026, 11, 4),
            exifOrientation: 1,
            mirror: "unknown",
            viewpoint: viewpoint,
            importSource: "camera",
            fitSupportsGeometry: false,
            isPartialOrOccluded: false,
            libraryAccess: .authorized,
            persisted: true,
            uploaded: true,
            localFileName: nil
        )
    }

    private func provenance(effectiveAt: Date, viewpoint: String) -> WeeklyPhotoProvenance {
        WeeklyPhotoProvenance(
            submissionId: UUID().uuidString,
            originalSHA256: UUID().uuidString,
            originalByteCount: 8,
            contentType: "jpeg",
            capturedAt: effectiveAt,
            timeZoneIdentifier: "UTC",
            effectiveAt: effectiveAt,
            dateWasCorrected: false,
            importedAt: effectiveAt,
            exifOrientation: 1,
            mirror: "mirrored",
            viewpoint: viewpoint,
            importSource: "camera",
            isBackfill: false,
            isDuplicate: false,
            fitSupportsGeometry: false,
            isPartialOrOccluded: false,
            countsTowardHabit: true
        )
    }
}
