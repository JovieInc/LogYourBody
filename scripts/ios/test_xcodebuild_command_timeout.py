#!/usr/bin/env python3
"""The xcodebuild hang cap stays fixed, and only a terminal result may extend it."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
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
    def test_terminal_lines_are_exact(self) -> None:
        self.assertTrue(deadline.is_terminal_result("** TEST EXECUTE SUCCEEDED **"))
        self.assertTrue(deadline.is_terminal_result("  ** TEST EXECUTE FAILED **  "))
        self.assertFalse(deadline.is_terminal_result("** TEST EXECUTE SUCCEEDED ** extra"))
        self.assertFalse(deadline.is_terminal_result("prefix ** TEST EXECUTE SUCCEEDED **"))
        self.assertFalse(deadline.is_terminal_result("** TEST FAILED **"))

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
