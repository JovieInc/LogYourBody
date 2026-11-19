"""Interaction-path scans, signpost names, and device-receipt checks."""
from __future__ import annotations

import re
from dataclasses import dataclass

PASS_CLAIMS = {"pass", "passed", "physical-pass", "physical_pass"}
REQUIRED_RECEIPT_FIELDS = (
    "device",
    "os",
    "buildSha",
    "thermalState",
    "refreshRateHz",
    "fixtureId",
)

VIEW_MARKERS = ("/Views/", "/Components/", "/Features/", "/DesignSystem/", "SettingsComponents.swift")
BLOCKING = (
    ("interaction.perform_and_wait", re.compile(r"\bperformAndWait\b"), "performAndWait blocks the interaction path."),
    ("interaction.dispatch_semaphore", re.compile(r"\bDispatchSemaphore\b"), "DispatchSemaphore blocks the interaction path."),
    ("interaction.main_sync", re.compile(r"\.main\.sync\b"), "main.sync stalls the interaction path."),
    ("interaction.thread_sleep", re.compile(r"\bThread\.sleep\b"), "Thread.sleep stalls the interaction path."),
)
UIIMAGE_DATA = re.compile(r"\bUIImage\s*\(\s*data\s*:")
SWIFTUI_SMELLS = (
    (
        "swiftui.no_render_path_image_decode",
        re.compile(r"Image\s*\(\s*uiImage:\s*UIImage\s*\(\s*data\s*:"),
        "Decode image data before SwiftUI render work starts.",
    ),
    (
        "swiftui.no_inline_collection_transform_in_foreach",
        re.compile(r"ForEach\s*\([^)\n]*\.(?:filter|sorted|map)\s*(?:\{|\\\()"),
        "Precompute collection transforms before ForEach.",
    ),
    (
        "swiftui.no_per_render_uuid_identity",
        re.compile(r"\b(?:var|let)\s+id\s*=\s*UUID\s*\(\s*\)"),
        "Use a stable domain identity for visual rows.",
    ),
)
VIEW_BODY = re.compile(
    r"(?:@ViewBuilder\s+)?"
    r"(?:(?:public|private|fileprivate|internal|open|package|static|final)\s+)*"
    r"var\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*some\s+View\b"
)
SIGNPOST_CALL = re.compile(r"PerfSignpost\s*\.\s*(?:measure|begin|event)\s*\(")
SIGNPOST_LITERAL = re.compile(r'PerfSignpost\s*\.\s*(?:measure|begin|event)\s*\(\s*"([^"]+)"')
CONCURRENT = re.compile(r"(?<![\w])@concurrent\b")

@dataclass(frozen=True)
class Finding:
    rule: str
    path: str
    line: int
    detail: str

def mask_comments(text: str) -> str:
    """Blank comments while preserving indexes, newlines, and string literals."""
    chars = list(text)
    i = 0
    n = len(chars)
    while i < n:
        if chars[i] == "/" and i + 1 < n and chars[i + 1] == "/":
            while i < n and chars[i] != "\n":
                chars[i] = " "
                i += 1
            continue
        if chars[i] == "/" and i + 1 < n and chars[i + 1] == "*":
            chars[i] = chars[i + 1] = " "
            i += 2
            while i + 1 < n and not (chars[i] == "*" and chars[i + 1] == "/"):
                if chars[i] != "\n":
                    chars[i] = " "
                i += 1
            if i < n:
                chars[i] = " "
            if i + 1 < n:
                chars[i + 1] = " "
            i += 2
            continue
        if chars[i] == '"':
            if text.startswith('"""', i):
                i += 3
                while i + 2 < n and not text.startswith('"""', i):
                    i += 1
                i += 3
                continue
            i += 1
            while i < n and chars[i] != '"':
                if chars[i] == "\\":
                    i += 2
                    continue
                if chars[i] == "\n":
                    break
                i += 1
            i += 1
            continue
        i += 1
    return "".join(chars)


