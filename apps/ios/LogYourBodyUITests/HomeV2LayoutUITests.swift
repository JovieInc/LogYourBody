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
