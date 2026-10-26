import XCTest

final class TrainingNumericScrubUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDragAllLiveDimensionsPersistsDraftAcrossRelaunchWithoutRecordingASet() {
        let app = launchFixture()
        let reps = control("reps", in: app)
        let load = control("load", in: app)
        let rir = control("rir", in: app)
        drag(reps, horizontal: 60, velocity: .fast)
        let repsValue = reps.value as? String
        drag(load, horizontal: -48, velocity: .slow)
        let loadValue = load.value as? String
        reveal(rir, in: app)
        drag(rir, horizontal: 60, velocity: .fast)
        XCTAssertEqual(rir.value as? String, "6")
        let values = [repsValue, loadValue, rir.value as? String]
        for value in values { XCTAssertNotNil(value) }
        XCTAssertNotEqual(values[0], "10")
        XCTAssertNotEqual(values[1], "60")
        app.buttons["training_live_session_close_button"].tap()
        XCTAssertEqual(app.staticTexts["training_fixture_submissions"].label, "Submissions: 0")
        XCTAssertEqual(app.staticTexts["training_fixture_count"].label, "Acknowledged sets: 0")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-lybUITestResetTrainingFixture" }
        app.launch()
        open(app)
        for (index, dimension) in ["reps", "load", "rir"].enumerated() {
            XCTAssertEqual(control(dimension, in: app).value as? String, values[index])
        }
        let log = app.buttons["training_log_set_fixture_press_1"]
        reveal(log, in: app)
        log.tap()
        XCTAssertTrue(app.descendants(matching: .any)["training_load_fixture_press_2"].waitForExistence(timeout: 5))
        app.buttons["training_live_session_close_button"].tap()
        XCTAssertEqual(app.staticTexts["training_fixture_count"].label, "Acknowledged sets: 1")
        XCTAssertEqual(app.staticTexts["training_fixture_submissions"].label, "Submissions: 1")
        XCTAssertEqual(app.staticTexts["training_fixture_saved_load"].label, "Saved load: \(values[1] ?? "")")
    }

    func testImperialTapEntryRejectsWrongUnitAndReadsBackKilogramsAfterSaving() {
        let app = launchFixture(extra: ["-lybUITestTrainingScrubImperial"])
        let load = control("load", in: app)
        XCTAssertEqual(load.value as? String, "132.28")
        load.tap()
        let entry = app.textFields["training_load_fixture_press_1_entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        replace(entry, with: "5000")
        XCTAssertFalse(app.buttons["training_load_fixture_press_1_done"].isEnabled)
        replace(entry, with: "50")
        app.buttons["training_load_fixture_press_1_done"].tap()
        XCTAssertEqual(load.value as? String, "50")
        let log = app.buttons["training_log_set_fixture_press_1"]
        reveal(log, in: app)
        log.tap()
        XCTAssertTrue(app.descendants(matching: .any)["training_load_fixture_press_2"].waitForExistence(timeout: 5))
        app.buttons["training_live_session_close_button"].tap()
        let saved = app.staticTexts["training_fixture_saved_load"].label.replacingOccurrences(of: "Saved load: ", with: "")
        XCTAssertEqual(Double(saved) ?? 0, 50 / 2.20462, accuracy: 0.0001)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-lybUITestResetTrainingFixture" }
        app.launch()
        XCTAssertEqual(app.staticTexts["training_fixture_saved_load"].label, "Saved load: \(saved)")
    }

    func testCancelledDragKeyboardCancelAndBackgroundKeepThePriorValue() {
        let app = launchFixture()
        let load = control("load", in: app)
        drag(load, horizontal: 160, vertical: 90, velocity: .slow)
        XCTAssertEqual(load.value as? String, "60")
        load.tap()
        let entry = app.textFields["training_load_fixture_press_1_entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        replace(entry, with: "22,75")
        app.buttons["training_load_fixture_press_1_cancel"].tap()
        XCTAssertEqual(load.value as? String, "60")
        load.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        replace(entry, with: "22.75")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        XCTAssertEqual(load.value as? String, "60")
    }

    func testLargeTypeReducedMotionAlternativesAndSafeArea() {
        let app = launchFixture(extra: [
            "-lybUITestReduceMotion", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        for dimension in ["reps", "load", "rir"] {
            let value = control(dimension, in: app)
            reveal(value, in: app)
            XCTAssertTrue(value.isHittable)
            XCTAssertTrue(app.frame.contains(value.frame))
            let plus = app.buttons["training_\(dimension)_fixture_press_1_plus"]
            reveal(plus, in: app)
            XCTAssertGreaterThanOrEqual(plus.frame.height, 44)
            XCTAssertGreaterThanOrEqual(plus.frame.width, 44)
            let before = value.value as? String
            plus.tap()
            XCTAssertNotEqual(value.value as? String, before)
        }
        let close = app.buttons["training_live_session_close_button"]
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.frame.contains(close.frame))
    }

    func testOfflinePendingSetLocksScrubbingAndRetryCreatesOneAcknowledgement() {
        let app = launchFixture(offline: true)
        app.buttons["training_load_fixture_press_1_plus"].tap()
        let load = control("load", in: app)
        let canonical = load.value as? String
        let log = app.buttons["training_log_set_fixture_press_1"]
        reveal(log, in: app)
        log.tap()
        XCTAssertTrue(app.staticTexts["training_pending_sync"].waitForExistence(timeout: 5))
        let plus = app.buttons["training_load_fixture_press_1_plus"]
        reveal(plus, in: app)
        XCTAssertFalse(plus.isEnabled)
        XCTAssertEqual(load.value as? String, canonical)
        app.buttons["training_live_session_close_button"].tap()
        app.switches["training_fixture_offline"].tap()
        open(app)
        reveal(log, in: app)
        log.tap()
        XCTAssertTrue(app.descendants(matching: .any)["training_load_fixture_press_2"].waitForExistence(timeout: 5))
        app.buttons["training_live_session_close_button"].tap()
        XCTAssertEqual(app.staticTexts["training_fixture_count"].label, "Acknowledged sets: 1")
        XCTAssertEqual(app.staticTexts["training_fixture_submissions"].label, "Submissions: 2")
    }

    private func launchFixture(extra: [String] = [], offline: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestTrainingFixture", "-lybUITestResetTrainingFixture", "-lybUITestTrainingScrub"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["training_fixture_open"].waitForExistence(timeout: 10))
        if offline { app.switches["training_fixture_offline"].tap() }
        open(app)
        return app
    }

    private func open(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["training_fixture_open"].waitForExistence(timeout: 5))
        app.buttons["training_fixture_open"].tap()
        XCTAssertTrue(control("reps", in: app).waitForExistence(timeout: 5))
    }

    private func control(_ dimension: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["training_\(dimension)_fixture_press_1"]
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 where !element.isHittable {
            if element.frame.minY < scroll.frame.minY { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func replace(_ entry: XCUIElement, with text: String) {
        entry.tap()
        entry.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32) + text)
    }

    private func drag(
        _ control: XCUIElement, horizontal: CGFloat, vertical: CGFloat = 0, velocity: XCUIGestureVelocity
    ) {
        let start = control.coordinate(withNormalizedOffset: CGVector(dx: horizontal > 0 ? 0.1 : 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: horizontal, dy: vertical)),
                    withVelocity: velocity, thenHoldForDuration: 0.1)
    }
}
