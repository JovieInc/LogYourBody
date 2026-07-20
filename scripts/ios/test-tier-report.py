#!/usr/bin/env python3
"""Report test durations and coverage for a tiered iOS test run.

Read-only summary of an .xcresult bundle produced by the LogYourBodyTiers
scheme: total/failed test-case counts, unit tests that exceeded the duration
threshold, the slowest tests overall, and the app target's line coverage.

This script never fails the build: it always exits 0.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional


@dataclass
class TestCaseDuration:
    identifier: str
    result: str
    duration_seconds: float


def env_float(name: str, default: float) -> float:
    raw_value = os.environ.get(name)
    if raw_value is None or raw_value.strip() == "":
        return default
    try:
        return float(raw_value)
    except ValueError:
        return default


def run_json_command(command: list[str]) -> Optional[Any]:
    process = subprocess.run(
        command,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if process.returncode != 0 or not process.stdout.strip():
        return None

    try:
        return json.loads(process.stdout)
    except json.JSONDecodeError:
        return None


def collect_test_cases(result_bundle: Path) -> list[TestCaseDuration]:
    if not result_bundle.is_dir():
        return []

    payload = run_json_command(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "tests",
            "--format",
            "json",
            "--path",
            str(result_bundle),
        ]
    )
    if payload is None:
        return []

    cases: list[TestCaseDuration] = []

    def walk(node: dict[str, Any]) -> None:
        if node.get("nodeType") == "Test Case":
            identifier = node.get("nodeIdentifier") or node.get("name") or "unknown"
            result = str(node.get("result") or "Unknown")
            duration = node.get("durationInSeconds")
            cases.append(
                TestCaseDuration(
                    identifier=str(identifier),
                    result=result,
                    duration_seconds=float(duration) if isinstance(duration, (int, float)) else 0.0,
                )
            )

        for child in node.get("children", []):
            if isinstance(child, dict):
                walk(child)

    for root in payload.get("testNodes", []):
        if isinstance(root, dict):
            walk(root)

    return cases


def app_line_coverage(result_bundle: Path) -> Optional[tuple[float, int, int]]:
    """Return (lineCoverage 0-1, coveredLines, executableLines) for LogYourBody.app."""
    if not result_bundle.is_dir():
        return None

    payload = run_json_command(
        ["xcrun", "xccov", "view", "--report", "--json", str(result_bundle)]
    )
    if not isinstance(payload, dict):
        return None

    targets = payload.get("targets")
    if not isinstance(targets, list):
        return None

    for target in targets:
        if not isinstance(target, dict):
            continue
        name = str(target.get("name") or "")
        if name != "LogYourBody.app":
            continue
        line_coverage = target.get("lineCoverage")
        covered = target.get("coveredLines")
        executable = target.get("executableLines")
        if not isinstance(line_coverage, (int, float)):
            return None
        return (
            float(line_coverage),
            int(covered) if isinstance(covered, (int, float)) else 0,
            int(executable) if isinstance(executable, (int, float)) else 0,
        )

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xcresult", type=Path, help="Path to the .xcresult bundle to summarize")
    parser.add_argument(
        "--unit-threshold-ms",
        type=float,
        default=None,
        help="Flag unit tests slower than this many milliseconds "
        "(default: env PERF_UNIT_THRESHOLD_MS or 200)",
    )
    args = parser.parse_args()

    threshold_ms = (
        args.unit_threshold_ms
        if args.unit_threshold_ms is not None
        else env_float("PERF_UNIT_THRESHOLD_MS", 200.0)
    )
    threshold_seconds = threshold_ms / 1_000.0

    result_bundle = args.xcresult
    print(f"# Test tier report: {result_bundle}")

    cases = collect_test_cases(result_bundle)
    if not cases:
        print("\nNo test cases found (missing bundle or unreadable xcresult data).")
    else:
        failures = [case for case in cases if case.result.lower() not in {"passed", "skipped"}]
        slow_over_threshold = sorted(
            (case for case in cases if case.duration_seconds > threshold_seconds),
            key=lambda case: case.duration_seconds,
            reverse=True,
        )
        slowest = sorted(cases, key=lambda case: case.duration_seconds, reverse=True)[:10]

        print(f"\nTotal test cases: {len(cases)}")
        print(f"Failures: {len(failures)}")
        for case in failures:
            print(f"  FAIL {case.identifier} ({case.duration_seconds * 1_000:.1f} ms)")

        print(f"\nTests slower than {threshold_ms:.0f} ms ({len(slow_over_threshold)}):")
        for case in slow_over_threshold:
            print(f"  {case.duration_seconds * 1_000:8.1f} ms  {case.identifier}")

        print("\nSlowest 10 tests:")
        for case in slowest:
            print(f"  {case.duration_seconds * 1_000:8.1f} ms  {case.identifier}")

    coverage = app_line_coverage(result_bundle)
    if coverage is None:
        print("\nLogYourBody.app line coverage: coverage not collected")
    else:
        line_coverage, covered, executable = coverage
        print(
            f"\nLogYourBody.app line coverage: {line_coverage * 100:.1f}% "
            f"({covered}/{executable} lines)"
        )

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # noqa: BLE001 - report-only script must not fail builds
        print(f"test-tier-report: unexpected error: {error}")
        sys.exit(0)
