import XCTest

final class HomeV2TimelineIntegrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHorizontalPhotoDragKeepsTodaySelectedWithoutOpeningViewer() throws {
        let app = launch()
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        let firstCaption = caption.label, firstWeight = weight.label
        try assertPhotoColor(stage, red: true)
        drag(stage, from: 0.85, to: 0.3)
        XCTAssertEqual(caption.label, firstCaption)
        XCTAssertEqual(weight.label, firstWeight)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        try assertPhotoColor(stage, red: true)
        capture(app, "today-remains-selected")

        drag(stage, from: 0.3, to: 0.85)
        XCTAssertEqual(caption.label, firstCaption)
        XCTAssertEqual(weight.label, firstWeight)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        try assertPhotoColor(stage, red: true)
        stage.tap()
        XCTAssertTrue(
            app.buttons["home_v2_viewer_close"].waitForExistence(timeout: 5), "An intentional tap still opens the photo"
        )
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

    func testLargestTextHasNoTimelineRulerAndKeepsLoggingReachable() {
        let app = launch(largestText: true)
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_timeline_scrubber"].exists)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["home_v2_log_weight"].frame))
        capture(app, "today-largest-text")
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
