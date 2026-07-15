//
// OnboardingFlowViewModelTests.swift
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
final class OnboardingFlowViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Self.clearPersistedOnboardingCompletion()
    }

    override func tearDown() {
        Self.clearPersistedOnboardingCompletion()
        super.tearDown()
    }

    // updateCompletionStatus(false) is deliberately ignored while a completed
    // userId is persisted (stale-false protection), so another suite's leftover
    // completion state survives it. Clear the raw keys instead.
    private static func clearPersistedOnboardingCompletion() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Constants.hasCompletedOnboardingKey)
        defaults.removeObject(forKey: Constants.onboardingCompletedVersionKey)
        defaults.removeObject(forKey: Constants.onboardingCompletedUserIdKey)
    }

    func testAdvanceAfterHealthConfirmationSkipsToLoadingWhenMetricsExist() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 185, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .healthKit)
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .loading)
    }

    func testPersistedProgressRestoresDefaultHomeModeChoice() {
        let userId = "onboarding-default-mode-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated
        let previousDefaultHomeMode = UserDefaults.standard.string(forKey: Constants.defaultHomeModeKey)

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            if let previousDefaultHomeMode {
                UserDefaults.standard.set(previousDefaultHomeMode, forKey: Constants.defaultHomeModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.defaultHomeModeKey)
            }
            OnboardingProgressStore.shared.clearProgress(for: userId)
        }

        AuthManager.shared.currentUser = User(
            id: userId,
            email: "default-mode@example.com",
            name: "Default Mode"
        )
        AuthManager.shared.isAuthenticated = true
        UserDefaults.standard.set(DefaultHomeMode.avatar.rawValue, forKey: Constants.defaultHomeModeKey)

        let viewModel = OnboardingFlowViewModel()
        viewModel.currentStep = .defaultHomeMode
        viewModel.updateDefaultHomeMode(.photo)

        let savedSnapshot = OnboardingProgressStore.shared.snapshotForTesting(for: userId)
        XCTAssertEqual(savedSnapshot?.currentStep, .defaultHomeMode)
        XCTAssertEqual(savedSnapshot?.defaultHomeMode, .photo)

        UserDefaults.standard.set(DefaultHomeMode.avatar.rawValue, forKey: Constants.defaultHomeModeKey)
        let restoredViewModel = OnboardingFlowViewModel()

        XCTAssertEqual(restoredViewModel.currentStep, .defaultHomeMode)
        XCTAssertEqual(restoredViewModel.defaultHomeMode, .photo)
    }

    func testAuthenticatedFlowConsumesPreAuthDefaultHomeModeChoice() {
        let userId = "preauth-default-mode-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated
        let previousDefaultHomeMode = UserDefaults.standard.string(forKey: Constants.defaultHomeModeKey)

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            if let previousDefaultHomeMode {
                UserDefaults.standard.set(previousDefaultHomeMode, forKey: Constants.defaultHomeModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.defaultHomeModeKey)
            }
            OnboardingProgressStore.shared.clearProgress(for: userId)
            PreAuthOnboardingStore.shared.clear()
        }

        PreAuthOnboardingStore.shared.clear()
        AuthManager.shared.currentUser = User(
            id: userId,
            email: "preauth-default-mode@example.com",
            name: "Pre Auth"
        )
        AuthManager.shared.isAuthenticated = true
        UserDefaults.standard.set(DefaultHomeMode.avatar.rawValue, forKey: Constants.defaultHomeModeKey)

        let input = BodyScoreInput(
            sex: .male,
            birthYear: 1_990,
            height: HeightValue(value: 70, unit: .inches),
            weight: WeightValue(value: 185, unit: .pounds),
            bodyFat: BodyFatValue(percentage: 18, source: .manualValue)
        )
        let result = BodyScoreResult(
            score: 82,
            ffmi: 21.4,
            leanPercentile: 0.72,
            ffmiStatus: "Strong",
            bodyFatReferenceRange: .init(lowerBound: 10, upperBound: 15, label: "Athletic"),
            statusTagline: "Strong base"
        )

        PreAuthOnboardingStore.shared.save(
            input: input,
            result: result,
            defaultHomeMode: .photo
        )

        let viewModel = OnboardingFlowViewModel()

        XCTAssertEqual(viewModel.currentStep, .profileDetails)
        XCTAssertEqual(viewModel.bodyScoreInput, input)
        XCTAssertEqual(viewModel.bodyScoreResult, result)
        XCTAssertEqual(viewModel.defaultHomeMode, .photo)
        XCTAssertEqual(UserDefaults.standard.string(forKey: Constants.defaultHomeModeKey), DefaultHomeMode.photo.rawValue)

        let savedSnapshot = OnboardingProgressStore.shared.snapshotForTesting(for: userId)
        XCTAssertEqual(savedSnapshot?.currentStep, .profileDetails)
        XCTAssertEqual(savedSnapshot?.defaultHomeMode, .photo)
        XCTAssertNil(PreAuthOnboardingStore.shared.load())
    }

    func testPersistedProgressRestoresProfileDetailsDraft() throws {
        let userId = "onboarding-profile-draft-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated
        let dateOfBirth = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 1_992, month: 7, day: 4))
        )

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            OnboardingProgressStore.shared.clearProgress(for: userId)
        }

        let initialUser = User(
            id: userId,
            email: "profile-draft@example.com",
            name: "Seed User"
        )
        AuthManager.shared.currentUser = initialUser
        AuthManager.shared.isAuthenticated = true

        let viewModel = OnboardingFlowViewModel()
        viewModel.currentStep = .profileDetails
        viewModel.hydrateProfileDetailsDraftIfNeeded(from: initialUser)
        viewModel.profileFirstName = "Avery"
        viewModel.profileLastName = "Stone"
        viewModel.profileDateOfBirth = dateOfBirth
        viewModel.updateProfileBiologicalSex(.female)
        viewModel.profileHeightUnit = .inches
        viewModel.profileHeightFeet = 5
        viewModel.profileHeightInches = 7
        viewModel.profileHeightCentimetersText = "170"
        viewModel.profileDetailsActiveSubstep = .height

        let savedSnapshot = OnboardingProgressStore.shared.snapshotForTesting(for: userId)
        XCTAssertEqual(savedSnapshot?.currentStep, .profileDetails)
        XCTAssertEqual(savedSnapshot?.profileFirstName, "Avery")
        XCTAssertEqual(savedSnapshot?.profileLastName, "Stone")
        XCTAssertEqual(savedSnapshot?.profileDateOfBirth, dateOfBirth)
        XCTAssertEqual(savedSnapshot?.profileBiologicalSex, .female)
        XCTAssertEqual(savedSnapshot?.profileHeightUnit, .inches)
        XCTAssertEqual(savedSnapshot?.profileHeightFeet, 5)
        XCTAssertEqual(savedSnapshot?.profileHeightInches, 7)
        XCTAssertEqual(savedSnapshot?.profileDetailsActiveSubstep, .height)

        let restoredViewModel = OnboardingFlowViewModel()

        XCTAssertEqual(restoredViewModel.currentStep, .profileDetails)
        XCTAssertEqual(restoredViewModel.profileFirstName, "Avery")
        XCTAssertEqual(restoredViewModel.profileLastName, "Stone")
        XCTAssertEqual(restoredViewModel.profileDateOfBirth, dateOfBirth)
        XCTAssertEqual(restoredViewModel.profileBiologicalSex, .female)
        XCTAssertEqual(restoredViewModel.profileHeightUnit, .inches)
        XCTAssertEqual(restoredViewModel.profileHeightFeet, 5)
        XCTAssertEqual(restoredViewModel.profileHeightInches, 7)
        XCTAssertEqual(restoredViewModel.profileHeightCentimetersText, "170")
        XCTAssertEqual(restoredViewModel.profileDetailsActiveSubstep, .height)

        let laterUserSnapshot = User(
            id: userId,
            email: "profile-draft@example.com",
            name: "Server Override"
        )
        restoredViewModel.hydrateProfileDetailsDraftIfNeeded(from: laterUserSnapshot)

        XCTAssertEqual(restoredViewModel.profileFirstName, "Avery")
        XCTAssertEqual(restoredViewModel.profileLastName, "Stone")
        XCTAssertEqual(restoredViewModel.profileDetailsActiveSubstep, .height)
    }

    func testAdvanceAfterHealthConfirmationRequestsBodyFatWhenMissing() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 185, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue()
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .bodyFatChoice)
    }

    func testAdvanceAfterHealthConfirmationRequiresWeightWhenMissing() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue()
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .healthKit)
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .manualWeight)
    }

    func testManualWeightStepContinuesToBodyFatChoiceWhenNeeded() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 180, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue()
        viewModel.currentStep = .manualWeight

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .bodyFatChoice)
    }

    func testManualWeightStepSkipsBodyFatWhenAlreadyEntered() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 180, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 17.5, source: .manualValue)
        viewModel.currentStep = .manualWeight

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .loading)
    }

    func testProfileDetailsAdvancesToFirstPhotoWhenEnabled() {
        let viewModel = OnboardingFlowViewModel(includesFirstPhotoStep: true)
        viewModel.currentStep = .profileDetails

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .firstPhoto)
        XCTAssertFalse(OnboardingStateManager.shared.hasCompletedCurrentVersion)
    }

    func testProfileCompletionGateSkipsFirstPhotoOnSubmit() {
        let viewModel = ProfileCompletionGatePolicy.makeViewModel()

        XCTAssertFalse(viewModel.includesFirstPhotoStep)
    }

    func testProfileDetailsCompletesOnboardingWhenFirstPhotoDisabled() async {
        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: false,
            profileUpdateHandler: { _ in }
        )
        viewModel.currentStep = .profileDetails

        await viewModel.finishOnboardingAndShowPaywall()

        XCTAssertEqual(viewModel.currentStep, .paywall)
        XCTAssertTrue(OnboardingStateManager.shared.hasCompletedCurrentVersion)
    }

    func testProfileDetailsDoesNotCompleteWhenDurableProfileWriteFails() async {
        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: false,
            profileUpdateHandler: { _ in throw SupabaseError.requestFailed }
        )
        viewModel.currentStep = .profileDetails

        await viewModel.finishOnboardingAndShowPaywall()

        XCTAssertEqual(viewModel.currentStep, .profileDetails)
        XCTAssertFalse(OnboardingStateManager.shared.hasCompletedCurrentVersion)
        XCTAssertEqual(
            viewModel.errorMessage,
            "We couldn't save your setup. Check your connection and try again."
        )
    }

    func testFirstPhotoStepCanCompleteToPaywall() async {
        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: true,
            profileUpdateHandler: { _ in }
        )
        viewModel.currentStep = .firstPhoto

        await viewModel.completeFirstPhotoStep()

        XCTAssertEqual(viewModel.currentStep, .paywall)
        XCTAssertTrue(OnboardingStateManager.shared.hasCompletedCurrentVersion)
    }

    func testFirstPhotoStepDoesNotAdvanceDuringConcurrentCompletionSave() async {
        var releaseSave: CheckedContinuation<Void, Never>?
        var updateAttempts = 0
        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: true,
            profileUpdateHandler: { _ in
                updateAttempts += 1
                await withCheckedContinuation { continuation in
                    releaseSave = continuation
                }
                throw SupabaseError.requestFailed
            }
        )
        viewModel.currentStep = .firstPhoto

        let firstCompletion = Task {
            await viewModel.completeFirstPhotoStep()
        }
        while releaseSave == nil {
            await Task.yield()
        }

        await viewModel.completeFirstPhotoStep()

        XCTAssertEqual(updateAttempts, 1)
        XCTAssertEqual(viewModel.currentStep, .firstPhoto)
        XCTAssertTrue(viewModel.isCompletingOnboarding)
        XCTAssertFalse(OnboardingStateManager.shared.hasCompletedCurrentVersion)

        releaseSave?.resume()
        await firstCompletion.value

        XCTAssertEqual(updateAttempts, 1)
        XCTAssertEqual(viewModel.currentStep, .firstPhoto)
        XCTAssertFalse(viewModel.isCompletingOnboarding)
        XCTAssertFalse(OnboardingStateManager.shared.hasCompletedCurrentVersion)
        XCTAssertEqual(
            viewModel.firstPhotoErrorMessage,
            "We couldn't save your setup. Check your connection and try again."
        )
    }

    func testFirstPhotoCompletionMarksLocalUserComplete() async {
        let userId = "onboarding-first-photo-complete-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            OnboardingProgressStore.shared.clearProgress(for: userId)
        }

        AuthManager.shared.currentUser = User(
            id: userId,
            email: "first-photo-complete@example.com",
            name: "First Photo",
            profile: UserProfile(
                id: userId,
                email: "first-photo-complete@example.com",
                username: nil,
                fullName: "First Photo",
                dateOfBirth: nil,
                height: nil,
                heightUnit: nil,
                gender: nil,
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: nil,
                onboardingCompleted: false
            ),
            onboardingCompleted: false
        )
        AuthManager.shared.isAuthenticated = true

        let viewModel = OnboardingFlowViewModel(
            includesFirstPhotoStep: true,
            profileUpdateHandler: { _ in }
        )
        viewModel.currentStep = .firstPhoto

        await viewModel.completeFirstPhotoStep()

        XCTAssertEqual(viewModel.currentStep, .paywall)
        XCTAssertTrue(OnboardingStateManager.shared.hasCompletedCurrentVersion)
        XCTAssertTrue(AuthManager.shared.currentUser?.onboardingCompleted == true)
        XCTAssertEqual(AuthManager.shared.currentUser?.profile?.onboardingCompleted, true)
        XCTAssertNil(OnboardingProgressStore.shared.snapshotForTesting(for: userId))
    }

    func testProfileCompletionSyncPersistsCurrentOnboardingVersion() {
        let suiteName = "onboarding-profile-sync-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 2)

        manager.syncCompletionFlagFromProfile(true)

        XCTAssertTrue(manager.hasCompletedCurrentVersion)
        XCTAssertEqual(defaults.integer(forKey: Constants.onboardingCompletedVersionKey), 2)
    }

    func testProfileCompletionSyncIgnoresStaleFalseForSameCompletedUser() {
        let suiteName = "onboarding-profile-stale-false-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 1)

        manager.markCompleted(userId: "same-user")
        manager.syncCompletionFlagFromProfile(false, userId: "same-user")

        XCTAssertTrue(manager.hasCompletedCurrentVersion)
        XCTAssertTrue(manager.hasCompletedCurrentVersion(for: "same-user"))
        XCTAssertEqual(defaults.string(forKey: Constants.onboardingCompletedUserIdKey), "same-user")
    }

    func testCompletionUpdateIgnoresUnauthenticatedFalseForCompletedUser() {
        let suiteName = "onboarding-auth-refresh-false-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 1)

        manager.markCompleted(userId: "same-user")
        manager.updateCompletionStatus(false)

        XCTAssertTrue(manager.hasCompletedCurrentVersion)
        XCTAssertTrue(manager.hasCompletedCurrentVersion(for: "same-user"))
        XCTAssertEqual(defaults.string(forKey: Constants.onboardingCompletedUserIdKey), "same-user")
        XCTAssertEqual(defaults.integer(forKey: Constants.onboardingCompletedVersionKey), 1)
    }

    func testProfileCompletionSyncClearsInheritedCompletionForDifferentUser() {
        let suiteName = "onboarding-profile-user-switch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 1)

        manager.markCompleted(userId: "previous-user")
        XCTAssertFalse(manager.hasCompletedCurrentVersion(for: "new-user"))

        manager.syncCompletionFlagFromProfile(false, userId: "new-user")

        XCTAssertFalse(manager.hasCompletedCurrentVersion)
        XCTAssertFalse(manager.hasCompletedCurrentVersion(for: "previous-user"))
        XCTAssertNil(defaults.string(forKey: Constants.onboardingCompletedUserIdKey))
    }

    func testFirstPhotoBackNavigationAndPaywallBackNavigation() {
        let viewModel = OnboardingFlowViewModel(includesFirstPhotoStep: true)
        viewModel.currentStep = .firstPhoto

        viewModel.goBack()
        XCTAssertEqual(viewModel.currentStep, .profileDetails)

        viewModel.currentStep = .paywall
        viewModel.goBack()
        XCTAssertEqual(viewModel.currentStep, .firstPhoto)
    }

    func testFirstPhotoProgressOnlyAppearsWhenEnabled() {
        let enabledViewModel = OnboardingFlowViewModel(includesFirstPhotoStep: true)
        let disabledViewModel = OnboardingFlowViewModel(includesFirstPhotoStep: false)

        XCTAssertNotNil(enabledViewModel.progress(for: .firstPhoto))
        XCTAssertNil(disabledViewModel.progress(for: .firstPhoto))
    }

    func testBuildOnboardingProfileUpdatesIncludesGenderDobAndHeight() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.updateSex(.female)
        viewModel.updateBirthYear(1_990)
        viewModel.bodyScoreInput.height = HeightValue(value: 180, unit: .centimeters)
        viewModel.setHeightUnit(.centimeters)

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["gender"] as? String, "Female")

        let dateOfBirth = updates["dateOfBirth"] as? Date
        XCTAssertNotNil(dateOfBirth)

        if let dateOfBirth {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: dateOfBirth)
            XCTAssertEqual(components.year, 1_990)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 1)
        }

        let height = updates["height"] as? Double
        XCTAssertNotNil(height)
        if let height {
            XCTAssertEqual(height, 180.0, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "cm")
        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testBuildOnboardingProfileUpdatesRespectsImperialHeightUnit() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.height = HeightValue(value: 72, unit: .inches)
        viewModel.setHeightUnit(.inches)

        let updates = viewModel.buildOnboardingProfileUpdates()

        let height = updates["height"] as? Double
        XCTAssertNotNil(height)
        if let height {
            XCTAssertEqual(height, 72 * 2.54, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "in")
    }

    func testBuildOnboardingProfileUpdatesPrefersPersistedProfileDetailsDraft() throws {
        let userId = "onboarding-profile-update-draft-\(UUID().uuidString)"
        let previousUser = AuthManager.shared.currentUser
        let previousAuthenticationState = AuthManager.shared.isAuthenticated
        let profileDateOfBirth = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 1_991, month: 3, day: 22))
        )

        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.isAuthenticated = previousAuthenticationState
            OnboardingProgressStore.shared.clearProgress(for: userId)
        }

        let user = User(
            id: userId,
            email: "profile-update-draft@example.com",
            name: "Profile Draft"
        )
        AuthManager.shared.currentUser = user
        AuthManager.shared.isAuthenticated = true

        let viewModel = OnboardingFlowViewModel()
        viewModel.updateSex(.male)
        viewModel.updateBirthYear(1_979)
        viewModel.bodyScoreInput.height = HeightValue(value: 180, unit: .centimeters)
        viewModel.setHeightUnit(.centimeters)
        viewModel.hydrateProfileDetailsDraftIfNeeded(from: user)
        viewModel.updateProfileBiologicalSex(.female)
        viewModel.profileDateOfBirth = profileDateOfBirth
        viewModel.profileHeightUnit = .inches
        viewModel.profileHeightFeet = 5
        viewModel.profileHeightInches = 7

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["gender"] as? String, "Female")

        let dateOfBirth = updates["dateOfBirth"] as? Date
        XCTAssertEqual(dateOfBirth, profileDateOfBirth)

        let height = updates["height"] as? Double
        XCTAssertNotNil(height)
        if let height {
            XCTAssertEqual(height, 67 * 2.54, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "in")
        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testBuildOnboardingProfileUpdatesAlwaysMarksOnboardingCompleted() {
        let viewModel = OnboardingFlowViewModel()

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }
}
