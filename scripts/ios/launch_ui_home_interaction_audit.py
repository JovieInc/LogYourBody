"""Home-column and synthetic-typing checks for the launch UI regression audit."""

from __future__ import annotations

from pathlib import Path
import re

from launch_ui_timeline_audit import text_for


def function_body(text: str, name: str, next_name: str) -> str:
    if f"func {name}" not in text or f"func {next_name}" not in text:
        return ""
    chunk = text.split(f"func {name}", 1)[1].split(f"func {next_name}", 1)[0]
    return chunk.split("{", 1)[1] if "{" in chunk else ""


def contribute(root: Path, app_dir: Path, violations: list, violation, _line_number) -> None:
    check_home_interactions(root, violations, violation)
    check(root, app_dir, violations, function_body, violation)
    before = len(violations)
    check_person_mask_executor(root, app_dir, violations, violation)
    if len(violations) > before:
        violations.append(violation(
            check="photo.segmentation_dispatch_worker",
            file=str((app_dir / "Services/BackgroundRemovalService.swift").relative_to(root)), line=1,
            detail="Keep blocking segmentation on a serial Dispatch queue.",
        ))
    check_logout_alert(root, violations, violation)
    check_profile_logout_presentation(root, violations, violation)
    check_ui_test_offline_fixture(root, violations, violation)


def check_person_mask_executor(root: Path, app_dir: Path, violations: list, violation) -> None:
    """Blocking Vision segmentation must leave the Swift cooperative pool available."""
    path = app_dir / "Services/BackgroundRemovalService.swift"
    text = text_for(path)
    body = text.split("func personMask(", 1)[-1].split("func personMaskGrid(", 1)[0]
    queue = re.search(
        r"segmentationQueue\s*:\s*DispatchQueue\s*=\s*DispatchQueue\(([^)]*)\)", text
    )
    if ("Task.detached" in body or "withCheckedThrowingContinuation" not in body
            or "segmentationQueue.async {" not in body or queue is None
            or ".concurrent" in queue.group(1) or body.count("continuation.resume(") != 1):
        violations.append(violation(
            check="photo.segmentation_dispatch_executor",
            file=str(path.relative_to(root)), line=1,
            detail="Run blocking person segmentation asynchronously on a serial Dispatch queue, outside Swift's cooperative pool.",
        ))


def check(root: Path, app_dir: Path, violations: list, function_body, violation) -> None:
    """The provenance chip stays above the weekly prompt, and typed characters refocus."""
    surface = app_dir / "Views/HomeV2/HomeV2Surface.swift"
    text = text_for(surface)
    body = text.split("var body: some View {", 1)[-1].split("private var systemBanner", 1)[0]
    numbers = text.split("private var photoNumberBlock: some View {", 1)[-1].split(
        "private var ffmiSummary", 1
    )[0]
    prompt = "WeeklyPhotoCheckInPrompt("
    chip = "HomeV2ProvenanceChip("
    rendered = body.replace("photoNumberBlock", numbers, 1)
    prompt_at = rendered.find(prompt)
    chip_at = rendered.find(chip)
    if prompt_at < 0 or chip_at < 0 or prompt_at < chip_at:
        violations.append(violation(
            check="home.provenance_chip_precedes_weekly_prompt",
            file=str(surface.relative_to(root)),
            line=1,
            detail="Place the weekly photo prompt after the provenance chip so the chip stays above the dock.",
        ))

    ui_tests = root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
    if not ui_tests.is_file():
        return
    loop = function_body(
        text_for(ui_tests),
        "submitSyntheticChatQuestion",
        "enteredSyntheticQuestion",
    )
    character = loop.split("for character in addition", 1)[-1] if "for character in addition" in loop else ""
    type_at = character.find("typeText(")
    focus_at = character.find("keyboard.exists")
    if type_at < 0 or focus_at < 0 or focus_at > type_at:
        violations.append(violation(
            check="chat.synthetic_typing_refocuses",
            file=str(ui_tests.relative_to(root)),
            line=1,
            detail="Refocus the composer when the keyboard drops before each synthetic character.",
        ))


