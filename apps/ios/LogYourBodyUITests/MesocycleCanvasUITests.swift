import XCTest

final class MesocycleCanvasUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDraftSplitVoiceDragPersistsAndReducedMotion() {
        let app = XCUIApplication()
        app.launchArguments = ["-lybUITestMesocycleCanvasFixture", "-lybUITestResetMesocycleCanvas", "-lybUITestReduceMotion"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Motion reduced"].waitForExistence(timeout: 8))
        send(app, "Build a hypertrophy plan")
        accept(app)
        XCTAssertTrue(app.staticTexts["Incline dumbbell press"].waitForExistence(timeout: 3))
        let readback = app.staticTexts.matching(identifier: "mesocycle_canvas_readback").firstMatch
        XCTAssertTrue(
            app.staticTexts["mesocycle_canvas_readback"].exists ||
                readback.label.contains("Incline dumbbell press")
        )

        send(app, "Prioritize upper chest and triceps")
        let reject = app.buttons["mesocycle_canvas_reject"]
        XCTAssertTrue(reject.waitForExistence(timeout: 3))
        reject.tap()

        send(app, "Make it five training days")
        accept(app)
        XCTAssertTrue(app.staticTexts["Thursday"].waitForExistence(timeout: 3))

        send(app, "Split Wednesday AM/PM into stacked sessions")
        accept(app)
        XCTAssertTrue(app.staticTexts["Wednesday AM"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Wednesday PM"].exists)

        send(app, "Swap incline dumbbell press for the Smith machine incline press")
        XCTAssertTrue(app.staticTexts["mesocycle_canvas_live"].waitForExistence(timeout: 3) ||
            app.staticTexts.matching(identifier: "mesocycle_canvas_live").firstMatch.label.contains("smith_machine"))
        let live = app.descendants(matching: .any)["mesocycle_canvas_live"]
        XCTAssertTrue(live.label.contains("smith_machine"))

        send(app, "I have a Smith machine")
        accept(app)
        send(app, "Swap incline dumbbell press for the Smith machine incline press", voice: true)
        XCTAssertEqual(app.descendants(matching: .any)["mesocycle_canvas_preview_source"].label, "voice")
        accept(app)
        XCTAssertTrue(app.staticTexts["Smith machine incline press"].waitForExistence(timeout: 3))

        let move = app.buttons["mesocycle_move_ex:tue:dumbbell_curl"]
        XCTAssertTrue(move.waitForExistence(timeout: 3))
        move.tap()
        accept(app)

        app.terminate()
        let reloaded = XCUIApplication()
        reloaded.launchArguments = ["-lybUITestMesocycleCanvasFixture", "-lybUITestReduceMotion"]
        reloaded.launch()
        XCTAssertTrue(reloaded.staticTexts["Smith machine incline press"].waitForExistence(timeout: 8))
        XCTAssertTrue(reloaded.staticTexts["Motion reduced"].exists)
        let readback = reloaded.descendants(matching: .any)["mesocycle_canvas_readback"]
        XCTAssertTrue(readback.label.contains("Smith machine incline press"))
        XCTAssertTrue(readback.label.contains("Goblet squat"))
        XCTAssertTrue(readback.label.contains("Dumbbell hip thrust"))

        send(reloaded, "undo")
        accept(reloaded)
        send(reloaded, "redo")
        accept(reloaded)
        XCTAssertTrue(reloaded.descendants(matching: .any)["mesocycle_canvas_readback"].label.contains("Dumbbell curl"))
    }

    private func send(_ app: XCUIApplication, _ text: String, voice: Bool = false) {
        let field = app.textFields["mesocycle_canvas_composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.buttons[voice ? "mesocycle_canvas_voice" : "mesocycle_canvas_send"].tap()
    }

    private func accept(_ app: XCUIApplication) {
        let button = app.buttons["mesocycle_canvas_accept"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }
}
