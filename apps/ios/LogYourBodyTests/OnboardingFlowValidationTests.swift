//
// OnboardingFlowValidationTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

@MainActor
final class OnboardingFlowValidationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Self.clearPersistedOnboardingCompletion()
    }

    override func tearDown() {
        Self.clearPersistedOnboardingCompletion()
        super.tearDown()
    }

    // Mirrors OnboardingFlowViewModelTests: raw-key cleanup because
    // updateCompletionStatus(false) is deliberately ignored for completed users.
    private static func clearPersistedOnboardingCompletion() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Constants.hasCompletedOnboardingKey)
        defaults.removeObject(forKey: Constants.onboardingCompletedVersionKey)
        defaults.removeObject(forKey: Constants.onboardingCompletedUserIdKey)
    }

    // MARK: - Step gating (can-continue rules)

    func testCanContinueBasicsRequiresSexSelection() {
        let viewModel = OnboardingFlowViewModel()

        XCTAssertFalse(viewModel.canContinueBasics)

        viewModel.updateSex(.male)

        XCTAssertTrue(viewModel.canContinueBasics)
        XCTAssertEqual(viewModel.bodyScoreInput.sex, .male)
    }

    func testCanContinueHeightEnforcesMetricFloorAndImperialMinimum() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.heightUnit = .centimeters

        viewModel.heightCentimetersText = "99"
        XCTAssertFalse(viewModel.canContinueHeight)

        viewModel.heightCentimetersText = "100"
        XCTAssertTrue(viewModel.canContinueHeight)

        // Empty text falls back to the already-stored height.
        viewModel.heightCentimetersText = ""
        viewModel.bodyScoreInput.height = HeightValue(value: 150, unit: .centimeters)
        XCTAssertTrue(viewModel.canContinueHeight)

        viewModel.heightUnit = .inches
        viewModel.heightFeet = 3
        viewModel.heightInches = 11
        XCTAssertFalse(viewModel.canContinueHeight)

        viewModel.heightFeet = 4
        viewModel.heightInches = 0
        XCTAssertTrue(viewModel.canContinueHeight)
    }

    func testCanContinueWeightEnforcesSeventyPoundFloorAcrossUnits() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.weightUnit = .pounds

        viewModel.manualWeightText = "69"
        XCTAssertFalse(viewModel.canContinueWeight)

        viewModel.manualWeightText = "70"
        XCTAssertTrue(viewModel.canContinueWeight)

        viewModel.weightUnit = .kilograms
        viewModel.manualWeightText = "31"
        XCTAssertFalse(viewModel.canContinueWeight)

        viewModel.manualWeightText = "32"
        XCTAssertTrue(viewModel.canContinueWeight)

        // Empty text falls back to the already-stored weight.
        viewModel.manualWeightText = ""
        viewModel.bodyScoreInput.weight = WeightValue(value: 180, unit: .pounds)
        viewModel.weightUnit = .pounds
        XCTAssertTrue(viewModel.canContinueWeight)
    }

    func testCanContinueBodyFatNumericEnforcesPlausibleBand() {
        let viewModel = OnboardingFlowViewModel()

        viewModel.bodyFatPercentageText = "3.9"
        XCTAssertFalse(viewModel.canContinueBodyFatNumeric)

        viewModel.bodyFatPercentageText = "4"
        XCTAssertTrue(viewModel.canContinueBodyFatNumeric)

        viewModel.bodyFatPercentageText = "60"
        XCTAssertTrue(viewModel.canContinueBodyFatNumeric)

        viewModel.bodyFatPercentageText = "60.1"
        XCTAssertFalse(viewModel.canContinueBodyFatNumeric)

        viewModel.bodyFatPercentageText = "abc"
        XCTAssertFalse(viewModel.canContinueBodyFatNumeric)
    }

    func testCanContinueBodyFatChoiceRequiresSelectedSource() {
        let viewModel = OnboardingFlowViewModel()

        XCTAssertFalse(viewModel.canContinueBodyFatChoice)

        viewModel.updateBodyFatSource(.manualValue)

        XCTAssertTrue(viewModel.canContinueBodyFatChoice)
    }

    // MARK: - Email capture & account creation

    func testEmailCaptureGateOnlyAcceptsWellFormedAddresses() {
        let viewModel = OnboardingFlowViewModel()

        viewModel.emailAddress = ""
        XCTAssertFalse(viewModel.canContinueEmailCapture)

        viewModel.emailAddress = "user@example.com"
        XCTAssertTrue(viewModel.canContinueEmailCapture)

        // Surrounding whitespace is tolerated via trimming.
        viewModel.emailAddress = "  user@example.com  "
        XCTAssertTrue(viewModel.canContinueEmailCapture)

        viewModel.emailAddress = "user@example.c"
        XCTAssertFalse(viewModel.canContinueEmailCapture)

        viewModel.emailAddress = "userexample.com"
        XCTAssertFalse(viewModel.canContinueEmailCapture)

        viewModel.emailAddress = "user name@example.com"
        XCTAssertFalse(viewModel.canContinueEmailCapture)
    }

    func testPersistEmailCaptureStoresTrimmedAddress() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.emailAddress = "  user@example.com  "

        viewModel.persistEmailCapture()

        XCTAssertEqual(viewModel.emailAddress, "user@example.com")
    }

    func testAccountCreationGateMirrorsEmailGate() {
        let viewModel = OnboardingFlowViewModel()

        viewModel.emailAddress = "not-an-email"
        XCTAssertFalse(viewModel.canContinueAccountCreation)

        viewModel.emailAddress = "user@example.com"
        XCTAssertTrue(viewModel.canContinueAccountCreation)
    }

    // MARK: - Entry persistence & formatting

    func testPersistManualWeightEntryStoresOnlyNumericInput() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.weightUnit = .pounds

        viewModel.manualWeightText = "abc"
        viewModel.persistManualWeightEntry()
        XCTAssertNil(viewModel.bodyScoreInput.weight.value)

        viewModel.manualWeightText = "185"
        viewModel.persistManualWeightEntry()
        XCTAssertEqual(viewModel.bodyScoreInput.weight.inPounds ?? 0, 185, accuracy: 0.01)
    }

    func testPersistHeightEntryHandlesBothUnits() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.heightUnit = .centimeters
        viewModel.heightCentimetersText = "178"

        viewModel.persistHeightEntry()
        XCTAssertEqual(viewModel.bodyScoreInput.height.inCentimeters ?? 0, 178, accuracy: 0.01)

        let imperialViewModel = OnboardingFlowViewModel()
        imperialViewModel.heightUnit = .inches
        imperialViewModel.heightFeet = 5
        imperialViewModel.heightInches = 10

        imperialViewModel.persistHeightEntry()
        XCTAssertEqual(imperialViewModel.bodyScoreInput.height.unit, .inches)
        XCTAssertEqual(imperialViewModel.bodyScoreInput.height.inCentimeters ?? 0, 177.8, accuracy: 0.01)
        XCTAssertEqual(imperialViewModel.heightCentimetersText, "177.8")
    }

    func testPersistBodyFatPercentageEntryStoresOnlyNumericInput() {
        let viewModel = OnboardingFlowViewModel()

        viewModel.bodyFatPercentageText = "abc"
        viewModel.persistBodyFatPercentageEntry()
        XCTAssertNil(viewModel.bodyScoreInput.bodyFat.percentage)

        viewModel.bodyFatPercentageText = "18.5"
        viewModel.persistBodyFatPercentageEntry()
        XCTAssertEqual(viewModel.bodyScoreInput.bodyFat.percentage ?? 0, 18.5, accuracy: 0.01)
        XCTAssertEqual(viewModel.bodyScoreInput.bodyFat.source, .manualValue)
    }

    func testVisualBodyFatSelectionDrivesInputAndGate() {
        let viewModel = OnboardingFlowViewModel()

        XCTAssertFalse(viewModel.canContinueBodyFatVisual)

        viewModel.selectVisualBodyFat(20)

        XCTAssertTrue(viewModel.canContinueBodyFatVisual)
        XCTAssertEqual(viewModel.selectedVisualBodyFat, 20)
        XCTAssertEqual(viewModel.bodyScoreInput.bodyFat.percentage, 20)
        XCTAssertEqual(viewModel.bodyScoreInput.bodyFat.source, .visualEstimate)
    }

    func testUpdateBodyFatSourcePrefillsFromExistingPercentage() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .healthKit)

        viewModel.updateBodyFatSource(.manualValue)
        XCTAssertEqual(viewModel.bodyFatPercentageText, "18")
        XCTAssertEqual(viewModel.bodyScoreInput.bodyFat.source, .manualValue)

        viewModel.updateBodyFatSource(.visualEstimate)
        XCTAssertEqual(viewModel.selectedVisualBodyFat, 18)
        XCTAssertEqual(viewModel.bodyScoreInput.bodyFat.source, .visualEstimate)
    }

    func testSetWeightUnitConvertsTextAndStoredValue() {
        let previousSystem = UserDefaults.standard.string(forKey: Constants.preferredMeasurementSystemKey)
        let previousWeightUnit = UserDefaults.standard.string(forKey: Constants.preferredWeightUnitKey)
        defer {
            if let previousSystem {
                UserDefaults.standard.set(previousSystem, forKey: Constants.preferredMeasurementSystemKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.preferredMeasurementSystemKey)
            }
            if let previousWeightUnit {
                UserDefaults.standard.set(previousWeightUnit, forKey: Constants.preferredWeightUnitKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.preferredWeightUnitKey)
            }
        }

        let viewModel = OnboardingFlowViewModel()
        viewModel.weightUnit = .pounds
        viewModel.manualWeightText = "185"

        viewModel.setWeightUnit(.kilograms)

        XCTAssertEqual(viewModel.weightUnit, .kilograms)
        XCTAssertEqual(viewModel.manualWeightText, "83.9")
        XCTAssertEqual(viewModel.bodyScoreInput.weight.inKilograms ?? 0, 83.9, accuracy: 0.01)
    }

    func testUpdateImperialFieldsClampsToPickerRanges() {
        let viewModel = OnboardingFlowViewModel()

        viewModel.updateImperialFields(fromCentimeters: 178)
        XCTAssertEqual(viewModel.heightFeet, 5)
        XCTAssertEqual(viewModel.heightInches, 10)

        viewModel.updateImperialFields(fromCentimeters: 300)
        XCTAssertEqual(viewModel.heightFeet, 8)
        XCTAssertEqual(viewModel.heightInches, 10)

        viewModel.updateImperialFields(fromCentimeters: 100)
        XCTAssertEqual(viewModel.heightFeet, 3)
        XCTAssertEqual(viewModel.heightInches, 3)
    }

    // MARK: - Step routing

    func testAdvanceFromBodyFatChoiceFollowsSelectedSource() {
        let numericViewModel = OnboardingFlowViewModel()
        numericViewModel.currentStep = .bodyFatChoice
        numericViewModel.updateBodyFatSource(.manualValue)
        numericViewModel.goToNextStep()
        XCTAssertEqual(numericViewModel.currentStep, .bodyFatNumeric)

        let visualViewModel = OnboardingFlowViewModel()
        visualViewModel.currentStep = .bodyFatChoice
        visualViewModel.updateBodyFatSource(.visualEstimate)
        visualViewModel.goToNextStep()
        XCTAssertEqual(visualViewModel.currentStep, .bodyFatVisual)

        let importedViewModel = OnboardingFlowViewModel()
        importedViewModel.currentStep = .bodyFatChoice
        importedViewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .healthKit)
        importedViewModel.goToNextStep()
        XCTAssertEqual(importedViewModel.currentStep, .loading)

        let skippedViewModel = OnboardingFlowViewModel()
        skippedViewModel.currentStep = .bodyFatChoice
        skippedViewModel.updateBodyFatSource(.unspecified)
        skippedViewModel.goToNextStep()
        XCTAssertEqual(skippedViewModel.currentStep, .bodyFatChoice)
    }

    func testFirstMissingInputStepRoutesToEarliestGap() {
        let viewModel = OnboardingFlowViewModel(healthKitManager: HealthKitManager())

        XCTAssertEqual(viewModel.firstMissingInputStep(), .basics)

        viewModel.updateSex(.female)
        XCTAssertEqual(viewModel.firstMissingInputStep(), .height)

        viewModel.bodyScoreInput.height = HeightValue(value: 170, unit: .centimeters)
        XCTAssertEqual(viewModel.firstMissingInputStep(), .manualWeight)

        viewModel.bodyScoreInput.weight = WeightValue(value: 150, unit: .pounds)
        XCTAssertEqual(viewModel.firstMissingInputStep(), .bodyFatChoice)

        let authorizedViewModel = OnboardingFlowViewModel(healthKitManager: HealthKitManager())
        authorizedViewModel.healthKitManager.isAuthorized = true
        authorizedViewModel.updateSex(.female)
        authorizedViewModel.bodyScoreInput.height = HeightValue(value: 170, unit: .centimeters)
        XCTAssertEqual(authorizedViewModel.firstMissingInputStep(), .healthConfirmation)
    }

    func testCalculateScoreIfNeededRoutesToFirstMissingInputWhenUnready() async {
        let viewModel = OnboardingFlowViewModel(healthKitManager: HealthKitManager())

        await viewModel.calculateScoreIfNeeded()

        XCTAssertEqual(viewModel.currentStep, .basics)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "Missing inputs for score calculation.")
    }

    // MARK: - Profile details draft logic

    func testRecomputeProfileDetailsActiveSubstepPicksFirstIncompleteField() {
        let viewModel = OnboardingFlowViewModel()
        let adultDateOfBirth = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()

        viewModel.profileFirstName = ""
        viewModel.profileLastName = ""
        viewModel.recomputeProfileDetailsActiveSubstep()
        XCTAssertEqual(viewModel.profileDetailsActiveSubstep, .firstName)

        viewModel.profileFirstName = "Avery"
        viewModel.recomputeProfileDetailsActiveSubstep()
        XCTAssertEqual(viewModel.profileDetailsActiveSubstep, .lastName)

        viewModel.profileLastName = "Stone"
        viewModel.profileDateOfBirth = Calendar.current.date(byAdding: .year, value: -15, to: Date()) ?? Date()
        viewModel.recomputeProfileDetailsActiveSubstep()
        XCTAssertEqual(viewModel.profileDetailsActiveSubstep, .dateOfBirth)

        viewModel.profileDateOfBirth = adultDateOfBirth
        viewModel.profileShouldAskSex = true
        viewModel.profileBiologicalSex = nil
        viewModel.recomputeProfileDetailsActiveSubstep()
        XCTAssertEqual(viewModel.profileDetailsActiveSubstep, .sex)

        viewModel.profileBiologicalSex = .female
        viewModel.recomputeProfileDetailsActiveSubstep()
        XCTAssertEqual(viewModel.profileDetailsActiveSubstep, .height)
    }

    func testBiologicalSexParsingHandlesStoredGenderStrings() {
        XCTAssertEqual(OnboardingFlowViewModel.biologicalSex(from: "Female"), .female)
        XCTAssertEqual(OnboardingFlowViewModel.biologicalSex(from: "male"), .male)
        XCTAssertEqual(OnboardingFlowViewModel.biologicalSex(from: "woman"), .female)
        XCTAssertEqual(OnboardingFlowViewModel.biologicalSex(from: "Man"), .male)
        XCTAssertNil(OnboardingFlowViewModel.biologicalSex(from: "non-binary"))
        XCTAssertNil(OnboardingFlowViewModel.biologicalSex(from: ""))
    }

    func testProfileHeightInCentimetersRespectsActiveUnit() {
        let viewModel = OnboardingFlowViewModel()

        viewModel.profileHeightUnit = .centimeters
        viewModel.profileHeightCentimetersText = "178"
        XCTAssertEqual(viewModel.profileHeightInCentimeters ?? 0, 178, accuracy: 0.01)

        viewModel.profileHeightUnit = .inches
        viewModel.profileHeightFeet = 5
        viewModel.profileHeightInches = 10
        XCTAssertEqual(viewModel.profileHeightInCentimeters ?? 0, 177.8, accuracy: 0.01)
        XCTAssertEqual(viewModel.profileHeightUnitStorageValue, "in")

        viewModel.profileHeightCentimetersText = "abc"
        viewModel.profileHeightUnit = .centimeters
        XCTAssertNil(viewModel.profileHeightInCentimeters)
    }

    func testBodyScoreInputReadinessAndAgeDerivation() {
        var input = BodyScoreInput()
        XCTAssertNil(input.age)
        XCTAssertFalse(input.isReadyForCalculation)

        input.sex = .male
        input.height = HeightValue(value: 178, unit: .centimeters)
        input.weight = WeightValue(value: 185, unit: .pounds)
        input.bodyFat = BodyFatValue(percentage: 18, source: .manualValue)
        XCTAssertTrue(input.isReadyForCalculation)

        let currentYear = Calendar.current.component(.year, from: Date())
        input.birthYear = currentYear - 30
        XCTAssertEqual(input.age, 30)

        input.birthYear = currentYear + 1
        XCTAssertEqual(input.age, 0)
    }
}
