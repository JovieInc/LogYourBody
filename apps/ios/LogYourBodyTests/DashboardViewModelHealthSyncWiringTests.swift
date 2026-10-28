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
final class DashboardViewModelHealthSyncWiringTests: XCTestCase {
    func testAppearanceDelegatesToTheSharedCoordinatorWithSyncPreference() {
        let coordinator = MockHealthSyncCoordinator()
        let viewModel = DashboardViewModel(healthSyncCoordinator: coordinator)

        viewModel.requestForegroundHealthRefresh(syncEnabled: true)
        viewModel.requestForegroundHealthRefresh(syncEnabled: false)

        XCTAssertEqual(coordinator.foregroundRefreshRequests, [true, false])
        XCTAssertFalse(viewModel.isSyncingData)
    }

    func testForegroundRefreshGateDefaultsToOffAndUsesStableKey() {
        XCTAssertFalse(HealthKitForegroundRefreshPolicy.isEnabled { key in
            XCTAssertEqual(key, "healthkit_foreground_refresh_v1")
            return false
        })
    }

    func testSceneActiveAndViewAppearancesDebounceOneRefreshWithoutBlockingFirstPaint() async {
        let manager = MockHealthKitSyncManager()
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)
        let viewModel = DashboardViewModel(healthSyncCoordinator: coordinator)

        coordinator.requestForegroundRefresh(syncEnabled: true) // Scene active.
        viewModel.requestForegroundHealthRefresh(syncEnabled: true) // Dashboard appears.
        viewModel.requestForegroundHealthRefresh(syncEnabled: true) // Metric appears.
        coordinator.bootstrapIfNeeded(syncEnabled: true)

