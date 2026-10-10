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
        capture(app, named: "revealed-link-manual-log-destination")
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

    func testEditorialCardKeepsFullBleedGeometryWithPhotoDataAndNoMeasurements() {
        var expected: CGSize?
        let fixtures = ["-lybUITestHomeV2PhotoFixture", "-lybUITestHomeV2Fixture", "-lybUITestHomeV2EmptyFixture"]
        for fixture in fixtures {
            let app = launchEditorial(fixture: fixture)
            let card = app.descendants(matching: .any)["home_v2_editorial_card"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 30))
            XCTAssertEqual(card.frame.minX, app.windows.firstMatch.frame.minX, accuracy: 1)
            XCTAssertEqual(card.frame.width, app.windows.firstMatch.frame.width, accuracy: 1)
            XCTAssertEqual(card.frame.height, card.frame.width / 0.8, accuracy: 1)
            if let expected {
                XCTAssertEqual(card.frame.width, expected.width, accuracy: 1)
                XCTAssertEqual(card.frame.height, expected.height, accuracy: 1)
            } else {
                expected = card.frame.size
            }
            assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "editorial-\(fixture)")
            app.terminate()
        }
    }

    func testEditorialDataHeroLabelsVisualEstimate() {
        let app = launchEditorial(extra: ["-lybUITestHomeV2EstimateHeroFixture"])
        let graphic = app.descendants(matching: .any)["home_v2_body_fat_graphic"]
        XCTAssertTrue(graphic.waitForExistence(timeout: 30))
        XCTAssertTrue(graphic.label.contains("15.8 percent"))
        XCTAssertTrue(graphic.label.contains("Visual estimate"))
        XCTAssertFalse(graphic.label.contains("muscle"))
        capture(app, named: "editorial-visual-estimate")
        assertReachableByScrolling("home_v2_view_progress", in: app)
        app.buttons["home_v2_view_progress"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_progress_value"].waitForExistence(timeout: 8))
        capture(app, named: "revealed-link-progress-destination")
    }

    func testEditorialWeightOnlyHeroShowsActualSparseReadings() {
        for largestText in [false, true] {
            let app = launchEditorial(extra: ["-lybUITestHomeV2WeightOnlyHeroFixture"], largestText: largestText)
            let graphic = app.descendants(matching: .any)["home_v2_editorial_card"]
            XCTAssertTrue(graphic.waitForExistence(timeout: 30))
            let summary = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "4 recorded weight entries")
            ).firstMatch
            XCTAssertTrue(summary.waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertTrue(summary.label.contains("Latest 181.0 lb"), summary.label)
            XCTAssertEqual(graphic.frame.width, app.windows.firstMatch.frame.width, accuracy: 1)
            XCTAssertEqual(graphic.frame.height, graphic.frame.width / 0.8, accuracy: 1)
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_body_fat_graphic"].exists)
            capture(app, named: largestText ? "editorial-weight-only-ax5" : "editorial-weight-only")
            assertReachableByScrolling("home_v2_today_details", in: app)
            capture(app, named: largestText ? "editorial-weight-only-ax5-scrolled" : "editorial-weight-only-scrolled")
            app.terminate()
        }
    }

    func testEditorialSingleWeightDoesNotInventAHistory() {
        let app = launchEditorial(extra: ["-lybUITestHomeV2SingleWeightHeroFixture"])
        let graphic = app.descendants(matching: .any)["home_v2_editorial_card"]
        XCTAssertTrue(graphic.waitForExistence(timeout: 30))
        XCTAssertTrue(graphic.label.contains("1 recorded weight entry"))
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "181.0")
        XCTAssertEqual(app.staticTexts["home_v2_change_sentence"].label, "No 30-day trend yet")
        capture(app, named: "editorial-single-weight")
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
    }

    func testEditorialSingleReadingDoesNotClaimAWeightTrendBehindPhotoOrBodyFat() {
        for photo in [false, true] {
            let app = launchEditorial(
                fixture: photo ? "-lybUITestHomeV2PhotoFixture" : "-lybUITestHomeV2Fixture",
                extra: ["-lybUITestHomeV2SingleReadingFixture"]
            )
            XCTAssertTrue(app.descendants(matching: .any)["home_v2_editorial_card"].waitForExistence(timeout: 30))
            if photo {
                XCTAssertTrue(app.buttons["home_v2_photo_stage"].exists)
            } else {
                let bodyFat = app.descendants(matching: .any)["home_v2_body_fat_graphic"]
                XCTAssertTrue(bodyFat.label.contains("15.8 percent"))
                XCTAssertTrue(bodyFat.label.contains("Entered by you"))
            }
            XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "181.0")
            XCTAssertEqual(app.staticTexts["home_v2_change_sentence"].label, "No 30-day trend yet")
            XCTAssertFalse(app.staticTexts["No change in 30 days"].exists)
            capture(app, named: photo ? "editorial-single-reading-photo" : "editorial-single-reading-body-fat")
            app.terminate()
        }
    }

    func testEditorialEmptyAtLargestTextKeepsHealthAndLoggingReachable() {
        let app = launchEditorial(fixture: "-lybUITestHomeV2EmptyFixture", largestText: true)
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_day_zero"].waitForExistence(timeout: 30))
        assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "editorial-empty-largest-text")
        assertReachableByScrolling("home_v2_connect_health", in: app)
        capture(app, named: "editorial-empty-largest-text-scrolled")
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
    }

    private func launchEditorial(
        fixture: String = "-lybUITestHomeV2Fixture", extra: [String] = [], largestText: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestPhotoTimelineHUDFixture", fixture, "-lybUITestSuppressWhatsNew"] + extra
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
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
        let marker = photo ? "home_v2_photo_stage" : "home_v2_editorial_card"
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
        // XCUI includes the covered safe-area inset in ScrollView.frame. A tappable
        // point there can hit the ruler/dock instead of the intended content row.
        let pinned = [app.descendants(matching: .any)["home_v2_timeline_scrubber"],
                      app.buttons["home_v2_log_weight"], app.buttons["home_v2_connect_health"]]
        let bottom = pinned.filter(\.exists).map { $0.frame.minY }.min() ?? scroll.frame.maxY
        let viewport = CGRect(x: scroll.frame.minX, y: scroll.frame.minY, width: scroll.frame.width,
                              height: max(0, min(bottom, scroll.frame.maxY) - scroll.frame.minY))
        XCTAssertGreaterThan(viewport.height, 88, "Home must leave a usable scrolling viewport")
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 40))
        let end = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + 40))
        for _ in 0..<6 where !target.isHittable || !viewport.contains(target.frame) {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let frames = "target=\(target.frame), viewport=\(viewport), pinned=\(pinned.filter(\.exists).map { $0.frame })"
        let geometry = XCTAttachment(string: frames)
        geometry.name = "visible-link-geometry-\(identifier)"
        geometry.lifetime = .keepAlways
        add(geometry)
        capture(app, named: "reachable-\(identifier)")
        XCTAssertTrue(target.isHittable, "Home details must remain reachable with large text: \(frames)")
        XCTAssertTrue(viewport.contains(target.frame), "The complete target must scroll above the pinned controls: \(frames)")
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
