import UIKit
import XCTest

final class HomeV2TimelineIntegrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }


    func testMountedHeldCorrectionKeepsOriginalContextThroughActualStoredReturn() throws {
        let nonce = UUID()
        let launchedAt = Date()
        let completion = CorrectionFixtureCompletion()
        let app = launch(correctionNonce: nonce, correctionCompletion: completion)
        _ = try waitCorrectionFixture(app, scope: "home", nonce: nonce, phase: "positive-boot") {
            $0["publicationGeneration"] as? String == $0["generation"] as? String
        }
        try tapCorrectionControl(app.buttons["home_v2_context_button"])
        guard requireRawContext(app, day: launchedAt, weight: "181.0 lb", source: "Typed", bodyFat: "15.8%") else {
            return
        }
        try tapCorrectionControl(app.buttons["home_v2_edit_entry"])
        let initial = try waitCorrectionFixture(app, scope: "editor", nonce: nonce, phase: "positive-original-editor") {
            Self.correctionEditor($0) != nil
        }
        let editor = try XCTUnwrap(Self.correctionEditor(initial))
        let route = try XCTUnwrap(editor["route"] as? String)
        let lifetime = try XCTUnwrap(editor["editor"] as? String)
        try tapCorrectionControl(app.buttons["home_v2_correction_fixture_arm"])
        try tapCorrectionControl(app.buttons["home_v2_log_sheet_plus"])
        let field = app.textFields["home_v2_log_sheet_value"]
        XCTAssertEqual(field.value as? String, "181.1")
        try tapCorrectionControl(app.buttons["home_v2_log_sheet_save"])
        let held = try waitCorrectionFixture(app, scope: "editor", nonce: nonce, phase: "positive-actual-write-held") {
            Self.correctionAttempt($0)?["held"] as? Bool == true
        }
        let attempt = try XCTUnwrap(Self.correctionAttempt(held))
        let attemptID = try XCTUnwrap(attempt["id"] as? String)
        XCTAssertEqual(attempt["route"] as? String, route)
        XCTAssertEqual(attempt["editor"] as? String, lifetime)
        XCTAssertEqual(Self.correctionEditor(held)?["saving"] as? Bool, true)
        XCTAssertEqual(attempt["terminal"] as? Bool, false)
        XCTAssertEqual(attempt["writerAdmissions"] as? Int, 0)
        XCTAssertEqual(attempt["writerRejections"] as? Int, 0)
        let original = try XCTUnwrap(attempt["original"] as? [String: Any])
        let beforeRaw = try XCTUnwrap(attempt["actualRaw"] as? [String: Any])
        XCTAssertEqual(original as NSDictionary, beforeRaw as NSDictionary)
        try tapCorrectionControl(app.buttons["home_v2_correction_fixture_release_\(attemptID)"])
        let returned = try waitCorrectionFixture(app, scope: "context", nonce: nonce, phase: "positive-real-store-return") {
            guard let actual = Self.correctionAttempt($0) else { return false }
            return actual["terminal"] as? Bool == true && actual["returned"] as? Bool == true
        }
        let completed = try XCTUnwrap(Self.correctionAttempt(returned))
        XCTAssertEqual(completed["id"] as? String, attemptID)
        XCTAssertEqual(completed["writerAdmissions"] as? Int, 1)
        XCTAssertEqual(completed["writerRejections"] as? Int, 0)
        XCTAssertEqual(returned["visibleContextIDs"] as? [String], [route])
        XCTAssertFalse(app.staticTexts["home_v2_log_sheet"].exists,
                       "The real save must dismiss normally; the test does not dismiss the positive editor")
        let stored = try XCTUnwrap(completed["stored"] as? [String: Any])
        let actualRaw = try XCTUnwrap(completed["actualRaw"] as? [String: Any])
        XCTAssertEqual(stored as NSDictionary, actualRaw as NSDictionary)
        XCTAssertEqual(try XCTUnwrap(stored["weight"] as? Double), 181.1 / 2.20462, accuracy: 0.000000001)
        XCTAssertEqual(stored["body_fat_percentage"] as? Double, 15.8)
        var originalUntouched = original
        var storedUntouched = stored
        for key in ["weight", "updated_at"] {
            originalUntouched.removeValue(forKey: key)
            storedUntouched.removeValue(forKey: key)
        }
        XCTAssertEqual(originalUntouched as NSDictionary, storedUntouched as NSDictionary,
                       "Exact ID/owner/date/raw BF/method/metadata/photo/createdAt and every untouched field must survive")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(stored["updated_at"] as? Double),
                                    try XCTUnwrap(original["updated_at"] as? Double))
        assertCorrectionRootAndTransport(initial, equals: returned)
        guard requireRawContext(app, day: launchedAt, weight: "181.1 lb", source: "Typed", bodyFat: "15.8%") else {
            return
        }
        try tapCorrectionControl(app.buttons["home_v2_context_close"])
        try finishCorrectionFixture(app, nonce: nonce, baseline: initial)
        completion.markVerified()
    }

    func testMountedHeldCorrectionRejectsOldTaskAfterSameSubjectNewEditorABA() throws {
        let nonce = UUID()
        let launchedAt = Date()
        let completion = CorrectionFixtureCompletion()
        let app = launch(correctionNonce: nonce, correctionCompletion: completion)
        _ = try waitCorrectionFixture(app, scope: "home", nonce: nonce, phase: "negative-boot") {
            $0["publicationGeneration"] as? String == $0["generation"] as? String
        }
        try tapCorrectionControl(app.buttons["home_v2_context_button"])
        guard requireRawContext(app, day: launchedAt, weight: "181.0 lb", source: "Typed", bodyFat: "15.8%") else {
            return
        }
        try tapCorrectionControl(app.buttons["home_v2_edit_entry"])
        let initial = try waitCorrectionFixture(app, scope: "editor", nonce: nonce, phase: "negative-original-editor") {
            Self.correctionEditor($0) != nil
        }
        let originalEditor = try XCTUnwrap(Self.correctionEditor(initial))
        let oldRoute = try XCTUnwrap(originalEditor["route"] as? String)
        let oldLifetime = try XCTUnwrap(originalEditor["editor"] as? String)
        let oldGeneration = try XCTUnwrap(initial["generation"] as? String)
        try tapCorrectionControl(app.buttons["home_v2_correction_fixture_arm"])
        try tapCorrectionControl(app.buttons["home_v2_log_sheet_plus"])
        XCTAssertEqual(app.textFields["home_v2_log_sheet_value"].value as? String, "181.1")
        try tapCorrectionControl(app.buttons["home_v2_log_sheet_save"])
        let held = try waitCorrectionFixture(app, scope: "editor", nonce: nonce, phase: "negative-actual-write-held") {
            Self.correctionAttempt($0)?["held"] as? Bool == true
        }
        let attemptID = try XCTUnwrap(Self.correctionAttempt(held)?["id"] as? String)
        let original = try XCTUnwrap(Self.correctionAttempt(held)?["original"] as? [String: Any])
        XCTAssertEqual(Self.correctionAttempt(held)?["actualRaw"] as? NSDictionary, original as NSDictionary)
        try tapCorrectionControl(app.buttons["home_v2_correction_fixture_replace_\(attemptID)"])
        let newHome = try waitCorrectionFixture(app, scope: "home", nonce: nonce, phase: "negative-old-modals-gone") {
            guard let generation = $0["generation"] as? String,
                  let closed = $0["closedContextIDs"] as? [String],
                  let old = ($0["editors"] as? [[String: Any]])?.filter({ $0["editor"] as? String == oldLifetime }),
                  old.count == 1, let attempt = Self.correctionAttempt($0) else { return false }
            return generation != oldGeneration && $0["publicationGeneration"] as? String == generation &&
                closed.contains(oldRoute) && old[0]["visible"] as? Bool == false &&
                attempt["held"] as? Bool == true && attempt["terminal"] as? Bool == false
        }
        XCTAssertFalse(app.staticTexts["home_v2_context"].exists)
        XCTAssertFalse(app.staticTexts["home_v2_log_sheet"].exists)
        assertCorrectionRootAndTransport(initial, equals: newHome)
        try tapCorrectionControl(app.buttons["home_v2_context_button"])
        guard requireRawContext(app, day: launchedAt, weight: "181.0 lb", source: "Typed", bodyFat: "15.8%") else {
            return
        }
        try tapCorrectionControl(app.buttons["home_v2_edit_entry"])
        let newEditorState = try waitCorrectionFixture(app, scope: "editor", nonce: nonce,
                                                       phase: "negative-new-editor-before-old-release") {
            guard let editor = Self.correctionEditor($0) else { return false }
            return editor["route"] as? String != oldRoute && editor["editor"] as? String != oldLifetime &&
                editor["generation"] as? String == $0["generation"] as? String &&
                editor["saving"] as? Bool == false && editor["invalidated"] as? Bool == false &&
                editor["error"] is NSNull && Self.correctionAttempt($0)?["held"] as? Bool == true
        }
        let newEditor = try XCTUnwrap(Self.correctionEditor(newEditorState))
        XCTAssertEqual(app.textFields["home_v2_log_sheet_value"].value as? String, "181.0")
        XCTAssertTrue(app.buttons["home_v2_log_sheet_save"].exists)
        XCTAssertTrue(app.buttons["home_v2_log_sheet_save"].isEnabled)
        try tapCorrectionControl(app.buttons["home_v2_correction_fixture_release_\(attemptID)"])
        let terminal = try waitCorrectionFixture(app, scope: "editor", nonce: nonce, phase: "negative-old-task-actual-terminal") {
            Self.correctionAttempt($0)?["terminal"] as? Bool == true
        }
        let completed = try XCTUnwrap(Self.correctionAttempt(terminal))
        XCTAssertEqual(completed["id"] as? String, attemptID)
        XCTAssertEqual(completed["released"] as? Bool, true)
        XCTAssertEqual(completed["held"] as? Bool, false)
        XCTAssertEqual(completed["cancelObserved"] as? Bool, true,
                       "Cancellation observation is distinct from the separately awaited actual task terminal")
        XCTAssertEqual(completed["writerAdmissions"] as? Int, 0)
        XCTAssertEqual(completed["writerRejections"] as? Int, 1,
                       "The actual CoreData writer admission must reject the original receipt")
        XCTAssertEqual(completed["returned"] as? Bool, false)
        XCTAssertTrue(completed["stored"] is NSNull)
        XCTAssertEqual(completed["actualRaw"] as? NSDictionary, original as NSDictionary)
        let terminalEditor = try XCTUnwrap(Self.correctionEditor(terminal))
        XCTAssertEqual(terminalEditor as NSDictionary, newEditor as NSDictionary)
        XCTAssertEqual(terminal["generation"] as? String, newEditorState["generation"] as? String)
        XCTAssertEqual(app.textFields["home_v2_log_sheet_value"].value as? String, "181.0")
        XCTAssertFalse(app.staticTexts["home_v2_log_sheet_error"].exists)
        XCTAssertTrue(app.buttons["home_v2_log_sheet_save"].isEnabled)
        assertCorrectionRootAndTransport(initial, equals: terminal)
        // Cleanup only AFTER rejection/store/new-editor assertions. This is not positive save/dismiss proof.
        let sheetTitle = app.staticTexts["home_v2_log_sheet"]
        for _ in 0..<2 where sheetTitle.exists {
            sheetTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            )
        }
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !sheetTitle.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
        guard requireRawContext(app, day: launchedAt, weight: "181.0 lb", source: "Typed", bodyFat: "15.8%") else {
            return
        }
        try tapCorrectionControl(app.buttons["home_v2_context_close"])
        try finishCorrectionFixture(app, nonce: nonce, baseline: initial)
        completion.markVerified()
    }

    private static func correctionAttempt(_ snapshot: [String: Any]) -> [String: Any]? {
        guard let attempts = snapshot["attempts"] as? [[String: Any]], attempts.count == 1 else { return nil }
        return attempts[0]
    }

    private static func correctionEditor(_ snapshot: [String: Any]) -> [String: Any]? {
        guard let editors = snapshot["editors"] as? [[String: Any]] else { return nil }
        let visible = editors.filter { $0["visible"] as? Bool == true }
        guard visible.count == 1 else { return nil }
        return visible[0]
    }

    private func correctionFixtureObject(_ app: XCUIApplication, scope: String) -> [String: Any]? {
        let query = app.staticTexts.matching(identifier: "home_v2_correction_fixture_snapshot_\(scope)")
        guard query.count == 1, let data = query.element.label.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func waitCorrectionFixture(
        _ app: XCUIApplication, scope: String, nonce: UUID, phase: String,
        matching condition: @escaping ([String: Any]) -> Bool
    ) throws -> [String: Any] {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = self.correctionFixtureObject(app, scope: scope),
                  value["admitted"] as? Bool == true, value["nonce"] as? String == nonce.uuidString,
                  value["commandError"] is NSNull,
                  value["failureCleanupRequested"] as? Bool == false else { return false }
            return condition(value)
        }, object: nil)
        let result = XCTWaiter.wait(for: [expected], timeout: 8)
        let snapshot = correctionFixtureObject(app, scope: scope)
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = "correction-\(phase)-AX"
        ax.lifetime = .keepAlways
        add(ax)
        let query = app.staticTexts.matching(identifier: "home_v2_correction_fixture_snapshot_\(scope)")
        let json = XCTAttachment(string: query.count == 1 ? query.element.label : "missing unique scoped snapshot")
        json.name = "correction-\(phase)-state"
        json.lifetime = .keepAlways
        add(json)
        capture(app, "correction-\(phase)")
        return try XCTUnwrap(result == .completed ? snapshot : nil,
                             "Actual nonce-bound mounted phase must complete; no helper/timeout substitute")
    }

    private func tapCorrectionControl(_ element: XCUIElement) throws {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isEnabled && element.isHittable
        }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 8)
        guard result == .completed else {
            XCTFail("Require the actual unique enabled hittable control before mutation")
            throw NSError(domain: "MountedCorrectionPrerequisite", code: 1)
        }
        element.tap()
    }

    private func assertCorrectionRootAndTransport(_ initial: [String: Any], equals current: [String: Any]) {
        let main = initial["mainTabIDs"] as? [String]
        let hud = initial["hudIDs"] as? [String]
        XCTAssertEqual(main?.count, 1)
        XCTAssertEqual(hud?.count, 1)
        XCTAssertEqual(current["mainTabIDs"] as? [String], main)
        XCTAssertEqual(current["hudIDs"] as? [String], hud)
        XCTAssertEqual(current["transportTasks"] as? Int, 0,
                       "Session-specific zero is evaluated only after actual same-producer unit calibration")
        XCTAssertEqual(current["healthAuthorized"] as? Bool, false)
        XCTAssertEqual(current["billingSDKConfigured"] as? Bool, false)
        XCTAssertTrue(current["commandError"] is NSNull)
    }

    /// Failure reporting only. Never called by a successful case or used as acceptance evidence.
    /// The original XCTest issue remains recorded even if this bounded cleanup is unavailable/times out.
    @MainActor
    private func cleanupFailedCorrectionFixture(_ app: XCUIApplication, nonce: UUID) {
        let originalFailureCount = testRun?.failureCount
        let scopes = ["editor", "context", "home", "app", "boot"]
        var commandSent = false
        var lastStatus: [String: Any]?
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard app.state == .runningForeground || app.state == .runningBackground else { return false }
            for scope in scopes {
                let suffix = "\(scope)_\(nonce.uuidString)"
                let statuses = app.staticTexts.matching(identifier: "home_v2_correction_failure_status_\(suffix)")
                guard statuses.count == 1, let data = statuses.element.label.data(using: .utf8),
                      let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      state["nonce"] as? String == nonce.uuidString,
                      state["failureOnly"] as? Bool == true, state["acceptance"] as? Bool == false else { continue }
                lastStatus = state
                if !commandSent {
                    let commands = app.buttons.matching(identifier: "home_v2_correction_failure_cleanup_\(suffix)")
                    if commands.count == 1, commands.element.isEnabled, commands.element.isHittable {
                        commands.element.tap()
                        commandSent = true
                    }
                }
                if state["requested"] as? Bool == true,
                   state["actualHeldTasksTerminal"] as? Bool == true,
                   state["pendingOwnedWork"] as? Bool == false,
                   state["heldCount"] as? Int == 0,
                   state["callbackObserved"] as? Bool == true,
                   state["ownedDefaultsDisposed"] as? Bool == true,
                   state["ownedDefaultsActuallyAbsent"] as? Bool == true,
                   state["transportInvalidations"] as? Int == 1,
                   state["cleanupError"] is NSNull {
                    return true
                }
            }
            return false
        }, object: nil)
        let result = XCTWaiter.wait(for: [finished], timeout: 8)
        let value: [String: Any] = [
            "nonce": nonce.uuidString, "failureCleanupOnly": true, "acceptance": false,
            "originalFailureCountBeforeCleanup": originalFailureCount as Any? ?? NSNull(),
            "originalFailureWasNotCleared": true, "completionTokenWasVerified": false,
            "commandSent": commandSent, "waiterResult": String(describing: result),
            "cleanupAvailable": lastStatus != nil, "actualStatus": lastStatus as Any? ?? NSNull()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let metadata = XCTAttachment(string: text)
            metadata.name = "correction-failed-case-owned-cleanup-metadata"
            metadata.lifetime = .keepAlways
            add(metadata)
        }
        if app.state == .runningForeground || app.state == .runningBackground {
            let ax = XCTAttachment(string: app.debugDescription)
            ax.name = "correction-failed-case-cleanup-AX"
            ax.lifetime = .keepAlways
            add(ax)
            capture(app, "correction-failed-case-cleanup")
        }
        // Before-graph failure is unavailable, not fabricated disposal or zero-provider evidence.
        // Crashes/harness termination cannot guarantee XCTest teardown; owning artifact review must say so.
    }

    private func finishCorrectionFixture(_ app: XCUIApplication, nonce: UUID, baseline: [String: Any]) throws {
        let home = try waitCorrectionFixture(app, scope: "home", nonce: nonce, phase: "cleanup-before-invalidate") {
            ($0["visibleContextIDs"] as? [String])?.isEmpty == true &&
                ($0["editors"] as? [[String: Any]])?.allSatisfy { $0["visible"] as? Bool == false } == true &&
                $0["pendingWork"] as? Bool == false
        }
        XCTAssertEqual(home["ownedDefaultsMarker"] as? String, nonce.uuidString)
        assertCorrectionRootAndTransport(baseline, equals: home)
        try tapCorrectionControl(app.buttons["home_v2_correction_fixture_finish"])
        let cleaned = try waitCorrectionFixture(app, scope: "home", nonce: nonce, phase: "actual-invalidation-owned-disposal") {
            $0["cleanupRequested"] as? Bool == true && $0["sessionInvalidated"] as? Bool == true &&
                $0["ownedDefaultsDisposed"] as? Bool == true && $0["ownedDefaultsMarker"] is NSNull
        }
        XCTAssertEqual(cleaned["transportInvalidations"] as? Int, 1)
        XCTAssertTrue(cleaned["invalidationError"] is NSNull)
        assertCorrectionRootAndTransport(baseline, equals: cleaned)
    }


    func testHorizontalPhotoDragPagesPixelsAndMetricsWithoutOpeningViewer() throws {
        let app = launch(withSteps: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        let steps = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Steps · ")).firstMatch
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        let firstCaption = caption.label, firstWeight = weight.label
        assertStepCount(6_000, in: app)
        let firstStepsLabel = steps.label
        XCTAssertTrue(firstCaption.hasPrefix(firstStepsLabel.replacingOccurrences(of: "Steps · ", with: "")))
        try assertPhotoColor(stage, red: true)
        drag(stage, from: 0.85, to: 0.3)
        let moved = expectation(for: NSPredicate(format: "label != %@", firstCaption), evaluatedWith: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        XCTAssertNotEqual(weight.label, firstWeight)
        XCTAssertNotEqual(steps.label, firstStepsLabel, "Steps must follow the selected day, not remain labeled Today")
        XCTAssertTrue(caption.label.hasPrefix(steps.label.replacingOccurrences(of: "Steps · ", with: "")))
        assertStepCount(8_000, in: app)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        try assertPhotoColor(stage, red: false)
        capture(app, "timeline-older-blue-photo")

        // Preserve the precise right-drag regression from the default-Home qualification.
        drag(stage, from: 0.3, to: 0.85)
        let returned = expectation(for: NSPredicate(format: "label == %@", firstCaption), evaluatedWith: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertEqual(weight.label, firstWeight)
        XCTAssertEqual(steps.label, firstStepsLabel)
        assertStepCount(6_000, in: app)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        try assertPhotoColor(stage, red: true)
        stage.tap()
        XCTAssertTrue(
            app.buttons["home_v2_viewer_close"].waitForExistence(timeout: 5), "An intentional tap still opens the photo"
        )
    }

    func testSelectedWeightOnlyDayNeverBorrowsTodaysBodyFat() throws {
        let launchedAt = Date()
        let app = launch(singlePhoto: true)
        defer { app.terminate() }
        let heroPicker = app.segmentedControls["home_v2_hero_metric_picker"]
        XCTAssertTrue(heroPicker.waitForExistence(timeout: 8))
        heroPicker.buttons["Body fat"].tap()
        XCTAssertTrue(heroPicker.buttons["Body fat"].isSelected)
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let historyLoaded = expectation(
            for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager
        )
        guard XCTWaiter.wait(for: [historyLoaded], timeout: 8) == .completed,
              Calendar.current.isDate(launchedAt, inSameDayAs: Date()),
              stage.label.contains("15.8") else {
            capture(app, "raw-history-Today-prerequisite")
            XCTFail("Require actual full fixture and Today body-fat positive before any raw absence")
            return
        }
        try assertPhotoIdentity(stage, expected: 0b101)
        let calendar = Calendar.current
        let selectedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -14, to: launchedAt))
        let fullDate = DateFormatter()
        fullDate.locale = .current
        fullDate.dateStyle = .medium
        fullDate.timeStyle = .none
        app.buttons["home_v2_context_button"].tap()
        guard requireRawContext(
            app, day: launchedAt, weight: "181.0 lb", source: "Typed", bodyFat: "15.8%"
        ) else { return }
        app.buttons["home_v2_context_close"].tap()
        guard stage.waitForExistence(timeout: 8) else {
            XCTFail("Today raw positive must return to the mounted Home"); return
        }
        for _ in 0..<2 {
            let previous = caption.label
            stage.swipeLeft()
            let changed = expectation(for: NSPredicate(format: "label != %@", previous), evaluatedWith: caption)
            guard XCTWaiter.wait(for: [changed], timeout: 5) == .completed else {
                capture(app, "raw-history-navigation-prerequisite")
                XCTFail("Historical selection must change the actual displayed date"); return
            }
        }
        let selectedCaption = caption.label
        capture(app, "timeline-selected-bracket-before-assertions")
        XCTAssertEqual(selectedCaption, fullDate.string(from: selectedDay))
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "183.9")
        let composition = app.buttons["home_v2_photo_stage"]
        guard composition.waitForExistence(timeout: 5), !composition.label.isEmpty else {
            XCTFail("Require the existing composition node before evaluating inferred presentation"); return
        }
        let inferred = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Body fat, 16.6 %. Inferred between recorded values"),
            evaluatedWith: composition
        )
        XCTAssertEqual(XCTWaiter.wait(for: [inferred], timeout: 5), .completed)
        XCTAssertFalse(composition.label.contains("15.8"), "Never substitute Today's observed body fat")
        XCTAssertEqual(app.staticTexts["home_v2_ffmi_value"].label, "22.1")
        XCTAssertEqual(app.staticTexts["home_v2_steps_value"].label, "—")
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        // The existing SinglePhotoFixture keeps only day0's real image; selected metrics stay day14.
        let actualPhoto = app.staticTexts["home_v2_actual_photo_date"]
        XCTAssertTrue(actualPhoto.waitForExistence(timeout: 5))
        XCTAssertEqual(actualPhoto.label, "Photo · " + fullDate.string(from: launchedAt))
        XCTAssertNotEqual(actualPhoto.label, "Photo · " + selectedCaption)
        try assertPhotoIdentity(stage, expected: 0b101)
        capture(app, "timeline-nearest-actual-photo-distinct-from-selected-moment")

        let menu = app.buttons["photo_timeline_root_menu"]
        guard menu.waitForExistence(timeout: 5), menu.isHittable else {
            XCTFail("The actual Home menu must remain mounted before raw Entries"); return
        }
        let progress = app.buttons["home_v2_view_progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        if !progress.isHittable { app.scrollViews["home_v2_content_scroll"].swipeUp() }
        XCTAssertTrue(progress.isHittable)
        progress.tap()
        let weightTab = app.buttons["home_v2_progress_tab_weight"]
        XCTAssertTrue(weightTab.waitForExistence(timeout: 8))
        weightTab.tap()
        XCTAssertTrue(weightTab.isSelected)
        let entriesAction = app.buttons["home_v2_metric_entries"]
        guard entriesAction.waitForExistence(timeout: 5), entriesAction.isHittable else {
            capture(app, "raw-entries-menu-prerequisite")
            XCTFail("The actual source-defined Entries action must exist"); return
        }
        entriesAction.tap()
        capture(app, "raw-entries-before-row-query")
        let header = app.staticTexts["home_v2_entries"]
        guard header.waitForExistence(timeout: 8), header.label == "Entries" else {
            XCTFail("The real Entries header must be mounted before querying any raw row"); return
        }
        let weekdayDay = DateFormatter()
        weekdayDay.setLocalizedDateFormatFromTemplate("EEE d")
        let expectedRow = weekdayDay.string(from: selectedDay) + ", 183.9 lb, Apple Health"
        let rawRows = app.buttons.matching(identifier: "home_v2_entries_row").matching(
            NSPredicate(format: "label == %@", expectedRow)
        )
        let exactRow = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in rawRows.count == 1 }, object: nil)
        let rowResult = XCTWaiter.wait(for: [exactRow], timeout: 5)
        let rawAX = XCTAttachment(string: app.debugDescription)
        rawAX.name = "raw-entries-owning-AX-before-exact-row-assert"
        rawAX.lifetime = .keepAlways
        add(rawAX)
        guard rowResult == .completed, rawRows.count == 1, rawRows.element.isHittable else {
            XCTFail("Require one exact dated183.9lb AppleHealth raw row; ambiguity/missing is a prerequisite failure")
            return
        }
        rawRows.element.tap()
        guard requireRawContext(
            app, day: selectedDay, weight: "183.9 lb", source: "Apple Health", bodyFat: nil
        ) else { return }
        app.buttons["home_v2_context_close"].tap()
        let entriesBack = app.buttons["home_v2_entries_back"]
        guard entriesBack.waitForExistence(timeout: 8), entriesBack.isHittable else {
            XCTFail("Raw Context must return through the actual Entries route"); return
        }
        entriesBack.tap()
        XCTAssertTrue(app.buttons["home_v2_progress_tab_weight"].waitForExistence(timeout: 8))
        menu.tap()
        let todayAction = app.buttons["home_v2_sidebar_today"]
        XCTAssertTrue(todayAction.waitForExistence(timeout: 5))
        todayAction.tap()
        guard stage.waitForExistence(timeout: 8) else { XCTFail("Raw readback must return Home"); return }
        heroPicker.buttons["Body fat"].tap()
        XCTAssertTrue(heroPicker.buttons["Body fat"].isSelected)
        XCTAssertEqual(caption.label, selectedCaption)
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, "183.9")
        XCTAssertTrue(stage.label.contains("Body fat, 16.6 %. Inferred between recorded values"))
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        capture(app, "timeline-raw-readback-preserves-inferred-presentation-without-persisting-it")
    }

    func testVerticalRulerDragDoesNotSelectOrNavigateAndHorizontalScrubStillWorks() {
        let app = launch(largestText: true)
        let ruler = app.descendants(matching: .any)["home_v2_timeline_scrubber"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 8))
        let originalDate = ruler.value as? String
        let start = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -110)))
        XCTAssertEqual(ruler.value as? String, originalDate)
        XCTAssertTrue(app.buttons["home_v2_log_weight"].isHittable)
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        let end = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.7))
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.7)).press(forDuration: 0.05, thenDragTo: end)
        let changed = expectation(for: NSPredicate(format: "value != %@", originalDate ?? ""), evaluatedWith: ruler)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["home_v2_log_weight"].frame))
        capture(app, "timeline-ruler-largest-text")
    }

    func testBodyFatCheckInUpdatesSelectedHistoricalPhotoWithoutChangingWeight() throws {
        let app = launch()
        let heroPicker = app.segmentedControls["home_v2_hero_metric_picker"]
        XCTAssertTrue(heroPicker.waitForExistence(timeout: 8))
        heroPicker.buttons["Body fat"].tap()
        XCTAssertTrue(heroPicker.buttons["Body fat"].isSelected)
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let today = caption.label
        drag(stage, from: 0.85, to: 0.3)
        let moved = expectation(for: NSPredicate(format: "label != %@", today), evaluatedWith: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        let ruler = app.descendants(matching: .any)["home_v2_timeline_scrubber"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        let selectedDate = try XCTUnwrap(ruler.value as? String)
        try assertPhotoColor(stage, red: false)
        let weight = app.staticTexts["home_v2_weight_value"].label
        let oldFFMI = app.staticTexts["home_v2_ffmi_value"].label
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(app.staticTexts["home_v2_log_sheet"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons["Body Fat"].isSelected)
        let field = app.textFields["Body fat percentage value"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "16.2", "The sheet must use the selected older check-in")
        let method = app.descendants(matching: .any).matching(identifier: "home_v2_body_fat_method").firstMatch
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        XCTAssertEqual(method.value as? String, "Method not specified", "Apple Health alone does not identify a method")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "16.0")
        let save = app.buttons["home_v2_log_sheet_save"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        save.tap()
        let updated = expectation(for: NSPredicate(format: "label CONTAINS %@", "16.0"), evaluatedWith: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
        XCTAssertEqual(ruler.value as? String, selectedDate, "Saving body fat must retain the selected historical day")
        try assertPhotoColor(stage, red: false)
        XCTAssertEqual(app.staticTexts["home_v2_weight_value"].label, weight)
        XCTAssertNotEqual(app.staticTexts["home_v2_ffmi_value"].label, oldFFMI)
        XCTAssertTrue(heroPicker.buttons["Body fat"].isSelected)
        XCTAssertFalse(stage.label.contains("From Apple Health"), "Providers remain in selected entry details")
        let details = app.buttons["home_v2_today_details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        if !details.isHittable { app.scrollViews["home_v2_content_scroll"].swipeUp() }
        XCTAssertTrue(details.isHittable)
        details.tap()
        let rawWeight = app.descendants(matching: .any)["home_v2_context_row_weight"]
        let rawFat = app.descendants(matching: .any)["home_v2_context_row_body_fat"]
        XCTAssertTrue(rawWeight.waitForExistence(timeout: 8))
        XCTAssertTrue(rawFat.waitForExistence(timeout: 5))
        XCTAssertTrue(rawWeight.label.contains("Apple Health"))
        XCTAssertTrue(rawFat.label.contains("16.0"))
        XCTAssertTrue(rawFat.label.contains("Apple Health"), "Original field provenance must survive the edit")
        XCTAssertFalse(rawFat.label.contains("Visual estimate"))
        capture(app, "timeline-edited-field-actual-source-details")
        app.buttons["home_v2_context_close"].tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 8))
        XCTAssertEqual(ruler.value as? String, selectedDate)
        XCTAssertFalse(app.buttons["home_v2_undo"].exists)
        XCTAssertFalse(app.buttons["home_v2_done"].exists)
        XCTAssertFalse(app.staticTexts["home_v2_logged_sentence"].exists)
        capture(app, "timeline-body-fat-save-selected-photo")
        app.buttons["home_v2_log_weight"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, "16.0")
        XCTAssertEqual(method.value as? String, "Method not specified")
        capture(app, "timeline-body-fat-method-after-save")
    }

    func testSelectedDayStepsAtLargestTextFollowThePhotoAndRemainReachable() throws {
        let app = launch(largestText: true, withSteps: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let historyLoaded = expectation(for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [historyLoaded], timeout: 8), .completed)
        let firstCaption = caption.label
        let initialCardY = stage.frame.minY
        for (index, count) in [6_000, 8_000, 6_000].enumerated() {
            if index > 0 {
                revealTimelineCard(stage, initialY: initialCardY, in: app)
                let previous = caption.label
                if index == 1 { stage.swipeLeft() } else { stage.swipeRight() }
                let moved = expectation(for: NSPredicate(format: "label != %@", previous), evaluatedWith: caption)
                XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
            }
            assertStepCount(count, in: app)
            let stepsDate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Steps · ")).firstMatch
            XCTAssertTrue(caption.label.hasPrefix(stepsDate.label.replacingOccurrences(of: "Steps · ", with: "")))
            try assertPhotoColor(stage, red: index != 1)
            capture(app, "timeline-steps-ax5-photo-\(index)")
            let summary = app.otherElements["home_v2_steps_summary"].buttons.firstMatch
            revealTimelineSteps(summary, in: app)
            let value = app.staticTexts["home_v2_steps_value"]
            let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            let font = UIFontMetrics(forTextStyle: .title2).scaledFont(
                for: .systemFont(ofSize: 28, weight: .semibold), compatibleWith: traits
            )
            XCTAssertLessThan(value.frame.height, font.lineHeight * 1.5,
                              "The step total must remain one readable line, not split its final digit")
            XCTAssertLessThanOrEqual(stepsDate.frame.maxY, value.frame.minY,
                                     "At accessibility sizes the complete dated heading must precede the total")
            XCTAssertTrue(timelineViewport(in: app).contains(stepsDate.frame))
            XCTAssertTrue(timelineViewport(in: app).contains(value.frame))
            capture(app, "timeline-steps-ax5-value-\(index)")
            XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
        }
        XCTAssertEqual(caption.label, firstCaption)
    }

    private func revealTimelineCard(_ stage: XCUIElement, initialY: CGFloat, in app: XCUIApplication) {
        let scroll = app.scrollViews["home_v2_content_scroll"]
        let viewport = timelineViewport(in: app)
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let top = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + 30))
        let bottom = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 30))
        XCTAssertTrue(scroll.exists)
        for _ in 0..<6 where stage.frame.minY < initialY - 1 {
            top.press(forDuration: 0.05, thenDragTo: bottom)
        }
        XCTAssertEqual(stage.frame.minY, initialY, accuracy: 1)
    }

    private func revealTimelineSteps(_ target: XCUIElement, in app: XCUIApplication) {
        let viewport = timelineViewport(in: app)
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let top = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + 30))
        let bottom = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 30))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        for _ in 0..<6 where !target.isHittable || !viewport.contains(target.frame) {
            if target.frame.minY < viewport.minY {
                top.press(forDuration: 0.05, thenDragTo: bottom)
            } else {
                bottom.press(forDuration: 0.05, thenDragTo: top)
            }
        }
        XCTAssertTrue(target.isHittable)
        XCTAssertTrue(viewport.contains(target.frame), "Selected-day steps must fit above the pinned controls")
    }

    private func timelineViewport(in app: XCUIApplication) -> CGRect {
        let scroll = app.scrollViews["home_v2_content_scroll"]
        let ruler = app.descendants(matching: .any)["home_v2_timeline_scrubber"]
        XCTAssertTrue(scroll.exists)
        XCTAssertTrue(ruler.exists)
        let viewport = CGRect(x: scroll.frame.minX, y: scroll.frame.minY, width: scroll.frame.width,
                              height: max(0, min(scroll.frame.maxY, ruler.frame.minY) - scroll.frame.minY))
        XCTAssertGreaterThan(viewport.height, 88, "Home must leave a usable scrolling viewport")
        return viewport
    }

    func testDiagnosticMountedCurrentPhotoCodeRejectsHistoricalIdentity() throws {
        let app = launch(calibrationVariant: "0")
        defer { app.terminate() }
        let stage = app.buttons["home_v2_photo_stage"]
        capturePhotoDiagnostic(app, stage: stage, name: "calibration-current-initial", requested: "0")
        try assertPhotoColor(stage, red: true)
        capturePhotoDiagnostic(app, stage: stage, name: "calibration-current-ready", requested: "0")
        XCTAssertEqual(LuminanceFixtureIdentity.code(image: try XCTUnwrap(stage.screenshot().image.cgImage)), 0b101)
        XCTAssertNotEqual(LuminanceFixtureIdentity.code(image: try XCTUnwrap(stage.screenshot().image.cgImage)), 0b011)
    }

    func testDiagnosticMountedHistoricalPhotoCodeRejectsCurrentIdentity() throws {
        let app = launch(calibrationVariant: "7")
        defer { app.terminate() }
        let stage = app.buttons["home_v2_photo_stage"]
        capturePhotoDiagnostic(app, stage: stage, name: "calibration-historical-initial", requested: "7")
        try assertPhotoColor(stage, red: false)
        capturePhotoDiagnostic(app, stage: stage, name: "calibration-historical-ready", requested: "7")
        XCTAssertEqual(LuminanceFixtureIdentity.code(image: try XCTUnwrap(stage.screenshot().image.cgImage)), 0b011)
        XCTAssertNotEqual(LuminanceFixtureIdentity.code(image: try XCTUnwrap(stage.screenshot().image.cgImage)), 0b101)
    }

    func testDiagnosticMountedDefaultGrayAndBlankRejectPhotoIdentity() throws {
        for variant in ["gray", "blank"] {
            let app = launch(calibrationVariant: variant)
            let stage = app.buttons["home_v2_photo_stage"]
            capturePhotoDiagnostic(app, stage: stage, name: "calibration-\(variant)-initial", requested: variant)
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let image = stage.screenshot().image.cgImage else { return false }
                return variant == "gray" ? LuminanceFixtureIdentity.isDefaultGrayPlate(image) :
                    LuminanceFixtureIdentity.isBlankPlate(image)
            }, object: nil)
            let result = XCTWaiter.wait(for: [loaded], timeout: 8)
            capturePhotoDiagnostic(app, stage: stage, name: "calibration-\(variant)-ready", requested: variant)
            XCTAssertEqual(result, .completed, "Require the actual negative image, not a loading placeholder")
            let image = try XCTUnwrap(stage.screenshot().image.cgImage)
            XCTAssertNil(LuminanceFixtureIdentity.code(image: image))
            app.terminate()
        }
    }

    private func capturePhotoDiagnostic(_ app: XCUIApplication, stage: XCUIElement,
                                        name: String, requested: String) {
        capture(app, name)
        let screenshot = stage.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name + "-owning-stage"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = screenshot.image.cgImage
        let diagnostic: [String: Any] = [
            "requestedVariant": requested,
            "stageFrame": NSCoder.string(for: stage.frame),
            "caption": app.staticTexts["home_v2_photo_caption"].label,
            "weight": app.staticTexts["home_v2_weight_value"].label,
            "luminanceSignature": image.flatMap(LuminanceFixtureIdentity.signature) as Any? ?? NSNull(),
            "decodedCode": image.flatMap(LuminanceFixtureIdentity.code) as Any? ?? NSNull(),
            "isDefaultGrayPlate": image.map(LuminanceFixtureIdentity.isDefaultGrayPlate) ?? false,
            "isBlankPlate": image.map(LuminanceFixtureIdentity.isBlankPlate) ?? false,
            "phase": "Actual owning image must determine loading versus ready; no unconditional phase claim",
            "ownership": "Image code identifies a fixture day only; separate account/generation evidence is required"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys])) ?? Data()
        let text = XCTAttachment(string: String(bytes: data, encoding: .utf8) ?? "")
        text.name = name + "-luminance-and-frame"
        text.lifetime = .keepAlways
        add(text)
    }

    // Test-only current-main contract witness. All navigation and actual-photo controls precede intended RED.
    func testSelectedMomentInfersBracketedBodyFatWithProvenance() throws {
        let launchDate = Date()
        let app = launch()
        defer { app.terminate() }
        let heroPicker = app.segmentedControls["home_v2_hero_metric_picker"]
        XCTAssertTrue(heroPicker.waitForExistence(timeout: 8))
        heroPicker.buttons["Body fat"].tap()
        XCTAssertTrue(heroPicker.buttons["Body fat"].isSelected)
        let stage = app.buttons["home_v2_photo_stage"]
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let ready = expectation(for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager)
        let readyResult = XCTWaiter.wait(for: [ready], timeout: 8)
        capturePhotoDiagnostic(app, stage: stage, name: "bracket-before-navigation", requested: "0")
        guard readyResult == .completed, Calendar.current.isDate(launchDate, inSameDayAs: Date()),
              stage.label.contains("15.8"), weight.label == "181.0" else {
            XCTFail("Bracket prerequisite failed: actual history, same calendar day, Today body fat and exact weight required")
            return
        }
        try assertPhotoIdentity(stage, expected: 0b101)
        for index in 0..<2 {
            let before = caption.label
            drag(stage, from: 0.85, to: 0.3)
            let moved = expectation(for: NSPredicate(format: "label != %@", before), evaluatedWith: caption)
            let result = XCTWaiter.wait(for: [moved], timeout: 5)
            capture(app, "bracket-navigation-\(index)")
            guard result == .completed else {
                XCTFail("Bracket prerequisite failed: intentional historical navigation did not change the selected date")
                return
            }
        }
        let calendar = Calendar.current
        let selected = try XCTUnwrap(calendar.date(byAdding: .day, value: -14, to: launchDate))
        let older = try XCTUnwrap(calendar.date(byAdding: .day, value: -21, to: launchDate))
        let newer = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: launchDate))
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let selectedDate = formatter.string(from: selected)
        let beforeInferenceCaption = caption.label
        capturePhotoDiagnostic(app, stage: stage, name: "bracket-selected-before-inference-assert", requested: "14")
        guard beforeInferenceCaption.contains(selectedDate), weight.label == "183.9" else {
            XCTFail("Bracket prerequisite failed: require full selected date and the exact83.4kg/183.9lb source weight")
            return
        }
        try assertPhotoIdentity(stage, expected: 0b110)
        XCTAssertEqual(stage.frame.width / stage.frame.height, 4.0 / 5.0, accuracy: 0.02)
        // Constants come from the existing fixture, never the app's presentation resolver.
        let expectedBodyFat = 16.9 + (16.2 - 16.9) *
            selected.timeIntervalSince(older) / newer.timeIntervalSince(older)
        XCTAssertEqual(expectedBodyFat, 16.55, accuracy: 0.0001)
        // Decimal fixture16.90/16.20 has exact midpoint16.55; the expected display uses explicit decimal half-up.
        // Floating-point interpolation is compared with tolerance, never formatted to derive its own oracle.
        let rounding = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 1,
            raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        let expectedBodyFatDisplay = NSDecimalNumber(string: "16.55").rounding(accordingToBehavior: rounding).stringValue
        XCTAssertEqual(expectedBodyFatDisplay, "16.6")
        let heightMeters = 178.0 / 100
        let expectedFFMI = 83.4 * (1 - expectedBodyFat / 100) / pow(heightMeters, 2) +
            6.1 * (1.8 - heightMeters)
        XCTAssertEqual(expectedFFMI, 22.088071203131, accuracy: 0.000001)
        XCTAssertEqual(String(format: "%.1f", expectedFFMI), "22.1")
        let constants = XCTAttachment(string:
            "selected=\(selectedDate);older=\(formatter.string(from: older)),16.90%,DEXA;" +
            "newer=\(formatter.string(from: newer)),16.20%,Apple Health;" +
            "weight=83.4kg;display=183.9lb;height=178cm;inferredBF=16.55%;normalizedDerivedFFMI=22.1")
        constants.name = "bracket-independent-fixture-expectations"
        constants.lifetime = .keepAlways
        add(constants)
        let sentence = app.buttons["home_v2_photo_stage"]
        let mounted = sentence.waitForExistence(timeout: 5)
        let mountedLabel = mounted ? sentence.label : "<composition node absent>"
        capture(app, "bracket-existing-composition-prerequisite")
        let compositionAX = XCTAttachment(string: mounted ? sentence.debugDescription : app.debugDescription)
        compositionAX.name = "bracket-existing-composition-owning-AX"
        compositionAX.lifetime = .keepAlways
        add(compositionAX)
        let compositionLabel = XCTAttachment(string: mountedLabel)
        compositionLabel.name = "bracket-existing-composition-label"
        compositionLabel.lifetime = .keepAlways
        add(compositionLabel)
        guard mounted, !mountedLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            XCTFail("Bracket prerequisite failed: existing composition node must be mounted with a nonempty label")
            return
        }
        let inferred = expectation(for: NSPredicate(format: "label CONTAINS %@", "Inferred between recorded values"),
                                   evaluatedWith: sentence)
        let inferenceResult = XCTWaiter.wait(for: [inferred], timeout: 5)
        capture(app, "bracket-intended-contract-result")
        switch inferenceResult {
        case .completed: break
        case .timedOut:
            XCTFail("INTENDED_CONTRACT_RED timedOut: selected14-day moment needs bracketed inferred body fat")
            return
        default:
            XCTFail("Non-contract waiter failure: \(inferenceResult); not accepted as intended RED")
            return
        }
        XCTAssertTrue(
            sentence.label.contains(expectedBodyFatDisplay),
            "Inferred percentage must use independent elapsed-time anchors"
        )
        XCTAssertEqual(caption.label, beforeInferenceCaption)
        XCTAssertEqual(weight.label, "183.9", "An exact measured weight takes precedence over interpolation")
        XCTAssertEqual(app.staticTexts["home_v2_ffmi_value"].label, "22.1", "FFMI is derived, never measured")
        capture(app, "bracket-parent-moment-before-AX-assert")
        let momentQuery = app.otherElements.matching(identifier: "home_v2_selected_moment")
        guard momentQuery.count == 1 else {
            XCTFail("Parent moment prerequisite failed: expected one containing Home AX node")
            return
        }
        let parent = momentQuery.element
        let parentAX = XCTAttachment(string: parent.debugDescription)
        parentAX.name = "bracket-selected-parent-owning-AX"
        parentAX.lifetime = .keepAlways
        add(parentAX)
        let momentValue = try XCTUnwrap(parent.value as? String)
        XCTAssertTrue(momentValue.contains(selected.formatted(date: .complete, time: .omitted)))
        XCTAssertTrue(heroPicker.buttons["Body fat"].isSelected)
        XCTAssertTrue(momentValue.contains("Body fat, 16.6 %"))
        XCTAssertTrue(momentValue.contains("Inferred between recorded values"))
        // Supporting values remain children of this same selected moment;
        // full anchor/source/height evidence is asserted in the detail sheet below.
        XCTAssertEqual(parent.staticTexts["home_v2_weight_value"].label, "183.9")
        XCTAssertEqual(parent.staticTexts["home_v2_ffmi_value"].label, "22.1")
        let actualPhoto = app.staticTexts["home_v2_actual_photo_date"]
        XCTAssertTrue(actualPhoto.waitForExistence(timeout: 5))
        XCTAssertEqual(actualPhoto.label, "Photo · " + selectedDate, "Normal fixture photo is captured at the selected moment")
        app.buttons["home_v2_hero_reading_detail"].tap()
        let detail = app.descendants(matching: .any)["home_v2_provenance_detail"]
        let opened = detail.waitForExistence(timeout: 8)
        capture(app, "bracket-anchor-provenance")
        XCTAssertTrue(opened)
        for token in [formatter.string(from: older), formatter.string(from: newer),
                      "16.90 %", "16.20 %", "From your DEXA scan", "From Apple Health", "178.00 cm profile height"] {
            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", token)).firstMatch.exists,
                "Accessible inference provenance must include actual anchor dates, values, " +
                    "sources and derivation inputs"
            )
        }
        app.buttons["home_v2_provenance_done"].tap()
        XCTAssertFalse(app.buttons["home_v2_viewer_close"].exists)
    }

    private func requireRawContext(
        _ app: XCUIApplication, day: Date, weight: String, source: String, bodyFat: String?
    ) -> Bool {
        capture(app, "raw-context-before-prerequisite-query")
        let header = app.staticTexts["home_v2_context"]
        let dayNumber = Calendar.current.component(.day, from: day)
        let selectedDay = app.buttons["home_v2_context_day_\(dayNumber)"]
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        let weights = app.descendants(matching: .any).matching(identifier: "home_v2_context_row_weight")
        let fats = app.descendants(matching: .any).matching(identifier: "home_v2_context_row_body_fat")
        guard header.waitForExistence(timeout: 8), selectedDay.exists, selectedDay.isSelected,
              selectedDay.label == formatter.string(from: day),
              weights.count == 1, !weights.element.label.isEmpty,
              weights.element.label.contains(weight), weights.element.label.contains(source) else {
            let ax = XCTAttachment(string: app.debugDescription)
            ax.name = "raw-context-prerequisite-owning-AX"
            ax.lifetime = .keepAlways
            add(ax)
            XCTFail("Require mounted raw Context, actual selected date and exact stored weight/source before BF absence")
            return false
        }
        if let bodyFat {
            guard fats.count == 1, fats.element.label.contains(bodyFat) else {
                XCTFail("Raw Today body-fat positive must exist before any missing-body-fat assertion")
                return false
            }
        } else {
            guard fats.allElementsBoundByIndex.isEmpty else {
                XCTFail("Selected raw weight-only record must still have no persisted body-fat row")
                return false
            }
        }
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = bodyFat == nil ? "raw-context-weight-only-owning-AX" : "raw-context-Today-BF-positive-owning-AX"
        ax.lifetime = .keepAlways
        add(ax)
        capture(app, bodyFat == nil ? "raw-context-weight-only-nonpersistence" : "raw-context-Today-BF-positive")
        return true
    }

    func testHistoricalWeightOnlyDayInEntriesNeverBorrowsTodaysBodyFat() {
        let app = launch()
        let progress = app.buttons["home_v2_view_progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        progress.tap()
        let weightTab = app.buttons["home_v2_progress_tab_weight"]
        XCTAssertTrue(weightTab.waitForExistence(timeout: 8))
        weightTab.tap()
        XCTAssertTrue(weightTab.isSelected)
        let entriesAction = app.buttons["home_v2_metric_entries"]
        XCTAssertTrue(entriesAction.waitForExistence(timeout: 8))
        entriesAction.tap()
        XCTAssertTrue(app.staticTexts["home_v2_entries"].waitForExistence(timeout: 8))
        let rows = app.buttons.matching(identifier: "home_v2_entries_row")
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in rows.count == 5 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed)
        XCTAssertGreaterThan(rows.count, 2)
        XCTAssertTrue(rows.element(boundBy: 2).label.contains("183.9"), "Exact frozen day14 raw weight")
        rows.element(boundBy: 2).tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_context_row_weight"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["home_v2_context_row_body_fat"].exists)
        capture(app, "entries-selected-missing-body-fat")
    }

    private func launch(largestText: Bool = false, withSteps: Bool = false,
                        calibrationVariant: String? = nil, singlePhoto: Bool = false,
                        correctionNonce: UUID? = nil,
                        correctionCompletion: CorrectionFixtureCompletion? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2PhotoFixture",
            "-lybUITestHomeV2TimelineFixture", "-lybUITestHomeV2OfflineFixture", "-lybUITestSuppressWhatsNew"
        ]
        if withSteps { app.launchArguments.append("-lybUITestHomeV2StepsFixture") }
        if singlePhoto { app.launchArguments.append("-lybUITestHomeV2SinglePhotoFixture") }
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if let correctionNonce {
            guard let correctionCompletion else {
                XCTFail("Nonce fixture requires its explicit before-launch teardown completion token")
                return app
            }
            // Registered BEFORE launch, including prerequisite failure and continueAfterFailure=false paths.
            addTeardownBlock { @MainActor in
                defer { app.terminate() }
                if !correctionCompletion.isVerified {
                    self.cleanupFailedCorrectionFixture(app, nonce: correctionNonce)
                }
            }
            app.launchArguments += ["-lybUITestHomeV2CorrectionIsolationFixture", "-lybUITestDisableBiometricLock"]
            app.launchEnvironment["LYB_UI_TEST_CORRECTION_NONCE"] = correctionNonce.uuidString
            for key in ["XCTestConfigurationFilePath", "XCTestSessionIdentifier", "XCTestBundlePath"] {
                if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                    app.launchEnvironment[key] = value
                }
            }
        }
        if let calibrationVariant {
            XCTAssertNotNil(UUID(uuidString: ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] ?? ""))
            XCTAssertTrue(ProcessInfo.processInfo.environment["XCTestBundlePath"]?.hasSuffix(
                "/LogYourBodyUITests.xctest"
            ) == true)
            for key in ["XCTestConfigurationFilePath", "XCTestSessionIdentifier", "XCTestBundlePath"] {
                if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                    app.launchEnvironment[key] = value
                }
            }
            app.launchArguments += ["-lybUITestDisableBiometricLock",
                                    "-lybUITestHomeV2TimelinePhotoCalibration", calibrationVariant]
        }
        app.launch()
        XCTAssertTrue(app.buttons["home_v2_photo_stage"].waitForExistence(timeout: 30))
        return app
    }

    private func assertStepCount(_ expected: Int, in app: XCUIApplication) {
        let value = app.staticTexts["home_v2_steps_value"]
        let loaded = expectation(
            for: NSPredicate(format: "label == %@", expected.formatted()), evaluatedWith: value
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed,
                       "Steps must be read from the selected fixture owner's actual daily row")
    }

    private func drag(_ stage: XCUIElement, from: CGFloat, to: CGFloat) {
        // The photo moves during paging; keep both endpoints in the fixed window.
        let frame = stage.frame
        let origin = XCUIApplication().windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.minX + frame.width * from, dy: frame.midY))
        let end = origin.withOffset(CGVector(dx: frame.minX + frame.width * to, dy: frame.midY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    private func assertPhotoColor(_ stage: XCUIElement, red: Bool) throws {
        try assertPhotoIdentity(stage, expected: red ? 0b101 : 0b011)
        // Supplemental hue/luminance below the frozen first80/500px barcode;
        // all frozen identity/negative-control floors remain unchanged.
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard stage.exists, !stage.frame.isEmpty,
                  let image = stage.screenshot().image.cgImage,
                  let corner = image.cropping(to: CGRect(
                    x: CGFloat(image.width) / 10, y: CGFloat(image.height) * 0.35, width: 4, height: 4
                  )) else {
                return false
            }
            var pixel = [UInt8](repeating: 0, count: 4)
            return pixel.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(
                    data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                let redChannel = Int(bytes[0]), blueChannel = Int(bytes[2])
                let brightness = (redChannel + Int(bytes[1]) + blueChannel) / 3
                // The production subject plate desaturates and dims backgrounds.
                // Both hue and luminance must identify the actual selected fixture.
                return red
                    ? redChannel > blueChannel + 2 && brightness > 50
                    : blueChannel > redChannel + 2 && brightness < 50
            }
        }, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [loaded], timeout: 8), .completed, "Actual selected image pixels must match the fixture"
        )
    }

    private func assertPhotoIdentity(_ stage: XCUIElement, expected: Int) throws {
        let codes = [0b101, 0b011, 0b110, 0b100, 0b001]
        for code in codes {
            let signature = [2, 1, 0].map { (code & (1 << $0)) == 0 ? 0.02 : 0.28 }
            XCTAssertEqual(LuminanceFixtureIdentity.code(luminances: signature), code)
            if code != expected {
                XCTAssertNotEqual(LuminanceFixtureIdentity.code(luminances: signature), expected,
                                  "Every independently prescribed wrong-photo code must be rejected")
            }
        }
        XCTAssertNil(LuminanceFixtureIdentity.code(luminances: [0.2, 0.2, 0.2]), "Gray is not photo identity")
        XCTAssertNil(LuminanceFixtureIdentity.code(luminances: [0, 0, 0]), "Blank is not photo identity")
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = stage.screenshot().image.cgImage else { return false }
            return LuminanceFixtureIdentity.code(image: image) == expected
        }, object: nil)
        let result = XCTWaiter.wait(for: [loaded], timeout: 8)
        let evidence = XCTAttachment(screenshot: stage.screenshot())
        evidence.name = "fixture-luminance-identity-before-assert-\(expected)"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertEqual(result, .completed, "Actual rendered pixels must match the prescribed photo identity")
        let image = try XCTUnwrap(stage.screenshot().image.cgImage)
        XCTAssertEqual(LuminanceFixtureIdentity.code(image: image), expected)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// ARTIFACT ONLY — native renderer/mounted-crop calibration remains UNRUN.
