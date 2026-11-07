import XCTest
import UIKit

extension LogYourBodyUITests {
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
