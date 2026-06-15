#!/usr/bin/env python3
"""Static SwiftUI performance smell checks for launch-critical iOS surfaces."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class PerformanceSmell:
    check: str
    file: str
    line: int
    detail: str


def line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def add_pattern_smells(
    *,
    root: Path,
    paths: list[Path],
    pattern: re.Pattern[str],
    check: str,
    detail: str,
    smells: list[PerformanceSmell],
) -> None:
    for path in paths:
        if not path.is_file():
            continue
        text = path.read_text(errors="replace")
        for match in pattern.finditer(text):
            smells.append(
                PerformanceSmell(
                    check=check,
                    file=str(path.relative_to(root)),
                    line=line_number(text, match.start()),
                    detail=detail,
                )
            )


def write_outputs(artifact_dir: Path, smells: list[PerformanceSmell]) -> None:
    artifact_dir.mkdir(parents=True, exist_ok=True)
    status = "failed" if smells else "passed"
    payload = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "smells": [asdict(smell) for smell in smells],
    }
    (artifact_dir / "swiftui-performance-smell-audit.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n"
    )

    lines = [
        "# SwiftUI Performance Smell Audit",
        "",
        f"- Status: {status.capitalize()}",
        f"- Smells: {len(smells)}",
        "",
    ]

    if smells:
        lines.extend(["## Smells", ""])
        for smell in smells:
            lines.append(f"- `{smell.check}` at `{smell.file}:{smell.line}`: {smell.detail}")
    else:
        lines.extend(
            [
                "## Covered Contracts",
                "",
                "- Launch-critical SwiftUI views do not decode images from raw data inside render paths.",
                "- Launch-critical timeline controls do not filter, sort, or map collections inline inside `ForEach`.",
                "- Launch-critical views do not create per-render UUID identities for stable visual rows.",
            ]
        )

    (artifact_dir / "swiftui-performance-smell-audit.md").write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--artifact-dir", type=Path, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    app_dir = root / "apps/ios/LogYourBody"
    launch_critical_files = [
        app_dir / "Views/DashboardViewLiquid.swift",
        app_dir / "Views/DashboardViewLiquid+PhotoTimelineHUD.swift",
        app_dir / "Views/DashboardViewLiquid+Components.swift",
        app_dir / "Views/DashboardViewLiquid+HomeTimelineControls.swift",
        app_dir / "Views/DashboardViewLiquid+HeroAndActions.swift",
        app_dir / "Components/AvatarBodyRenderer.swift",
        app_dir / "Components/BodyScoreShareCard.swift",
        app_dir / "Components/GlobalTimelineHeader.swift",
        app_dir / "Components/LiquidGlassTimelineSlider.swift",
        app_dir / "Components/PhotoAnchoredTimelineSlider.swift",
        app_dir / "Components/ProgressTimelineView.swift",
    ]
    smells: list[PerformanceSmell] = []

    add_pattern_smells(
        root=root,
        paths=launch_critical_files,
        pattern=re.compile(r"Image\s*\(\s*uiImage:\s*UIImage\s*\(\s*data:"),
        check="swiftui.no_render_path_image_decode",
        detail="Decode/downsample image data before SwiftUI render work starts.",
        smells=smells,
    )

    add_pattern_smells(
        root=root,
        paths=launch_critical_files,
        pattern=re.compile(r"ForEach\s*\([^)]*\.(?:filter|sorted|map)\s*(?:\{|\\\()", re.MULTILINE),
        check="swiftui.no_inline_collection_transform_in_foreach",
        detail="Precompute collection transforms before `ForEach` so body updates stay cheap.",
        smells=smells,
    )

    add_pattern_smells(
        root=root,
        paths=launch_critical_files,
        pattern=re.compile(r"(?:var|let)\s+id\s*=\s*UUID\s*\(\s*\)"),
        check="swiftui.no_per_render_uuid_identity",
        detail="Use stable domain identity for launch-critical visual rows and cards.",
        smells=smells,
    )

    write_outputs(args.artifact_dir, smells)
    if smells:
        print(f"SwiftUI performance smell audit failed with {len(smells)} smell(s).")
        for smell in smells:
            print(f"- {smell.check}: {smell.file}:{smell.line} {smell.detail}")
    else:
        print("SwiftUI performance smell audit passed.")
    return 1 if smells else 0


if __name__ == "__main__":
    sys.exit(main())
