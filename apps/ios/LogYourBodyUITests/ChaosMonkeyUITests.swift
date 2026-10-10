//
// ChaosMonkeyUITests.swift
// LogYourBody
//
// A seeded random-walk monkey test. It drives the running app with weighted,
// denylist-aware interactions for a configurable number of steps, watching for
// crashes, hangs, and blank screens along the way. Every run is deterministic
// for a given seed, fixture and step count so a failing run can be replayed.
//
// Stuck recovery: a real device can leave the monkey wedged on a screen
// where every element is denylisted or nothing is hittable (a paywall with
// purchase/restore/log-out all denylisted is the observed trap). Rather than
// recording an anomaly on every step of a wedged run, `StuckDetector` flags
// the episode once (no hittable elements, or an identical element tree for
// five consecutive polls) and the run relaunches with the seeding fixture,
// counting exactly one anomaly per episode. Landing on the paywall itself
// (`world_class_screen_paywall`) triggers the same relaunch immediately,
// since every paywall control is denylisted and the run can never progress
// from there on its own.
//
// Env vars:
//   LYB_CHAOS_SEED       - RNG seed (default 20260928)
//   LYB_CHAOS_STEPS      - number of steps to run (default 250)
//   LYB_CHAOS_FIXTURE    - launch argument that seeds app state (default
//                          "-lybUITestPhotoTimelineHUDFixture")
//   LYB_CHAOS_EXTRA_ARGS - space-separated extra launch arguments, appended
//                          after the fixture and preserved across a
//                          stuck-recovery relaunch. Widens the harness past
//                          the default text size/locale, e.g.:
//                            "-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL"
//                            "-AppleLanguages (ar) -AppleLocale ar_SA"
//                            "-AppleLanguages (de)"
//                            "-NSDoubleLocalizedStrings YES"
//                            "-UIAccessibilityIsBoldTextEnabled YES"
//
import XCTest

extension XCUIApplication {
    /// Forward native XCTest context without inventing a marker for ordinary launches.
    func forwardActualXCTestContext() {
        for key in ["XCTestConfigurationFilePath", "XCTestSessionIdentifier", "XCTestBundlePath"] {
            if let value = ProcessInfo.processInfo.environment[key],
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                launchEnvironment[key] = value
            } else {
                launchEnvironment.removeValue(forKey: key)
            }
        }
    }
}

enum ChaosSystemAlertPolicy {
    static func denialLabel(availableLabels: [String]) -> String? {
        let denied = ["Don't Allow", "Not Now", "Cancel", "Deny", "No Thanks", "Later"]
        return denied.first { availableLabels.contains($0) }
    }
}

/// Native snapshot ancestry is the evidence for expected scroll clipping.
/// Missing or ambiguous snapshot matches remain layout findings.
struct ChaosScrollGeometry {
    private struct Record {
        let type: XCUIElement.ElementType
        let identifier: String
        let label: String
        let frame: CGRect
        let scrollFrames: [CGRect]
    }

    private var records: [Record] = []

    init(app: XCUIApplication) {
        if let snapshot = try? app.snapshot() {
            collect(snapshot, scrollFrames: [])
        }
    }

    private mutating func collect(_ snapshot: XCUIElementSnapshot, scrollFrames: [CGRect]) {
        records.append(Record(type: snapshot.elementType, identifier: snapshot.identifier,
                              label: snapshot.label, frame: snapshot.frame, scrollFrames: scrollFrames))
        // SwiftUI's settings list exposes UICollectionView, a UIScrollView subclass.
        let isScrollContainer = snapshot.elementType == .scrollView || snapshot.elementType == .collectionView
        let ancestors = isScrollContainer ? scrollFrames + [snapshot.frame] : scrollFrames
        for child in snapshot.children {
            collect(child, scrollFrames: ancestors)
        }
    }

    var diagnosticDescription: String {
        records.map { "\($0.type) \($0.identifier) \($0.label): \($0.frame), nativeScrollAncestors=\($0.scrollFrames)" }
            .joined(separator: "\n")
    }

    /// CGRect snapshots can derive widths by subtraction, changing their last
    /// floating-point bits. Compare edges within four ULPs for record identity;
    /// the one-point layout overflow threshold remains unchanged.
    private static func sameNativeFrame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let edges = [(lhs.minX, rhs.minX), (lhs.minY, rhs.minY),
                     (lhs.maxX, rhs.maxX), (lhs.maxY, rhs.maxY)]
        return edges.allSatisfy { abs($0.0 - $0.1) <= max($0.0.ulp, $0.1.ulp) * 4 }
    }

    func isExpectedScrollClipping(_ element: XCUIElement, window: CGRect) -> Bool {
        isExpectedScrollClipping(
            type: element.elementType, identifier: element.identifier,
            label: element.label, frame: element.frame, window: window
        )
    }

    func isExpectedScrollClipping(
        type: XCUIElement.ElementType, identifier: String, label: String,
        frame elementFrame: CGRect, window: CGRect
    ) -> Bool {
        let matches = records.filter {
            $0.type == type && $0.identifier == identifier
                && $0.label == label && Self.sameNativeFrame($0.frame, elementFrame)
        }
        guard matches.count == 1, let record = matches.first else { return false }
        let frame = record.frame
        return record.scrollFrames.contains { viewport in
            guard viewport.width > 0, viewport.height > 0,
                  viewport.minX >= window.minX - 1, viewport.maxX <= window.maxX + 1,
                  viewport.minY >= window.minY - 1, viewport.maxY <= window.maxY + 1 else { return false }
            // Every overflowing edge must be clipped by the native scroll viewport.
            return (frame.minX >= window.minX - 1 || frame.minX < viewport.minX)
                && (frame.maxX <= window.maxX + 1 || frame.maxX > viewport.maxX)
                && (frame.minY >= window.minY - 1 || frame.minY < viewport.minY)
                && (frame.maxY <= window.maxY + 1 || frame.maxY > viewport.maxY)
                && !viewport.contains(frame)
        }
    }
}

