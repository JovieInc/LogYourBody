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

/// Mutable per-run telemetry threaded through every step, bundled into one
/// `inout` parameter so `runStep`'s signature doesn't grow every time a new
/// counter joins the stuck-episode detector.
private struct StepTelemetry {
    var stuckDetector = StuckDetector()
    var slowQueryCount = 0
    var layoutAnomalyMessages: [String] = []
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
        let rawExtraArgs = ProcessInfo.processInfo.environment["LYB_CHAOS_EXTRA_ARGS"] ?? ""
        let extraArgs = rawExtraArgs.split(separator: " ").map(String.init)
        let config = LaunchConfig(fixture: fixture, extraArgs: extraArgs)

        var rng = ChaosRNG(seed: seed)
        let app = XCUIApplication()
        var interruptionsDismissed = 0
        var anomalies: [String] = []
        var telemetry = StepTelemetry()

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

        app.launchArguments = config.launchArguments
        app.launch()
        app.tap()
        popToRootIfNeeded(in: app)

        for step in 0..<steps {
            do {
                try runStep(
                    step: step,
                    seed: seed,
                    app: app,
                    config: config,
                    rng: &rng,
                    telemetry: &telemetry
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
        anomalies.append(contentsOf: telemetry.layoutAnomalyMessages)

        var summaryLines = [
            "seed=\(seed) steps=\(steps) fixture=\(fixture) extraArgs=\(extraArgs.joined(separator: " "))",
            "systemAlertsDismissed=\(interruptionsDismissed)",
            "slowQueries(10-30s)=\(telemetry.slowQueryCount)",
            "layoutAnomalies=\(telemetry.layoutAnomalyMessages.count)",
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
        config: LaunchConfig,
        rng: inout ChaosRNG,
        telemetry: inout StepTelemetry
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
            dismissKeyboardForStep(app: app)
            return
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
        let layoutFindings = layoutAnomalies(candidates: snapshot.layoutCandidates, in: app)
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
            // Cap what actually gets typed (edgeStrings includes a 300-char
            // entry) so a field like chat_composer never accumulates enough
            // text to make a later step's keyboard-present handling slower
            // than it needs to be.
            field.typeText(String(edge.prefix(24)))
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
    private func relaunch(app: XCUIApplication, config: LaunchConfig) {
        app.terminate()
        app.launchArguments = config.launchArguments
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

    /// Runs in place of the general element query on any step where a
    /// keyboard is already up (see `runStep`). Prefers an explicit
    /// send/return affordance so a chat draft goes somewhere instead of
    /// sitting half-typed forever, then the composer's own "Close chat"
    /// exit (`home_chat_collapse`, DashboardViewLiquid+PhotoTimelineHUD.swift),
    /// then the generic keyboard dismissal as a last resort.
    private func dismissKeyboardForStep(app: XCUIApplication) {
        let candidates = [
            app.buttons["chat_send_button"],
            app.keyboards.buttons["return"],
            app.keyboards.buttons["Return"],
            app.keyboards.buttons["Send"],
            app.buttons["home_chat_collapse"]
        ]
        for candidate in candidates where candidate.exists && candidate.isHittable {
            candidate.tap()
            return
        }
        dismissKeyboard(app: app)
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
        let interactive = elements.filter { element in
            hasFiniteNonZeroFrame(element) && element.isHittable
                && element.elementType != .key && !isDenylisted(element)
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
    private func layoutAnomalies(candidates: [XCUIElement], in app: XCUIApplication) -> [String] {
        guard !app.alerts.firstMatch.exists else { return [] }
        let windowFrame = app.windows.firstMatch.frame
        guard windowFrame.width > 0, windowFrame.height > 0 else { return [] }

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

            guard element.isHittable else { continue }

            if frame.minX < windowFrame.minX - 1 || frame.maxX > windowFrame.maxX + 1
                || frame.minY < windowFrame.minY - 1 || frame.maxY > windowFrame.maxY + 1 {
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
