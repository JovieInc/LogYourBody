import UIKit
import XCTest

final class HomeV2TimelineIntegrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

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

    func testDiagnosticMountedCurrentPhotoCodeRejectsHistoricalIdentity() throws {
        let app = launch(calibrationVariant: "0")
        defer { app.terminate() }
        let stage = app.buttons["home_v2_photo_stage"]
        capturePhotoDiagnostic(app, stage: stage, name: "calibration-current-initial", requested: "0")
        try assertPhotoColor(stage, red: true)
        capturePhotoDiagnostic(app, stage: stage, name: "calibration-current-ready", requested: "0")
        XCTAssertEqual(LuminanceFixtureIdentity.code(image: try XCTUnwrap(stage.screenshot().image.cgImage)), 0b101)
        XCTAssertNotEqual(LuminanceFixtureIdentity.code(image: try XCTUnwrap(stage.screenshot().image.cgImage)), 0b011)
    }

    func testDiagnosticMountedHistoricalPhotoCodeRejectsCurrentIdentity() throws {
        let app = launch(calibrationVariant: "7")
        defer { app.terminate() }
        let stage = app.buttons["home_v2_photo_stage"]
        capturePhotoDiagnostic(app, stage: stage, name: "calibration-historical-initial", requested: "7")
        try assertPhotoColor(stage, red: false)
        capturePhotoDiagnostic(app, stage: stage, name: "calibration-historical-ready", requested: "7")
        XCTAssertEqual(LuminanceFixtureIdentity.code(image: try XCTUnwrap(stage.screenshot().image.cgImage)), 0b011)
        XCTAssertNotEqual(LuminanceFixtureIdentity.code(image: try XCTUnwrap(stage.screenshot().image.cgImage)), 0b101)
    }

    func testDiagnosticMountedDefaultGrayAndBlankRejectPhotoIdentity() throws {
        for variant in ["gray", "blank"] {
            let app = launch(calibrationVariant: variant)
            let stage = app.buttons["home_v2_photo_stage"]
            capturePhotoDiagnostic(app, stage: stage, name: "calibration-\(variant)-initial", requested: variant)
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let image = stage.screenshot().image.cgImage else { return false }
                return variant == "gray" ? LuminanceFixtureIdentity.isDefaultGrayPlate(image) :
                    LuminanceFixtureIdentity.isBlankPlate(image)
            }, object: nil)
            let result = XCTWaiter.wait(for: [loaded], timeout: 8)
            capturePhotoDiagnostic(app, stage: stage, name: "calibration-\(variant)-ready", requested: variant)
            XCTAssertEqual(result, .completed, "Require the actual negative image, not a loading placeholder")
            let image = try XCTUnwrap(stage.screenshot().image.cgImage)
            XCTAssertNil(LuminanceFixtureIdentity.code(image: image))
            app.terminate()
        }
    }

    private func capturePhotoDiagnostic(_ app: XCUIApplication, stage: XCUIElement,
                                        name: String, requested: String) {
        capture(app, name)
        let screenshot = stage.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name + "-owning-stage"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = screenshot.image.cgImage
        let diagnostic: [String: Any] = [
            "requestedVariant": requested,
            "stageFrame": NSStringFromCGRect(stage.frame),
            "caption": app.staticTexts["home_v2_photo_caption"].label,
            "weight": app.staticTexts["home_v2_weight_value"].label,
            "luminanceSignature": image.flatMap(LuminanceFixtureIdentity.signature) as Any? ?? NSNull(),
            "decodedCode": image.flatMap(LuminanceFixtureIdentity.code) as Any? ?? NSNull(),
            "isDefaultGrayPlate": image.map(LuminanceFixtureIdentity.isDefaultGrayPlate) ?? false,
            "isBlankPlate": image.map(LuminanceFixtureIdentity.isBlankPlate) ?? false,
            "phase": "Actual owning image must determine loading versus ready; no unconditional phase claim",
            "ownership": "Image code identifies a fixture day only; separate account/generation evidence is required"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys])) ?? Data()
        let text = XCTAttachment(string: String(bytes: data, encoding: .utf8) ?? "")
        text.name = name + "-luminance-and-frame"
        text.lifetime = .keepAlways
        add(text)
    }

    // Test-only current-main contract witness. All navigation and actual-photo controls precede intended RED.
    func testSelectedMomentInfersBracketedBodyFatWithProvenance() throws {
        let launchDate = Date()
        let app = launch()
        defer { app.terminate() }
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let ready = expectation(for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager)
        let readyResult = XCTWaiter.wait(for: [ready], timeout: 8)
        capturePhotoDiagnostic(app, stage: stage, name: "bracket-before-navigation", requested: "0")
        guard readyResult == .completed, Calendar.current.isDate(launchDate, inSameDayAs: Date()),
              stage.label.contains("15.8"), weight.label == "181.0" else {
            XCTFail("Bracket prerequisite failed: actual history, same calendar day, Today body fat and exact weight required")
            return
        }
        try assertPhotoIdentity(stage, expected: 0b101)
        for index in 0..<2 {
            let before = caption.label
            drag(stage, from: 0.85, to: 0.3)
            let moved = expectation(for: NSPredicate(format: "label != %@", before), evaluatedWith: caption)
            let result = XCTWaiter.wait(for: [moved], timeout: 5)
            capture(app, "bracket-navigation-\(index)")
            guard result == .completed else {
                XCTFail("Bracket prerequisite failed: intentional historical navigation did not change the selected date")
                return
            }
        }
        let calendar = Calendar.current
        let selected = try XCTUnwrap(calendar.date(byAdding: .day, value: -14, to: launchDate))
        let older = try XCTUnwrap(calendar.date(byAdding: .day, value: -21, to: launchDate))
        let newer = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: launchDate))
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let selectedDate = formatter.string(from: selected)
        let beforeInferenceCaption = caption.label
        capturePhotoDiagnostic(app, stage: stage, name: "bracket-selected-before-inference-assert", requested: "14")
        guard beforeInferenceCaption.contains(selectedDate), weight.label == "183.9" else {
            XCTFail("Bracket prerequisite failed: require full selected date and the exact83.4kg/183.9lb source weight")
            return
        }
        try assertPhotoIdentity(stage, expected: 0b110)
        XCTAssertEqual(stage.frame.width / stage.frame.height, 4.0 / 5.0, accuracy: 0.02)
        // Constants come from the existing fixture, never the app's presentation resolver.
        let expectedBodyFat = 16.9 + (16.2 - 16.9) *
            selected.timeIntervalSince(older) / newer.timeIntervalSince(older)
        XCTAssertEqual(expectedBodyFat, 16.55, accuracy: 0.0001)
        // Decimal fixture16.90/16.20 has exact midpoint16.55; the expected display uses explicit decimal half-up.
        // Floating-point interpolation is compared with tolerance, never formatted to derive its own oracle.
        let rounding = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 1,
            raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        let expectedBodyFatDisplay = NSDecimalNumber(string: "16.55").rounding(accordingToBehavior: rounding).stringValue
        XCTAssertEqual(expectedBodyFatDisplay, "16.6")
        let heightMeters = 178.0 / 100
        let expectedFFMI = 83.4 * (1 - expectedBodyFat / 100) / pow(heightMeters, 2) +
            6.1 * (1.8 - heightMeters)
        XCTAssertEqual(expectedFFMI, 22.088071203131, accuracy: 0.000001)
        XCTAssertEqual(String(format: "%.1f", expectedFFMI), "22.1")
        let constants = XCTAttachment(string:
            "selected=\(selectedDate);older=\(formatter.string(from: older)),16.90%,DEXA;" +
            "newer=\(formatter.string(from: newer)),16.20%,Apple Health;" +
            "weight=83.4kg;display=183.9lb;height=178cm;inferredBF=16.55%;normalizedDerivedFFMI=22.1")
        constants.name = "bracket-independent-fixture-expectations"
        constants.lifetime = .keepAlways
        add(constants)
        let sentence = app.staticTexts["home_v2_composition_sentence"]
        let mounted = sentence.waitForExistence(timeout: 5)
        let mountedLabel = mounted ? sentence.label : "<composition node absent>"
        capture(app, "bracket-existing-composition-prerequisite")
        let compositionAX = XCTAttachment(string: mounted ? sentence.debugDescription : app.debugDescription)
        compositionAX.name = "bracket-existing-composition-owning-AX"
        compositionAX.lifetime = .keepAlways
        add(compositionAX)
        let compositionLabel = XCTAttachment(string: mountedLabel)
        compositionLabel.name = "bracket-existing-composition-label"
        compositionLabel.lifetime = .keepAlways
        add(compositionLabel)
        guard mounted, !mountedLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            XCTFail("Bracket prerequisite failed: existing composition node must be mounted with a nonempty label")
            return
        }
        let inferred = expectation(for: NSPredicate(format: "label CONTAINS %@", "Inferred body fat"),
                                   evaluatedWith: sentence)
        let inferenceResult = XCTWaiter.wait(for: [inferred], timeout: 5)
        capture(app, "bracket-intended-contract-result")
        switch inferenceResult {
        case .completed: break
        case .timedOut:
            XCTFail("INTENDED_CONTRACT_RED timedOut: selected14-day moment needs bracketed inferred body fat")
            return
        default:
            XCTFail("Non-contract waiter failure: \(inferenceResult); not accepted as intended RED")
            return
        }
        XCTAssertTrue(
            sentence.label.contains(expectedBodyFatDisplay),
            "Inferred percentage must use independent elapsed-time anchors"
        )
        XCTAssertEqual(caption.label, beforeInferenceCaption)
        XCTAssertEqual(weight.label, "183.9", "An exact measured weight takes precedence over interpolation")
        XCTAssertEqual(app.staticTexts["home_v2_ffmi_value"].label, "22.1", "FFMI is derived, never measured")
        app.buttons["home_v2_provenance_chip"].tap()
        let detail = app.descendants(matching: .any)["home_v2_provenance_detail"]
        let opened = detail.waitForExistence(timeout: 8)
        capture(app, "bracket-anchor-provenance")
        XCTAssertTrue(opened)
        for token in [formatter.string(from: older), formatter.string(from: newer),
                      "16.90 %", "16.20 %", "From your DEXA scan", "From Apple Health", "178"] {
            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", token)).firstMatch.exists,
                "Accessible inference provenance must include actual anchor dates, values, " +
                    "sources and derivation inputs"
            )
        }
        app.buttons["home_v2_provenance_done"].tap()
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
    }

    private func launch(largestText: Bool = false, withSteps: Bool = false,
                        calibrationVariant: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2PhotoFixture",
            "-lybUITestHomeV2TimelineFixture", "-lybUITestHomeV2OfflineFixture", "-lybUITestSuppressWhatsNew"
        ]
        if withSteps { app.launchArguments.append("-lybUITestHomeV2StepsFixture") }
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if let calibrationVariant {
            XCTAssertNotNil(UUID(uuidString: ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] ?? ""))
            XCTAssertTrue(ProcessInfo.processInfo.environment["XCTestBundlePath"]?.hasSuffix(
                "/LogYourBodyUITests.xctest"
            ) == true)
            for key in ["XCTestConfigurationFilePath", "XCTestSessionIdentifier", "XCTestBundlePath"] {
                if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                    app.launchEnvironment[key] = value
                }
            }
            app.launchArguments += ["-lybUITestDisableBiometricLock",
                                    "-lybUITestHomeV2TimelinePhotoCalibration", calibrationVariant]
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
        stage.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5)).press(
            forDuration: 0.05, thenDragTo: stage.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5))
        )
    }

    private func assertPhotoColor(_ stage: XCUIElement, red: Bool) throws {
        try assertPhotoIdentity(stage, expected: red ? 0b101 : 0b011)
    }

    private func assertPhotoIdentity(_ stage: XCUIElement, expected: Int) throws {
        let codes = [0b101, 0b011, 0b110, 0b100, 0b001]
        for code in codes {
            let signature = [2, 1, 0].map { (code & (1 << $0)) == 0 ? 0.02 : 0.28 }
            XCTAssertEqual(LuminanceFixtureIdentity.code(luminances: signature), code)
            if code != expected {
                XCTAssertNotEqual(LuminanceFixtureIdentity.code(luminances: signature), expected,
                                  "Every independently prescribed wrong-photo code must be rejected")
            }
        }
        XCTAssertNil(LuminanceFixtureIdentity.code(luminances: [0.2, 0.2, 0.2]), "Gray is not photo identity")
        XCTAssertNil(LuminanceFixtureIdentity.code(luminances: [0, 0, 0]), "Blank is not photo identity")
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = stage.screenshot().image.cgImage else { return false }
            return LuminanceFixtureIdentity.code(image: image) == expected
        }, object: nil)
        let result = XCTWaiter.wait(for: [loaded], timeout: 8)
        let evidence = XCTAttachment(screenshot: stage.screenshot())
        evidence.name = "fixture-luminance-identity-before-assert-\(expected)"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertEqual(result, .completed, "Actual rendered pixels must match the prescribed photo identity")
        let image = try XCTUnwrap(stage.screenshot().image.cgImage)
        XCTAssertEqual(LuminanceFixtureIdentity.code(image: image), expected)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// ARTIFACT ONLY — native renderer/mounted-crop calibration remains UNRUN.