// Independent prescribed fixture codes: day0=101,7=011,14=110,21=100,35=001.
private enum LuminanceFixtureIdentity {
    static func code(luminances: [Double]) -> Int? {
        guard luminances.count == 3, luminances.allSatisfy({ $0.isFinite }),
              let low = luminances.min(), let high = luminances.max(), high - low >= 0.12 else { return nil }
        var code = 0
        for value in luminances {
            let normalized = (value - low) / (high - low)
            guard normalized <= 0.25 || normalized >= 0.75 else { return nil }
            code = (code << 1) | (normalized >= 0.75 ? 1 : 0)
        }
        return code
    }

    static func code(image: CGImage) -> Int? {
        signature(image: image).flatMap { code(luminances: $0) }
    }

    static func signature(image: CGImage) -> [Double]? {
        var luminances: [Double] = []
        // Centers of the three 90x80 DEBUG fixture bands, above the person and stats.
        for x in [45.0 / 400.0, 200.0 / 400.0, 355.0 / 400.0] {
            let rect = CGRect(x: CGFloat(image.width) * x - 2,
                              y: CGFloat(image.height) * (40.0 / 500.0) - 2,
                              width: 4, height: 4)
            guard let region = image.cropping(to: rect) else { return nil }
            var rgba = [UInt8](repeating: 0, count: 4)
            let valid = rgba.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(
                    data: bytes.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(region, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            guard valid else { return nil }
            luminances.append((0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) +
                               0.0722 * Double(rgba[2])) / 255.0)
        }
        return luminances
    }

    private static func luminance(_ image: CGImage, x: Double, y: Double) -> Double? {
        let rect = CGRect(x: CGFloat(image.width) * CGFloat(x) - 2,
                          y: CGFloat(image.height) * CGFloat(y) - 2, width: 4, height: 4)
        guard let region = image.cropping(to: rect) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let valid = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(region, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard valid else { return nil }
        return (0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) + 0.0722 * Double(rgba[2])) / 255
    }

    static func isDefaultGrayPlate(_ image: CGImage) -> Bool {
        guard let signature = signature(image: image), let low = signature.min(), let high = signature.max(),
              let center = luminance(image, x: 0.5, y: 0.5) else { return false }
        // Actual gray fixture has a darker person; the BF loading fallback has bright center text.
        return high - low < 0.04 && low > 0.06 && low - center > 0.04
    }

    static func isBlankPlate(_ image: CGImage) -> Bool {
        let grid = [0.1, 0.3, 0.5, 0.7].flatMap { y in [0.1, 0.5, 0.9].map { (x: $0, y: y) } }
        let samples = grid.compactMap { luminance(image, x: $0.x, y: $0.y) }
        return samples.count == grid.count && samples.allSatisfy { $0 < 0.02 }
    }
}


// Test-owned cross-callback token; no process-global state or production completion flag.
private final class CorrectionFixtureCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var verified = false

