#!/usr/bin/env python3
"""Add a selector-specific whole-app ratchet to existing real XCTest evidence."""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path
import subprocess
import sys

APP_PREFIX = "apps/ios/LogYourBody/"
EMPTY_PATCH = hashlib.sha256(b"").hexdigest()
SELECTORS = {
    "quality-unit": {"scheme": "LogYourBody", "onlyTesting": "LogYourBodyTests", "testPlan": None},
    "unit-tier": {"scheme": "LogYourBodyTiers", "onlyTesting": None, "testPlan": "Unit"},
}


def counts(row):
    covered, executable = row.get("coveredLines"), row.get("executableLines")
    if type(covered) is not int or type(executable) is not int or not 0 <= covered <= executable or executable <= 0:
        raise ValueError("Invalid covered/executable line counts")
    return covered, executable


def validate_baseline_change(current, previous, tracked_sources):
    if current.get("target") != previous.get("target") or current.get("longTermTargetPercent", 0) < previous.get("longTermTargetPercent", 0):
        raise ValueError("Baseline target cannot be lowered or replaced")
    for name, old in previous["profiles"].items():
        new = current["profiles"].get(name)
        if new is None or new.get("selector") != old.get("selector"):
            raise ValueError("Existing selector profile cannot be removed or changed")
        nc, ne = counts(new)
        oc, oe = counts(old)
        if nc * oe < oc * ne or not set(old["requiredTests"]) <= set(new["requiredTests"]):
            raise ValueError("Baseline coverage or required native cases cannot be weakened")
    removed = set(previous["appSourceFiles"]) - set(current["appSourceFiles"])
    if removed & tracked_sources:
        raise ValueError("Cannot remove retained app sources from the baseline inventory")


def validate(report_bytes, evidence, baseline, profile, expected_sha, selector, tracked_sources, required_tests=()):
    if baseline.get("schemaVersion") != 1 or baseline.get("target") != "LogYourBody.app":
        raise ValueError("Unknown baseline schema or app target")
    floor = baseline["profiles"][profile]
    if selector != SELECTORS.get(profile) or floor["selector"] != selector:
        raise ValueError("Coverage belongs to a different native test selector")
    if not re.fullmatch(r"[0-9a-f]{40}", expected_sha) or evidence.get("sourceRevision") != expected_sha:
        raise ValueError("Native evidence is not bound to the expected exact source SHA")
    if evidence.get("status") != "passed" or evidence.get("evidenceKind") != "unit_tests":
        raise ValueError("Passing native unit evidence is required")
    if evidence.get("sourcePatchSha256") != EMPTY_PATCH:
        raise ValueError("Dirty or unknown source patch is not exact-head proof")
    if hashlib.sha256(report_bytes).hexdigest() != evidence.get("coverageSha256"):
        raise ValueError("Raw coverage does not match the native evidence digest")
    report = json.loads(report_bytes)
    targets = [t for t in report["targets"] if t.get("name") == baseline["target"]]
    if len(targets) != 1:
        raise ValueError("Missing or duplicate app target")
    target = targets[0]
    covered, executable = counts(target)
    ratio = target.get("lineCoverage")
    if type(ratio) not in (int, float) or not math.isfinite(ratio) or abs(ratio - covered / executable) > 1e-12:
        raise ValueError("Coverage fraction disagrees with the actual line counts")
    files = target.get("files", [])
    paths = []
    totals = [0, 0]
    for file in files:
        marker = "/" + APP_PREFIX
        path = file.get("path", "")
        if marker not in path:
            raise ValueError("Non-app source included in the app-target denominator")
        paths.append(path.split(marker, 1)[1])
        c, e = counts(file)
        totals[0] += c
        totals[1] += e
    if len(paths) != len(set(paths)) or totals != [covered, executable]:
        raise ValueError("App coverage files are duplicated, filtered, or inconsistent with target totals")
    missing = set(baseline["appSourceFiles"]) & tracked_sources - set(paths)
    if missing:
        raise ValueError("Retained app source is missing from whole-target coverage: " + ", ".join(sorted(missing)))
    tests = evidence.get("tests", [])
    identifiers = [t.get("identifier") for t in tests]
    if not identifiers or not all(isinstance(i, str) and i for i in identifiers) or len(identifiers) != len(set(identifiers)):
        raise ValueError("Missing or duplicate executed native cases")
    if any(t.get("result") not in ("Passed", "Skipped") for t in tests):
        raise ValueError("Native test failures cannot qualify coverage")
    passed = {t["identifier"] for t in tests if t["result"] == "Passed"}
    required = set(floor["requiredTests"]) | set(required_tests)
    if not passed or not required or not required <= passed:
        raise ValueError("Required risky native case is missing, skipped, or unexecuted")
    fc, fe = counts(floor)
    if covered * fe < fc * executable:
        raise ValueError("Whole-app coverage regressed for the same native selector")
    return {"profile": profile, "sourceRevision": expected_sha, "coveredLines": covered,
            "executableLines": executable, "lineCoverage": covered / executable,
            "passedCases": len(passed), "skippedCases": len(tests) - len(passed),
            "requiredTests": sorted(required), "meaning": "coverage ratchet; skipped and live-provider paths remain unverified"}



