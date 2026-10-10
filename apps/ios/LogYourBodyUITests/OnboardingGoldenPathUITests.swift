//
// OnboardingGoldenPathUITests.swift
// LogYourBody
//
import XCTest

final class OnboardingGoldenPathUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Manual path through the first run: "Enter my numbers" → weight → body
    /// fat choice → body fat value → fat-vs-muscle reveal → profile, which asks
    /// what's still missing (no Home-mode question, no last name). The launch fixture
    /// provisions an authenticated, subscribed user with
    /// `onboardingCompleted: false`, so the app lands on the hook step with a
    /// fresh progress store (unique userId per launch).
    func testBodyScoreOnboardingGoldenPathReachesReveal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestBodyScoreOnboardingFixture"]
        app.launch()

        assertHookStep(in: app)
        app.buttons["body_score_onboarding_start_button"].tap()
        completeManualWeightStep(in: app)
        completeBodyFatChoiceStep(in: app)
        completeBodyFatNumericStep(in: app)
        assertRevealStep(in: app)
        continueFromRevealToProfile(in: app)
    }

    /// The "Why we ask" disclosure is a compact caption. Its effective target
    /// must still be at least 44 points, including a tap at the top edge.
    func testWhyWeAskDisclosureKeepsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestBodyScoreOnboardingFixture"]
        app.launch()

        let startButton = app.buttons["body_score_onboarding_start_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let whyWeAsk = app.buttons["Why we ask"]
        XCTAssertTrue(whyWeAsk.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(whyWeAsk.frame.width, 44, "Why we ask width \(whyWeAsk.frame.width)")
        XCTAssertGreaterThanOrEqual(whyWeAsk.frame.height, 44, "Why we ask height \(whyWeAsk.frame.height)")
        XCTAssertTrue(whyWeAsk.isHittable)

        whyWeAsk.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()

        XCTAssertTrue(
            app.staticTexts["We use sex at birth only to match you to the right comparison group—never for marketing."]
                .waitForExistence(timeout: 3),
            "A tap at the top of the 44-point target must expand the disclosure"
        )
    }

    // MARK: - Steps

    private func assertHookStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Are you losing fat or muscle?"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_bodyScoreIntro"].exists)

        // One primary path (the scan), Apple Health second, typing last.
        XCTAssertTrue(app.buttons["body_score_onboarding_import_scan_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["body_score_onboarding_use_health_button"].isHittable)
        let startButton = app.buttons["body_score_onboarding_start_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertTrue(startButton.isHittable)
    }

    /// Scan path: importing two DEXA scans goes straight to the reveal, which
    /// says what changed between them, then asks only what the scan lacks.
    func testScanImportGoesStraightToFatVsMuscleWithWhatChanged() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestBodyScoreOnboardingFixture", "-lybUITestOnboardingScanImportFixture"]
        app.launch()

        assertHookStep(in: app)
        attachScreenshot(named: "first-run-your-data", from: app)
        app.buttons["body_score_onboarding_import_scan_button"].tap()

        XCTAssertTrue(app.staticTexts["Here’s your fat vs muscle."].waitForExistence(timeout: 15))
        let summary = app.descendants(matching: .any)["body_score_reveal_fat_vs_muscle"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Fat 34 lb. Lean mass 146 lb. Body fat 19%. Body fat measured by your scan.")
        let change = app.descendants(matching: .any)["body_score_reveal_scan_change"]
        XCTAssertTrue(change.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["Since Jun 2, 2026: 7 lb less fat, 1 lb more lean mass."].exists,
            "Two scans answer the question directly"
        )
        attachScreenshot(named: "first-run-scan-reveal", from: app)

        continueFromRevealToProfile(in: app)
        attachScreenshot(named: "first-run-only-whats-missing", from: app)
    }

    /// Apple Health is one tap from the first screen, and Back returns to it.
    func testAppleHealthPathOpensFromTheFirstScreenAndBackReturns() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestBodyScoreOnboardingFixture"]
        app.launch()

        assertHookStep(in: app)
        app.buttons["body_score_onboarding_use_health_button"].tap()
        XCTAssertTrue(app.staticTexts["Use what your iPhone already knows."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["body_score_onboarding_enter_manually_button"].exists, "Health stays optional")

        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
        XCTAssertTrue(app.staticTexts["Are you losing fat or muscle?"].waitForExistence(timeout: 5))
    }

    private func completeBasicsStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Which reference should we use?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_sexAtBirth"].exists)

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
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_height"].exists)

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
        XCTAssertTrue(app.staticTexts["Use what your iPhone already knows."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_appleHealth"].exists)

        // Synchronous path: skips the HealthKit permission sheet entirely.
        let manualEntryButton = app.buttons["body_score_onboarding_enter_manually_button"]
        XCTAssertTrue(manualEntryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(manualEntryButton.isHittable)
        manualEntryButton.tap()
    }

    private func completeManualWeightStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["What’s your current weight?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_weight"].exists)

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
        XCTAssertTrue(app.staticTexts["How do you know your body fat?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_bodyFatMethod"].exists)

        // Selecting an option advances to the matching input step directly.
        let manualButton = app.buttons["body_score_onboarding_body_fat_manual_button"]
        XCTAssertTrue(manualButton.waitForExistence(timeout: 3))
        XCTAssertTrue(manualButton.isHittable)
        manualButton.tap()
    }

    private func completeBodyFatNumericStep(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Enter your body fat."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_bodyFatValue"].exists)

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
        // The loading step runs a fully local calculation; waiting for the
        // reveal is the deterministic way to observe that transition.
        XCTAssertTrue(app.staticTexts["Here’s your fat vs muscle."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_bodyScoreReveal"].exists)
        XCTAssertFalse(app.staticTexts["Splitting fat from muscle"].exists)

        // 182 lb at 18% body fat: 33 lb fat, 149 lb lean, labeled as an entered value.
        let summary = app.descendants(matching: .any)["body_score_reveal_fat_vs_muscle"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Fat 33 lb. Lean mass 149 lb. Body fat 18%. Body fat you entered.")
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Body Score"))
                .firstMatch.exists,
            "The reveal answers fat vs muscle, not a 0-100 score"
        )
        XCTAssertFalse(app.buttons["Share my score"].exists, "One primary action")
        attachScreenshot(named: "first-run-manual-reveal", from: app)
    }

    private func continueFromRevealToProfile(in app: XCUIApplication) {
        let continueButton = app.buttons["body_score_reveal_continue_button"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertTrue(continueButton.isHittable)
        continueButton.tap()

        XCTAssertFalse(
            app.staticTexts["What should Home answer first?"].waitForExistence(timeout: 2),
            "The Home-mode question is gone"
        )
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_completeProfile"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["Last name"].exists)
    }

    // MARK: - Field helpers

    private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
