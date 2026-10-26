//
// HealthSyncPipelineTests.swift
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

// XCTestCase classes moved into one-class-per-file test sources.

@MainActor
final class HealthSyncPipelineAnchoredFetchTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var auth: AuthManager!
    private var coreData: CoreDataManager!
    private var weightQueries = 0

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "HealthSyncPipelineAnchoredFetchTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        auth = AuthManager(userDefaults: defaults, urlSession: URLSession(configuration: configuration))
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        coreData = CoreDataManager(persistentStoreDescriptions: [store])
        weightQueries = 0
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        auth = nil
        coreData = nil
        defaults = nil
        try await super.tearDown()
    }

    func testObserverFetchesOnlySamplesSinceTheStoredAnchor() async throws {
        let userId = "anchor-observer-\(UUID().uuidString)"
        let probe = AnchoredSampleFetchProbe()
        probe.page = HealthAnchoredSamplePage(added: [], deleted: [], newAnchor: Data([8]))
        let manager = try makeManager(userId: userId, probe: probe)
        let store = HealthAnchorStore(defaults: defaults)
        store.advance(Data([7]), for: .weight, userId: userId, commitSucceeded: true)
        store.advance(Data([7]), for: .bodyFat, userId: userId, commitSucceeded: true)

        manager.scheduleObservedBodyMetricSync(for: userId, debounce: 0.05)
        try await waitUntil(store.anchor(for: .bodyFat, userId: userId) == Data([8]))
        manager.syncDebounceTimer?.invalidate()

        let requestedAnchors = probe.recorded().map(\.1)
        XCTAssertEqual(requestedAnchors, [Data([7]), Data([7])])
        XCTAssertEqual(weightQueries, 0)
        XCTAssertEqual(store.anchor(for: .weight, userId: userId), Data([8]))
        XCTAssertEqual(store.anchor(for: .bodyFat, userId: userId), Data([8]))
    }

    func testAnchoredWeightSyncRecordsSuccessfulCompletion() async throws {
        let userId = "anchor-completion-\(UUID().uuidString)"
        let probe = AnchoredSampleFetchProbe()
        let manager = try makeManager(userId: userId, probe: probe)
        let store = HealthAnchorStore(defaults: defaults)
        store.advance(Data([7]), for: .weight, userId: userId, commitSucceeded: true)
        store.advance(Data([7]), for: .bodyFat, userId: userId, commitSucceeded: true)
        let initialSync = await manager.lastSuccessfulSync
        XCTAssertNil(initialSync)

        try await manager.syncWeightFromHealthKit()

        let completed = await manager.lastSuccessfulSync
        XCTAssertNotNil(completed)
        XCTAssertEqual(store.anchor(for: .weight, userId: userId), Data([9]))
        XCTAssertEqual(store.anchor(for: .bodyFat, userId: userId), Data([9]))
        XCTAssertEqual(weightQueries, 0)
    }

    func testFailedCommitDoesNotAdvanceTheStoredAnchor() async throws {
        let userId = "anchor-failed-\(UUID().uuidString)"
        let probe = AnchoredSampleFetchProbe()
        let sample = HealthAnchoredSample(
            id: "new-weight", kind: .weight, value: 70, date: Date(),
            sourceMetadata: BodyMetricSourceMetadata(
                vendor: "apple_health", sampleId: "new-weight",
                quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue
            )
        )
        probe.page = HealthAnchoredSamplePage(added: [sample], deleted: [], newAnchor: Data([9]))
        let manager = try makeManager(userId: userId, probe: probe, failCommit: true)
        let store = HealthAnchorStore(defaults: defaults)
        store.advance(Data([7]), for: .weight, userId: userId, commitSucceeded: true)
        store.advance(Data([7]), for: .bodyFat, userId: userId, commitSucceeded: true)
        let previousSync = Date(timeIntervalSince1970: 123)
        defaults.set(previousSync, forKey: HealthKitDefaultsKey.lastSuccessfulSync.scoped(with: userId))

        do {
            try await manager.syncWeightFromHealthKit()
            XCTFail("An anchored persistence failure must fail the sync")
        } catch HealthKitError.syncFailed {
            let afterFailure = await manager.lastSuccessfulSync
            XCTAssertEqual(afterFailure, previousSync)
        }

        XCTAssertFalse(probe.recorded().isEmpty)
        XCTAssertEqual(store.anchor(for: .weight, userId: userId), Data([7]))
        XCTAssertEqual(store.anchor(for: .bodyFat, userId: userId), Data([7]))
        let visible = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertTrue(visible.isEmpty)
    }

    func testFirstRunAndRepeatFullImportDoNotDuplicateRows() async throws {
        let userId = "anchor-first-\(UUID().uuidString)"
        let probe = AnchoredSampleFetchProbe()
        probe.page = HealthAnchoredSamplePage(added: [], deleted: [], newAnchor: Data([4]))
        let sampleDate = Date()
        let manager = try makeManager(
            userId: userId, probe: probe, weightSampleDate: sampleDate
        )

        let first = await manager.syncAllHistoricalHealthKitData()
        let second = await manager.syncAllHistoricalHealthKitData()

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        let rows = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.weight ?? 0, 70, accuracy: 0.001)
        let queriesAfterFullImport = weightQueries
        XCTAssertGreaterThan(queriesAfterFullImport, 0)
        try await manager.syncWeightFromHealthKit()
        XCTAssertEqual(weightQueries, queriesAfterFullImport)
        let rowsAfterIncrementalSync = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertEqual(rowsAfterIncrementalSync.count, 1)
        XCTAssertEqual(HealthAnchorStore(defaults: defaults).anchor(for: .weight, userId: userId), Data([4]))
    }

    func testAnchorResetFallsBackToTheFullImport() async throws {
        let userId = "anchor-reset-\(UUID().uuidString)"
        let probe = AnchoredSampleFetchProbe()
        probe.page = HealthAnchoredSamplePage(added: [], deleted: [], newAnchor: Data([5]))
        let manager = try makeManager(userId: userId, probe: probe, weightSampleDate: Date())
        let store = HealthAnchorStore(defaults: defaults)
        store.advance(Data([3]), for: .weight, userId: userId, commitSucceeded: true)
        store.advance(Data([3]), for: .bodyFat, userId: userId, commitSucceeded: true)
        store.advance(Data([3]), for: .steps, userId: userId, commitSucceeded: true)

        await manager.resetForCurrentUser()

        XCTAssertNil(store.anchor(for: .weight, userId: userId))
        XCTAssertNil(store.anchor(for: .bodyFat, userId: userId))
        XCTAssertNil(store.anchor(for: .steps, userId: userId))
        manager.isAuthorized = true
        defaults.set(true, forKey: HealthKitDefaultsKey.fullSyncCompleted.scoped(with: userId))
        try await manager.syncWeightFromHealthKit()

        XCTAssertGreaterThan(weightQueries, 0)
        XCTAssertFalse(probe.recorded().contains { $0.1 == Data([3]) })
        let rowsAfterReset = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertEqual(rowsAfterReset.count, 1)
    }

    func testDeletedHealthKitSampleMarksTheImportedRow() async throws {
        let userId = "anchor-delete-\(UUID().uuidString)"
        let manager = try makeManager(userId: userId, probe: AnchoredSampleFetchProbe())
        let date = Date()
        try await coreData.saveBodyMetricsAndWait(
            BodyMetrics(
                id: "imported-weight", userId: userId, date: date, weight: 70, weightUnit: "kg",
                bodyFatPercentage: nil, bodyFatMethod: nil, muscleMass: nil, boneMass: nil,
                notes: "Imported from HealthKit", photoUrl: nil,
                dataSource: BodyMetricSource.healthKit.rawValue,
                sourceMetadata: BodyMetricSourceMetadata(
                    vendor: "apple_health", sourceName: "Scale", sampleId: "weight-sample",
                    quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue
                ),
                createdAt: date, updatedAt: date
            ),
            userId: userId
        )
        let ownership = try XCTUnwrap(auth.captureAccountSession())

        let applied = try await manager.applyAnchoredBodyMetricDeletions(
            [HealthAnchoredDeletion(id: "weight-sample", kind: .weight, date: nil)],
            ownership: ownership
        )

        XCTAssertTrue(applied)
        let visible = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertTrue(visible.isEmpty)
        let flagged = try await deletionFlags(userId: userId)
        XCTAssertEqual(flagged, [true])
    }

    func testDeletedPairedSamplesTombstoneTheCombinedRow() async throws {
        let userId = "anchor-paired-\(UUID().uuidString)"
        let manager = try makeManager(userId: userId, probe: AnchoredSampleFetchProbe())
        let date = Date()
        try await coreData.saveBodyMetricsAndWait(
            BodyMetrics(
                id: "combined", userId: userId, date: date, weight: 71, weightUnit: "kg",
                bodyFatPercentage: 18, bodyFatMethod: "HealthKit", muscleMass: nil, boneMass: nil,
                notes: "Imported from HealthKit", photoUrl: nil,
                dataSource: BodyMetricSource.healthKit.rawValue,
                sourceMetadata: BodyMetricSourceMetadata(
                    vendor: "apple_health", sourceName: "Scale", sampleId: "weight-sample",
                    quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue, bodyFatSampleId: "fat-sample"
                ),
                createdAt: date, updatedAt: date
            ),
            userId: userId
        )
        let ownership = try XCTUnwrap(auth.captureAccountSession())

        let applied = try await manager.applyAnchoredBodyMetricDeletions(
            [
                HealthAnchoredDeletion(id: "weight-sample", kind: .weight, date: nil),
                HealthAnchoredDeletion(id: "fat-sample", kind: .bodyFat, date: nil)
            ],
            ownership: ownership
        )

        XCTAssertTrue(applied)
        let visible = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertTrue(visible.isEmpty)
        let flagged = try await deletionFlags(userId: userId)
        XCTAssertEqual(flagged, [true])
    }

    func testStepSyncFetchesOnlySamplesSinceTheStoredAnchor() async throws {
        let userId = "anchor-steps-\(UUID().uuidString)"
        let probe = AnchoredSampleFetchProbe()
        probe.page = HealthAnchoredSamplePage(added: [], deleted: [], newAnchor: Data([6]))
        let manager = try makeManager(userId: userId, probe: probe)
        let store = HealthAnchorStore(defaults: defaults)
        store.advance(Data([2]), for: .steps, userId: userId, commitSucceeded: true)

        try await manager.syncStepsFromHealthKit()

        XCTAssertEqual(probe.recorded().map(\.0), [.steps])
        XCTAssertEqual(probe.recorded().map(\.1), [Data([2])])
        XCTAssertEqual(store.anchor(for: .steps, userId: userId), Data([6]))
    }

    func testFailedStepCommitDoesNotAdvanceTheStoredAnchor() async throws {
        let userId = "anchor-steps-failed-\(UUID().uuidString)"
        let probe = AnchoredSampleFetchProbe()
        probe.page = HealthAnchoredSamplePage(
            added: [HealthAnchoredSample(
                id: "step-sample", kind: .steps, value: 100, date: Date(), sourceMetadata: nil
            )],
            deleted: [], newAnchor: Data([9])
        )
        let manager = try makeManager(userId: userId, probe: probe)
        manager.stepDayTotalQuery = { _ in throw AnchorCommitFailure() }
        let store = HealthAnchorStore(defaults: defaults)
        store.advance(Data([2]), for: .steps, userId: userId, commitSucceeded: true)

        do {
            try await manager.syncStepsFromHealthKit()
            XCTFail("A failed step total must not commit the anchor")
        } catch {
            XCTAssertTrue(error is AnchorCommitFailure)
        }
        XCTAssertEqual(store.anchor(for: .steps, userId: userId), Data([2]))
    }

    private func makeManager(
        userId: String,
        probe: AnchoredSampleFetchProbe,
        failCommit: Bool = false,
        weightSampleDate: Date? = nil
    ) throws -> HealthKitManager {
        auth.authSession = .localFixture(subject: userId, email: "\(userId)@example.com")
        auth.currentUser = LocalUser(
            id: userId, email: "\(userId)@example.com", name: "Anchor", avatarUrl: nil,
            profile: nil, onboardingCompleted: false
        )
        let manager = HealthKitManager(
            userDefaults: defaults, authManager: auth, coreDataManager: coreData,
            weightImportQuery: { _, _ in
                self.weightQueries += 1
                guard let weightSampleDate else { return [] }
                return [HealthKitWeightImportSample(
                    weight: 70, date: weightSampleDate,
                    sourceMetadata: BodyMetricSourceMetadata(
                        vendor: "apple_health", sampleId: "full-import-weight",
                        quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue
                    )
                )]
            },
            bodyFatImportQuery: { _ in [] },
            earliestImportDateQuery: { weightSampleDate },
            syncTrigger: {}, importCompletion: { _ in },
            metricImportStore: failCommit ? { _, _ in throw AnchorCommitFailure() } : nil,
            historicalImportPriority: .userInitiated,
            bodyFatOnlyImportEnabled: { false }
        )
        manager.isAuthorized = true
        manager.smartScaleSyncEnabled = { false }
        manager.anchoredSampleQuery = { kind, anchor in try await probe(kind, anchor) }
        return manager
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition())
    }

    private func deletionFlags(userId: String) async throws -> [Bool] {
        let context = coreData.viewContext
        return try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", userId)
            return try context.fetch(request).map(\.isMarkedDeleted)
        }
    }
}

private struct AnchorCommitFailure: Error {}
