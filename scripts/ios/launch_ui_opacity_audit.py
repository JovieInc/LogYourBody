#!/usr/bin/env python3
"""Reject optional CGFloat values passed to SwiftUI opacity."""

from __future__ import annotations

import re
from functools import lru_cache
from pathlib import Path

from launch_ui_timeline_audit import AuditViolation, line_number

_CGFLOAT_BINDING = re.compile(
    r"\b(?:var|let)\s+([A-Za-z_]\w*)\s*:\s*CGFloat\b"
    r"|\bfunc\s+([A-Za-z_]\w*)\s*\([^;\n]*\)\s*->\s*CGFloat\b"
)
_MEMBER = re.compile(r"\?\.([A-Za-z_]\w*)\b")
# One nested call covers the opacity arguments in this tree, including Double(...).
# A per-character walk is traced on every audit run and blows the 30s coverage limit.
_OPACITY_CALL = re.compile(
    r"\.opacity\((?P<arg>(?:[^()]|\([^()]*\))*)\)",
    re.DOTALL,
)
_DOUBLE_CAST = re.compile(
    r"(?<![\w])Double\((?:[^()]|\([^()]*\))*\)",
    re.DOTALL,
)
_DETAIL = "Convert optional CGFloat opacity to Double; SwiftUI does not implicitly convert CGFloat?."


def _without_double_casts(argument: str) -> str:
    """Drop Double(...) conversions so a wrapped CGFloat member is allowed."""
    previous = None
    current = argument
    while current != previous:
        previous = current
        current = _DOUBLE_CAST.sub("", current)
    return current


def _walk_opacity_arguments(text: str):
    """Paren walk for the rare argument the one-level pattern cannot close."""
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


def _opacity_arguments(text: str):
    matches = list(_OPACITY_CALL.finditer(text))
    if len(matches) == text.count(".opacity("):
        for match in matches:
            yield match.start("arg"), match.group("arg")
        return
    yield from _walk_opacity_arguments(text)


@lru_cache(maxsize=512)
def _binding_names(pattern, text: str) -> frozenset[str]:
    """Cache only immutable parse results, never file reads or combined findings."""
    return frozenset(next(group for group in match.groups() if group)
                     for match in pattern.finditer(text))


def check_optional_cgfloat_opacity(
    root: Path,
    paths: list[Path],
    violations: list[AuditViolation],
    texts: dict[Path, str] | None = None,
) -> None:
    """SwiftUI opacity accepts CGFloat, but not CGFloat? from optional chaining."""
    names: set[str] = set()
    candidates: list[tuple[Path, str]] = []
    pairs = (
        texts.items()
        if texts is not None
        else ((path, path.read_text(errors="replace")) for path in paths)
    )
    for path, text in pairs:
        if "CGFloat" in text:
            names.update(_binding_names(_CGFLOAT_BINDING, text))
        # A file without optional chaining cannot pass a CGFloat? into opacity.
        if ".opacity(" in text and "?." in text:
            candidates.append((path, text))
    if not names:
        return
    for path, text in candidates:
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


def contribute(root, _app_dir, violations, _violation, _line_number) -> None:
    """Run the opacity check from the one-pass Swift snapshot."""
    import launch_ui_timeline_audit as sources

    texts = sources.SWIFT_SOURCES
    if texts is None:
        texts = sources.begin_swift_sources(root)
    check_optional_cgfloat_opacity(root, list(texts), violations, texts)
