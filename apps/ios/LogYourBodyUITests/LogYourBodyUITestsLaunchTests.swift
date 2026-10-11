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

    func testPaywallLegalDoneMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPaywallFixture",
            "-lybUITestSuppressWhatsNew"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_paywall"].waitForExistence(timeout: 20))
        let terms = app.buttons["Terms of Service"].firstMatch
        XCTAssertTrue(terms.waitForExistence(timeout: 8))
        terms.tap()

        let done = app.descendants(matching: .any)["paywall_legal_done_button"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let frame = done.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Paywall legal done \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Paywall legal done \(frame)")
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_paywall"].waitForExistence(timeout: 5))
        XCTAssertFalse(done.exists)
    }

    func testTrainingSessionCloseMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestTrainingFixture",
            "-lybUITestResetTrainingFixture"
        ]
        app.launch()

        let open = app.buttons["training_fixture_open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        XCTAssertTrue(app.navigationBars["Live session"].waitForExistence(timeout: 8))
        let close = app.descendants(matching: .any)["training_live_session_close_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let frame = close.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Training close \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Training close \(frame)")
        close.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Live session"].exists)
    }

    func testExportCancelMeetsMinimumHitTarget() throws {
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

        let export = app.buttons["home_v2_settings_export"]
        var swipes = 0
        while !export.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(export.waitForExistence(timeout: 8))
        export.tap()

        XCTAssertTrue(app.staticTexts["Export your data"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["world_class_screen_exportData"].waitForExistence(timeout: 5)
        )
        let cancel = app.buttons["Cancel export"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let frame = cancel.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Cancel export \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Cancel export \(frame)")
        var exportAction = app.descendants(matching: .any)["export_data_action"]
        if !exportAction.waitForExistence(timeout: 2) {
            app.swipeUp()
            exportAction = app.descendants(matching: .any)["export_data_action"]
        }
        XCTAssertTrue(
            exportAction.waitForExistence(timeout: 5),
            "export action missing; buttons \(app.buttons.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        let actionFrame = exportAction.frame
        XCTAssertGreaterThanOrEqual(actionFrame.width, 44, "Export action \(actionFrame)")
        XCTAssertGreaterThanOrEqual(actionFrame.height, 44, "Export action \(actionFrame)")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["world_class_screen_exportData"].waitForNonExistence(timeout: 5)
        )
    }
}
