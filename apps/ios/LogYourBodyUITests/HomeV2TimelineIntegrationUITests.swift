import UIKit
import XCTest

final class HomeV2TimelineIntegrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPhotoHoldScrubsBothDirectionsThenAnotherHoldRestoresTap() {
        let app = launch(withSteps: true, holdScrub: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let loaded = expectation(for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed)
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        let date = caption.label, initialWeight = weight.label
        assertStepCount(6_000, in: app)
        let mode = app.staticTexts["home_v2_photo_scrub_mode"]
        stage.press(forDuration: 0.7)
        XCTAssertFalse(mode.exists, "A short hold must not activate scrubbing")
        // A short hold may be a normal photo tap. Return if the viewer opened.
        let close = app.buttons["home_v2_viewer_close"]
        if close.exists { close.tap() }
        let start = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 1.3, thenDragTo: start.withOffset(CGVector(dx: -stage.frame.width * 0.75, dy: 0)))
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertNotEqual(caption.label, date)
        XCTAssertNotEqual(weight.label, initialWeight)
        let stepsDate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Steps · ")).firstMatch
        XCTAssertTrue(caption.label.hasPrefix(stepsDate.label.replacingOccurrences(of: "Steps · ", with: "")))
        XCTAssertFalse(close.exists, "Holding and scrubbing must not open the photo viewer")
        let surface = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        surface.press(forDuration: 0.05, thenDragTo: surface.withOffset(CGVector(dx: pager.frame.width * 0.85, dy: 0)))
        XCTAssertEqual(caption.label, date)
        XCTAssertEqual(weight.label, initialWeight)
        assertStepCount(6_000, in: app)
        stage.press(forDuration: 1.3)
        XCTAssertFalse(mode.exists)
        stage.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testPhotoScrubResetsWhenNavigatingToTheMenuAndBack() {
        let app = launch(holdScrub: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let loaded = expectation(for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed)
        stage.press(forDuration: 1.3)
        let mode = app.staticTexts["home_v2_photo_scrub_mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        app.buttons["photo_timeline_root_menu"].tap()
        let scrim = app.buttons["home_v2_sidebar_scrim"]
        XCTAssertTrue(scrim.waitForExistence(timeout: 5))
        scrim.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertFalse(mode.exists)
        stage.tap()
        XCTAssertTrue(app.buttons["home_v2_viewer_close"].waitForExistence(timeout: 5))
    }

    func testHorizontalPhotoDragPagesPixelsAndMetricsWithoutOpeningViewer() throws {
        let app = launch(withSteps: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        let steps = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Steps · ")).firstMatch
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        let firstCaption = caption.label, firstWeight = weight.label
        assertStepCount(6_000, in: app)
        let firstStepsLabel = steps.label
        XCTAssertTrue(firstCaption.hasPrefix(firstStepsLabel.replacingOccurrences(of: "Steps · ", with: "")))
        try assertPhotoColor(stage, red: true)
        drag(stage, from: 0.85, to: 0.3)
        let moved = expectation(for: NSPredicate(format: "label != %@", firstCaption), evaluatedWith: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        XCTAssertNotEqual(weight.label, firstWeight)
        XCTAssertNotEqual(steps.label, firstStepsLabel, "Steps must follow the selected day, not remain labeled Today")
        XCTAssertTrue(caption.label.hasPrefix(steps.label.replacingOccurrences(of: "Steps · ", with: "")))
        assertStepCount(8_000, in: app)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        try assertPhotoColor(stage, red: false)
        capture(app, "timeline-older-blue-photo")

        // Preserve the precise right-drag regression from the default-Home qualification.
        drag(stage, from: 0.3, to: 0.85)
        let returned = expectation(for: NSPredicate(format: "label == %@", firstCaption), evaluatedWith: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertEqual(weight.label, firstWeight)
        XCTAssertEqual(steps.label, firstStepsLabel)
        assertStepCount(6_000, in: app)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        try assertPhotoColor(stage, red: true)
        stage.tap()
        XCTAssertTrue(
            app.buttons["home_v2_viewer_close"].waitForExistence(timeout: 5), "An intentional tap still opens the photo"
        )
    }

    func testSelectedWeightOnlyDayNeverBorrowsTodaysBodyFat() {
        let app = launch()
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let historyLoaded = expectation(
            for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager
        )
        XCTAssertEqual(XCTWaiter.wait(for: [historyLoaded], timeout: 8), .completed,
                       "Wait for real history after the newest-only first paint before swiping")
        for _ in 0..<2 {
            let previous = caption.label
            stage.swipeLeft()
            let changed = expectation(for: NSPredicate(format: "label != %@", previous), evaluatedWith: caption)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        }
        let composition = app.staticTexts["home_v2_composition_sentence"]
        let missing = expectation(
            for: NSPredicate(format: "label == %@", "Body fat not logged for this day."), evaluatedWith: composition
        )
        XCTAssertEqual(XCTWaiter.wait(for: [missing], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        XCTAssertEqual(app.staticTexts["home_v2_ffmi_value"].label, "—",
                       "FFMI must not borrow body fat from today's record")
        XCTAssertEqual(app.staticTexts["home_v2_steps_value"].label, "—")
        capture(app, "timeline-selected-missing-body-fat")
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
        let changed = expectation(for: NSPredicate(format: "value != %@", originalDate ?? ""), evaluatedWith: ruler)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["home_v2_log_weight"].frame))
        capture(app, "timeline-ruler-largest-text")
    }

    func testBodyFatCheckInUpdatesSelectedHistoricalPhotoWithoutChangingWeight() throws {
        let app = launch()
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let today = caption.label
        drag(stage, from: 0.85, to: 0.3)
        let moved = expectation(for: NSPredicate(format: "label != %@", today), evaluatedWith: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        let ruler = app.descendants(matching: .any)["home_v2_timeline_scrubber"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        let selectedDate = try XCTUnwrap(ruler.value as? String)
        try assertPhotoColor(stage, red: false)
        let weight = app.staticTexts["home_v2_weight_value"].label
        let oldFFMI = app.staticTexts["home_v2_ffmi_value"].label
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons["Body Fat"].isSelected)
        let field = app.textFields["Body fat percentage value"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "16.2", "The sheet must use the selected older check-in")
        let method = app.descendants(matching: .any).matching(identifier: "home_v2_body_fat_method").firstMatch
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        XCTAssertEqual(method.value as? String, "Method not specified", "Apple Health alone does not identify a method")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "16.0")
        let save = app.buttons["home_v2_log_sheet_save"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        save.tap()
        let updated = expectation(for: NSPredicate(format: "label CONTAINS %@", "16.0"), evaluatedWith: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
        XCTAssertEqual(ruler.value as? String, selectedDate, "Saving body fat must retain the selected historical day")
        try assertPhotoColor(stage, red: false)
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, weight)
        XCTAssertNotEqual(app.staticTexts["home_v2_ffmi_value"].label, oldFFMI)
        XCTAssertTrue(stage.label.contains("From Apple Health"), "The original provenance must survive the value edit")
        XCTAssertFalse(stage.label.contains("Visual estimate"))
        XCTAssertFalse(app.buttons["home_v2_undo"].exists)
        XCTAssertFalse(app.buttons["home_v2_done"].exists)
        XCTAssertFalse(app.staticTexts["home_v2_logged_sentence"].exists)
        capture(app, "timeline-body-fat-save-selected-photo")
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, "16.0")
        XCTAssertEqual(method.value as? String, "Method not specified")
        capture(app, "timeline-body-fat-method-after-save")
    }

    func testSelectedDayStepsAtLargestTextFollowThePhotoAndRemainReachable() throws {
        let app = launch(largestText: true, withSteps: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let historyLoaded = expectation(for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [historyLoaded], timeout: 8), .completed)
        let firstCaption = caption.label
        let initialCardY = stage.frame.minY
        for (index, count) in [6_000, 8_000, 6_000].enumerated() {
            if index > 0 {
                revealTimelineCard(stage, initialY: initialCardY, in: app)
                let previous = caption.label
                if index == 1 { stage.swipeLeft() } else { stage.swipeRight() }
                let moved = expectation(for: NSPredicate(format: "label != %@", previous), evaluatedWith: caption)
                XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
            }
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

    private func revealTimelineCard(_ stage: XCUIElement, initialY: CGFloat, in app: XCUIApplication) {
        let scroll = app.scrollViews["home_v2_content_scroll"]
        let viewport = timelineViewport(in: app)
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let top = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + 30))
        let bottom = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 30))
        XCTAssertTrue(scroll.exists)
        for _ in 0..<6 where stage.frame.minY < initialY - 1 {
            top.press(forDuration: 0.05, thenDragTo: bottom)
        }
        XCTAssertEqual(stage.frame.minY, initialY, accuracy: 1)
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
