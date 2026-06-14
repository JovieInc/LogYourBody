#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=LYB Golden iPhone 16}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$IOS_DIR/test_results/performance-audit/$STAMP}"

mkdir -p "$ARTIFACT_DIR"

cd "$IOS_DIR"

swiftlint lint --strict | tee "$ARTIFACT_DIR/swiftlint.log"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:LogYourBodyTests/DashboardTimelineProviderPerformanceTests \
  -only-testing:LogYourBodyTests/ProgressPhotoImagePipelineTests \
  test | tee "$ARTIFACT_DIR/performance-unit-tests.log"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testLaunchPerformance \
  test | tee "$ARTIFACT_DIR/launch-performance.log"

cat > "$ARTIFACT_DIR/summary.md" <<SUMMARY
# iOS Performance Audit

- Destination: \`$DESTINATION\`
- Unit coverage: dashboard timeline indexes, progress-photo image pipeline
- Launch smoke: \`LogYourBodyUITests/testLaunchPerformance\`
- Logs: \`$ARTIFACT_DIR\`
SUMMARY

echo "Performance audit logs written to $ARTIFACT_DIR"
