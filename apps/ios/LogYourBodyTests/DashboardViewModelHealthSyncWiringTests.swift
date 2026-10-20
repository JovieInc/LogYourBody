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
        let deleted = await CoreDataManager.shared.markBodyMetricDeleted(id: "\(userId)_0")
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