    var isVerified: Bool {
        lock.lock()
        defer { lock.unlock() }
        return verified
    }

    func markVerified() {
        lock.lock()
        verified = true
        lock.unlock()
    }
}


// Additional known-beta selector purposes retained alongside exact frozen coverage.
extension HomeV2TimelineIntegrationUITests {
    func testPhotoHoldScrubsBothDirectionsThenAnotherHoldRestoresTap() {
        let app = launchHoldScrubFixture(withSteps: true, holdScrub: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let loaded = expectation(for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed)
        let caption = app.staticTexts["home_v2_photo_caption"]
        let weight = app.staticTexts["home_v2_weight_value"]
        let date = caption.label, initialWeight = weight.label
        assertStepCount(6_000, in: app)
        let mode = app.staticTexts["home_v2_photo_scrub_mode"]
        stage.press(forDuration: 0.7)
        XCTAssertFalse(mode.exists, "A short hold must not activate scrubbing")
        // A short hold may be a normal photo tap. Return if the viewer opened.
        let close = app.buttons["home_v2_viewer_close"]
        if close.exists { close.tap() }
        let start = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 1.3, thenDragTo: start.withOffset(CGVector(dx: -stage.frame.width * 0.75, dy: 0)))
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertNotEqual(caption.label, date)
        XCTAssertNotEqual(weight.label, initialWeight)
        let stepsDate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Steps · ")).firstMatch
        XCTAssertTrue(caption.label.hasPrefix(stepsDate.label.replacingOccurrences(of: "Steps · ", with: "")))
        XCTAssertFalse(close.exists, "Holding and scrubbing must not open the photo viewer")
        let surface = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        surface.press(forDuration: 0.05, thenDragTo: surface.withOffset(CGVector(dx: pager.frame.width * 0.85, dy: 0)))
        XCTAssertEqual(caption.label, date)
        XCTAssertEqual(weight.label, initialWeight)
        assertStepCount(6_000, in: app)
        stage.press(forDuration: 1.3)
        XCTAssertFalse(mode.exists)
        stage.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testPhotoScrubResetsWhenNavigatingToTheMenuAndBack() {
        let app = launchHoldScrubFixture(holdScrub: true)
        let stage = app.buttons["home_v2_photo_stage"]
        let pager = app.descendants(matching: .any)["home_v2_timeline_pager"]
        let loaded = expectation(for: NSPredicate(format: "value == %@", "Entry 5 of 5"), evaluatedWith: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed)
        stage.press(forDuration: 1.3)
        let mode = app.staticTexts["home_v2_photo_scrub_mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        app.buttons["photo_timeline_root_menu"].tap()
        let scrim = app.buttons["home_v2_sidebar_scrim"]
        XCTAssertTrue(scrim.waitForExistence(timeout: 5))
        scrim.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertFalse(mode.exists)
        stage.tap()
        XCTAssertTrue(app.buttons["home_v2_viewer_close"].waitForExistence(timeout: 5))
    }

    private func launchHoldScrubFixture(largestText: Bool = false, withSteps: Bool = false, holdScrub: Bool = false)
        -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2PhotoFixture",
            "-lybUITestHomeV2TimelineFixture", "-lybUITestHomeV2OfflineFixture", "-lybUITestSuppressWhatsNew"
        ]
        if withSteps { app.launchArguments.append("-lybUITestHomeV2StepsFixture") }
        if holdScrub { app.launchArguments.append("-lybUITestPhotoHoldScrub") }
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["home_v2_photo_stage"].waitForExistence(timeout: 30))
        return app
    }
}
