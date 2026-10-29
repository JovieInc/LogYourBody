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


@MainActor
final class HealthSyncCoordinatorPipelineTests: XCTestCase {
    func testBootstrapSkipsObserversWhenAnotherAccountOwnsHealthSync() async throws {
        let manager = MockHealthKitSyncManager()
        manager.admitsAutomaticImport = false
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        coordinator.bootstrapIfNeeded(syncEnabled: true)
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(manager.didCallCheckAuthorizationStatus)
        XCTAssertFalse(manager.didCallObserveWeightChanges)
        XCTAssertFalse(manager.didCallObserveStepChanges)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 0)
    }

    func testSignOutSuspensionAllowsTheSameAccountToBootstrapAgain() async throws {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        coordinator.bootstrapIfNeeded(syncEnabled: true)
        await coordinator.suspendAutomaticImportAfterSignOut()
        coordinator.bootstrapIfNeeded(syncEnabled: true)

        XCTAssertEqual(manager.checkAuthorizationCallCount, 2)
        XCTAssertTrue(manager.didCallObserveWeightChanges)
    }

    func testBootstrapSkipsHealthKitWhenSyncIsDisabled() async {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        coordinator.bootstrapIfNeeded(syncEnabled: false)
        await Task.yield()

        XCTAssertFalse(manager.didCallCheckAuthorizationStatus)
        XCTAssertFalse(manager.didCallObserveWeightChanges)
        XCTAssertFalse(manager.didCallObserveBodyFatChanges)
        XCTAssertFalse(manager.didCallObserveStepChanges)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 0)
        XCTAssertEqual(manager.setupStepCountBackgroundDeliveryCallCount, 0)
    }

    func testBootstrapConfiguresBodyMetricAndStepObserversWithBackgroundDelivery() async throws {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        coordinator.bootstrapIfNeeded(syncEnabled: true)

        XCTAssertTrue(manager.didCallCheckAuthorizationStatus)
        XCTAssertTrue(manager.didCallObserveWeightChanges)
        XCTAssertTrue(manager.didCallObserveBodyFatChanges)
        XCTAssertTrue(manager.didCallObserveStepChanges)
        await waitForBackgroundDelivery(manager)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 1)
        XCTAssertEqual(manager.setupStepCountBackgroundDeliveryCallCount, 1)
    }

    func testDeferredOnboardingWeightSyncBootstrapsBodyMetricPipelineBeforeImport() async {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        await coordinator.runDeferredOnboardingWeightSync()

        XCTAssertTrue(manager.didCallObserveWeightChanges)
        XCTAssertTrue(manager.didCallObserveBodyFatChanges)
        XCTAssertTrue(manager.didCallObserveStepChanges)
        await waitForBackgroundDelivery(manager)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 1)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
    }

    /// Background delivery starts on an unstructured main-actor task. One yield
    /// drops that task when CI is busy. Wait for the call; the equality check
    /// still fails if delivery is never configured.
    private func waitForBackgroundDelivery(_ manager: MockHealthKitSyncManager) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let bodyMetricsReady = manager.setupBackgroundDeliveryCallCount >= 1
            let stepsReady = manager.setupStepCountBackgroundDeliveryCallCount >= 1
            if bodyMetricsReady, stepsReady { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testInitialConnectSyncBootstrapsObserversAndRunsInitialImports() async throws {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        try await coordinator.performInitialConnectSync()
        await Task.yield()

        XCTAssertTrue(manager.didCallObserveWeightChanges)
        XCTAssertTrue(manager.didCallObserveBodyFatChanges)
        XCTAssertTrue(manager.didCallObserveStepChanges)
        XCTAssertGreaterThanOrEqual(manager.setupBackgroundDeliveryCallCount, 1)
        XCTAssertGreaterThanOrEqual(manager.setupStepCountBackgroundDeliveryCallCount, 1)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
        XCTAssertEqual(manager.fetchTodayStepCountCallCount, 1)
    }

    func testFullHealthKitSyncForwardsFailureResultToCaller() async {
        let manager = MockHealthKitSyncManager()
        manager.forceFullHealthKitSyncResult = false
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        let didSucceed = await coordinator.forceFullHealthKitSync()

        XCTAssertFalse(didSucceed)
        XCTAssertTrue(manager.didCallForceFullHealthKitSync)
        XCTAssertEqual(coordinator.syncState, .unavailable)
        XCTAssertNil(coordinator.lastSuccessfulSync)
    }

    func testRefreshPublishesCheckingThenUpdatedWithCompletionTime() async throws {
        let manager = MockHealthKitSyncManager()
        let completedAt = Date(timeIntervalSince1970: 1_000)
        let coordinator = HealthSyncCoordinator(healthKitManager: manager, now: { completedAt })
        manager.onSyncWeight = {
            XCTAssertEqual(coordinator.syncState, .checking)
            XCTAssertNil(coordinator.lastSuccessfulSync)
        }

        try await coordinator.syncWeightFromHealthKit()

        XCTAssertEqual(coordinator.syncState, .updated)
        XCTAssertEqual(coordinator.lastSuccessfulSync, completedAt)
    }

    func testRefreshFailuresReachUnavailableOfflineAndPermissionNeededWithoutAdvancingDate() async throws {
        let failures: [(Error, HealthSyncState)] = [
            (HealthKitError.syncFailed, .unavailable),
            (URLError(.notConnectedToInternet), .offline),
            (URLError(.networkConnectionLost), .offline),
            (HealthKitError.notAuthorized, .permissionNeeded),
            (NSError(domain: HKErrorDomain, code: HKError.Code.errorAuthorizationDenied.rawValue), .permissionNeeded)
        ]
        for (error, expected) in failures {
            let manager = MockHealthKitSyncManager()
            var now = Date(timeIntervalSince1970: 1_000)
            let coordinator = HealthSyncCoordinator(healthKitManager: manager, now: { now })
            try await coordinator.syncWeightFromHealthKit()
            let previousSync = coordinator.lastSuccessfulSync
            now = now.addingTimeInterval(60)
            manager.syncWeightError = error

            do {
                try await coordinator.syncWeightFromHealthKit()
                XCTAssertEqual(expected, .permissionNeeded, "Other failures must still reach callers")
            } catch {
                XCTAssertNotEqual(expected, .permissionNeeded, "Permission failures must be silent")
            }

            XCTAssertEqual(coordinator.syncState, expected)
            XCTAssertEqual(coordinator.lastSuccessfulSync, previousSync)
            XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 2, "No implicit retry")
        }
    }

    func testDeniedPermissionSkipsAllRefreshAndBootstrapPathsWithoutRetrying() async throws {
        let manager = MockHealthKitSyncManager()
        manager.isAuthorized = false
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        for _ in 0..<2 {
            coordinator.bootstrapIfNeeded(syncEnabled: true)
            await coordinator.warmUpAfterLoginIfNeeded()
            await coordinator.configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync()
            await coordinator.configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync()
            await coordinator.runDeferredOnboardingWeightSync()
            try await coordinator.performInitialConnectSync()
            try await coordinator.syncWeightFromHealthKit()
            try await coordinator.syncStepsFromHealthKit()
            let succeeded = await coordinator.forceFullHealthKitSync()
            XCTAssertFalse(succeeded)
        }
        await Task.yield()

        XCTAssertEqual(coordinator.syncState, .permissionNeeded)
        XCTAssertFalse(coordinator.syncState.isNagWorthy)
        XCTAssertNil(coordinator.lastSuccessfulSync)
        XCTAssertFalse(manager.didCallObserveWeightChanges)
        XCTAssertFalse(manager.didCallObserveBodyFatChanges)
        XCTAssertFalse(manager.didCallObserveStepChanges)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 0)
        XCTAssertEqual(manager.setupStepCountBackgroundDeliveryCallCount, 0)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 0)
        XCTAssertEqual(manager.syncStepsFromHealthKitCallCount, 0)
        XCTAssertEqual(manager.fetchTodayStepCountCallCount, 0)
        XCTAssertFalse(manager.didCallForceFullHealthKitSync)
        XCTAssertEqual(manager.smartScaleRefreshCallCount, 0)
    }

    func testRevocationBlocksFurtherAttemptsUntilExplicitAuthorization() async throws {
        let manager = MockHealthKitSyncManager()
        let completedAt = Date(timeIntervalSince1970: 1_000)
        let coordinator = HealthSyncCoordinator(healthKitManager: manager, now: { completedAt })
        try await coordinator.syncWeightFromHealthKit()

        manager.isAuthorized = false
        coordinator.bootstrapIfNeeded(syncEnabled: true)
        // A stale adapter flag must not undo the recorded permission decision.
        manager.isAuthorized = true
        try await coordinator.syncWeightFromHealthKit()
        try await coordinator.syncStepsFromHealthKit()
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
        XCTAssertEqual(manager.syncStepsFromHealthKitCallCount, 0)
        XCTAssertEqual(coordinator.syncState, .permissionNeeded)
        XCTAssertFalse(coordinator.syncState.isNagWorthy)
        XCTAssertEqual(coordinator.lastSuccessfulSync, completedAt)

        try await coordinator.performInitialConnectSync()
        XCTAssertEqual(coordinator.syncState, .updated)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 2)
    }

    func testLateRefreshCompletionCannotOverwriteRevocation() async throws {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)
        manager.onSyncWeight = {
            manager.isAuthorized = false
            coordinator.bootstrapIfNeeded(syncEnabled: true)
            manager.isAuthorized = true
        }

        try await coordinator.syncWeightFromHealthKit()

        XCTAssertEqual(coordinator.syncState, .permissionNeeded)
        XCTAssertFalse(coordinator.syncState.isNagWorthy)
        XCTAssertNil(coordinator.lastSuccessfulSync)
    }

    func testSuccessfulEmptyRefreshIsUpdatedAndNeverMeansPermissionDenial() async {
        let manager = MockHealthKitSyncManager()
        manager.todayStepCount = nil
        let completedAt = Date(timeIntervalSince1970: 1_000)
        let coordinator = HealthSyncCoordinator(healthKitManager: manager, now: { completedAt })

        await coordinator.warmUpAfterLoginIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while coordinator.syncState != .updated, Date() < deadline { await Task.yield() }

        XCTAssertEqual(coordinator.syncState, .updated)
        XCTAssertFalse(coordinator.syncState.isNagWorthy)
        XCTAssertEqual(coordinator.lastSuccessfulSync, completedAt)
        XCTAssertEqual(manager.fetchTodayStepCountCallCount, 1)
    }

    func testStepAndFullRefreshesReportSuccessAndPreserveTimestampOnFailure() async throws {
        let manager = MockHealthKitSyncManager()
        var now = Date(timeIntervalSince1970: 1_000)
        let coordinator = HealthSyncCoordinator(healthKitManager: manager, now: { now })

        try await coordinator.syncStepsFromHealthKit()
        XCTAssertEqual(coordinator.lastSuccessfulSync, now)
        now = now.addingTimeInterval(60)
        let succeeded = await coordinator.forceFullHealthKitSync()
        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.syncState, .updated)
        XCTAssertEqual(coordinator.lastSuccessfulSync, now)

        manager.syncStepsError = URLError(.notConnectedToInternet)
        do {
            try await coordinator.syncStepsFromHealthKit()
            XCTFail("Offline errors must still reach callers")
        } catch {
            XCTAssertEqual(coordinator.syncState, .offline)
        }
        manager.forceFullHealthKitSyncResult = false
        let failed = await coordinator.forceFullHealthKitSync()
        XCTAssertFalse(failed)
        XCTAssertEqual(coordinator.syncState, .unavailable)
        XCTAssertEqual(coordinator.lastSuccessfulSync, now)
    }

    func testAccountResetDiscardsInFlightRefreshCompletion() async throws {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)
        try await coordinator.syncStepsFromHealthKit()
        manager.onSyncWeight = { await coordinator.resetForCurrentUser() }

        try await coordinator.syncWeightFromHealthKit()

        XCTAssertEqual(coordinator.syncState, .unavailable)
        XCTAssertNil(coordinator.lastSuccessfulSync)
    }

    func testForegroundAdapterOutcomesFeedTheSameReducerWithoutCountingSkippedReadsAsSuccess() async {
        let rows: [(HealthKitSmartScaleRefreshResult, HealthSyncState, Bool)] = [
            (.inactive, .unavailable, false), (.busy, .unavailable, false),
            (.denied, .permissionNeeded, false), (.unavailable, .unavailable, false),
            (.failed, .unavailable, false),
            (HealthKitSmartScaleRefreshResult(outcome: .refreshed), .updated, true),
            (HealthKitSmartScaleRefreshResult(outcome: .refreshed, imported: 1), .updated, true)
        ]
        let completedAt = Date(timeIntervalSince1970: 1_000)
        for (result, expected, succeeds) in rows {
            let manager = MockHealthKitSyncManager()
            manager.smartScaleRefreshResult = result
            let coordinator = HealthSyncCoordinator(healthKitManager: manager, now: { completedAt })
            coordinator.bootstrapIfNeeded(syncEnabled: true)
            let deadline = Date().addingTimeInterval(2)
            while manager.smartScaleRefreshCallCount == 0 || coordinator.syncState != expected, Date() < deadline {
                await Task.yield()
            }

            XCTAssertEqual(manager.smartScaleRefreshCallCount, 1)
            XCTAssertEqual(coordinator.syncState, expected)
            XCTAssertEqual(coordinator.lastSuccessfulSync, succeeds ? completedAt : nil)
            if expected == .permissionNeeded {
                XCTAssertFalse(coordinator.syncState.isNagWorthy)
                coordinator.bootstrapIfNeeded(syncEnabled: true)
                await Task.yield()
                XCTAssertEqual(manager.smartScaleRefreshCallCount, 1, "Denial must not schedule another attempt")
            }
        }
    }

    func testBackgroundDeliveryDenialIsSilentAndDoesNotRetry() async {
        let manager = MockHealthKitSyncManager()
        manager.backgroundDeliveryError = HealthKitError.notAuthorized
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)
        coordinator.bootstrapIfNeeded(syncEnabled: true)
        let deadline = Date().addingTimeInterval(2)
        while coordinator.syncState != .permissionNeeded, Date() < deadline { await Task.yield() }

        coordinator.bootstrapIfNeeded(syncEnabled: true)
        await Task.yield()
        XCTAssertEqual(coordinator.syncState, .permissionNeeded)
        XCTAssertFalse(coordinator.syncState.isNagWorthy)
        XCTAssertNil(coordinator.lastSuccessfulSync)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 1)
        XCTAssertEqual(manager.setupStepCountBackgroundDeliveryCallCount, 0)
    }
}
