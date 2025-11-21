//
// LogYourBodyTests.swift
// LogYourBody
//
import XCTest
@testable import LogYourBody

@MainActor
final class OnboardingFlowViewModelTests: XCTestCase {
    func testAdvanceAfterHealthConfirmationSkipsToLoadingWhenMetricsExist() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 185, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .healthKit)
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .loading)
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
            let expectedInches = 180.0 / 2.54
            XCTAssertEqual(height, expectedInches, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "cm")
        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testBuildOnboardingProfileUpdatesRespectsImperialHeightUnit() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.height = HeightValue(value: 72, unit: .inches)
        viewModel.setHeightUnit(.inches)

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["height"] as? Double, 72)
        XCTAssertEqual(updates["heightUnit"] as? String, "in")
    }

    func testBuildOnboardingProfileUpdatesAlwaysMarksOnboardingCompleted() {
        let viewModel = OnboardingFlowViewModel()

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }
}
