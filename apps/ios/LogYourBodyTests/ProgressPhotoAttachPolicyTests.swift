//
// CoreDataAndPhotoPolicyTests.swift
// LogYourBodyTests
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody


final class ProgressPhotoAttachPolicyTests: XCTestCase {
    @MainActor
    func testWeeklyMirrorSelfiesPersistWithoutSideCaptureOrMeasurements() async throws {
        let store = makeObservationStore()
        let owner = "synthetic-selfie-owner"
        let directory = try observationDirectory()
        let bytes = try XCTUnwrap(SyntheticImage.mirrorSelfie().pngData())
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let saved = try await saveSelfie(bytes, date: date, owner: owner, directory: directory, store: store)

        // Refetch committed state rather than accepting the write's return value.
        store.viewContext.reset()
        let rows = await store.fetchBodyMetrics(for: owner, localDate: BodyMetricLocalDate.key(for: date))
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        let observation = try XCTUnwrap(row.toBodyMetrics())
        XCTAssertEqual(observation.id, saved.id)
        XCTAssertEqual(observation.date, date)
        XCTAssertEqual(observation.localDate, BodyMetricLocalDate.key(for: date))
        XCTAssertEqual(observation.metricSource, .photo)
        XCTAssertNil(observation.weight)
        XCTAssertNil(observation.weightUnit)
        XCTAssertNil(observation.bodyFatPercentage)
        XCTAssertNil(observation.bodyFatMethod)
        XCTAssertNil(observation.muscleMass)
        XCTAssertNil(observation.boneMass)
        XCTAssertNil(observation.waistCm)
        XCTAssertNil(observation.hipCm)
        let originalURL = try XCTUnwrap(URL(string: XCTUnwrap(row.originalPhotoUrl)))
        XCTAssertEqual(observation.photoUrl, originalURL.absoluteString)
        XCTAssertEqual(try Data(contentsOf: originalURL), bytes)
        XCTAssertNotNil(UIImage(contentsOfFile: originalURL.path))
        let provenance = try XCTUnwrap(observation.sourceMetadata?.weeklyPhotoProvenance)
        XCTAssertEqual(provenance.originalSHA256, WeeklyPhotoCheckInPolicy.sha256Hex(bytes))
        XCTAssertEqual(provenance.originalByteCount, bytes.count)
        XCTAssertEqual(provenance.viewpoint, "front")
        XCTAssertEqual(provenance.mirror, "mirrored")
        XCTAssertFalse(provenance.fitSupportsGeometry)
        XCTAssertEqual(row.syncStatus, "local_weekly_photo")
        XCTAssertTrue(row.isSynced, "A local file URL must stay out of remote metric sync")
    }