def mask_non_code(text: str) -> str:
    """Blank comments and strings while preserving indexes and newlines."""
    chars = list(text)
    i = 0
    n = len(chars)
    while i < n:
        if chars[i] == "/" and i + 1 < n and chars[i + 1] == "/":
            while i < n and chars[i] != "\n":
                chars[i] = " "
                i += 1
            continue
        if chars[i] == "/" and i + 1 < n and chars[i + 1] == "*":
            chars[i] = chars[i + 1] = " "
            i += 2
            while i + 1 < n and not (chars[i] == "*" and chars[i + 1] == "/"):
                if chars[i] != "\n":
                    chars[i] = " "
                i += 1
            if i < n:
                chars[i] = " "
            if i + 1 < n:
                chars[i + 1] = " "
            i += 2
            continue
        if chars[i] == '"':
            if text.startswith('"""', i):
                chars[i] = chars[i + 1] = chars[i + 2] = " "
                i += 3
                while i + 2 < n and not text.startswith('"""', i):
                    if chars[i] != "\n":
                        chars[i] = " "
                    i += 1
                for _ in range(3):
                    if i < n:
                        chars[i] = " "
                        i += 1
                continue
            chars[i] = " "
            i += 1
            while i < n and chars[i] != '"':
                if chars[i] == "\\":
                    chars[i] = " "
                    i += 1
                    if i < n and chars[i] != "\n":
                        chars[i] = " "
                        i += 1
                    continue
                if chars[i] != "\n":
                    chars[i] = " "
                i += 1
            if i < n:
                chars[i] = " "
                i += 1
            continue
        i += 1
    return "".join(chars)


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def is_view_path(path: str) -> bool:
    return any(marker in f"/{path}" or path.endswith(marker) for marker in VIEW_MARKERS)


def brace_end(text: str, open_index: int) -> int:
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index + 1
    return len(text)


def view_body_spans(masked: str) -> list[tuple[int, int]]:
    spans = []
    for match in VIEW_BODY.finditer(masked):
        brace = masked.find("{", match.end())
        if brace < 0:
            continue
        spans.append((brace, brace_end(masked, brace)))
    return spans


def in_spans(index: int, spans: list[tuple[int, int]]) -> bool:
    return any(start <= index < end for start, end in spans)


def scan_source(path: str, text: str) -> list[Finding]:
    masked = mask_non_code(text)
    findings: list[Finding] = []
    for rule, pattern, detail in BLOCKING:
        for match in pattern.finditer(masked):
            findings.append(Finding(rule, path, line_of(text, match.start()), detail))
    spans = view_body_spans(masked)
    for match in UIIMAGE_DATA.finditer(masked):
        if in_spans(match.start(), spans):
            findings.append(
                Finding(
                    "interaction.uiimage_data_in_view_body",
                    path,
                    line_of(text, match.start()),
                    "UIImage(data:) inside a view body decodes on the render path.",
                )
            )
    if is_view_path(path):
        for rule, pattern, detail in SWIFTUI_SMELLS:
            for match in pattern.finditer(masked):
                findings.append(Finding(rule, path, line_of(text, match.start()), detail))
    return findings


def counts_of(findings: list[Finding]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for finding in findings:
        key = f"{finding.rule}|{finding.path}"
        counts[key] = counts.get(key, 0) + 1
    return dict(sorted(counts.items()))


def ratchet_errors(live: dict[str, int], baseline: dict[str, int]) -> list[str]:
    errors = []
    for key in sorted(set(live) | set(baseline)):
        have = live.get(key, 0)
        allowed = baseline.get(key, 0)
        if have > allowed:
            errors.append(f"new violation {key}: {have} > baseline {allowed}")
        elif have < allowed:
            errors.append(f"stale-high baseline {key}: baseline {allowed} > live {have}")
    return errors


def fall_only_errors(current: dict[str, int], ancestor: dict[str, int] | None) -> list[str]:
    if ancestor is None:
        return []
    errors = []
    for key, count in sorted(current.items()):
        previous = ancestor.get(key, 0)
        if count > previous:
            errors.append(f"baseline may only fall for {key}: {previous} -> {count}")
    return errors


def signpost_errors(text: str, allowed: set[str], path: str) -> list[str]:
    masked = mask_comments(text)
    errors = []
    for match in SIGNPOST_CALL.finditer(masked):
        literal = SIGNPOST_LITERAL.match(masked, match.start())
        if literal is None:
            errors.append(f"unknown signpost at {path}:{line_of(text, match.start())}: name must be a contract string literal")
            continue
        name = literal.group(1)
        if name not in allowed:
            errors.append(f"unknown signpost {name} at {path}:{line_of(text, match.start())}")
    return errors


def validate_device_receipt(payload: object) -> tuple[str, list[str]]:
    """Return (status, errors). Missing data is unverified and is not a failure."""
    if payload is None:
        return "unverified", []
    if not isinstance(payload, dict):
        return "rejected", ["device receipt must be a JSON object"]
    claim = str(payload.get("verdict") or payload.get("status") or "").strip().lower()
    if claim not in PASS_CLAIMS:
        return ("unverified" if claim in {"", "missing", "unverified"} else "recorded"), []
    missing = []
    for field in REQUIRED_RECEIPT_FIELDS:
        value = payload.get(field)
        if field == "refreshRateHz":
            if value not in (60, 120):
                missing.append(field)
            continue
        if not isinstance(value, str) or not value.strip():
            missing.append(field)
    if missing:
        return "rejected", ["physical-pass receipt omits " + ", ".join(missing)]
    return "verified", []


def uses_concurrent(text: str) -> bool:
    return CONCURRENT.search(mask_non_code(text)) is not None

