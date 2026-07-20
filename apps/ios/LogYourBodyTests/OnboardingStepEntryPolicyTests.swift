//
// OnboardingStepEntryPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

@MainActor
final class OnboardingStepEntryPolicyTests: XCTestCase {
    private typealias HeightInput = ProfileDetailsValidationPolicy.ProfileHeightInput

    // MARK: - Height entry (BodyScoreHeightView)

    func testHeightCentimetersErrorOnlyFlagsBelowFloorEntries() {
        XCTAssertNil(HeightEntryPolicy.centimetersError(for: ""))
        XCTAssertNil(HeightEntryPolicy.centimetersError(for: "100"))
        XCTAssertNil(HeightEntryPolicy.centimetersError(for: "250.4"))
        XCTAssertEqual(HeightEntryPolicy.centimetersError(for: "99.9"), "Enter at least 100 cm.")
        // Unparseable text reads as 0 and hits the same floor message.
        XCTAssertEqual(HeightEntryPolicy.centimetersError(for: "abc"), "Enter at least 100 cm.")
    }

    // MARK: - Manual weight entry (BodyScoreManualWeightView)

    func testWeightValidationErrorEnforcesSeventyPoundFloorInBothUnits() {
        XCTAssertNil(ManualWeightEntryPolicy.validationError(for: "", unit: .pounds))
        XCTAssertEqual(
            ManualWeightEntryPolicy.validationError(for: "abc", unit: .pounds),
            "Enter a valid number."
        )
        XCTAssertEqual(
            ManualWeightEntryPolicy.validationError(for: "69.9", unit: .pounds),
            "Enter at least 70 lbs (about 32 kg)."
        )
        XCTAssertNil(ManualWeightEntryPolicy.validationError(for: "70", unit: .pounds))
        // 31.7 kg ≈ 69.9 lbs (blocked); 31.8 kg ≈ 70.1 lbs (allowed).
        XCTAssertEqual(
            ManualWeightEntryPolicy.validationError(for: "31.7", unit: .kilograms),
            "Enter at least 32 kg (about 70 lbs)."
        )
        XCTAssertNil(ManualWeightEntryPolicy.validationError(for: "31.8", unit: .kilograms))
    }

    func testWeightNudgeUsesUnitStepsTextFirstAndNeverBelowZero() {
        XCTAssertEqual(ManualWeightEntryPolicy.stepAmount(for: .kilograms), 0.5)
        XCTAssertEqual(ManualWeightEntryPolicy.stepAmount(for: .pounds), 1)

        XCTAssertEqual(
            ManualWeightEntryPolicy.nudgeText(currentText: "180", storedValue: nil, amount: 1),
            "181"
        )
        XCTAssertEqual(
            ManualWeightEntryPolicy.nudgeText(currentText: "abc", storedValue: 175, amount: -1),
            "174"
        )
        XCTAssertEqual(
            ManualWeightEntryPolicy.nudgeText(currentText: "", storedValue: 80, amount: 0.5),
            "80.5"
        )
        XCTAssertEqual(
            ManualWeightEntryPolicy.nudgeText(currentText: "0.5", storedValue: nil, amount: -1),
            "0"
        )
    }

    // MARK: - Body fat numeric entry (BodyScoreBodyFatNumericView)

    func testBodyFatValidationErrorEnforcesPlausibleBand() {
        XCTAssertNil(BodyFatEntryPolicy.validationError(for: ""))
        XCTAssertEqual(BodyFatEntryPolicy.validationError(for: "abc"), "Enter a valid percentage.")
        XCTAssertEqual(BodyFatEntryPolicy.validationError(for: "3.9"), "Enter a body fat between 4–60%.")
        XCTAssertNil(BodyFatEntryPolicy.validationError(for: "4"))
        XCTAssertNil(BodyFatEntryPolicy.validationError(for: "60"))
        XCTAssertEqual(BodyFatEntryPolicy.validationError(for: "60.1"), "Enter a body fat between 4–60%.")
    }

    // MARK: - Profile details (BodyScoreProfileDetailsView)

    func testProfileNameValidationIgnoresWhitespaceOnlyInput() {
        XCTAssertFalse(ProfileDetailsValidationPolicy.isNameValid(""))
        XCTAssertFalse(ProfileDetailsValidationPolicy.isNameValid("   "))
        XCTAssertTrue(ProfileDetailsValidationPolicy.isNameValid(" Avery "))
    }

