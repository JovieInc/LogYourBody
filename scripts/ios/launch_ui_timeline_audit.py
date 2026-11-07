#!/usr/bin/env python3
"""Timeline calendar-day checks for the launch UI regression audit."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


@dataclass
class AuditViolation:
    check: str
    file: str
    line: int
    detail: str


def line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def function_body(text: str, name: str, next_name: str) -> str:
    if f"func {name}" not in text or f"func {next_name}" not in text:
        return ""
    chunk = text.split(f"func {name}", 1)[1].split(f"func {next_name}", 1)[0]
    return chunk.split("{", 1)[1] if "{" in chunk else ""


def check_timeline_calendar_day(root: Path, violations: list[AuditViolation]) -> None:
    """Timeline positions follow the injected calendar day, not elapsed 86400-second offsets."""
    calculator = root / "apps/ios/LogYourBody/Helpers/TimelineCalculator.swift"
    if not calculator.is_file():
        return
    text = calculator.read_text(errors="replace")
    points_body = function_body(text, "calculateTimelinePoints", "calculateWeightedPositions")
    weighted_body = function_body(text, "calculateWeightedPositions", "formatLabel")
    detail = "Timeline day distance must use the injected now and calendar, not a fresh clock."
    if (
        "now: Date = Date()" not in text
        or "calendar: Calendar = .current" not in text
        or not points_body
        or not weighted_body
        or re.search(r"\blet now = Date\(\)", points_body + weighted_body)
        or re.search(r"\bCalendar\.current\b", points_body + weighted_body)
    ):
        violations.append(AuditViolation(
            check="timeline.injected_calendar_day",
            file=str(calculator.relative_to(root)),
            line=1,
            detail=detail,
        ))

    tests = root / "apps/ios/LogYourBodyTests/TimelineCalculatorTests.swift"
    if not tests.is_file():
        return
    test_text = tests.read_text(errors="replace")
    relative = str(tests.relative_to(root))
    if "addingTimeInterval(-daysAgo * 24 * 60 * 60)" in test_text:
        violations.append(AuditViolation(
            check="timeline.elapsed_day_offset",
            file=relative,
            line=line_number(test_text, test_text.index("addingTimeInterval(-daysAgo * 24 * 60 * 60)")),
            detail="Build timeline fixtures with calendar.date(byAdding: .day), not elapsed 86400-second offsets.",
        ))
    if "pacific fallback hour keeps calendar-day timeline position" not in test_text:
        violations.append(AuditViolation(
            check="timeline.fallback_hour_regression",
            file=relative,
            line=1,
            detail="Keep the Pacific DST fallback regression for the merge-group timeline position failure.",
        ))


