#!/usr/bin/env python3
"""Summarize failed tests from a chaos-testing xcresult bundle into issues.json.

Reads the JSON produced by `xcrun xcresulttool get test-results tests` on
stdin (see scripts/ios/chaos-device.sh), matches failures against the
attachment manifest produced by `xcrun xcresulttool export attachments`, and
writes a small, stable summary: one entry per failed/errored test with its
failure message(s) and the exported screenshot paths for that test.
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

PASSING_RESULTS = {"Passed", "Skipped", "Expected Failure"}


def walk(node):
    yield node
    for child in node.get("children", []):
        yield from walk(child)


def failed_test_cases(payload):
    cases = []
    for root in payload.get("testNodes", []):
        for node in walk(root):
            if node.get("nodeType") == "Test Case" and node.get("result") not in PASSING_RESULTS:
                cases.append(node)
    return cases


def failure_messages(test_node):
    messages = []
    for node in walk(test_node):
        if node.get("nodeType") == "Failure Message":
            name = node.get("name")
            if name:
                messages.append(name)
    return messages


def test_method_name(identifier):
    """The bare test method name ("testFoo"), stripped of "()" and any
    "Target/" or "Target/ClassName/" prefix. The tests-tree nodeIdentifier and
    the attachment manifest's testIdentifier disagree on how many path
    components they include (target/class/method vs. just target/method), so
    matching on the method name alone is the one thing both sides agree on."""
    cleaned = identifier.replace("()", "")
    parts = [part for part in cleaned.split("/") if part]
    return parts[-1] if parts else cleaned


def load_manifest(attachments_dir):
    manifest_path = attachments_dir / "manifest.json"
    if not manifest_path.is_file():
        return []
    return json.loads(manifest_path.read_text())


def screenshots_for(test_identifier, manifest, attachments_dir):
    target_method = test_method_name(test_identifier)
    paths = []
    for entry in manifest:
        entry_test_id = entry.get("testIdentifier", "")
        if test_method_name(entry_test_id) != target_method:
            continue
        for attachment in entry.get("attachments", []):
            exported_name = attachment.get("exportedFileName")
            if exported_name:
                paths.append(str(attachments_dir / exported_name))
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--attachments-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--result-bundle", type=Path, default=None)
    args = parser.parse_args()

    payload = json.load(sys.stdin)
    manifest = load_manifest(args.attachments_dir)

    failed = failed_test_cases(payload)
    issues = []
    for test in failed:
        identifier = test.get("nodeIdentifier") or test.get("name") or "unknown"
        issues.append({
            "test": identifier,
            "result": test.get("result"),
            "messages": failure_messages(test),
            "screenshots": screenshots_for(identifier, manifest, args.attachments_dir),
        })

    summary = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "resultBundle": str(args.result_bundle) if args.result_bundle else None,
        "attachmentsDir": str(args.attachments_dir),
        "failedTestCount": len(issues),
        "issues": issues,
    }

    args.output.write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{len(issues)} failed test(s) written to {args.output}")


if __name__ == "__main__":
    main()