/// Deterministic SplitMix64 generator so a chaos run is fully reproducible
/// from its seed, independent of the platform's default `Random`.
struct ChaosRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var result = state
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}

private enum ChaosAction: CaseIterable, Equatable {
    case tap
    case swipe
    case type
    case dismiss
    case background
}

private enum ChaosStepOutcome: Equatable {
    case executed(ChaosAction)
    case skipped(String)
}

private struct ChaosStepAccounting {
    let requested: Int
    var maximumAttempts: Int { requested * 4 }
    var shouldAttempt: Bool { completed < requested && attempted < maximumAttempts }

    private(set) var attempted = 0
    private(set) var completed = 0
    private(set) var skipped = 0
    private(set) var failed = 0

    mutating func record(_ outcome: ChaosStepOutcome) {
        attempted += 1
        switch outcome {
        case .executed: completed += 1
        case .skipped: skipped += 1
        }
    }

    mutating func recordFailure() {
        attempted += 1
        failed += 1
    }
}

private enum ChaosStepError: Error, CustomStringConvertible {
    case noInteractiveElements
    case appNotForeground(String)
    case slowQuery(TimeInterval)
    case stuckRecovered(String)

    var description: String {
        switch self {
        case .noInteractiveElements:
            return "no hittable interactive elements found"
        case .appNotForeground(let state):
            return "app left the foreground unexpectedly (state: \(state))"
        case .slowQuery(let seconds):
            return "element query took \(seconds)s (> 10s hang threshold)"
        case .stuckRecovered(let reason):
            return "recovered from a stuck screen (\(reason)); relaunched"
        }
    }
}

/// Tracks whether the monkey looks wedged on one screen: either nothing
/// hittable and non-denylisted is on screen, or the interactive-element
/// fingerprint hasn't changed for `repeatThreshold` consecutive polls (taps,
/// swipes, and types are landing but nothing about the screen is changing).
/// `reset()` after a recovery relaunch so a fresh episode needs its own
/// `repeatThreshold` streak before it counts again -- this is what keeps a
/// wedged run to exactly one anomaly per episode instead of one per step.
private struct StuckDetector {
    static let repeatThreshold = 5
    static let blankThreshold = 2

    private var lastFingerprint: Int?
    private var sameFingerprintStreak = 0
    private var blankStreak = 0

    /// Feeds one step's element fingerprint (`nil` when there were no
    /// hittable, non-denylisted candidates at all) and returns a stuck
    /// reason once a threshold trips, or `nil` if the run still looks live.
    mutating func observe(fingerprint: Int?) -> String? {
        guard let fingerprint else {
            blankStreak += 1
            sameFingerprintStreak = 0
            lastFingerprint = nil
            if blankStreak >= Self.blankThreshold {
                return "no hittable, non-denylisted elements for \(blankStreak) consecutive polls"
            }
            return nil
        }

        blankStreak = 0
        if fingerprint == lastFingerprint {
            sameFingerprintStreak += 1
        } else {
            sameFingerprintStreak = 1
            lastFingerprint = fingerprint
        }
        if sameFingerprintStreak >= Self.repeatThreshold {
            return "identical element tree for \(sameFingerprintStreak) consecutive polls"
        }
        return nil
    }

    mutating func reset() {
        lastFingerprint = nil
        sameFingerprintStreak = 0
        blankStreak = 0
    }
}

/// Mutable per-run telemetry threaded through every step, bundled into one
/// `inout` parameter so `runStep`'s signature doesn't grow every time a new
/// counter joins the stuck-episode detector.
private struct StepTelemetry {
    var stuckDetector = StuckDetector()
    var slowQueryCount = 0
    var layoutAnomalyMessages: [String] = []
    var expectedScrollClipping: [String] = []
}

/// What every launch/relaunch needs: the fixture argument plus any extra
/// launch arguments passed through `LYB_CHAOS_EXTRA_ARGS` (Dynamic Type
/// size, locale, bold text, etc.), kept together so a stuck-recovery
/// relaunch preserves the same conditions the run started under instead of
/// silently dropping back to defaults.
private struct LaunchConfig {
    let fixture: String
    let extraArgs: [String]

    var launchArguments: [String] {
        [fixture] + extraArgs + ["-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"]
    }
}

