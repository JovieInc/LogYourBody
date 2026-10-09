//
// LogYourBodyUITestsLaunchTests.swift
// LogYourBody
//
import XCTest

final class LogYourBodyUITestsLaunchTests: XCTestCase {
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testProgressPhotoCancelMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestSuppressWhatsNew"
        ]
        app.launch()

        let addPhoto = app.buttons["launch_timeline_add_photo"]
        XCTAssertTrue(addPhoto.waitForExistence(timeout: 20), "A day without a photo must offer an add-photo action")
        addPhoto.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["progress_photo_attach_sheet"].waitForExistence(timeout: 8)
        )
        let cancel = app.descendants(matching: .any)["progress_photo_attach_cancel_button"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let frame = cancel.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Photo cancel \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Photo cancel \(frame)")

        let attach = app.descendants(matching: .any)["progress_photo_attach_submit_button"]
        XCTAssertTrue(attach.waitForExistence(timeout: 5))
        let attachFrame = attach.frame
        XCTAssertGreaterThanOrEqual(attachFrame.width, 44, "Photo attach \(attachFrame)")
        XCTAssertGreaterThanOrEqual(attachFrame.height, 44, "Photo attach \(attachFrame)")
        cancel.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["progress_photo_attach_sheet"].waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))
    }
}
