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
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        let store = CoreDataManager(persistentStoreDescriptions: [description])
        let owner = "synthetic-selfie-owner"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try XCTUnwrap(SyntheticImage.mirrorSelfie().pngData())
        let firstDate = Date(timeIntervalSince1970: 1_790_000_000)
        let dates = [firstDate, try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: firstDate))]
        var observationIDs = Set<String>()

        for (index, date) in dates.enumerated() {
            let sourceURL = directory.appendingPathComponent("mirror-\(index).png")
            try bytes.write(to: sourceURL)
            let result = try await store.createOrUpdatePhotoUploadMetricsPlaceholder(for: date, userId: owner)
            XCTAssertTrue(result.createdNewEntry)
            let saved = try await store.updateBodyMetricPhoto(
                id: result.metrics.id, userId: owner,
                storagePath: sourceURL.absoluteString, processedUrl: sourceURL.absoluteString
            )
            XCTAssertTrue(saved)
            // Refetch committed state rather than accepting the write's return value.
            store.viewContext.reset()
            let rows = await store.fetchBodyMetrics(for: owner, localDate: BodyMetricLocalDate.key(for: date))
            XCTAssertEqual(rows.count, 1)
            let row = try XCTUnwrap(rows.first)
            let observation = try XCTUnwrap(row.toBodyMetrics())
            observationIDs.insert(observation.id)
            XCTAssertEqual(observation.localDate, BodyMetricLocalDate.key(for: date))
            XCTAssertEqual(observation.metricSource, .photo)
            XCTAssertNil(observation.weight)
            XCTAssertNil(observation.bodyFatPercentage)
            XCTAssertNil(observation.bodyFatMethod)
            XCTAssertNil(observation.muscleMass)
            XCTAssertNil(observation.boneMass)
            XCTAssertEqual(observation.photoUrl, sourceURL.absoluteString)
            let originalURL = try XCTUnwrap(URL(string: XCTUnwrap(row.originalPhotoUrl)))
            XCTAssertEqual(try Data(contentsOf: originalURL), bytes)
            XCTAssertNotNil(UIImage(contentsOfFile: originalURL.path))
        }
        XCTAssertEqual(observationIDs.count, 2, "Each week's selfie must remain its own dated observation")
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
