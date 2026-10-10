import XCTest

/// Guards the Home dock against content that exceeds a compact viewport.
final class HomeV2LayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPhotoOfflineDockIsFullyVisibleAndOpensLogSheet() {
        let app = launch(photo: true, state: "Offline")
        assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "photo-offline-dock")
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
    }

    func testPhotoOfflineAtLargestTextKeepsDockPinnedAndDetailsReachable() {
        let app = launch(photo: true, state: "Offline", largestText: true)
        assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "photo-offline-largest-text")
        assertReachableByScrolling("home_v2_all_photos_row", in: app)
        assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "photo-offline-largest-text-scrolled")
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
    }

    func testPhotoHealthOffAtLargestTextKeepsConnectDockVisible() {
        let app = launch(photo: true, state: "HealthOff", largestText: true)
        assertDockVisible(in: app, identifier: "home_v2_connect_health", screenshot: "photo-health-off-largest-text")
        assertHealthLabelCanWrap(in: app)
        assertReachableByScrolling("home_v2_all_photos_row", in: app)
        assertDockVisible(in: app, identifier: "home_v2_connect_health", screenshot: "photo-health-off-largest-text-scrolled")
    }

    func testMetricOfflineAtLargestTextKeepsLogDockAndDetailsReachable() {
        let app = launch(photo: false, state: "Offline", largestText: true)
        assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "metric-offline-largest-text")
        assertReachableByScrolling("home_v2_today_details", in: app)
        assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "metric-offline-largest-text-scrolled")
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
    }

    func testMetricHealthOffAtLargestTextKeepsManualLoggingReachable() {
        let app = launch(photo: false, state: "HealthOff", largestText: true)
        assertDockVisible(in: app, identifier: "home_v2_connect_health", screenshot: "metric-health-off-largest-text")
        assertHealthLabelCanWrap(in: app)
        assertReachableByScrolling("home_v2_today_details", in: app)
        assertDockVisible(in: app, identifier: "home_v2_connect_health", screenshot: "metric-health-off-largest-text-scrolled")
        app.buttons["home_v2_today_details"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
    }

    func testLogSheetHasOneHeadingAndKeepsEntryControls() {
        let app = launch(photo: false, state: "Offline")
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
        capture(app, named: "single-log-weight-heading")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Log weight")).count, 1)
        XCTAssertTrue(app.segmentedControls.firstMatch.exists)
        XCTAssertTrue(app.buttons["home_v2_log_sheet_plus"].exists)
        XCTAssertTrue(app.buttons["home_v2_log_sheet_save"].exists)
    }

    func testLogSheetEditsUnitsWithKeyboardAndCancelsWithoutChangingHome() {
        let app = launch(photo: false, state: "Offline")
        let originalWeight = app.descendants(matching: .any)["home_v2_weight_value"].label
        app.buttons["home_v2_log_weight"].tap()
        let field = app.textFields["home_v2_log_sheet_value"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertTrue(app.datePickers["home_v2_log_sheet_date"].exists)
        capture(app, named: "polished-log-weight-compact")

        let unit = app.buttons["home_v2_log_sheet_unit"]
        XCTAssertTrue(unit.isHittable)
        unit.tap()
        app.buttons["kg"].tap()
        XCTAssertEqual(unit.value as? String, "kg")
        unit.tap()
        app.buttons["lbs"].tap()
        XCTAssertEqual(unit.value as? String, "lbs")

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "182.4")
        XCTAssertEqual(field.value as? String, "182.4")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let save = app.buttons["home_v2_log_sheet_save"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture(app, named: "polished-log-weight-keyboard")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["home_v2_log_weight"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["home_v2_weight_value"].label, originalWeight)
        XCTAssertFalse(app.buttons["home_v2_undo"].exists)
    }

    func testLogSheetAtLargestTextKeepsValueAndDetailsReachable() {
        let app = launch(photo: false, state: "Offline", largestText: true)
        app.buttons["home_v2_log_weight"].tap()
        let field = app.textFields["home_v2_log_sheet_value"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertTrue(field.isHittable)
        capture(app, named: "polished-log-weight-largest-text")

        let scroll = app.scrollViews["home_v2_log_sheet_content"]
        let details = app.buttons["home_v2_log_sheet_details"]
        for _ in 0..<6 where !details.isHittable || !scroll.frame.contains(details.frame) {
            scroll.swipeUp()
        }
        XCTAssertTrue(details.isHittable)
        XCTAssertTrue(scroll.frame.contains(details.frame))
        let save = app.buttons["home_v2_log_sheet_save"]
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(save.frame))
        capture(app, named: "polished-log-weight-largest-text-scrolled")
        details.tap()
        XCTAssertTrue(app.staticTexts["Enter body fat percentage"].waitForExistence(timeout: 5))
    }

    private func launch(photo: Bool, state: String, largestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture",
            photo ? "-lybUITestHomeV2PhotoFixture" : "-lybUITestHomeV2Fixture",
            "-lybUITestHomeV2\(state)Fixture",
            "-lybUITestSuppressWhatsNew"
        ]
        if largestText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
        app.launch()
        let marker = photo ? "home_v2_photo_stage" : "home_v2_metric_first"
        XCTAssertTrue(app.descendants(matching: .any)[marker].waitForExistence(timeout: 30))
        return app
    }

    private func assertDockVisible(in app: XCUIApplication, identifier: String, screenshot: String) {
        let dock = app.buttons[identifier]
        XCTAssertTrue(dock.waitForExistence(timeout: 5))
        capture(app, named: screenshot)
        XCTAssertGreaterThanOrEqual(dock.frame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(dock.frame), "The complete dock must fit: \(dock.frame)")
        XCTAssertTrue(dock.isHittable, "The pinned dock must be tappable without scrolling")
    }

    private func assertReachableByScrolling(_ identifier: String, in app: XCUIApplication) {
        let scroll = app.scrollViews["home_v2_content_scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let target = app.buttons[identifier]
        for _ in 0..<6 where !target.isHittable || !scroll.frame.contains(target.frame) {
            scroll.swipeUp()
        }
        XCTAssertTrue(target.isHittable, "Home details must remain reachable with large text")
        XCTAssertTrue(scroll.frame.contains(target.frame), "Home details must scroll above the dock")
    }

    private func assertHealthLabelCanWrap(in app: XCUIApplication) {
        let dock = app.buttons["home_v2_connect_health"]
        XCTAssertEqual(dock.label, "Connect Apple Health")
        XCTAssertGreaterThan(
            dock.frame.height, 70,
            "At the largest text size, the full Health label needs a taller button instead of an ellipsis"
        )
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