    @MainActor
    func testSecondWeeklyCheckInSavesWhileEarlierPhotoIsCurrentWithoutPromptOrTutorial() async throws {
        let store = makeObservationStore()
        let directory = try observationDirectory()
        let owner = "returning-selfie-owner"
        let bytes = try XCTUnwrap(SyntheticImage.mirrorSelfie().pngData())
        let firstDate = Date(timeIntervalSince1970: 1_790_000_000)
        let nextWeek = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: firstDate))
        let current = try await saveSelfie(bytes, date: firstDate, owner: owner, directory: directory, store: store)
        XCTAssertTrue(PhotoTimelineHUDPolicy.hasUsablePhoto(current))
        XCTAssertNil(WeeklyPhotoCheckInPolicy.prompt(
            metrics: [current], now: nextWeek, dismissedWeekKey: nil, enabled: false
        ))
        XCTAssertFalse(WeeklyPhotoCheckInPolicy.guidance(hasPreviousPhoto: true, guideEnabled: false).blocksSave)

        // No tutorial acknowledgement or prompt flag is part of the save contract.
        let second = try await saveSelfie(
            bytes, date: nextWeek, owner: owner, directory: directory, store: store,
            history: WeeklyPhotoCheckInPolicy.history(from: [current])
        )
        XCTAssertNotEqual(second.id, current.id)
        store.viewContext.reset()
        for (date, expectedID) in [(firstDate, current.id), (nextWeek, second.id)] {
            let rows = await store.fetchBodyMetrics(for: owner, localDate: BodyMetricLocalDate.key(for: date))
            XCTAssertEqual(rows.count, 1)
            let observation = try XCTUnwrap(rows.first?.toBodyMetrics())
            XCTAssertEqual(observation.id, expectedID)
            XCTAssertEqual(observation.date, date)
            let url = try XCTUnwrap(URL(string: XCTUnwrap(observation.photoUrl)))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        XCTAssertTrue(second.sourceMetadata?.weeklyPhotoProvenance?.countsTowardHabit ?? false)
    }

    @MainActor
    func testSameDaySelfiesAreIndependentAndRetryKeepsObservationIdentity() async throws {
        let store = makeObservationStore()
        let directory = try observationDirectory()
        let owner = "same-day-selfie-owner"
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let bytes = try XCTUnwrap(SyntheticImage.mirrorSelfie().pngData())
        let first = try await saveSelfie(bytes, date: date, owner: owner, directory: directory, store: store)
        let second = try await saveSelfie(bytes, date: date, owner: owner, directory: directory, store: store)
        let replay = try await PhotoMetadataService.shared.createWeeklyPhotoObservation(
            userId: owner, provenance: XCTUnwrap(first.sourceMetadata?.weeklyPhotoProvenance),
            originalURL: XCTUnwrap(URL(string: XCTUnwrap(first.photoUrl))), coreDataManager: store
        )
        XCTAssertEqual(replay.id, first.id)
        XCTAssertNotEqual(second.id, first.id)
        store.viewContext.reset()
        let rows = await store.fetchBodyMetrics(for: owner, localDate: BodyMetricLocalDate.key(for: date))
        XCTAssertEqual(Set(rows.compactMap(\.id)), [first.id, second.id])
    }

    @MainActor
    func testRevokedSessionDoesNotCreatePhotoObservation() async throws {
        let store = makeObservationStore()
        let directory = try observationDirectory()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let bytes = try XCTUnwrap(SyntheticImage.mirrorSelfie().pngData())
        let provenance = try selfieProvenance(bytes, date: date)
        do {
            _ = try await PhotoMetadataService.shared.createWeeklyPhotoObservation(
                userId: "revoked-owner", provenance: provenance,
                originalURL: directory.appendingPathComponent(provenance.submissionId), coreDataManager: store,
                writeAdmission: { throw PhotoUploadManager.PhotoError.notAuthenticated }
            )
            XCTFail("A revoked account session must reject the save")
        } catch PhotoUploadManager.PhotoError.notAuthenticated {
            let rows = await store.fetchBodyMetrics(for: "revoked-owner")
            XCTAssertTrue(rows.isEmpty)
        }
    }

    private func makeObservationStore() -> CoreDataManager {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        return CoreDataManager(persistentStoreDescriptions: [description])
    }

    private func observationDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func selfieProvenance(
        _ bytes: Data, date: Date, history: [WeeklyPhotoProvenance] = []
    ) throws -> WeeklyPhotoProvenance {
        let draft = WeeklyPhotoDraft(
            submissionId: UUID().uuidString, originalBytes: bytes, contentType: "png", capturedAt: date,
            timeZone: .current, effectiveAt: date, dateWasCorrected: false, importedAt: nil,
            exifOrientation: 1, mirror: "mirrored", viewpoint: "front", importSource: "camera",
            fitSupportsGeometry: false, isPartialOrOccluded: false, libraryAccess: .notDetermined,
            persisted: true, uploaded: false, localFileName: nil
        )
        return try XCTUnwrap(WeeklyPhotoCheckInPolicy.resolve(draft, history: history).outcome?.provenance)
    }

    private func saveSelfie(
        _ bytes: Data, date: Date, owner: String, directory: URL, store: CoreDataManager,
        history: [WeeklyPhotoProvenance] = []
    ) async throws -> BodyMetrics {
        var provenance = try selfieProvenance(bytes, date: date, history: history)
        let originalURL = try WeeklyPhotoOriginalStore.retain(
            bytes, submissionId: provenance.submissionId, directory: directory
        )
        provenance.localFileName = originalURL.lastPathComponent
        return try await PhotoMetadataService.shared.createWeeklyPhotoObservation(
            userId: owner, provenance: provenance, originalURL: originalURL, coreDataManager: store
        )
    }

    func testProgressPhotoAttachStateCopyCoversCoreStates() {
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .empty), "Choose a photo")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .ready), "Ready to attach")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .processing), "Processing photo")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .success), "Photo added")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .permissionDenied), "Permission needed")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .failed("Upload failed")), "Photo failed")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusMessage(for: .failed("Upload failed")), "Upload failed")
    }

    func testProgressPhotoAttachTargetCopyDistinguishesAttachAndCreate() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.targetCopy(
                hasTargetMetric: true,
                targetDate: date
            ).hasPrefix("Attaches to")
        )
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.targetCopy(
                hasTargetMetric: false,
                targetDate: date
            ).hasPrefix("Adds to")
        )
    }

    func testProgressPhotoAttachCameraPolicyRequiresAvailableAuthorizedCamera() {
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: true,
                authorizationStatus: .authorized
            )
        )
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: true,
                authorizationStatus: .notDetermined
            )
        )
        XCTAssertFalse(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: false,
                authorizationStatus: .authorized
            )
        )
        XCTAssertFalse(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: true,
                authorizationStatus: .denied
            )
        )
    }

    func testProgressPhotoAttachBusyStateOnlyComesFromLocalProcessingStatus() {
        XCTAssertTrue(ProgressPhotoAttachPolicy.isBusy(status: .processing))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .empty))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .ready))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .success))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .failed("Upload failed")))
    }

    func testProgressPhotoAttachSheetPresentationMatchesDismissRules() {
        XCTAssertEqual(
            ProgressPhotoAttachPolicy.canDismiss(status: .ready),
            NativeSheetPresentationPolicy.canDismissProgressPhotoAttach(status: .ready)
        )
        XCTAssertTrue(ProgressPhotoAttachPolicy.canDismiss(status: .empty))
        XCTAssertTrue(ProgressPhotoAttachPolicy.canDismiss(status: .ready))
        XCTAssertTrue(ProgressPhotoAttachPolicy.canDismiss(status: .success))
        XCTAssertFalse(ProgressPhotoAttachPolicy.canDismiss(status: .processing))
        XCTAssertEqual(
            NativeSheetPresentationPolicy.detents(for: .progressPhotoAttach),
            [.medium, .large]
        )
        XCTAssertEqual(
            NativeSheetPresentationPolicy.dragIndicator(for: .progressPhotoAttach),
            .visible
        )
        XCTAssertTrue(NativeSheetPresentationPolicy.presentsCameraAsFullScreenCover(.progressPhotoAttach))
        XCTAssertTrue(NativeSheetPresentationPolicy.presentsCameraAsFullScreenCover(.camera))
        XCTAssertFalse(NativeSheetPresentationPolicy.usesCustomGrabber(.progressPhotoAttach))
    }
}
