#!/usr/bin/env python3
"""Static SwiftUI performance smell checks for the per-surface contract file sets."""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


spec = importlib.util.spec_from_file_location("swift_performance_guard", Path(__file__).with_name("swift-performance-guard.py"))
guard = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = guard
spec.loader.exec_module(guard)


def write_outputs(artifact_dir: Path, report: dict) -> None:
    artifact_dir.mkdir(parents=True, exist_ok=True)
    regressions = [error for error in report["errors"] if error.startswith("new violation") or error.startswith("stale-high")]
    status = "passed" if report["ok"] else "failed"
    payload = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "surfaceFiles": report["files"],
        "findings": [finding.__dict__ if hasattr(finding, "__dict__") else finding for finding in report["findings"]],
        "errors": report["errors"],
    }
    (artifact_dir / "swiftui-performance-smell-audit.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    lines = [
        "# SwiftUI Performance Smell Audit",
        "",
        f"- Status: {status.capitalize()}",
        f"- Surface files: {report['files']}",
        f"- Live findings: {len(report['findings'])}",
        "",
        "Budgets in the performance contract are proposed targets. This audit ratchets",
        "interaction-path violations on the contract's surface file sets. The baseline may only fall.",
        "",
    ]
    if report["ok"]:
        lines.extend([
            "## Covered contracts",
            "",
            "- Launch, home, stats, share, settings, HealthKit, chat, and paywall surfaces are scanned.",
            "- `performAndWait`, `DispatchSemaphore`, `main.sync`, `Thread.sleep`, and `UIImage(data:)` inside a view body are baselined and may only fall.",
            "- Render-path image decode, inline `ForEach` transforms, and per-render `UUID()` identities stay on the same ratchet.",
            "",
        ])
    else:
        lines.extend(["## Failures", ""])
        lines.extend(f"- {error}" for error in report["errors"])
        lines.append("")
    if regressions:
        lines.extend(["## Ratchet", ""])
        lines.extend(f"- {error}" for error in regressions)
        lines.append("")
    (artifact_dir / "swiftui-performance-smell-audit.md").write_text("\n".join(lines))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--artifact-dir", type=Path, required=True)
    args = parser.parse_args()
    report = guard.interaction_report(args.root.resolve())
    write_outputs(args.artifact_dir, report)
    if report["ok"]:
        print(f"SwiftUI performance smell audit passed ({report['files']} surface files, {len(report['findings'])} baselined findings).")
        return 0
    print(f"SwiftUI performance smell audit failed with {len(report['errors'])} error(s).")
    for error in report["errors"]:
        print(f"- {error}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
