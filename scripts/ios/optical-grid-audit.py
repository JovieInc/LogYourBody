#!/usr/bin/env python3
"""Optical-grid drift ratchet for LYB iOS (optical-grid-consistent-v1).

Source-bound detectors, shrink-only. Every count is compared per file against
`scripts/ios/optical-grid-baseline.json`; a file may only get cleaner. New
files start at zero. Regenerate the baseline with `--update-baseline` only when
a slice has intentionally removed drift (the baseline must never grow).

Detector classes (native D4 "second scale" from the reviewed invariant):
- spacing_scale     `.padding(N)` / `.padding(.edge, N)` / `spacing: N` where N is
                    not on the 4px scale (0, 1, 2 hairlines allowed).
- radius_scale      `cornerRadius: N` / `.cornerRadius(N)` off the 4px scale
                    (0, 2 hairline and 999 pill allowed).
- raw_hex_color     `Color(hex: "...")` outside the two token homes.
- system_color      raw SwiftUI system colours (.green/.red/.orange/...) instead of
                    palette tokens (palette-core-accents-v1: success is blue).
- display_weight    `size: 28, weight: .bold` — locked atom is type 28 / 620
                    (semibold), never bold.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

SOURCE_ROOT = Path("apps/ios/LogYourBody")
TOKEN_HOMES = {
    "apps/ios/LogYourBody/Extensions/Color+Theme.swift",
    "apps/ios/LogYourBody/DesignSystem/Theme.swift",
}
DEFAULT_BASELINE = Path("scripts/ios/optical-grid-baseline.json")

SPACING = re.compile(r"(?:\.padding\((?:\.[a-zA-Z]+,\s*)?|spacing:\s*)(-?\d+(?:\.\d+)?)\b")
RADIUS = re.compile(r"(?:cornerRadius:\s*|\.cornerRadius\()(\d+(?:\.\d+)?)\b")
RAW_HEX = re.compile(r'Color\(hex:\s*"#')
SYSTEM_COLOR = re.compile(
    r"(\bColor\.|(?<![\w.])\.)(green|orange|blue|purple|red|yellow|mint|teal|cyan|indigo|pink)\b"
)
SYSTEM_COLOR_EXCLUDE = re.compile(r"UIColor|\(red:|components\.|\.(red|green|blue)\s*[:=]|\.red\)$")
DISPLAY_WEIGHT = re.compile(r"size:\s*28,\s*weight:\s*\.bold\b")


@dataclass
class Finding:
    check: str
    file: str
    line: int
    detail: str


def on_spacing_scale(value: float) -> bool:
    return value in (0, 1, 2) or value % 4 == 0


def on_radius_scale(value: float) -> bool:
    return value in (0, 2, 999) or value % 4 == 0


def scan(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    for path in sorted((root / SOURCE_ROOT).rglob("*.swift")):
        rel = str(path.relative_to(root))
        text = path.read_text(errors="replace")
        for number, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            for match in SPACING.finditer(line):
                value = float(match.group(1))
                if not on_spacing_scale(value):
                    findings.append(Finding("spacing_scale", rel, number, f"{match.group(0).strip()} is off the 4px grid"))
            for match in RADIUS.finditer(line):
                value = float(match.group(1))
                if not on_radius_scale(value):
                    findings.append(Finding("radius_scale", rel, number, f"{match.group(0).strip()} is off the radius scale"))
            if rel not in TOKEN_HOMES and RAW_HEX.search(line):
                findings.append(Finding("raw_hex_color", rel, number, "raw hex colour outside the token homes"))
            if rel not in TOKEN_HOMES and not SYSTEM_COLOR_EXCLUDE.search(line):
                for match in SYSTEM_COLOR.finditer(line):
                    findings.append(Finding("system_color", rel, number, f"raw system colour .{match.group(2)}; use a palette token"))
            if DISPLAY_WEIGHT.search(line):
                findings.append(Finding("display_weight", rel, number, "type 28 must be 620/semibold, not bold"))
    return findings


def counts_by_file(findings: list[Finding]) -> dict[str, dict[str, int]]:
    table: dict[str, Counter[str]] = defaultdict(Counter)
    for finding in findings:
        table[finding.check][finding.file] += 1
    return {check: dict(sorted(files.items())) for check, files in sorted(table.items())}


def load_baseline(path: Path) -> dict[str, dict[str, int]]:
    if not path.exists():
        return {}
    text = path.read_text().strip()
    if not text:
        return {}
    payload = json.loads(text)
    return payload.get("counts", {})


def regressions(current: dict[str, dict[str, int]], baseline: dict[str, dict[str, int]]) -> list[str]:
    problems: list[str] = []
    for check, files in current.items():
        allowed = baseline.get(check, {})
        for file, count in files.items():
            limit = allowed.get(file, 0)
            if count > limit:
                problems.append(f"{check}: {file} has {count} finding(s); baseline allows {limit}")
    return problems


def write_outputs(artifact_dir: Path, findings: list[Finding], problems: list[str], current: dict) -> None:
    artifact_dir.mkdir(parents=True, exist_ok=True)
    status = "failed" if problems else "passed"
    totals = {check: sum(files.values()) for check, files in current.items()}
    payload = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "totals": totals,
        "regressions": problems,
        "findings": [asdict(finding) for finding in findings],
    }
    (artifact_dir / "optical-grid-audit.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    lines = ["# Optical Grid Audit", "", f"- Status: {status.capitalize()}", f"- Findings: {len(findings)}", f"- Regressions vs baseline: {len(problems)}", ""]
    lines.append("## Totals by detector")
    lines.append("")
    for check, total in sorted(totals.items()):
        lines.append(f"- `{check}`: {total}")
    if problems:
        lines.extend(["", "## Regressions", ""])
        lines.extend(f"- {problem}" for problem in problems)
    (artifact_dir / "optical-grid-audit.md").write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--artifact-dir", type=Path, default=None)
    parser.add_argument("--baseline", type=Path, default=None)
    parser.add_argument("--update-baseline", action="store_true", help="Rewrite the baseline from the current scan (shrink only).")
    args = parser.parse_args()

    root = args.root.resolve()
    baseline_path = (args.baseline or (root / DEFAULT_BASELINE)).resolve()
    findings = scan(root)
    current = counts_by_file(findings)

    if args.update_baseline:
        previous = load_baseline(baseline_path)
        grew = regressions(current, previous) if previous else []
        if grew:
            print("Refusing to grow the baseline:", file=sys.stderr)
            for problem in grew:
                print(f"  {problem}", file=sys.stderr)
            return 2
        baseline_path.write_text(json.dumps({"schemaVersion": 1, "counts": current}, indent=2, sort_keys=True) + "\n")
        print(f"Baseline written to {baseline_path} ({len(findings)} finding(s)).")
        return 0

    problems = regressions(current, load_baseline(baseline_path))
    if args.artifact_dir:
        write_outputs(args.artifact_dir, findings, problems, current)

    totals = {check: sum(files.values()) for check, files in current.items()}
    print(f"Optical grid audit: {len(findings)} finding(s) across {len(totals)} detector(s); {len(problems)} regression(s).")
    for check, total in sorted(totals.items()):
        print(f"  {check}: {total}")
    for problem in problems:
        print(f"REGRESSION {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
