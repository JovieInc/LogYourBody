#!/usr/bin/env python3
"""The xcodebuild hang cap stays fixed, and only a terminal result may extend it."""

from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

WATCHER = Path(__file__).with_name("xcodebuild-command-timeout.py")
SPEC = importlib.util.spec_from_file_location("xcodebuild_command_timeout", WATCHER)
assert SPEC and SPEC.loader
deadline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(deadline)


def run_watcher(timeout: str, grace: str, child: list[str]) -> subprocess.CompletedProcess[str]:
    started = time.monotonic()
    result = subprocess.run(
        [sys.executable, str(WATCHER), "--timeout-seconds", timeout, "--grace-seconds", grace, "--", *child],
        text=True,
        capture_output=True,
        check=False,
    )
    result.elapsed = time.monotonic() - started  # type: ignore[attr-defined]
    return result


def python_child(source: str) -> list[str]:
    return [sys.executable, "-c", source]


class DeadlineRuleTests(unittest.TestCase):
    def audit_budget(self, elapsed: int, *, override: str = "", duration: int = 1700):
        source = WATCHER.with_name("launch-quality-audit.sh").read_text()
        default = next(line for line in source.splitlines() if line.startswith("AUDIT_DEADLINE_SECONDS="))
        helpers = source[source.index("remaining_budget_seconds() {"):source.index('\nPHASE_NAME=""')]
        # Exercise the actual shell budget with a virtual clock and UI command.
        command = "\n".join([
            "set -euo pipefail", default, "AUDIT_STARTED_AT=10000",
            f"date() {{ echo {10000 + elapsed}; }}", helpers,
            'cap="$(bounded_seconds 1800)"', 'echo "cap=$cap"',
            'echo command-started', f'(( {duration} <= cap )) || exit 124',
            'echo selected-tests-completed',
        ])
        return subprocess.run(
            ["/bin/bash", "-c", command], capture_output=True, text=True,
            env={"PATH": os.defpath, "AUDIT_DEADLINE_SECONDS": override}, check=False,
        )

    def test_slow_prefix_uses_available_step_budget_without_losing_ui_cases(self):
        # Run 42695073821 spent 1168s before UI; its old 2760s audit cap
        # killed passing tests during the canvas journey, before onboarding.
        old = self.audit_budget(1168, override="2760")
        self.assertEqual(old.returncode, 124)
        self.assertNotIn("selected-tests-completed", old.stdout)
        current = self.audit_budget(1168)
        self.assertEqual(current.returncode, 0, current.stderr)
        self.assertIn("selected-tests-completed", current.stdout)
        self.assertIn("cap=1800", current.stdout)
        # Run 42795533093 spent 1375s before UI. Deadline 2940 left 1565s and
        # killed still-passing UI cases. The retry finished those cases in 1697s,
        # so the cold prefix must keep the full 1800s hang cap.
        shrunk = self.audit_budget(1375, override="2940")
        self.assertEqual(shrunk.returncode, 124)
        self.assertIn("cap=1565", shrunk.stdout)
        self.assertNotIn("selected-tests-completed", shrunk.stdout)
        cold = self.audit_budget(1375)
        self.assertEqual(cold.returncode, 0, cold.stderr)
        self.assertIn("cap=1800", cold.stdout)
        self.assertIn("selected-tests-completed", cold.stdout)
        self.assertIn("cap=1800", self.audit_budget(0).stdout)
        self.assertIn("cap=20", self.audit_budget(40, override="60", duration=19).stdout)
        self.assertEqual(self.audit_budget(40, override="60", duration=21).returncode, 124)

    def test_audit_reserves_finalization_within_the_real_workflow_step(self):
        workflow = WATCHER.parents[2] / ".github/workflows/ios-quality.yml"
        step = workflow.read_text().split("- name: Run launch quality audit", 1)[1].split("\n      - name:", 1)[0]
        minutes = int(re.search(r"timeout-minutes: (\d+)", step).group(1))
        result = self.audit_budget(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        # Read the default through Bash, including arithmetic expressions.
        source = WATCHER.with_name("launch-quality-audit.sh").read_text()
        default = next(line for line in source.splitlines() if line.startswith("AUDIT_DEADLINE_SECONDS="))
        budget = subprocess.check_output(
            ["/bin/bash", "-c", default + '\nprintf "%s" "$AUDIT_DEADLINE_SECONDS"'],
            env={"PATH": os.defpath}, text=True,
        )
        self.assertLessEqual(int(budget) + deadline.MAX_FINALIZATION_GRACE_SECONDS, minutes * 60)

    def test_expired_audit_cannot_start_another_command_with_a_fresh_minute(self):
        for elapsed in (60, 61, 120):
            with self.subTest(elapsed=elapsed):
                expired = self.audit_budget(elapsed, override="60", duration=1)
                self.assertEqual(expired.returncode, 124, expired.stderr)
                self.assertNotIn("command-started", expired.stdout)
                self.assertIn("audit deadline exhausted", expired.stderr)

    def test_budget_reaches_build_and_test_callers_even_inside_a_condition(self):
        source = WATCHER.with_name("launch-quality-audit.sh").read_text()
        helpers = source[source.index("remaining_budget_seconds() {"):source.index('\nPHASE_NAME=""')]
        functions = source[source.index("run_xcodebuild_test() {"):source.index("assert_xcresult_evidence() {")]
        functions += source[source.index("build_for_testing_once() {"):source.index('\nif [[ "$AUDIT_MODE" == diagnostic-seven ]]; then\n  source ')]
        setup = """
set -euo pipefail
AUDIT_STARTED_AT=1000; AUDIT_DEADLINE_SECONDS=60
date() { echo "$FIXTURE_NOW"; }
# Model the runner's populated arrays: Bash 3.2 treats empty arrays as unset.
COMMON_XCODEBUILD_ARGS=(-project "Fixture Project.xcodeproj")
XCODEBUILD_SETTINGS_ARRAY=(CODE_SIGNING_ALLOWED=NO)
XCODEBUILD_COMMAND_TIMEOUT_SECONDS=1800; BUILD_FOR_TESTING_TIMEOUT_SECONDS=900
cleanup_booted_simulator_apps() { :; }
start_launch_probe() { echo probe-started; }
stop_launch_probe() { :; }
run_with_timeout() { printf 'command-started timeout=%s\\n' "$1"; printf 'arg=%s\\n' "$@"; }
"""
        with tempfile.TemporaryDirectory() as directory:
            for now in (1059, 1060, 1061):
                for command in ('build_for_testing_once', 'run_xcodebuild_test fixture "$ARTIFACT_DIR/ui.xcresult" "$ARTIFACT_DIR/ui.log"'):
                    with self.subTest(now=now, command=command):
                        result = subprocess.run(
                            ["/bin/bash", "-c", setup + helpers + functions
                             + f'\nif {command}; then exit 0; else exit "$?"; fi'],
                            env={"PATH": os.defpath, "ARTIFACT_DIR": directory, "FIXTURE_NOW": str(now)},
                            capture_output=True, text=True, check=False,
                        )
                        self.assertEqual(result.returncode, 0 if now < 1060 else 124, result.stderr)
                        if now < 1060:
                            self.assertIn("command-started timeout=1\n", result.stdout)
                            self.assertIn("arg=Fixture Project.xcodeproj\n", result.stdout)
                            self.assertIn("arg=CODE_SIGNING_ALLOWED=NO\n", result.stdout)
                            self.assertEqual("probe-started" in result.stdout, command.startswith("run_xcodebuild_test"))
                        else:
                            self.assertIn("audit deadline exhausted", result.stderr)
                            self.assertNotIn("command-started", result.stdout)
                            self.assertNotIn("probe-started", result.stdout)

    def test_terminal_lines_are_exact(self) -> None:
        self.assertTrue(deadline.is_terminal_result("** TEST EXECUTE SUCCEEDED **"))
        self.assertTrue(deadline.is_terminal_result("  ** TEST EXECUTE FAILED **  "))
        self.assertFalse(deadline.is_terminal_result("** TEST EXECUTE SUCCEEDED ** extra"))
        self.assertFalse(deadline.is_terminal_result("prefix ** TEST EXECUTE SUCCEEDED **"))
        self.assertFalse(deadline.is_terminal_result("** TEST FAILED **"))
        passed = "Test Suite 'Selected tests' passed at 2026-11-07 15:37:49.105."
        failed = "Test Suite 'Selected tests' failed at 2026-11-07 15:37:49.105."
        self.assertTrue(deadline.is_terminal_result(passed))
        self.assertTrue(deadline.is_terminal_result(f"  {failed}  "))
        self.assertFalse(deadline.is_terminal_result("Test Suite 'Selected tests' started at 2026-11-07 15:37:49.105."))
        self.assertFalse(deadline.is_terminal_result(passed + " extra"))
        self.assertFalse(deadline.is_terminal_result("Test Suite 'All tests' passed at 2026-11-07 15:37:49.105."))

    def test_early_result_does_not_extend_and_late_result_extends_once(self) -> None:
        self.assertEqual(deadline.next_deadline(10, 1, 3, False), (10, True))
        extended, once = deadline.next_deadline(10, 9, 3, False)
        self.assertEqual((extended, once), (12, True))
        self.assertEqual(deadline.next_deadline(extended, 11, 3, True), (12, True))

    def test_grace_above_the_reviewed_cap_is_refused_before_a_command_starts(self) -> None:
        sentinel = Path(__file__).with_name(".grace-sentinel")
        sentinel.unlink(missing_ok=True)
        result = run_watcher(
            "5",
            "181",
            python_child(f"from pathlib import Path; Path({str(sentinel)!r}).write_text('ran')"),
        )
        self.assertEqual(result.returncode, 64)
        self.assertIn("reviewed cap", result.stderr)
        self.assertFalse(sentinel.exists())
        self.assertEqual(run_watcher("0", "1", ["true"]).returncode, 64)
        self.assertEqual(run_watcher("1", "-1", ["true"]).returncode, 64)
        self.assertEqual(
            subprocess.run(
                [sys.executable, str(WATCHER), "--timeout-seconds", "1", "--grace-seconds", "1"],
                text=True,
                capture_output=True,
                check=False,
            ).returncode,
            64,
        )

    def test_child_status_and_output_pass_through_before_the_hang_cap(self) -> None:
        result = run_watcher(
            "5",
            "1",
            python_child("import sys; print('child-ready', flush=True); raise SystemExit(9)"),
        )
        self.assertEqual(result.returncode, 9)
        self.assertIn("xcodebuild deadline 5s finalization-grace 1s", result.stdout)
        self.assertIn("child-ready", result.stdout)
        self.assertLess(result.elapsed, 2)  # type: ignore[attr-defined]

    def test_no_terminal_result_keeps_the_hang_cap(self) -> None:
        result = run_watcher("1", "2", python_child("import time; time.sleep(8)"))
        self.assertEqual(result.returncode, 124)
        self.assertLess(result.elapsed, 1.8)  # type: ignore[attr-defined]
        self.assertGreater(result.elapsed, 0.8)  # type: ignore[attr-defined]

    def test_late_terminal_result_can_finish_and_a_finalization_hang_still_dies(self) -> None:
        marker = "print('** TEST EXECUTE SUCCEEDED **', flush=True)"
        finished = run_watcher("1", "2", python_child(f"{marker}; import time; time.sleep(1.3)"))
        self.assertEqual(finished.returncode, 0, finished.stderr)
        self.assertGreater(finished.elapsed, 1.15)  # type: ignore[attr-defined]
        self.assertLess(finished.elapsed, 2.2)  # type: ignore[attr-defined]
        hung = run_watcher(
            "1",
            "2",
            python_child("import time; print('** TEST EXECUTE FAILED **', flush=True); time.sleep(8)"),
        )
        self.assertEqual(hung.returncode, 124)
        self.assertGreater(hung.elapsed, 1.6)  # type: ignore[attr-defined]
        self.assertLess(hung.elapsed, 3.2)  # type: ignore[attr-defined]

    def test_early_terminal_result_does_not_add_grace_to_a_hang(self) -> None:
        result = run_watcher(
            "2",
            "0.5",
            python_child("import time; print('** TEST EXECUTE SUCCEEDED **', flush=True); time.sleep(8)"),
        )
        self.assertEqual(result.returncode, 124)
        self.assertGreater(result.elapsed, 1.7)  # type: ignore[attr-defined]
        self.assertLess(result.elapsed, 2.35)  # type: ignore[attr-defined]

    def test_selected_suite_completion_starts_finalization_before_the_execute_line(self) -> None:
        # Run 42382904905 printed the suite result and was killed before
        # ** TEST EXECUTE SUCCEEDED **. The hang cap stays fixed.
        suite = "Test Suite 'Selected tests' passed at 2026-11-07 15:37:49.105."
        finished = run_watcher("1", "2", python_child(f"import time; print({suite!r}, flush=True); time.sleep(1.3)"))
        self.assertEqual(finished.returncode, 0, finished.stderr)
        self.assertGreater(finished.elapsed, 1.15)  # type: ignore[attr-defined]
        self.assertLess(finished.elapsed, 2.2)  # type: ignore[attr-defined]
        lookalike = run_watcher(
            "1",
            "2",
            python_child(
                "import time; print(\"Test Suite 'Selected tests' passed at later\", flush=True); time.sleep(8)"
            ),
        )
        self.assertEqual(lookalike.returncode, 124)
        self.assertLess(lookalike.elapsed, 1.8)  # type: ignore[attr-defined]

    def test_a_lookalike_line_does_not_extend_the_hang_cap(self) -> None:
        result = run_watcher(
            "1",
            "2",
            python_child("import time; print('** TEST EXECUTE SUCCEEDED ** extra', flush=True); time.sleep(8)"),
        )
        self.assertEqual(result.returncode, 124)
        self.assertLess(result.elapsed, 1.8)  # type: ignore[attr-defined]


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(DeadlineRuleTests)
    result = unittest.TextTestRunner().run(suite)
    print(f"xcodebuild deadline behavior tests executed: {result.testsRun}")
    if not result.wasSuccessful() or result.testsRun == 0:
        sys.exit(1)
