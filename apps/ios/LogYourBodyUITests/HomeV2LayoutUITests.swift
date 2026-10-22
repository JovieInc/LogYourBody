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
        selectWeightEntry(in: app)
        capture(app, named: "single-log-weight-heading")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Log weight")).count, 1)
        XCTAssertTrue(app.segmentedControls.firstMatch.exists)
        XCTAssertTrue(app.buttons["home_v2_log_sheet_plus"].exists)
        XCTAssertTrue(app.buttons["home_v2_log_sheet_save"].exists)
    }

    func testLogSheetEditsUnitsWithKeyboardAndCancelsWithoutChangingHome() {
        let app = launch(photo: false, state: "Offline")
        let originalWeight = app.staticTexts["home_v2_weight_value"].label
        app.buttons["home_v2_log_weight"].tap()
        selectWeightEntry(in: app)
        let field = app.textFields["home_v2_log_sheet_value"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertTrue(app.datePickers["home_v2_log_sheet_date"].exists)
        capture(app, named: "polished-log-weight-compact")

        let unit = app.buttons["home_v2_log_sheet_unit"]
        XCTAssertTrue(unit.isHittable)
        XCTAssertLessThanOrEqual(
            field.frame.maxX, unit.frame.minX + 1,
            "The value and unit must sit side by side without drawing over each other"
        )
        XCTAssertEqual(app.buttons["home_v2_log_sheet_save"].label, "Save")
        selectMenuOption("kg", from: unit, in: app)
        XCTAssertEqual(unit.value as? String, "kg")
        selectMenuOption("lbs", from: unit, in: app)
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
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, originalWeight)
        XCTAssertFalse(app.buttons["home_v2_undo"].exists)
    }

    func testLogSheetAtLargestTextKeepsValueAndDetailsReachable() {
        let app = launch(photo: false, state: "Offline", largestText: true)
        app.buttons["home_v2_log_weight"].tap()
        selectWeightEntry(in: app)
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
        XCTAssertTrue(app.buttons["home_v2_progress_tab_body_fat"].isSelected,
                      "Generic Progress opens body fat; explicit metric taps choose their own workspace")
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
        let launchedAt = Date()
        let app = launchEditorial(extra: ["-lybUITestHomeV2SingleWeightHeroFixture"])
        let graphic = app.descendants(matching: .any)["home_v2_editorial_card"]
        XCTAssertTrue(graphic.waitForExistence(timeout: 30))
        XCTAssertTrue(graphic.label.contains("1 recorded weight entry"))
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "181.0")
        XCTAssertEqual(app.staticTexts["home_v2_change_sentence"].label, "No 30-day trend yet")
        assertSingleReadingRulerShowsToday(in: app, launchedAt: launchedAt)
        capture(app, named: "editorial-single-weight")
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
    }

    func testEditorialSingleReadingDoesNotClaimAWeightTrendBehindPhotoOrBodyFat() {
        for photo in [false, true] {
            let launchedAt = Date()
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
            XCTAssertFalse(app.staticTexts["home_v2_change_sentence"].exists,
                           "A body-fat-led card must not restore the removed weight-trend headline")
            XCTAssertFalse(app.staticTexts["No change in 30 days"].exists)
            assertSingleReadingRulerShowsToday(in: app, launchedAt: launchedAt)
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

    func testCompositionHomeShowsBodyFatFirstAndHonestSupportingMetrics() {
        for photo in [false, true] {
            let app = launchEditorial(fixture: photo ? "-lybUITestHomeV2PhotoFixture" : "-lybUITestHomeV2Fixture")
            let primary = app.descendants(matching: .any)[photo ? "home_v2_photo_stage" : "home_v2_body_fat_graphic"]
            XCTAssertTrue(primary.waitForExistence(timeout: 30))
            XCTAssertTrue(primary.label.contains("15.8"), primary.label)
            XCTAssertTrue(primary.label.contains("Entered by you"), primary.label)
            XCTAssertFalse(app.staticTexts["home_v2_change_sentence"].exists)
            XCTAssertEqual(app.buttons["home_v2_log_weight"].label, "Log check-in")
            capture(app, named: photo ? "composition-photo-primary" : "composition-data-primary")

            assertReachableByScrolling("home_v2_ffmi_summary", in: app)
            XCTAssertEqual(app.staticTexts["home_v2_ffmi_value"].label, "21.9")
            assertReachableByScrolling("home_v2_weight_summary", in: app)
            XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "181.0")
            assertReachableByScrolling("home_v2_steps_summary", in: app)
            XCTAssertTrue(app.staticTexts["No step data"].waitForExistence(timeout: 8))
            XCTAssertEqual(app.staticTexts["home_v2_steps_value"].label, "—",
                           "The fixture has no daily step row; missing must not become zero or another day's total")
            capture(app, named: photo ? "composition-photo-context" : "composition-data-context")
            app.buttons["home_v2_log_weight"].tap()
            assertBodyFatEntry(in: app, expected: "15.8")
            app.terminate()
        }
    }

    func testSupportingMetricTapsOpenTheirOwnProgressWorkspace() {
        for metric in ["ffmi", "weight", "steps"] {
            let app = launchEditorial()
            XCTAssertTrue(app.descendants(matching: .any)["home_v2_editorial_card"].waitForExistence(timeout: 30))
            let identifier = "home_v2_\(metric)_summary"
            assertReachableByScrolling(identifier, in: app)
            detailControl(identifier, in: app).tap()
            let tab = app.buttons["home_v2_progress_tab_\(metric)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 8))
            XCTAssertTrue(tab.isSelected, "The \(metric) action must not fall back to generic body-fat Progress")
            XCTAssertTrue(app.descendants(matching: .any)["home_v2_progress_value"].exists)
            capture(app, named: "composition-progress-\(metric)")
            app.terminate()
        }
    }

    func testBodyFatCheckInRefreshesDataHeroWithoutSavingWeight() {
        let app = launchEditorial()
        let graphic = app.descendants(matching: .any)["home_v2_body_fat_graphic"]
        XCTAssertTrue(graphic.waitForExistence(timeout: 30))
        let weight = app.staticTexts["home_v2_weight_value"].label
        app.buttons["home_v2_log_weight"].tap()
        assertBodyFatEntry(in: app, expected: "15.8")
        let field = app.textFields["Body fat percentage value"]
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "17.0")
        let save = app.buttons["home_v2_log_sheet_save"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        save.tap()
        let refreshed = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "17.0 percent"), evaluatedWith: graphic
        )
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 8), .completed)
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, weight)
        XCTAssertEqual(app.staticTexts["home_v2_ffmi_value"].label, "21.6")
        XCTAssertTrue(graphic.label.contains("Entered by you"), "Editing a value must preserve its recorded method")
        XCTAssertFalse(app.buttons["home_v2_undo"].exists)
        XCTAssertFalse(app.buttons["home_v2_done"].exists)
        XCTAssertFalse(app.staticTexts["home_v2_logged_sentence"].exists)
        capture(app, named: "composition-body-fat-save-data")
        app.buttons["home_v2_log_weight"].tap()
        assertBodyFatEntry(in: app, expected: "17.0")
        capture(app, named: "composition-body-fat-method-after-save")
    }

    func testCompositionContextAtLargestTextKeepsEachSupportingMetricReachable() {
        let cases: [(name: String, fixture: String, extra: [String], ffmi: String)] = [
            ("data", "-lybUITestHomeV2Fixture", [], "21.9"),
            ("photo", "-lybUITestHomeV2PhotoFixture", [], "21.9"),
            ("estimate", "-lybUITestHomeV2Fixture", ["-lybUITestHomeV2EstimateHeroFixture"], "21.9"),
            ("single-weight", "-lybUITestHomeV2Fixture", ["-lybUITestHomeV2SingleWeightHeroFixture"], "—")
        ]
        for item in cases {
            let app = launchEditorial(fixture: item.fixture, extra: item.extra, largestText: true)
            XCTAssertTrue(app.descendants(matching: .any)["home_v2_editorial_card"].waitForExistence(timeout: 30))
            assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "composition-ax5-\(item.name)-primary")
            for metric in ["ffmi", "weight", "steps"] {
                assertReachableByScrolling("home_v2_\(metric)_summary", in: app)
                let expected = metric == "ffmi" ? item.ffmi : (metric == "weight" ? "181.0" : "—")
                XCTAssertEqual(app.staticTexts["home_v2_\(metric)_value"].label, expected)
                capture(app, named: "composition-ax5-\(item.name)-\(metric)")
            }
            app.terminate()
        }
    }

    func testBodyFatEditorAtLargestTextPreservesMethodUntilExplicitSelection() {
        let app = launchEditorial(fixture: "-lybUITestHomeV2PhotoFixture", largestText: true)
        let stage = app.buttons["home_v2_photo_stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 30))
        let weight = app.staticTexts["home_v2_weight_value"].label
        for (value, changesMethod) in [("17.0", false), ("18.0", true)] {
            app.buttons["home_v2_log_weight"].tap()
            XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
            if !changesMethod {
                assertBodyFatDateCanOpenWithoutChangingValue(in: app)
            }
            let method = app.descendants(matching: .any).matching(identifier: "home_v2_body_fat_method").firstMatch
            assertSheetControlReachable(method, in: app, screenshot: "body-fat-ax5-method-before-\(value)")
            XCTAssertEqual(method.value as? String, "Entered by you")
            if changesMethod {
                selectMenuOption("DEXA", from: method, in: app)
                XCTAssertEqual(method.value as? String, "DEXA")
            }
            let field = app.textFields["Body fat percentage value"]
            assertSheetControlReachable(field, in: app, screenshot: "body-fat-ax5-value-\(value)")
            field.tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + value)
            capture(app, named: "body-fat-ax5-keyboard-\(value)")
            let save = app.buttons["home_v2_log_sheet_save"]
            XCTAssertEqual(save.label, "Save Body Fat")
            XCTAssertTrue(save.isEnabled)
            XCTAssertTrue(save.isHittable)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(save.frame))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY)
            XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY)
            XCTAssertLessThanOrEqual(field.frame.maxY, save.frame.minY, "Save must not cover the edited reading")
            let viewport = app.scrollViews["add_entry_content"].frame
            XCTAssertTrue(viewport.contains(field.frame), "The full styled field must be inside the scroll viewport: \(field.frame), \(viewport)")
            save.tap()
            let updated = expectation(for: NSPredicate(format: "label CONTAINS %@", value), evaluatedWith: stage)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
            XCTAssertTrue(stage.label.contains(changesMethod ? "From your DEXA scan" : "Entered by you"))
            XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, weight)
            capture(app, named: "body-fat-ax5-saved-\(value)")
        }
        app.buttons["home_v2_log_weight"].tap()
        let method = app.descendants(matching: .any).matching(identifier: "home_v2_body_fat_method").firstMatch
        assertSheetControlReachable(method, in: app, screenshot: "body-fat-ax5-method-reopened")
        XCTAssertEqual(method.value as? String, "DEXA")
    }

    private func assertBodyFatDateCanOpenWithoutChangingValue(in app: XCUIApplication) {
        let picker = app.datePickers.firstMatch
        assertSheetControlReachable(picker, in: app, screenshot: "body-fat-ax5-date-before")
        let originalValue = picker.value as? String
        XCTAssertNotNil(originalValue)
        picker.tap()
        capture(app, named: "body-fat-ax5-date-open")
        app.staticTexts["home_v2_log_sheet"].tap()
        XCTAssertEqual(picker.value as? String, originalValue, "Opening the calendar must preserve the selected day")
        assertSheetControlReachable(picker, in: app, screenshot: "body-fat-ax5-date-dismissed")
    }

    private func assertSheetControlReachable(_ target: XCUIElement, in app: XCUIApplication, screenshot: String) {
        let scroll = app.scrollViews["add_entry_content"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let save = app.buttons["home_v2_log_sheet_save"]
        let viewport = CGRect(x: scroll.frame.minX, y: scroll.frame.minY, width: scroll.frame.width,
                              height: max(0, min(scroll.frame.maxY, save.frame.minY) - scroll.frame.minY))
        XCTAssertGreaterThan(viewport.height, 88)
        let attempts = scrollToContain(target, in: viewport, app: app)
        let geometry = XCTAttachment(string: attempts.joined(separator: "\n"))
        geometry.name = "sheet-control-geometry-\(screenshot)"
        geometry.lifetime = .keepAlways
        add(geometry)
        capture(app, named: screenshot)
        XCTAssertTrue(target.isHittable)
        XCTAssertTrue(viewport.contains(target.frame), "The complete control must be above Save: \(target.frame), \(viewport)")
    }

    private func assertBodyFatEntry(in app: XCUIApplication, expected: String) {
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons["Body Fat"].isSelected)
        let field = app.textFields["Body fat percentage value"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, expected)
        let method = app.descendants(matching: .any).matching(identifier: "home_v2_body_fat_method").firstMatch
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        XCTAssertEqual(method.value as? String, "Entered by you")
    }

    private func selectWeightEntry(in app: XCUIApplication) {
        let segment = app.segmentedControls.firstMatch.buttons["Weight"]
        XCTAssertTrue(segment.waitForExistence(timeout: 8))
        segment.tap()
        XCTAssertTrue(segment.isSelected)
    }

    private func selectMenuOption(_ label: String, from control: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(control.isHittable)
        control.tap()
        let menu = app.collectionViews.containing(.button, identifier: label).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let option = menu.buttons[label]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        // Native menus can extend below the window at large text sizes. Scroll
        // inside their visible bounds before acting on the complete option.
        let viewport = menu.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 0, dy: 8)
        XCTAssertGreaterThan(viewport.height, 88)
        let attempts = scrollToContain(option, in: viewport, app: app)
        XCTAssertTrue(option.isEnabled)
        XCTAssertGreaterThan(option.frame.width, 0)
        XCTAssertGreaterThan(option.frame.height, 0)
        XCTAssertTrue(viewport.contains(option.frame), attempts.joined(separator: "\n"))
        // iOS 26 can vend an invalid activation point for a visible menu item.
        // Use its verified native frame; the caller still checks the selection.
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5))
    }

    func testEditorialUnsupportedWeightKeepsRawValueAndReviewVisible() {
        for largestText in [false, true] {
            let app = launchEditorial(extra: ["-lybUITestHomeV2HistoricalOnlyFixture"], largestText: largestText)
            XCTAssertTrue(app.descendants(matching: .any)["home_v2_day_zero"].waitForExistence(timeout: 30))
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_review_graphic"].exists,
                           "A 2018 import must not be drawn as Today")
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_graphic"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_plot"].exists,
                           "An unsupported source value must not be rendered as a supported trend")
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_timeline_scrubber"].exists)
            assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "weight-review-dock-\(largestText)")
            // Today's details is empty for this historical import. Open the
            // exact saved entry to inspect its original value and provenance.
            app.buttons["photo_timeline_root_menu"].tap()
            app.buttons.matching(NSPredicate(format: "label == %@", "Entries")).firstMatch.tap()
            let rows = app.buttons.matching(identifier: "home_v2_entries_row")
            let imported = rows.matching(NSPredicate(format: "label CONTAINS %@", "17.99 kg")).firstMatch
            XCTAssertTrue(imported.waitForExistence(timeout: 8))
            imported.tap()
            let rawWeight = app.descendants(matching: .any).matching(identifier: "home_v2_context_row_weight")
            XCTAssertTrue(rawWeight.element.waitForExistence(timeout: 8))
            XCTAssertEqual(rawWeight.count, 1)
            XCTAssertTrue(rawWeight.element.label.contains("17.99 kg"), rawWeight.element.label)
            XCTAssertTrue(rawWeight.element.label.contains("Withings via Apple Health"), rawWeight.element.label)
            XCTAssertTrue(rawWeight.element.label.contains(
                "Outside the supported logging range. Source value kept unchanged."
            ), rawWeight.element.label)
            capture(app, named: "weight-review-context-\(largestText)")
            app.terminate()
        }
    }

    func testHistoricalOnlyDataKeepsSourceReadingsReachableAtLargestText() {
        let app = launchEditorial(extra: ["-lybUITestHomeV2HistoricalOnlyFixture"], largestText: true)

        XCTAssertTrue(app.descendants(matching: .any)["home_v2_day_zero"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_timeline_scrubber"].exists,
                       "Today does not scrub 2018 samples")
        assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "historical-only-today-empty")

        app.buttons["photo_timeline_root_menu"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "Entries")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_entries"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["November 2018"].exists)
        let rows = app.buttons.matching(identifier: "home_v2_entries_row")
        XCTAssertEqual(rows.count, 2)
        let sourceSample = rows.matching(NSPredicate(format: "label CONTAINS %@", "17.99 kg")).firstMatch
        XCTAssertTrue(sourceSample.exists)
        XCTAssertTrue(sourceSample.label.contains("Withings via Apple Health"))
        XCTAssertTrue(sourceSample.label.contains("Source value kept unchanged"))
        sourceSample.tap()

        let contextWeight = app.descendants(matching: .any)["home_v2_context_row_weight"]
        XCTAssertTrue(contextWeight.waitForExistence(timeout: 8))
        XCTAssertTrue(contextWeight.label.contains("17.99 kg"))
        XCTAssertTrue(contextWeight.label.contains("Withings via Apple Health"))
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

    private func assertSingleReadingRulerShowsToday(in app: XCUIApplication, launchedAt: Date) {
        let ruler = app.descendants(matching: .any)["home_v2_timeline_scrubber"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        let possibleDays = [launchedAt, Date()].map { formatter.string(from: $0) }
        XCTAssertTrue(possibleDays.contains(ruler.value as? String ?? ""), "The selected ruler date must be the saved day")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(ruler.frame), "The complete ruler must remain visible")
    }

    private func assertDockVisible(in app: XCUIApplication, identifier: String, screenshot: String) {
        let dock = app.buttons[identifier]
        XCTAssertTrue(dock.waitForExistence(timeout: 5))
        capture(app, named: screenshot)
        XCTAssertGreaterThanOrEqual(dock.frame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(dock.frame), "The complete dock must fit: \(dock.frame)")
        XCTAssertTrue(dock.isHittable, "The pinned dock must be tappable without scrolling")
    }

    private func detailControl(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        if identifier.hasSuffix("_summary") {
            // SwiftUI exposes the contained summary as an Other wrapping its real button.
            return app.otherElements[identifier].buttons.firstMatch
        }
        return app.buttons[identifier]
    }

    private func assertReachableByScrolling(_ identifier: String, in app: XCUIApplication) {
        let scroll = app.scrollViews["home_v2_content_scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let target = detailControl(identifier, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        // XCUI includes the covered safe-area inset in ScrollView.frame. A tappable
        // point there can hit the ruler/dock instead of the intended content row.
        let pinned = [app.descendants(matching: .any)["home_v2_timeline_scrubber"],
                      app.buttons["home_v2_log_weight"], app.buttons["home_v2_connect_health"]]
        let bottom = pinned.filter(\.exists).map { $0.frame.minY }.min() ?? scroll.frame.maxY
        let viewport = CGRect(x: scroll.frame.minX, y: scroll.frame.minY, width: scroll.frame.width,
                              height: max(0, min(bottom, scroll.frame.maxY) - scroll.frame.minY))
        XCTAssertGreaterThan(viewport.height, 88, "Home must leave a usable scrolling viewport")
        let attempts = scrollToContain(target, in: viewport, app: app)
        let frames = "target=\(target.frame), viewport=\(viewport), pinned=\(pinned.filter(\.exists).map { $0.frame })" +
            "\n" + attempts.joined(separator: "\n")
        let geometry = XCTAttachment(string: frames)
        geometry.name = "visible-link-geometry-\(identifier)"
        geometry.lifetime = .keepAlways
        add(geometry)
        capture(app, named: "reachable-\(identifier)")
        XCTAssertTrue(target.isHittable, "Home details must remain reachable with large text: \(frames)")
        XCTAssertTrue(viewport.contains(target.frame), "The complete target must scroll above the pinned controls: \(frames)")
    }

    private func scrollToContain(_ target: XCUIElement, in viewport: CGRect, app: XCUIApplication) -> [String] {
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        var attempts: [String] = []
        for attempt in 0..<6 {
            let frame = target.frame
            let hittable = target.isHittable
            attempts.append("attempt=\(attempt), target=\(frame), viewport=\(viewport), hittable=\(hittable)")
            if hittable && viewport.contains(frame) { break }
            if frame.height > viewport.height { break }
            let below = max(0, frame.maxY - viewport.maxY)
            let above = max(0, viewport.minY - frame.minY)
            if below == 0 && above == 0 { break }
            let upward = below > 0
            let margin = min(CGFloat(12), max(0, (viewport.height - frame.height) / 2))
            let distance = min(viewport.height - 80, (upward ? below : above) + margin)
            let startY = upward ? viewport.maxY - 40 : viewport.minY + 40
            let endY = startY + (upward ? -distance : distance)
            attempts.append("distance=\(distance), startY=\(startY), endY=\(endY)")
            let start = origin.withOffset(CGVector(dx: viewport.midX, dy: startY))
            let end = origin.withOffset(CGVector(dx: viewport.midX, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        return attempts
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
