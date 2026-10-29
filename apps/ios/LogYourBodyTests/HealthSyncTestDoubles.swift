//
// HealthSyncTestDoubles.swift
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

final class MockHealthSyncCoordinator: HealthSyncCoordinating {
    private(set) var didCallBootstrapIfNeeded = false
    private(set) var lastBootstrapSyncEnabled: Bool?

    private(set) var didCallResetForCurrentUser = false
    private(set) var didCallConfigureWeightOnly = false
    private(set) var didCallConfigureWeightAndSteps = false
    private(set) var didCallWarmUpAfterLogin = false
    private(set) var didCallPerformInitialConnectSync = false
    private(set) var didCallRunDeferredOnboardingWeightSync = false
    private(set) var didCallSyncWeightFromHealthKit = false
    private(set) var didCallSyncStepsFromHealthKit = false
    private(set) var didCallForceFullHealthKitSync = false

    var performInitialConnectSyncError: Error?
    var syncWeightError: Error?
    var syncStepsError: Error?
    var forceFullHealthKitSyncResult = true

    func bootstrapIfNeeded(syncEnabled: Bool) {
        didCallBootstrapIfNeeded = true
        lastBootstrapSyncEnabled = syncEnabled
    }

    func resetForCurrentUser() async {
        didCallResetForCurrentUser = true
    }

    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync() async {
        didCallConfigureWeightOnly = true
    }

    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync() async {
        didCallConfigureWeightAndSteps = true
    }

    func warmUpAfterLoginIfNeeded() async {
        didCallWarmUpAfterLogin = true
    }

    func performInitialConnectSync() async throws {
        didCallPerformInitialConnectSync = true
        if let error = performInitialConnectSyncError {
            throw error
        }
    }

    func runDeferredOnboardingWeightSync() async {
        didCallRunDeferredOnboardingWeightSync = true
    }

    func syncWeightFromHealthKit() async throws {
        didCallSyncWeightFromHealthKit = true
        if let error = syncWeightError {
            throw error
        }
    }

    func syncStepsFromHealthKit() async throws {
        didCallSyncStepsFromHealthKit = true
        if let error = syncStepsError {
            throw error
        }
    }

    func forceFullHealthKitSync() async -> Bool {
        didCallForceFullHealthKitSync = true
        return forceFullHealthKitSyncResult
    }
}

final class MockHealthKitSyncManager: HealthKitSyncManaging {
    var isHealthKitAvailable = true
    var isAuthorized = true
    var admitsAutomaticImport = true

    private(set) var didCallCheckAuthorizationStatus = false
    private(set) var checkAuthorizationCallCount = 0
    private(set) var didCallObserveWeightChanges = false
    private(set) var didCallObserveBodyFatChanges = false
    private(set) var didCallObserveStepChanges = false
    private(set) var setupBackgroundDeliveryCallCount = 0
    private(set) var setupStepCountBackgroundDeliveryCallCount = 0
    private(set) var didCallResetForCurrentUser = false
    private(set) var syncWeightFromHealthKitCallCount = 0
    private(set) var syncStepsFromHealthKitCallCount = 0
    private(set) var fetchTodayStepCountCallCount = 0
    private(set) var didCallForceFullHealthKitSync = false
    var forceFullHealthKitSyncResult = true
    var syncWeightError: Error?
    var syncStepsError: Error?
    var todayStepCount: Int? = 123
    var onSyncWeight: (() async throws -> Void)?
    var backgroundDeliveryError: Error?
    var smartScaleRefreshResult = HealthKitSmartScaleRefreshResult.inactive
    private(set) var smartScaleRefreshCallCount = 0

    func checkAuthorizationStatus() {
        didCallCheckAuthorizationStatus = true
        checkAuthorizationCallCount += 1
    }

    func admitsAutomaticImportForCurrentAccount() -> Bool {
        admitsAutomaticImport
    }

    func observeWeightChanges() {
        didCallObserveWeightChanges = true
    }

    func observeBodyFatChanges() {
        didCallObserveBodyFatChanges = true
    }

    func observeStepChanges() {
        didCallObserveStepChanges = true
    }

    func setupBackgroundDelivery() async throws {
        setupBackgroundDeliveryCallCount += 1
        if let backgroundDeliveryError { throw backgroundDeliveryError }
    }

    func setupStepCountBackgroundDelivery() async throws {
        setupStepCountBackgroundDeliveryCallCount += 1
    }

    func resetForCurrentUser() async {
        didCallResetForCurrentUser = true
    }

    func syncWeightFromHealthKit() async throws {
        syncWeightFromHealthKitCallCount += 1
        try await onSyncWeight?()
        if let syncWeightError { throw syncWeightError }
    }

    func syncStepsFromHealthKit() async throws {
        syncStepsFromHealthKitCallCount += 1
        if let syncStepsError { throw syncStepsError }
    }

    func fetchTodayStepCount() async throws -> Int? {
        fetchTodayStepCountCallCount += 1
        return todayStepCount
    }

    func forceFullHealthKitSync() async -> Bool {
        didCallForceFullHealthKitSync = true
        return forceFullHealthKitSyncResult
    }

    func refreshSmartScaleSamplesIfEnabled() async -> HealthKitSmartScaleRefreshResult {
        smartScaleRefreshCallCount += 1
        return smartScaleRefreshResult
    }
}

/// Records anchored HealthKit fetches for weight, body fat, and steps.
final class AnchoredSampleFetchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [(HealthAnchorSampleKind, Data?)] = []
    var page = HealthAnchoredSamplePage(added: [], deleted: [], newAnchor: Data([9]))

    func callAsFunction(
        _ kind: HealthAnchorSampleKind, _ anchor: Data?
    ) async throws -> HealthAnchoredSamplePage {
        lock.lock()
        requests.append((kind, anchor))
        let response = page
        lock.unlock()
        return response
    }

    func recorded() -> [(HealthAnchorSampleKind, Data?)] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}
