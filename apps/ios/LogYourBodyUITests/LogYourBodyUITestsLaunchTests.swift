//
// LogYourBodyUITestsLaunchTests.swift
// LogYourBody
//
import XCTest

final class LogYourBodyUITestsLaunchTests: XCTestCase {
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWeightGoalCancelMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestWeightLoggerMVPFixture",
            "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Weight log"].waitForExistence(timeout: 20))
        let settings = app.buttons["mvp_settings_button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let tracking = app.descendants(matching: .any)["settings_tracking_link"]
        var swipes = 0
        while !tracking.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(tracking.waitForExistence(timeout: 8))
        tracking.tap()

        let weightGoal = app.buttons["settings_weight_goal_edit_button"]
        swipes = 0
        while !weightGoal.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(weightGoal.waitForExistence(timeout: 8))
        weightGoal.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["settings_goal_editor_text_field"].waitForExistence(timeout: 8)
        )
        let cancel = app.buttons["Cancel editing"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let frame = cancel.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Goal cancel \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Goal cancel \(frame)")

        let save = app.descendants(matching: .any)["settings_goal_editor_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let saveFrame = save.frame
        XCTAssertGreaterThanOrEqual(saveFrame.width, 44, "Goal save \(saveFrame)")
        XCTAssertGreaterThanOrEqual(saveFrame.height, 44, "Goal save \(saveFrame)")
        cancel.tap()
        XCTAssertTrue(weightGoal.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["settings_goal_editor_text_field"].waitForNonExistence(timeout: 5)
        )
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
