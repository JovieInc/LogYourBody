#!/usr/bin/env python3
"""Reject optional CGFloat values passed to SwiftUI opacity."""

from __future__ import annotations

import re
from pathlib import Path

from launch_ui_timeline_audit import AuditViolation, line_number

_CGFLOAT_BINDING = re.compile(
    r"\b(?:var|let)\s+([A-Za-z_]\w*)\s*:\s*CGFloat\b"
    r"|\bfunc\s+([A-Za-z_]\w*)\s*\([^;\n]*\)\s*->\s*CGFloat\b"
)
_MEMBER = re.compile(r"\?\.([A-Za-z_]\w*)\b")
_DETAIL = "Convert optional CGFloat opacity to Double; SwiftUI does not implicitly convert CGFloat?."


def _cgfloat_names(paths: list[Path]) -> set[str]:
    names: set[str] = set()
    for path in paths:
        for match in _CGFLOAT_BINDING.finditer(path.read_text(errors="replace")):
            names.add(next(group for group in match.groups() if group))
    return names


def _opacity_arguments(text: str):
    needle = ".opacity("
    start = 0
    while True:
        begin = text.find(needle, start)
        if begin < 0:
            return
        index = begin + len(needle)
        depth = 1
        argument_start = index
        while index < len(text) and depth:
            char = text[index]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            index += 1
        if depth == 0:
            yield argument_start, text[argument_start:index - 1]
        start = index


def _without_double_casts(argument: str) -> str:
    """Drop Double(...) conversions so a wrapped CGFloat member is allowed."""
    kept: list[str] = []
    index = 0
    while index < len(argument):
        previous = argument[index - 1] if index else ""
        if argument.startswith("Double(", index) and not (previous.isalnum() or previous == "_"):
            index += len("Double(")
            depth = 1
            while index < len(argument) and depth:
                if argument[index] == "(":
                    depth += 1
                elif argument[index] == ")":
                    depth -= 1
                index += 1
            continue
        kept.append(argument[index])
        index += 1
    return "".join(kept)


def check_optional_cgfloat_opacity(
    root: Path, paths: list[Path], violations: list[AuditViolation]
) -> None:
    """SwiftUI opacity accepts CGFloat, but not CGFloat? from optional chaining."""
    names = _cgfloat_names(paths)
    if not names:
        return
    for path in paths:
        text = path.read_text(errors="replace")
        for argument_start, argument in _opacity_arguments(text):
            exposed = _without_double_casts(argument)
            if any(match.group(1) in names for match in _MEMBER.finditer(exposed)):
                violations.append(
                    AuditViolation(
                        check="swift.optional_cgfloat_opacity",
                        file=str(path.relative_to(root)),
                        line=line_number(text, argument_start),
                        detail=_DETAIL,
                    )
                )
