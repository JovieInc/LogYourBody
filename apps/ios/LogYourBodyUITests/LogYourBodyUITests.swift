//
// LogYourBodyUITests.swift
// LogYourBody
//
import XCTest

final class LogYourBodyUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSignedOutAppleSignInVisibleByDefault() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestSignedOutFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["LogYourBody"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["login_email_field"].exists)
        XCTAssertTrue(app.buttons["login_email_code_button"].exists)
        XCTAssertTrue(app.buttons["Continue with Apple"].exists)
    }

    func testEmailVerificationFixtureShowsOTPReadyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestEmailVerificationFixture"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["email_verification_screen"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Verify Your Email"].exists)
        XCTAssertTrue(app.staticTexts["email_verification_pending_email"].exists)
        XCTAssertEqual(app.staticTexts["email_verification_pending_email"].label, "otp-ready-ui@example.com")
        XCTAssertTrue(app.descendants(matching: .any)["email_verification_code_field"].exists)
        XCTAssertTrue(app.buttons["email_verification_verify_button"].exists)
        XCTAssertFalse(app.buttons["email_verification_verify_button"].isEnabled)
        XCTAssertTrue(app.staticTexts["email_verification_resend_timer"].exists)
    }

    func testPaidMVPWeightEntrySavesWithKeyboardOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestWeightLoggerMVPFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Weight log"].waitForExistence(timeout: 10))

        let weightField = app.textFields["mvp_weight_text_field"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        weightField.typeText("182.4")

        let keyboardSaveButton = app.buttons["mvp_keyboard_save_weight_bar_button"]
        XCTAssertTrue(keyboardSaveButton.waitForExistence(timeout: 3))
        XCTAssertTrue(keyboardSaveButton.isEnabled)
        keyboardSaveButton.tap()

        let savedMessage = app.descendants(matching: .any)["mvp_weight_saved_message"]
        XCTAssertTrue(savedMessage.waitForExistence(timeout: 8))
        XCTAssertTrue(savedMessage.label.contains("Saved locally"))
        XCTAssertFalse(app.staticTexts["Pending"].exists)

        let savedWeight = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "182.4")
        ).firstMatch
        XCTAssertTrue(savedWeight.waitForExistence(timeout: 5))
    }

    func testPaywallFixtureShowsRestoreAndLogoutEscapePaths() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestPaywallFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["paywall_title"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["paywall_plans_unavailable_state"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["$79.99"].waitForExistence(timeout: 3))

        let supportButton = app.buttons["Contact Support"]
        XCTAssertTrue(supportButton.waitForExistence(timeout: 3))
        XCTAssertTrue(supportButton.isHittable)

        let restoreButton = app.buttons["paywall_restore_purchases_button"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 3))
        XCTAssertTrue(restoreButton.isHittable)

        let logoutButton = app.buttons["paywall_logout_button"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 3))
        XCTAssertTrue(logoutButton.isHittable)
    }

    func testPaywallPlansFixtureShowsMonthlyAnnualAndSavings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestPaywallPlansFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["paywall_title"].waitForExistence(timeout: 10))

        let monthlyPlan = app.buttons["Monthly plan"]
        XCTAssertTrue(monthlyPlan.waitForExistence(timeout: 3))
        XCTAssertTrue(monthlyPlan.isHittable)

        let annualPlan = app.buttons["Annual plan"]
        XCTAssertTrue(annualPlan.waitForExistence(timeout: 3))
        XCTAssertTrue(annualPlan.isHittable)

        XCTAssertTrue(app.staticTexts["$9.99"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["$69.99"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Save 42%"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["$5.83/mo, billed yearly"].waitForExistence(timeout: 3))

        let purchaseButton = app.buttons["paywall_purchase_button"]
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 3))
        XCTAssertTrue(purchaseButton.isHittable)
    }

    func testSubscribedMVPSettingsExposeSubscriptionEscapePaths() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestWeightLoggerMVPFixture"]
        app.launch()

        try openSettings(in: app)

        let logoutButton = app.descendants(matching: .any)["settings_logout_button"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 5))
        XCTAssertTrue(logoutButton.isHittable)

        let manageSubscriptionButton = app.descendants(matching: .any)["settings_manage_subscription_button"]
        scrollUntilHittable(manageSubscriptionButton, in: app)
        XCTAssertTrue(manageSubscriptionButton.exists)

        let restoreButton = app.descendants(matching: .any)["settings_restore_purchases_button"]
        scrollUntilHittable(restoreButton, in: app)
        XCTAssertTrue(restoreButton.exists)
    }

    func testSubscribedMVPSettingsWeightGoalUsesNativeValidatedEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestWeightLoggerMVPFixture"]
        app.launch()

        try openSettings(in: app)

        let weightGoalButton = app.buttons["settings_weight_goal_edit_button"]
        scrollUntilHittable(weightGoalButton, in: app)
        XCTAssertTrue(weightGoalButton.waitForExistence(timeout: 5))
        XCTAssertTrue(weightGoalButton.isHittable)
        weightGoalButton.tap()

        let field = app.descendants(matching: .any)["settings_goal_editor_text_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        let error = app.staticTexts["settings_goal_editor_error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertEqual(error.label, "Enter a value.")
        XCTAssertFalse(app.buttons["Save"].isEnabled)

        field.tap()
        field.typeText("180")

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(weightGoalButton.waitForExistence(timeout: 5))
        XCTAssertTrue(weightGoalButton.label.contains("180.0 lbs"))
    }

    func testPaidMVPFixtureRoutesToDefaultTimelineSurface() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestPaidMVPFixture"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["photo_timeline_root_pager"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["photo_timeline_root_page_timeline"].exists)
        XCTAssertTrue(app.staticTexts["Start with a photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Weight log"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["legacy_full_dashboard_beta"].exists)
    }

    func testLegacyDashboardFixtureRoutesOnlyToLegacyBetaSurface() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestFullDashboardFixture"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["legacy_full_dashboard_beta"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Metrics"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_hud"].exists)
    }

    func testPhotoHUDFixtureRoutesToIntendedPostMVPDashboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestPhotoTimelineHUDFixture"]
        app.launch()

        let pager = app.descendants(matching: .any)["photo_timeline_root_pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_hud_stats_button"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_root_page_analytics"].exists)

        let swipeStart = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let swipeEnd = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)

        XCTAssertTrue(app.descendants(matching: .any)["photo_timeline_root_page_analytics"].waitForExistence(timeout: 10))
        let presenceSummary = app.descendants(matching: .any)["photo_timeline_stats_presence_summary"]
        XCTAssertTrue(presenceSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(presenceSummary.label.contains("Measured"))
        XCTAssertTrue(presenceSummary.label.contains("Interpolated"))
        XCTAssertFalse(app.staticTexts["Timeline states"].exists)
        attachScreenshot(named: "launch-quality-analytics", from: app)
        XCTAssertFalse(app.descendants(matching: .any)["legacy_full_dashboard_beta"].exists)
    }

    func testPhotoHUDFixtureDefaultsToAvatarHeroWhenNoPhotoExists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestPhotoTimelineHUDFixture"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["dashboard_home_timeline_hero"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard_home_timeline_avatar"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard_home_timeline_photo_stage"].exists)
    }

    func testLaunchQualityGateCapturesTimelineHomeSurface() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestPhaseInsightFixture",
            "-lybUITestGlp1WeeklyCheckInFixture"
        ]

        app.launch()

        let hero = app.descendants(matching: .any)["dashboard_home_timeline_hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))

        let window = app.windows.firstMatch
        let windowFrame = window.frame
        XCTAssertGreaterThan(hero.frame.width, windowFrame.width * 0.82)
        XCTAssertGreaterThanOrEqual(hero.frame.minX, windowFrame.minX - 1)
        XCTAssertLessThanOrEqual(hero.frame.maxX, windowFrame.maxX + 1)

        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_hud_stats_button"].exists)
        attachScreenshot(named: "launch-quality-home-timeline", from: app)
    }

    func testLaunchQualityGateCapturesBodyScoreShareSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestPhaseInsightFixture",
            "-lybUITestGlp1WeeklyCheckInFixture"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["dashboard_home_timeline_hero"].waitForExistence(timeout: 10))

        let shareButton = app.descendants(matching: .any)["body_score_hero_share_button"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
        XCTAssertTrue(shareButton.isHittable)
        shareButton.tap()

        let shareCard = app.descendants(matching: .any)["body_score_share_card"]
        XCTAssertTrue(shareCard.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["body_score_share_avatar_visual"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["body_score_share_save_button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["body_score_share_system_button"].exists)

        let cardFrame = shareCard.frame
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(cardFrame.width, windowFrame.width * 0.88)
        attachScreenshot(named: "launch-quality-body-score-share", from: app)
    }

    func testLaunchQualityGateCapturesOnboardingFixedCTA() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestBodyScoreOnboardingFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Get your Body Score in 60 seconds."].waitForExistence(timeout: 10))

        let startButton = app.buttons["Start my 60-sec Body Score"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertTrue(startButton.isHittable)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(startButton.frame.minY, windowFrame.height * 0.72)
        XCTAssertLessThanOrEqual(startButton.frame.maxY, windowFrame.maxY + 1)
        attachScreenshot(named: "launch-quality-onboarding-fixed-cta", from: app)
    }

    func testLaunchQualityGateCapturesOnboardingFirstPhotoCTA() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestBodyScoreFirstPhotoFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Start your visual timeline."].waitForExistence(timeout: 10))

        let addPhotoButton = app.buttons["Add first photo"]
        let skipButton = app.buttons["Skip for now"]
        XCTAssertTrue(addPhotoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        XCTAssertTrue(addPhotoButton.isHittable)
        XCTAssertTrue(skipButton.isHittable)
        XCTAssertFalse(app.buttons["Continue"].exists)

        attachScreenshot(named: "launch-quality-onboarding-first-photo", from: app)
    }

    func testPhaseInsightFixtureShowsDeterministicCuttingInsight() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestPhaseInsightFixture"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["dashboard_home_timeline_hero"].waitForExistence(timeout: 10))

        let insight = app.descendants(matching: .any)["photo_timeline_hud_phase_insight"]
        scrollUntilExists(insight, in: app)
        XCTAssertTrue(insight.waitForExistence(timeout: 8))
        let expectedInsight = NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@",
            "Cutting",
            "Weight is trending down"
        )
        expectation(for: expectedInsight, evaluatedWith: insight)
        waitForExpectations(timeout: 5)
    }

    func testGlp1WeeklyCheckInFixtureShowsPromptAndOpensDoseFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestGlp1WeeklyCheckInFixture"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["dashboard_home_timeline_hero"].waitForExistence(timeout: 10))

        let prompt = app.buttons["photo_timeline_hud_glp1_weekly_checkin"]
        scrollUntilExists(prompt, in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))

        scrollUntilHittable(prompt, in: app)
        XCTAssertTrue(prompt.isHittable)
        prompt.tap()

        XCTAssertTrue(app.staticTexts["Log GLP-1 dose"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Zepbound"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Save GLP-1"].exists)
    }

    func testBulkPhotoImportLockedByDefaultInIntegrations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestWeightLoggerMVPFixture"]
        app.launch()

        try openIntegrations(in: app)

        let lockedRow = app.descendants(matching: .any)["integrations_bulk_photo_import_locked"]
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Locked"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["integrations_bulk_photo_import_link"].exists)
        XCTAssertFalse(app.staticTexts["Bulk Photo Import"].exists)
        XCTAssertFalse(app.staticTexts["Google Fit"].exists)
        XCTAssertFalse(app.staticTexts["Export as JSON"].exists)
        XCTAssertFalse(app.staticTexts["API Access"].exists)
        XCTAssertFalse(app.staticTexts["Coming Soon"].exists)
    }

    func testBulkPhotoImportActivationOpensScannerEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestWeightLoggerMVPFixture",
            "-lybUITestBulkPhotoImportEnabledFixture"
        ]
        app.launch()

        try openIntegrations(in: app)

        let importLink = app.descendants(matching: .any)["integrations_bulk_photo_import_link"]
        XCTAssertTrue(importLink.waitForExistence(timeout: 8))

        let importButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Import Progress Photos")
        ).firstMatch
        scrollUntilHittable(importButton, in: app)
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertTrue(importButton.isHittable)
        importButton.tap()

        XCTAssertTrue(app.staticTexts["Bulk Photo Import"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Start Scanning"].exists)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) {
        var remainingSwipes = maxSwipes
        while !element.isHittable && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    private func scrollUntilExists(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 8
    ) {
        var remainingSwipes = maxSwipes
        while !element.exists && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openIntegrations(in app: XCUIApplication) throws {
        try openSettings(in: app)

        let integrationsButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Integrations")
        ).firstMatch
        scrollUntilHittable(integrationsButton, in: app)
        XCTAssertTrue(integrationsButton.waitForExistence(timeout: 5))
        XCTAssertTrue(integrationsButton.isHittable)
        integrationsButton.tap()

        XCTAssertTrue(app.navigationBars["Integrations"].waitForExistence(timeout: 5))
    }

    private func openSettings(in app: XCUIApplication) throws {
        XCTAssertTrue(app.staticTexts["Weight log"].waitForExistence(timeout: 10))

        let settingsButton = app.buttons["mvp_settings_button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
    }
}