def check_logout_alert(root: Path, violations: list, violation) -> None:
    """Duplicate accessibility wrappers must resolve to one physical alert action."""
    path = root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
    if not path.is_file():
        return
    text = text_for(path)
    helper = function_body(text, "hittableLogoutAction", "testProfileEditorProvidesAnEscapeRoute")
    journey = function_body(text, "testProfileLogoutSignsOutFromPushedDetail", "hittableLogoutAction")
    required = (
        "alert.buttons.matching(identifier: identifier)",
        "$0.label == label && $0.isEnabled && $0.isHittable",
        "reduce(into: [XCUIElement]())",
        "!unique.contains(where: { $0.frame == action.frame })",
        "unique.append(action)",
        "interactiveActions().count == 1",
        "actions.count == 1 ? actions.first : nil",
    )
    outcomes = (
        'identifier: "settings_logout_cancel", label: "Cancel"',
        "cancelLogout.tap()",
        "XCTAssertTrue(logoutConfirmation.waitForNonExistence(timeout: 5))",
        "XCTAssertTrue(logoutButton.exists)",
        'XCTAssertFalse(app.buttons["continueWithAppleButton"].exists)',
        'identifier: "settings_logout_confirm", label: "Log Out"',
        "confirmLogout.tap()",
        'XCTAssertTrue(app.buttons["continueWithAppleButton"].waitForExistence(timeout: 8))',
    )
    if (any(token not in helper for token in required)
            or "descendants(matching: .button)" in helper
            or any(token not in journey for token in outcomes)):
        violations.append(violation(
            check="settings.logout_alert_action_selection", file=str(path.relative_to(root)), line=1,
            detail="Require one enabled, hittable physical logout action.",
        ))
        violations.append(violation(
            check="logout.alert_action_identity", file=str(path.relative_to(root)), line=1,
            detail="Collapse identical alert action frames, reject distinct matches, and verify Cancel and Log Out outcomes.",
        ))


def check_profile_logout_presentation(root: Path, violations: list, violation) -> None:
    """The pushed profile screen owns logout confirmation and fills the row hit target."""
    button_path = root / "apps/ios/LogYourBody/SettingsComponents.swift"
    header_path = root / "apps/ios/LogYourBody/Views/PreferencesView+Header.swift"
    prefs_path = root / "apps/ios/LogYourBody/Views/PreferencesView.swift"
    account_path = root / "apps/ios/LogYourBody/Views/PreferencesView+AccountSection.swift"
    if not all(path.is_file() for path in (button_path, header_path, prefs_path, account_path)):
        return
    row = text_for(button_path).split("struct SettingsButtonRow", 1)[-1].split(
        "// MARK: - Picker Row", 1
    )[0]
    button = row.split("Button(role: role, action: action) {", 1)
    inside = button[1].split("\n        }", 1)[0] if len(button) == 2 else ""
    header = text_for(header_path)
    screen = header.split("struct ProfileLogoutScreen", 1)
    screen_body = screen[1] if len(screen) == 2 else ""
    before_screen = screen[0] if screen_body else header
    required_inside = (
        ".frame(maxWidth: .infinity, minHeight: SettingsLayout.rowMinHeight, alignment: .leading)",
        ".contentShape(Rectangle())",
    )
    required_screen = (
        "private let authManager: AuthManager",
        "self.authManager = authManager",
        "@State private var showingLogoutConfirmation = false",
        '"Log out of LogYourBody?"',
        "isPresented: $showingLogoutConfirmation",
        "settings_logout_confirm",
        "settings_logout_cancel",
        "await authManager.logout()",
    )
    if (any(token not in inside for token in required_inside)
            or ".frame(minHeight: SettingsLayout.rowMinHeight, alignment: .leading)" in row
            or "ProfileLogoutScreen(authManager: authManager) { showingLogoutConfirmation in" not in before_screen
            or "$showingLogoutConfirmation" in before_screen
            or "@State var showingLogoutConfirmation" in text_for(prefs_path)
            or "showingLogoutConfirmation.wrappedValue = true" not in text_for(account_path)
            or any(token not in screen_body for token in required_screen)):
        violations.append(violation(
            check="logout.profile_confirmation_hit_target",
            file=str(header_path.relative_to(root)),
            line=1,
            detail="Own logout confirmation on the pushed profile screen and fill the settings button hit target.",
        ))


