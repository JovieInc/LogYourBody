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
    func testAuthWaitReturnsAtDeadlineWithoutReadiness() async {
        let authManager = AuthManager()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )
        let completed = expectation(description: "Auth wait reaches its own deadline")
        let waiting = Task { @MainActor in
            let ready = await manager.waitForAuthInitialization(timeoutNanoseconds: 50_000_000)
            XCTAssertFalse(ready)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
        waiting.cancel()
        await waiting.value
        XCTAssertFalse(authManager.isAuthProviderLoaded)
        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.currentUser)
    }

    func testAuthWaitReturnsForAlreadyReadyProvider() async {
        let authManager = AuthManager()
        authManager.isAuthProviderLoaded = true
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )
        let ready = await manager.waitForAuthInitialization(timeoutNanoseconds: 0)
        XCTAssertTrue(ready)
        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.currentUser)
    }

    func testAuthWaitObservesReadinessBeforeDeadline() async {
        let authManager = AuthManager()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )
        let waiting = Task { @MainActor in
            await manager.waitForAuthInitialization(timeoutNanoseconds: 1_000_000_000)
        }
        await Task.yield()
        authManager.isAuthProviderLoaded = true
        let ready = await waiting.value
        XCTAssertTrue(ready)
        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.currentUser)
    }

    func testAuthWaitDoesNotTreatProviderFailureAsReady() async {
        let authManager = AuthManager()
        authManager.authProviderInitError = "Synthetic initialization failure"
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )
        let ready = await manager.waitForAuthInitialization(timeoutNanoseconds: 0)
        XCTAssertFalse(ready)
        XCTAssertFalse(authManager.isAuthProviderLoaded)
        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.currentUser)
    }

    func testCancelledAuthWaitReturnsWhileProviderRemainsPending() async {
        let authManager = AuthManager()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )
        let started = expectation(description: "Auth wait started")
        let completed = expectation(description: "Cancelled auth wait returns")
        let waiting = Task { @MainActor in
            started.fulfill()
            let ready = await manager.waitForAuthInitialization(timeoutNanoseconds: 5_000_000_000)
            XCTAssertFalse(ready)
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        waiting.cancel()
        await fulfillment(of: [completed], timeout: 1)
        await waiting.value
        XCTAssertFalse(authManager.isAuthProviderLoaded)
        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.currentUser)
    }

    func testBlockingPhaseCompletesWhileAuthInitializationRemainsSuspended() async {
        let authManager = AuthManager()
        let coordinator = MockHealthSyncCoordinator()
        let release = AsyncStream<Void>.makeStream()
        let authTask = Task { @MainActor in
            for await _ in release.stream { }
            authManager.isAuthProviderLoaded = true
        }
        // Release even after an assertion fails so the old, unbounded wait cannot strand CI.
        defer { release.continuation.finish() }
        var initializationRequested = false
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: coordinator,
            initializeAuthentication: {
                initializationRequested = true
                return authTask
            }
        )
        let completed = expectation(description: "Blocking phase returns before auth is released")
        let loadingTask = Task { @MainActor in
            await manager.startLoading()
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1.5)

        XCTAssertTrue(initializationRequested)
        XCTAssertFalse(manager.isLoading)
        XCTAssertEqual(manager.progress, 1.0)
        XCTAssertFalse(authManager.isAuthProviderLoaded)
        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.currentUser)
        XCTAssertFalse(coordinator.didCallWarmUpAfterLogin)
        XCTAssertFalse(authTask.isCancelled)

        release.continuation.finish()
        await authTask.value
        await loadingTask.value
        XCTAssertTrue(authManager.isAuthProviderReady)
        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.currentUser)
    }

    func testStartLoadingCompletesBlockingPhase() async {
        let authManager = AuthManager()
        authManager.authSession = nil

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
        authManager.authSession = .localFixture(
            subject: "loading-user",
            email: "loading@example.com"
        )

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
        authManager.authSession = nil

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )

        await manager.runWarmUpTasks()

        XCTAssertFalse(mockCoordinator.didCallWarmUpAfterLogin)
    }

    func testCachedProfileIsNotAppliedAfterAccountReplacement() async throws {
        let userA = "profile-owner-\(UUID().uuidString)"
        let userB = "profile-replacement-\(UUID().uuidString)"
        let ownerName = "Profile Owner A"
        let authManager = AuthManager()
        authManager.authSession = .localFixture(subject: userA, email: "profile-owner@example.com")
        authManager.currentUser = User(
            id: userA,
            email: "profile-owner@example.com",
            name: "Owner",
            profile: nil
        )
        CoreDataManager.shared.saveProfile(
            UserProfile(
                id: userA,
                email: "profile-owner@example.com",
                username: nil,
                fullName: ownerName,
                dateOfBirth: nil,
                height: 180,
                heightUnit: "cm",
                gender: nil,
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: "kg",
                onboardingCompleted: nil
            ),
            userId: userA,
            email: "profile-owner@example.com"
        )
        let saved = await waitForCachedProfile(userId: userA)
        XCTAssertEqual(saved?.fullName, ownerName)
        XCTAssertEqual(saved?.height ?? 0, 180, accuracy: 0.001)

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )
        let replacement = User(
            id: userB,
            email: "profile-replacement@example.com",
            name: "Replacement",
            profile: nil
        )
        var fetchedUserId: String?
        manager.onCachedProfileFetched = { userId in
            fetchedUserId = userId
            authManager.authSession = .localFixture(
                subject: userB,
                email: "profile-replacement@example.com"
            )
            authManager.currentUser = replacement
        }

        await manager.startLoading()

        XCTAssertEqual(fetchedUserId, userA)
        XCTAssertFalse(manager.isLoading)
        XCTAssertEqual(manager.progress, 1.0, accuracy: 0.001)
        XCTAssertEqual(authManager.currentUser?.id, userB)
        XCTAssertNil(authManager.currentUser?.profile)
        let ownerAfter = await CoreDataManager.shared.fetchProfile(for: userA)
        let replacementProfile = await CoreDataManager.shared.fetchProfile(for: userB)
        XCTAssertEqual(ownerAfter?.fullName, ownerName)
        XCTAssertNil(replacementProfile)
    }

    func testCachedProfileIsAppliedForTheSignedInAccount() async throws {
        let userA = "profile-owner-\(UUID().uuidString)"
        let ownerName = "Profile Owner A"
        let authManager = AuthManager()
        authManager.authSession = .localFixture(subject: userA, email: "profile-owner@example.com")
        authManager.currentUser = User(
            id: userA,
            email: "profile-owner@example.com",
            name: "Owner",
            profile: nil
        )
        CoreDataManager.shared.saveProfile(
            UserProfile(
                id: userA,
                email: "profile-owner@example.com",
                username: nil,
                fullName: ownerName,
                dateOfBirth: nil,
                height: 180,
                heightUnit: "cm",
                gender: nil,
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: "kg",
                onboardingCompleted: nil
            ),
            userId: userA,
            email: "profile-owner@example.com"
        )
        let saved = await waitForCachedProfile(userId: userA)
        XCTAssertEqual(saved?.fullName, ownerName)

        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )

        await manager.startLoading()

        XCTAssertFalse(manager.isLoading)
        XCTAssertEqual(authManager.currentUser?.id, userA)
        XCTAssertEqual(authManager.currentUser?.profile?.fullName, ownerName)
        XCTAssertEqual(authManager.currentUser?.profile?.height ?? 0, 180, accuracy: 0.001)
    }

    private func waitForCachedProfile(userId: String) async -> CachedProfile? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let profile = await CoreDataManager.shared.fetchProfile(for: userId) {
                return profile
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }
}