// Independent prescribed fixture codes: day0=101,7=011,14=110,21=100,35=001.
private enum LuminanceFixtureIdentity {
    static func code(luminances: [Double]) -> Int? {
        guard luminances.count == 3, luminances.allSatisfy({ $0.isFinite }),
              let low = luminances.min(), let high = luminances.max(), high - low >= 0.12 else { return nil }
        var code = 0
        for value in luminances {
            let normalized = (value - low) / (high - low)
            guard normalized <= 0.25 || normalized >= 0.75 else { return nil }
            code = (code << 1) | (normalized >= 0.75 ? 1 : 0)
        }
        return code
    }

    static func code(image: CGImage) -> Int? {
        signature(image: image).flatMap { code(luminances: $0) }
    }

    static func signature(image: CGImage) -> [Double]? {
        var luminances: [Double] = []
        // Centers of the three 90x80 DEBUG fixture bands, above the person and stats.
        for x in [45.0 / 400.0, 200.0 / 400.0, 355.0 / 400.0] {
            let rect = CGRect(x: CGFloat(image.width) * x - 2,
                              y: CGFloat(image.height) * (40.0 / 500.0) - 2,
                              width: 4, height: 4)
            guard let region = image.cropping(to: rect) else { return nil }
            var rgba = [UInt8](repeating: 0, count: 4)
            let valid = rgba.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(
                    data: bytes.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(region, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            guard valid else { return nil }
            luminances.append((0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) +
                               0.0722 * Double(rgba[2])) / 255.0)
        }
        return luminances
    }

    private static func luminance(_ image: CGImage, x: Double, y: Double) -> Double? {
        let rect = CGRect(x: CGFloat(image.width) * CGFloat(x) - 2,
                          y: CGFloat(image.height) * CGFloat(y) - 2, width: 4, height: 4)
        guard let region = image.cropping(to: rect) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let valid = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(region, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard valid else { return nil }
        return (0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) + 0.0722 * Double(rgba[2])) / 255
    }

    static func isDefaultGrayPlate(_ image: CGImage) -> Bool {
        guard let signature = signature(image: image), let low = signature.min(), let high = signature.max(),
              let center = luminance(image, x: 0.5, y: 0.5) else { return false }
        // Actual gray fixture has a darker person; the BF loading fallback has bright center text.
        return high - low < 0.04 && low > 0.06 && low - center > 0.04
    }

    static func isBlankPlate(_ image: CGImage) -> Bool {
        let grid = [0.1, 0.3, 0.5, 0.7].flatMap { y in [0.1, 0.5, 0.9].map { (x: $0, y: y) } }
        let samples = grid.compactMap { luminance(image, x: $0.x, y: $0.y) }
        return samples.count == grid.count && samples.allSatisfy { $0 < 0.02 }
    }
}