def check_ui_test_offline_fixture(root: Path, violations: list, violation) -> None:
    """A satisfied network path must not clear the UI-test offline fixture."""
    app = root / "apps/ios/LogYourBody/LogYourBodyApp.swift"
    sync = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager.swift"
    monitor = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager+Part01.swift"
    if not app.is_file() or not sync.is_file() or not monitor.is_file():
        return
    sync_text = text_for(sync)
    fixture = text_for(app).split("func applyPaidMVPUITestFixtureIfNeeded", 1)[-1].split(
        "func writeHomeV2FixturePhoto", 1
    )[0]
    policy = sync_text.split("static func online", 1)[-1]
    applicator = sync_text.split("func handleNetworkPathUpdate", 1)[-1].split(
        "var syncTimer", 1
    )[0]
    helper = ""
    if "func applyOfflineUITestFixture" in sync_text:
        helper = sync_text.split("func applyOfflineUITestFixture", 1)[1].split("#endif", 1)[0]
    # A shared helper counts only when it still pins offline. A direct assignment does too.
    offline_pinned = "isOnline = false" in fixture or (
        "applyOfflineUITestFixture()" in fixture and "isOnline = false" in helper
    )
    handler = text_for(monitor).split("func setupNetworkMonitoring", 1)[-1].split(
        "func setupAuthListener", 1
    )[0]
    required = (
        "-lybUITestPaidMVPFixture",
        "-lybUITestWeightLoggerMVPFixture",
        "-lybUITestPaywallFixture",
        "-lybUITestPaywallPlansFixture",
        "-lybUITestFullDashboardFixture",
        "-lybUITestPhotoTimelineHUDFixture",
        "-lybUITestBodyScoreOnboardingFixture",
        "-lybUITestBodyScoreFirstPhotoFixture",
    )
    held = applicator.find("guard !usesOfflineUITestFixture")
    assigned = applicator.find("self.isOnline = Self.online(isOnline)")
    if (any(token not in fixture or token not in policy for token in required)
            or "!RealtimeSyncManager.online(true, arguments)" not in fixture
            or "return !fixtureForcesOffline" not in policy
            or not offline_pinned
            or held < 0 or assigned < 0 or "return" not in applicator[held:assigned]
            or "handleNetworkPathUpdate(isOnline: path.status == .satisfied)" not in handler
            # A merge must not dispatch both parent implementations for one path.
            or handler.count("handleNetworkPathUpdate(") != 1
            or "applyNetworkPathStatus(" in handler
            or "isOnline = path.status" in handler):
        violations.append(violation(
            check="sync.ui_test_offline_survives_path",
            file=str(monitor.relative_to(root)),
            line=1,
            detail="A UI-test offline fixture must survive a satisfied network path.",
        ))


_CHARACTER_LOOP = re.compile(r"for\s+(?P<name>[A-Za-z_]\w*)\s+in\s+[^{\n]+\{")
_NESTED_TEST_CALL = re.compile(r"\b(test[A-Z]\w*)\s*\(")
_TEST_FUNC = re.compile(r"\bfunc\s+(test[A-Za-z0-9_]+)\s*\(")
_BRACE_TOKEN = re.compile(
    r'"(?:\\[\s\S]|[^"\\])*(?:"|\\?\Z)|//[^\n]*(?:\n|\Z)|/\*[\s\S]*?(?:\*/|\Z)|[{}]'
)


def _balanced_end(text, open_brace):
    """Index of the brace matching open_brace, skipping strings and comments."""
    depth = 0
    # Trace structural tokens, not every source character, on the coverage path.
    for match in _BRACE_TOKEN.finditer(text, open_brace):
        token = match.group()
        if token == "{":
            depth += 1
        elif token == "}":
            depth -= 1
            if depth == 0:
                return match.start()
    return len(text) - 1


def check_character_type_keyboard_focus(root, violations, violation):
    """A paced character loop must regain keyboard focus before every typeText."""
    ui = root / "apps/ios/LogYourBodyUITests"
    if not ui.is_dir():
        return
    for path in sorted(ui.rglob("*.swift")):
        text = text_for(path)
        for match in _CHARACTER_LOOP.finditer(text):
            name = match.group("name")
            open_brace = match.end() - 1
            body = text[open_brace:_balanced_end(text, open_brace) + 1]
            typed = body.find(f"String({name})")
            type_at = body.find(".typeText(")
            if typed < 0 or type_at < 0 or typed < type_at:
                continue
            prelude = body[:type_at]
            owner = text.rfind("func ", 0, match.start())
            focus_window = text[0 if owner < 0 else owner:open_brace + type_at]
            if "hasKeyboardFocus == true" not in focus_window or (
                "hasKeyboardFocus == true" not in prelude and "if !focused.exists" not in prelude
            ):
                violations.append(violation(
                    check="uitest.character_type_keyboard_focus",
                    file=str(path.relative_to(root)),
                    line=text.count("\n", 0, match.start()) + 1,
                    detail="Re-check hasKeyboardFocus before each character typeText. The field can keep its value and still lose the keyboard.",
                ))


