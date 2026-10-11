import Vision
import XCTest

final class HomeV2PhotoViewerLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExpandedDetailsDisplaysTheFullComparisonDate() throws {
        let app = launch()
        app.buttons["home_v2_viewer_details"].tap()
        let since = app.staticTexts["home_v2_viewer_since"]
        XCTAssertTrue(since.waitForExistence(timeout: 5))
        capture(app, named: "viewer-full-comparison-date")
        XCTAssertTrue(since.label.contains("since"), "The fixture must exercise a comparison date")
        try assertRenderedDate(since, in: app)
        XCTAssertTrue(app.buttons["home_v2_viewer_details_hide"].isHittable)
    }

    func testLargestTextDetailsScrollWithoutChangingThePhotoAndCanCollapse() throws {
        let app = launch(largestText: true)
        let heading = app.staticTexts["home_v2_viewer_date"]
        let selectedDate = heading.label
        capture(app, named: "viewer-largest-text-collapsed")
        try assertRenderedDate(heading, in: app)
        let disclosure = app.buttons["home_v2_viewer_details"]
        reveal(disclosure, in: app)
        disclosure.tap()
        let since = app.staticTexts["home_v2_viewer_since"]
        XCTAssertTrue(since.waitForExistence(timeout: 5))
        reveal(since, in: app)
        capture(app, named: "viewer-largest-text-measurements")
        try assertRenderedDate(since, in: app)
        for name in ["compare", "timelapse", "all_photos", "share"] {
            let button = app.buttons["home_v2_viewer_action_\(name)"]
            reveal(button, in: app)
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(app.frame.contains(button.frame))
        }
        let hide = app.buttons["home_v2_viewer_details_hide"]
        reveal(hide, in: app)
        capture(app, named: "viewer-largest-text-actions")
        XCTAssertEqual(heading.label, selectedDate, "Vertical details scrolling must not page to another photo")
        XCTAssertTrue(app.buttons["home_v2_viewer_close"].isHittable, "Close stays pinned while details scroll")
        hide.tap()
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home_v2_viewer_action_compare"].exists)
        XCTAssertEqual(heading.label, selectedDate, "Collapsing must retain the selected day")
        capture(app, named: "viewer-largest-text-collapsed-again")
        app.buttons["home_v2_viewer_close"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_photo_stage"].waitForExistence(timeout: 5))
    }

    func testVerticalRulerDragScrollsWithoutSelectingAndTapStillSelects() {
        let app = launch(largestText: true)
        app.buttons["home_v2_viewer_details"].tap()
        let ruler = app.descendants(matching: .any)["home_v2_photo_ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        reveal(ruler, in: app)
        let heading = app.staticTexts["home_v2_viewer_date"]
        let selectedDate = heading.label
        let originalY = ruler.frame.minY
        capture(app, named: "viewer-ruler-before-vertical-scroll")
        // Start far from the selected (latest) tick to expose touch-down selection.
        let start = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)))
        capture(app, named: "viewer-ruler-after-vertical-scroll")
        XCTAssertEqual(heading.label, selectedDate, "A vertical gesture on the ruler must not select another photo")
        XCTAssertLessThan(ruler.frame.minY, originalY - 20, "The ruler must yield to vertical details scrolling")
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.75)).tap()
        let tapChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", selectedDate), object: heading
        )
        XCTAssertEqual(XCTWaiter.wait(for: [tapChanged], timeout: 5), .completed, "Intentional ruler taps still select")
        capture(app, named: "viewer-ruler-after-intentional-tap")
    }

    func testPhotoPagingAndRulerRemainIndependentOfDetailsScrolling() {
        let app = launch()
        let heading = app.staticTexts["home_v2_viewer_date"]
        let firstDate = heading.label
        let stage = app.descendants(matching: .any)["home_v2_viewer_stage"]
        stage.swipeLeft()
        let pageChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", firstDate), object: heading
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pageChanged], timeout: 5), .completed)
        let pagedDate = heading.label
        app.buttons["home_v2_viewer_details"].tap()
        let ruler = app.descendants(matching: .any)["home_v2_photo_ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        let start = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7))
        let end = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: end)
        let rulerChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", pagedDate), object: heading
        )
        XCTAssertEqual(XCTWaiter.wait(for: [rulerChanged], timeout: 5), .completed)
        let selectedDate = heading.label
        stage.swipeUp()
        XCTAssertEqual(heading.label, selectedDate)
        app.buttons["home_v2_viewer_details_hide"].tap()
        XCTAssertTrue(app.buttons["home_v2_viewer_details"].waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, selectedDate)
        capture(app, named: "viewer-selected-date-after-ruler-and-collapse")
    }

    private func launch(largestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2PhotoFixture", "-lybUITestSuppressWhatsNew",
            "-UIPreferredContentSizeCategoryName",
            largestText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"
        ]
        app.launch()
        let photo = app.descendants(matching: .any)["home_v2_photo_stage"]
        XCTAssertTrue(photo.waitForExistence(timeout: 30))
        photo.tap()
        XCTAssertTrue(app.buttons["home_v2_viewer_tools"].waitForExistence(timeout: 8))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["home_v2_viewer_scroll"]
        for _ in 0..<6 {
            let bounds = scroll.exists ? scroll.frame : app.frame
            if element.isHittable && bounds.contains(element.frame) { return }
            let surface = scroll.exists ? scroll : app
            if element.exists && element.frame.minY < bounds.minY {
                surface.swipeDown()
            } else {
                surface.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, "Details and actions must be reachable by scrolling")
        XCTAssertTrue(app.frame.contains(element.frame))
    }

    /// Accessibility labels remain complete even when SwiftUI renders an ellipsis.
    /// Read the actual pixels in the text's frame to detect that visible regression.
    private func assertRenderedDate(_ text: XCUIElement, in app: XCUIApplication) throws {
        XCTAssertTrue(app.frame.contains(text.frame))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0
        request.recognitionLanguages = ["en-US"]
        let frame = text.frame.insetBy(dx: -2, dy: -2).intersection(app.frame)
        request.regionOfInterest = CGRect(
            x: frame.minX / app.frame.width,
            y: 1 - frame.maxY / app.frame.height,
            width: frame.width / app.frame.width,
            height: frame.height / app.frame.height
        )
        try VNImageRequestHandler(data: app.screenshot().pngRepresentation).perform([request])
        let visible = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
        let normalize: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let expectedDate = text.label.components(separatedBy: " since ").last ?? text.label
        XCTAssertTrue(
            normalize(visible).contains(normalize(expectedDate)),
            "The complete date \(expectedDate) must render without ellipsis; visible text: \(visible)"
        )
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
