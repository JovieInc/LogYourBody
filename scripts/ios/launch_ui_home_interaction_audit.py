"""Reject the hit-region and native-alert regressions seen by Launch Quality."""
from pathlib import Path
import re


def check_home_interactions(root: Path, texts: dict, violations: list, violation) -> None:
    # Offline fixtures must stop the real monitor before it can overwrite their state.
    sync = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager.swift"
    setup = texts[sync].split("func setupNetworkMonitoring(", 1)[-1]
    offline_guard = re.search(
        r'#if DEBUG\s+if arguments.contains\(HomeV2SystemStatePolicy.offlineFixtureArgument\) '
        r'\{\s+isOnline = false\s+syncStatus = \.offline\s+return\s+\}\s+#endif', setup
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