def check_nested_launch_time_allowance(root, violations, violation):
    """Nested launch scenarios need the audit maximum before XCTest's 2-minute kill."""
    path = root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
    if not path.is_file():
        return
    text = text_for(path)
    for match in _TEST_FUNC.finditer(text):
        brace = text.find("{", match.end())
        if brace < 0 or brace - match.end() > 80:
            continue
        body = text[brace:_balanced_end(text, brace) + 1]
        call = next((
            candidate for candidate in _NESTED_TEST_CALL.finditer(body)
            if candidate.group(1) != match.group(1)
            and "func " not in body[max(0, candidate.start() - 6):candidate.start()]
        ), None)
        if call and "executionTimeAllowance = 180" not in body[:call.start()]:
            violations.append(violation(
                check="uitest.nested_launch_time_allowance",
                file=str(path.relative_to(root)),
                line=text.count("\n", 0, match.start()) + 1,
                detail="Set executionTimeAllowance = 180 before running other test methods. XCTest rounds the 90s default up to 2 minutes.",
            ))


def check_launch_interruption_taps(root, violations, violation):
    """Activating a monitor must not tap an arbitrary control at app center."""
    ui = root / "apps/ios/LogYourBodyUITests"
    helper_path = ui / "LogYourBodyUITestsLaunchTests.swift"
    if helper_path.is_file():
        helper = text_for(helper_path).split("func activateSystemAlertMonitor()", 1)[-1].split(
            "func forwardActualXCTestContext()", 1
        )[0]
        if "coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()" not in helper:
            violations.append(violation(
                check="uitest.launch_interruption_tap", file=str(helper_path.relative_to(root)), line=1,
                detail="The interruption monitor helper must tap the screen corner above content.",
            ))
    for path in sorted(ui.glob("*.swift")):
        source = text_for(path)
        pattern = re.compile(
            r"\b(?P<app>\w+)\.launch\(\)(?:\s|//[^\n]*\n|/\*[\s\S]*?\*/)*"
            r"(?P=app)\.tap\(\)"
        )
        for match in pattern.finditer(source):
            violations.append(violation(
                check="uitest.launch_interruption_tap", file=str(path.relative_to(root)),
                line=source.count("\n", 0, match.start()) + 1,
                detail="Activate the interruption monitor with the screen-corner helper; an app-center tap can navigate away from the fixture.",
            ))


def check_viewer_history_navigation(root, violations, violation):
    """Wait for the sidebar destination before opening imported viewer history."""
    path = root / "apps/ios/LogYourBodyUITests/HomeV2PhotoViewerLayoutUITests.swift"
    if not path.is_file():
        return
    source = text_for(path)
    start = source.find("private func launch(")
    brace = source.find("{", start) if start >= 0 else -1
    helper = source[start:_balanced_end(source, brace) + 1] if brace >= 0 else ""
    required = ('let entries = app.buttons["home_v2_sidebar_entries"]',
                'guard entries.waitForExistence(timeout: 8) else {', 'entries.tap()')
    wait = helper.find(required[1])
    brace = helper.find("{", wait) if wait >= 0 else -1
    end = _balanced_end(helper, brace) if brace >= 0 else -1
    failure = helper[brace:end] if brace >= 0 else ""
    if (any(token not in helper for token in required)
            or any(token not in failure for token in ('XCTFail(', 'return app'))
            or helper.find('entries.tap()') < end or 'label == %@' in helper):
        violations.append(violation(
            check="uitest.viewer_history_navigation", file=str(path.relative_to(root)), line=1,
            detail="Open viewer history through the sidebar Entries identifier after its bounded existence wait.",
        ))


