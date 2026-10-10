import XCTest

final class HomeV2TimelineIntegrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHorizontalPhotoDragPagesPixelsAndMetricsWithoutOpeningViewer() throws {
        let app = launch()
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        let firstCaption = caption.label, firstWeight = weight.label
        try assertPhotoColor(stage, red: true)
        drag(stage, from: 0.85, to: 0.3)
        let moved = expectation(for: NSPredicate(format: "label != %@", firstCaption), evaluatedWith: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        XCTAssertNotEqual(weight.label, firstWeight)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        try assertPhotoColor(stage, red: false)
        capture(app, "timeline-older-blue-photo")

        // Preserve the precise right-drag regression from the default-Home qualification.
        drag(stage, from: 0.3, to: 0.85)
        let returned = expectation(for: NSPredicate(format: "label == %@", firstCaption), evaluatedWith: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertEqual(weight.label, firstWeight)
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

    private func launch(largestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2PhotoFixture",
            "-lybUITestHomeV2TimelineFixture", "-lybUITestHomeV2OfflineFixture", "-lybUITestSuppressWhatsNew"
        ]
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["home_v2_photo_stage"].waitForExistence(timeout: 30))
        return app
    }

    private func drag(_ stage: XCUIElement, from: CGFloat, to: CGFloat) {
        stage.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5)).press(
            forDuration: 0.05, thenDragTo: stage.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5))
        )
    }

    private func assertPhotoColor(_ stage: XCUIElement, red: Bool) throws {
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = stage.screenshot().image.cgImage,
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
                return red ? Int(bytes[0]) > Int(bytes[2]) + 40 : Int(bytes[2]) > Int(bytes[0]) + 40
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
