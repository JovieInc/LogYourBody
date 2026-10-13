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