def check_progress_share_readiness(root, violations, violation):
    """Read each metric only after selection, then await its exact share title."""
    path = root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
    if not path.is_file():
        return
    source = text_for(path)
    start = source.find("func testProgressShareKeepsSelectedMetricAndVisibleValue()")
    brace = source.find("{", start) if start >= 0 else -1
    body = source[brace:_balanced_end(source, brace) + 1] if brace >= 0 else ""
    ordered = (
        'let tab = app.buttons["home_v2_progress_tab_\\(identifier)"]',
        'tab.tap()',
        'NSPredicate(format: "isSelected == true"), object: tab)',
        'XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)',
        'let expectedValue = value.label',
        'share.tap()',
        'XCTAssertTrue(app.staticTexts["Share \\(title)"].waitForExistence(timeout: 5))',
        'XCTAssertEqual(summary.staticTexts["body_score_share_score"].label, expectedValue)',
    )
    positions = [body.find(token) for token in ordered]
    if -1 in positions or positions != sorted(positions):
        violations.append(violation(
            check="uitest.progress_share_readiness", file=str(path.relative_to(root)), line=1,
            detail="Await the selected metric before capturing its value, and the exact share title before checking its card.",
        ))


def check_home_interactions(root, violations, violation):
    # Offline fixtures must stop the real monitor before it can overwrite their state.
    sync = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager+Part01.swift"
    setup = text_for(sync).split("func setupNetworkMonitoring(", 1)[-1]
    offline_guard = re.search(
        r'#if DEBUG\s+if arguments.contains\(HomeV2SystemStatePolicy.offlineFixtureArgument\) '
        r'\{\s+applyOfflineUITestFixture\(\)\s+return\s+\}\s+#endif', setup
    )
    if (not offline_guard or 'arguments: [String] = ProcessInfo.processInfo.arguments' not in setup
            or any(setup.find(token) < offline_guard.end() for token in (
                'networkMonitor.start(', 'networkMonitor.pathUpdateHandler ='
            ))):
        violations.append(violation(
            check="timeline.offline_fixture_network", file=str(sync.relative_to(root)), line=1,
            detail="Keep offline fixtures DEBUG-only and return before starting the live network monitor.",
        ))
    dated = root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests+DatedTimeline.swift"
    if dated.is_file():
        scenario = text_for(dated).split(
            "func testDatedTimelineSwipeProvenanceOfflineRetryAndAccountIsolation()", 1
        )[-1]
        if '"-lybUITestHomeV2OfflineFixture"' not in scenario.split('let target =', 1)[0]:
            violations.append(violation(
                check="timeline.offline_retry_fixture", file=str(dated.relative_to(root)), line=1,
                detail="The offline retry scenario must explicitly request the offline fixture.",
            ))
    hud_path = root / "apps/ios/LogYourBody/Views/DashboardViewLiquid+PhotoTimelineHUD.swift"
    hud = text_for(hud_path)
    body = hud.split("var photoTimelineRoot: some View {", 1)[-1].split(
        "private var photoTimelineToolbarTitle", 1
    )[0]
    content = body.split("photoTimelineHomeContent\n", 1)[-1].split("if !isHomeV2CheckIn", 1)[0]
    parent = body.split("if !isHomeV2CheckIn", 1)[-1]
    edge = ".highPriorityGesture(photoTimelineSwipe)"
    overlay = content.split(".overlay(alignment: .leading)", 1)[-1].split("\n        }", 1)[0]
    if (edge not in overlay or edge in parent
            or edge in body.split("photoTimelineHomeContent", 1)[0]
            or ".contentShape(Rectangle())" not in overlay
            or ".padding(" in overlay.split(edge, 1)[0]):
        violations.append(violation(
            check="timeline.edge_swipe_excludes_header", file=str(hud_path.relative_to(root)), line=1,
            detail="Attach the edge swipe to content below the header, with its hit shape before padding.",
        ))

    settings = root / "apps/ios/LogYourBody/Views/PreferencesView+Header.swift"
    for identifier in ("settings_logout_confirm", "settings_logout_cancel"):
        if not re.search(
            r'\.accessibilityElement\(children: \.combine\)\s*'
            + re.escape(f'.accessibilityIdentifier("{identifier}")'), text_for(settings)
        ):
            violations.append(violation(
                check="settings.logout_alert_one_element", file=str(settings.relative_to(root)), line=1,
                detail="Combine each logout action into one accessibility element.",
            ))

    check_character_type_keyboard_focus(root, violations, violation)
    check_nested_launch_time_allowance(root, violations, violation)
    check_launch_interruption_taps(root, violations, violation)
    check_viewer_history_navigation(root, violations, violation)
    check_progress_share_readiness(root, violations, violation)
