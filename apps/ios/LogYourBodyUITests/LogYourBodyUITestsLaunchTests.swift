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

    func testWeightGoalCancelMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestWeightLoggerMVPFixture",
            "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Weight log"].waitForExistence(timeout: 20))
        let settings = app.buttons["mvp_settings_button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let tracking = app.descendants(matching: .any)["settings_tracking_link"]
        var swipes = 0
        while !tracking.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(tracking.waitForExistence(timeout: 8))
        tracking.tap()

        let weightGoal = app.buttons["settings_weight_goal_edit_button"]
        swipes = 0
        while !weightGoal.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(weightGoal.waitForExistence(timeout: 8))
        weightGoal.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["settings_goal_editor_text_field"].waitForExistence(timeout: 8)
        )
        let cancel = app.buttons["Cancel editing"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let frame = cancel.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Goal cancel \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Goal cancel \(frame)")

        let save = app.descendants(matching: .any)["settings_goal_editor_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let saveFrame = save.frame
        XCTAssertGreaterThanOrEqual(saveFrame.width, 44, "Goal save \(saveFrame)")
        XCTAssertGreaterThanOrEqual(saveFrame.height, 44, "Goal save \(saveFrame)")
        cancel.tap()
        XCTAssertTrue(weightGoal.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["settings_goal_editor_text_field"].waitForNonExistence(timeout: 5)
        )
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

    func testTrainingEnrollmentOffersTwoThroughSixDays() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestTrainingFixture", "-lybUITestResetTrainingFixture"]
        app.launch()

        let open = app.buttons["training_fixture_enroll"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let picker = app.buttons["training_enroll_sessions_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        for days in 2...6 {
            picker.tap()
            let option = app.buttons["\(days) days"]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
        }
    }

    func testTrainingEnrollmentCloseMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestTrainingFixture", "-lybUITestResetTrainingFixture"]
        app.launch()

        let open = app.buttons["training_fixture_enroll"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        XCTAssertTrue(app.navigationBars["Training coach"].waitForExistence(timeout: 8))
        let close = app.descendants(matching: .any)["training_enroll_close_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let frame = close.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Training enrollment close \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Training enrollment close \(frame)")
        close.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Training coach"].exists)
    }

    func testVoiceReviewCancelMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestTrainingFixture", "-lybUITestResetTrainingFixture"]
        app.launch()

        let open = app.buttons["training_fixture_voice_review"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        XCTAssertTrue(app.navigationBars["Review set"].waitForExistence(timeout: 8))
        let cancel = app.descendants(matching: .any)["voice_set_review_cancel_button"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let frame = cancel.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Voice review cancel \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Voice review cancel \(frame)")
        cancel.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Review set"].exists)
    }

    func testDexaPDFCloseMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestFullDashboardFixture",
            "-lybUITestDexaPDFSheetFixture",
            "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["legacy_full_dashboard_beta"].waitForExistence(timeout: 20))
        let settings = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Open profile and settings")
        ).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let integrations = app.descendants(matching: .any)["settings_integrations_link"]
        scrollUntilHittable(integrations, in: app)
        XCTAssertTrue(integrations.waitForExistence(timeout: 8))
        integrations.tap()

        let dexa = app.buttons["integrations_bodyspec_link"]
        scrollUntilHittable(dexa, in: app)
        XCTAssertTrue(dexa.waitForExistence(timeout: 8))
        dexa.tap()

        let importButton = app.buttons["body_spec_pdf_import"]
        scrollUntilHittable(importButton, in: app)
        XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        importButton.tap()

        XCTAssertTrue(app.navigationBars["Import scan PDF"].waitForExistence(timeout: 8))
        let close = app.descendants(matching: .any)["dexa_pdf_import_close_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let frame = close.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "DEXA PDF close \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "DEXA PDF close \(frame)")
        close.tap()
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Import scan PDF"].exists)
    }

    func testSyncDetailsCloseMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestFullDashboardFixture",
            "-lybUITestSyncDetailsFixture",
            "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["legacy_full_dashboard_beta"].waitForExistence(timeout: 20))
        let status = app.descendants(matching: .any)["dashboard_sync_status"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        status.tap()

        XCTAssertTrue(app.navigationBars["Sync"].waitForExistence(timeout: 8))
        let close = app.descendants(matching: .any)["dashboard_sync_close_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let frame = close.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Sync close \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Sync close \(frame)")
        close.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Sync"].exists)
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
    }

    func testPaywallLegalDoneMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPaywallFixture",
            "-lybUITestSuppressWhatsNew"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_paywall"].waitForExistence(timeout: 20))
        let terms = app.buttons["Terms of Service"].firstMatch
        XCTAssertTrue(terms.waitForExistence(timeout: 8))
        terms.tap()

        let done = app.descendants(matching: .any)["paywall_legal_done_button"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let frame = done.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Paywall legal done \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Paywall legal done \(frame)")
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_paywall"].waitForExistence(timeout: 5))
        XCTAssertFalse(done.exists)
    }

    func testTrainingSessionCloseMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestTrainingFixture",
            "-lybUITestResetTrainingFixture"
        ]
        app.launch()

        let open = app.buttons["training_fixture_open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        XCTAssertTrue(app.navigationBars["Live session"].waitForExistence(timeout: 8))
        let close = app.descendants(matching: .any)["training_live_session_close_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let frame = close.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Training close \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Training close \(frame)")
        close.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Live session"].exists)
    }

    func testFfmiInfoDoneMeetsMinimumHitTarget() throws {
        assertFfmiInfoDismissal(bottomAction: true)
    }

    func testFfmiInfoDoneRetainsToolbarWhenGateOff() throws {
        assertFfmiInfoDismissal(bottomAction: false)
    }

    private func assertFfmiInfoDismissal(bottomAction: Bool) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestBodyScoreOnboardingFixture",
            "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        if bottomAction { app.launchArguments.append("-lybUITestFFMIDismissTarget") }
        app.launch()

        let start = app.buttons["body_score_onboarding_start_button"]
        waitForFfmiControl(start, timeout: 15)
        start.tap()
        let male = app.buttons["Male"]
        waitForFfmiControl(male)
        male.tap()
        let next = app.buttons["body_score_onboarding_basics_continue_button"]
        waitForFfmiControl(next)
        next.tap()
        XCTAssertTrue(app.staticTexts["How tall are you?"].waitForExistence(timeout: 8))
        let why = app.buttons["Why we ask"]
        waitForFfmiControl(why)
        why.tap()
        let info = app.buttons["What's FFMI?"]
        waitForFfmiControl(info)
        info.tap()

        let bottomDone = app.buttons["ffmi_info_done_button"]
        let toolbarDone = app.navigationBars.buttons["Done"]
        let done = bottomAction ? bottomDone : toolbarDone
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let ready = expectation(for: NSPredicate { _, _ in
            done.isEnabled && done.isHittable
        }, evaluatedWith: done)
        let readiness = XCTWaiter.wait(for: [ready], timeout: 5)
        let prefix = bottomAction ? "ffmi-dismiss-gate-on" : "ffmi-dismiss-gate-off"
        captureFfmiDismissal(app, control: done, named: prefix + "-before")
        XCTAssertEqual(readiness, .completed, "Done must be enabled and hittable before the single tap")
        XCTAssertEqual(bottomDone.exists, bottomAction)
        XCTAssertEqual(toolbarDone.exists, !bottomAction)
        let frame = done.frame
        XCTAssertFalse(frame.isEmpty)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(frame), "Done must be fully inside the observed window")
        if bottomAction {
            XCTAssertGreaterThanOrEqual(frame.width, 44, "FFMI Done \(frame)")
            XCTAssertGreaterThanOrEqual(frame.height, 44, "FFMI Done \(frame)")
        }

        done.tap()
        let dismissed = done.waitForNonExistence(timeout: 5)
        let returned = expectation(for: NSPredicate { _, _ in
            info.exists && info.isHittable && app.staticTexts["How tall are you?"].exists
        }, evaluatedWith: app)
        let returnResult = XCTWaiter.wait(for: [returned], timeout: 5)
        captureFfmiDismissal(app, control: info, named: prefix + "-returned")
        XCTAssertTrue(dismissed, "One Done tap must dismiss the sheet")
        XCTAssertEqual(returnResult, .completed, "Dismissal must return to the originating height step")
    }

    private func waitForFfmiControl(_ control: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(control.waitForExistence(timeout: timeout))
        let ready = expectation(for: NSPredicate { _, _ in
            control.isEnabled && control.isHittable
        }, evaluatedWith: control)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
    }

    private func captureFfmiDismissal(_ app: XCUIApplication, control: XCUIElement, named name: String) {
        let original = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        original.name = name
        original.lifetime = .keepAlways
        add(original)
        let exists = control.exists
        let controlState = exists
            ? "frame=\(control.frame); enabled=\(control.isEnabled); hittable=\(control.isHittable)"
            : "absent"
        let geometry = XCTAttachment(string:
            "controlExists=\(exists); \(controlState); window=\(app.windows.firstMatch.frame)\n"
                + app.debugDescription
        )
        geometry.name = name + "-geometry-accessibility"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    func testExportCancelMeetsMinimumHitTarget() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestWeightLoggerMVPFixture",
            "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Weight log"].waitForExistence(timeout: 20))
        let settings = app.buttons["mvp_settings_button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let export = app.buttons["home_v2_settings_export"]
        var swipes = 0
        while !export.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(export.waitForExistence(timeout: 8))
        export.tap()

        XCTAssertTrue(app.staticTexts["Export your data"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["world_class_screen_exportData"].waitForExistence(timeout: 5)
        )
        let cancel = app.buttons["Cancel export"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let frame = cancel.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Cancel export \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Cancel export \(frame)")
        var exportAction = app.descendants(matching: .any)["export_data_action"]
        if !exportAction.waitForExistence(timeout: 2) {
            app.swipeUp()
            exportAction = app.descendants(matching: .any)["export_data_action"]
        }
        XCTAssertTrue(
            exportAction.waitForExistence(timeout: 5),
            "export action missing; buttons \(app.buttons.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        let actionFrame = exportAction.frame
        XCTAssertGreaterThanOrEqual(actionFrame.width, 44, "Export action \(actionFrame)")
        XCTAssertGreaterThanOrEqual(actionFrame.height, 44, "Export action \(actionFrame)")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["world_class_screen_exportData"].waitForNonExistence(timeout: 5)
        )
    }
}

extension XCUIApplication {
    /// Forward native XCTest context without inventing a marker for ordinary launches.
    func forwardActualXCTestContext() {
        for key in ["XCTestConfigurationFilePath", "XCTestSessionIdentifier", "XCTestBundlePath"] {
            if let value = ProcessInfo.processInfo.environment[key],
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                launchEnvironment[key] = value
            } else {
                launchEnvironment.removeValue(forKey: key)
            }
        }
    }
}