def resolve_comparison_base(source_root, head, event_base):
    """Use the trusted event base or canonical main, never a draft merge-base."""
    def revision(ref):
        return subprocess.check_output(["git", "-C", str(source_root), "rev-parse",
                                        "--verify", ref + "^{commit}"], text=True).strip()
    if event_base:
        if not re.fullmatch(r"[0-9a-f]{40}", event_base):
            raise ValueError("An exact trusted CI base revision is required")
        if revision(event_base) != event_base:
            raise ValueError("Event comparison base is not an exact commit")
        return event_base
    canonical = revision("refs/remotes/origin/main")
    if not re.fullmatch(r"[0-9a-f]{40}", canonical):
        raise ValueError("Missing trusted canonical main comparison base")
    # Only canonical main itself may compare against its prior commit.
    return revision(canonical + "^") if head == canonical else canonical


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--coverage", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--base-revision", default="",
                        help="Trusted event base SHA; empty uses fetched canonical origin/main")
    parser.add_argument("--profile", choices=SELECTORS, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--scheme", required=True)
    parser.add_argument("--only-testing")
    parser.add_argument("--test-plan")
    parser.add_argument("--required-test", action="append", default=[])
    args = parser.parse_args()
    try:
        sha = subprocess.check_output(["git", "-C", str(args.source_root), "rev-parse", "HEAD"], text=True).strip()
        if sha != args.source_sha:
            raise ValueError("Checkout differs from expected source SHA")
        paths = subprocess.check_output(["git", "-C", str(args.source_root), "ls-tree", "-r", "--name-only", "HEAD", "--", APP_PREFIX], text=True)
        tracked = {p.removeprefix(APP_PREFIX) for p in paths.splitlines()}
        baseline = json.loads(args.baseline.read_text())
        comparison_base = resolve_comparison_base(args.source_root, sha, args.base_revision)
        baseline_path = "scripts/ios/native-coverage-baseline.json"
        prior_path = subprocess.check_output(["git", "-C", str(args.source_root), "ls-tree",
                                             "--name-only", comparison_base, "--", baseline_path], text=True).strip()
        if prior_path:
            previous = subprocess.check_output(["git", "-C", str(args.source_root), "show",
                                                comparison_base + ":" + baseline_path], text=True)
            validate_baseline_change(baseline, json.loads(previous), tracked)
        receipt = validate(args.coverage.read_bytes(), json.loads(args.evidence.read_text()), baseline,
                           args.profile, args.source_sha,
                           {"scheme": args.scheme, "onlyTesting": args.only_testing, "testPlan": args.test_plan},
                           tracked, args.required_test)
        receipt["baselineBaseRevision"] = comparison_base
        receipt["baselineChange"] = "nonregressing" if prior_path else "initial baseline introduction"
        print(json.dumps(receipt, indent=2))
        return 0
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print("Native coverage ratchet rejected: " + str(error), file=sys.stderr)
        return 65


if __name__ == "__main__":
    sys.exit(main())
