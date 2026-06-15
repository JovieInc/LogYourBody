#!/usr/bin/env python3
"""Summarize iOS performance audit artifacts and enforce coarse budgets."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


LOG_TEST_RE = re.compile(
    r"Test case '(?P<test>[^']+)' (?P<result>passed|failed) .* \((?P<seconds>[0-9]+(?:\.[0-9]+)?) seconds\)"
)


@dataclass
class TestCaseDuration:
    identifier: str
    result: str
    duration_seconds: float
    source: str


@dataclass
class BudgetCheck:
    id: str
    label: str
    observed_seconds: Optional[float]
    budget_seconds: Optional[float]
    status: str
    detail: str


def env_float(name: str, default: float) -> float:
    raw_value = os.environ.get(name)
    if raw_value is None or raw_value.strip() == "":
        return default
    try:
        return float(raw_value)
    except ValueError:
        raise SystemExit(f"{name} must be a number, got {raw_value!r}")


def env_bool(name: str, default: bool = False) -> bool:
    raw_value = os.environ.get(name)
    if raw_value is None:
        return default
    return raw_value.lower() in {"1", "true", "yes", "y"}


def run_xcresulttool(result_bundle: Path, command: str) -> Optional[Any]:
    if not result_bundle.is_dir():
        return None

    process = subprocess.run(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            command,
            "--path",
            str(result_bundle),
            "--format",
            "json",
        ],
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


def collect_cases_from_xcresult(result_bundle: Path) -> list[TestCaseDuration]:
    payload = run_xcresulttool(result_bundle, "tests")
    if payload is None:
        return []

    cases: list[TestCaseDuration] = []

    def walk(node: dict[str, Any]) -> None:
        if node.get("nodeType") == "Test Case":
            identifier = node.get("nodeIdentifier") or node.get("name") or "unknown"
            result = str(node.get("result") or "Unknown")
            duration = node.get("durationInSeconds")
            if isinstance(duration, (int, float)):
                cases.append(
                    TestCaseDuration(
                        identifier=str(identifier),
                        result=result,
                        duration_seconds=float(duration),
                        source=str(result_bundle),
                    )
                )

        for child in node.get("children", []):
            if isinstance(child, dict):
                walk(child)

    for root in payload.get("testNodes", []):
        if isinstance(root, dict):
            walk(root)

    return cases


def collect_cases_from_log(log_path: Path) -> list[TestCaseDuration]:
    if not log_path.is_file():
        return []

    cases: list[TestCaseDuration] = []
    for line in log_path.read_text(errors="replace").splitlines():
        match = LOG_TEST_RE.search(line)
        if not match:
            continue
        cases.append(
            TestCaseDuration(
                identifier=match.group("test"),
                result=match.group("result").capitalize(),
                duration_seconds=float(match.group("seconds")),
                source=str(log_path),
            )
        )

    return cases


def collect_cases(result_bundle: Optional[Path], log_path: Optional[Path]) -> list[TestCaseDuration]:
    if result_bundle is not None:
        cases = collect_cases_from_xcresult(result_bundle)
        if cases:
            return cases

    if log_path is not None:
        return collect_cases_from_log(log_path)

    return []


def has_xctest_metric_statistics(result_bundle: Optional[Path]) -> bool:
    if result_bundle is None or not result_bundle.is_dir():
        return False

    metrics_payload = run_xcresulttool(result_bundle, "metrics")
    if isinstance(metrics_payload, list) and len(metrics_payload) > 0:
        return True
    if isinstance(metrics_payload, dict) and len(metrics_payload) > 0:
        return True

    summary_payload = run_xcresulttool(result_bundle, "summary")
    if isinstance(summary_payload, dict):
        statistics = summary_payload.get("statistics")
        return isinstance(statistics, list) and len(statistics) > 0

    return False


def seconds(value: Optional[float]) -> str:
    if value is None:
        return "-"
    return f"{value:.3f}s"


def markdown_status(status: str) -> str:
    return {
        "passed": "Passed",
        "warning": "Warning",
        "failed": "Failed",
        "skipped": "Skipped",
    }.get(status, status.capitalize())


def write_summary(
    args: argparse.Namespace,
    budgets: dict[str, Any],
    checks: list[BudgetCheck],
    unit_cases: list[TestCaseDuration],
    launch_cases: list[TestCaseDuration],
    launch_metrics_available: bool,
) -> int:
    failed_checks = [check for check in checks if check.status == "failed"]
    missing_launch_metrics = any(
        check.id == "launch.metric_statistics" and check.status in {"warning", "failed"}
        for check in checks
    )
    status = "failed" if failed_checks else "passed"

    summary = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "destination": args.destination,
        "status": status,
        "unitSkipped": args.unit_skipped,
        "launchSkipped": args.launch_skipped,
        "budgets": budgets,
        "checks": [asdict(check) for check in checks],
        "unitCases": [asdict(case) for case in unit_cases],
        "launchCases": [asdict(case) for case in launch_cases],
        "launchMetricStatisticsAvailable": launch_metrics_available,
    }

    args.summary_json.parent.mkdir(parents=True, exist_ok=True)
    args.summary_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")

    lines = [
        "# iOS Performance Audit",
        "",
        f"- Status: {markdown_status(status)}",
        f"- Destination: `{args.destination}`",
        f"- Unit result bundle: `{args.unit_xcresult or 'not provided'}`",
        f"- Launch result bundle: `{args.launch_xcresult or 'not provided'}`",
        f"- JSON summary: `{args.summary_json}`",
        "",
        "## Budget Checks",
        "",
        "| Check | Observed | Budget | Status |",
        "| --- | ---: | ---: | --- |",
    ]

    for check in checks:
        lines.append(
            f"| {check.label} | {seconds(check.observed_seconds)} | "
            f"{seconds(check.budget_seconds)} | {markdown_status(check.status)} |"
        )

    lines.extend(["", "## Notes", ""])
    for check in checks:
        lines.append(f"- {check.label}: {check.detail}")

    if missing_launch_metrics:
        lines.extend(
            [
                "",
                "## Follow-up",
                "",
                "- XCTest did not publish granular launch metric statistics in this result bundle. "
                "Capture a focused Instruments or ETTrace run before tightening frame or hitch budgets.",
            ]
        )

    args.summary_md.write_text("\n".join(lines) + "\n")

    return 2 if failed_checks else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact-dir", type=Path, required=True)
    parser.add_argument("--destination", default="unknown")
    parser.add_argument("--unit-xcresult", type=Path)
    parser.add_argument("--unit-log", type=Path)
    parser.add_argument("--launch-xcresult", type=Path)
    parser.add_argument("--launch-log", type=Path)
    parser.add_argument("--unit-skipped", action="store_true")
    parser.add_argument("--launch-skipped", action="store_true")
    parser.add_argument("--summary-md", type=Path)
    parser.add_argument("--summary-json", type=Path)
    args = parser.parse_args()

    args.summary_md = args.summary_md or args.artifact_dir / "summary.md"
    args.summary_json = args.summary_json or args.artifact_dir / "summary.json"

    budgets: dict[str, Any] = {
        "unitMaxCaseSeconds": env_float("PERF_MAX_UNIT_TEST_CASE_SECONDS", 0.75),
        "unitTotalCaseSeconds": env_float("PERF_MAX_UNIT_TEST_TOTAL_SECONDS", 2.0),
        "launchMaxTestSeconds": env_float("PERF_MAX_LAUNCH_TEST_SECONDS", 90.0),
        "launchWarnTestSeconds": env_float("PERF_WARN_LAUNCH_TEST_SECONDS", 60.0),
        "failOnMissingLaunchMetrics": env_bool("PERF_FAIL_ON_MISSING_LAUNCH_METRICS", False),
    }

    unit_cases = [] if args.unit_skipped else collect_cases(args.unit_xcresult, args.unit_log)
    launch_cases = [] if args.launch_skipped else collect_cases(args.launch_xcresult, args.launch_log)
    launch_case = next(
        (case for case in launch_cases if "testLaunchPerformance" in case.identifier),
        launch_cases[0] if launch_cases else None,
    )
    launch_metrics_available = False if args.launch_skipped else has_xctest_metric_statistics(args.launch_xcresult)

    checks: list[BudgetCheck] = []

    unit_total = sum(case.duration_seconds for case in unit_cases)
    unit_slowest = max(unit_cases, key=lambda case: case.duration_seconds, default=None)
    unit_total_budget = float(budgets["unitTotalCaseSeconds"])
    unit_case_budget = float(budgets["unitMaxCaseSeconds"])

    if args.unit_skipped:
        checks.append(
            BudgetCheck(
                id="unit.total_case_duration",
                label="Performance unit total",
                observed_seconds=None,
                budget_seconds=unit_total_budget,
                status="skipped",
                detail="Performance unit XCTest was disabled for this run.",
            )
        )

        checks.append(
            BudgetCheck(
                id="unit.slowest_case_duration",
                label="Slowest performance unit",
                observed_seconds=None,
                budget_seconds=unit_case_budget,
                status="skipped",
                detail="Performance unit XCTest was disabled for this run.",
            )
        )
    else:
        checks.append(
            BudgetCheck(
                id="unit.total_case_duration",
                label="Performance unit total",
                observed_seconds=unit_total if unit_cases else None,
                budget_seconds=unit_total_budget,
                status="failed" if unit_cases and unit_total > unit_total_budget else ("passed" if unit_cases else "warning"),
                detail=(
                    f"{len(unit_cases)} test cases reported {unit_total:.3f}s total XCTest runtime."
                    if unit_cases
                    else "No unit-test durations were found in the result bundle or log."
                ),
            )
        )

        checks.append(
            BudgetCheck(
                id="unit.slowest_case_duration",
                label="Slowest performance unit",
                observed_seconds=unit_slowest.duration_seconds if unit_slowest else None,
                budget_seconds=unit_case_budget,
                status=(
                    "failed"
                    if unit_slowest and unit_slowest.duration_seconds > unit_case_budget
                    else ("passed" if unit_slowest else "warning")
                ),
                detail=(
                    f"{unit_slowest.identifier} reported {unit_slowest.duration_seconds:.3f}s."
                    if unit_slowest
                    else "No unit-test case duration was available."
                ),
            )
        )

    if args.launch_skipped:
        checks.append(
            BudgetCheck(
                id="launch.performance_test_duration",
                label="Launch performance UI test",
                observed_seconds=None,
                budget_seconds=float(budgets["launchMaxTestSeconds"]),
                status="skipped",
                detail="Launch performance XCTest was disabled for this run.",
            )
        )
    else:
        launch_duration = launch_case.duration_seconds if launch_case else None
        launch_status = "warning"
        if launch_duration is not None:
            if launch_duration > float(budgets["launchMaxTestSeconds"]):
                launch_status = "failed"
            elif launch_duration > float(budgets["launchWarnTestSeconds"]):
                launch_status = "warning"
            else:
                launch_status = "passed"

        checks.append(
            BudgetCheck(
                id="launch.performance_test_duration",
                label="Launch performance UI test",
                observed_seconds=launch_duration,
                budget_seconds=float(budgets["launchMaxTestSeconds"]),
                status=launch_status,
                detail=(
                    f"{launch_case.identifier} reported {launch_duration:.3f}s end-to-end XCTest duration."
                    if launch_case and launch_duration is not None
                    else "No launch performance test duration was found in the result bundle or log."
                ),
            )
        )

    if not args.launch_skipped:
        missing_status = "passed" if launch_metrics_available else "warning"
        if not launch_metrics_available and bool(budgets["failOnMissingLaunchMetrics"]):
            missing_status = "failed"
        checks.append(
            BudgetCheck(
                id="launch.metric_statistics",
                label="Launch metric statistics",
                observed_seconds=None,
                budget_seconds=None,
                status=missing_status,
                detail=(
                    "XCTest launch metric statistics were present in the result bundle."
                    if launch_metrics_available
                    else "XCTest launch metric statistics were not present; only test-case duration is available."
                ),
            )
        )

    return write_summary(args, budgets, checks, unit_cases, launch_cases, launch_metrics_available)


if __name__ == "__main__":
    sys.exit(main())
