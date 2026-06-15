#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <result-bundle.xcresult> [more.xcresult ...]" >&2
  exit 64
fi

FAIL_ON_RUNTIME_WARNINGS="${FAIL_ON_RUNTIME_WARNINGS:-false}"
TEMP_OUTPUT="$(mktemp)"
trap 'rm -f "$TEMP_OUTPUT"' EXIT

for result_bundle in "$@"; do
  if [[ ! -d "$result_bundle" ]]; then
    echo "Missing xcresult bundle: $result_bundle" >&2
    exit 66
  fi

  xcrun xcresulttool get test-results tests \
    --path "$result_bundle" \
    --format json |
    python3 -c '
import json
import sys

bundle_path = sys.argv[1]
payload = json.load(sys.stdin)

def walk(node, current_test=None):
    node_type = node.get("nodeType")
    name = node.get("name", "")
    test_id = node.get("nodeIdentifier") or name

    if node_type == "Test Case":
        current_test = test_id

    if node_type == "Runtime Warning":
        print("{}\t{}\t{}".format(bundle_path, current_test or "-", name))

    for child in node.get("children", []):
        walk(child, current_test)

for root in payload.get("testNodes", []):
    walk(root)
' "$result_bundle" >> "$TEMP_OUTPUT"
done

warning_count="$(wc -l < "$TEMP_OUTPUT" | tr -d '[:space:]')"

if [[ "$warning_count" == "0" ]]; then
  echo "No XCTest runtime warnings found."
  exit 0
fi

echo "XCTest runtime warnings found: $warning_count"
cat "$TEMP_OUTPUT"

if [[ "$FAIL_ON_RUNTIME_WARNINGS" == "true" ]]; then
  exit 2
fi