final class ChaosMonkeyUITests: XCTestCase {
    func testMissingActionTargetsDoNotCompleteMonkeySteps() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"
        ]
        app.forwardActualXCTestContext()
        app.launch()
        XCTAssertTrue(app.buttons["Open Menu"].waitForExistence(timeout: 30))
        XCTAssertEqual(dismissKeyboardForStep(app: app), .skipped("keyboard was not present"))
        var rng = ChaosRNG(seed: 42)
        var accounting = ChaosStepAccounting(requested: 1)
        accounting.record(performTap(app: app, candidates: [], rng: &rng))
        accounting.record(performSwipe(app: app, rng: &rng, targets: []))
        accounting.record(performType(app: app, rng: &rng, fields: []))
        accounting.record(performDismiss(app: app, buttons: []))
        XCTAssertEqual(accounting.attempted, 4)
        XCTAssertEqual(accounting.completed, 0, "Returning without an action must never count toward the requested budget.")
        XCTAssertEqual(accounting.skipped, 4)
        XCTAssertEqual(accounting.failed, 0)
        XCTAssertFalse(
            accounting.shouldAttempt,
            "The bounded attempt budget must fail incomplete instead of converting no-ops into successes."
        )
    }

    func testExecutedNativeActionsCompleteOnlyTheirOwnBudget() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestChatFirstFixture", "-lybUITestChatOfflineFixture",
            "-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"
        ]
        app.forwardActualXCTestContext()
        app.launch()
        openDefaultHomeAsk(in: app)
        let composer = app.textFields["chat_composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 12))
        var rng = ChaosRNG(seed: 42)
        var accounting = ChaosStepAccounting(requested: 4)
        let menu = app.buttons["photo_timeline_root_menu"]
        XCTAssertTrue(menu.exists)
        accounting.record(performTap(app: app, candidates: [menu], rng: &rng))
        let closeMenu = app.buttons["home_v2_sidebar_scrim"]
        XCTAssertTrue(closeMenu.waitForExistence(timeout: 5))
        accounting.record(performDismiss(app: app, buttons: [closeMenu]))
        XCTAssertTrue(closeMenu.waitForNonExistence(timeout: 5))
        accounting.record(performSwipe(app: app, rng: &rng, targets: [app.windows.firstMatch]))
        accounting.record(performType(app: app, rng: &rng, fields: [composer]))
        XCTAssertEqual(accounting.attempted, 4)
        XCTAssertEqual(accounting.completed, 4)
        XCTAssertEqual(accounting.skipped, 0)
        XCTAssertFalse(accounting.shouldAttempt)
        XCTAssertFalse(app.keyboards.element.exists)
        if !composer.exists { openDefaultHomeAsk(in: app) }
        XCTAssertNotEqual(composer.value as? String, "", "Actual typing must leave a local draft without sending it.")
    }

    func testFailedActionsExhaustAttemptsWithoutCompletion() {
        var accounting = ChaosStepAccounting(requested: 1)
        while accounting.shouldAttempt { accounting.recordFailure() }
        XCTAssertEqual(accounting.attempted, 4)
        XCTAssertEqual(accounting.failed, 4)
        XCTAssertEqual(accounting.completed, 0)
        XCTAssertEqual(accounting.skipped, 0)
    }

    func testProfilePhotoImportIsExcludedFromMonkeyCandidates() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"
        ]
        app.forwardActualXCTestContext()
        app.launch()
        let menu = app.buttons["Open Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let profile = app.buttons["settings_profile_link"]
        XCTAssertTrue(profile.waitForExistence(timeout: 8))
        profile.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 8))
        let photo = app.buttons["Change profile photo"]
        XCTAssertTrue(photo.exists)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Profile photo picker candidate safety"
        tree.lifetime = .keepAlways
        add(tree)
        let candidates = snapshotElements(in: app).interactive
        XCTAssertFalse(candidates.contains { $0.label.contains("Change profile photo") })
        for candidate in candidates where candidate.elementType == .other || candidate.elementType == .cell {
            XCTAssertFalse(candidate.frame.intersects(photo.frame), "Generic parent must not activate profile photo import.")
        }
    }

    func testKeyboardDismissalPreservesDraftWithoutSending() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Existing DEBUG FixtureChatService.offline guarantees this red probe
        // cannot call a real chat provider or send a server message.
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestChatFirstFixture", "-lybUITestChatOfflineFixture",
            "-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"
        ]
        app.forwardActualXCTestContext()
        app.launch()
        openDefaultHomeAsk(in: app)
        let composer = app.textFields["chat_composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 12))
        composer.tap()
        let draft = "local chaos draft"
        composer.typeText(draft)
        XCTAssertTrue(app.keyboards.element.exists)
        XCTAssertEqual(dismissKeyboardForStep(app: app), .executed(.dismiss))
        XCTAssertFalse(app.keyboards.element.exists)
        // Default Home removes the Ask view when collapsed; reopen before inspecting its draft.
        if !composer.exists { openDefaultHomeAsk(in: app) }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Keyboard dismissal draft preservation"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertEqual(composer.value as? String, draft, "Keyboard dismissal must not submit or clear a draft.")
        XCTAssertFalse(app.staticTexts[draft].exists, "Keyboard dismissal must not submit the local draft.")
    }

    func testSystemAlertsRequireKnownDenyOnlyAction() {
        for label in ["Don't Allow", "Not Now", "Cancel", "Deny", "No Thanks", "Later"] {
            XCTAssertEqual(ChaosSystemAlertPolicy.denialLabel(availableLabels: [label]), label)
        }
        for labels in [["Allow", "OK"], ["Continue"], ["السماح"], []] {
            XCTAssertNil(ChaosSystemAlertPolicy.denialLabel(availableLabels: labels))
        }
    }

    func testWeightEntryPhotoImportControlsAreExcludedFromMonkeyCandidates() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestHomeV2PhotoFixture",
            "-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"
        ]
        app.forwardActualXCTestContext()
        app.launch()
        popToRootIfNeeded(in: app)
        let contextButton = app.buttons["home_v2_context_button"]
        XCTAssertTrue(contextButton.waitForExistence(timeout: 30))
        contextButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home_v2_context"].waitForExistence(timeout: 8))
        let addPhoto = app.buttons["home_v2_context_add_photo"]
        XCTAssertTrue(addPhoto.exists)
        let contextCandidates = snapshotElements(in: app).interactive
        XCTAssertFalse(contextCandidates.map(\.identifier).contains(addPhoto.identifier),
                       "Monkey must not open the personal photo picker from Context.")
        let edit = app.buttons["home_v2_edit_entry"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let sheet = app.descendants(matching: .any)["home_v2_log_sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        XCTAssertEqual(sheet.label, "Edit entry")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Photo import control scanner tree"
        tree.lifetime = .keepAlways
        add(tree)
        let photoControls = ["front", "side", "back"].map { "home_v2_log_sheet_photo_\($0)" }
        for identifier in photoControls {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        }
        let candidates = snapshotElements(in: app).interactive
        let identifiers = candidates.map(\.identifier)
        for identifier in photoControls {
            let protectedFrame = app.buttons[identifier].frame
            XCTAssertFalse(identifiers.contains(identifier), "Monkey must not open personal photo import: \(identifier)")
            for candidate in candidates where candidate.elementType == .other || candidate.elementType == .cell {
                let center = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
                XCTAssertFalse(protectedFrame.contains(center),
                               "Generic parent activation center enters protected photo control: \(candidate.identifier) \(candidate.frame)")
            }
        }
    }

    func testNativeScrollClippingRequiresActualScrollAncestor() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestPhotoTimelineHUDFixture", "-lybUITestChatFirstFixture", "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.forwardActualXCTestContext()
        app.launch()
        openDefaultHomeAsk(in: app)
        let prompt = app.buttons["Summarize my trend"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 30))
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(prompt.frame.maxX, window.maxX)
        XCTAssertTrue(prompt.frame.intersects(window))
        let geometry = ChaosScrollGeometry(app: app)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Native scroll ancestry regression tree"
        tree.lifetime = .keepAlways
        add(tree)
        let snapshot = XCTAttachment(string: geometry.diagnosticDescription)
        snapshot.name = "Native immutable geometry and ancestry"
        snapshot.lifetime = .keepAlways
        add(snapshot)
        XCTAssertTrue(geometry.isExpectedScrollClipping(prompt, window: window))
        let offscreen = app.buttons["What changed recently?"]
        XCTAssertTrue(offscreen.exists)
        XCTAssertFalse(offscreen.frame.intersects(window))
        XCTAssertTrue(geometry.isExpectedScrollClipping(offscreen, window: window))
        let send = app.buttons["chat_send_button"]
        XCTAssertTrue(send.exists)
        // Exercise overflow classification with a real non-scroll element and
        // a deliberately cropped viewport. This is a scanner regression,
        // not a claim that the rendered Send button overflows the app.
        let croppedWindow = CGRect(x: send.frame.minX, y: send.frame.minY,
                                   width: send.frame.width / 2, height: send.frame.height)
        XCTAssertGreaterThan(send.frame.maxX, croppedWindow.maxX)
        XCTAssertFalse(geometry.isExpectedScrollClipping(send, window: croppedWindow))
    }

    private func openDefaultHomeAsk(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["home_v2_log_weight"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["launch_timeline_surface"].exists)
        let menu = app.buttons["photo_timeline_root_menu"]
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        let ask = app.buttons["home_v2_sidebar_ask"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.tap()
        XCTAssertTrue(app.textFields["chat_composer"].waitForExistence(timeout: 8))
    }

    private static let edgeStrings: [String] = [
        "",
        "0",
        "-1",
        "999999",
        "66.6666666",
        "1e3",
        "\u{0661}\u{0662}\u{0663}",
        "\u{1F351}\u{1F4AA}",
        String(repeating: "x", count: 300),
        "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627} \u{0628}\u{0627}\u{0644}\u{0639}\u{0627}\u{0644}\u{0645}",
        "a\u{200D}b"
    ]

    private static let denylistedIdentifiers: Set<String> = [
        "delete_account_confirm_button",
        "delete_account_confirmation_field",
        "delete_account_confirmation_error",
        "home_v2_ask_delete",
        "home_v2_log_sheet_delete",
        "glp1DoseHistoryDeleteButton",
        "mvp_sign_out_button",
        "settings_logout_button",
        "home_v2_paywall_log_out",
        "paywall_logout_button",
        "home_v2_paywall_restore",
        "paywall_restore_purchases_button",
        "settings_restore_purchases_button",
        "home_v2_paywall_purchase",
        "paywall_purchase_button",
        "settings_manage_subscription_button",
        "integrations_health_sync_all_button",
        "continueWithAppleButton",
        "body_spec_pdf_import",
        "bulk_photo_import_start_scanning",
        "body_score_hero_share_button",
        "launch_timeline_add_photo",
        "home_v2_connect_health",
        "home_v2_context_add_photo",
        "home_v2_log_sheet_photo_front",
        "home_v2_log_sheet_photo_side",
        "home_v2_log_sheet_photo_back",
        "chat_send_button",
        "export_data_action",
        "body_score_quick_share_button",
        "home_v2_compare_share",
        "home_v2_share_action"
    ]

    private static let denylistedLabelFragments: [String] = [
        "delete",
        "log out",
        "sign out",
        "restore purchase",
        "start free trial",
        "subscribe",
        "manage in app store",
        "manage subscription",
        "connect apple health",
        "camera",
        "add photo",
        "add progress photo",
        "change profile photo",
        "retake",
        "import photos",
        "choose from library",
        "share",
        "send",
        "email support",
        "email secure link",
        "submit",
        "how am i doing?",
        "summarize my trend",
        "what changed recently?",
        "continue with apple",
        "open settings"
    ]

    func testHeightKeyboardDoneMeetsMinimumHitTarget() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-lybUITestBodyScoreOnboardingFixture",
            "-lybUITestSuppressWhatsNew",
            "-lybUITestDisableBiometricLock"
        ]
        app.forwardActualXCTestContext()
        app.launch()
        app.tap()

        let start = app.buttons["body_score_onboarding_start_button"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let male = app.buttons["Male"]
        XCTAssertTrue(male.waitForExistence(timeout: 8))
        male.tap()
        let basicsContinue = app.buttons["body_score_onboarding_basics_continue_button"]
        XCTAssertTrue(basicsContinue.waitForExistence(timeout: 5))
        basicsContinue.tap()

        XCTAssertTrue(app.staticTexts["How tall are you?"].waitForExistence(timeout: 8))
        let centimeters = app.buttons["CM"]
        XCTAssertTrue(centimeters.waitForExistence(timeout: 5))
        centimeters.tap()
        let field = app.textFields["Height in centimeters"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))

        let window = app.windows.firstMatch.frame
        let done = app.buttons.matching(identifier: "body_score_height_keyboard_done_button").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(window.contains(done.frame), "height Done \(done.frame) window \(window)")
        XCTAssertGreaterThanOrEqual(done.frame.width, 44, "height Done \(done.frame)")
        XCTAssertGreaterThanOrEqual(done.frame.height, 44, "height Done \(done.frame)")

        let labeledDones = app.buttons.matching(NSPredicate(format: "label == 'Done'"))
        for index in 0..<labeledDones.count {
            let control = labeledDones.element(boundBy: index)
            guard control.exists, control.frame.width > 1, control.frame.height > 1 else { continue }
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, "height Done \(control.frame)")
        }

        done.tap()
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["How tall are you?"].exists)
    }

    override func setUpWithError() throws {
        // The monkey must survive individual bad taps; only a hard app-death
        // check below stops the run early.
        continueAfterFailure = true
    }

    func testChaosMonkey() throws {
        let seed = UInt64(ProcessInfo.processInfo.environment["LYB_CHAOS_SEED"] ?? "") ?? 20_260_928
        let steps = Int(ProcessInfo.processInfo.environment["LYB_CHAOS_STEPS"] ?? "") ?? 250
        let rawFixture = ProcessInfo.processInfo.environment["LYB_CHAOS_FIXTURE"] ?? ""
        let fixture = rawFixture.isEmpty ? "-lybUITestPhotoTimelineHUDFixture" : rawFixture
        let rawExtraArgs = ProcessInfo.processInfo.environment["LYB_CHAOS_EXTRA_ARGS"] ?? ""
        let extraArgs = rawExtraArgs.split(separator: " ").map(String.init)
        let config = LaunchConfig(fixture: fixture, extraArgs: extraArgs)

        var rng = ChaosRNG(seed: seed)
        let app = XCUIApplication()
        var interruptionsDismissed = 0
        var unexpectedSystemAlert = false
        var anomalies: [String] = []
        var telemetry = StepTelemetry()

        let monitor = addUIInterruptionMonitor(withDescription: "Chaos monkey system alert") { alert in
            let labels = alert.buttons.allElementsBoundByIndex.map(\.label)
            if let label = ChaosSystemAlertPolicy.denialLabel(availableLabels: labels) {
                alert.buttons[label].tap()
                interruptionsDismissed += 1
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
            unexpectedSystemAlert = true
            XCTFail("Unexpected system alert has no known deny-only action; see retained evidence.")
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }

        app.launchArguments = config.launchArguments
        app.forwardActualXCTestContext()
        app.launch()
        app.tap()
        popToRootIfNeeded(in: app)

        guard steps > 0, steps <= Int.max / 4 else {
            XCTFail("Requested action count must be positive and have a bounded attempt budget.")
            return
        }
        var accounting = ChaosStepAccounting(requested: steps)
        var actionTrace: [String] = []
        while accounting.shouldAttempt {
            let step = accounting.attempted
            guard !unexpectedSystemAlert else { break }
            do {
                let outcome = try runStep(
                    step: step,
                    seed: seed,
                    app: app,
                    config: config,
                    rng: &rng,
                    telemetry: &telemetry
                )
                accounting.record(outcome)
                actionTrace.append("attempt \(step): \(outcome)")
            } catch {
                accounting.recordFailure()
                let message = "step \(step): \(error)"
                anomalies.append(message)
                attachDiagnostics(app: app, name: "chaos-\(seed)-step-\(step)-anomaly")

                if case ChaosStepError.appNotForeground = error {
                    XCTFail("Chaos monkey stopped: \(message)")
                    break
                }
            }

            if step.isMultiple(of: 25) {
                attachDiagnostics(app: app, name: "chaos-\(seed)-step-\(step)")
            }
        }

        attachDiagnostics(app: app, name: "chaos-\(seed)-step-final")
        anomalies.append(contentsOf: telemetry.layoutAnomalyMessages)

        var summaryLines = [
            "seed=\(seed) steps=\(steps) fixture=\(fixture) extraArgs=\(extraArgs.joined(separator: " "))",
            "attemptedSteps=\(accounting.attempted) completedSteps=\(accounting.completed) " +
                "skippedSteps=\(accounting.skipped) failedSteps=\(accounting.failed) maxAttempts=\(accounting.maximumAttempts)",
            "systemAlertsDismissed=\(interruptionsDismissed)",
            "slowQueries(10-30s)=\(telemetry.slowQueryCount)",
            "layoutAnomalies=\(telemetry.layoutAnomalyMessages.count)",
            "expectedScrollClipping=\(telemetry.expectedScrollClipping.count)",
            "anomalies=\(anomalies.count)"
        ]
        summaryLines.append(contentsOf: actionTrace)
        summaryLines.append(contentsOf: anomalies)
        summaryLines.append(contentsOf: telemetry.expectedScrollClipping)
        let summary = XCTAttachment(string: summaryLines.joined(separator: "\n"))
        summary.name = "chaos-\(seed)-summary"
        summary.lifetime = .keepAlways
        add(summary)

        XCTAssertEqual(
            accounting.completed, steps,
            "Requested executed actions were not reached within the bounded attempt budget; see retained telemetry."
        )
        XCTAssertTrue(anomalies.isEmpty, "Untriaged anomalies under fixture \(fixture): \(anomalies.count); see attachments.")
    }

    // MARK: - Step execution

    private func runStep(
        step: Int,
        seed: UInt64,
        app: XCUIApplication,
        config: LaunchConfig,
        rng: inout ChaosRNG,
        telemetry: inout StepTelemetry
    ) throws -> ChaosStepOutcome {
        guard app.state == .runningForeground else {
            throw ChaosStepError.appNotForeground(String(describing: app.state))
        }

        // Notification banners render in SpringBoard, not the app under
        // test, so the app's own element queries never see them -- they
        // just silently swallow the next tap. Clear one before acting.
        dismissNotificationBanner(app: app)

        // Every paywall control is denylisted (purchase/restore/log-out), so
        // the monkey can never make progress from here on its own; escape
        // immediately rather than waiting for the stuck-tree threshold.
        if app.descendants(matching: .any)["world_class_screen_paywall"].exists {
            relaunch(app: app, config: config)
            telemetry.stuckDetector.reset()
            throw ChaosStepError.stuckRecovered("landed on the paywall (world_class_screen_paywall)")
        }

        // A visible keyboard adds ~45 extra nodes the general element query
        // below must traverse, which alone can exceed the old 10s
        // slow-query threshold; worse, that threw *before* any action ran,
        // so the step that hit it never fixed it either -- a real device
        // sat typing into chat_composer for 100+ steps in a row this way
        // (docs/engineering/chaos-testing.md has the incident). Skip the
        // general query entirely and dismiss the keyboard directly instead.
        if app.keyboards.element.exists {
            return dismissKeyboardForStep(app: app)
        }

        let queryStart = Date()
        let snapshot = snapshotElements(in: app)
        let queryDuration = Date().timeIntervalSince(queryStart)
        // A merely-slow query (device under load, a larger tree) is a
        // metric, not a step-ending anomaly on its own -- only a genuine
        // hang past 30s is. The stuck detector below still observes this
        // step's fingerprint either way.
        if queryDuration > 10 {
            telemetry.slowQueryCount += 1
        }
        if queryDuration > 30 {
            throw ChaosStepError.slowQuery(queryDuration)
        }

        // Reuses snapshot.layoutCandidates (already fetched above) rather
        // than a second tree query. Recorded, not thrown: a layout defect
        // shouldn't block this step's normal action the way a stuck screen
        // does, but it's exactly the kind of finding a Dynamic Type or RTL
        // round (LYB_CHAOS_EXTRA_ARGS) exists to surface.
        var clipping: [String] = []
        let layoutFindings = layoutAnomalies(candidates: snapshot.layoutCandidates, in: app, observations: &clipping)
        telemetry.expectedScrollClipping.append(contentsOf: clipping.map { "step \(step): \($0)" })
        if !layoutFindings.isEmpty {
            for finding in layoutFindings {
                telemetry.layoutAnomalyMessages.append("step \(step): layout defect: \(finding)")
            }
            attachDiagnostics(app: app, name: "chaos-\(seed)-step-\(step)-layout")
        }

        let fingerprint = snapshot.interactive.isEmpty ? nil : treeFingerprint(snapshot.interactive)
        if let stuckReason = telemetry.stuckDetector.observe(fingerprint: fingerprint) {
            relaunch(app: app, config: config)
            telemetry.stuckDetector.reset()
            throw ChaosStepError.stuckRecovered(stuckReason)
        }

        let candidates = snapshot.interactive
        switch pickAction(using: &rng) {
        case .tap:
            return performTap(app: app, candidates: candidates, rng: &rng)
        case .swipe:
            return performSwipe(app: app, rng: &rng)
        case .type:
            return performType(app: app, rng: &rng)
        case .dismiss:
            return performDismiss(app: app)
        case .background:
            return try performBackground(app: app)
        }
    }

    private func pickAction(using rng: inout ChaosRNG) -> ChaosAction {
        let roll = Int.random(in: 0..<100, using: &rng)
        switch roll {
        case 0..<55: return .tap
        case 55..<70: return .swipe
        case 70..<85: return .type
        case 85..<95: return .dismiss
        default: return .background
        }
    }

    // MARK: - Actions

    private func performTap(app: XCUIApplication, candidates: [XCUIElement], rng: inout ChaosRNG) -> ChaosStepOutcome {
        guard let target = candidates.randomElement(using: &rng), target.exists, target.isHittable, !isDenylisted(target) else {
            return .skipped("no safe tappable target")
        }
        target.tap()
        return .executed(.tap)
    }

    private func performSwipe(app: XCUIApplication, rng: inout ChaosRNG, targets: [XCUIElement]? = nil) -> ChaosStepOutcome {
        let scrollable = targets ?? (
            app.scrollViews.allElementsBoundByIndex
                + app.collectionViews.allElementsBoundByIndex
                + app.tables.allElementsBoundByIndex
                + [app.windows.firstMatch]
        ).filter(\.isHittable)
        guard let target = scrollable.randomElement(using: &rng), target.exists, target.isHittable,
              hasFiniteNonZeroFrame(target) else { return .skipped("no hittable swipe target") }
        switch Int.random(in: 0..<4, using: &rng) {
        case 0: target.swipeUp()
        case 1: target.swipeDown()
        case 2: target.swipeLeft()
        default: target.swipeRight()
        }
        return .executed(.swipe)
    }

    private func performType(app: XCUIApplication, rng: inout ChaosRNG, fields: [XCUIElement]? = nil) -> ChaosStepOutcome {
        let available = (fields ?? (app.textFields.allElementsBoundByIndex + app.searchFields.allElementsBoundByIndex))
            .filter { $0.isHittable && !isDenylisted($0) }
        guard let field = available.first else { return .skipped("no safe text field") }
        field.tap()
        guard app.keyboards.element.waitForExistence(timeout: 1.5) else {
            return .skipped("text field did not gain keyboard focus")
        }
        let edge = Self.edgeStrings.randomElement(using: &rng) ?? ""
        guard !edge.isEmpty else { return .skipped("seeded text was empty") }
        field.typeText(String(edge.prefix(24)))
        guard dismissKeyboardForStep(app: app) == .executed(.dismiss) else {
            return .skipped("typing finished but keyboard dismissal was not verified")
        }
        return .executed(.type)
    }

    private func performDismiss(app: XCUIApplication, buttons: [XCUIElement]? = nil) -> ChaosStepOutcome {
        let candidates = buttons ?? ["Back", "Close", "Cancel", "Done"].map { app.buttons[$0] }
            + [app.navigationBars.buttons.element(boundBy: 0)]
        for button in candidates where button.exists && button.isHittable && !isDenylisted(button) {
            if button.identifier == "home_v2_sidebar_scrim" {
                // The drawer covers the scrim's center; dismiss through its exposed right edge.
                button.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                    .withOffset(CGVector(dx: -8, dy: 0)).tap()
            } else {
                button.tap()
            }
            return .executed(.dismiss)
        }
        return .skipped("no safe dismissal control")
    }

    private func performBackground(app: XCUIApplication) throws -> ChaosStepOutcome {
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        // `activate()` returns before the state transition is guaranteed to
        // have landed; poll briefly so the next step's foreground check does
        // not spuriously flag this deliberate backgrounding as an anomaly.
        let deadline = Date().addingTimeInterval(5)
        while app.state != .runningForeground, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        guard app.state == .runningForeground else {
            throw ChaosStepError.appNotForeground(String(describing: app.state))
        }
        return .executed(.background)
    }

    /// Terminates and relaunches with the seeding fixture, mirroring the
    /// initial launch in `testChaosMonkey`. Used to recover from a wedged
    /// screen rather than continuing to hammer a state the run can't escape.
    private func relaunch(app: XCUIApplication, config: LaunchConfig) {
        app.terminate()
        app.launchArguments = config.launchArguments
        app.forwardActualXCTestContext()
        app.launch()
        app.tap()
        popToRootIfNeeded(in: app)
    }

    /// A shared dev simulator/device has landed a fresh launch on a pushed
    /// screen left over from an earlier run instead of the fixture's
    /// intended root -- the account's own state outlives the process. No
    /// fixture's intended root pushes a screen with a navigation Back
    /// button, so any Back button present here is stray. Records what was
    /// actually on screen before popping (visible even on an otherwise-
    /// passing run); a single fast `.exists` check when already at the
    /// fixture-driven root.
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

    /// System notification banners render in SpringBoard, not the app under
    /// test, so `app`'s own element tree never sees them and XCTest's
    /// alert-style interruption monitor doesn't apply to them either (they
    /// aren't a `UIAlertController`). Reach into SpringBoard directly and
    /// swipe the banner up and off-screen before acting; a no-op if none is
    /// showing.
    private func dismissNotificationBanner(app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.otherElements["NotificationShortLookView"]
        guard banner.waitForExistence(timeout: 0.5) else { return }
        let start = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -3))
        start.press(forDuration: 0.05, thenDragTo: end)
        _ = banner.waitForNonExistence(timeout: 2)
    }

    private func dismissKeyboard(app: XCUIApplication) -> Bool {
        let candidates = [
            app.keyboards.buttons["Done"],
            app.buttons["mvp_keyboard_done_button"],
            app.buttons["mvp_keyboard_bottom_done_button"],
            app.toolbars.buttons["Done"]
        ]
        for candidate in candidates where candidate.exists && candidate.isHittable && !isDenylisted(candidate) {
            candidate.tap()
            if app.keyboards.element.waitForNonExistence(timeout: 2) { return true }
        }
        return false
    }

    /// Count a dismissal only when a previously visible keyboard disappears.
    private func dismissKeyboardForStep(app: XCUIApplication) -> ChaosStepOutcome {
        guard app.keyboards.element.exists else { return .skipped("keyboard was not present") }
        let scroll = app.scrollViews.firstMatch
        if scroll.exists && hasFiniteNonZeroFrame(scroll) && scroll.isHittable {
            scroll.swipeDown()
            if app.keyboards.element.waitForNonExistence(timeout: 2) { return .executed(.dismiss) }
        }
        let closeChat = app.buttons["home_chat_collapse"]
        if closeChat.exists && closeChat.isHittable {
            closeChat.tap()
            if app.keyboards.element.waitForNonExistence(timeout: 2) { return .executed(.dismiss) }
        }
        // Leave the existing navigation cover open; closing it restores composer focus.
        let menu = app.buttons["photo_timeline_root_menu"]
        if menu.exists && menu.isHittable {
            menu.tap()
            attachDiagnostics(app: app, name: "keyboard-dismissal-navigation-cover")
            if app.keyboards.element.waitForNonExistence(timeout: 2) { return .executed(.dismiss) }
        }
        return dismissKeyboard(app: app) ? .executed(.dismiss) : .skipped("keyboard remained visible")
    }

    // MARK: - Element discovery

    /// One round of element queries feeding two different views: the
    /// denylist-aware `interactive` candidates the monkey acts on (as
    /// `interactiveElements` always returned), and the broader, unfiltered
    /// `layoutCandidates` (every hittable button and static text)
    /// `layoutAnomalies` scans -- buttons are queried once and reused
    /// rather than fetched twice per step.
    private struct StepSnapshot {
        let interactive: [XCUIElement]
        let layoutCandidates: [XCUIElement]
    }

    private func snapshotElements(in app: XCUIApplication) -> StepSnapshot {
        let buttons = app.buttons.allElementsBoundByIndex
        let staticTexts = app.staticTexts.allElementsBoundByIndex

        var elements: [XCUIElement] = buttons
        elements.append(contentsOf: app.cells.allElementsBoundByIndex)
        elements.append(contentsOf: app.textFields.allElementsBoundByIndex)
        elements.append(contentsOf: app.switches.allElementsBoundByIndex)
        elements.append(contentsOf: app.sliders.allElementsBoundByIndex)
        elements.append(contentsOf: app.segmentedControls.allElementsBoundByIndex)
        elements.append(contentsOf: app.otherElements.allElementsBoundByIndex.prefix(40))

        // Defense in depth: `runStep` already skips the general query
        // entirely whenever a keyboard is showing, but exclude individual
        // key elements from the candidate set too in case one is ever
        // picked up by a type query above regardless. hasFiniteNonZeroFrame
        // guards `.isHittable`, which can hard-fail XCTest for a degenerate
        // frame under an extreme text size or locale instead of returning
        // false -- see layoutAnomalies below for the evidence.
        let windowFrame = app.windows.firstMatch.frame
        let protectedFrames = buttons.filter { isDenylisted($0) && hasFiniteNonZeroFrame($0) }
            .map(\.frame).filter { $0.intersects(windowFrame) }
        let interactive = elements.filter { element in
            guard hasFiniteNonZeroFrame(element), element.frame.intersects(windowFrame),
                  !isDenylisted(element), element.elementType != .key else { return false }
            // A generic parent can delegate its activation point to a protected
            // child. Keep such parents out of random taps; direct safe controls
            // and the existing app-level swipe actions remain available.
            if element.elementType == .other || element.elementType == .cell {
                let frame = element.frame
                if protectedFrames.contains(where: { $0.intersects(frame) }) { return false }
            }
            return element.isHittable
        }
        // Not pre-filtered by .isHittable: layoutAnomalies needs to see a
        // degenerate frame (including one .isHittable can't safely judge)
        // to report it as a finding rather than skip it.
        let layoutCandidates = buttons + staticTexts
        return StepSnapshot(interactive: interactive, layoutCandidates: layoutCandidates)
    }

    /// `.isHittable` can hard-fail XCTest for a degenerate frame instead of
    /// returning false ("Failed to determine hittability ...: Activation
    /// point invalid and no suggested hit points based on element frame"),
    /// so geometry is checked before ever calling it -- own simulator
    /// evidence: a "What changed recently?" button crashed a layout scan
    /// this way under AccessibilityXXXL.
    private func hasFiniteNonZeroFrame(_ element: XCUIElement) -> Bool {
        let frame = element.frame
        return frame.width.isFinite && frame.height.isFinite
            && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width > 0 && frame.height > 0
    }

    private func isDenylisted(_ element: XCUIElement) -> Bool {
        if Self.denylistedIdentifiers.contains(element.identifier) {
            return true
        }
        let haystack = (element.identifier + " " + element.label).lowercased()
        return Self.denylistedLabelFragments.contains { haystack.contains($0) }
    }

    /// A cheap fingerprint of the candidate set `StuckDetector` compares
    /// across steps: identifier + label + enabled state for each element,
    /// order-sensitive (the query order is stable for an unchanged tree).
    private func treeFingerprint(_ elements: [XCUIElement]) -> Int {
        var hasher = Hasher()
        for element in elements {
            hasher.combine(element.identifier)
            hasher.combine(element.label)
            hasher.combine(element.isEnabled)
        }
        return hasher.finalize()
    }

    // MARK: - Layout defect detection

    /// Scans the given candidates (buttons + static texts `snapshotElements`
    /// already fetched this step) for three classes of layout defect: a
    /// frame extending outside the app window, a zero-size frame while the
    /// element still reports as hittable, or a label clipped down to a
    /// single ellipsis. System alerts are excluded -- their layout isn't
    /// the app's to fix, and the keyboard never reaches this point at all
    /// (runStep returns before fetching `candidates` whenever one is up).
    private func layoutAnomalies(
        candidates: [XCUIElement], in app: XCUIApplication, observations: inout [String]
    ) -> [String] {
        guard !app.alerts.firstMatch.exists else { return [] }
        let windowFrame = app.windows.firstMatch.frame
        guard windowFrame.width > 0, windowFrame.height > 0 else { return [] }

        let scrollGeometry = ChaosScrollGeometry(app: app)
        var findings: [String] = []
        for element in candidates {
            guard element.exists else { continue }
            let frame = element.frame

            // `.isHittable` itself can hard-fail instead of returning false
            // for a degenerate frame (see hasFiniteNonZeroFrame above), so
            // geometry is checked -- and a bad frame reported directly --
            // before ever calling it.
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

    // MARK: - Diagnostics

    private func attachDiagnostics(app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
