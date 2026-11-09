import XCTest
import UIKit

extension LogYourBodyUITests {
    func testDatedStatsReadyHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "ready")
    }

    func testDatedStatsDenialHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "denial")
    }

    func testDatedStatsNoDataHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "no-data")
    }

    func testDatedStatsOfflineHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "offline")
    }

    func testDatedStatsStaleHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "stale")
    }

    func testDatedStatsConflictingHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "conflicting")
    }

    func testDatedStatsUnsafeDateHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "unsafe-date")
    }

    func testDatedStatsImpossibleDateHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "impossible-date")
    }

    func testDatedStatsExpiredDateHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "expired-date")
    }

    func testDatedStatsMaintenanceHasOneReachableRecovery() throws {
        assertDatedStatsRecovery(state: "maintenance")
    }

    private func assertDatedStatsRecovery(state: String) {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestHomeRollbackFixture", "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestPhotoTimelineAnalyticsFixture", "-lybUITestDatedTimelineFixture",
            "-lybUITestDatedStatsState", state, "-lybUITestChatFirstFixture"
        ])
        let surface = app.descendants(matching: .any)["dated_stats_\(state)"]
        XCTAssertTrue(surface.waitForExistence(timeout: 15), state)
        XCTAssertEqual(app.buttons.matching(identifier: "launch_next_action").count, 1, state)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard_body_score_hero"].exists)
        if state != "ready" {
            XCTAssertFalse(app.descendants(matching: .any)["dated_stats_drift"].exists, state)
        }
        let action = app.buttons["launch_next_action"]
        XCTAssertTrue(action.isHittable, state)
        attachScreenshot(named: "dated-stats-\(state)", from: app)
        action.tap()
        switch state {
        case "unsafe-date", "impossible-date", "expired-date", "maintenance":
            let date = app.textFields["launch_outcome_date"]
            XCTAssertTrue(date.waitForExistence(timeout: 8), state)
            XCTAssertEqual(date.value as? String,
                           state == "expired-date" ? "2026-10-01" : state == "impossible-date" ? "2026-11-08" : "2026-12-27")
            XCTAssertTrue(app.switches["launch_outcome_maintenance"].exists)
            app.buttons["launch_outcome_cancel"].tap()
            XCTAssertTrue(surface.waitForExistence(timeout: 8), state)
        case "denial", "no-data", "stale", "conflicting":
            XCTAssertTrue(app.textFields["Weight value"].waitForExistence(timeout: 8), state)
            app.buttons["Cancel"].tap()
            XCTAssertTrue(surface.waitForExistence(timeout: 8), state)
        case "offline":
            XCTAssertTrue(surface.waitForExistence(timeout: 8))
        default:
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: surface)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 8), .completed)
        }
        assertDatedCoachRecovery(in: app, state: state)
    }

    private func assertDatedCoachRecovery(in app: XCUIApplication, state: String) {
        app.buttons["photo_timeline_root_menu"].tap()
        let timeline = app.buttons["photo_timeline_root_nav_timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        timeline.tap()
        let composer = app.textFields["chat_composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Review my dated outcome")
        app.buttons["chat_send_button"].tap()
        let coach = app.descendants(matching: .any)["launch_directive_coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 8), state)
        XCTAssertEqual(app.buttons.matching(identifier: "launch_next_action").count, 1, state)
        let action = app.buttons["launch_next_action"]
        if !action.isHittable {
            app.scrollViews["launch_directive_scroll"].swipeUp()
        }
        XCTAssertTrue(action.isHittable, state)
        attachScreenshot(named: "dated-coach-\(state)", from: app)
        action.tap()
        switch state {
        case "denial", "no-data", "stale", "conflicting":
            XCTAssertTrue(app.textFields["Weight value"].waitForExistence(timeout: 5), state)
            app.buttons["Cancel"].tap()
        case "offline":
            XCTAssertTrue(coach.waitForExistence(timeout: 5))
        default:
            // The arithmetic-only UI fixture owns no persisted outcome revision.
            // Even ready arithmetic must not produce an unbound saved action.
            XCTAssertTrue(app.textFields["launch_outcome_date"].waitForExistence(timeout: 5), state)
            app.buttons["launch_outcome_cancel"].tap()
        }
    }

    func testDatedStatsManualMeasurementDateEditExpiryAndAccountReturn() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestHomeRollbackFixture", "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestPhotoTimelineEmptyFixture", "-lybUITestPhotoTimelineAnalyticsFixture",
            "-lybUITestDatedTimelineFixture"
        ])
        let offline = app.descendants(matching: .any)["dated_stats_offline"]
        XCTAssertTrue(offline.waitForExistence(timeout: 15))
        app.buttons["launch_next_action"].tap()
        let target = app.textFields["launch_outcome_value"]
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        target.tap()
        target.typeText("76")
        let date = app.textFields["launch_outcome_date"]
        date.tap()
        date.typeText("2099-12-27")
        app.buttons["launch_outcome_save"].tap()
        XCTAssertTrue(offline.waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["dated_stats_drift"].exists)
        app.buttons["launch_next_action"].tap()
        let weight = app.textFields["Weight value"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8))
        weight.tap()
        weight.typeText("172")
        app.buttons["add_entry_save_button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["dated_stats_offline"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["dated_stats_measurement"].label.contains("kg"))
        app.buttons["dated_timeline_outcome"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "2000-01-01")
        app.buttons["launch_outcome_save"].tap()
        let expired = app.descendants(matching: .any)["dated_stats_expired-date"]
        XCTAssertTrue(expired.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(identifier: "launch_next_action").count, 1)
        app.buttons["launch_next_action"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        XCTAssertEqual(date.value as? String, "2000-01-01")
        app.buttons["launch_outcome_cancel"].tap()
        XCTAssertTrue(expired.waitForExistence(timeout: 8))
        app.terminate()
        app.launch() // Existing fixture rotates accounts on each launch.
        XCTAssertTrue(offline.waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["dated_stats_target"].exists)
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
