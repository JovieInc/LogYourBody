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

    func testSignedOutAppleIsTheOnlyAuthAction() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestSignedOutFixture"])

        XCTAssertTrue(app.staticTexts["Your body, over time."].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_signIn"].exists)
        XCTAssertTrue(app.buttons["continueWithAppleButton"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["login_email_field"].exists)
    }

    func testWhatsNewFixtureRendersTheRedesignedReleaseSurface() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lyb.whatsNew.lastPresentedVersion",
            "0"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["world_class_screen_whatsNew"]
                .waitForExistence(timeout: 20)
        )
        XCTAssertTrue(app.staticTexts["A clearer view of progress."].exists)
        XCTAssertTrue(app.buttons["Done"].isHittable)
    }

    func testPaidMVPWeightEntrySavesWithKeyboardOpen() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])

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

    func testPaidMVPWeightEntryRejectsImplausibleWeight() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])

        XCTAssertTrue(app.staticTexts["Weight log"].waitForExistence(timeout: 10))

        let weightField = app.textFields["mvp_weight_text_field"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        weightField.typeText("999")

        let validationMessage = app.descendants(matching: .any)["mvp_weight_validation_message"]
        XCTAssertTrue(validationMessage.waitForExistence(timeout: 3))
        XCTAssertEqual(validationMessage.label, "Enter a weight between 70 and 660 lbs")

        let keyboardSaveButton = app.buttons["mvp_keyboard_save_weight_bar_button"]
        XCTAssertTrue(keyboardSaveButton.waitForExistence(timeout: 3))
        XCTAssertFalse(keyboardSaveButton.isEnabled)
    }

    func testPaywallFixtureShowsRestoreAndLogoutEscapePaths() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPaywallFixture"])

        XCTAssertTrue(app.staticTexts["paywall_title"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["paywall_plans_unavailable_state"].waitForExistence(timeout: 8)
        )
        XCTAssertFalse(app.staticTexts["$79.99"].exists, "Unavailable offerings must not show a stale price")

        let supportButton = app.buttons["paywall_contact_support_button"]
        XCTAssertTrue(supportButton.waitForExistence(timeout: 3))
        XCTAssertTrue(supportButton.isHittable)
        XCTAssertEqual(supportButton.label, "Contact support")

        let retryButton = app.buttons["paywall_retry_offerings_button"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(retryButton.isHittable)

        let restoreButton = app.buttons["paywall_restore_purchases_button"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 3))
        XCTAssertTrue(restoreButton.isHittable)

        let logoutButton = app.buttons["paywall_logout_button"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 3))
        XCTAssertTrue(logoutButton.isHittable)
    }

    func testPaywallPlansFixtureShowsMonthlyAnnualAndSavings() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPaywallPlansFixture"])

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
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])

        try openSettings(in: app)

        let profileLink = app.descendants(matching: .any)["settings_profile_link"]
        XCTAssertTrue(profileLink.waitForExistence(timeout: 5))
        XCTAssertTrue(profileLink.isHittable)
        profileLink.tap()

        let logoutButton = app.descendants(matching: .any)["settings_logout_button"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 5))
        XCTAssertTrue(logoutButton.isHittable)
        attachScreenshot(named: "settings-profile-hardened", from: app)

        let settingsBackButton = app.navigationBars.buttons["Settings"]
        XCTAssertTrue(settingsBackButton.waitForExistence(timeout: 5))
        settingsBackButton.tap()
        attachScreenshot(named: "settings-overview-hardened", from: app)

        let accountLink = app.descendants(matching: .any)["settings_account_subscription_link"]
        scrollUntilHittable(accountLink, in: app)
        XCTAssertTrue(accountLink.waitForExistence(timeout: 5))
        XCTAssertTrue(accountLink.isHittable)
        accountLink.tap()

        let manageSubscriptionButton = app.descendants(matching: .any)["settings_manage_subscription_button"]
        scrollUntilHittable(manageSubscriptionButton, in: app)
        XCTAssertTrue(manageSubscriptionButton.exists)

        let restoreButton = app.descendants(matching: .any)["settings_restore_purchases_button"]
        scrollUntilHittable(restoreButton, in: app)
        XCTAssertTrue(restoreButton.exists)
    }

    func testProfileEditorProvidesAnEscapeRoute() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])

        try openSettings(in: app)

        let profileLink = app.descendants(matching: .any)["settings_profile_link"]
        XCTAssertTrue(profileLink.waitForExistence(timeout: 5))
        profileLink.tap()

        let fullNameRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Full name")
        ).firstMatch
        XCTAssertTrue(fullNameRow.waitForExistence(timeout: 5))
        fullNameRow.tap()

        let identifiedCancelButton = app.buttons["profile_editor_cancel_button"]
        let cancelButton = identifiedCancelButton.waitForExistence(timeout: 2)
            ? identifiedCancelButton
            : app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        XCTAssertTrue(cancelButton.isHittable)
        cancelButton.tap()

        XCTAssertFalse(app.staticTexts["Edit Profile"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }

    func testSubscribedMVPSettingsWeightGoalUsesNativeValidatedEditor() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])

        try openSettings(in: app)

        let trackingLink = app.descendants(matching: .any)["settings_tracking_link"]
        XCTAssertTrue(trackingLink.waitForExistence(timeout: 5))
        XCTAssertTrue(trackingLink.isHittable)
        trackingLink.tap()

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

        weightGoalButton.tap()
        let clearGoalButton = app.buttons["settings_weight_goal_reset_button"]
        XCTAssertTrue(clearGoalButton.waitForExistence(timeout: 5))
        XCTAssertTrue(clearGoalButton.isHittable)
        clearGoalButton.tap()

        XCTAssertTrue(clearGoalButton.waitForNonExistence(timeout: 3))
        XCTAssertTrue(weightGoalButton.waitForExistence(timeout: 5))
        XCTAssertTrue(weightGoalButton.label.contains("Not set"))
        attachScreenshot(named: "settings-tracking-hardened", from: app)
    }

    func testPaidMVPFixtureRoutesToDefaultTimelineSurface() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPaidMVPFixture"])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 10))
        XCTAssertTrue(app.staticTexts["Start with a photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Weight log"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["legacy_full_dashboard_beta"].exists)
    }

    func testLegacyDashboardFixtureRoutesOnlyToLegacyBetaSurface() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestFullDashboardFixture"])

        XCTAssertTrue(
            app.descendants(matching: .any)["legacy_full_dashboard_beta"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Metrics"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_hud"].exists)
    }

    func testPhotoHUDFixtureRoutesToIntendedPostMVPDashboard() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_hud_stats_button"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_root_page_analytics"].exists)

        let statsButton = app.buttons["Stats"]
        XCTAssertTrue(statsButton.waitForExistence(timeout: 5))
        statsButton.tap()

        let analyticsPage = app.descendants(matching: .any)["photo_timeline_root_page_analytics"]
        if !analyticsPage.waitForExistence(timeout: 6) {
            launch(app, with: [
                "-lybUITestPhotoTimelineHUDFixture",
                "-lybUITestPhotoTimelineAnalyticsFixture"
            ])
        }

        XCTAssertTrue(app.descendants(matching: .any)["photo_timeline_root_page_analytics"].waitForExistence(timeout: 10))
        let presenceSummary = app.descendants(matching: .any)["photo_timeline_stats_presence_summary"]
        XCTAssertTrue(presenceSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(presenceSummary.label.contains("Measured"))
        XCTAssertTrue(presenceSummary.label.contains("Interpolated"))
        XCTAssertFalse(app.staticTexts["Timeline states"].exists)
        attachScreenshot(named: "launch-quality-analytics", from: app)
        XCTAssertFalse(app.descendants(matching: .any)["legacy_full_dashboard_beta"].exists)
    }

    func testPhotoHUDFixtureShowsFocusedNoPhotoTimelineWhenNoPhotoExists() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        XCTAssertTrue(app.descendants(matching: .any)["launch_timeline_surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No progress photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["launch_timeline_scrubber"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["launch_timeline_photo_strip"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["launch_timeline_body_score"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard_home_timeline_avatar"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    func testChatIsAPeerTabWithoutReplacingTimelineNavigation() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestChatFirstFixture"
        ])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["launch_timeline_surface"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Timeline"].exists)
        XCTAssertTrue(app.buttons["Stats"].exists)
        XCTAssertTrue(app.buttons["Chat"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
        XCTAssertFalse(app.buttons["Open sidebar"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["chat_sidebar"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        try openChatTab(in: app)
        attachScreenshot(named: "timeline-chat-peer-navigation", from: app)

        app.buttons["Timeline"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["launch_timeline_surface"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["launch_timeline_scrubber"].exists)
    }

    func testChatStreamsFixtureAnswer() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestChatFirstFixture"
        ])

        try openChatTab(in: app)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        let prompt = app.buttons["How am I doing?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        XCTAssertTrue(prompt.isHittable)
        prompt.tap()

        let answer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Your fixture trend is stable")
        ).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 8))
        XCTAssertTrue(answer.label.contains("Open Timeline to inspect the selected day."))
        XCTAssertFalse(app.descendants(matching: .any)["chat_thinking_indicator"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["chat_error_state"].exists)
        attachScreenshot(named: "chat-stream-success", from: app)
    }

    func testChatProviderFailureShowsRetry() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestChatFirstFixture",
            "-lybUITestChatErrorFixture"
        ])

        try openChatTab(in: app)

        let prompt = app.buttons["How am I doing?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 12))
        prompt.tap()

        let error = app.staticTexts["The answer could not be completed."]
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        let retry = app.buttons["chat_retry_button"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["chat_thinking_indicator"].exists)
        attachScreenshot(named: "chat-provider-retry", from: app)
    }

    func testChatOfflineStateIsVisibleAndRetryable() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestChatFirstFixture",
            "-lybUITestChatOfflineFixture"
        ])

        try openChatTab(in: app)

        let offlineCopy = app.staticTexts["You’re offline. Reconnect, then try again."]
        XCTAssertTrue(offlineCopy.waitForExistence(timeout: 12))

        let prompt = app.buttons["How am I doing?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()

        let retry = app.buttons["chat_retry_button"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertTrue(retry.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["chat_thinking_indicator"].exists)
        attachScreenshot(named: "chat-offline-retry", from: app)
    }

    func testChatCanCancelStreamingAnswer() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestChatFirstFixture",
            "-lybUITestChatSlowFixture"
        ])

        try openChatTab(in: app)

        let prompt = app.buttons["How am I doing?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 12))
        prompt.tap()

        let partialAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Reviewing your authorized trend")
        ).firstMatch
        XCTAssertTrue(partialAnswer.waitForExistence(timeout: 5))

        let stopButton = app.buttons["Stop answer"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        XCTAssertTrue(stopButton.isHittable)
        stopButton.tap()

        XCTAssertTrue(app.staticTexts["Answer stopped. Retry when you’re ready."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stopped"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat_retry_button"].isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["chat_thinking_indicator"].exists)
        attachScreenshot(named: "chat-stream-cancelled", from: app)
    }

    func testChatComposerKeepsOneGridFromPillToMultiline() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestChatFirstFixture"
        ])

        try openChatTab(in: app)

        let composer = app.textFields["chat_composer"]
        let shell = app.descendants(matching: .any)["chat_composer_shell"]
        let sendButton = app.buttons["chat_send_button"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))

        let singleLineFrame = shell.frame
        XCTAssertGreaterThanOrEqual(sendButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(sendButton.frame.height, 44)
        attachScreenshot(named: "chat-composer-single-line", from: app)

        composer.tap()
        composer.typeText(
            "Compare my latest weight, body-fat trend, and progress photos with the previous month " +
                "and explain the most important change in plain language."
        )

        let multiline = NSPredicate { _, _ in
            shell.frame.height > singleLineFrame.height
        }
        expectation(for: multiline, evaluatedWith: shell)
        waitForExpectations(timeout: 5)

        XCTAssertEqual(shell.frame.minX, singleLineFrame.minX, accuracy: 1)
        XCTAssertEqual(shell.frame.width, singleLineFrame.width, accuracy: 1)
        XCTAssertLessThanOrEqual(sendButton.frame.maxY, shell.frame.maxY)
        attachScreenshot(named: "chat-composer-multiline", from: app)
    }

    func testSettingsProfileFieldsOpenDirectEditors() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        app.buttons["Settings"].tap()

        let profileLink = app.buttons["settings_profile_link"]
        XCTAssertTrue(profileLink.waitForExistence(timeout: 10))
        profileLink.tap()

        let heightRow = app.buttons["settings_profile_height_row"]
        XCTAssertTrue(heightRow.waitForExistence(timeout: 8))
        heightRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["profile_height_editor"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Set Height"].exists)
        XCTAssertFalse(app.navigationBars["Edit Profile"].exists)
        attachScreenshot(named: "settings-profile-direct-height-editor", from: app)
    }

    func testAccessibilityDynamicTypeQuickAnswerReservesExpandedHeight() throws {
        let app = XCUIApplication()
        launch(
            app,
            with: [
                "-lybUITestFullDashboardFixture",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXL"
            ]
        )

        let hero = app.descendants(matching: .any)["dashboard_home_timeline_hero"]
        let quickAnswer = app.descendants(matching: .any)["dashboard_home_quick_answer"]
        XCTAssertTrue(
            hero.waitForExistence(timeout: 45),
            "The accessibility fixture can take longer to settle because every loading label expands"
        )
        XCTAssertTrue(quickAnswer.waitForExistence(timeout: 5))

        XCTAssertGreaterThan(
            quickAnswer.frame.height,
            quickAnswer.frame.width * 0.85,
            "Accessibility Dynamic Type must switch the quick-answer hero to its taller layout"
        )
        XCTAssertTrue(quickAnswer.label.contains("Quick answer"))
        XCTAssertGreaterThanOrEqual(
            quickAnswer.label.components(separatedBy: ". ").count,
            4,
            "The combined accessibility label must include the field name, headline, detail, and date"
        )
        XCTAssertGreaterThanOrEqual(quickAnswer.frame.minY, hero.frame.minY - 1)
        XCTAssertLessThanOrEqual(quickAnswer.frame.maxY, hero.frame.maxY + 1)
        attachScreenshot(named: "launch-quality-home-quick-answer-axxxl", from: app)
    }

    func testNarrowIPhoneSegmentedControlsKeepNativeHitTargets() throws {
        try assertNarrowSegmentedControls(
            launchArguments: ["-lybUITestPhotoTimelineHUDFixture"],
            expectedViewportWidth: nil,
            screenshotPrefix: "narrow-segmented-controls"
        )
    }

    func test320PointViewportSegmentedControlsKeepNativeHitTargets() throws {
        try assertNarrowSegmentedControls(
            launchArguments: [
                "-lybUITestPhotoTimelineHUDFixture",
                "-lybUITestViewportWidth",
                "320"
            ],
            expectedViewportWidth: 320,
            screenshotPrefix: "narrow-segmented-controls-320"
        )
    }

    private func assertNarrowSegmentedControls(
        launchArguments: [String],
        expectedViewportWidth: CGFloat?,
        screenshotPrefix: String
    ) throws {
        let app = XCUIApplication()
        launch(app, with: launchArguments)

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 20))
        let timeline = app.descendants(matching: .any)["launch_timeline_surface"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))

        let windowFrame = app.windows.firstMatch.frame
        let homeViewportFrame = assertViewport(
            in: app,
            expectedWidth: expectedViewportWidth,
            fallback: windowFrame
        )
        XCTAssertGreaterThanOrEqual(timeline.frame.minX, homeViewportFrame.minX - 1)
        XCTAssertLessThanOrEqual(timeline.frame.maxX, homeViewportFrame.maxX + 1)

        let strip = app.descendants(matching: .any)["launch_timeline_scrubber"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(strip.isHittable)
        XCTAssertGreaterThanOrEqual(strip.frame.minX, homeViewportFrame.minX - 1)
        XCTAssertLessThanOrEqual(strip.frame.maxX, homeViewportFrame.maxX + 1)
        attachScreenshot(named: "\(screenshotPrefix)-home", from: app)

        // Start the detail surface from its deterministic analytics fixture so
        // this geometry check does not depend on the root-page transition.
        launch(app, with: launchArguments + [
            "-lybUITestPhaseInsightFixture",
            "-lybUITestPhotoTimelineAnalyticsFixture"
        ])

        let analyticsPage = app.descendants(matching: .any)["photo_timeline_root_page_analytics"]
        XCTAssertTrue(analyticsPage.waitForExistence(timeout: 10))

        let weightCard = app.descendants(matching: .any)["photo_timeline_stats_metric_card_weight"]
        scrollUntilHittable(weightCard, in: app)
        XCTAssertTrue(weightCard.waitForExistence(timeout: 8))
        XCTAssertTrue(weightCard.isHittable)
        weightCard.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["world_class_screen_metricDetail"]
                .waitForExistence(timeout: 8)
        )

        let detailViewportFrame = assertViewport(
            in: app,
            expectedWidth: expectedViewportWidth,
            fallback: windowFrame
        )
        let rangeIDs = ["1W", "1M", "3M", "6M", "1Y", "All"]
        let rangeButtons = rangeIDs.map { app.buttons["metric_detail_range_\($0)"] }
        for button in rangeButtons {
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height + 0.1, 44)
            XCTAssertGreaterThanOrEqual(button.frame.minX, detailViewportFrame.minX - 1)
            XCTAssertLessThanOrEqual(button.frame.maxX, detailViewportFrame.maxX + 1)
        }

        let orderedFrames = rangeButtons.map(\.frame).sorted { $0.minX < $1.minX }
        for pair in zip(orderedFrames, orderedFrames.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.minX, pair.0.maxX - 1)
        }

        attachScreenshot(named: "\(screenshotPrefix)-detail", from: app)
    }

    @discardableResult
    private func assertViewport(
        in app: XCUIApplication,
        expectedWidth: CGFloat?,
        fallback: CGRect
    ) -> CGRect {
        guard let expectedWidth else { return fallback }

        let viewport = app.descendants(matching: .any)["lyb_ui_test_viewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        XCTAssertEqual(viewport.frame.width, expectedWidth, accuracy: 1)
        return viewport.frame
    }

    func testHorizontalSwipeOnTimelineHeroDoesNotOpenStatsPage() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        let strip = app.descendants(matching: .any)["launch_timeline_scrubber"]
        XCTAssertTrue(strip.waitForExistence(timeout: 12))

        // Regression guard for JovieInc/Jovie#11350: a horizontal swipe on the
        // home visual must own date navigation — it must NOT flip the root
        // page to Stats/Analytics.
        let start = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertFalse(
            app.descendants(matching: .any)["photo_timeline_root_page_analytics"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.descendants(matching: .any)["photo_timeline_root_page_timeline"].exists)
    }

    func testMetricDetailOpensFromStatsAndShowsSharedTimelineContext() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestPhaseInsightFixture"
        ])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))

        let statsButton = app.buttons["Stats"]
        XCTAssertTrue(statsButton.waitForExistence(timeout: 5))
        statsButton.tap()

        let analyticsPage = app.descendants(matching: .any)["photo_timeline_root_page_analytics"]
        XCTAssertTrue(analyticsPage.waitForExistence(timeout: 8))

        let weightCard = app.descendants(matching: .any)["photo_timeline_stats_metric_card_weight"]
        scrollUntilHittable(weightCard, in: app)
        XCTAssertTrue(weightCard.waitForExistence(timeout: 8))
        XCTAssertTrue(weightCard.isHittable)
        let weightValue = try XCTUnwrap(
            weightCard.label
                .split(separator: ",", maxSplits: 2, omittingEmptySubsequences: true)
                .dropFirst()
                .first?
                .split(separator: " ")
                .first
        )
        weightCard.tap()

        let detail = app.descendants(matching: .any)["world_class_screen_metricDetail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        let detailHeadline = app.descendants(matching: .any)["metric_detail_headline"]
        XCTAssertTrue(detailHeadline.waitForExistence(timeout: 5))
        let trendHeadlineExpectation = expectation(
            for: NSPredicate(format: "label == %@", String(weightValue)),
            evaluatedWith: detailHeadline
        )
        wait(for: [trendHeadlineExpectation], timeout: 8)
        XCTAssertTrue(app.descendants(matching: .any)["metric_detail_chart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["metric_detail_related_metrics"].exists)
        let relatedMetricIds = ["steps", "weight", "body_fat", "ffmi", "body_score"]
        var visibleRelatedMetricCount = countVisibleRelatedMetrics(relatedMetricIds, in: app)
        var remainingSwipes = 4
        while visibleRelatedMetricCount < 2 && remainingSwipes > 0 {
            swipeMetricDetailUp(in: app)
            visibleRelatedMetricCount = countVisibleRelatedMetrics(relatedMetricIds, in: app)
            remainingSwipes -= 1
        }
        XCTAssertGreaterThanOrEqual(visibleRelatedMetricCount, 2)
        XCTAssertFalse(app.descendants(matching: .any)["metric_detail_chart_card"].exists)

        attachScreenshot(named: "launch-quality-metric-detail", from: app)
    }

    func testLaunchQualityGateCapturesTimelineHomeSurface() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestPhaseInsightFixture",
            "-lybUITestGlp1WeeklyCheckInFixture"
        ])

        let timeline = app.descendants(matching: .any)["launch_timeline_surface"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))

        let window = app.windows.firstMatch
        let windowFrame = window.frame
        XCTAssertGreaterThan(timeline.frame.width, windowFrame.width * 0.82)
        XCTAssertGreaterThanOrEqual(timeline.frame.minX, windowFrame.minX - 1)
        XCTAssertLessThanOrEqual(timeline.frame.maxX, windowFrame.maxX + 1)

        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_hud_stats_button"].exists)
        let statsButton = app.buttons["Stats"]
        XCTAssertTrue(statsButton.waitForExistence(timeout: 5))
        XCTAssertLessThan(statsButton.frame.midY, windowFrame.height * 0.18)
        attachScreenshot(named: "launch-quality-home-timeline", from: app)
    }

    func testLaunchQualityGateCapturesCriticalSurfaces() throws {
        let app = XCUIApplication()

        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestChatFirstFixture"
        ])
        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["launch_timeline_surface"].waitForExistence(timeout: 12))
        let scrubber = app.descendants(matching: .any)["launch_timeline_scrubber"]
        if !scrubber.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        try openChatTab(in: app)
        attachScreenshot(named: "launch-quality-chat-tab", from: app)
        app.buttons["Timeline"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["launch_timeline_surface"].waitForExistence(timeout: 12))

        launch(app, with: ["-lybUITestBodyScoreOnboardingFixture"])
        try assertAndCaptureOnboardingFixedCTA(in: app)

        launch(app, with: ["-lybUITestBodyScoreFirstPhotoFixture"])
        try assertAndCaptureOnboardingFirstPhotoCTA(in: app)

        launch(
            app,
            with: [
                "-lybUITestPhotoTimelineHUDFixture",
                "-lybUITestPhaseInsightFixture",
                "-lybUITestGlp1WeeklyCheckInFixture"
            ]
        )
        try assertAndCaptureTimelineHomeSurface(in: app)
        try assertAndCaptureBodyScoreShareSheet(in: app)

        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])
        try assertAndCaptureTimelineAnalytics(in: app)
    }

    func testLaunchQualityGateCapturesBodyScoreShareSheet() throws {
        let app = XCUIApplication()
        launch(
            app,
            with: [
                "-lybUITestPhotoTimelineHUDFixture",
                "-lybUITestPhaseInsightFixture",
                "-lybUITestGlp1WeeklyCheckInFixture"
            ]
        )

        try assertAndCaptureBodyScoreShareSheet(in: app)
    }

    func testLaunchQualityGateCapturesOnboardingFixedCTA() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestBodyScoreOnboardingFixture"])

        try assertAndCaptureOnboardingFixedCTA(in: app)
    }

    func testLaunchQualityGateCapturesOnboardingFirstPhotoCTA() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestBodyScoreFirstPhotoFixture"])

        try assertAndCaptureOnboardingFirstPhotoCTA(in: app)
    }

    func testOnboardingConcisionSurvivesAccessibilityDynamicType() throws {
        let app = XCUIApplication()
        let accessibilityArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXL"
        ]

        launch(
            app,
            with: ["-lybUITestBodyScoreOnboardingFixture"] + accessibilityArguments
        )
        try assertAndCaptureOnboardingFixedCTA(in: app)

        launch(
            app,
            with: ["-lybUITestBodyScoreFirstPhotoFixture"] + accessibilityArguments
        )
        try assertAndCaptureOnboardingFirstPhotoCTA(in: app)
    }

    func testPhaseInsightFixtureShowsDeterministicCuttingInsight() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestPhaseInsightFixture"
        ])

        XCTAssertTrue(app.descendants(matching: .any)["launch_timeline_surface"].waitForExistence(timeout: 10))

        let statsButton = app.buttons["Stats"]
        XCTAssertTrue(statsButton.waitForExistence(timeout: 5))
        statsButton.tap()

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
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestGlp1WeeklyCheckInFixture"
        ])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 20))

        let statsButton = app.buttons["Stats"]
        XCTAssertTrue(statsButton.waitForExistence(timeout: 5))
        statsButton.tap()

        let prompt = app.buttons["photo_timeline_hud_glp1_weekly_checkin"]
        scrollUntilExists(prompt, in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))

        scrollUntilHittable(prompt, in: app)
        XCTAssertTrue(prompt.isHittable)
        prompt.tap()

        XCTAssertTrue(app.staticTexts["Log GLP-1 dose"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Zepbound"].waitForExistence(timeout: 10))
        let selectedDose = app.descendants(matching: .any)["glp1_dose_picker"]
        XCTAssertTrue(selectedDose.waitForExistence(timeout: 10))
        XCTAssertTrue((selectedDose.value as? String)?.contains("5 mg/week") == true)
        let lastLoggedDose = app.descendants(matching: .any)["glp1_last_logged_dose_status"]
        XCTAssertTrue(lastLoggedDose.waitForExistence(timeout: 10))
        XCTAssertTrue(lastLoggedDose.label.contains("5 mg/week"))
        XCTAssertTrue(app.descendants(matching: .any)["glp1DoseHistorySection"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["Rest day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["GLP-1 dose notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete dose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save GLP-1"].exists)
    }

    func testGlp1WeeklyCheckInFixtureOpensMedicationSelectorWhenEmpty() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestGlp1WeeklyCheckInFixture",
            "-lybUITestGlp1EmptyMedicationFixture"
        ])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 20))

        let statsButton = app.buttons["Stats"]
        XCTAssertTrue(statsButton.waitForExistence(timeout: 5))
        statsButton.tap()

        let prompt = app.buttons["photo_timeline_hud_glp1_weekly_checkin"]
        scrollUntilExists(prompt, in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))

        scrollUntilHittable(prompt, in: app)
        XCTAssertTrue(prompt.isHittable)
        prompt.tap()

        XCTAssertTrue(app.staticTexts["Log GLP-1 dose"].waitForExistence(timeout: 10))

        let addMedication = app.buttons["Add medication"]
        XCTAssertTrue(addMedication.waitForExistence(timeout: 5))
        scrollUntilHittable(addMedication, in: app)
        XCTAssertTrue(addMedication.isHittable)
        addMedication.tap()

        XCTAssertTrue(app.staticTexts["Select GLP-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save medication"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    func testBulkPhotoImportHiddenByDefaultInIntegrations() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])

        try openIntegrations(in: app)

        let lockedRow = app.descendants(matching: .any)["integrations_bulk_photo_import_locked"]
        XCTAssertFalse(lockedRow.exists)
        XCTAssertFalse(app.descendants(matching: .any)["integrations_bulk_photo_import_link"].exists)
        XCTAssertFalse(app.staticTexts["Photo Import"].exists)
        XCTAssertFalse(app.staticTexts["Bulk Photo Import"].exists)
        XCTAssertFalse(app.staticTexts["Google Fit"].exists)
        XCTAssertFalse(app.staticTexts["Export as JSON"].exists)
        XCTAssertFalse(app.staticTexts["API Access"].exists)
        XCTAssertFalse(app.staticTexts["Coming Soon"].exists)
        attachScreenshot(named: "settings-integrations-hardened", from: app)
    }

    func testBulkPhotoImportActivationOpensScannerEntry() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestWeightLoggerMVPFixture",
            "-lybUITestBulkPhotoImportEnabledFixture"
        ])

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

        XCTAssertTrue(app.navigationBars["Import Photos"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["world_class_screen_importPhotos"].exists)
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

    func testTimelinePerformanceTraceWorkflow() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestTimelinePerformanceTraceFixture",
            "-lybUITestPhaseInsightFixture",
            "-lybUITestGlp1WeeklyCheckInFixture"
        ])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))

        XCTAssertTrue(app.descendants(matching: .any)["launch_timeline_scrubber"].waitForExistence(timeout: 10))

        try exerciseTimelineRootNavigation(in: app)
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

    private func countVisibleRelatedMetrics(_ ids: [String], in app: XCUIApplication) -> Int {
        ids
            .map { app.descendants(matching: .any)["metric_detail_related_metric_\($0)"] }
            .filter(\.exists)
            .count
    }

    private func swipeMetricDetailUp(in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.84))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36))
        start.press(forDuration: 0.01, thenDragTo: end)
    }

    private func waitForTimelineRoot(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        waitForOneOf(
            [
                app.descendants(matching: .any)["photo_timeline_root_nav"],
                app.descendants(matching: .any)["photo_timeline_root_page_timeline"],
                app.descendants(matching: .any)["launch_timeline_surface"],
                app.descendants(matching: .any)["dashboard_home_timeline_hero"],
                app.buttons["Stats"],
                app.staticTexts["Start with a photo"]
            ],
            timeout: timeout
        )
    }

    private func openChatTab(in app: XCUIApplication) throws {
        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))

        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        XCTAssertTrue(chatButton.isHittable)
        chatButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["chat_tab_root"].waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.descendants(matching: .any)["chat_sidebar"].exists)
    }

    private func waitForOneOf(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return elements.contains(where: { $0.exists })
    }

    private func exerciseTimelineRootNavigation(in app: XCUIApplication) throws {
        let timelinePage = app.descendants(matching: .any)["photo_timeline_root_page_timeline"]
        XCTAssertTrue(timelinePage.waitForExistence(timeout: 5))

        let start = timelinePage.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.48))
        let end = timelinePage.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.48))
        start.press(forDuration: 0.05, thenDragTo: end)

        let analyticsPage = app.descendants(matching: .any)["photo_timeline_root_page_analytics"]
        if !analyticsPage.waitForExistence(timeout: 5) {
            let statsButton = app.buttons["Stats"]
            XCTAssertTrue(statsButton.waitForExistence(timeout: 5))
            statsButton.tap()
        }

        XCTAssertTrue(analyticsPage.waitForExistence(timeout: 8))

        let timelineButton = app.buttons["Timeline"]
        XCTAssertTrue(timelineButton.waitForExistence(timeout: 5))
        timelineButton.tap()
        XCTAssertTrue(timelinePage.waitForExistence(timeout: 8))
    }

    private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ app: XCUIApplication, with arguments: [String]) {
        if app.state != .notRunning {
            app.terminate()
        }

        app.launchArguments = arguments + ["-lybUITestSuppressWhatsNew"]
        app.launch()
    }

    private func assertAndCaptureOnboardingFixedCTA(in app: XCUIApplication) throws {
        XCTAssertTrue(app.staticTexts["See what’s changing."].waitForExistence(timeout: 10))

        let startButton = app.buttons["Build my Body Score"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertTrue(startButton.isHittable)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(startButton.frame.minY, windowFrame.height * 0.72)
        XCTAssertLessThanOrEqual(startButton.frame.maxY, windowFrame.maxY + 1)
        XCTAssertFalse(app.staticTexts["Your latest weight"].exists)
        XCTAssertFalse(app.staticTexts["A measured or estimated body-fat value"].exists)
        XCTAssertFalse(app.staticTexts["Your height for a frame-adjusted comparison"].exists)
        attachScreenshot(named: "launch-quality-onboarding-fixed-cta", from: app)
    }

    private func assertAndCaptureOnboardingFirstPhotoCTA(in app: XCUIApplication) throws {
        XCTAssertTrue(app.staticTexts["Start a visual timeline?"].waitForExistence(timeout: 10))

        let addPhotoButton = app.buttons["Add first photo"]
        let skipButton = app.buttons["Skip for now"]
        XCTAssertTrue(addPhotoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        XCTAssertTrue(addPhotoButton.isHittable)
        XCTAssertTrue(skipButton.isHittable)
        XCTAssertFalse(app.buttons["Continue"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["onboarding_first_photo_card"].exists)
        XCTAssertFalse(app.staticTexts["A private baseline, on your terms."].exists)
        XCTAssertFalse(app.staticTexts["Camera and photo library access are optional."].exists)

        attachScreenshot(named: "launch-quality-onboarding-first-photo", from: app)
    }

    private func assertAndCaptureTimelineHomeSurface(in app: XCUIApplication) throws {
        let timeline = app.descendants(matching: .any)["launch_timeline_surface"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))

        let window = app.windows.firstMatch
        let windowFrame = window.frame
        XCTAssertGreaterThan(timeline.frame.width, windowFrame.width * 0.82)
        XCTAssertGreaterThanOrEqual(timeline.frame.minX, windowFrame.minX - 1)
        XCTAssertLessThanOrEqual(timeline.frame.maxX, windowFrame.maxX + 1)

        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_hud_stats_button"].exists)
        attachScreenshot(named: "launch-quality-home-timeline", from: app)
    }

    private func assertAndCaptureBodyScoreShareSheet(in app: XCUIApplication) throws {
        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 20))

        let timeline = app.descendants(matching: .any)["launch_timeline_surface"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 20))

        let shareButton = app.descendants(matching: .any)["body_score_hero_share_button"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
        scrollUntilHittable(shareButton, in: app)
        XCTAssertTrue(shareButton.isHittable)
        shareButton.tap()

        let shareSheet = app.descendants(matching: .any)["body_score_share_sheet"]
        let shareCard = app.descendants(matching: .any)["body_score_share_card"]
        // Sheet identifier is preferred; card must remain discoverable for launch quality.
        let sheetVisible = shareSheet.waitForExistence(timeout: 8)
        let cardVisible = shareCard.waitForExistence(timeout: sheetVisible ? 4 : 8)
        XCTAssertTrue(sheetVisible || cardVisible, "Share overlay must appear after tapping share")
        XCTAssertTrue(cardVisible, "Share card must remain accessibility-discoverable inside the overlay")
        XCTAssertTrue(app.descendants(matching: .any)["body_score_share_content_controls"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["body_score_share_avatar_visual"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["body_score_share_save_button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["body_score_share_system_button"].exists)

        let closeButton = app.descendants(matching: .any)["body_score_share_close_button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        XCTAssertTrue(closeButton.isHittable, "Close must stay tappable outside the safe-area notch")

        let cardFrame = shareCard.frame
        let windowFrame = app.windows.firstMatch.frame
        // The portrait preview is fitted into the remaining vertical space
        // below the controls, so its width is intentionally below the full
        // sheet width on compact iPhones.
        XCTAssertGreaterThan(cardFrame.width, windowFrame.width * 0.80)
        XCTAssertGreaterThan(cardFrame.height, cardFrame.width * 1.18)
        XCTAssertGreaterThan(cardFrame.minY, windowFrame.minY + 72)
        XCTAssertLessThanOrEqual(cardFrame.maxY, windowFrame.maxY - 72)
        attachScreenshot(named: "launch-quality-body-score-share", from: app)

        // Escape path: Close must actually dismiss the full-screen overlay.
        closeButton.tap()
        XCTAssertFalse(
            shareSheet.waitForExistence(timeout: 3),
            "Share sheet must dismiss when Close is tapped"
        )
        XCTAssertTrue(
            shareButton.waitForExistence(timeout: 5),
            "Home share control must return after dismissing share sheet"
        )
    }

    private func assertAndCaptureTimelineAnalytics(in app: XCUIApplication) throws {
        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_hud_stats_button"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["photo_timeline_root_page_analytics"].exists)

        let statsButton = app.buttons["Stats"]
        XCTAssertTrue(statsButton.waitForExistence(timeout: 5))
        XCTAssertLessThan(statsButton.frame.midY, app.windows.firstMatch.frame.height * 0.18)
        statsButton.tap()

        let analyticsPage = app.descendants(matching: .any)["photo_timeline_root_page_analytics"]
        if !analyticsPage.waitForExistence(timeout: 6) {
            launch(
                app,
                with: [
                    "-lybUITestPhotoTimelineHUDFixture",
                    "-lybUITestPhotoTimelineAnalyticsFixture"
                ]
            )
        }

        XCTAssertTrue(app.descendants(matching: .any)["photo_timeline_root_page_analytics"].waitForExistence(timeout: 10))
        let presenceSummary = app.descendants(matching: .any)["photo_timeline_stats_presence_summary"]
        XCTAssertTrue(presenceSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(presenceSummary.label.contains("Measured"))
        XCTAssertTrue(presenceSummary.label.contains("Interpolated"))
        XCTAssertTrue(app.descendants(matching: .any)["photo_timeline_stats_metric_stack"].exists)
        let weightCard = app.descendants(matching: .any)["photo_timeline_stats_metric_card_weight"]
        XCTAssertTrue(weightCard.waitForExistence(timeout: 10))
        let bodyFatCard = app.descendants(matching: .any)["photo_timeline_stats_metric_card_body_fat"]
        XCTAssertTrue(bodyFatCard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Timeline states"].exists)
        attachScreenshot(named: "launch-quality-analytics", from: app)
        let ffmiCard = app.descendants(matching: .any)["photo_timeline_stats_metric_card_ffmi"]
        scrollUntilExists(ffmiCard, in: app)
        XCTAssertTrue(ffmiCard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["legacy_full_dashboard_beta"].exists)
    }

    private func openIntegrations(in app: XCUIApplication) throws {
        try openSettings(in: app)

        let integrationsButton = app.descendants(matching: .any)["settings_integrations_link"]
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
