#!/usr/bin/env python3
"""Per-surface Swift performance contract and shrink-only ratchet.

Budgets in the contract are proposed targets. Current numbers stay blank until
a physical-device receipt exists. A missing device receipt is unverified.
Baseline counts may only fall.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from swift_performance_scan import (  # noqa: E402
    REQUIRED_RECEIPT_FIELDS,
    counts_of,
    fall_only_errors,
    mask_non_code,
    ratchet_errors,
    scan_source,
    signpost_errors,
    uses_concurrent,
    validate_device_receipt,
)
from swift_performance_toolchain import (  # noqa: E402
    PROJECT_REL,
    SCHEMA,
    build_toolchain_receipt,
    parse_project,
    row_enables_concurrent,
    toolchain_drift_errors,
)

CONTRACT_REL = "scripts/ios/swift-performance-contract.json"
RECEIPT_REL = "scripts/ios/swift-performance-toolchain.json"
BASELINE_REL = "scripts/ios/swift-performance-baseline.json"
DEVICE_RECEIPT_REL = "scripts/ios/swift-performance-device-receipt.json"
SURFACES = (
    ("launch-auth-onboarding", "launch/auth/onboarding"),
    ("home-timeline-photos", "home/timeline/photos"),
    ("stats-chart-detail", "stats/chart detail"),
    ("share", "share"),
    ("settings", "settings"),
    ("healthkit-import-sync", "HealthKit/import/sync"),
    ("chat", "chat"),
    ("paywall-account-export", "paywall/account/export"),
)
BLANK_CURRENT = {
    "synchronousUiWorkMs": None,
    "eventToFeedbackP95Ms": None,
    "hitchMsPerSecond": None,
}
LEGACY_SMELL_FILES = (
    "apps/ios/LogYourBody/Views/DashboardViewLiquid.swift",
    "apps/ios/LogYourBody/Views/DashboardViewLiquid+PhotoTimelineHUD.swift",
    "apps/ios/LogYourBody/Views/DashboardViewLiquid+Components.swift",
    "apps/ios/LogYourBody/Views/DashboardViewLiquid+HomeTimelineControls.swift",
    "apps/ios/LogYourBody/Views/DashboardViewLiquid+HeroAndActions.swift",
    "apps/ios/LogYourBody/Components/AvatarBodyRenderer.swift",
    "apps/ios/LogYourBody/Components/BodyScoreShareCard.swift",
    "apps/ios/LogYourBody/Components/GlobalTimelineHeader.swift",
    "apps/ios/LogYourBody/Components/LiquidGlassTimelineSlider.swift",
    "apps/ios/LogYourBody/Components/PhotoAnchoredTimelineSlider.swift",
    "apps/ios/LogYourBody/Components/ProgressTimelineView.swift",
)

BASELINE_POLICY = "Counts may only fall. A stale-high baseline fails until it is lowered to the live tree."


def canonical(payload: dict) -> str:
    return json.dumps(payload, indent=2, sort_keys=True) + "\n"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text())


def contract_errors(contract: dict, device_status: str) -> list[str]:
    errors = []
    policy = str(contract.get("measurementPolicy") or "")
    lowered = policy.lower()
    if "target" not in lowered or "blank" not in lowered or "receipt" not in lowered:
        errors.append("contract must state that budgets are targets and current numbers stay blank until a receipt exists")
    surfaces = contract.get("surfaces")
    if not isinstance(surfaces, list) or [ (item.get("id"), item.get("name")) for item in surfaces ] != list(SURFACES):
        errors.append("contract must list the eight surfaces in order: " + ", ".join(name for _, name in SURFACES))
        return errors
    seen: dict[str, str] = {}
    for surface in surfaces:
        sid = surface["id"]
        acknowledgement = str(surface.get("localAcknowledgement") or "").strip()
        if not acknowledgement:
            errors.append(f"{sid} needs a local-acknowledgement point")
        names = surface.get("signposts")
        if not isinstance(names, list) or not names or not all(isinstance(name, str) and name for name in names):
            errors.append(f"{sid} needs signpost names")
            names = []
        for name in names:
            if name in seen:
                errors.append(f"signpost {name} is listed on both {seen[name]} and {sid}")
            seen[name] = sid
        targets = surface.get("targets") if isinstance(surface.get("targets"), dict) else {}
        if targets.get("kind") != "proposed-target":
            errors.append(f"{sid} targets must be marked proposed-target")
        if targets.get("synchronousUiWorkMs") != 5 or targets.get("eventToFeedbackP95Ms") != 100 or targets.get("hitchCeilingMsPerSecond") != 10:
            errors.append(f"{sid} must keep the proposed targets of 5ms, p95 100ms, and 10ms/s hitches")
        current = targets.get("current")
        if device_status != "verified":
            if current != BLANK_CURRENT:
                errors.append(f"{sid} current numbers must stay blank until a verified device receipt exists")
        elif not _current_values_ok(current):
            errors.append(f"{sid} current measurements must be numbers or blank")
        if not isinstance(surface.get("files"), list) or not surface["files"]:
            errors.append(f"{sid} needs a file set")
    signpost_build = contract.get("signpostBuild") if isinstance(contract.get("signpostBuild"), dict) else {}
    if signpost_build.get("compilationCondition") != "LYB_PERF_TRACE" or signpost_build.get("appStoreRelease") != "excluded":
        errors.append("signposts must be an opt-in LYB_PERF_TRACE build and stay out of the App Store release")
    requires = (contract.get("deviceReceipt") or {}).get("physicalPassRequires") if isinstance(contract.get("deviceReceipt"), dict) else None
    if list(requires or []) != list(REQUIRED_RECEIPT_FIELDS):
        errors.append("contract device-receipt fields must be device, os, buildSha, thermalState, refreshRateHz, fixtureId")
    return errors


def _current_values_ok(current: object) -> bool:
    if not isinstance(current, dict):
        return False
    if set(current) != set(BLANK_CURRENT):
        return False
    return all(value is None or isinstance(value, (int, float)) for value in current.values())


def resolve_surface_files(root: Path, contract: dict) -> tuple[dict[str, list[Path]], list[str]]:
    resolved: dict[str, list[Path]] = {}
    empty = []
    for surface in contract.get("surfaces") or []:
        found: set[Path] = set()
        for pattern in surface.get("files") or []:
            found.update(path for path in root.glob(pattern) if path.is_file() and path.suffix == ".swift")
        files = sorted(found)
        resolved[surface.get("id", "")] = files
        if not files:
            empty.append(str(surface.get("id")))
    return resolved, empty


def scan_surfaces(root: Path, contract: dict) -> tuple[list[Finding], list[str]]:
    resolved, empty = resolve_surface_files(root, contract)
    errors = [f"surface {sid} resolved no Swift files" for sid in empty]
    seen: set[Path] = set()
    findings: list[Finding] = []
    for files in resolved.values():
        for path in files:
            if path in seen:
                continue
            seen.add(path)
            relative = path.relative_to(root).as_posix()
            findings.extend(scan_source(relative, path.read_text(errors="replace")))
    return findings, errors


def legacy_coverage_errors(resolved_paths: set[str]) -> list[str]:
    missing = [path for path in LEGACY_SMELL_FILES if path not in resolved_paths]
    if not missing:
        return []
    return ["SwiftUI smell audit dropped legacy surface files: " + ", ".join(missing)]


def production_swift(root: Path) -> list[Path]:
    files: list[Path] = []
    for folder in ("apps/ios/LogYourBody", "apps/ios/LogYourBodyWidget"):
        base = root / folder
        if not base.exists():
            continue
        for path in base.rglob("*.swift"):
            if any(part in {"Vendor", "build", "DerivedData", "Preview Content"} for part in path.parts):
                continue
            files.append(path)
    return sorted(files)


def trace_gate_errors(text: str) -> list[str]:
    masked_lines = mask_non_code(text).splitlines()
    stack: list[str] = []
    gated = 0
    unguarded = []
    for number, code in enumerate(masked_lines, start=1):
        stripped = code.strip()
        if stripped.startswith("#if"):
            stack.append(stripped[3:].strip())
        elif stripped.startswith("#elseif") and stack:
            stack[-1] = stripped[len("#elseif"):].strip()
        elif stripped.startswith("#else") and stack:
            stack[-1] = "!"
        elif stripped.startswith("#endif") and stack:
            stack.pop()
        if "OSSignposter" not in code:
            continue
        if any(frame.strip() == "LYB_PERF_TRACE" for frame in stack):
            gated += 1
        else:
            unguarded.append(str(number))
    if unguarded:
        return ["OSSignposter must compile only inside #if LYB_PERF_TRACE (lines " + ", ".join(unguarded) + ")"]
    if gated == 0:
        return ["OSSignposter must compile inside #if LYB_PERF_TRACE so signposts stay out of the App Store binary"]
    return []


def release_trace_errors(rows: list[dict]) -> list[str]:
    enabled = [f"{row['target']} {row['config']}" for row in rows if row["trace"]]
    if not enabled:
        return []
    message = "LYB_PERF_TRACE is committed for " + ", ".join(enabled) + "; trace builds stay opt-in and out of checked-in configurations"
    if any(row["trace"] and row["target"] == "LogYourBody" and row["config"] == "Release" for row in rows):
        message = "App Store Release compiles perf signposts. " + message
    return [message]


def parse_baseline(payload: dict) -> dict[str, int]:
    if payload.get("schemaVersion") != SCHEMA or "may only fall" not in str(payload.get("policy") or ""):
        raise ValueError("invalid performance baseline")
    counts = payload.get("counts")
    if not isinstance(counts, dict):
        raise ValueError("invalid performance baseline")
    parsed = {}
    for key, value in counts.items():
        if not isinstance(key, str) or not isinstance(value, int) or value < 1:
            raise ValueError(f"invalid baseline count for {key}")
        parsed[key] = value
    return parsed


def ancestor_counts(root: Path, base_ref: str) -> dict[str, int] | None:
    try:
        output = subprocess.check_output(
            ["git", "show", f"{base_ref}:{BASELINE_REL}"],
            cwd=root,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return parse_baseline(json.loads(output.decode()))


def allowed_signposts(contract: dict) -> set[str]:
    names: set[str] = set()
    for surface in contract.get("surfaces") or []:
        for name in surface.get("signposts") or []:
            names.add(name)
    return names


def interaction_report(root: Path, contract: dict | None = None, baseline: dict[str, int] | None = None, base_ref: str | None = "origin/main") -> dict:
    root = root.resolve()
    contract = contract if contract is not None else load_json(root / CONTRACT_REL)
    findings, resolve_errors = scan_surfaces(root, contract)
    resolved, _empty = resolve_surface_files(root, contract)
    paths = {path.relative_to(root).as_posix() for files in resolved.values() for path in files}
    errors = list(resolve_errors)
    if baseline is None:
        try:
            baseline = parse_baseline(load_json(root / BASELINE_REL))
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            return {"ok": False, "errors": errors + [f"performance baseline unreadable: {exc}"], "findings": findings, "files": len(paths), "live": counts_of(findings)}
    errors.extend(legacy_coverage_errors(paths))
    live = counts_of(findings)
    errors.extend(ratchet_errors(live, baseline))
    if base_ref:
        errors.extend(fall_only_errors(baseline, ancestor_counts(root, base_ref)))
    return {
        "ok": not errors,
        "errors": errors,
        "findings": findings,
        "files": len(paths),
        "live": live,
    }


def evaluate(root: Path, base_ref: str | None = "origin/main", device_payload: object | None = None, use_device_file: bool = True) -> dict:
    root = root.resolve()
    errors: list[str] = []
    contract_path = root / CONTRACT_REL
    receipt_path = root / RECEIPT_REL
    project_path = root / PROJECT_REL
    try:
        contract = load_json(contract_path)
    except (OSError, json.JSONDecodeError) as exc:
        return {"ok": False, "errors": [f"contract unreadable: {exc}"], "deviceReceipt": "unverified", "findings": []}
    if use_device_file:
        device_path = root / DEVICE_RECEIPT_REL
        if device_path.is_file():
            try:
                device_payload = load_json(device_path)
            except json.JSONDecodeError as exc:
                errors.append(f"device receipt unreadable: {exc}")
                device_payload = False
        else:
            device_payload = None
    if device_payload is False:
        device_status = "rejected"
        device_errors: list[str] = []
    else:
        device_status, device_errors = validate_device_receipt(device_payload)
    errors.extend(device_errors)
    errors.extend(contract_errors(contract, "verified" if device_status == "verified" else "missing"))
    try:
        project_text = project_path.read_text()
    except OSError as exc:
        errors.append(f"Xcode project unreadable: {exc}")
        project_text = ""
    rows = parse_project(project_text) if project_text else []
    live_receipt = build_toolchain_receipt(project_text) if project_text else {}
    try:
        committed_receipt = load_json(receipt_path)
    except (OSError, json.JSONDecodeError) as exc:
        committed_receipt = None
        errors.append(f"toolchain receipt unreadable: {exc}")
    if committed_receipt is not None and live_receipt:
        errors.extend(toolchain_drift_errors(live_receipt, committed_receipt))
    errors.extend(release_trace_errors(rows))
    app_enabled = bool(live_receipt.get("concurrentAttributeEnabled"))
    widget_rows = [row for row in rows if row["target"] == "LogYourBodyRestTimer"]
    widget_enabled = bool(widget_rows) and all(row_enables_concurrent(row) for row in widget_rows)
    for path in production_swift(root):
        text = path.read_text(errors="replace")
        relative = path.relative_to(root).as_posix()
        if uses_concurrent(text):
            enabled = widget_enabled if relative.startswith("apps/ios/LogYourBodyWidget/") else app_enabled
            if not enabled:
                errors.append(f"@concurrent in {relative} while the toolchain receipt does not enable it")
        errors.extend(signpost_errors(text, allowed_signposts(contract), relative))
    signpost_path = root / "apps/ios/LogYourBody/Utils/PerfSignpost.swift"
    if signpost_path.is_file():
        errors.extend(trace_gate_errors(signpost_path.read_text(errors="replace")))
    else:
        errors.append("PerfSignpost.swift is missing")
    report = interaction_report(root, contract, base_ref=base_ref)
    errors.extend(report["errors"])
    return {
        "ok": not errors,
        "errors": errors,
        "deviceReceipt": device_status,
        "findings": [asdict(finding) for finding in report["findings"]],
        "files": report["files"],
        "toolchain": {
            "SWIFT_VERSION": live_receipt.get("SWIFT_VERSION"),
            "swiftLanguageMode": live_receipt.get("swiftLanguageMode"),
            "defaultActorIsolation": live_receipt.get("defaultActorIsolation"),
            "concurrentAttributeEnabled": live_receipt.get("concurrentAttributeEnabled"),
        },
    }


def write_baseline(path: Path, counts: dict[str, int]) -> int:
    previous = None
    if path.is_file():
        previous = parse_baseline(load_json(path))
        raised = fall_only_errors(counts, previous)
        if raised:
            for line in raised:
                print(f"swift-performance-guard: {line}")
            return 2
    payload = {"schemaVersion": SCHEMA, "kind": "lyb.swift-performance-baseline", "policy": BASELINE_POLICY, "counts": counts}
    path.write_text(canonical(payload))
    print(f"Wrote {path}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--artifact-dir", type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--write-baseline", action="store_true")
    parser.add_argument("--write-toolchain-receipt", action="store_true")
    parser.add_argument("--base-ref", default="origin/main")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    if args.write_toolchain_receipt:
        receipt = build_toolchain_receipt((root / PROJECT_REL).read_text())
        destination = root / RECEIPT_REL
        destination.write_text(canonical(receipt))
        print(f"Wrote {destination}")
        return 0
    if args.write_baseline:
        contract = load_json(root / CONTRACT_REL)
        findings, resolve_errors = scan_surfaces(root, contract)
        if resolve_errors:
            for line in resolve_errors:
                print(f"swift-performance-guard: {line}")
            return 1
        return write_baseline(root / BASELINE_REL, counts_of(findings))
    report = evaluate(root, base_ref=args.base_ref or None)
    if args.artifact_dir:
        args.artifact_dir.mkdir(parents=True, exist_ok=True)
        (args.artifact_dir / "swift-performance-guard.json").write_text(canonical({
            "schemaVersion": SCHEMA,
            "ok": report["ok"],
            "deviceReceipt": report["deviceReceipt"],
            "errors": report["errors"],
            "toolchain": report.get("toolchain"),
            "files": report.get("files"),
        }))
    for error in report["errors"]:
        print(f"swift-performance-guard: {error}")
    state = "passed" if report["ok"] else "failed"
    print(f"swift-performance-guard: {state}; device receipt: {report['deviceReceipt']}; surface files: {report.get('files', 0)}")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
