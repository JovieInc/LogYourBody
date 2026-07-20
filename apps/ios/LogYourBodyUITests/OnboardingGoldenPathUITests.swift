//
// OnboardingGoldenPathUITests.swift
// LogYourBody
//
import XCTest

final class OnboardingGoldenPathUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Golden path through the Body Score onboarding flow: hook → basics →
    /// height → health connect (manual entry) → manual weight → body fat
    /// choice → body fat numeric → loading → reveal. The launch fixture
    /// provisions an authenticated, subscribed user with
    /// `onboardingCompleted: false`, so the app lands on the hook step with a
    /// fresh progress store (unique userId per launch).
    func testBodyScoreOnboardingGoldenPathReachesReveal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestBodyScoreOnboardingFixture"]
        app.launch()

        assertHookStep(in: app)
        completeBasicsStep(in: app)
        completeHeightStep(in: app)
        completeHealthConnectStep(in: app)
        completeManualWeightStep(in: app)
        completeBodyFatChoiceStep(in: app)
        completeBodyFatNumericStep(in: app)
        assertRevealStep(in: app)
    }

    // MARK: - Steps

    private func assertHookStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Get your Body Score in 60 seconds."].waitForExistence(timeout: 10))

        let startButton = app.buttons["body_score_onboarding_start_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertTrue(startButton.isHittable)
        startButton.tap()
    }

    private func completeBasicsStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Sex at birth"].waitForExistence(timeout: 5))

        let continueButton = app.buttons["body_score_onboarding_basics_continue_button"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertFalse(continueButton.isEnabled, "Continue must stay gated until a sex is selected")

        let maleOption = app.buttons["Male"]
        XCTAssertTrue(maleOption.waitForExistence(timeout: 3))
        maleOption.tap()

        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
    }

    private func completeHeightStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["How tall are you?"].waitForExistence(timeout: 5))

        // The UI-test fixture forces imperial units; switch to centimeters so
        // the height can be typed instead of spun in on picker wheels.
        let centimetersSegment = app.buttons["CM"]
        XCTAssertTrue(centimetersSegment.waitForExistence(timeout: 3))
        centimetersSegment.tap()

        let heightField = app.textFields["Height in centimeters"]
        XCTAssertTrue(heightField.waitForExistence(timeout: 3))
        heightField.tap()
        clearText(in: heightField)
        heightField.typeText("178")
        XCTAssertEqual(heightField.value as? String, "178")

        dismissKeyboardIfNeeded(in: app)

        let continueButton = app.buttons["body_score_onboarding_height_continue_button"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
    }

    private func completeHealthConnectStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Pull from Apple Health?"].waitForExistence(timeout: 5))

        // Synchronous path: skips the HealthKit permission sheet entirely.
        let manualEntryButton = app.buttons["body_score_onboarding_enter_manually_button"]
        XCTAssertTrue(manualEntryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(manualEntryButton.isHittable)
        manualEntryButton.tap()
    }

    private func completeManualWeightStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["What’s your most recent weight?"].waitForExistence(timeout: 5))

        // Switching the height step to centimeters also flips the preferred
        // measurement system to metric; return the weight unit to pounds.
        let poundsSegment = app.buttons["LBS"]
        XCTAssertTrue(poundsSegment.waitForExistence(timeout: 3))
        poundsSegment.tap()

        let weightField = app.textFields["Weight (lbs)"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 3))
        weightField.tap()
        clearText(in: weightField)
        weightField.typeText("182")
        XCTAssertEqual(weightField.value as? String, "182")

        dismissKeyboardIfNeeded(in: app)

        let continueButton = app.buttons["body_score_onboarding_manual_weight_continue_button"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
    }

    private func completeBodyFatChoiceStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["How do you want to estimate body fat?"].waitForExistence(timeout: 5))

        // Selecting an option advances to the matching input step directly.
        let manualButton = app.buttons["body_score_onboarding_body_fat_manual_button"]
        XCTAssertTrue(manualButton.waitForExistence(timeout: 3))
        XCTAssertTrue(manualButton.isHittable)
        manualButton.tap()
    }

    private func completeBodyFatNumericStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Enter your body fat %"].waitForExistence(timeout: 5))

        let bodyFatField = app.textFields["Body fat percentage"]
        XCTAssertTrue(bodyFatField.waitForExistence(timeout: 3))
        bodyFatField.tap()
        clearText(in: bodyFatField)
        bodyFatField.typeText("18")
        XCTAssertEqual(bodyFatField.value as? String, "18")

        dismissKeyboardIfNeeded(in: app)

        let continueButton = app.buttons["body_score_onboarding_body_fat_numeric_continue_button"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
    }

    private func assertRevealStep(in app: XCUIApplication) {
        // The loading step ("Calculating your Body Score") runs a fully local
        // score calculation; waiting for the reveal is the deterministic way
        // to observe that transition without racing the spinner.
        XCTAssertTrue(app.staticTexts["Your Body Score"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Crunching your numbers…"].exists)

        // The score hero is a combined accessibility element labelled
        // "Body Score <score>. <tagline>". Only the numeric structure is
        // asserted — never the Statsig-gated Target/Reference copy.
        let scoreElement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "Body Score [0-9]+\\..*"))
            .firstMatch
        XCTAssertTrue(scoreElement.waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Starting point"].waitForExistence(timeout: 3))

        let nextStepsButton = app.buttons["See my next steps"]
        XCTAssertTrue(nextStepsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(nextStepsButton.isHittable)
    }

    // MARK: - Field helpers

    private func clearText(in field: XCUIElement) {
        guard let currentValue = field.value as? String, !currentValue.isEmpty else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
    }

    private func dismissKeyboardIfNeeded(in app: XCUIApplication) {
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 2) {
            doneButton.tap()
        }
    }
}
