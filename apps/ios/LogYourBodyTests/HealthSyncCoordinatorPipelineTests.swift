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
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(manager.didCallCheckAuthorizationStatus)
        XCTAssertTrue(manager.didCallObserveWeightChanges)
        XCTAssertTrue(manager.didCallObserveBodyFatChanges)
        XCTAssertTrue(manager.didCallObserveStepChanges)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 1)
        XCTAssertEqual(manager.setupStepCountBackgroundDeliveryCallCount, 1)
    }

    func testDeferredOnboardingWeightSyncBootstrapsBodyMetricPipelineBeforeImport() async {
        let manager = MockHealthKitSyncManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: manager)

        await coordinator.runDeferredOnboardingWeightSync()
        await Task.yield()

        XCTAssertTrue(manager.didCallObserveWeightChanges)
        XCTAssertTrue(manager.didCallObserveBodyFatChanges)
        XCTAssertTrue(manager.didCallObserveStepChanges)
        XCTAssertEqual(manager.setupBackgroundDeliveryCallCount, 1)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
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
}
