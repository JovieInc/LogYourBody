"""Shared real-source fixtures for the launch UI audit behavior suite."""

import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
# The coverage tracer counts every Python line. Copying the Swift tree in
# this process pushes the required suite past its 30s limit.
_COPY_APP_SWIFT_TREE = """
import shutil
import sys
from pathlib import Path
root, dest = (Path(arg) for arg in sys.argv[1:])
for source in (root / "apps/ios/LogYourBody").rglob("*.swift"):
    target = dest / source.relative_to(root)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
"""
SPEC = importlib.util.spec_from_file_location(
    "launch_ui_audit", ROOT / "scripts/ios/launch-ui-regression-audit.py"
)
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)
from launch_ui_home_interaction_audit import (
    _balanced_end, check_launch_interruption_taps, check_viewer_history_navigation,
    check_progress_share_readiness,
)  # noqa: E402


class BraceScannerTests(unittest.TestCase):
    def test_brace_scanner_preserves_strings_comments_and_unclosed_input(self):
        cases = [
            ('prefix { nested { value } }', 7, ' suffix'),
            (r'{ "escaped \" }" { value } }', 0, ' suffix'),
            ('{ // } ignored\n /* { ignored } */ { value } }', 0, ' suffix'),
            ('{ "unterminated }', 0, ''),
            ('{ /* unterminated }', 0, ''),
            ('{ // unterminated }', 0, ''),
        ]
        for source, start, suffix in cases:
            with self.subTest(source=source):
                self.assertEqual(_balanced_end(source + suffix, start), len(source) - 1)

    def test_brace_scanner_traces_tokens_instead_of_source_characters(self):
        # Keep coverage cost bounded without a wall-clock benchmark or a larger CI timeout.
        source = '{' + ' ' * 20_000 + '"' + '}' * 20_000 + '" /* { */ // }\n}'
        events = 0

        def count_lines(frame, event, _argument):
            nonlocal events
            if event == 'line' and frame.f_code is _balanced_end.__code__:
                events += 1
            return count_lines

        previous = sys.gettrace()
        try:
            sys.settrace(count_lines)
            end = _balanced_end(source, 0)
        finally:
            sys.settrace(previous)
        self.assertEqual(end, len(source) - 1)
        self.assertLess(events, 100, 'Brace scanning must trace tokens, not source characters')


class LaunchUIAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._swift_template = tempfile.TemporaryDirectory()
        subprocess.run(
            [sys.executable, "-c", _COPY_APP_SWIFT_TREE, str(ROOT), cls._swift_template.name],
            check=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls._swift_template.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "apps/ios/LogYourBody"
        subprocess.run(
            ["cp", "-a", str(Path(self._swift_template.name) / "apps"), str(self.root)],
            check=True,
        )

    def replace(self, relative_path, before, after):
        path = self.app / relative_path
        source = path.read_text()
        self.assertIn(before, source)
        path.write_text(source.replace(before, after))

    def run_audit(self):
        output = self.root / "audit-output"
        with patch.object(sys, "argv", ["audit", "--root", str(self.root), "--artifact-dir", str(output)]):
            with contextlib.redirect_stdout(io.StringIO()):
                result = AUDIT.main()
        return result, output

    def assert_rejected(self, check):
        result, output = self.run_audit()
        self.assertEqual(result, 1)
        self.assertIn(check, "\n".join(path.read_text() for path in output.glob("*.json")))


class PatternScanTests(LaunchUIAuditTests):
    def test_native_discovery_reuses_app_paths_and_keeps_exact_file_order(self):
        directories = ("LogYourBody", "LogYourBodyTests", "LogYourBodyUITests", "LogYourBodyWidget")
        for directory in directories[1:]:
            path = self.root / "apps/ios" / directory / "Discovery.swift"
            path.parent.mkdir(parents=True)
            path.write_text("struct Discovery {}\n")
        expected = sorted(path for directory in directories
                          for path in (self.root / "apps/ios" / directory).rglob("*.swift"))
        rglob = Path.rglob
        visited = []

        def tracked_rglob(path, pattern):
            visited.append(path)
            return rglob(path, pattern)

        with patch.object(Path, "rglob", tracked_rglob), \
                patch.object(Path, "__lt__", side_effect=AssertionError("Sort path parts once")), \
                patch.object(AUDIT, "read_sources", wraps=AUDIT.read_sources) as read:
            self.assertEqual(self.run_audit()[0], 0)
        self.assertEqual(read.call_args.args[0], expected)
        self.assertEqual(visited.count(self.app), 1, "Do not rediscover the same app tree")

    def test_full_tree_patterns_skip_irrelevant_sources_without_changing_findings(self):
        scan = AUDIT.add_pattern_violations
        with patch.object(AUDIT, "add_pattern_violations", wraps=scan) as calls:
            self.assertEqual(self.run_audit()[0], 0)
        cases = {
            "swift.explicit_geometry_nonfinite": [
                "let point = CGPoint(\n x: +.infinity, y: -.nan)\n",
                "let size = CGSize(width: .nan, height: 1)\n",
                "let safe = CGPoint(x: 0, y: 0) // .infinity is only a comment\n",
            ],
            "overscroll.no_large_fake_bottom_spacers": [
                "Spacer \n (minLength: 120)\n",
                "Spacer(minLength: 8)\n",
            ],
            "timeline.no_bottom_stats_card": [
                'let identifier = "photo_timeline_hud_stats_button"\n',
                'let identifier = "photo_timeline_hud_stats"\n',
            ],
        }
        checked = set()
        for call in calls.call_args_list:
            arguments = call.kwargs.copy()
            check = arguments["check"]
            if check not in cases:
                continue
            checked.add(check)
            sources = ["struct Irrelevant { let value = 0 }\n" * 100] * 100 + cases[check]
            texts = {self.root / f"Fixture{index}.swift": text
                     for index, text in enumerate(sources)}
            pattern = arguments["pattern"]
            expected = [AUDIT.AuditViolation(
                check=check, file=str(path.relative_to(self.root)),
                line=AUDIT.line_number(text, match.start()), detail=arguments["detail"],
            ) for path, text in texts.items() for match in pattern.finditer(text)]
            scanned = []

            class CountedPattern:
                def finditer(self, text):
                    scanned.append(text)
                    return pattern.finditer(text)

            findings = []
            arguments.update(paths=list(texts), texts=texts, pattern=CountedPattern(),
                             violations=findings)
            scan(**arguments)
            with self.subTest(check=check):
                self.assertEqual(findings, expected)
                self.assertTrue(expected, "The negative control must contain a violation")
                self.assertLessEqual(len(scanned), len(cases[check]),
                                     "Full-tree regexes must skip irrelevant source bytes")
        self.assertEqual(checked, set(cases))


class LaunchExecutionAuditTests(unittest.TestCase):
    def test_progress_share_waits_for_selection_and_exact_title_before_readback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            relative = "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
            path = root / relative
            path.parent.mkdir(parents=True)
            original = (ROOT / relative).read_text()

            def findings():
                violations = []
                check_progress_share_readiness(root, violations, AUDIT.AuditViolation)
                return [item.check for item in violations]

            self.assertEqual(findings(), [])  # Missing optional fixture tree.
            path.write_text(original)
            self.assertEqual(findings(), [])
            wait = 'XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)'
            title = 'XCTAssertTrue(app.staticTexts["Share \\(title)"].waitForExistence(timeout: 5))'
            cases = [
                ('NSPredicate(format: "isSelected == true"), object: tab)',
                 'NSPredicate(format: "exists == true"), object: tab)'),
                (wait, ''),
                (wait, 'let prematureValue = value.label\n            ' + wait),
                (title, 'XCTAssertTrue(app.staticTexts["Share \\(title)"].exists)'),
                (title, 'XCTAssertTrue(app.staticTexts["Share Body Score"].waitForExistence(timeout: 5))'),
                ('func testProgressShareKeepsSelectedMetricAndVisibleValue()', 'func missingShareTest()'),
            ]
            for before, after in cases:
                with self.subTest(before=before, after=after):
                    self.assertIn(before, original)
                    mutated = original.replace(before, after, 1)
                    if 'prematureValue' in mutated:
                        mutated = mutated.replace('let expectedValue = value.label',
                                                  'let expectedValue = prematureValue', 1)
                    path.write_text(mutated)
                    self.assertEqual(findings(), ["uitest.progress_share_readiness"])

    def test_launch_monitor_rejects_center_taps_and_preserves_targeted_actions(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        ui = root / "apps/ios/LogYourBodyUITests"
        ui.mkdir(parents=True)
        path = ui / "LaunchFixture.swift"
        path.write_text('app.launch()\napp.activateSystemAlertMonitor()\napp.buttons["Menu"].tap()\n')
        helper = ui / "LogYourBodyUITestsLaunchTests.swift"
        original = (ROOT / "apps/ios/LogYourBodyUITests/LogYourBodyUITestsLaunchTests.swift").read_text()
        helper.write_text(original)

        def findings(source_root):
            violations = []
            check_launch_interruption_taps(source_root, violations, AUDIT.AuditViolation)
            return [finding.check for finding in violations]

        self.assertEqual(findings(ROOT), [])
        self.assertEqual(findings(root), [])
        helper.write_text(original.replace("CGVector(dx: 0.02, dy: 0.02)", "CGVector(dx: 0.5, dy: 0.5)"))
        self.assertEqual(findings(root), ["uitest.launch_interruption_tap"])
        helper.write_text(original)
        for separator in ("\n", "\n// trigger the monitor\n", " /* monitor */\n"):
            path.write_text(f"application.launch(){separator}application.tap()\n")
            self.assertEqual(findings(root), ["uitest.launch_interruption_tap"])

    def test_viewer_history_navigation_waits_for_the_sidebar_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            relative = "apps/ios/LogYourBodyUITests/HomeV2PhotoViewerLayoutUITests.swift"
            path = root / relative
            path.parent.mkdir(parents=True)
            original = (ROOT / relative).read_text()

            def findings():
                violations = []
                check_viewer_history_navigation(root, violations, AUDIT.AuditViolation)
                return [item.check for item in violations]

            self.assertEqual(findings(), [])  # Missing optional fixture tree.
            path.write_text(original)
            self.assertEqual(findings(), [])
            cases = [
                ('app.buttons["home_v2_sidebar_entries"]',
                 'app.buttons.matching(NSPredicate(format: "label == %@", "Entries")).firstMatch'),
                ('guard entries.waitForExistence(timeout: 8) else {', 'if false {'),
                ('return app\n        }\n        entries.tap()', 'entries.tap()\n        }'),
                ('private func launch(', 'private func wrongLaunch('),
            ]
            for before, after in cases:
                with self.subTest(before=before):
                    self.assertIn(before, original)
                    path.write_text(original.replace(before, after, 1))
                    self.assertEqual(findings(), ["uitest.viewer_history_navigation"])

    def test_ui_command_uses_remaining_audit_budget_without_extending_deadline(self):
        source = (ROOT / "scripts/ios/launch-quality-audit.sh").read_text()
        start = source.index('UI_RESULT_BUNDLES=("$UI_RESULT_BUNDLE")')
        end = source.index('XCODEBUILD_COMMAND_TIMEOUT_SECONDS="$UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS" run_xcodebuild_test', start)
        budget = source[start:end]
        workflow = (ROOT / ".github/workflows/ios-quality.yml").read_text()
        self.assertIn("timeout-minutes: 52", workflow.split("- name: Run launch quality audit", 1)[1])
        cases = [(1200, None, 0, "1860"), (1472, None, 0, "1588"),
                 (1472, "2000", 0, "1588"), (1472, "1200", 0, "1200"),
                 (3060, None, 124, ""), (3120, None, 124, "")]
        for elapsed, override, status, expected in cases:
            with self.subTest(elapsed=elapsed, override=override):
                script = 'set -euo pipefail\nAUDIT_STARTED_AT=0\nUI_RESULT_BUNDLE=fixture\n'
                script += f'date() {{ echo {elapsed}; }}\n'
                if override is not None:
                    script += f'UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS={override}\n'
                result = subprocess.run(
                    ["bash", "-c", script + budget + '\nprintf "%s" "$UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS"'],
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(result.stdout, expected)


class TimelineAndTypingAuditTests(LaunchUIAuditTests):
    """Cases extracted so the behavior module stays within the 500-line ratchet."""

    def test_timeline_position_uses_the_injected_calendar_day(self):
        calculator = self.app / "Helpers/TimelineCalculator.swift"
        original = calculator.read_text()
        self.assertIn("now: Date = Date()", original)
        self.assertIn("if point.date >= thirtyDaysAgo {", original)
        tests = self.root / "apps/ios/LogYourBodyTests/TimelineCalculatorTests.swift"
        tests.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "apps/ios/LogYourBodyTests/TimelineCalculatorTests.swift", tests)
        self.assertEqual(self.run_audit()[0], 0)

        tests.write_text("let date = now.addingTimeInterval(-daysAgo * 24 * 60 * 60)\n")
        self.assert_rejected("timeline.elapsed_day_offset")
        self.assert_rejected("timeline.fallback_hour_regression")

        tests.unlink()
        calculator.write_text(original.replace(
            "if point.date >= thirtyDaysAgo {",
            "if point.date >= thirtyDaysAgo {\n            let now = Date()",
            1,
        ))
        self.assert_rejected("timeline.injected_calendar_day")

        calculator.write_text(original.replace("now: Date = Date(),\n        ", "", 1))
        self.assert_rejected("timeline.injected_calendar_day")

    def test_character_typing_regains_focus_and_nested_launch_tests_get_time(self):
        ui = self.root / "apps/ios/LogYourBodyUITests"
        ui.mkdir(parents=True)
        shutil.copyfile(ROOT / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift", ui / "LogYourBodyUITests.swift")
        shutil.copyfile(
            ROOT / "apps/ios/LogYourBodyUITests/ChaosMonkeyUITests.swift", ui / "ChaosMonkeyUITests.swift"
        )
        self.assertEqual(self.run_audit()[0], 0)

        chat = ui / "LogYourBodyUITests.swift"
        original = chat.read_text()
        focus = (
            '.matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch\n'
            "                    if !focused.exists {\n"
            "                        if prefix.isEmpty {\n"
            "                            composer.tap()\n"
            "                        } else {\n"
            "                            composer.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()\n"
            "                        }\n"
            "                        guard focused.waitForExistence(timeout: 2) else { break }\n"
            "                    }\n"
            "                    "
        )
        self.assertIn(focus, original)
        chat.write_text(original.replace(focus, "", 1))
        self.assert_rejected("uitest.character_type_keyboard_focus")

        scenario = "func testLaunchQualityGateCapturesTimelineSurfaces()"
        prefix, body = original.split(scenario, 1)
        self.assertIn("        executionTimeAllowance = 180\n", body)
        chat.write_text(prefix + scenario + body.replace("        executionTimeAllowance = 180\n",
            "        try testDatedTimelineManualBaselineAndInterruptedPhotoReturn()\n", 1))
        self.assert_rejected("uitest.nested_launch_time_allowance")

    def test_dated_stats_fixture_survives_path_and_account_change(self):
        self.assertEqual(self.run_audit()[0], 0)
        cases = [
            ("Services/RealtimeSyncManager+Part01.swift",
             "self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)",
             "self.isOnline = path.status == .satisfied", "dated_stats.offline_survives_path"),
            ("Services/RealtimeSyncManager.swift", "self.isOnline = Self.online(isOnline)",
             "self.isOnline = isOnline", "dated_stats.offline_survives_path"),
            ("Services/RealtimeSyncManager.swift", "guard !usesOfflineUITestFixture else { return }",
             "", "dated_stats.offline_survives_path"),
            ("Services/RealtimeSyncManager.swift", "return !fixtureForcesOffline",
             "return pathSatisfied", "dated_stats.offline_survives_path"),
            ("Services/RealtimeSyncManager.swift", '"-lybUITestPhotoTimelineHUDFixture"',
             '"-not-an-offline-fixture"', "dated_stats.offline_survives_path"),
            ("Views/DashboardViewLiquid.swift",
             "selectedPhotoTimelineRootPage = Self.pageAfterAccountChange()",
             "selectedPhotoTimelineRootPage = .timeline", "dated_stats.analytics_survives_account"),
            ("Services/DatedTimelineUI.swift", "return .analytics", "return .timeline",
             "dated_stats.analytics_survives_account"),
        ]
        for relative, before, after, check in cases:
            with self.subTest(before=before):
                path = self.app / relative
                source = path.read_text()
                self.assertIn(before, source)
                path.write_text(source.replace(before, after, 1))
                self.assert_rejected(check)
                path.write_text(source)
