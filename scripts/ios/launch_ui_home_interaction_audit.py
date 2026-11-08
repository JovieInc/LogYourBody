"""Reject the hit-region and native-alert regressions seen by Launch Quality."""
from pathlib import Path
import re

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
        text = path.read_text(encoding="utf-8", errors="replace")
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
    text = path.read_text(encoding="utf-8", errors="replace")
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
        helper = helper_path.read_text().split("func activateSystemAlertMonitor()", 1)[-1].split(
            "func forwardActualXCTestContext()", 1
        )[0]
        if "coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()" not in helper:
            violations.append(violation(
                check="uitest.launch_interruption_tap", file=str(helper_path.relative_to(root)), line=1,
                detail="The interruption monitor helper must tap the screen corner above content.",
            ))
    for path in sorted(ui.glob("*.swift")):
        source = path.read_text(encoding="utf-8")
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


def check_home_interactions(root: Path, texts: dict, violations: list, violation) -> None:
    # Blocking Vision work must not exhaust Swift's cooperative worker pool.
    segmentation = root / "apps/ios/LogYourBody/Services/BackgroundRemovalService.swift"
    source = texts[segmentation]
    worker = source.split("func personMask(", 1)[-1].split("func personMaskGrid(", 1)[0]
    serial_queue = re.search(
        r'private let segmentationQueue = DispatchQueue\(\s*label: "[^"]+",\s*'
        r'qos: \.userInitiated\s*\)', source
    )
    required = ('try await withCheckedThrowingContinuation { continuation in',
                'segmentationQueue.async {', 'continuation.resume(with: Result {',
                'try handler.perform([request])', 'return result.pixelBuffer')
    if (not serial_queue or any(token not in worker for token in required)
            or 'Task.' in worker or worker.count('continuation.resume(') != 1):
        violations.append(violation(
            check="photo.segmentation_dispatch_worker", file=str(segmentation.relative_to(root)), line=1,
            detail="Run blocking segmentation on one serial dispatch queue and resume once with its result.",
        ))
    # Offline fixtures must stop the real monitor before it can overwrite their state.
    sync = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager+Part01.swift"
    setup = texts[sync].split("func setupNetworkMonitoring(", 1)[-1]
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
        scenario = dated.read_text().split(
            "func testDatedTimelineSwipeProvenanceOfflineRetryAndAccountIsolation()", 1
        )[-1]
        if '"-lybUITestHomeV2OfflineFixture"' not in scenario.split('let target =', 1)[0]:
            violations.append(violation(
                check="timeline.offline_retry_fixture", file=str(dated.relative_to(root)), line=1,
                detail="The offline retry scenario must explicitly request the offline fixture.",
            ))
    hud_path = root / "apps/ios/LogYourBody/Views/DashboardViewLiquid+PhotoTimelineHUD.swift"
    hud = texts[hud_path]
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
            + re.escape(f'.accessibilityIdentifier("{identifier}")'), texts[settings]
        ):
            violations.append(violation(
                check="settings.logout_alert_one_element", file=str(settings.relative_to(root)), line=1,
                detail="Combine each logout action into one accessibility element.",
            ))

    check_character_type_keyboard_focus(root, violations, violation)
    check_nested_launch_time_allowance(root, violations, violation)
    check_launch_interruption_taps(root, violations, violation)

    ui_path = root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
    if not ui_path.is_file():
        return
    helper = ui_path.read_text().split("private func hittableLogoutAction(", 1)[-1].split(
        "func testProfileEditorProvidesAnEscapeRoute", 1
    )[0]
    required = ('alert.buttons.matching(identifier: identifier)', '$0.label == label',
                '$0.isEnabled', '$0.isHittable', 'children(matching: .button).count == 0',
                'seen.insert(key).inserted', 'leaves.count == 1 ? leaves.first : nil',
                'frame.minX', 'frame.minY', 'frame.width', 'frame.height')
    if (any(token not in helper for token in required)
            or any(token in helper for token in ('firstMatch.exists', 'XCTWaiter.wait'))):
        violations.append(violation(
            check="settings.logout_alert_action_selection", file=str(ui_path.relative_to(root)), line=1,
            detail="Select one enabled, hittable logout leaf, collapsing same-frame aliases without blocking queries.",
        ))
