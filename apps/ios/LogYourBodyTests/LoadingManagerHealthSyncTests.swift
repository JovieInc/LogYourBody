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
final class LoadingManagerHealthSyncTests: XCTestCase {
    func testStartLoadingCompletesBlockingPhase() async {
        let authManager = AuthManager()
        authManager.isAuthenticated = false

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )

        await manager.startLoading()

        XCTAssertFalse(manager.isLoading)
        XCTAssertEqual(manager.progress, 1.0, accuracy: 0.001)
        XCTAssertEqual(manager.loadingStatus, "Ready!")
        XCTAssertFalse(mockCoordinator.didCallWarmUpAfterLogin)
    }

    func testRunWarmUpTasksInvokesHealthSyncWhenAuthenticated() async {
        let authManager = AuthManager()
        authManager.isAuthenticated = true

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )

        await manager.runWarmUpTasks()

        XCTAssertTrue(mockCoordinator.didCallWarmUpAfterLogin)
    }

    func testRunWarmUpTasksSkipsWhenNotAuthenticated() async {
        let authManager = AuthManager()
        authManager.isAuthenticated = false

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )

        await manager.runWarmUpTasks()

        XCTAssertFalse(mockCoordinator.didCallWarmUpAfterLogin)
    }
}
