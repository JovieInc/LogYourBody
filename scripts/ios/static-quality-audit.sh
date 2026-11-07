#!/usr/bin/env bash
# The launch-quality checks that need no Xcode or simulator: SwiftLint (strict), the SwiftUI performance smell
# audit, the static launch UI regression audit, the optical-grid ratchet, the evidence validator tests, the
# size-500 split ratchet, and the static performance budget summary. CI runs this on ubuntu so hosted macOS
# minutes go only to xcodebuild.
# launch-quality-audit.sh and performance-audit.sh run the same checks when ios-quality.yml is called with
# static-audits=true (post-merge and manual dispatch).
#
# Env: ARTIFACT_DIR (default apps/ios/test_results/static-quality), SWIFTLINT (default: swiftlint on PATH).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/apps/ios/test_results/static-quality}"
SWIFTLINT="${SWIFTLINT:-swiftlint}"
mkdir -p "$ARTIFACT_DIR"

(cd "$ROOT_DIR/apps/ios" && "$SWIFTLINT" lint --strict | tee "$ARTIFACT_DIR/swiftlint.log")

python3 "$ROOT_DIR/scripts/ios/launch-ui-regression-audit.py" --root "$ROOT_DIR" --artifact-dir "$ARTIFACT_DIR" |
  tee "$ARTIFACT_DIR/launch-ui-regression-audit.log"
python3 "$ROOT_DIR/scripts/ios/optical-grid-audit.py" --root "$ROOT_DIR" --artifact-dir "$ARTIFACT_DIR" |
  tee "$ARTIFACT_DIR/optical-grid-audit.log"
python3 "$ROOT_DIR/scripts/ios/test_launch_quality_evidence.py"
python3 "$ROOT_DIR/scripts/ios/test_split_size_ratchet.py"
python3 "$ROOT_DIR/scripts/ios/split_size_ratchet.py" --check --root "$ROOT_DIR"

# Smell audit and budget summary, with the xcodebuild phases off (same flags the macOS step used).
RUN_SWIFTLINT=false RUN_LAUNCH_PERFORMANCE=false RUN_PERFORMANCE_UNIT_TESTS=false RUN_TIMELINE_TRACE_WORKFLOW=false \
  DESTINATION="static-only (no simulator)" ARTIFACT_DIR="$ARTIFACT_DIR/performance" \
  bash "$ROOT_DIR/scripts/ios/performance-audit.sh"
