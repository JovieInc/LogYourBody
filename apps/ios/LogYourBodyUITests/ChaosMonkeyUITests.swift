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
//   LYB_CHAOS_SEED    - RNG seed (default 20260928)
//   LYB_CHAOS_STEPS   - number of steps to run (default 250)
//   LYB_CHAOS_FIXTURE - launch argument that seeds app state (default
//                        "-lybUITestPhotoTimelineHUDFixture")
//
import XCTest

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

private enum ChaosAction: CaseIterable {
    case tap
    case swipe
    case type
    case dismiss
    case background
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

final class ChaosMonkeyUITests: XCTestCase {
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
        "home_v2_connect_health"
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
        "continue with apple",
        "open settings"
    ]

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

        var rng = ChaosRNG(seed: seed)
        let app = XCUIApplication()
        var interruptionsDismissed = 0
        var anomalies: [String] = []
        var stuckDetector = StuckDetector()

        let monitor = addUIInterruptionMonitor(withDescription: "Chaos monkey system alert") { alert in
            let dismissLabels = ["Don't Allow", "Not Now", "Cancel", "Deny", "No Thanks", "Later", "OK"]
            for label in dismissLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                interruptionsDismissed += 1
                return true
            }
            if let firstButton = alert.buttons.allElementsBoundByIndex.first, firstButton.exists {
                firstButton.tap()
                interruptionsDismissed += 1
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }

        app.launchArguments = [fixture, "-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"]
        app.launch()
        app.tap()
        popToRootIfNeeded(in: app)

