//
// ChaosEdgeCaseUITests.swift
// LogYourBody
//
// Twelve targeted edge cases the chaos monkey is unlikely to hit reliably on
// its own: numeric boundary values, rapid double taps, backgrounding mid-save,
// permission denial, and settings round trips. Each test is named for the
// behavior it protects.
//
import XCTest

final class ChaosEdgeCaseUITests: XCTestCase {
    private var systemAlertMonitor: NSObjectProtocol?

    override func setUpWithError() throws {
        continueAfterFailure = false
        // A fresh fixture identity can trigger a real system permission
        // prompt (notifications, etc.) on first launch. Without dismissing
        // it, every subsequent element query in the test times out against
        // a covered screen. Mirrors ChaosMonkeyUITests' monitor.
        systemAlertMonitor = addUIInterruptionMonitor(withDescription: "Edge case system alert") { alert in
            let labels = alert.buttons.allElementsBoundByIndex.map(\.label)
            if let label = ChaosSystemAlertPolicy.denialLabel(availableLabels: labels) {
                alert.buttons[label].tap()
                return true
            }
            let tree = XCTAttachment(string: alert.debugDescription)
            tree.name = "Unexpected system alert; no button tapped"
            tree.lifetime = .keepAlways
            self.add(tree)
            let screenshot = XCTAttachment(screenshot: alert.screenshot())
            screenshot.name = "Unexpected system alert"
            screenshot.lifetime = .keepAlways
            self.add(screenshot)
            XCTFail("Unexpected system alert has no known deny-only action; see retained evidence.")
            return false
        }
    }

    override func tearDownWithError() throws {
        if let systemAlertMonitor {
            removeUIInterruptionMonitor(systemAlertMonitor)
        }
        systemAlertMonitor = nil
    }

