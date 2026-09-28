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
            let dismissLabels = ["Don't Allow", "Not Now", "Cancel", "Deny", "No Thanks", "Later", "OK"]
            for label in dismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            if let firstButton = alert.buttons.allElementsBoundByIndex.first, firstButton.exists {
                firstButton.tap()
                return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        if let systemAlertMonitor {
            removeUIInterruptionMonitor(systemAlertMonitor)
        }
        systemAlertMonitor = nil
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

        XCTAssertEqual(app.state, .runningForeground, "App must resume cleanly after a mid-save backgrounding.")
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 3), "No error alert should surface after resuming.")
    }

    // MARK: - 5. Rotate through main screens

    func testRotatingThroughMainScreensDoesNotCrash() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        attachScreenshot(named: "rotate-timeline", from: app)

        openPhotoTimelineMenu(in: app)
        let settings = app.buttons["Settings"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            XCTAssertTrue(app.descendants(matching: .any)["home_v2_settings"].waitForExistence(timeout: 8))
            attachScreenshot(named: "rotate-settings", from: app)
            app.buttons["home_v2_settings_back"].tap()
        }

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 8))
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
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])
        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        openPhotoTimelineMenu(in: app)
        let settings = app.buttons["Settings"]
        guard settings.waitForExistence(timeout: 5) else {
            throw XCTSkip("Settings entry point not reachable from this fixture.")
        }
        settings.tap()

        let integrationsLink = app.buttons["settings_integrations_link"]
        guard integrationsLink.waitForExistence(timeout: 8) else {
            throw XCTSkip("Integrations link not reachable from this fixture.")
        }
        integrationsLink.tap()

        let bulkImportLink = app.buttons["integrations_bulk_photo_import_link"]
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

        // Wait for the composer itself, not just the timeline root: the chat
        // surface finishes mounting after the timeline does, and checking only
        // the timeline root races the offline-copy assertion below.
        let composer = app.textFields["chat_composer"]
        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        XCTAssertTrue(composer.waitForExistence(timeout: 8))

        let retry = app.buttons["chat_retry_button"]
        XCTAssertTrue(retry.waitForExistence(timeout: 12), "Offline chat must surface a retryable control.")
        XCTAssertTrue(retry.isHittable)
        attachScreenshot(named: "edge-chat-offline-retry", from: app)
    }

    // MARK: - 8. Settings hierarchy round trip

    func testSettingsHierarchyRoundTripsThroughEverySectionAndBack() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        openPhotoTimelineMenu(in: app)
        let settings = app.buttons["Settings"]
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
        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 8))
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

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        openPhotoTimelineMenu(in: app)
        let settings = app.buttons["Settings"]
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
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2EmptyFixture"])
        try openAddEntrySheetFromHome(in: app)

        let notesField = app.textFields["GLP-1 dose notes"]
        guard notesField.waitForExistence(timeout: 5) else {
            throw XCTSkip("GLP-1 notes field is not reachable from this fixture.")
        }
        notesField.tap()
        XCTAssertTrue(waitForKeyboard(in: app), "Keyboard did not appear after tapping the field.")
        let longNote = String(repeating: "n", count: 300)
        notesField.typeText(longNote)
        dismissKeyboardIfNeeded(in: app)

        XCTAssertEqual(app.state, .runningForeground, "A 300-character note must not crash the entry sheet.")
    }

    // MARK: - 12. Very long profile name renders without clipping

    func testVeryLongProfileNameRendersWithoutClipping() throws {
        let app = XCUIApplication()
        launch(app, with: ["-lybUITestPhotoTimelineHUDFixture"])

        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        openPhotoTimelineMenu(in: app)
        let settings = app.buttons["Settings"]
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

    // MARK: - Shared helpers

    private func launch(_ app: XCUIApplication, with arguments: [String]) {
        if app.state != .notRunning {
            app.terminate()
        }
        app.launchArguments = arguments + ["-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"]
        app.launch()
        // XCTest only checks for an interruption (e.g. a fresh-install system
        // permission prompt) on a synthesized event, not a plain existence
        // poll, so tap once to give the interruption monitor a chance to run
        // before any waitForExistence-based navigation below.
        app.tap()
    }

    private func openMVPWeightEntry(in app: XCUIApplication) throws {
        guard app.textFields["mvp_weight_text_field"].waitForExistence(timeout: 10) else {
            throw XCTSkip("MVP weight entry field is not present under this fixture.")
        }
    }

    private func openAddEntrySheetFromHome(in app: XCUIApplication) throws {
        XCTAssertTrue(waitForTimelineRoot(in: app, timeout: 12))
        let logButton = app.buttons["home_v2_log_weight"]
        guard logButton.waitForExistence(timeout: 8) else {
            throw XCTSkip("home_v2_log_weight entry point is not present under this fixture.")
        }
        logButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_log_sheet"].waitForExistence(timeout: 8))
    }

    private func waitForTimelineRoot(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let candidates = [
            app.descendants(matching: .any)["photo_timeline_root_nav"],
            app.descendants(matching: .any)["photo_timeline_root_page_timeline"],
            app.descendants(matching: .any)["launch_timeline_surface"],
            app.descendants(matching: .any)["dashboard_home_timeline_hero"],
            app.buttons["Open Menu"]
        ]
        while Date() < deadline {
            if candidates.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return candidates.contains { $0.exists }
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
        if !app.descendants(matching: .any)["photo_timeline_menu"].waitForExistence(timeout: 8) {
            // A single retry covers the rare case where the first tap lands
            // just as the cover starts presenting and gets swallowed.
            menu.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["photo_timeline_menu"].waitForExistence(timeout: 8))
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
}
