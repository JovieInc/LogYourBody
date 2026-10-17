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
        let graphic = app.staticTexts["home_v2_composition_sentence"]
        XCTAssertTrue(graphic.waitForExistence(timeout: 30))
        XCTAssertTrue(graphic.label.contains("15.8%"))
        XCTAssertTrue(graphic.label.contains("Visual estimate"))
        XCTAssertFalse(graphic.label.contains("muscle"))
        let selected = app.descendants(matching: .any)["home_v2_selected_body_fat_graphic"]
        XCTAssertTrue(selected.exists)
        XCTAssertEqual(selected.label, "Body fat, 15.8 %. Visual estimate")
        XCTAssertFalse(selected.label.contains("muscle"))
        capture(app, named: "editorial-visual-estimate")
        assertReachableByScrolling("home_v2_view_progress", in: app)
        app.buttons["home_v2_view_progress"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_progress_value"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["home_v2_progress_tab_body_fat"].isSelected,
                      "Generic Progress opens body fat; explicit metric taps choose their own workspace")
        capture(app, named: "revealed-link-progress-destination")
    }

    func testEditorialWeightOnlyHeroShowsActualSparseReadings() throws {
        for largestText in [false, true] {
            let app = launchEditorial(extra: ["-lybUITestHomeV2WeightOnlyHeroFixture"], largestText: largestText)
            selectHeroMetric("Weight", in: app)
            let graphic = app.descendants(matching: .any)["home_v2_editorial_card"]
            XCTAssertTrue(graphic.waitForExistence(timeout: 30))
            let summary = try uniqueWeightBranch(in: app, identifier: "home_v2_weight_graphic")
            XCTAssertEqual(summary.label, "Weight, 181.0 lb. Recorded")
            XCTAssertTrue(summary.staticTexts["4 recorded weight entries in the preceding 30 days · lb"].exists)
            XCTAssertEqual(app.staticTexts["home_v2_composition_sentence"].label, "Body fat unavailable at this time.")
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_review_graphic"].exists)
            XCTAssertEqual(graphic.frame.width, app.windows.firstMatch.frame.width, accuracy: 1)
            XCTAssertEqual(graphic.frame.height, graphic.frame.width / 0.8, accuracy: 1)
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_body_fat_graphic"].exists)
            captureWeightBranch(app, named: largestText ? "editorial-weight-only-ax5" : "editorial-weight-only")
            assertReachableByScrolling("home_v2_today_details", in: app)
            capture(app, named: largestText ? "editorial-weight-only-ax5-scrolled" : "editorial-weight-only-scrolled")
            app.terminate()
        }
    }

    func testEditorialSingleWeightDoesNotInventAHistory() throws {
        let launchedAt = Date()
        let app = launchEditorial(extra: ["-lybUITestHomeV2SingleWeightHeroFixture"])
        selectHeroMetric("Weight", in: app)
        let graphic = app.descendants(matching: .any)["home_v2_editorial_card"]
        XCTAssertTrue(graphic.waitForExistence(timeout: 30))
        let summary = try uniqueWeightBranch(in: app, identifier: "home_v2_weight_graphic")
        XCTAssertEqual(summary.label, "Weight, 181.0 lb. Recorded")
        XCTAssertTrue(summary.staticTexts["1 recorded weight entry in the preceding 30 days · lb"].exists)
        XCTAssertEqual(app.staticTexts["home_v2_composition_sentence"].label, "Body fat unavailable at this time.")
        XCTAssertEqual(app.staticTexts["home_v2_weight_hero_value"].label, "181.0")
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_plot"].exists,
                       "One exact reading must remain a value, not a history plot")
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_review_graphic"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_body_fat_graphic"].exists)
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "181.0")
        XCTAssertEqual(app.staticTexts["home_v2_change_sentence"].label, "Weight · No 30-day trend yet")
        assertSingleReadingRulerShowsToday(in: app, launchedAt: launchedAt)
        captureWeightBranch(app, named: "editorial-single-weight")
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
                let bodyFat = app.staticTexts["home_v2_composition_sentence"]
                XCTAssertTrue(bodyFat.label.contains("15.8%"))
                XCTAssertTrue(bodyFat.label.contains("Recorded"))
                XCTAssertEqual(app.staticTexts["home_v2_actual_photo_date"].label, "No photo this day")
            }
            XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "181.0")
            XCTAssertFalse(app.staticTexts["home_v2_change_sentence"].exists,
                           "A body-fat-led card must not restore the removed weight-trend headline")
            XCTAssertFalse(app.staticTexts["No change in 30 days"].exists)
            assertSingleReadingRulerShowsToday(in: app, launchedAt: launchedAt)
            capture(app, named: photo ? "editorial-single-reading-photo" : "editorial-single-reading-body-fat")
            assertSelectedMomentEvidence(["Body fat", "Entered by you"], in: app)
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
            let primary = app.descendants(matching: .any)[photo ? "home_v2_photo_stage" : "home_v2_editorial_card"]
            XCTAssertTrue(primary.waitForExistence(timeout: 30))
            let composition = app.staticTexts["home_v2_composition_sentence"]
            XCTAssertTrue(composition.waitForExistence(timeout: 8))
            XCTAssertTrue(composition.label.contains("15.8%"), composition.label)
            XCTAssertTrue(composition.label.contains("Recorded"), composition.label)
            XCTAssertFalse(app.staticTexts["home_v2_change_sentence"].exists)
            XCTAssertEqual(app.buttons["home_v2_log_weight"].label, "Log check-in")
            if !photo {
                let summary = app.descendants(matching: .any).matching(identifier: "home_v2_selected_body_fat_graphic")
                XCTAssertEqual(summary.count, 1)
                XCTAssertEqual(summary.element.label, "Body fat, 15.8 %. Recorded")
                XCTAssertFalse(summary.element.label.contains("Body fat not logged"))
                XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_graphic"].exists,
                               "The default body-fat hero must not silently become a weight graphic")
            }
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
            assertSelectedMomentEvidence(["Body fat", "Entered by you"], in: app)
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
        let graphic = app.staticTexts["home_v2_composition_sentence"]
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
            for: NSPredicate(format: "label CONTAINS %@", "17.0%"), evaluatedWith: graphic
        )
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 8), .completed)
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, weight)
        XCTAssertEqual(app.staticTexts["home_v2_ffmi_value"].label, "21.6")
        XCTAssertTrue(graphic.label.contains("Recorded"))
        XCTAssertFalse(app.buttons["home_v2_undo"].exists)
        XCTAssertFalse(app.buttons["home_v2_done"].exists)
        XCTAssertFalse(app.staticTexts["home_v2_logged_sentence"].exists)
        capture(app, named: "composition-body-fat-save-data")
        assertSelectedMomentEvidence(["Body fat", "Entered by you"], in: app)
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
            recordCompositionPhase("\(item.name)-before-launch")
            let app = launchEditorial(fixture: item.fixture, extra: item.extra, largestText: true)
            recordCompositionPhase("\(item.name)-after-launch")
            XCTAssertTrue(app.descendants(matching: .any)["home_v2_editorial_card"].waitForExistence(timeout: 30))
            assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "composition-ax5-\(item.name)-primary")
            // Pinned controls do not move while this fixture's content scrolls.
            // Capture their viewport once, rather than resolving the same AX trees for every metric.
            let viewport = homeDetailsViewport(in: app)
            for metric in ["ffmi", "weight", "steps"] {
                assertReachableByScrolling("home_v2_\(metric)_summary", in: app, viewport: viewport)
                let expected = metric == "ffmi" ? item.ffmi : (metric == "weight" ? "181.0" : "—")
                XCTAssertEqual(app.staticTexts["home_v2_\(metric)_value"].label, expected)
                capture(app, named: "composition-ax5-\(item.name)-\(metric)")
                recordCompositionPhase("\(item.name)-after-\(metric)")
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
                guard assertBodyFatDateCanOpenWithoutChangingValue(in: app) else { return }
            }
            let method = app.descendants(matching: .any).matching(identifier: "home_v2_body_fat_method").firstMatch
            assertSheetControlReachable(method, in: app, screenshot: "body-fat-ax5-method-before-\(value)")
            XCTAssertEqual(method.value as? String, "Entered by you")
            if changesMethod {
                method.tap()
                let dexa = app.buttons["DEXA"]
                XCTAssertTrue(dexa.waitForExistence(timeout: 5))
                dexa.tap()
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
            XCTAssertTrue(stage.label.contains("Recorded"))
            XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, weight)
            capture(app, named: "body-fat-ax5-saved-\(value)")
            assertSelectedMomentEvidence(["Body fat", changesMethod ? "From your DEXA scan" : "Entered by you"], in: app)
        }
        app.buttons["home_v2_log_weight"].tap()
        let method = app.descendants(matching: .any).matching(identifier: "home_v2_body_fat_method").firstMatch
        assertSheetControlReachable(method, in: app, screenshot: "body-fat-ax5-method-reopened")
        XCTAssertEqual(method.value as? String, "DEXA")
    }

    private func assertBodyFatDateCanOpenWithoutChangingValue(in app: XCUIApplication) -> Bool {
        let content = app.scrollViews["add_entry_content"]
        let compactPickers = content.datePickers
        guard content.waitForExistence(timeout: 8), compactPickers.count == 1 else {
            capture(app, named: "body-fat-ax5-compact-picker-ambiguous")
            XCTFail("The actual editor content must contain exactly one compact typed DatePicker")
            return false
        }
        // The open popup is a second DatePicker outside this content subtree.
        let picker = compactPickers.element
        assertSheetControlReachable(picker, in: app, screenshot: "body-fat-ax5-date-before")
        let originalValue = picker.value as? String
        XCTAssertNotNil(originalValue)
        picker.tap()
        capture(app, named: "body-fat-ax5-date-open")
        let popup = app.datePickers.containing(.button, identifier: "DatePicker.Show").element
        let dismiss = app.buttons["PopoverDismissRegion"]
        guard popup.waitForExistence(timeout: 5),
              dismiss.waitForExistence(timeout: 5), dismiss.isHittable else {
            XCTFail("The observed calendar popup must expose its dismissal region")
            return false
        }
        let region = dismiss.frame
        let save = app.buttons["home_v2_log_sheet_save"]
        let cancel = app.navigationBars.buttons["Cancel"]
        let gapBottom = min(save.frame.minY, content.frame.maxY)
        let point = CGPoint(x: content.frame.midX, y: (popup.frame.maxY + gapBottom) / 2)
        let controlFrames = content.buttons.allElementsBoundByIndex.map(\.frame) +
            content.textFields.allElementsBoundByIndex.map(\.frame)
        capture(app, named: "body-fat-ax5-before-popup-dismiss")
        let target = XCTAttachment(string:
            "popup=\(popup.frame), content=\(content.frame), save=\(save.frame), " +
            "cancel=\(cancel.frame), point=\(point)\n" + app.debugDescription)
        target.name = "body-fat-ax5-popup-dismiss-geometry"
        target.lifetime = .keepAlways
        add(target)
        guard content.exists, save.exists, cancel.exists, gapBottom - popup.frame.maxY >= 44,
              region.insetBy(dx: 24, dy: 24).contains(point),
              content.frame.insetBy(dx: 12, dy: 12).contains(point),
              !controlFrames.contains(where: { $0.contains(point) }),
              !popup.frame.contains(point), !save.frame.contains(point),
              !cancel.frame.contains(point), !picker.frame.contains(point) else {
            XCTFail("Dismiss only in the observed content gap outside the popup, picker, Save and Cancel")
            return false
        }
        dismiss.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - region.minX, dy: point.y - region.minY)).tap()
        guard dismiss.waitForNonExistence(timeout: 5), !popup.exists else {
            capture(app, named: "body-fat-ax5-popup-not-dismissed")
            XCTFail("Close the actual calendar popup before querying the compact picker geometry")
            return false
        }
        XCTAssertEqual(picker.value as? String, originalValue, "Opening the calendar must preserve the selected day")
        assertSheetControlReachable(picker, in: app, screenshot: "body-fat-ax5-date-dismissed")
        return true
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

    func testHistoricalOnlyDataKeepsSourceReadingsReachableAtLargestText() {
        let app = launchEditorial(extra: ["-lybUITestHomeV2HistoricalOnlyFixture"], largestText: true)

        XCTAssertTrue(app.descendants(matching: .any)["home_v2_editorial_card"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_day_zero"].exists)
        let ruler = app.descendants(matching: .any)["home_v2_timeline_scrubber"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 8))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(ruler.frame))
        assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "historical-only-selected-day")

        assertReachableByScrolling("home_v2_weight_summary", in: app)
        detailControl("home_v2_weight_summary", in: app).tap()
        let weightTab = app.buttons["home_v2_progress_tab_weight"]
        XCTAssertTrue(weightTab.waitForExistence(timeout: 8))
        XCTAssertTrue(weightTab.isSelected)
        let entries = app.buttons["home_v2_metric_entries"]
        XCTAssertTrue(entries.waitForExistence(timeout: 8))
        XCTAssertTrue(entries.isHittable)
        entries.tap()
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

    func testEditorialUnsupportedWeightKeepsRawValueAndReviewVisible() throws {
        for (largestText, withHistory) in [(false, false), (true, false), (false, true), (true, true)] {
            let app = launchEditorial(
                extra: ["-lybUITestHomeV2WeightReviewHeroFixture"] +
                    (withHistory ? ["-lybUITestHomeV2WeightReviewHistoryFixture"] : []),
                largestText: largestText
            )
            defer { app.terminate() }
            selectHeroMetric("Weight", in: app)
            let card = try uniqueWeightBranch(in: app, identifier: "home_v2_editorial_card")
            let review = try uniqueWeightBranch(in: app, identifier: "home_v2_weight_review_graphic")
            XCTAssertTrue(review.label.contains("39.68"), review.label)
            XCTAssertTrue(review.label.contains("lb"), review.label)
            XCTAssertTrue(review.label.contains(
                "Outside the supported logging range. Source value kept unchanged."
            ), review.label)
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_graphic"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_body_fat_graphic"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_plot"].exists,
                           "An unsupported source value must not be rendered as a supported trend")
            XCTAssertEqual(card.frame.width, app.windows.firstMatch.frame.width, accuracy: 1)
            XCTAssertEqual(card.frame.height, card.frame.width / 0.8, accuracy: 1)
            captureWeightBranch(app, named: (withHistory ? "editorial-weight-review-history-bf" : "editorial-weight-review") +
                                (largestText ? "-ax5" : ""))
            if withHistory {
                let composition = app.staticTexts["home_v2_composition_sentence"]
                XCTAssertTrue(composition.label.contains("15.8%"))
                XCTAssertTrue(composition.label.contains("Recorded"))
                app.buttons["home_v2_context_button"].tap()
                let rawWeight = app.descendants(matching: .any).matching(identifier: "home_v2_context_row_weight")
                let rawFat = app.descendants(matching: .any).matching(identifier: "home_v2_context_row_body_fat")
                XCTAssertTrue(rawWeight.element.waitForExistence(timeout: 8))
                XCTAssertEqual(rawWeight.count, 1)
                XCTAssertEqual(rawFat.count, 1)
                XCTAssertTrue(rawWeight.element.label.contains("39.68 lb"), rawWeight.element.label)
                XCTAssertTrue(rawWeight.element.label.contains("Apple Health"), rawWeight.element.label)
                XCTAssertTrue(rawFat.element.label.contains("15.8%"), rawFat.element.label)
                XCTAssertTrue(rawFat.element.label.contains("Typed"), rawFat.element.label)
                captureWeightBranch(
                    app,
                    named: largestText ? "review-history-bf-raw-context-ax5" : "review-history-bf-raw-context"
                )
                app.buttons["home_v2_context_close"].tap()
                let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    !app.staticTexts["home_v2_context"].exists
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
            }
            assertDockVisible(in: app, identifier: "home_v2_log_weight", screenshot: "weight-review-dock")
        }
    }

    func testSelectedMomentUnavailableWeightDoesNotCarryPastReading() throws {
        let launchedAt = Date()
        let app = launchEditorial(extra: ["-lybUITestHomeV2SelectedMissingWeightFixture"])
        defer { app.terminate() }
        selectHeroMetric("Weight", in: app)
        _ = try uniqueWeightBranch(in: app, identifier: "home_v2_selected_values_unavailable")
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "—")
        XCTAssertTrue(app.staticTexts["home_v2_selected_weight_unavailable"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_graphic"].exists)
        XCTAssertFalse(app.staticTexts["home_v2_weight_hero_value"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_plot"].exists)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        XCTAssertEqual(app.staticTexts["home_v2_photo_caption"].label, formatter.string(from: launchedAt))
        captureWeightBranch(app, named: "selected-unavailable-does-not-carry-past-weight")
        app.buttons["home_v2_context_button"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_context"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "home_v2_context_row_weight").count, 0)
        captureWeightBranch(app, named: "selected-unavailable-raw-context")
    }

    func testSelectedMomentBodyFatOnlyKeepsSourceWithoutFalseAbsence() throws {
        let app = launchEditorial(extra: ["-lybUITestHomeV2SelectedBodyFatOnlyFixture"])
        defer { app.terminate() }
        let graphic = try uniqueWeightBranch(in: app, identifier: "home_v2_selected_body_fat_graphic")
        XCTAssertEqual(graphic.label, "Body fat, 20.0 %. Recorded")
        XCTAssertEqual(app.staticTexts["home_v2_selected_body_fat_hero_value"].label, "20.0%")
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "—")
        XCTAssertTrue(detailControl("home_v2_weight_summary", in: app).staticTexts["Not logged"].exists)
        XCTAssertFalse(app.staticTexts["No weight or body fat logged."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_weight_graphic"].exists)
        captureWeightBranch(app, named: "selected-body-fat-only-truth")
        assertSelectedMomentEvidence(["Body fat", "Entered by you", "Weight unavailable at this time."], in: app)
        app.buttons["home_v2_context_button"].tap()
        let rawFat = app.descendants(matching: .any).matching(identifier: "home_v2_context_row_body_fat")
        XCTAssertTrue(rawFat.element.waitForExistence(timeout: 8))
        XCTAssertEqual(rawFat.count, 1)
        XCTAssertTrue(rawFat.element.label.contains("20.0%"), rawFat.element.label)
        XCTAssertTrue(rawFat.element.label.contains("Typed"), rawFat.element.label)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "home_v2_context_row_weight").count, 0)
        captureWeightBranch(app, named: "selected-body-fat-only-raw-context")
    }

    func testSelectedInferredWeightHasRealFocusWithZeroPastSamples() throws {
        try assertSelectedInferredWeightFocus(priorDays: 40)
    }

    func testSelectedInferredWeightHasRealFocusWithOnePastSample() throws {
        try assertSelectedInferredWeightFocus(priorDays: 10)
    }

    private func assertSelectedInferredWeightFocus(priorDays: Int) throws {
        let launchedAt = Date()
        let zero = priorDays == 40
        let app = launchEditorial(extra: [
            zero ? "-lybUITestHomeV2InferredWeightZeroPriorFixture" : "-lybUITestHomeV2InferredWeightOnePriorFixture"
        ])
        defer { app.terminate() }
        selectHeroMetric("Weight", in: app)
        let card = try uniqueWeightBranch(in: app, identifier: "home_v2_editorial_card")
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let initial = expectation(for: NSPredicate(format: "value == %@", "Entry 3 of 3"), evaluatedWith: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [initial], timeout: 8), .completed)
        card.swipeLeft()
        let selected = expectation(for: NSPredicate(format: "value == %@", "Entry 2 of 3"), evaluatedWith: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 8), .completed)
        XCTAssertTrue(Calendar.current.isDate(launchedAt, inSameDayAs: Date()))
        let captionDate = DateFormatter()
        captionDate.dateStyle = .medium
        captionDate.timeStyle = .none
        XCTAssertEqual(app.staticTexts["home_v2_photo_caption"].label, captionDate.string(from: launchedAt))
        let calendar = Calendar.current
        let before = try XCTUnwrap(calendar.date(byAdding: .day, value: -priorDays, to: launchedAt))
        let after = try XCTUnwrap(calendar.date(byAdding: .day, value: 10, to: launchedAt))
        let afterAmount = zero ? 90.0 : 84.0
        let expectedKG = 80 + (afterAmount - 80) *
            launchedAt.timeIntervalSince(before) / after.timeIntervalSince(before)
        let expectedLB = String(format: "%.1f", expectedKG * 2.20462)
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, expectedLB)
        let graphic = try uniqueWeightBranch(in: app, identifier: "home_v2_weight_graphic")
        let history = zero ? "0 recorded weight entries" : "1 recorded weight entry"
        XCTAssertTrue(graphic.staticTexts[history + " in the preceding 30 days · lb"].exists)
        XCTAssertEqual(graphic.label, "Weight, \(expectedLB) lb. Inferred between recorded values")
        XCTAssertEqual(app.staticTexts["home_v2_composition_sentence"].label, "Body fat 20.0% · Recorded")
        let plot = try uniqueWeightBranch(in: app, identifier: "home_v2_weight_plot")
        // The placeholder has the same identifier; only the real rendered chart has scale/focus AX.
        let focus = try XCTUnwrap(plot.value as? String)
        XCTAssertTrue(focus.contains("Scale from"), focus)
        XCTAssertTrue(focus.contains(expectedLB), focus)
        XCTAssertTrue(focus.contains("inferred"), focus)
        XCTAssertTrue(focus.contains(launchedAt.formatted(date: .complete, time: .omitted)), focus)
        XCTAssertFalse(app.staticTexts["No supported weight history at this time."].exists)
        captureWeightBranch(app, named: zero ? "inferred-zero-prior-real-focus" : "inferred-one-prior-real-focus")
        assertReachableByScrolling("home_v2_hero_reading_detail", in: app)
        app.buttons["home_v2_hero_reading_detail"].tap()
        let detail = app.descendants(matching: .any)["home_v2_provenance_detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "80.00 kg")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                                                           String(format: "%.2f kg", afterAmount)
                )
            ).firstMatch.exists
        )
        XCTAssertTrue(
            detail.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Weight inferred between")).firstMatch
                .exists
        )
        XCTAssertTrue(detail.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Entered by you")).firstMatch.exists)
        captureWeightBranch(app, named: zero ? "inferred-zero-prior-anchor-provenance" : "inferred-one-prior-anchor-provenance")
    }

    /// Hero identity is an explicit user choice; sparse data must not choose it for the test.
    private func selectHeroMetric(_ title: String, in app: XCUIApplication) {
        let segmented = app.segmentedControls["home_v2_hero_metric_picker"]
        if segmented.waitForExistence(timeout: 3) {
            let option = segmented.buttons[title]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            XCTAssertTrue(option.isSelected, "The hero must retain the explicitly selected metric")
            return
        }
        // Accessibility text uses the same picker as a native menu.
        let picker = app.descendants(matching: .any).matching(identifier: "home_v2_hero_metric_picker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        let moment = app.descendants(matching: .any)["home_v2_selected_moment"]
        let selected = expectation(for: NSPredicate(format: "value CONTAINS %@", title + ", "), evaluatedWith: moment)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 8), .completed,
                       "The menu selection must become the selected moment's hero metric")
    }

    /// Provider names and original evidence live in details; Home shows only classification.
    private func assertSelectedMomentEvidence(_ fragments: [String], in app: XCUIApplication) {
        assertReachableByScrolling("home_v2_hero_reading_detail", in: app)
        app.buttons["home_v2_hero_reading_detail"].tap()
        let detail = app.descendants(matching: .any)["home_v2_provenance_detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        for fragment in fragments {
            let matching = detail.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment))
            XCTAssertEqual(matching.count, 1, "The selected moment must retain evidence: \(fragment)")
        }
        let done = app.buttons["home_v2_provenance_done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(detail.waitForNonExistence(timeout: 8))
    }

    private func uniqueWeightBranch(in app: XCUIApplication, identifier: String) throws -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(matches.element.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(matches.count, 1, "A weight witness must identify one mounted branch")
        return try XCTUnwrap(matches.count == 1 ? matches.allElementsBoundByIndex.first : nil)
    }

    private func captureWeightBranch(_ app: XCUIApplication, named name: String) {
        capture(app, named: name)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func launchEditorial(
        fixture: String = "-lybUITestHomeV2Fixture", extra: [String] = [], largestText: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.forwardActualXCTestContext()
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
            return app.otherElements[identifier].buttons.element
        }
        return app.buttons[identifier]
    }

    private func recordCompositionPhase(_ phase: String) {
        let timing = XCTAttachment(string: "epochSeconds=\(Date().timeIntervalSince1970)")
        timing.name = "composition-phase-" + phase
        timing.lifetime = .keepAlways
        add(timing)
    }

    private func homeDetailsViewport(in app: XCUIApplication) -> CGRect {
        let scroll = app.scrollViews["home_v2_content_scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let scrollFrame = scroll.frame
        // XCUI includes the covered safe-area inset in ScrollView.frame.
        let pinned = [app.otherElements["home_v2_timeline_scrubber"],
                      app.buttons["home_v2_log_weight"], app.buttons["home_v2_connect_health"]]
        let pinnedFrames = pinned.filter(\.exists).map(\.frame)
        let bottom = pinnedFrames.map(\.minY).min() ?? scrollFrame.maxY
        let viewport = CGRect(x: scrollFrame.minX, y: scrollFrame.minY, width: scrollFrame.width,
                              height: max(0, min(bottom, scrollFrame.maxY) - scrollFrame.minY))
        XCTAssertGreaterThan(viewport.height, 88, "Home must leave a usable scrolling viewport")
        let geometry = XCTAttachment(string: "viewport=\(viewport), pinned=\(pinnedFrames)")
        geometry.name = "home-details-pinned-viewport"
        geometry.lifetime = .keepAlways
        add(geometry)
        return viewport
    }

    private func assertReachableByScrolling(
        _ identifier: String, in app: XCUIApplication, viewport suppliedViewport: CGRect? = nil
    ) {
        let viewport = suppliedViewport ?? homeDetailsViewport(in: app)
        let target = detailControl(identifier, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let attempts = scrollToContain(target, in: viewport, app: app)
        let targetFrame = target.frame
        let hittable = target.isHittable
        let frames = "target=\(targetFrame), viewport=\(viewport)\n" + attempts.joined(separator: "\n")
        let geometry = XCTAttachment(string: frames)
        geometry.name = "visible-link-geometry-\(identifier)"
        geometry.lifetime = .keepAlways
        add(geometry)
        capture(app, named: "reachable-\(identifier)")
        XCTAssertTrue(hittable, "Home details must remain reachable with large text: \(frames)")
        XCTAssertTrue(viewport.contains(targetFrame), "The complete target must scroll above the pinned controls: \(frames)")
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