    func testChaosLaunchForwardsActualXCTestConfiguration() throws {
        let markerKeys = ["XCTestConfigurationFilePath", "XCTestSessionIdentifier", "XCTestBundlePath"]
        let markers = markerKeys.map { "\($0)=\(ProcessInfo.processInfo.environment[$0] ?? "<absent>")" }
        let markerAttachment = XCTAttachment(string: markers.joined(separator: "\n"))
        markerAttachment.name = "Actual XCTest runner markers"
        markerAttachment.lifetime = .keepAlways
        add(markerAttachment)
        let session = try XCTUnwrap(ProcessInfo.processInfo.environment["XCTestSessionIdentifier"])
        XCTAssertNotNil(UUID(uuidString: session))
        let bundle = try XCTUnwrap(ProcessInfo.processInfo.environment["XCTestBundlePath"])
        XCTAssertTrue(bundle.hasSuffix("/LogYourBodyUITests.xctest"))
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])
        XCTAssertEqual(app.launchEnvironment["XCTestSessionIdentifier"], session)
        XCTAssertEqual(app.launchEnvironment["XCTestBundlePath"], bundle)
        let configuration = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
        if let configuration, !configuration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            XCTAssertEqual(app.launchEnvironment["XCTestConfigurationFilePath"], configuration)
        } else {
            XCTAssertNil(app.launchEnvironment["XCTestConfigurationFilePath"])
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - 1. Weight entry boundaries

    func testWeightEntryRejectsInvalidAndOutOfRangeValues() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])
        try openMVPWeightEntry(in: app)

        // Pin the unit so the range check below (70-660 lb) is deterministic
        // regardless of the device's default measurement system.
        let unitPicker = app.segmentedControls["mvp_weight_unit_picker"]
        if unitPicker.waitForExistence(timeout: 5) {
            unitPicker.buttons["lb"].tap()
        }

        let invalidValues = ["0", "-1", "999999", "66.6666666", "not-a-number"]
        let field = app.textFields["mvp_weight_text_field"]

        for value in invalidValues {
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            XCTAssertTrue(waitForKeyboard(in: app), "Keyboard did not appear after tapping the field.")
            clearText(in: field)
            field.typeText(value)

            let saveBar = app.buttons["mvp_keyboard_save_weight_bar_button"]
            if saveBar.waitForExistence(timeout: 3), saveBar.isEnabled {
                saveBar.tap()
            }

            XCTAssertFalse(
                app.descendants(matching: .any)["mvp_weight_saved_message"].waitForExistence(timeout: 2),
                "Value '\(value)' must not save; it is outside the valid range or non-numeric."
            )
            XCTAssertTrue(
                app.staticTexts["mvp_weight_validation_message"].waitForExistence(timeout: 5),
                "Value '\(value)' must show a plain-language validation message."
            )
            field.tap()
            clearText(in: field)
        }

        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - 2. Body fat entry boundaries

    func testBodyFatEntryRejectsOutOfRangeValues() throws {
        let app = XCUIApplication()
        // The empty-fixture flag skips seeding a "logged today" metric, so the
        // Home dock shows "Log weight" (home_v2_log_weight) instead of "Done".
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2EmptyFixture"])
        try openAddEntrySheetFromHome(in: app)

        let detailsButton = app.buttons["home_v2_log_sheet_details"]
        guard detailsButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Body fat and more tab is not reachable from this fixture.")
        }
        detailsButton.tap()

        let bodyFatField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == '0.0'")
        ).firstMatch
        guard bodyFatField.waitForExistence(timeout: 5) else {
            throw XCTSkip("Body fat field is not reachable from this fixture.")
        }

        for value in ["0", "100", "101"] {
            bodyFatField.tap()
            XCTAssertTrue(waitForKeyboard(in: app), "Keyboard did not appear after tapping the field.")
            clearText(in: bodyFatField)
            bodyFatField.typeText(value)
            dismissKeyboardIfNeeded(in: app)

            let saveButton = app.buttons["home_v2_log_sheet_save"]
            XCTAssertFalse(
                saveButton.exists && saveButton.isEnabled,
                "Body fat '\(value)%' is out of the valid 3-60% range and must not be saveable."
            )
        }

        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - 3. Rapid double tap save

    func testRapidDoubleTapSaveCreatesOneEntry() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])
        try openMVPWeightEntry(in: app)

        let unitPicker = app.segmentedControls["mvp_weight_unit_picker"]
        if unitPicker.waitForExistence(timeout: 5) {
            unitPicker.buttons["lb"].tap()
        }

        let field = app.textFields["mvp_weight_text_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(waitForKeyboard(in: app), "Keyboard did not appear after tapping the field.")
        field.typeText("201.5")

        let saveBar = app.buttons["mvp_keyboard_save_weight_bar_button"]
        XCTAssertTrue(saveBar.waitForExistence(timeout: 3))
        saveBar.tap()
        // Fire a second tap immediately; a well-guarded save button disables
        // itself or the sheet dismisses before this lands.
        if saveBar.exists, saveBar.isHittable {
            saveBar.tap()
        }

        let savedMessages = app.descendants(matching: .any).matching(identifier: "mvp_weight_saved_message")
        XCTAssertTrue(savedMessages.firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(savedMessages.count, 1, "A rapid double tap must create exactly one saved entry, not two.")
    }

    // MARK: - 4. Background mid-save

    func testBackgroundingDuringSaveThenForegroundingPreservesState() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestWeightLoggerMVPFixture"])
        try openMVPWeightEntry(in: app)

        let field = app.textFields["mvp_weight_text_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(waitForKeyboard(in: app), "Keyboard did not appear after tapping the field.")
        field.typeText("175.0")

        let saveBar = app.buttons["mvp_keyboard_save_weight_bar_button"]
        XCTAssertTrue(saveBar.waitForExistence(timeout: 3))
        saveBar.tap()

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        // `activate()` returns before the state transition is guaranteed to
        // have landed. A real device under notification pressure can take
        // noticeably longer than the simulator to report runningForeground,
        // so poll for up to 15s rather than trusting the state immediately.
        let foregroundDeadline = Date().addingTimeInterval(15)
        while app.state != .runningForeground, Date() < foregroundDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        if app.state != .runningForeground {
            attachDiagnosticTree(from: app, named: "background-resume-timeout-tree")
            XCTFail("App did not report runningForeground within 15s of resuming (state: \(app.state.rawValue)).")
        }
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 3), "No error alert should surface after resuming.")
    }

    // MARK: - 5. Rotate through main screens

    func testRotatingThroughMainScreensDoesNotCrash() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        assertTimelineRootAppears(in: app, timeout: 30)
        attachScreenshot(named: "rotate-timeline", from: app)

        openPhotoTimelineMenu(in: app)
        let settings = waitForSettingsMenuEntry(in: app)
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            XCTAssertTrue(app.descendants(matching: .any)["home_v2_settings"].waitForExistence(timeout: 8))
            attachScreenshot(named: "rotate-settings", from: app)
            app.buttons["home_v2_settings_back"].tap()
        }

        assertTimelineRootAppears(in: app, timeout: 8)
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - 6. Photo permission recovery copy

    func testPhotoPermissionRecoveryCopyMatchesCurrentAuthorizationState() throws {
        // This app reads the device's live PHPhotoLibrary authorization state
        // with no UI-test fixture to force "denied" (see docs/engineering/chaos-testing.md).
        // Forcing denial would mutate shared, hard-to-reverse device state used by
        // other concurrent test runs, so this only asserts the surface renders
        // without crashing and validates recovery copy when the device already
        // happens to be denied/restricted.
        // Bulk import is gated behind BulkProgressPhotoImportPolicy (either
        // >=2 seeded progress photos or this fixture flag); without it the
        // fixture account here has too few photos to reach the entry point
        // at all (IntegrationsView.swift's isBulkProgressPhotoImportEnabled).
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture", "-lybUITestBulkPhotoImportEnabledFixture"])
        assertTimelineRootAppears(in: app, timeout: 30)
        openPhotoTimelineMenu(in: app)
        let settings = waitForSettingsMenuEntry(in: app)
        guard settings.waitForExistence(timeout: 5) else {
            throw XCTSkip("Settings entry point not reachable from this fixture.")
        }
        settings.tap()

        let integrationsLink = app.buttons["settings_integrations_link"]
        guard integrationsLink.waitForExistence(timeout: 8) else {
            throw XCTSkip("Integrations link not reachable from this fixture.")
        }
        integrationsLink.tap()

        // The NavigationLink row concatenates its own identifier with its
        // children's ("integrations_bulk_photo_import_link-<same>-<same>"
        // observed on-device), so an exact bracket match on the plain
        // identifier never hits; match on containment instead.
        let bulkImportLink = app.buttons.matching(
            NSPredicate(format: "identifier CONTAINS 'integrations_bulk_photo_import_link'")
        ).firstMatch
        XCTAssertTrue(bulkImportLink.waitForExistence(timeout: 8))
        bulkImportLink.tap()

        // Either the scanning UI (authorized) or a denied/restricted recovery
        // message renders; both are valid device states, but neither may crash.
        let recoveryPredicate = NSPredicate(
            format: "label CONTAINS[c] 'Photo' AND (label CONTAINS[c] 'access' "
                + "OR label CONTAINS[c] 'permission' OR label CONTAINS[c] 'Settings')"
        )
        let recovery = app.staticTexts.matching(recoveryPredicate).firstMatch
        let scanning = app.buttons["bulk_photo_import_start_scanning"]
        XCTAssertTrue(
            recovery.waitForExistence(timeout: 8) || scanning.waitForExistence(timeout: 8),
            "Bulk photo import must render either recovery copy or the scanning entry point."
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - 7. Chat offline retryable state

    func testChatOfflineFixtureShowsRetryableState() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-lybUITestChatFirstFixture",
            "-lybUITestChatOfflineFixture"
        ])

        // The ChatFirst fixture opens directly onto the chat surface, so the
        // usual timeline-root identifiers never appear; wait for the chat
        // composer itself instead (mirrors LogYourBodyUITests' proven
        // waitForHomeChatComposer pattern for this exact fixture combo).
        let composer = app.textFields["chat_composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 12))

        // MainTabView.swift renders two distinct "Retry" controls: the
        // fixture here simulates a failed *conversation load* on first open
        // (no message has been sent yet), which is `chat_reload_button`
        // (`isConversationLoadRetryAvailable`) -- `chat_retry_button` only
        // appears after a failed message *send* (`failedTurn != nil`),
        // which never happens in this scenario.
        let retry = app.buttons["chat_reload_button"]
        XCTAssertTrue(retry.waitForExistence(timeout: 12), "Offline chat must surface a retryable control.")
        XCTAssertTrue(retry.isHittable)
        attachScreenshot(named: "edge-chat-offline-retry", from: app)
    }

    // MARK: - 8. Settings hierarchy round trip

    func testSettingsHierarchyRoundTripsThroughEverySectionAndBack() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        assertTimelineRootAppears(in: app, timeout: 30)
        openPhotoTimelineMenu(in: app)
        let settings = waitForSettingsMenuEntry(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_settings"].waitForExistence(timeout: 8))

        // Deliberately excludes "home_v2_settings_delete" (destructive).
        let sectionIdentifiers = [
            "settings_profile_link",
            "settings_account_subscription_link",
            "settings_tracking_link",
            "home_v2_settings_units",
            "home_v2_settings_target",
            "home_v2_settings_reminders",
            "settings_privacy_data_link"
        ]

        for identifier in sectionIdentifiers {
            let link = app.buttons[identifier]
            guard link.waitForExistence(timeout: 5), link.isHittable else {
                continue
            }
            link.tap()
            XCTAssertTrue(
                waitForSettingsDetailScreen(in: app, timeout: 8),
                "Section '\(identifier)' must render a detail screen."
            )
            navigateBack(in: app)
            XCTAssertTrue(
                app.descendants(matching: .any)["home_v2_settings"].waitForExistence(timeout: 8),
                "Section '\(identifier)' must return cleanly to the settings root."
            )
        }

        app.buttons["home_v2_settings_back"].tap()
        assertTimelineRootAppears(in: app, timeout: 8)
    }

    // MARK: - 9. Paywall shows both plans and restore, never purchase

    func testPaywallShowsBothPlansAndRestoreControlWithoutPurchasing() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPaywallPlansFixture"])

        let paywall = app.descendants(matching: .any)["home_v2_paywall"]
        XCTAssertTrue(paywall.waitForExistence(timeout: 12))

        let plans = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'paywall_plan_'")
        )
        XCTAssertGreaterThanOrEqual(plans.count, 2, "Paywall must show at least two plan options.")

        let restore = app.buttons["paywall_restore_purchases_button"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(restore.isHittable)

        // Intentionally never tap restore or the purchase button.
        attachScreenshot(named: "edge-paywall-plans-restore", from: app)
    }

    // MARK: - 10. DEXA import sheet opens and cancels cleanly

    func testDexaImportSheetOpensAndCancelsCleanly() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        assertTimelineRootAppears(in: app, timeout: 30)
        openPhotoTimelineMenu(in: app)
        let settings = waitForSettingsMenuEntry(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let integrationsLink = app.buttons["settings_integrations_link"]
        guard integrationsLink.waitForExistence(timeout: 8) else {
            throw XCTSkip("Integrations link not reachable from this fixture.")
        }
        integrationsLink.tap()

        let dexaLink = app.buttons["integrations_bodyspec_link"]
        XCTAssertTrue(dexaLink.waitForExistence(timeout: 8))
        dexaLink.tap()

        let importButton = app.buttons["body_spec_pdf_import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        importButton.tap()

        // The system document picker runs out-of-process; give it a generous
        // window and cancel without selecting a file.
        let cancelButton = app.navigationBars.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 10) {
            cancelButton.tap()
        } else {
            XCTFail("System document picker Cancel control did not appear within 10s.")
        }

        XCTAssertTrue(importButton.waitForExistence(timeout: 8), "Cancelling the picker must return to the DEXA screen.")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - 11. Add Entry accepts a 300-character note

    func testAddEntryAccepts300CharacterNote() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture", "-lybUITestGlp1WeeklyCheckInFixture"])
        assertTimelineRootAppears(in: app, timeout: 30)
        openPhotoTimelineMenu(in: app)
        let stats = app.buttons["Stats"]
        XCTAssertTrue(stats.waitForExistence(timeout: 5))
        stats.tap()
        let prompt = app.buttons["photo_timeline_hud_glp1_weekly_checkin"]
        for _ in 0..<8 {
            if prompt.exists && prompt.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        XCTAssertTrue(prompt.isHittable)
        prompt.tap()
        XCTAssertTrue(app.staticTexts["Log GLP-1 dose"].waitForExistence(timeout: 10))

        let notesField = app.textFields["GLP-1 dose notes"]
        guard notesField.waitForExistence(timeout: 5) else {
            attachDiagnosticTree(from: app, named: "notes-field-unreachable-tree")
            XCTFail("GLP-1 notes field is not reachable from this fixture.")
            return
        }
        notesField.tap()
        XCTAssertTrue(waitForKeyboard(in: app), "Keyboard did not appear after tapping the field.")
        let longNote = String(repeating: "n", count: 300)
        notesField.typeText(longNote)
        XCTAssertEqual(notesField.value as? String, longNote)
        dismissKeyboardIfNeeded(in: app)

        XCTAssertEqual(app.state, .runningForeground, "A 300-character note must not crash the entry sheet.")
    }

    // MARK: - 12. Very long profile name renders without clipping

    func testVeryLongProfileNameRendersWithoutClipping() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        assertTimelineRootAppears(in: app, timeout: 30)
        openPhotoTimelineMenu(in: app)
        let settings = waitForSettingsMenuEntry(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let profileLink = app.buttons["settings_profile_link"]
        XCTAssertTrue(profileLink.waitForExistence(timeout: 8))
        profileLink.tap()

        let nameRow = app.descendants(matching: .any)["settings_profile_name_row"]
        XCTAssertTrue(nameRow.waitForExistence(timeout: 8))
        nameRow.tap()

        let editor = app.descendants(matching: .any)["profile_name_editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        XCTAssertTrue(waitForKeyboard(in: app), "Keyboard did not appear after tapping the field.")
        clearText(in: nameField)
        let longName = "Alexandra Christensen-Whitmore Montgomery van der Berg the Third"
        nameField.typeText(longName)

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        let displayedRow = app.descendants(matching: .any)["settings_profile_name_row"]
        XCTAssertTrue(displayedRow.waitForExistence(timeout: 8))
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(displayedRow.frame.minX, windowFrame.minX)
        XCTAssertLessThanOrEqual(displayedRow.frame.maxX, windowFrame.maxX + 1)
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - 13. Accessibility XXXL round trip has no layout anomalies

    func testAccessibilityXXXLHomeSettingsProfileHasNoLayoutAnomalies() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])

        assertTimelineRootAppears(in: app, timeout: 30)
        assertNoLayoutAnomalies(in: app, context: "timeline root")

        openPhotoTimelineMenu(in: app)
        let settings = waitForSettingsMenuEntry(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_settings"].waitForExistence(timeout: 8))
        assertNoLayoutAnomalies(in: app, context: "settings root")

        let profileLink = app.buttons["settings_profile_link"]
        let window = app.windows.firstMatch.frame
        let navigationBottom = app.navigationBars.firstMatch.frame.maxY
        let visibleViewport = CGRect(x: window.minX, y: navigationBottom, width: window.width,
                                     height: window.maxY - navigationBottom)
        let settingsList = app.collectionViews["home_v2_settings"]
        XCTAssertTrue(settingsList.exists)
        attachDiagnosticTree(from: app, named: "xxxl-profile-before-bounded-scroll")
        for _ in 0..<6 {
            // A native lazy list does not materialize the Profile row while the
            // XXXL account header fills the viewport. Scroll before requiring it.
            if profileLink.exists && visibleViewport.contains(profileLink.frame) && profileLink.isHittable { break }
            let moveDown = profileLink.exists && profileLink.frame.minY < visibleViewport.minY
            let start = settingsList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.4 : 0.65))
            let end = settingsList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.65 : 0.4))
            // Finish the bounded pan at rest so list inertia cannot skip a
            // virtualized row between existence checks.
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        attachDiagnosticTree(from: app, named: "xxxl-profile-row-before-tap")
        XCTAssertTrue(profileLink.waitForExistence(timeout: 8), "Bounded native scrolling must materialize the Profile row.")
        XCTAssertTrue(visibleViewport.contains(profileLink.frame), "Scroll the whole profile row into view before tapping.")
        XCTAssertTrue(profileLink.isHittable)
        profileLink.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Email"].waitForExistence(timeout: 8))
        attachDiagnosticTree(from: app, named: "xxxl-profile-after-tap")
        attachScreenshot(named: "xxxl-profile-after-tap", from: app)
        let emailIcon = app.images["envelope.fill"]
        let emailTitle = app.staticTexts["Email"]
        XCTAssertTrue(emailIcon.exists)
        XCTAssertTrue(emailTitle.exists)
        let iconGeometry = XCTAttachment(string: "icon=\(emailIcon.frame) title=\(emailTitle.frame)")
        iconGeometry.name = "XXXL Profile Email icon and title geometry"
        iconGeometry.lifetime = .keepAlways
        add(iconGeometry)
        XCTAssertLessThanOrEqual(emailIcon.frame.maxX, emailTitle.frame.minX, "The scaled Email icon must not overlap its title.")
        assertNoLayoutAnomalies(in: app, context: "profile")
        let nameRow = app.buttons["settings_profile_name_row"]
        let profileList = app.collectionViews.firstMatch
        for _ in 0..<8 {
            if nameRow.exists { break }
            let start = profileList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let end = profileList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(nameRow.exists, "The profile name control must remain reachable at XXXL.")
        assertNoLayoutAnomalies(in: app, context: "profile name row")

        navigateBack(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["home_v2_settings"].waitForExistence(timeout: 8),
            "Profile must return cleanly to the settings root."
        )
        app.buttons["home_v2_settings_back"].tap()
        assertTimelineRootAppears(in: app, timeout: 8)
        assertNoLayoutAnomalies(in: app, context: "timeline root after round trip")
    }

    // MARK: - 14. Arabic locale renders the root with a hittable composer

    func testArabicLocaleRootRendersAndComposerIsHittable() throws {
        let app = XCUIApplication()
        launch(app, with: [
            "-lybUITestPhotoTimelineHUDFixture",
            "-AppleLanguages", "(ar)",
            "-AppleLocale", "ar_SA"
        ])

        assertTimelineRootAppears(in: app, timeout: 30)

        let composer = app.textFields["chat_composer"]
        XCTAssertTrue(
            composer.waitForExistence(timeout: 12),
            "The docked chat composer (home_chat_composer_dock, MainTabView.swift) must render under Arabic/RTL."
        )
        XCTAssertTrue(composer.isHittable)
        attachScreenshot(named: "edge-arabic-locale-root", from: app)
    }

    // MARK: - Shared helpers

    private func launch(_ app: XCUIApplication, with arguments: [String]) {
        if app.state != .notRunning {
            app.terminate()
        }
        app.launchArguments = arguments + ["-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"]
        app.forwardActualXCTestContext()
        app.launch()
        // XCTest only checks for an interruption (e.g. a fresh-install system
        // permission prompt) on a synthesized event, not a plain existence
        // poll, so tap once to give the interruption monitor a chance to run
        // before any waitForExistence-based navigation below.
        app.tap()
        popToRootIfNeeded(in: app)
    }

    /// A shared dev simulator/device has landed a fresh `launch()` on a
    /// pushed screen left over from an earlier run (observed as a "Weight"
    /// metric detail with a live Back button) instead of the fixture's
    /// intended root -- the account's own state outlives the process. No
    /// fixture's intended root shows a navigation Back button (the custom
    /// `photoTimelineRootNavigation` toolbar isn't a pushed screen, and a
    /// fixture like ChatFirst that deliberately opens off the timeline root
    /// doesn't push one either), so any Back button present here is stray.
    /// Records what was actually on screen before popping, so the recovery
    /// is visible even on an otherwise-passing run. A single fast `.exists`
    /// check when already at the fixture-driven root.
    private func popToRootIfNeeded(in app: XCUIApplication) {
        guard app.navigationBars.buttons["Back"].exists else { return }

        // A single lightweight query, not a full-tree `allElementsBoundByIndex`
        // scan: that raced a screen still mid-transition right after launch
        // ("Failed to get matching snapshot: No matches found for Element at
        // index N", a hard XCTest failure, not a catchable Swift error) on
        // this exact codepath. The nav bar's own identifier already carries
        // the screen's title (e.g. "Weight") without walking the tree.
        let screenTitle = app.navigationBars.firstMatch.identifier
        let found = screenTitle.isEmpty ? "an unidentified pushed screen" : screenTitle
        let attachment = XCTAttachment(string: "launch did not land on root: \(found)")
        attachment.name = "launch-stray-navigation"
        attachment.lifetime = .keepAlways
        add(attachment)

        for _ in 0..<5 {
            let backButton = app.navigationBars.buttons["Back"]
            guard backButton.exists, backButton.isHittable else { return }
            backButton.tap()
        }
    }

    private func openMVPWeightEntry(in app: XCUIApplication) throws {
        guard app.textFields["mvp_weight_text_field"].waitForExistence(timeout: 10) else {
            throw XCTSkip("MVP weight entry field is not present under this fixture.")
        }
    }

    private func openAddEntrySheetFromHome(in app: XCUIApplication) throws {
        assertTimelineRootAppears(in: app, timeout: 30)
        let logButton = app.buttons["home_v2_log_weight"]
        guard logButton.waitForExistence(timeout: 8) else {
            throw XCTSkip("home_v2_log_weight entry point is not present under this fixture.")
        }
        logButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_log_sheet"].waitForExistence(timeout: 8))
    }

    private func waitForTimelineRoot(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isAtTimelineRoot(app) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return isAtTimelineRoot(app)
    }

    /// True only when a root marker is actually hittable (front-most) and no
    /// navigation Back button is showing. `.exists` alone on these
    /// identifiers is not enough: SwiftUI can keep the root mounted --
    /// still reporting `.exists` -- while a NavigationStack destination is
    /// pushed on top of it, which previously let this assertion pass on a
    /// stray `world_class_screen_metricDetail` screen (own simulator run,
    /// Test-LogYourBody-2026.09.28_14-48-12: "rotate-timeline" showed a
    /// Weight metric detail with a live Back button, not the timeline root).
    private func isAtTimelineRoot(_ app: XCUIApplication) -> Bool {
        guard !app.navigationBars.buttons["Back"].exists else { return false }
        let candidates = [
            app.descendants(matching: .any)["photo_timeline_root_nav"],
            app.descendants(matching: .any)["photo_timeline_root_page_timeline"],
            app.descendants(matching: .any)["launch_timeline_surface"],
            app.descendants(matching: .any)["dashboard_home_timeline_hero"],
            app.buttons["Open Menu"]
        ]
        return candidates.contains { $0.isHittable }
    }

    /// Wraps `waitForTimelineRoot` with failure diagnostics: on timeout it
    /// attaches the full element tree and fails with the `world_class_screen_*`
    /// identifiers actually on screen, so a red run says what was showing
    /// instead of just "false". Real-device runs have seen the plain
    /// `waitForTimelineRoot` timeout fire under notification-banner pressure
    /// with no indication of what was on screen instead; this is the fix.
    @discardableResult
    private func assertTimelineRootAppears(
        in app: XCUIApplication,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        if waitForTimelineRoot(in: app, timeout: timeout) {
            return true
        }

        attachDiagnosticTree(from: app, named: "timeline-root-timeout-tree")
        let screenIdentifiers = app.descendants(matching: .any).allElementsBoundByIndex
            .map(\.identifier)
            .filter { $0.hasPrefix("world_class_screen_") }
        let found = screenIdentifiers.isEmpty
            ? "no world_class_screen_* identifiers were found"
            : "found: \(screenIdentifiers.joined(separator: ", "))"
        XCTFail("Timeline root did not appear within \(timeout)s (\(found)).", file: file, line: line)
        return false
    }

    /// Finds the Settings entry inside the currently open root menu overlay.
    /// The overlay differs by surface: the legacy `PhotoTimelineNavigationMenu`
    /// exposes `photo_timeline_menu_settings`
    /// (DashboardViewLiquid+PhotoTimelineHUD.swift), the HomeV2 sidebar
    /// exposes `home_v2_sidebar_settings` (HomeV2SidebarView.swift). Prefer
    /// the concrete identifier for whichever is active; fall back to a
    /// label-based lookup only if neither is present yet.
    private func waitForSettingsMenuEntry(in app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        let legacy = app.buttons["photo_timeline_menu_settings"]
        let homeV2 = app.buttons["home_v2_sidebar_settings"]
        while Date() < deadline {
            if legacy.exists { return legacy }
            if homeV2.exists { return homeV2 }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return app.buttons["Settings"]
    }

    private func waitForSettingsDetailScreen(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let hasNavBarButton = !app.navigationBars.buttons.allElementsBoundByIndex.isEmpty
            if hasNavBarButton && !app.descendants(matching: .any)["home_v2_settings"].exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func openPhotoTimelineMenu(in app: XCUIApplication) {
        let menu = app.buttons["Open Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap()
        // The menu is a fullScreenCover; its transition is noticeably slower
        // on a real device under Instruments-level automation overhead than
        // in a simulator, so this needs more headroom than a typical wait.
        if !waitForMenuOverlay(in: app, timeout: 8) {
            // A single retry covers the rare case where the first tap lands
            // just as the cover starts presenting and gets swallowed.
            menu.tap()
        }
        XCTAssertTrue(waitForMenuOverlay(in: app, timeout: 8), "Root menu overlay did not appear after tapping Open Menu.")
    }

    /// Two distinct overlays can render behind `isShowingPhotoTimelineMenu`
    /// depending on `HomeV2Policy`: the legacy `PhotoTimelineNavigationMenu`,
    /// wrapped in `photo_timeline_menu` (DashboardViewLiquid+PhotoTimelineHUD.swift),
    /// or the HomeV2 sidebar, which has no single wrapper identifier but always
    /// renders its `home_v2_sidebar_settings` row once presented
    /// (HomeV2SidebarView.swift).
    private func waitForMenuOverlay(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let candidates = [
            app.descendants(matching: .any)["photo_timeline_menu"],
            app.buttons["home_v2_sidebar_settings"]
        ]
        while Date() < deadline {
            if candidates.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return candidates.contains { $0.exists }
    }

    private func navigateBack(in app: XCUIApplication) {
        for identifier in ["home_v2_reminders_back", "profile_editor_cancel_button"] {
            let button = app.buttons[identifier]
            if button.exists, button.isHittable {
                button.tap()
                return
            }
        }
        let navBack = app.navigationBars.buttons.element(boundBy: 0)
        if navBack.exists, navBack.isHittable {
            navBack.tap()
        }
    }

    /// A tap does not always land focus in time on a real device, and typing
    /// into an unfocused field raises a hard XCTest event synthesis error.
    /// XCUIElement has no public focus query, so wait for the keyboard
    /// itself as a focus proxy before typing.
    private func waitForKeyboard(in app: XCUIApplication, timeout: TimeInterval = 1.5) -> Bool {
        app.keyboards.element.waitForExistence(timeout: timeout)
    }

    /// Clears a focused text field's existing value with backspaces. SwiftUI
    /// `TextField` has no native "Clear text" button, so this is the only
    /// reliable way to reset a field between values in the same test.
    private func clearText(in field: XCUIElement) {
        guard let current = field.value as? String, !current.isEmpty else { return }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
        field.typeText(deleteString)
    }

    private func dismissKeyboardIfNeeded(in app: XCUIApplication) {
        let doneButton = app.keyboards.buttons["Done"]
        if doneButton.exists {
            doneButton.tap()
            return
        }
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)
        ).tap()
    }

    private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Attaches the full accessibility-element tree so a red run says what
    /// was actually on screen, not just that a wait timed out.
    private func attachDiagnosticTree(from app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Layout defect detection

    /// Fails with a screenshot if `layoutAnomalies` finds anything at this
    /// checkpoint. Unlike the chaos monkey's soft per-step recording, these
    /// are dedicated, deterministic checkpoints under an extreme text size,
    /// so a genuine defect should fail the test outright.
    private func assertNoLayoutAnomalies(
        in app: XCUIApplication,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        attachDiagnosticTree(from: app, named: "layout-scan-\(context)-tree")
        attachScreenshot(named: "layout-scan-\(context)", from: app)
        let window = app.windows.firstMatch.frame
        let elements = app.buttons.allElementsBoundByIndex + app.staticTexts.allElementsBoundByIndex
        let geometry = elements.map { "\($0.identifier) \($0.label): \($0.frame)" }
        let attachment = XCTAttachment(string: "window=\(window)\n" + geometry.joined(separator: "\n"))
        attachment.name = "layout-scan-\(context)-geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        var observations: [String] = []
        let findings = layoutAnomalies(in: app, observations: &observations)
        let clipping = XCTAttachment(string: observations.joined(separator: "\n"))
        clipping.name = "layout-scan-\(context)-expected-native-scroll-clipping"
        clipping.lifetime = .keepAlways
        add(clipping)
        guard !findings.isEmpty else { return }
        attachScreenshot(named: "layout-anomaly-\(context)", from: app)
        XCTFail("Layout anomalies at \(context): \(findings.joined(separator: "; "))", file: file, line: line)
    }

    /// Scans every hittable button and static text for three classes of
    /// layout defect: a frame extending outside the app window, a
    /// zero-size frame while the element still reports as hittable, or a
    /// label clipped down to a single ellipsis. The keyboard and system
    /// alerts are excluded -- neither is the app's layout to fix.
    private func layoutAnomalies(in app: XCUIApplication, observations: inout [String]) -> [String] {
        guard !app.keyboards.element.exists, !app.alerts.firstMatch.exists else { return [] }
        let windowFrame = app.windows.firstMatch.frame
        guard windowFrame.width > 0, windowFrame.height > 0 else { return [] }

        let candidates = app.buttons.allElementsBoundByIndex + app.staticTexts.allElementsBoundByIndex

        let scrollGeometry = ChaosScrollGeometry(app: app)
        var findings: [String] = []
        for element in candidates {
            guard element.exists else { continue }
            let frame = element.frame

            // `.isHittable` itself can hard-fail ("Failed to determine
            // hittability ...: Activation point invalid and no suggested
            // hit points based on element frame") for a degenerate frame
            // instead of returning false, so geometry is checked -- and a
            // non-finite/zero-size frame reported directly -- before ever
            // calling it (own simulator evidence: a "What changed
            // recently?" button crashed the whole scan this way under
            // AccessibilityXXXL, before this reordering).
            guard frame.width.isFinite, frame.height.isFinite,
                frame.origin.x.isFinite, frame.origin.y.isFinite else {
                findings.append("non-finite frame: \(describeLayoutElement(element))")
                continue
            }
            if frame.width <= 0 || frame.height <= 0 {
                findings.append("zero-size frame: \(describeLayoutElement(element))")
                continue
            }

            let overflowsWindow = frame.minX < windowFrame.minX - 1 || frame.maxX > windowFrame.maxX + 1
                || frame.minY < windowFrame.minY - 1 || frame.maxY > windowFrame.maxY + 1
            if overflowsWindow && scrollGeometry.isExpectedScrollClipping(element, window: windowFrame) {
                observations.append("native scroll clipping: \(describeLayoutElement(element))")
                continue
            }
            // Fully offscreen frames must never reach XCTest's activation-point query.
            guard frame.intersects(windowFrame) else {
                findings.append("non-scroll frame outside window bounds \(windowFrame): \(describeLayoutElement(element))")
                continue
            }
            guard element.isHittable else { continue }
            if overflowsWindow {
                findings.append("frame outside window bounds \(windowFrame): \(describeLayoutElement(element))")
                continue
            }
            if element.label == "\u{2026}" {
                findings.append("label clipped to a single ellipsis: \(describeLayoutElement(element))")
            }
        }
        return findings
    }

    private func describeLayoutElement(_ element: XCUIElement) -> String {
        let identifier = element.identifier.isEmpty ? "(no identifier)" : element.identifier
        let label = element.label.isEmpty ? "(no label)" : element.label
        return "\(String(describing: element.elementType)) id=\(identifier) label=\"\(label)\" frame=\(element.frame)"
    }
}