        XCTAssertEqual(manager.smartScaleRefreshCallCount, 0)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 0)
        XCTAssertFalse(viewModel.isSyncingData)
        await completeForegroundRefresh(clock: clock, manager: manager)
        XCTAssertEqual(clock.requestedDelays, [BatterySyncIntervalPolicy.debounceInterval])
        XCTAssertEqual(manager.smartScaleRefreshCallCount, 1)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
        XCTAssertEqual(manager.syncStepsFromHealthKitCallCount, 1)
    }

    func testRapidSceneActivationHonorsMinimumIntervalAndRefreshesWhenDue() async {
        let manager = MockHealthKitSyncManager()
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)
        coordinator.requestForegroundRefresh(syncEnabled: true)
        await completeForegroundRefresh(clock: clock, manager: manager)

        clock.now = clock.now.addingTimeInterval(299)
        for _ in 0..<10 { coordinator.requestForegroundRefresh(syncEnabled: true) }
        XCTAssertEqual(clock.requestedDelays.count, 1)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)

        clock.now = clock.now.addingTimeInterval(1)
        coordinator.requestForegroundRefresh(syncEnabled: true)
        await completeForegroundRefresh(clock: clock, manager: manager, count: 2)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 2)
        XCTAssertEqual(clock.requestedDelays.count, 2)
    }

    func testForegroundRefreshSkipsUnauthorizedUnavailableDisabledAndOtherAccount() async {
        for scenario in ["unauthorized", "unavailable", "disabled", "preferenceOff", "gateOff", "otherAccount"] {
            let manager = MockHealthKitSyncManager()
            manager.isAuthorized = scenario != "unauthorized"
            manager.isHealthKitAvailable = scenario != "unavailable"
            manager.admitsAutomaticImport = scenario != "otherAccount"
            let clock = ForegroundHealthRefreshTestClock()
            let coordinator = makeForegroundCoordinator(
                manager: manager, clock: clock,
                enabled: { scenario != "gateOff" }, syncEnabled: { scenario != "preferenceOff" }
            )

            coordinator.requestForegroundRefresh(syncEnabled: scenario != "disabled")
            await Task.yield()

            XCTAssertTrue(clock.requestedDelays.isEmpty, scenario)
            XCTAssertEqual(manager.smartScaleRefreshCallCount, 0, scenario)
            XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 0, scenario)
            XCTAssertEqual(manager.syncStepsFromHealthKitCallCount, 0, scenario)
        }
    }

    func testPermissionRevokedDuringDebounceDoesNotQueryHealthKit() async {
        let manager = MockHealthKitSyncManager()
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)
        coordinator.requestForegroundRefresh(syncEnabled: true)
        await waitForForegroundCondition { clock.hasPendingSleep }
        manager.isAuthorized = false
        clock.finishDebounce()
        await waitForForegroundCondition { manager.checkAuthorizationCallCount == 2 }

        XCTAssertEqual(manager.smartScaleRefreshCallCount, 0)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 0)
        XCTAssertEqual(manager.syncStepsFromHealthKitCallCount, 0)
    }

    func testAnchoredRefreshAvoidsASecondFullWeightImport() async {
        let manager = MockHealthKitSyncManager()
        manager.smartScaleRefreshResult = HealthKitSmartScaleRefreshResult(outcome: .refreshed, imported: 1)
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)

        coordinator.requestForegroundRefresh(syncEnabled: true)
        await completeForegroundRefresh(clock: clock, manager: manager)

        XCTAssertEqual(manager.smartScaleRefreshCallCount, 1)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 0)
        XCTAssertEqual(manager.syncStepsFromHealthKitCallCount, 1)
    }

    func testInFlightRefreshCoalescesFurtherSceneActivations() async {
        let manager = MockHealthKitSyncManager()
        var finishWeight: CheckedContinuation<Void, Never>?
        manager.weightSyncAction = { await withCheckedContinuation { finishWeight = $0 } }
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)
        coordinator.requestForegroundRefresh(syncEnabled: true)
        await waitForForegroundCondition { clock.hasPendingSleep }
        clock.finishDebounce()
        await waitForForegroundCondition { finishWeight != nil }

        clock.now = clock.now.addingTimeInterval(1_800)
        coordinator.requestForegroundRefresh(syncEnabled: true)
        XCTAssertEqual(clock.requestedDelays.count, 1)
        finishWeight?.resume()
        await waitForForegroundCondition { manager.syncStepsFromHealthKitCallCount == 1 }
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
    }

    func testAnchoredPermissionDenialDoesNotFallBackToMoreHealthKitQueries() async {
        let manager = MockHealthKitSyncManager()
        manager.smartScaleRefreshResult = .denied
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)
        coordinator.requestForegroundRefresh(syncEnabled: true)
        await waitForForegroundCondition { clock.hasPendingSleep }
        clock.finishDebounce()
        await waitForForegroundCondition { manager.smartScaleRefreshCallCount == 1 }
        await Task.yield()

        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 0)
        XCTAssertEqual(manager.syncStepsFromHealthKitCallCount, 0)
    }

    func testWeightFailureDoesNotBlockStepsOrBypassCooldown() async {
        let manager = MockHealthKitSyncManager()
        manager.weightSyncAction = { throw HealthKitError.syncFailed }
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)

        coordinator.requestForegroundRefresh(syncEnabled: true)
        await completeForegroundRefresh(clock: clock, manager: manager)
        coordinator.requestForegroundRefresh(syncEnabled: true)

        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
        XCTAssertEqual(manager.syncStepsFromHealthKitCallCount, 1)
        XCTAssertEqual(clock.requestedDelays.count, 1)
    }

    func testSignOutCancelsPendingRefreshWithoutCancellingNextAccountsRequest() async {
        let manager = MockHealthKitSyncManager()
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)
        coordinator.requestForegroundRefresh(syncEnabled: true)
        await waitForForegroundCondition { clock.hasPendingSleep }
        await coordinator.suspendAutomaticImportAfterSignOut()
        clock.finishDebounce()

        coordinator.requestForegroundRefresh(syncEnabled: true)
        await completeForegroundRefresh(clock: clock, manager: manager)
        XCTAssertEqual(manager.smartScaleRefreshCallCount, 1)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 1)
    }

    func testAccountResetClearsCompletedForegroundRefreshCooldown() async {
        let manager = MockHealthKitSyncManager()
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)
        coordinator.requestForegroundRefresh(syncEnabled: true)
        await completeForegroundRefresh(clock: clock, manager: manager)

        await coordinator.resetForCurrentUser()
        coordinator.requestForegroundRefresh(syncEnabled: true)
        await completeForegroundRefresh(clock: clock, manager: manager, count: 2)

        XCTAssertTrue(manager.didCallResetForCurrentUser)
        XCTAssertEqual(manager.syncWeightFromHealthKitCallCount, 2)
    }

    func testForegroundImportMakesNewMeasurementAvailableToDashboard() async throws {
        let userId = "dashboard_foreground_\(UUID().uuidString)"
        let auth = AuthManager()
        auth.currentUser = LocalUser(
            id: userId, email: "foreground@example.com", name: "Foreground",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        try await saveHistoryMetric(userId: userId, index: 0, date: Date().addingTimeInterval(-86_400))
        let manager = MockHealthKitSyncManager()
        manager.weightSyncAction = {
            try await self.saveHistoryMetric(userId: userId, index: 1, date: Date())
        }
        let clock = ForegroundHealthRefreshTestClock()
        let coordinator = makeForegroundCoordinator(manager: manager, clock: clock)
        let viewModel = DashboardViewModel(healthSyncCoordinator: coordinator)
        await viewModel.loadData(authManager: auth, selectedIndex: 0)
        XCTAssertEqual(viewModel.bodyMetrics.count, 1)

        viewModel.requestForegroundHealthRefresh(syncEnabled: true)
        await completeForegroundRefresh(clock: clock, manager: manager)
        // Dashboard's existing Core Data change handler reloads this same cache.
        await viewModel.loadData(authManager: auth, loadOnlyNewest: true, selectedIndex: 0)

        XCTAssertEqual(viewModel.bodyMetrics.first?.id, "\(userId)_1")
        XCTAssertEqual(viewModel.bodyMetrics.count, 2)
    }

    private func makeForegroundCoordinator(
        manager: MockHealthKitSyncManager, clock: ForegroundHealthRefreshTestClock,
        enabled: @escaping @MainActor () -> Bool = { true },
        syncEnabled: @escaping @MainActor () -> Bool = { true }
    ) -> HealthSyncCoordinator {
        HealthSyncCoordinator(
            healthKitManager: manager, foregroundRefreshEnabled: enabled, syncEnabled: syncEnabled,
            minimumInterval: { BatterySyncIntervalPolicy.interval(state: .unplugged, level: 0.6) },
            now: { clock.now }, sleep: { await clock.sleep($0) }
        )
    }

    private func completeForegroundRefresh(
        clock: ForegroundHealthRefreshTestClock, manager: MockHealthKitSyncManager, count: Int = 1
    ) async {
        await waitForForegroundCondition { clock.hasPendingSleep }
        clock.finishDebounce()
        await waitForForegroundCondition { manager.syncStepsFromHealthKitCallCount == count }
        await Task.yield()
    }

    private func waitForForegroundCondition(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }

    func testNewestRefreshPreservesLoadedHistoryAndIncludesNewMeasurement() async throws {
        let userId = "dashboard_history_\(UUID().uuidString)"
        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: userId, email: "history@example.com", name: "History",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        let viewModel = DashboardViewModel(healthSyncCoordinator: MockHealthSyncCoordinator())
        let now = Date()
        for index in 0..<5 {
            try await saveHistoryMetric(userId: userId, index: index,
                                        date: now.addingTimeInterval(Double(index) * 86_400))
        }
        await viewModel.loadData(authManager: authManager, selectedIndex: 0)
        XCTAssertEqual(viewModel.bodyMetrics.count, 5)
        try await saveHistoryMetric(userId: userId, index: 5,
                                    date: now.addingTimeInterval(5 * 86_400))

        await viewModel.loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0)

        XCTAssertEqual(viewModel.bodyMetrics.count, 6, "A refresh must not collapse loaded history")
        XCTAssertEqual(viewModel.sortedBodyMetricsAscending.count, 6)
        XCTAssertEqual(viewModel.bodyMetrics.first?.id, "\(userId)_5")
        XCTAssertEqual(viewModel.sortedBodyMetricsAscending.first?.id, "\(userId)_0")
    }

    func testNewestRefreshReconcilesDeletionAndUserChange() async throws {
        let userId = "dashboard_reconcile_\(UUID().uuidString)"
        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: userId, email: "history@example.com", name: "History",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        let viewModel = DashboardViewModel(healthSyncCoordinator: MockHealthSyncCoordinator())
        for index in 0..<3 {
            try await saveHistoryMetric(userId: userId, index: index,
                                        date: Date().addingTimeInterval(Double(index) * 86_400))
        }
        await viewModel.loadData(authManager: authManager, selectedIndex: 0)
        let deleted = await CoreDataManager.shared.markBodyMetricDeleted(id: "\(userId)_0", userId: userId)
        XCTAssertTrue(deleted)
        await viewModel.loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0)
        XCTAssertEqual(Set(viewModel.bodyMetrics.map(\.id)), Set(["\(userId)_1", "\(userId)_2"]))

        let otherId = "dashboard_other_\(UUID().uuidString)"
        try await saveHistoryMetric(userId: otherId, index: 0, date: Date())
        authManager.currentUser = LocalUser(
            id: otherId, email: "other@example.com", name: "Other",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        await viewModel.loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0)
        XCTAssertEqual(viewModel.bodyMetrics.map(\.id), ["\(otherId)_0"])
        XCTAssertEqual(viewModel.sortedBodyMetricsAscending.map(\.userId), [otherId])
    }

    func testSuspendedFirstPaintCannotOverwriteCompletedHistory() async throws {
        let userId = "dashboard_overlap_\(UUID().uuidString)"
        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: userId, email: "overlap@example.com", name: "Overlap",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        for index in 0..<3 {
            try await saveHistoryMetric(userId: userId, index: index,
                                        date: Date().addingTimeInterval(Double(index) * 86_400))
        }
        let fetchStarted = expectation(description: "First-paint fetch suspended")
        var pendingFetch: CheckedContinuation<BodyMetrics?, Never>?
        let viewModel = DashboardViewModel(
            healthSyncCoordinator: MockHealthSyncCoordinator(),
            latestMetricLoader: { _ in
                await withCheckedContinuation { continuation in
                    pendingFetch = continuation
                    fetchStarted.fulfill()
                }
            }
        )
        let initialLoad = Task {
            await viewModel.loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0)
        }
        await fulfillment(of: [fetchStarted], timeout: 3)
        await viewModel.loadData(authManager: authManager, selectedIndex: 0)
        pendingFetch?.resume(returning: viewModel.bodyMetrics.first)
        await initialLoad.value
        XCTAssertEqual(viewModel.bodyMetrics.count, 3)
        XCTAssertEqual(viewModel.sortedBodyMetricsAscending.count, 3)
    }

    private func saveHistoryMetric(userId: String, index: Int, date: Date) async throws {
        let metric = BodyMetrics(
            id: "\(userId)_\(index)", userId: userId, date: date,
            weight: 82 + Double(index), weightUnit: "kg", bodyFatPercentage: 16,
            bodyFatMethod: "manual", muscleMass: nil, boneMass: nil,
            notes: nil, photoUrl: nil, dataSource: "manual", createdAt: date, updatedAt: date
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: userId, markAsSynced: true)
    }

    func testCanInitializeWithMockHealthSyncCoordinator() {
        let viewModel = DashboardViewModel(
            healthKitManager: HealthKitManager.shared,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )

        XCTAssertNotNil(viewModel)
    }

    func testRefreshSkipsHealthKitSyncWhenDeniedAndKeepsLocalMetrics() async throws {
        let userId = "dashboard_healthkit_denied_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_denied@example.com",
            name: "HealthKit Denied",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        let authManager = AuthManager()
        authManager.currentUser = user
        authManager.authSession = .localFixture(
            subject: userId,
            email: "hk_denied@example.com",
            name: "HealthKit Denied"
        )

        let localMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: Date(),
            weight: 82.1,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "manual still works",
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        CoreDataManager.shared.saveBodyMetrics(localMetric, userId: userId, markAsSynced: false)

        let healthKitManager = HealthKitManager.shared
        healthKitManager.isAuthorized = false
        let mockCoordinator = MockHealthSyncCoordinator()
        let viewModel = DashboardViewModel(
            healthKitManager: healthKitManager,
            healthSyncCoordinator: mockCoordinator
        )

        await viewModel.refreshData(
            authManager: authManager,
            realtimeSyncManager: RealtimeSyncManager.shared
        )

        XCTAssertFalse(mockCoordinator.didCallSyncWeightFromHealthKit)
        XCTAssertTrue(viewModel.hasLoadedInitialData)
        XCTAssertEqual(viewModel.bodyMetrics.first?.id, localMetric.id)
        XCTAssertEqual(viewModel.bodyMetrics.first?.dataSource, "manual")
    }
}

@MainActor
private final class ForegroundHealthRefreshTestClock {
    var now = Date(timeIntervalSince1970: 10_000)
    private(set) var requestedDelays: [TimeInterval] = []
    private var continuation: CheckedContinuation<Void, Never>?
    var hasPendingSleep: Bool { continuation != nil }

    func sleep(_ interval: TimeInterval) async {
        requestedDelays.append(interval)
        await withCheckedContinuation { continuation = $0 }
    }

    func finishDebounce() {
        now = now.addingTimeInterval(requestedDelays.last ?? 0)
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
