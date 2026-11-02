#!/usr/bin/env python3
"""Write launch UI regression audit artifacts.

Extracted from launch-ui-regression-audit.py so that module stays within
the company 500-line ratchet. The audit loads this sibling by path.
"""

from __future__ import annotations

import json
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path


def write_outputs(artifact_dir: Path, violations: list) -> None:
    artifact_dir.mkdir(parents=True, exist_ok=True)
    status = "failed" if violations else "passed"
    payload = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "violations": [asdict(violation) for violation in violations],
    }
    (artifact_dir / "launch-ui-regression-audit.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n"
    )

    lines = [
        "# Launch UI Regression Audit",
        "",
        f"- Status: {status.capitalize()}",
        f"- Violations: {len(violations)}",
        "",
    ]

    if violations:
        lines.extend(["## Violations", ""])
        for violation in violations:
            lines.append(
                f"- `{violation.check}` at `{violation.file}:{violation.line}`: "
                f"{violation.detail}"
            )
    else:
        lines.extend(
            [
                "## Covered Contracts",
                "",
                "- Geometry constructors explicitly type non-finite constants to avoid Swift overload ambiguity.",
                "- Dashboard ScrollViews do not use large fake bottom spacers that create dead over-scroll.",
                "- Onboarding fixed-CTA screens use size-based vertical scroll bounce to avoid empty over-scroll.",
                "- The removed bottom stats-card hook stays out of app source.",
                "- Body Score share cards expose layout anchors for UI assertions.",
                "- Body Score share cards preserve actual photo aspect defaults instead of forcing one crop.",
                "- Body Score sharing resolves the actual progress photo before presenting the sheet.",
                "- Today and Progress provenance sheets dismiss through their presenting state binding.",
                "- The dashboard avatar visual fills a full-width black stage while preserving each transparent asset's native aspect ratio.",
                "- Dashboard/HUD launch surfaces stay on theme-backed glass or flat surface treatments.",
                "- Timeline/Stats swipe navigation changes page on release, not during drag updates.",
                "- Paid users default directly into the timeline HUD without a Statsig or legacy fallback gate.",
                "- Chat composer stays pinned to the home hero; Timeline/Stats use Jovie swipe and menu, not top tabs.",
                "- Timeline positions follow the injected calendar day, not elapsed 86400-second offsets.",
            ]
        )

    (artifact_dir / "launch-ui-regression-audit.md").write_text("\n".join(lines) + "\n")
