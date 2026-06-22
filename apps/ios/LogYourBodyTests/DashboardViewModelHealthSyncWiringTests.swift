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
        authManager.isAuthenticated = true

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
