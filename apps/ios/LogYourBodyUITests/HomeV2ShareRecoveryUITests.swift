import XCTest

final class HomeV2ShareRecoveryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSinglePhotoToolsExplainCompareAndShareAndReturnToViewer() {
        let app = launch(fixture: "-lybUITestHomeV2SinglePhotoFixture")
        for tool in ["compare", "share"] {
            openTool(tool, in: app)
            let explanation = app.staticTexts["home_v2_photos_needed"]
            let explained = explanation.waitForExistence(timeout: 8)
            capture(app, named: "single-photo-\(tool)-result")
            XCTAssertTrue(explained)
            XCTAssertEqual(
                explanation.label,
                tool == "share" ? "Two photos are needed to share progress." : "Two photos are needed to compare."
            )
            let back = app.buttons["home_v2_photos_needed_back"]
            XCTAssertTrue(back.waitForExistence(timeout: 8))
            XCTAssertTrue(back.isHittable)
            capture(app, named: "single-photo-\(tool)-recovery")
            back.tap()
            XCTAssertTrue(app.buttons["home_v2_viewer_tools"].waitForExistence(timeout: 8))
        }
    }

    func testSinglePhotoDetailsActionAlsoExplainsMissingPair() {
        let app = launch(fixture: "-lybUITestHomeV2SinglePhotoFixture")
        app.buttons["home_v2_viewer_details"].tap()
        XCTAssertEqual(app.staticTexts["home_v2_viewer_body_fat_change"].label, "Body fat · no comparison")
        capture(app, named: "single-photo-details-no-body-fat-comparison")
        let compare = app.buttons["home_v2_viewer_action_compare"]
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        compare.tap()
        XCTAssertTrue(app.staticTexts["home_v2_photos_needed"].waitForExistence(timeout: 8))
        app.buttons["home_v2_photos_needed_back"].tap()
        XCTAssertTrue(compare.waitForExistence(timeout: 8), "Recovery keeps the selected photo and expanded details")
    }

    func testMissingSharePhotoShowsRetryAndCancelInsteadOfPreparingForever() {
        let app = launch(fixture: "-lybUITestHomeV2ShareMissingPhotoFixture")
        openTool("share", in: app)
        XCTAssertTrue(app.staticTexts["home_v2_share"].waitForExistence(timeout: 8), "The share preview must open")
        let error = app.staticTexts["home_v2_share_error"]
        let finishedLoading = error.waitForExistence(timeout: 10)
        capture(app, named: "share-photo-load-result")
        XCTAssertTrue(finishedLoading, "A failed load must leave Preparing and show retry")
        let retry = app.buttons["home_v2_share_retry"]
        XCTAssertTrue(retry.isEnabled)
        XCTAssertFalse(app.buttons["home_v2_share_action"].exists)
        capture(app, named: "share-photo-load-failed")
        retry.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 10), "A repeated failure must finish with recovery controls")
        XCTAssertTrue(retry.isEnabled)
        app.buttons["home_v2_share_cancel"].tap()
        XCTAssertTrue(app.buttons["home_v2_viewer_tools"].waitForExistence(timeout: 8))
    }

    func testShareCropRequiresReviewAndKeepsReadyCardAndOptions() {
        let app = launch()
        openTool("share", in: app)
        let share = app.buttons["home_v2_share_action"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: share)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let note = app.staticTexts["home_v2_share_face_note"]
        XCTAssertEqual(note.label, "Check the preview for faces and details you don’t want to share.")
        capture(app, named: "share-preview-before-crop")
        app.buttons["home_v2_share_options"].tap()
        let crop = app.switches["home_v2_share_crop"]
        XCTAssertTrue(crop.waitForExistence(timeout: 5))
        crop.tap()
        XCTAssertEqual(note.label, "Top of each photo cropped. Your face may still be visible; check the preview.")
        XCTAssertTrue(app.switches["home_v2_share_show_numbers"].exists)
        XCTAssertTrue(app.switches["home_v2_share_show_dates"].exists)
        XCTAssertTrue(share.isEnabled)
        XCTAssertTrue(app.frame.contains(app.descendants(matching: .any)["home_v2_share_card"].frame))
        capture(app, named: "share-preview-after-crop")
    }

    func testSinglePhotoRecoveryIsReachableAtLargestText() {
        let app = launch(fixture: "-lybUITestHomeV2SinglePhotoFixture", largestText: true)
        openTool("compare", in: app)
        XCTAssertTrue(app.staticTexts["home_v2_photos_needed"].waitForExistence(timeout: 8))
        let back = app.buttons["home_v2_photos_needed_back"]
        XCTAssertTrue(back.isHittable)
        XCTAssertTrue(app.frame.contains(back.frame))
        capture(app, named: "single-photo-recovery-largest-text")
        back.tap()
        XCTAssertTrue(app.buttons["home_v2_viewer_tools"].waitForExistence(timeout: 8))
    }

    func testShareRetryAndCancelAreReachableAtLargestText() {
        let app = launch(fixture: "-lybUITestHomeV2ShareMissingPhotoFixture", largestText: true)
        openTool("share", in: app)
        XCTAssertTrue(app.staticTexts["home_v2_share_error"].waitForExistence(timeout: 10))
        let retry = app.buttons["home_v2_share_retry"]
        let cancel = app.buttons["home_v2_share_cancel"]
        XCTAssertTrue(retry.isHittable)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(app.frame.contains(retry.frame))
        XCTAssertTrue(app.frame.contains(cancel.frame))
        let title = app.staticTexts["home_v2_share"]
        let error = app.staticTexts["home_v2_share_error"]
        XCTAssertGreaterThanOrEqual(title.frame.minY, cancel.frame.maxY)
        XCTAssertTrue(app.frame.contains(error.frame), "The full recovery explanation must remain readable")
        XCTAssertGreaterThan(error.frame.height, 80, "Large text must wrap instead of truncating")
        capture(app, named: "share-retry-largest-text")
        cancel.tap()
        XCTAssertTrue(app.buttons["home_v2_viewer_tools"].waitForExistence(timeout: 8))
    }

    func testSharePosterAndPrivacyRemainReadableAtLargestText() {
        let app = launch(largestText: true)
        openTool("share", in: app)
        let share = app.buttons["home_v2_share_action"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: share)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let title = app.staticTexts["home_v2_share"]
        let cancel = app.buttons["home_v2_share_cancel"]
        let note = app.staticTexts["home_v2_share_face_note"]
        XCTAssertGreaterThanOrEqual(title.frame.minY, cancel.frame.maxY)
        XCTAssertTrue(app.frame.contains(note.frame))
        XCTAssertGreaterThan(note.frame.height, 80, "The privacy reminder must wrap at large text sizes")
        capture(app, named: "share-privacy-largest-text")

        let scroll = app.scrollViews["home_v2_share_scroll"]
        let card = app.descendants(matching: .any)["home_v2_share_card"]
        scroll.swipeUp()
        XCTAssertTrue(scroll.frame.contains(card.frame), "The complete poster must be reachable without clipping")
        let summary = card.value as? String ?? ""
        XCTAssertTrue(summary.contains("Before "))
        XCTAssertTrue(summary.contains("after "))
        XCTAssertTrue(summary.contains(" in "), "VoiceOver must retain the visible weight-change summary")
        XCTAssertTrue(share.isHittable)
        XCTAssertTrue(app.frame.contains(share.frame))
        capture(app, named: "share-poster-largest-text")
        app.buttons["home_v2_share_options"].tap()
        scroll.swipeUp()
        for identifier in ["home_v2_share_show_numbers", "home_v2_share_crop", "home_v2_share_show_dates"] {
            let option = app.switches[identifier]
            XCTAssertTrue(option.isHittable, "Every export option must remain reachable at large text sizes")
            XCTAssertTrue(app.frame.contains(option.frame))
        }
        app.switches["home_v2_share_crop"].tap()
        XCTAssertTrue(share.isEnabled)
        capture(app, named: "share-options-largest-text")
    }

    private func launch(fixture: String? = nil, largestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2PhotoFixture", "-lybUITestSuppressWhatsNew"
        ]
        if let fixture { app.launchArguments.append(fixture) }
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let photo = app.descendants(matching: .any)["home_v2_photo_stage"]
        XCTAssertTrue(photo.waitForExistence(timeout: 30))
        photo.tap()
        XCTAssertTrue(app.buttons["home_v2_viewer_tools"].waitForExistence(timeout: 8))
        return app
    }

    private func openTool(_ tool: String, in app: XCUIApplication) {
        app.buttons["home_v2_viewer_tools"].tap()
        let action = app.buttons["home_v2_photo_tool_\(tool)"]
        XCTAssertTrue(action.waitForExistence(timeout: 8))
        action.tap()
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
