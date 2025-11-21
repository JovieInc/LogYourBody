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
}
