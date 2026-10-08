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

    func testFfmiInfoDoneMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestBodyScoreOnboardingFixture",
            "-lybUITestSuppressWhatsNew"
        ]
        app.launch()

        let start = app.buttons["body_score_onboarding_start_button"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let male = app.buttons["Male"]
        XCTAssertTrue(male.waitForExistence(timeout: 8))
        male.tap()
        app.buttons["body_score_onboarding_basics_continue_button"].tap()

        XCTAssertTrue(app.staticTexts["How tall are you?"].waitForExistence(timeout: 8))
        let why = app.buttons["Why we ask"]
        XCTAssertTrue(why.waitForExistence(timeout: 5))
        why.tap()

        let info = app.buttons["What's FFMI?"]
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        info.tap()

        let done = app.descendants(matching: .any)["ffmi_info_done_button"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let frame = done.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "FFMI done \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "FFMI done \(frame)")
        done.tap()
        XCTAssertFalse(done.exists)
    }
}