        for step in 0..<steps {
            do {
                try runStep(
                    step: step,
                    seed: seed,
                    app: app,
                    fixture: fixture,
                    rng: &rng,
                    stuckDetector: &stuckDetector
                )
            } catch {
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

        var summaryLines = [
            "seed=\(seed) steps=\(steps) fixture=\(fixture)",
            "systemAlertsDismissed=\(interruptionsDismissed)",
            "anomalies=\(anomalies.count)"
        ]
        summaryLines.append(contentsOf: anomalies)
        let summary = XCTAttachment(string: summaryLines.joined(separator: "\n"))
        summary.name = "chaos-\(seed)-summary"
        summary.lifetime = .keepAlways
        add(summary)

        XCTAssertLessThan(
            anomalies.count,
            max(steps / 4, 1),
            "Too many anomalies (\(anomalies.count)/\(steps)) under fixture \(fixture); see attachments."
        )
    }

    // MARK: - Step execution

    private func runStep(
        step: Int,
        seed: UInt64,
        app: XCUIApplication,
        fixture: String,
        rng: inout ChaosRNG,
        stuckDetector: inout StuckDetector
    ) throws {
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
            relaunch(app: app, fixture: fixture)
            stuckDetector.reset()
            throw ChaosStepError.stuckRecovered("landed on the paywall (world_class_screen_paywall)")
        }

        let queryStart = Date()
        let candidates = interactiveElements(in: app)
        let queryDuration = Date().timeIntervalSince(queryStart)
        if queryDuration > 10 {
            throw ChaosStepError.slowQuery(queryDuration)
        }

        let fingerprint = candidates.isEmpty ? nil : treeFingerprint(candidates)
        if let stuckReason = stuckDetector.observe(fingerprint: fingerprint) {
            relaunch(app: app, fixture: fixture)
            stuckDetector.reset()
            throw ChaosStepError.stuckRecovered(stuckReason)
        }

        switch pickAction(using: &rng) {
        case .tap:
            performTap(app: app, candidates: candidates, rng: &rng)
        case .swipe:
            performSwipe(app: app, rng: &rng)
        case .type:
            performType(app: app, rng: &rng)
        case .dismiss:
            performDismiss(app: app)
        case .background:
            performBackground(app: app)
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

    private func performTap(app: XCUIApplication, candidates: [XCUIElement], rng: inout ChaosRNG) {
        guard let target = candidates.randomElement(using: &rng), target.exists, target.isHittable else {
            return
        }
        target.tap()
    }

    private func performSwipe(app: XCUIApplication, rng: inout ChaosRNG) {
        let scrollable = (
            app.scrollViews.allElementsBoundByIndex
                + app.collectionViews.allElementsBoundByIndex
                + app.tables.allElementsBoundByIndex
        ).filter(\.isHittable)
        let target = scrollable.randomElement(using: &rng) ?? app.windows.firstMatch
        guard target.exists else { return }

        switch Int.random(in: 0..<4, using: &rng) {
        case 0: target.swipeUp()
        case 1: target.swipeDown()
        case 2: target.swipeLeft()
        default: target.swipeRight()
        }
    }

    private func performType(app: XCUIApplication, rng: inout ChaosRNG) {
        let fields = (app.textFields.allElementsBoundByIndex + app.searchFields.allElementsBoundByIndex)
            .filter { $0.isHittable && !isDenylisted($0) }
        guard let field = fields.first else { return }

        field.tap()
        // A tap does not always land focus in time on a real device; typing
        // into an unfocused field raises a hard XCTest event synthesis error
        // rather than a catchable Swift error. XCUIElement has no public
        // focus query, so wait for the keyboard itself as a focus proxy, and
        // skip typing this step (not the whole run) if it never appears.
        guard app.keyboards.element.waitForExistence(timeout: 1.5) else { return }

        let edge = Self.edgeStrings.randomElement(using: &rng) ?? ""
        if !edge.isEmpty {
            field.typeText(edge)
        }
        dismissKeyboard(app: app)
    }

    private func performDismiss(app: XCUIApplication) {
        for label in ["Back", "Close", "Cancel", "Done"] {
            let button = app.buttons[label]
            if button.exists, button.isHittable, !isDenylisted(button) {
                button.tap()
                return
            }
        }
        let navBack = app.navigationBars.buttons.element(boundBy: 0)
        if navBack.exists, navBack.isHittable, !isDenylisted(navBack) {
            navBack.tap()
        }
    }

    private func performBackground(app: XCUIApplication) {
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
    }

    /// Terminates and relaunches with the seeding fixture, mirroring the
    /// initial launch in `testChaosMonkey`. Used to recover from a wedged
    /// screen rather than continuing to hammer a state the run can't escape.
    private func relaunch(app: XCUIApplication, fixture: String) {
        app.terminate()
        app.launchArguments = [fixture, "-lybUITestSuppressWhatsNew", "-lybUITestDisableBiometricLock"]
        app.launch()
        app.tap()
        popToRootIfNeeded(in: app)
    }

    /// A shared dev simulator/device has landed a fresh launch directly on
    /// `world_class_screen_metricDetail` left over from an earlier run
    /// instead of the fixture's intended root -- the account's own state
    /// persists across relaunches even though the process itself is fresh.
    /// Scoped to that one identifier (rather than any visible Back button)
    /// so a genuinely denylist-driven screen never gets popped by mistake.
    /// A fast no-op when already at the fixture-driven root.
    private func popToRootIfNeeded(in app: XCUIApplication) {
        for _ in 0..<5 {
            guard app.descendants(matching: .any)["world_class_screen_metricDetail"].exists else { return }
            let backButton = app.navigationBars.buttons["Back"]
            guard backButton.waitForExistence(timeout: 2), backButton.isHittable else { return }
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

    private func dismissKeyboard(app: XCUIApplication) {
        let candidates = [
            app.keyboards.buttons["Done"],
            app.buttons["mvp_keyboard_done_button"],
            app.buttons["mvp_keyboard_bottom_done_button"],
            app.toolbars.buttons["Done"]
        ]
        for candidate in candidates where candidate.exists {
            candidate.tap()
            return
        }
        // Fall back to a tap near the top of the screen, which dismisses the
        // keyboard on most screens without hitting a destructive control.
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)
        ).tap()
    }

    // MARK: - Element discovery

    private func interactiveElements(in app: XCUIApplication) -> [XCUIElement] {
        var elements: [XCUIElement] = []
        elements.append(contentsOf: app.buttons.allElementsBoundByIndex)
        elements.append(contentsOf: app.cells.allElementsBoundByIndex)
        elements.append(contentsOf: app.textFields.allElementsBoundByIndex)
        elements.append(contentsOf: app.switches.allElementsBoundByIndex)
        elements.append(contentsOf: app.sliders.allElementsBoundByIndex)
        elements.append(contentsOf: app.segmentedControls.allElementsBoundByIndex)
        elements.append(contentsOf: app.otherElements.allElementsBoundByIndex.prefix(40))

        return elements.filter { element in
            element.isHittable && !isDenylisted(element)
        }
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