    func testProfileDateOfBirthRestrictsAgeToSixteenThroughEighty() throws {
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_026, month: 7, day: 20)))
        func dob(_ yearsAgo: Int) -> Date {
            calendar.date(byAdding: .year, value: -yearsAgo, to: now) ?? now
        }

        XCTAssertTrue(ProfileDetailsValidationPolicy.isDateOfBirthWithinValidRange(dob(16), now: now, calendar: calendar))
        XCTAssertFalse(ProfileDetailsValidationPolicy.isDateOfBirthWithinValidRange(dob(15), now: now, calendar: calendar))
        XCTAssertTrue(ProfileDetailsValidationPolicy.isDateOfBirthWithinValidRange(dob(80), now: now, calendar: calendar))
        XCTAssertFalse(ProfileDetailsValidationPolicy.isDateOfBirthWithinValidRange(dob(81), now: now, calendar: calendar))
    }

    func testProfileHeightValidationAndConversion() {
        func input(unit: HeightUnit, text: String = "", feet: Int, inches: Int) -> HeightInput {
            HeightInput(unit: unit, centimetersText: text, feet: feet, inches: inches)
        }

        XCTAssertFalse(ProfileDetailsValidationPolicy.isHeightValid(input(unit: .centimeters, text: "99", feet: 5, inches: 10)))
        XCTAssertTrue(ProfileDetailsValidationPolicy.isHeightValid(input(unit: .centimeters, text: "100", feet: 5, inches: 10)))
        XCTAssertTrue(ProfileDetailsValidationPolicy.isHeightValid(input(unit: .centimeters, text: "250", feet: 5, inches: 10)))
        XCTAssertFalse(ProfileDetailsValidationPolicy.isHeightValid(input(unit: .centimeters, text: "251", feet: 5, inches: 10)))
        XCTAssertFalse(ProfileDetailsValidationPolicy.isHeightValid(input(unit: .centimeters, text: "abc", feet: 5, inches: 10)))
        XCTAssertFalse(ProfileDetailsValidationPolicy.isHeightValid(input(unit: .inches, feet: 3, inches: 11)))
        XCTAssertTrue(ProfileDetailsValidationPolicy.isHeightValid(input(unit: .inches, feet: 4, inches: 0)))
        XCTAssertTrue(ProfileDetailsValidationPolicy.isHeightValid(input(unit: .inches, feet: 8, inches: 0)))
        XCTAssertFalse(ProfileDetailsValidationPolicy.isHeightValid(input(unit: .inches, feet: 8, inches: 1)))

        XCTAssertEqual(
            ProfileDetailsValidationPolicy.heightInCentimeters(input(unit: .centimeters, text: "178", feet: 5, inches: 10)),
            178
        )
        let imperial = ProfileDetailsValidationPolicy.heightInCentimeters(input(unit: .inches, feet: 5, inches: 10))
        XCTAssertEqual(imperial ?? 0, 177.8, accuracy: 0.01)
        XCTAssertNil(
            ProfileDetailsValidationPolicy.heightInCentimeters(input(unit: .centimeters, text: "abc", feet: 5, inches: 10))
        )
        XCTAssertNil(
            ProfileDetailsValidationPolicy.heightInCentimeters(input(unit: .inches, feet: 0, inches: 0))
        )
    }

    func testProfileDetailsCanContinueFollowsActiveSubstep() {
        func canContinue(
            _ substep: OnboardingFlowViewModel.ProfileDetailsSubstep,
            firstName: String = "Avery",
            lastName: String = "Stone",
            yearsAgo: Int = 20,
            sex: BiologicalSex? = .male,
            heightText: String = "178"
        ) -> Bool {
            let dateOfBirth = Calendar.current.date(byAdding: .year, value: -yearsAgo, to: Date()) ?? Date()
            let height = ProfileDetailsValidationPolicy.ProfileHeightInput(
                unit: .centimeters,
                centimetersText: heightText,
                feet: 5,
                inches: 10
            )
            return ProfileDetailsValidationPolicy.canContinue(
                substep: substep,
                firstName: firstName,
                lastName: lastName,
                dateOfBirth: dateOfBirth,
                biologicalSex: sex,
                height: height
            )
        }

        XCTAssertFalse(canContinue(.firstName, firstName: " "))
        XCTAssertTrue(canContinue(.firstName))
        XCTAssertFalse(canContinue(.lastName, lastName: ""))
        XCTAssertTrue(canContinue(.lastName))
        XCTAssertFalse(canContinue(.dateOfBirth, lastName: ""))
        XCTAssertFalse(canContinue(.dateOfBirth, yearsAgo: 15))
        XCTAssertTrue(canContinue(.dateOfBirth))
        XCTAssertFalse(canContinue(.sex, sex: nil))
        XCTAssertTrue(canContinue(.sex))
        XCTAssertFalse(canContinue(.height, heightText: "99"))
        XCTAssertTrue(canContinue(.height))
    }
}
