#!/usr/bin/env python3
"""Timeline calendar-day checks for the launch UI regression audit."""

from __future__ import annotations

import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


@dataclass
class AuditViolation:
    check: str
    file: str
    line: int
    detail: str


def line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


# Read each Swift file once per audit so the coverage trace stays inside 30s.
SWIFT_SOURCES: dict[Path, str] | None = None
APP_SOURCES: dict[Path, str] | None = None
_SWIFT_TREES = ("LogYourBody", "LogYourBodyTests", "LogYourBodyUITests", "LogYourBodyWidget")
_GEOMETRY = re.compile(
    r"\b(?:CGPoint|CGSize|CGRect|CGVector|CGAffineTransform)\s*\("
    r"[^()]*?\b\w+\s*:\s*[+-]?\s*\.(?:infinity|nan)\b"
)
_SPACER = re.compile(r"Spacer\s*\(\s*minLength:\s*(?:1[2-9]\d|[2-9]\d{2,})")
_STATS_BUTTON = re.compile(r"photo_timeline_hud_stats_button")
_GEOMETRY_DETAIL = (
    "Qualify non-finite geometry arguments with CGFloat or Double to avoid ambiguous overloads."
)
_SPACER_DETAIL = "Use real bottom padding or safe-area insets instead of fake ScrollView content."
_STATS_DETAIL = "Stats must stay in top navigation or swipe navigation, not a bottom switch card."


def begin_swift_sources(root: Path) -> dict[Path, str]:
    """Snapshot every native Swift file once for this audit invocation."""
    global SWIFT_SOURCES, APP_SOURCES
    texts: dict[Path, str] = {}
    app_texts: dict[Path, str] = {}
    ios = root / "apps" / "ios"
    for directory in _SWIFT_TREES:
        for path in (ios / directory).rglob("*.swift"):
            text = path.read_text(errors="replace")
            texts[path] = text
            if directory == "LogYourBody":
                app_texts[path] = text
    SWIFT_SOURCES = texts
    APP_SOURCES = app_texts
    return texts


def end_swift_sources() -> None:
    """Drop the snapshot so a later mutation is not hidden by the previous audit."""
    global SWIFT_SOURCES, APP_SOURCES
    SWIFT_SOURCES = None
    APP_SOURCES = None


@lru_cache(maxsize=512)
def _pattern_offsets(pattern, text: str) -> tuple[int, ...]:
    """Reuse parsing of identical bytes; paths and findings stay invocation-local."""
    return tuple(match.start() for match in pattern.finditer(text))


def _append_matches(root, path, text, pattern, check, detail, violations, violation, line_number):
    for offset in _pattern_offsets(pattern, text):
        violations.append(violation(
            check=check,
            file=str(path.relative_to(root)),
            line=line_number(text, offset),
            detail=detail,
        ))


def scan_tree_patterns(root: Path, violations: list, violation, line_number) -> None:
    """Apply the full-tree patterns in one pass. A second walk blows the 30s trace."""
    texts = SWIFT_SOURCES or {}
    app_texts = APP_SOURCES or {}
    for path, text in texts.items():
        # The regex scan is traced per file. Skip texts that cannot match.
        if ".infinity" in text or ".nan" in text:
            _append_matches(
                root, path, text, _GEOMETRY, "swift.explicit_geometry_nonfinite",
                _GEOMETRY_DETAIL, violations, violation, line_number,
            )
        if path not in app_texts:
            continue
        if "Spacer" in text:
            _append_matches(
                root, path, text, _SPACER, "overscroll.no_large_fake_bottom_spacers",
                _SPACER_DETAIL, violations, violation, line_number,
            )
        if "photo_timeline_hud_stats_button" in text:
            _append_matches(
                root, path, text, _STATS_BUTTON, "timeline.no_bottom_stats_card",
                _STATS_DETAIL, violations, violation, line_number,
            )


def text_for(path: Path) -> str:
    """Return the audit snapshot when one is active, otherwise the current file."""
    texts = SWIFT_SOURCES
    if texts is not None and path in texts:
        return texts[path]
    return path.read_text(errors="replace")


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
    text = text_for(calculator)
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
    test_text = text_for(tests)
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


