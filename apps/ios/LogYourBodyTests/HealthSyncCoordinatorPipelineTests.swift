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
    }
}
