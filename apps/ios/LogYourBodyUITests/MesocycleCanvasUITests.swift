import XCTest

final class MesocycleCanvasUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReducedMotionUsesStackedDayCards() {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestCanvasFixture", "-lybUITestReduceMotion"]
        app.launch()
        send(app, "Build a 4-week hypertrophy plan for a full gym")
        tap(app, "canvas_accept")
        XCTAssertTrue(app.staticTexts["Incline dumbbell press"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["canvas_layout_stack"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["canvas_motion_reduced"].waitForExistence(timeout: 8))
        attachScreenshot(named: "launch-quality-canvas-reduced-motion", from: app)
    }

    func testGoalThroughUndoKeepsTheCanvasAndReadbackTogether() {
        // The runner's maximum allowance. Pinned decisions keep this under it;
        // the default 90s budget cannot type and accept the whole week.
        executionTimeAllowance = 180
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
        let inclinePressCard = app.staticTexts.matching(
            identifier: "canvas_card_incline_dumbbell_press:monday:single:0"
        ).firstMatch
        XCTAssertTrue(inclinePressCard.waitForExistence(timeout: 8))

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
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 3))
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
        XCTAssertTrue(app.descendants(matching: .any)["canvas_execution"].label.contains("Smith machine incline press"))
        revealReadback(app)
        attachScreenshot(named: "launch-quality-canvas-replay-readback", from: app)

        send(app, "undo")
        tap(app, "canvas_accept")
        XCTAssertTrue(app.descendants(matching: .any)["canvas_day_tuesday_single"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Leg press"].exists)
        XCTAssertTrue(app.staticTexts["Standing calf raise"].exists)
        revealReadback(app)
        attachScreenshot(named: "launch-quality-canvas-undo-readback", from: app)

        tap(app, "canvas_inject_missed")
        XCTAssertTrue(narration(app).localizedCaseInsensitiveContains("unchanged"))
        XCTAssertTrue(app.staticTexts["Standing calf raise"].exists)
    }

    private func send(_ app: XCUIApplication, _ text: String) {
        let composer = app.textFields["canvas_composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields.matching(identifier: "canvas_composer").count, 1)
        XCTAssertEqual(app.textFields.matching(identifier: "canvas_root").count, 0)
        XCTAssertEqual(app.buttons.matching(identifier: "canvas_root").count, 0)
        XCTAssertTrue(composer.isHittable)
        composer.tap()
        composer.typeText(text)
        tap(app, "canvas_send")
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 3))
        let accept = app.buttons["canvas_accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 8))
        // Proposal decisions stay reachable even when its change list fills the scroll view.
        XCTAssertTrue(accept.isHittable)
        XCTAssertTrue(app.buttons["canvas_reject"].isHittable)
    }

    private func tap(_ app: XCUIApplication, _ identifier: String) {
        let control = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(control.waitForExistence(timeout: 8), identifier)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: identifier).count, 1, identifier)
        let scroll = app.scrollViews.firstMatch
        // Previews sit above the plan. Voice decisions and fixture checks are pinned.
        let abovePlan = identifier == "canvas_accept" || identifier == "canvas_reject"
            || identifier.hasPrefix("canvas_sets_")
        for _ in 0..<4 where !control.isHittable {
            if abovePlan {
                scroll.swipeDown(velocity: .fast)
            } else {
                scroll.swipeUp(velocity: .fast)
            }
        }
        XCTAssertTrue(control.isHittable, identifier)
        control.tap()
    }

    private func narration(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["canvas_narration"].label
    }

    private func revealReadback(_ app: XCUIApplication) {
        let readback = app.descendants(matching: .any)["canvas_execution"]
        XCTAssertTrue(readback.waitForExistence(timeout: 4))
        let reveal = app.buttons["canvas_reveal_readback"]
        if !readback.isHittable, reveal.exists, reveal.isHittable {
            reveal.tap()
        }
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 where !readback.isHittable {
            scroll.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(readback.isHittable)
    }

    private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
