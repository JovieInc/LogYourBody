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

    func testTrainingEnrollmentCloseMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestTrainingFixture", "-lybUITestResetTrainingFixture"]
        app.launch()

        let open = app.buttons["training_fixture_enroll"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        XCTAssertTrue(app.navigationBars["Training coach"].waitForExistence(timeout: 8))
        let close = app.descendants(matching: .any)["training_enroll_close_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let frame = close.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Training enrollment close \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Training enrollment close \(frame)")
        close.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Training coach"].exists)
    }

    func testVoiceReviewCancelMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestTrainingFixture", "-lybUITestResetTrainingFixture"]
        app.launch()

        let open = app.buttons["training_fixture_voice_review"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        XCTAssertTrue(app.navigationBars["Review set"].waitForExistence(timeout: 8))
        let cancel = app.descendants(matching: .any)["voice_set_review_cancel_button"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let frame = cancel.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Voice review cancel \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Voice review cancel \(frame)")
        cancel.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Review set"].exists)
    }

    func testDexaPDFCloseMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestFullDashboardFixture",
            "-lybUITestDexaPDFSheetFixture",
            "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["legacy_full_dashboard_beta"].waitForExistence(timeout: 20))
        let settings = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Open profile and settings")
        ).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let integrations = app.descendants(matching: .any)["settings_integrations_link"]
        scrollUntilHittable(integrations, in: app)
        XCTAssertTrue(integrations.waitForExistence(timeout: 8))
        integrations.tap()

        let dexa = app.buttons["integrations_bodyspec_link"]
        scrollUntilHittable(dexa, in: app)
        XCTAssertTrue(dexa.waitForExistence(timeout: 8))
        dexa.tap()

        let importButton = app.buttons["body_spec_pdf_import"]
        scrollUntilHittable(importButton, in: app)
        XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        importButton.tap()

        XCTAssertTrue(app.navigationBars["Import scan PDF"].waitForExistence(timeout: 8))
        let close = app.descendants(matching: .any)["dexa_pdf_import_close_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let frame = close.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "DEXA PDF close \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "DEXA PDF close \(frame)")
        close.tap()
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Import scan PDF"].exists)
    }

    func testSyncDetailsCloseMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestFullDashboardFixture",
            "-lybUITestSyncDetailsFixture",
            "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["legacy_full_dashboard_beta"].waitForExistence(timeout: 20))
        let status = app.descendants(matching: .any)["dashboard_sync_status"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        status.tap()

        XCTAssertTrue(app.navigationBars["Sync"].waitForExistence(timeout: 8))
        let close = app.descendants(matching: .any)["dashboard_sync_close_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let frame = close.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Sync close \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Sync close \(frame)")
        close.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Sync"].exists)
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
    }
}
