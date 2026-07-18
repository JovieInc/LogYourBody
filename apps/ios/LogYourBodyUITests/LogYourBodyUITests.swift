//
// LogYourBodyUITests.swift
// LogYourBody
//
import XCTest

final class LogYourBodyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testLoginNavigatesToSignUp() throws {
        let app = launch(scenario: "login")

        XCTAssertTrue(app.staticTexts["LogYourBody"].waitForExistence(timeout: 5))

        app.buttons["Sign up"].tap()

        XCTAssertTrue(app.staticTexts["Create Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Terms of Service"].exists)
    }

    func testSignUpTermsDisplaysDocument() throws {
        let app = launch(scenario: "signup")

        XCTAssertTrue(app.staticTexts["Create Account"].waitForExistence(timeout: 5))

        app.buttons["Terms of Service"].tap()

        XCTAssertTrue(app.navigationBars["Terms of Service"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Terms of Service"].exists)
    }

    func testOnboardingProgressesFromHookToHeight() throws {
        let app = launch(scenario: "onboarding")

        XCTAssertTrue(app.staticTexts["Get your Body Score in 60 seconds."].waitForExistence(timeout: 5))

        app.buttons["Start my 60-sec Body Score"].tap()

        XCTAssertTrue(app.staticTexts["Sex at birth"].waitForExistence(timeout: 5))

        app.buttons["Female"].tap()

        XCTAssertTrue(app.staticTexts["How tall are you?"].waitForExistence(timeout: 5))

        let heightField = app.textFields["Height in centimeters"]
        XCTAssertTrue(heightField.waitForExistence(timeout: 5))
        heightField.tap()
        heightField.typeText("170")

        XCTAssertTrue(app.buttons["Continue"].isEnabled)

        let dismissKeyboard = app.buttons["Dismiss keyboard"]
        XCTAssertTrue(dismissKeyboard.exists)
        dismissKeyboard.tap()
        XCTAssertFalse(dismissKeyboard.waitForExistence(timeout: 1))
    }

    func testOnboardingImperialHeightProgressesWithoutKeyboard() throws {
        let app = launch(scenario: "onboarding")

        app.buttons["Start my 60-sec Body Score"].tap()
        XCTAssertTrue(app.staticTexts["Sex at birth"].waitForExistence(timeout: 5))
        app.buttons["Female"].tap()

        XCTAssertTrue(app.staticTexts["How tall are you?"].waitForExistence(timeout: 5))
        app.buttons["FT/IN"].tap()
        XCTAssertTrue(app.pickers["Feet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.pickers["Inches"].exists)

        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Pull from Apple Health?"].waitForExistence(timeout: 5))
        app.buttons["Enter manually instead"].tap()
        XCTAssertTrue(app.staticTexts["What’s your most recent weight?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["onboarding-manual-weight"].exists)
    }

    func testOnboardingManualBodyScoreJourneyReachesScore() throws {
        let app = launch(scenario: "onboarding")

        app.buttons["Start my 60-sec Body Score"].tap()
        XCTAssertTrue(app.staticTexts["Sex at birth"].waitForExistence(timeout: 5))

        app.buttons["Female"].tap()
        XCTAssertTrue(app.staticTexts["How tall are you?"].waitForExistence(timeout: 5))

        app.buttons["FT/IN"].tap()
        XCTAssertTrue(app.pickers["Feet"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Pull from Apple Health?"].waitForExistence(timeout: 5))
        app.buttons["Enter manually instead"].tap()

        XCTAssertTrue(app.staticTexts["What’s your most recent weight?"].waitForExistence(timeout: 5))
        let weightField = app.textFields["onboarding-manual-weight"]
        weightField.tap()
        weightField.typeText("150")
        let dismissKeyboard = app.buttons["Dismiss keyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
        dismissKeyboard.tap()
        XCTAssertFalse(dismissKeyboard.waitForExistence(timeout: 1))
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["How do you want to estimate body fat?"].waitForExistence(timeout: 5))
        app.buttons["body-fat-source-manual"].tap()

        XCTAssertTrue(app.staticTexts["Enter your body fat %"].waitForExistence(timeout: 5))
        let bodyFatField = app.textFields["onboarding-body-fat"]
        bodyFatField.tap()
        bodyFatField.typeText("18")
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
        dismissKeyboard.tap()
        XCTAssertFalse(dismissKeyboard.waitForExistence(timeout: 1))
        app.buttons["Continue"].tap()

        let scoreTitle = app.staticTexts["Your Body Score"]
        XCTAssertTrue(scoreTitle.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Starting point"].exists)
        XCTAssertTrue(app.buttons["See my next steps"].exists)
    }

    func testOnboardingVisualBodyFatJourneyCalculatesScore() throws {
        let app = launch(scenario: "onboarding")

        app.buttons["Start my 60-sec Body Score"].tap()
        XCTAssertTrue(app.staticTexts["Sex at birth"].waitForExistence(timeout: 5))

        app.buttons["Female"].tap()
        XCTAssertTrue(app.staticTexts["How tall are you?"].waitForExistence(timeout: 5))

        app.buttons["FT/IN"].tap()
        XCTAssertTrue(app.pickers["Feet"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Pull from Apple Health?"].waitForExistence(timeout: 5))
        app.buttons["Enter manually instead"].tap()

        let weightField = app.textFields["onboarding-manual-weight"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        weightField.typeText("150")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["How do you want to estimate body fat?"].waitForExistence(timeout: 5))
        app.buttons["body-fat-source-visual"].tap()

        XCTAssertTrue(app.staticTexts["Pick the closest match"].waitForExistence(timeout: 5))
        app.staticTexts["20% Balanced"].tap()

        let scoreTitle = app.staticTexts["Your Body Score"]
        XCTAssertTrue(scoreTitle.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Starting point"].exists)
    }

    func testOnboardingEmailCaptureValidatesAndAdvancesToAccountSetup() throws {
        let app = launch(scenario: "onboarding-email")

        XCTAssertTrue(app.staticTexts["Save your score?"].waitForExistence(timeout: 5))

        let emailField = app.textFields["you@domain.com"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)

        emailField.tap()
        emailField.typeText("not-an-email")
        XCTAssertTrue(app.staticTexts["Enter a valid email address."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)

        emailField.tap()
        emailField.typeText("@example.com")
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 5))
        let passwordField = app.secureTextFields["••••••••"]
        XCTAssertTrue(passwordField.exists)
        XCTAssertFalse(app.buttons["Create account"].isEnabled)

        passwordField.tap()
        passwordField.typeText("StrongPass1")
        XCTAssertTrue(app.buttons["Create account"].isEnabled)
    }

    func testOnboardingProfileDetailsCollectsNameBeforeBirthday() throws {
        let app = launch(scenario: "onboarding-profile")

        XCTAssertTrue(app.staticTexts["What's your first name?"].waitForExistence(timeout: 5))

        let firstName = app.textFields["First name"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        firstName.tap()
        firstName.typeText("Alex")
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["And your last name?"].waitForExistence(timeout: 5))
        let lastName = app.textFields["Last name"]
        XCTAssertTrue(lastName.waitForExistence(timeout: 5))
        lastName.tap()
        lastName.typeText("Runner")
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Birthday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers.firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
    }

    func testOnboardingBodyScoreShareChangesFormatAndPresentsShareSheet() throws {
        let app = launch(scenario: "onboarding-reveal")

        XCTAssertTrue(app.staticTexts["Your Body Score"].waitForExistence(timeout: 5))
        app.buttons["Share my score"].tap()

        XCTAssertTrue(app.navigationBars["Share Body Score"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["4:5"].waitForExistence(timeout: 5))
        app.buttons["4:5"].tap()
        XCTAssertTrue(app.buttons["9:16"].exists)
        app.buttons["9:16"].tap()

        app.buttons["Share"].tap()
        XCTAssertTrue(app.cells["Save to Files"].waitForExistence(timeout: 8), app.debugDescription)
    }

    func testOnboardingHealthConfirmationReviewsImportedDataAndCalculatesScore() throws {
        let app = launch(scenario: "onboarding-health")

        XCTAssertTrue(app.staticTexts["Health data synced"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HEIGHT"].exists)
        XCTAssertTrue(app.staticTexts["180 cm (5' 11\")"].exists)
        XCTAssertTrue(app.staticTexts["WEIGHT"].exists)
        XCTAssertTrue(app.staticTexts["80 kg"].exists)
        XCTAssertTrue(app.staticTexts["BODY FAT"].exists)
        XCTAssertTrue(app.staticTexts["18.5%"].exists)
        XCTAssertTrue(app.staticTexts["We read only what you allow."].exists)

        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Your Body Score"].waitForExistence(timeout: 8), app.debugDescription)
    }

    func testOnboardingHealthConfirmationLetsUserEnterMetricsManually() throws {
        let app = launch(scenario: "onboarding-health")

        XCTAssertTrue(app.staticTexts["Health data synced"].waitForExistence(timeout: 5))
        app.buttons["Enter manually instead"].tap()

        XCTAssertTrue(app.staticTexts["What’s your most recent weight?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["onboarding-manual-weight"].exists)
    }

    func testLegalConsentRequiresBothAgreementsAndCompletesAcceptance() throws {
        let app = launch(scenario: "legal-consent")

        XCTAssertTrue(app.staticTexts["Welcome to LogYourBody"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)

        let continueButton = app.buttons["Continue"]
        let termsConsent = app.buttons["legal-consent-Terms of Service"]
        XCTAssertTrue(termsConsent.isHittable, app.debugDescription)
        termsConsent.tap()
        XCTAssertFalse(continueButton.isEnabled)

        let privacyConsent = app.buttons["legal-consent-Privacy Policy"]
        XCTAssertTrue(privacyConsent.isHittable, app.debugDescription)
        privacyConsent.tap()
        let continueEnabled = expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: continueButton
        )
        wait(for: [continueEnabled], timeout: 5)
        XCTAssertTrue(continueButton.isEnabled, app.debugDescription)

        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Legal consent accepted"].waitForExistence(timeout: 5))
    }

    func testWhatsNewShowsReleaseDetailsAndDismisses() throws {
        let app = launch(scenario: "whats-new")

        XCTAssertTrue(app.navigationBars["What's New"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Version 1.4.0"].exists)
        XCTAssertTrue(app.staticTexts["Frictionless Apple Sign In with post-auth consent"].exists)

        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Changelog dismissed"].waitForExistence(timeout: 5))
    }

    func testBodySpecExplainsUnavailableConfigurationWithoutStartingExternalAuth() throws {
        let app = launch(scenario: "body-spec")

        XCTAssertTrue(app.navigationBars["BodySpec"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BodySpec DEXA"].exists)
        XCTAssertTrue(app.staticTexts["BodySpec is not configured for this build."].exists)
        XCTAssertFalse(app.buttons["Connect BodySpec"].isEnabled)
        XCTAssertFalse(app.buttons["Sync DEXA Scans"].isEnabled)
        XCTAssertTrue(app.staticTexts["No DEXA scans found yet."].exists)
    }

    func testIntegrationsOpensPhotoImportAndCanReturnBeforeRequestingAccess() throws {
        let app = launch(scenario: "integrations")

        XCTAssertTrue(app.navigationBars["Integrations"].waitForExistence(timeout: 5))
        let photoImport = app.staticTexts["Import Progress Photos"]
        for _ in 0..<4 where !photoImport.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(photoImport.isHittable, app.debugDescription)
        photoImport.tap()

        XCTAssertTrue(app.navigationBars["Import Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bulk Photo Import"].exists)
        XCTAssertTrue(app.staticTexts["Preserves original photo dates"].exists)
        XCTAssertTrue(app.buttons["Start Scanning"].isEnabled)

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Integrations"].waitForExistence(timeout: 5))
    }

    func testBulkPhotoImportExplainsPermissionBeforeOpeningTheSystemPrompt() throws {
        let app = launch(scenario: "bulk-photo-import")

        XCTAssertTrue(app.navigationBars["Import Photos"].waitForExistence(timeout: 5))
        app.buttons["Start Scanning"].tap()

        XCTAssertTrue(app.staticTexts["Access Your Photos"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(
            app.staticTexts["Allow LogYourBody to scan your photo library for potential progress photos"].exists
        )
        XCTAssertTrue(app.buttons["Allow Access"].isEnabled)
    }

    func testBulkPhotoImportShowsLiveScanningProgress() throws {
        let app = launch(scenario: "bulk-photo-import-scanning")

        XCTAssertTrue(app.navigationBars["Import Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scanning Photos..."].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["65%"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    func testBulkPhotoImportExplainsAnEmptyScanResult() throws {
        let app = launch(scenario: "bulk-photo-import-empty")

        XCTAssertTrue(app.navigationBars["Import Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Progress Photos Found"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["We couldn't find any photos that look like progress photos in your library"].exists)
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    func testBulkPhotoImportExplainsDeniedPhotoAccess() throws {
        let app = launch(scenario: "bulk-photo-import-denied")

        XCTAssertTrue(app.navigationBars["Import Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Photo Access Required"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Please enable photo library access in Settings to import progress photos"].exists)
        XCTAssertTrue(app.buttons["Open Settings"].exists)
    }

    func testEmailVerificationResendsAndAcceptsACompleteCode() throws {
        let app = launch(scenario: "email-verification-success")

        XCTAssertTrue(app.staticTexts["Verify Your Email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["your email"].exists)
        XCTAssertFalse(app.buttons["Verify"].isEnabled)

        app.buttons["Resend"].tap()
        XCTAssertTrue(
            app.staticTexts["A new verification code has been sent to your email."].waitForExistence(timeout: 5)
        )

        let verificationCode = app.textFields["email-verification-code"]
        XCTAssertTrue(verificationCode.exists)
        verificationCode.tap()
        verificationCode.typeText("123456")

        XCTAssertTrue(app.staticTexts["Email verified successfully!"].waitForExistence(timeout: 5))
    }

    func testEmailVerificationShowsAnActionableErrorForAnInvalidCode() throws {
        let app = launch(scenario: "email-verification-failure")

        XCTAssertTrue(app.staticTexts["Verify Your Email"].waitForExistence(timeout: 5))
        let verificationCode = app.textFields["email-verification-code"]
        verificationCode.tap()
        verificationCode.typeText("000000")

        XCTAssertTrue(
            app.staticTexts["Invalid verification code. Please try again."].waitForExistence(timeout: 5)
        )
    }

    func testChangePasswordExplainsRequirementsAndOnlyEnablesAValidMatch() throws {
        let app = launch(scenario: "change-password")

        XCTAssertTrue(app.staticTexts["Change Password"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["At least 8 characters"].exists)
        XCTAssertTrue(app.staticTexts["Mix of uppercase and lowercase"].exists)
        XCTAssertTrue(app.staticTexts["At least one number or symbol"].exists)

        let updatePassword = app.buttons["Update Password"]
        XCTAssertFalse(updatePassword.isEnabled)

        let currentPassword = app.secureTextFields["Enter current password"]
        let newPassword = app.secureTextFields["Enter new password"]
        let confirmation = app.secureTextFields["Re-enter new password"]
        XCTAssertTrue(currentPassword.exists)
        XCTAssertTrue(newPassword.exists)
        XCTAssertTrue(confirmation.exists)

        currentPassword.tap()
        currentPassword.typeText("CurrentPass1")
        newPassword.tap()
        newPassword.typeText("NewPassword1")
        confirmation.tap()
        confirmation.typeText("NewPassword1")

        XCTAssertTrue(updatePassword.isEnabled, app.debugDescription)
    }

    func testSecuritySessionsShowsSafeEmptyStateWhenNoSessionIsAvailable() throws {
        let app = launch(scenario: "security-sessions")

        XCTAssertTrue(app.navigationBars["Active Sessions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Other Sessions"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Only this device is currently signed in"].exists)
    }

    func testSecuritySessionsShowsDeviceDetailsAndRevokesASecondaryDevice() throws {
        let app = launch(scenario: "security-sessions-fixture")

        XCTAssertTrue(app.navigationBars["Active Sessions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["iPhone 16"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MacBook Pro"].exists)

        app.buttons["session-details-ui-test-current-device"].tap()
        XCTAssertTrue(app.staticTexts["192.0.2.10"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["First Signed In"].exists)

        app.buttons["revoke-session-ui-test-secondary-device"].tap()
        let revokeMessage = app.staticTexts[
            "Are you sure you want to revoke this session? The device will be signed out immediately."
        ]
        XCTAssertTrue(revokeMessage.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Revoke"].tap()

        let secondaryDeviceRemoved = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.staticTexts["MacBook Pro"]
        )
        wait(for: [secondaryDeviceRemoved], timeout: 5)
        XCTAssertTrue(app.staticTexts["iPhone 16"].exists)
    }

    func testDeleteAccountRequiresConfirmationPhraseAndCanBeCancelledSafely() throws {
        let app = launch(scenario: "delete-account")

        XCTAssertTrue(app.navigationBars["Delete Account"].waitForExistence(timeout: 5))
        let deleteButton = app.buttons["Delete My Account"]
        XCTAssertFalse(deleteButton.isEnabled)

        let confirmation = app.textFields["Type DELETE"]
        XCTAssertTrue(confirmation.exists)
        confirmation.tap()
        confirmation.typeText("DELETE")
        XCTAssertTrue(deleteButton.isEnabled, app.debugDescription)
        let done = app.keyboards.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
        done.tap()

        let keyboardDismissed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.keyboards.element
        )
        wait(for: [keyboardDismissed], timeout: 5)

        let deleteButtonHittable = expectation(
            for: NSPredicate(format: "isHittable == true"),
            evaluatedWith: deleteButton
        )
        wait(for: [deleteButtonHittable], timeout: 5)
        XCTAssertTrue(deleteButton.isHittable, app.debugDescription)

        deleteButton.tap()
        let confirmationMessage = app.staticTexts[
            "Are you sure you want to delete your account? This cannot be undone."
        ]
        XCTAssertTrue(confirmationMessage.waitForExistence(timeout: 5), app.debugDescription)
        let dismissPopup = app.otherElements["dismiss popup"]
        XCTAssertTrue(dismissPopup.isHittable, app.debugDescription)
        dismissPopup.tap()
        XCTAssertTrue(app.navigationBars["Delete Account"].waitForExistence(timeout: 5))
    }

    func testProgressPhotoCarouselExplainsItsEmptyStateWithoutCrashing() throws {
        let app = launch(scenario: "progress-photos-empty")

        XCTAssertTrue(app.staticTexts["No data yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Log your first entry to start tracking"].exists)
    }

    func testOptimizedProgressPhotoExplainsMissingAndInvalidImages() throws {
        let emptyApp = launch(scenario: "optimized-photo-empty")
        XCTAssertTrue(emptyApp.staticTexts["No image available"].waitForExistence(timeout: 5))

        emptyApp.terminate()
        let invalidApp = launch(scenario: "optimized-photo-invalid")
        XCTAssertTrue(invalidApp.staticTexts["Failed to load image"].waitForExistence(timeout: 5))
    }

    func testBiometricRecoveryAllowsRetryOrSafeFallback() throws {
        let app = launch(scenario: "biometric-recovery")

        XCTAssertTrue(app.staticTexts["Need help unlocking?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Face ID didn’t complete"].exists)

        app.buttons["Retry Face ID"].tap()
        XCTAssertTrue(app.staticTexts["Biometric retry requested"].waitForExistence(timeout: 5))

        app.buttons["Use device passcode"].tap()
        XCTAssertTrue(app.staticTexts["Biometric fallback selected"].waitForExistence(timeout: 5))
    }

    func testBiometricLockUnlocksAfterSuccessfulAuthentication() throws {
        let app = launch(scenario: "biometric-lock-success")

        XCTAssertTrue(app.staticTexts["Biometric lock unlocked"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testBiometricLockKeepsDataLockedWhenBiometricAndPasscodeAuthenticationFail() throws {
        let app = launch(scenario: "biometric-lock-failure")

        XCTAssertTrue(app.staticTexts["Touch ID didn’t complete"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Make sure your finger covers the Touch ID sensor."].exists)

        app.buttons["Use device passcode"].tap()
        XCTAssertFalse(app.staticTexts["Biometric lock unlocked"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Touch ID didn’t complete"].exists, app.debugDescription)
    }

    func testBiometricLockUnlocksOnlyAfterDeviceOwnerAuthenticationSucceeds() throws {
        let app = launch(scenario: "biometric-lock-passcode-success")

        XCTAssertTrue(app.staticTexts["Touch ID didn’t complete"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Use device passcode"].tap()
        XCTAssertTrue(app.staticTexts["Biometric lock unlocked"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testProgressTimelineKeepsAnUnanchoredSelectionWithinTheScrubberRange() throws {
        let app = launch(scenario: "progress-timeline")
        let scrubber = app.otherElements["progress-timeline-scrubber"]

        XCTAssertTrue(scrubber.waitForExistence(timeout: 5), app.debugDescription)
        let rawValue = try XCTUnwrap(scrubber.value as? String)
        let position = try XCTUnwrap(Double(rawValue))
        XCTAssertGreaterThanOrEqual(position, 0)
        XCTAssertLessThanOrEqual(position, 1)
    }

    func testAddEntrySwitchesToBodyFatAndValidatesInput() throws {
        let app = launch(scenario: "add-entry")

        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 5))

        let entryTypes = app.segmentedControls["Entry type selector"]
        XCTAssertTrue(entryTypes.exists)
        entryTypes.buttons["Body Fat"].tap()

        XCTAssertTrue(app.staticTexts["Enter body fat percentage"].waitForExistence(timeout: 5))

        let bodyFatField = app.textFields["Body fat percentage value"]
        bodyFatField.tap()
        bodyFatField.typeText("2")

        XCTAssertTrue(
            app.staticTexts["Body fat validation error: Body fat must be between 3-50%"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["Save Body Fat"].isEnabled)
    }

    func testAddEntrySavesValidWeightAndDismissesSheet() throws {
        let app = launch(scenario: "add-entry")

        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 5))

        let weightField = app.textFields["Weight value"]
        weightField.tap()
        weightField.typeText("72")

        let saveButton = app.buttons["Save Weight"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["Entry dismissed"].waitForExistence(timeout: 8))
    }

    func testAddEntrySavesValidBodyFatAndDismissesSheet() throws {
        let app = launch(scenario: "add-entry")

        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 5))
        let entryTypes = app.segmentedControls["Entry type selector"]
        entryTypes.buttons["Body Fat"].tap()

        let bodyFatField = app.textFields["Body fat percentage value"]
        XCTAssertTrue(bodyFatField.waitForExistence(timeout: 5))
        bodyFatField.tap()
        bodyFatField.typeText("18")

        let saveButton = app.buttons["Save Body Fat"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["Entry dismissed"].waitForExistence(timeout: 8))
    }

    func testAddEntryPhotoTabExplainsSelectionAndPreventsEmptyUpload() throws {
        let app = launch(scenario: "add-entry")

        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 5))
        let entryTypes = app.segmentedControls["Entry type selector"]
        entryTypes.buttons["Photos"].tap()

        XCTAssertTrue(app.staticTexts["Select progress photos"].waitForExistence(timeout: 5))
        let photoSelectionHint = "Photos will be automatically dated based on when they were taken. " +
            "You can select multiple photos for bulk upload."
        XCTAssertTrue(app.staticTexts[photoSelectionHint].exists)
        XCTAssertTrue(app.buttons["Choose Photos"].exists)
        XCTAssertFalse(app.buttons["Upload Photo"].isEnabled)
    }

    func testAddEntrySavesConfiguredGLP1Dose() throws {
        let app = launch(scenario: "add-entry")

        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 5))
        let entryTypes = app.segmentedControls["Entry type selector"]
        entryTypes.buttons["GLP-1"].tap()

        XCTAssertTrue(app.staticTexts["Log GLP-1 dose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Wegovy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save GLP-1"].isEnabled)

        app.buttons["Save GLP-1"].tap()

        XCTAssertTrue(app.staticTexts["Entry dismissed"].waitForExistence(timeout: 8))
    }

    func testAddEntryCreatesAndSelectsAnOralGLP1Medication() throws {
        let app = launch(
            scenario: "add-entry-no-medication",
            fixtureUserId: "ui-test-add-medication-\(UUID().uuidString)"
        )

        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 5))
        let entryTypes = app.segmentedControls["Entry type selector"]
        entryTypes.buttons["GLP-1"].tap()

        XCTAssertTrue(app.staticTexts["Add your GLP-1 medication"].waitForExistence(timeout: 5))
        app.buttons["Add medication"].tap()

        XCTAssertTrue(app.navigationBars["Select GLP-1"].waitForExistence(timeout: 5))
        let searchField = app.textFields["Search brand or generic"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Rybelsus")

        let rybelsusOption = app.buttons["Rybelsus, semaglutide, Oral • once daily"]
        XCTAssertTrue(rybelsusOption.waitForExistence(timeout: 5), app.debugDescription)
        rybelsusOption.tap()

        let saveMedication = app.buttons["Save medication"]
        XCTAssertTrue(saveMedication.isEnabled)
        saveMedication.tap()

        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["Rybelsus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save GLP-1"].isEnabled)

        app.buttons["Save GLP-1"].tap()
        XCTAssertTrue(app.staticTexts["Entry dismissed"].waitForExistence(timeout: 8), app.debugDescription)
    }

    func testLegalNavigationDisplaysPrivacyPolicy() throws {
        let app = launch(scenario: "legal")

        XCTAssertTrue(app.navigationBars["Legal"].waitForExistence(timeout: 5))

        app.buttons["Privacy Policy"].tap()

        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Privacy Policy"].exists)
    }

    func testProfileEditorOpensHeightPicker() throws {
        let app = launch(scenario: "profile-editor")

        XCTAssertTrue(app.staticTexts["Physical Information"].waitForExistence(timeout: 5))

        let profileEditorHeight = app.buttons["profile-editor-height"]
        XCTAssertTrue(profileEditorHeight.exists)

        profileEditorHeight.tap()

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    func testSettingsRendersProfileControls() throws {
        let app = launch(scenario: "settings")

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile-full-name"].exists)
        XCTAssertTrue(app.buttons["profile-date-of-birth"].exists)
        XCTAssertTrue(app.buttons["profile-height"].exists)
    }

    func testFullMetricChartSupportsRangeModeAndAddEntry() throws {
        let app = launch(scenario: "full-chart")

        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today"].exists)
        XCTAssertTrue(app.buttons["1W"].exists)
        XCTAssertTrue(app.buttons["Raw"].exists)

        app.buttons["1W"].tap()
        app.buttons["Raw"].tap()
        app.buttons["Add Entry"].tap()

        XCTAssertTrue(app.staticTexts["Chart add requested"].waitForExistence(timeout: 5))
    }

    func testFullMetricChartEmptyStateExplainsMissingData() throws {
        let app = launch(scenario: "full-chart-empty")

        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No data available for this range."].waitForExistence(timeout: 5))
    }

    func testQuickLogPrefillsAndSavesManualMetrics() throws {
        let app = launch(scenario: "log-metrics")

        XCTAssertTrue(app.staticTexts["Log Metrics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Quick"].exists)

        app.buttons["Quick"].tap()

        XCTAssertTrue(app.staticTexts["72.0 kg"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["18.0%"].exists)
        XCTAssertTrue(app.buttons["Save Measurement"].isEnabled)

        app.buttons["Save Measurement"].tap()

        XCTAssertTrue(app.staticTexts["Saved successfully!"].waitForExistence(timeout: 5))
    }

    func testDirectExportShowsFormatsPhotosAndShareSheet() throws {
        let app = launch(scenario: "export")

        XCTAssertTrue(app.navigationBars["Export Data"].waitForExistence(timeout: 5))

        app.buttons["export-method-download"].tap()

        XCTAssertTrue(app.staticTexts["Export Format"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-format-csv"].exists)
        app.buttons["export-include-photos"].tap()
        XCTAssertTrue(app.staticTexts["Progress Photos"].waitForExistence(timeout: 5))

        app.buttons["export-data"].tap()

        XCTAssertTrue(app.cells["Save to Files"].waitForExistence(timeout: 8), app.debugDescription)
    }

    func testPaywallExplainsBenefitsAndOpensTerms() throws {
        let app = launch(scenario: "paywall")

        XCTAssertTrue(app.staticTexts["LogYourBody Pro"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Progress Photos"].exists)
        XCTAssertTrue(app.staticTexts["HealthKit Sync"].exists)

        let terms = app.buttons["Terms of Service"]
        for _ in 0..<5 where !terms.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(terms.isHittable, app.debugDescription)
        terms.tap()

        XCTAssertTrue(app.navigationBars["Terms of Service"].waitForExistence(timeout: 5))
    }

    func testDashboardShowsMetricsAndOpensNewEntry() throws {
        let app = launch(scenario: "dashboard")

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["UI"].exists)

        tapPrimaryTab("Metrics", in: app)
        XCTAssertTrue(app.staticTexts["Your Metrics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weight"].exists)

        tapPrimaryTab("Home", in: app)
        let newEntry = app.buttons["New Entry"]
        XCTAssertTrue(newEntry.waitForExistence(timeout: 5))
        newEntry.tap()

        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 5))
    }

    func testDashboardKeepsPrimaryNavigationAndAddEntryReachableInIPadLandscape() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "Landscape is supported only on iPad."
        )
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launch(scenario: "dashboard-preloaded")
        let window = app.windows.firstMatch

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThan(window.frame.width, window.frame.height, app.debugDescription)
        XCTAssertTrue(app.buttons["New Entry"].isHittable, app.debugDescription)

        tapPrimaryTab("Metrics", in: app)
        XCTAssertTrue(app.staticTexts["Your Metrics"].waitForExistence(timeout: 5), app.debugDescription)

        tapPrimaryTab("Photos", in: app)
        XCTAssertTrue(app.staticTexts["No progress photo"].waitForExistence(timeout: 5), app.debugDescription)

        tapPrimaryTab("Home", in: app)
        app.buttons["New Entry"].tap()
        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testDashboardLoadsFixtureData() throws {
        let app = launch(scenario: "dashboard")

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["UI"].exists)
        XCTAssertTrue(app.buttons["New Entry"].exists)
    }

    func testDashboardEmptyStateGuidesUsersToCreateTheirFirstEntry() throws {
        let app = launch(scenario: "dashboard-empty")

        XCTAssertTrue(app.staticTexts["Start tracking your progress"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Add your first entry to unlock trends, charts, and insights."].exists)

        app.buttons["Get Started"].tap()

        XCTAssertTrue(app.navigationBars["Add Entry"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testDashboardRendersPreloadedDataWithoutRefresh() throws {
        let app = launch(scenario: "dashboard-preloaded")

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Body Score"].exists)
        XCTAssertTrue(app.staticTexts["Steps"].exists)

        tapPrimaryTab("Metrics", in: app)
        let weight = app.staticTexts["Weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<2 where !weight.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(weight.isHittable, app.debugDescription)
        weight.tap()

        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testDashboardOpensTheBodyFatMetricDetail() throws {
        let app = launch(scenario: "dashboard-preloaded")

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 10), app.debugDescription)
        tapPrimaryTab("Metrics", in: app)

        let bodyFat = app.staticTexts["Body Fat %"]
        for _ in 0..<3 where !bodyFat.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(bodyFat.isHittable, app.debugDescription)
        bodyFat.tap()

        XCTAssertTrue(app.navigationBars["Body Fat %"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["18.0"].exists)
    }

    func testDashboardOpensTheFFMIMetricDetail() throws {
        let app = launch(scenario: "dashboard-preloaded")

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 10), app.debugDescription)
        tapPrimaryTab("Metrics", in: app)

        let ffmi = app.staticTexts["FFMI"]
        for _ in 0..<4 where !ffmi.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(ffmi.isHittable, app.debugDescription)
        ffmi.tap()

        XCTAssertTrue(app.navigationBars["FFMI"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testDashboardExplainsAndSurfacesARecoverableSyncFailure() throws {
        let app = launch(scenario: "dashboard-sync-error")

        XCTAssertTrue(app.staticTexts["Sync failed. Tap to retry."].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Unable to reach the sync service."].exists)
    }

    func testDashboardSyncDetailsExplainsOfflineQueuedDataAndCanClose() throws {
        let app = launch(scenario: "dashboard-sync-details")

        XCTAssertTrue(app.navigationBars["Sync Details"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Offline"].exists)
        XCTAssertTrue(app.staticTexts["4"].exists)
        XCTAssertTrue(app.staticTexts["2"].exists)
        XCTAssertTrue(app.staticTexts["No network available. Changes will sync when you reconnect."].exists)
        XCTAssertFalse(app.buttons["Retry"].isEnabled)

        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Sync details dismissed"].waitForExistence(timeout: 5))
    }

    func testDashboardBackgroundTaskShowsDetailsAndCancelsAllWork() throws {
        let app = launch(scenario: "dashboard-background-task")

        XCTAssertTrue(app.navigationBars["Background Tasks"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Scanning photo library"].exists)
        XCTAssertTrue(app.staticTexts["Looking for progress photos"].exists)
        XCTAssertTrue(app.staticTexts["60%"].exists)

        app.buttons["Cancel All"].tap()
        XCTAssertTrue(app.staticTexts["Cancel All Tasks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Are you sure you want to cancel all background tasks? This cannot be undone."].exists)
        app.buttons["Cancel All Tasks"].tap()

        XCTAssertTrue(app.staticTexts["All Tasks Complete"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testDashboardBackgroundProcessingDoesNotOfferUnsafeCancellation() throws {
        let app = launch(scenario: "dashboard-background-processing")

        XCTAssertTrue(app.navigationBars["Background Tasks"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Processing 2 photos"].exists)
        XCTAssertTrue(app.staticTexts["Optimizing images"].exists)
        XCTAssertFalse(app.buttons["Cancel All"].exists)
    }

    func testDashboardPhotosExplainsEntriesWithoutProgressPhotos() throws {
        let app = launch(scenario: "dashboard-preloaded")

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 10), app.debugDescription)
        tapPrimaryTab("Photos", in: app)

        XCTAssertTrue(app.staticTexts["No progress photo"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func launch(scenario: String, fixtureUserId: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestScenario", scenario,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        if let fixtureUserId {
            app.launchEnvironment["UI_TEST_FIXTURE_USER_ID"] = fixtureUserId
        }
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        return app
    }

    private func tapPrimaryTab(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tabBarItem = app.tabBars.buttons[title]
        if tabBarItem.waitForExistence(timeout: 1) {
            tabBarItem.tap()
            return
        }

        // iPadOS 26 renders the primary navigation as a floating tab control rather than XCUIElementTypeTabBar.
        let floatingTabItem = app.buttons[title].firstMatch
        XCTAssertTrue(floatingTabItem.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        floatingTabItem.tap()
    }
}
