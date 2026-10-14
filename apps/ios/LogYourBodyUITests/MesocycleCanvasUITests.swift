import XCTest

final class MesocycleCanvasUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReducedMotionUsesStackedDayCards() {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestCanvasFixture", "-lybUITestReduceMotion"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["canvas_layout_stack"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["canvas_motion_reduced"].waitForExistence(timeout: 8))
    }

    func testGoalThroughUndoKeepsTheCanvasAndReadbackTogether() {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestCanvasFixture"]
        app.launch()

        send(app, "Build a 4-week hypertrophy plan for a full gym")
        XCTAssertTrue(app.descendants(matching: .any)["canvas_narration"].waitForExistence(timeout: 8))
        XCTAssertTrue(narration(app).localizedCaseInsensitiveContains("not saved"))
        tap(app, "canvas_accept")
        XCTAssertTrue(app.staticTexts["Incline dumbbell press"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Leg press"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["canvas_day_monday_single"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["canvas_layout_stack"].exists)

        send(app, "Prioritize upper chest and triceps")
        tap(app, "canvas_reject")
        XCTAssertTrue(narration(app).localizedCaseInsensitiveContains("unchanged"))
        XCTAssertTrue(app.staticTexts["Incline dumbbell press"].exists)

        send(app, "Prioritize upper chest and triceps")
        tap(app, "canvas_sets_6_incline_dumbbell_press:monday:single:0")
        tap(app, "canvas_accept")
        XCTAssertTrue(app.staticTexts.matching(identifier: "canvas_card_incline_dumbbell_press:monday:single:0").firstMatch.waitForExistence(timeout: 8))

        send(app, "five training days")
        tap(app, "canvas_accept")
        XCTAssertTrue(app.descendants(matching: .any)["canvas_day_wednesday_single"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "canvas_day_wednesday_single").count, 1)
        XCTAssertFalse(app.buttons["canvas_accept"].exists)

        send(app, "Split Wednesday into AM/PM")
        tap(app, "canvas_accept")
        XCTAssertTrue(app.descendants(matching: .any)["canvas_day_wednesday_am"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["canvas_day_wednesday_pm"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["canvas_day_wednesday_single"].exists)

        tap(app, "canvas_inject_unsupported")
        XCTAssertTrue(narration(app).localizedCaseInsensitiveContains("unsupported equipment"))
        XCTAssertTrue(app.staticTexts["Incline dumbbell press"].exists)
        XCTAssertFalse(app.staticTexts["Smith machine incline press"].exists)

        let composer = app.textFields["canvas_composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 4))
        composer.tap()
        composer.typeText("Swap incline dumbbell press for the Smith machine incline press")
        tap(app, "canvas_voice")
        XCTAssertTrue(app.descendants(matching: .any)["canvas_voice_pending"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Incline dumbbell press"].exists)
        tap(app, "canvas_voice_confirm")
        tap(app, "canvas_accept")
        XCTAssertTrue(app.staticTexts["Smith machine incline press"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Incline dumbbell press"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["canvas_execution"].label.contains("Smith machine incline press"))

        tap(app, "canvas_move_friday_standing_calf_raise:tuesday:single:3")
        tap(app, "canvas_accept")
        XCTAssertTrue(app.descendants(matching: .any)["canvas_day_friday_single"].waitForExistence(timeout: 8))
        tap(app, "canvas_reload")
        XCTAssertTrue(app.staticTexts["Standing calf raise"].exists)

        send(app, "undo")
        tap(app, "canvas_accept")
        XCTAssertTrue(app.descendants(matching: .any)["canvas_day_tuesday_single"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Leg press"].exists)
        XCTAssertTrue(app.staticTexts["Standing calf raise"].exists)

        tap(app, "canvas_inject_missed")
        XCTAssertTrue(narration(app).localizedCaseInsensitiveContains("unchanged"))
        XCTAssertTrue(app.staticTexts["Standing calf raise"].exists)
    }

    private func send(_ app: XCUIApplication, _ text: String) {
        let composer = app.textFields["canvas_composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        composer.tap()
        composer.typeText(text)
        tap(app, "canvas_send")
    }

    private func tap(_ app: XCUIApplication, _ identifier: String) {
        let control = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(control.waitForExistence(timeout: 8), identifier)
        control.tap()
    }

    private func narration(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["canvas_narration"].label
    }
}
