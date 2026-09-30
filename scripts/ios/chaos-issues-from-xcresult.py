#!/usr/bin/env python3
"""Summarize failed tests from a chaos-testing xcresult bundle into issues.json.

Reads the JSON produced by `xcrun xcresulttool get test-results tests` on
stdin (see scripts/ios/chaos-device.sh), matches failures against the
attachment manifest produced by `xcrun xcresulttool export attachments`, and
writes a small, stable summary: one entry per failed/errored test with its
failure message(s), source file:line (when the message carries one), its
duration, and every exported attachment for that test (screenshots and tree
dumps alike). `testChaosMonkey` additionally gets its per-step anomaly lines
parsed out of its own summary attachment and grouped by reason, whether the
run passed or failed, since a passing run can still have recovered from
several stuck episodes worth surfacing. A run that ends because the runner
itself crashed (device auto-lock, signal kill, "encountered an error") is
still one issue entry, with the last monkey step reached inferred from the
last per-step diagnostic attachment actually exported before the crash.
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

PASSING_RESULTS = {"Passed", "Skipped", "Expected Failure"}

# "ChaosEdgeCaseUITests.swift:178: XCTAssertEqual failed: ..." -> file/line.
FAILURE_LOCATION_RE = re.compile(r"^(?P<file>[\w.+-]+\.(?:swift|m|mm)):(?P<line>\d+):\s*(?P<detail>.*)$")

# "step 17: recovered from a stuck screen (...); relaunched" -> step/reason.
STEP_LINE_RE = re.compile(r"^step (?P<step>\d+):\s*(?P<reason>.*)$")

# "chaos-<seed>-step-<n>[-anomaly][-tree]" in an exported attachment's
# suggested name -> the step number, used to infer how far a run got when it
# ended before writing its own summary attachment.
STEP_ATTACHMENT_RE = re.compile(r"-step-(\d+)(?:-anomaly)?[_.\-]")

SCREENSHOT_EXTENSIONS = (".png", ".jpg", ".jpeg", ".heic")


def walk(node):
    yield node
    for child in node.get("children", []):
        yield from walk(child)


def all_test_cases(payload):
    cases = []
    for root in payload.get("testNodes", []):
        for node in walk(root):
            if node.get("nodeType") == "Test Case":
                cases.append(node)
    return cases


def failed_test_cases(payload):
    return [test for test in all_test_cases(payload) if test.get("result") not in PASSING_RESULTS]


def failure_messages(test_node):
    messages = []
    for node in walk(test_node):
        if node.get("nodeType") == "Failure Message":
            name = node.get("name")
            if name:
                messages.append(name)
    return messages


def parse_location(message):
    match = FAILURE_LOCATION_RE.match(message)
    if not match:
        return None
    return {"file": match.group("file"), "line": int(match.group("line"))}


def duration_seconds(test_node):
    value = test_node.get("durationInSeconds")
    return value if isinstance(value, (int, float)) else None


def test_method_name(identifier):
    """The bare test method name ("testFoo"), stripped of "()" and any
    "Target/" or "Target/ClassName/" prefix. The tests-tree nodeIdentifier and
    the attachment manifest's testIdentifier disagree on how many path
    components they include (target/class/method vs. just target/method), so
    matching on the method name alone is the one thing both sides agree on."""
    cleaned = identifier.replace("()", "")
    parts = [part for part in cleaned.split("/") if part]
    return parts[-1] if parts else cleaned


def is_monkey_related(identifier):
    lowered = identifier.lower()
    return "chaosmonkey" in lowered or "runner" in lowered or "encountered an error" in lowered


def load_manifest(attachments_dir):
    manifest_path = attachments_dir / "manifest.json"
    if not manifest_path.is_file():
        return []
    return json.loads(manifest_path.read_text())


def attachments_for(test_identifier, manifest, attachments_dir):
    target_method = test_method_name(test_identifier)
    results = []
    for entry in manifest:
        if test_method_name(entry.get("testIdentifier", "")) != target_method:
            continue
        for attachment in entry.get("attachments", []):
            exported_name = attachment.get("exportedFileName")
            if not exported_name:
                continue
            results.append({
                "name": attachment.get("suggestedHumanReadableName", exported_name),
                "path": str(attachments_dir / exported_name),
            })
    return results


def is_screenshot(attachment):
    return attachment["path"].lower().endswith(SCREENSHOT_EXTENSIONS)


def read_text_attachment(attachment):
    try:
        return Path(attachment["path"]).read_text()
    except OSError:
        return None


def monkey_summary_text(test_identifier, manifest, attachments_dir):
    for attachment in attachments_for(test_identifier, manifest, attachments_dir):
        if attachment["path"].endswith(".txt") and "summary" in attachment["name"].lower():
            text = read_text_attachment(attachment)
            if text:
                return text
    return None


def classify_anomaly(reason):
    lowered = reason.lower()
    if "layout defect" in lowered:
        return "layout"
    if "stuck screen" in lowered:
        return "stuck-recovered"
    if "paywall" in lowered:
        return "paywall-escape"
    if "left the foreground" in lowered or "not foreground" in lowered:
        return "app-not-foreground"
    if "query took" in lowered or "slow" in lowered:
        return "slow-query"
    if "blank" in lowered:
        return "blank-screen"
    return "other"


def parse_monkey_anomalies(summary_text):
    if not summary_text:
        return None
    lines = summary_text.splitlines()
    steps = []
    grouped = {}
    for line in lines:
        match = STEP_LINE_RE.match(line)
        if not match:
            continue
        reason = match.group("reason")
        category = classify_anomaly(reason)
        grouped[category] = grouped.get(category, 0) + 1
        steps.append({"step": int(match.group("step")), "reason": reason, "category": category})
    return {
        "header": lines[0] if lines else "",
        "anomalyCount": len(steps),
        "byCategory": grouped,
        "anomalies": steps,
    }


def last_step_reached(manifest):
    """Infers the last monkey step reached from exported attachment names
    when the run ended before writing its own final summary (a runner
    crash mid-run, e.g. the device auto-locking)."""
    best = None
    for entry in manifest:
        for attachment in entry.get("attachments", []):
            match = STEP_ATTACHMENT_RE.search(attachment.get("suggestedHumanReadableName", ""))
            if match:
                step = int(match.group(1))
                best = step if best is None else max(best, step)
    return best


def build_issue(test_node, manifest, attachments_dir, last_step):
    identifier = test_node.get("nodeIdentifier") or test_node.get("name") or "unknown"
    messages = failure_messages(test_node)
    location = parse_location(messages[0]) if messages else None
    attachments = attachments_for(identifier, manifest, attachments_dir)

    issue = {
        "test": identifier,
        "result": test_node.get("result"),
        "durationSeconds": duration_seconds(test_node),
        "messages": messages,
        "file": location["file"] if location else None,
        "line": location["line"] if location else None,
        "attachments": attachments,
        "screenshots": [a["path"] for a in attachments if is_screenshot(a)],
    }

    if test_method_name(identifier) == "testChaosMonkey":
        issue["monkeySummary"] = parse_monkey_anomalies(
            monkey_summary_text(identifier, manifest, attachments_dir)
        )
        if issue["monkeySummary"] is None:
            issue["lastStepReached"] = last_step
    elif is_monkey_related(identifier):
        # A runner-crash pseudo-test ("LogYourBodyUITests-Runner (8718)
        # encountered an error") has no attachments of its own; the last
        # step the monkey reached still lives in the manifest globally.
        issue["lastStepReached"] = last_step

    return issue


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--attachments-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--result-bundle", type=Path, default=None)
    args = parser.parse_args()

    payload = json.load(sys.stdin)
    manifest = load_manifest(args.attachments_dir)
    last_step = last_step_reached(manifest)

    failed = failed_test_cases(payload)
    issues = [build_issue(test, manifest, args.attachments_dir, last_step) for test in failed]

    # Surface the monkey's anomaly breakdown even when it isn't in `issues`
    # (i.e. the run passed) -- a green run can still have recovered from
    # several stuck episodes, which is exactly the signal worth triaging.
    monkey_summary = None
    if not any(test_method_name(issue["test"]) == "testChaosMonkey" for issue in issues):
        monkey_node = next(
            (t for t in all_test_cases(payload)
             if test_method_name(t.get("nodeIdentifier", "")) == "testChaosMonkey"),
            None,
        )
        if monkey_node is not None:
            monkey_summary = parse_monkey_anomalies(
                monkey_summary_text(monkey_node.get("nodeIdentifier", ""), manifest, args.attachments_dir)
            )

    summary = {
        "schemaVersion": 2,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "resultBundle": str(args.result_bundle) if args.result_bundle else None,
        "attachmentsDir": str(args.attachments_dir),
        "failedTestCount": len(issues),
        "issues": issues,
        "monkeySummary": monkey_summary,
    }

    args.output.write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{len(issues)} failed test(s) written to {args.output}")


if __name__ == "__main__":
    main()
