#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-$IOS_DIR/test_results/quality-gate/$STAMP}"

mkdir -p "$ARTIFACT_ROOT"

bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"

if [[ "${DESTINATION:-}" == "auto" ]]; then
  DESTINATION="$(IOS_DIR="$IOS_DIR" bash "$ROOT_DIR/scripts/ios/resolve-simulator-destination.sh")"
  export DESTINATION
fi

echo "Using iOS quality gate destination: ${DESTINATION:-platform=iOS Simulator,name=LYB Golden iPhone 16}"

RUN_SWIFTLINT=true \
ARTIFACT_DIR="$ARTIFACT_ROOT/launch-quality" \
bash "$ROOT_DIR/scripts/ios/launch-quality-audit.sh"

RUN_SWIFTLINT=false \
ARTIFACT_DIR="$ARTIFACT_ROOT/performance" \
bash "$ROOT_DIR/scripts/ios/performance-audit.sh"

cat > "$ARTIFACT_ROOT/summary.md" <<SUMMARY
# iOS Quality Gate

- Destination: \`${DESTINATION:-platform=iOS Simulator,name=LYB Golden iPhone 16}\`
- Launch quality audit: \`$ARTIFACT_ROOT/launch-quality\`
- Performance audit: \`$ARTIFACT_ROOT/performance\`
- Launch performance XCTest: \`${RUN_LAUNCH_PERFORMANCE:-true}\`
SUMMARY

echo "iOS quality gate artifacts written to $ARTIFACT_ROOT"
