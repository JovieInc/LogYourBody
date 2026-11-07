import XCTest
import UIKit

extension LogYourBodyUITests {
    func testDatedOutcomeFirstLaunchCancelBackAndManualBaseline() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestBodyScoreOnboardingFixture", "-lybUITestDatedOutcomeEntryFixture",
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestPhotoTimelineEmptyFixture", "-lybUITestDatedTimelineFixture"
        ])
        let promise = app.staticTexts["Pick a date. We build the plan backward from it and adjust every week."]
        XCTAssertTrue(promise.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["body_score_onboarding_import_scan_button"].exists)
        let next = app.buttons["dated_launch_continue"]
        next.tap()
        let date = app.textFields["launch_outcome_date"]
        let target = app.textFields["launch_outcome_value"]
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        target.tap()
        target.typeText("76")
        date.tap()
        date.typeText("2099-12-27")
        app.buttons["launch_outcome_cancel"].tap()
        XCTAssertTrue(promise.waitForExistence(timeout: 8))
        next.tap()
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        XCTAssertNotEqual(target.value as? String, "76", "Cancel must not persist a draft")
        target.tap()
        target.typeText("76")
        date.tap()
        date.typeText("2099-12-27")
        app.buttons["launch_outcome_save"].tap()
        let saved = app.staticTexts["dated_launch_saved_outcome"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertTrue(saved.label.contains("2099-12-27"))
        XCTAssertTrue(app.staticTexts["dated_outcome_pending"].exists)
        app.buttons["Edit outcome and date"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        XCTAssertEqual(date.value as? String, "2099-12-27")
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "2099-12-28")
        app.buttons["launch_outcome_cancel"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertTrue(saved.label.contains("2099-12-27"))
        app.buttons["Back"].tap()
        XCTAssertTrue(promise.waitForExistence(timeout: 8))
        next.tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        XCTAssertEqual(date.value as? String, "2099-12-27")
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "2099-12-28")
        app.buttons["launch_outcome_save"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertTrue(saved.label.contains("2099-12-28"))
        next.tap()
        let weight = app.textFields["Weight value"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8))
        weight.tap()
        weight.typeText("172")
        app.buttons["add_entry_save_button"].tap()
        XCTAssertTrue(app.buttons["dated_timeline_outcome"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["dated_timeline_outcome"].label.contains("2099-12-28"))
        attachScreenshot(named: "dated-launch-manual-baseline", from: app)
        app.terminate()
    }

    func testDatedOutcomeGateOffKeepsExistingFirstRun() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestBodyScoreOnboardingFixture"])
        XCTAssertTrue(app.buttons["body_score_onboarding_import_scan_button"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["dated_launch_continue"].exists)
        app.terminate()
    }

    func testDatedTimelineManualBaselineAndInterruptedPhotoReturn() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestHomeRollbackFixture", "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestPhotoTimelineEmptyFixture", "-lybUITestDatedTimelineFixture"
        ])
        let next = app.buttons["launch_next_action"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        next.tap()
        let target = app.textFields["launch_outcome_value"]
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        target.tap()
        target.typeText("76")
        let date = app.textFields["launch_outcome_date"]
        date.tap()
        date.typeText("2099-12-27")
        app.buttons["launch_outcome_save"].tap()
        let saved = app.buttons["dated_timeline_outcome"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertTrue(saved.label.contains("2099-12-27"))
        XCTAssertTrue(app.staticTexts["No progress photo"].exists)
        app.buttons["launch_timeline_add_photo"].tap()
        XCTAssertTrue(app.buttons["progress_photo_attach_cancel_button"].waitForExistence(timeout: 8))
        app.buttons["progress_photo_attach_cancel_button"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 8), "Cancelling an optional import keeps the outcome")
        next.tap()
        let weight = app.textFields["Weight value"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8), "Offline and optional access cannot block manual entry")
        weight.tap()
        weight.typeText("172")
        app.buttons["add_entry_save_button"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["dated_timeline_provenance"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Hold the plan"].exists, "No policy was supplied")
        attachScreenshot(named: "dated-timeline-manual-baseline", from: app)
    }

    func testDatedTimelineExpiredOutcomeOpensEditorWithoutExtendingDate() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestHomeRollbackFixture", "-lybUITestPhotoTimelineHUDFixture", "-lybUITestDatedTimelineFixture"
        ])
        let next = app.buttons["launch_next_action"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        next.tap()
        let target = app.textFields["launch_outcome_value"]
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        target.tap()
        target.typeText("76")
        let date = app.textFields["launch_outcome_date"]
        date.tap()
        date.typeText("2000-01-01")
        app.buttons["launch_outcome_save"].tap()
        let saved = app.buttons["dated_timeline_outcome"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertTrue(saved.label.contains("2000-01-01"))
        XCTAssertEqual(next.label, "Choose a new date or maintenance")
        next.tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        XCTAssertEqual(date.value as? String, "2000-01-01")
        attachScreenshot(named: "dated-timeline-expiry-editor", from: app)
    }

    func testDatedTimelineSwipeProvenanceOfflineRetryAndAccountIsolation() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestHomeRollbackFixture", "-lybUITestPhotoTimelineHUDFixture", "-lybUITestDatedTimelineFixture"
        ])
        XCTAssertTrue(app.descendants(matching: .any)["dated_timeline_provenance"].waitForExistence(timeout: 15))
        app.buttons["launch_next_action"].tap()
        let target = app.textFields["launch_outcome_value"]
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        target.tap()
        target.typeText("76")
        let date = app.textFields["launch_outcome_date"]
        date.tap()
        date.typeText("2099-12-27")
        app.buttons["launch_outcome_save"].tap()
        let saved = app.buttons["dated_timeline_outcome"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["launch_next_action"].label, "Retry sync")
        app.buttons["launch_next_action"].tap()
        XCTAssertTrue(saved.exists)
        let scrubber = app.descendants(matching: .any)["launch_timeline_scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 8))
        scrubber.swipeRight()
        XCTAssertTrue(app.descendants(matching: .any)["dated_timeline_provenance"].exists)
        app.terminate()
        // The existing fixture deliberately creates a new account each launch.
        app.launch()
        XCTAssertTrue(app.buttons["launch_next_action"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["dated_timeline_outcome"].exists, "Another account must not inherit the saved goal")
    }
}
