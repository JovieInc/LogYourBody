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

    func testSignedOutAppleSignInHiddenByDefault() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestSignedOutFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["LogYourBody"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["login_email_field"].exists)
        XCTAssertTrue(app.buttons["login_email_code_button"].exists)
        XCTAssertFalse(app.buttons["Continue with Apple"].exists)
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
        app.launchArguments = ["-lybUITestPaidMVPFixture"]
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

        let restoreButton = app.buttons["paywall_restore_purchases_button"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 3))
        XCTAssertTrue(restoreButton.isHittable)

        let logoutButton = app.buttons["paywall_logout_button"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 3))
        XCTAssertTrue(logoutButton.isHittable)
    }

    func testSubscribedMVPSettingsExposeSubscriptionEscapePaths() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestPaidMVPFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Weight log"].waitForExistence(timeout: 10))

        let settingsButton = app.buttons["mvp_settings_button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))

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
}
