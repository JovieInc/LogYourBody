import UIKit
import XCTest

final class HomeV2TimelineIntegrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPhotoHoldScrubsBothDirectionsThenAnotherHoldRestoresTap() {
        let app = launch(withSteps: true, holdScrub: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        assertTodayPagerStaysToday(pager)
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        let date = caption.label, initialWeight = weight.label
        assertStepCount(6_000, in: app)
        let mode = app.staticTexts["home_v2_photo_scrub_mode"]
        stage.press(forDuration: 0.7)
        XCTAssertFalse(mode.exists, "A short hold must not activate scrubbing")
        let close = app.buttons["home_v2_viewer_close"]
        if close.exists { close.tap() }
        let start = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 1.3, thenDragTo: start.withOffset(CGVector(dx: -stage.frame.width * 0.75, dy: 0)))
        XCTAssertFalse(mode.exists, "Today has one entry, so hold cannot scrub into history")
        XCTAssertEqual(caption.label, date)
        XCTAssertEqual(weight.label, initialWeight)
        assertStepCount(6_000, in: app)
        XCTAssertFalse(close.exists, "Holding must not open the photo viewer")
        stage.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testPhotoScrubResetsWhenNavigatingToTheMenuAndBack() {
        let app = launch(holdScrub: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        assertTodayPagerStaysToday(pager)
        stage.press(forDuration: 1.3)
        XCTAssertFalse(app.staticTexts["home_v2_photo_scrub_mode"].exists)
        app.buttons["photo_timeline_root_menu"].tap()
        let scrim = app.buttons["home_v2_sidebar_scrim"]
        XCTAssertTrue(scrim.waitForExistence(timeout: 5))
        scrim.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(pager.value as? String, "Entry 1 of 1")
        stage.tap()
        XCTAssertTrue(app.buttons["home_v2_viewer_close"].waitForExistence(timeout: 5))
    }

    func testHorizontalPhotoDragPagesPixelsAndMetricsWithoutOpeningViewer() throws {
        let app = launch(withSteps: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        assertTodayPagerStaysToday(pager)
        let steps = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Steps · ")).firstMatch
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        let firstCaption = caption.label, firstWeight = weight.label
        assertStepCount(6_000, in: app)
        let firstStepsLabel = steps.label
        XCTAssertTrue(firstCaption.hasPrefix(firstStepsLabel.replacingOccurrences(of: "Steps · ", with: "")))
        try assertPhotoColor(stage, red: true)
        drag(stage, from: 0.85, to: 0.3)
        XCTAssertEqual(caption.label, firstCaption, "A drag on Today cannot page into older samples")
        XCTAssertEqual(weight.label, firstWeight)
        XCTAssertEqual(steps.label, firstStepsLabel)
        assertStepCount(6_000, in: app)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        try assertPhotoColor(stage, red: true)
        capture(app, "timeline-today-stays-red")

        app.buttons["photo_timeline_root_menu"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "Entries")).firstMatch.tap()
        let rows = app.buttons.matching(identifier: "home_v2_entries_row")
        XCTAssertEqual(rows.count, 5, "Older samples stay available behind Entries")
        app.buttons["home_v2_entries_back"].tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        XCTAssertEqual(caption.label, firstCaption)
        assertStepCount(6_000, in: app)
        stage.tap()
        XCTAssertTrue(
            app.buttons["home_v2_viewer_close"].waitForExistence(timeout: 5), "An intentional tap still opens the photo"
        )
    }

    func testSelectedWeightOnlyDayNeverBorrowsTodaysBodyFat() {
        let app = launch()
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        assertTodayPagerStaysToday(pager)
        XCTAssertFalse(
            app.staticTexts["home_v2_composition_sentence"].label == "Body fat not logged for this day.",
            "Today must not present an older weight-only day"
        )
        XCTAssertNotEqual(app.staticTexts["home_v2_ffmi_value"].label, "—")
        capture(app, "timeline-today-keeps-its-body-fat")
    }

    func testVerticalRulerDragDoesNotSelectOrNavigateAndHorizontalScrubStillWorks() {
        let app = launch(largestText: true)
        let ruler = app.descendants(matching: .any)["home_v2_timeline_scrubber"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 8))
        let originalDate = ruler.value as? String
        let start = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -110)))
        XCTAssertEqual(ruler.value as? String, originalDate)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        let end = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.7))
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.7)).press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(ruler.value as? String, originalDate, "Today's ruler has no older day to select")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["home_v2_log_weight"].frame))
        capture(app, "timeline-ruler-largest-text")
    }

    func testBodyFatCheckInUpdatesSelectedHistoricalPhotoWithoutChangingWeight() throws {
        let app = launch()
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let today = caption.label
        try assertPhotoColor(stage, red: true)
        let weight = app.staticTexts["home_v2_weight_value"].label
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons["Body Fat"].isSelected)
        let field = app.textFields["Body fat percentage value"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "15.8", "The sheet must use today's check-in")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        XCTAssertEqual(caption.label, today)
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, weight)
        app.buttons["photo_timeline_root_menu"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "Entries")).firstMatch.tap()
        let imported = app.buttons.matching(identifier: "home_v2_entries_row")
            .matching(NSPredicate(format: "label CONTAINS %@", "Apple Health")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 8), "Imported history stays behind Entries")
        capture(app, "timeline-imported-history-unchanged")
    }

    func testSelectedDayStepsAtLargestTextFollowThePhotoAndRemainReachable() throws {
        let app = launch(largestText: true, withSteps: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        assertTodayPagerStaysToday(pager)
        let firstCaption = caption.label
        let count = 6_000
        do {
            let index = 0
            assertStepCount(count, in: app)
            let stepsDate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Steps · ")).firstMatch
            XCTAssertTrue(caption.label.hasPrefix(stepsDate.label.replacingOccurrences(of: "Steps · ", with: "")))
            try assertPhotoColor(stage, red: index != 1)
            capture(app, "timeline-steps-ax5-photo-\(index)")
            let summary = app.otherElements["home_v2_steps_summary"].buttons.firstMatch
            revealTimelineSteps(summary, in: app)
            let value = app.staticTexts["home_v2_steps_value"]
            let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            let font = UIFontMetrics(forTextStyle: .title2).scaledFont(
                for: .systemFont(ofSize: 28, weight: .semibold), compatibleWith: traits
            )
            XCTAssertLessThan(value.frame.height, font.lineHeight * 1.5,
                              "The step total must remain one readable line, not split its final digit")
            XCTAssertLessThanOrEqual(stepsDate.frame.maxY, value.frame.minY,
                                     "At accessibility sizes the complete dated heading must precede the total")
            XCTAssertTrue(timelineViewport(in: app).contains(stepsDate.frame))
            XCTAssertTrue(timelineViewport(in: app).contains(value.frame))
            capture(app, "timeline-steps-ax5-value-\(index)")
            XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        }
        XCTAssertEqual(caption.label, firstCaption)
    }

    private func revealTimelineSteps(_ target: XCUIElement, in app: XCUIApplication) {
        let viewport = timelineViewport(in: app)
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let top = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + 30))
        let bottom = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 30))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        for _ in 0..<6 where !target.isHittable || !viewport.contains(target.frame) {
            if target.frame.minY < viewport.minY {
                top.press(forDuration: 0.05, thenDragTo: bottom)
            } else {
                bottom.press(forDuration: 0.05, thenDragTo: top)
            }
        }
        XCTAssertTrue(target.isHittable)
        XCTAssertTrue(viewport.contains(target.frame), "Selected-day steps must fit above the pinned controls")
    }

    private func timelineViewport(in app: XCUIApplication) -> CGRect {
        let scroll = app.scrollViews["home_v2_content_scroll"]
        let ruler = app.descendants(matching: .any)["home_v2_timeline_scrubber"]
        XCTAssertTrue(scroll.exists)
        XCTAssertTrue(ruler.exists)
        let viewport = CGRect(x: scroll.frame.minX, y: scroll.frame.minY, width: scroll.frame.width,
                              height: max(0, min(scroll.frame.maxY, ruler.frame.minY) - scroll.frame.minY))
        XCTAssertGreaterThan(viewport.height, 88, "Home must leave a usable scrolling viewport")
        return viewport
    }

    func testHistoricalWeightOnlyDayInEntriesNeverBorrowsTodaysBodyFat() {
        let app = launch()
        app.buttons["photo_timeline_root_menu"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "Entries")).firstMatch.tap()
        let rows = app.buttons.matching(identifier: "home_v2_entries_row")
        XCTAssertGreaterThan(rows.count, 2)
        rows.element(boundBy: 2).tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_context_row_weight"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_context_row_body_fat"].exists)
        capture(app, "entries-selected-missing-body-fat")
    }

    private func assertTodayPagerStaysToday(_ pager: XCUIElement) {
        XCTAssertTrue(pager.waitForExistence(timeout: 8))
        let leaked = expectation(for: NSPredicate(format: "value != %@", "Entry 1 of 1"), evaluatedWith: pager)
        XCTAssertEqual(
            XCTWaiter.wait(for: [leaked], timeout: 8), .timedOut,
            "Today must stay on today's entry after history loads"
        )
        XCTAssertEqual(pager.value as? String, "Entry 1 of 1")
    }

    private func launch(largestText: Bool = false, withSteps: Bool = false, holdScrub: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2PhotoFixture",
            "-lybUITestHomeV2TimelineFixture", "-lybUITestHomeV2OfflineFixture", "-lybUITestSuppressWhatsNew"
        ]
        if withSteps { app.launchArguments.append("-lybUITestHomeV2StepsFixture") }
        if holdScrub { app.launchArguments.append("-lybUITestPhotoHoldScrub") }
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["home_v2_photo_stage"].waitForExistence(timeout: 30))
        return app
    }

    private func assertStepCount(_ expected: Int, in app: XCUIApplication) {
        let value = app.staticTexts["home_v2_steps_value"]
        let loaded = expectation(
            for: NSPredicate(format: "label == %@", expected.formatted()), evaluatedWith: value
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed,
                       "Steps must be read from the selected fixture owner's actual daily row")
    }

    private func drag(_ stage: XCUIElement, from: CGFloat, to: CGFloat) {
        // The photo moves during paging; keep both endpoints in the fixed window.
        let frame = stage.frame
        let origin = XCUIApplication().windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.minX + frame.width * from, dy: frame.midY))
        let end = origin.withOffset(CGVector(dx: frame.minX + frame.width * to, dy: frame.midY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    private func assertPhotoColor(_ stage: XCUIElement, red: Bool) throws {
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard stage.exists, !stage.frame.isEmpty,
                  let image = stage.screenshot().image.cgImage,
                  let corner = image.cropping(to: CGRect(
                    x: CGFloat(image.width) / 10, y: CGFloat(image.height) / 10, width: 4, height: 4
                  )) else {
                return false
            }
            var pixel = [UInt8](repeating: 0, count: 4)
            return pixel.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(
                    data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                let redChannel = Int(bytes[0]), blueChannel = Int(bytes[2])
                let brightness = (redChannel + Int(bytes[1]) + blueChannel) / 3
                // The production subject plate desaturates and dims backgrounds.
                // Both hue and luminance must identify the actual selected fixture.
                return red
                    ? redChannel > blueChannel + 2 && brightness > 50
                    : blueChannel > redChannel + 2 && brightness < 50
            }
        }, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [loaded], timeout: 8), .completed, "Actual selected image pixels must match the fixture"
        )
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
