#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=LYB Golden iPhone 16}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$IOS_DIR/test_results/performance-audit/$STAMP}"
RUN_SWIFTLINT="${RUN_SWIFTLINT:-true}"
RUN_LAUNCH_PERFORMANCE="${RUN_LAUNCH_PERFORMANCE:-true}"
XCODEBUILD_SETTINGS="${XCODEBUILD_SETTINGS:-CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO}"

read -r -a XCODEBUILD_SETTINGS_ARRAY <<< "$XCODEBUILD_SETTINGS"

mkdir -p "$ARTIFACT_DIR"

if [[ "$DESTINATION" == "auto" ]]; then
  DESTINATION="$(IOS_DIR="$IOS_DIR" PROJECT="$PROJECT" SCHEME="$SCHEME" bash "$ROOT_DIR/scripts/ios/resolve-simulator-destination.sh")"
fi

cd "$IOS_DIR"

if [[ "$RUN_SWIFTLINT" == "true" ]]; then
  swiftlint lint --strict | tee "$ARTIFACT_DIR/swiftlint.log"
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -resultBundlePath "$ARTIFACT_DIR/performance-unit-tests.xcresult" \
  -only-testing:LogYourBodyTests/DashboardTimelineProviderPerformanceTests \
  -only-testing:LogYourBodyTests/ProgressPhotoImagePipelineTests \
  "${XCODEBUILD_SETTINGS_ARRAY[@]}" \
  test | tee "$ARTIFACT_DIR/performance-unit-tests.log"

if [[ "$RUN_LAUNCH_PERFORMANCE" == "true" ]]; then
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -resultBundlePath "$ARTIFACT_DIR/launch-performance.xcresult" \
    -only-testing:LogYourBodyUITests/LogYourBodyUITests/testLaunchPerformance \
    "${XCODEBUILD_SETTINGS_ARRAY[@]}" \
    test | tee "$ARTIFACT_DIR/launch-performance.log"
else
  echo "Skipping launch-performance XCTest because RUN_LAUNCH_PERFORMANCE=false" | tee "$ARTIFACT_DIR/launch-performance.log"
fi

cat > "$ARTIFACT_DIR/summary.md" <<SUMMARY
# iOS Performance Audit

- Destination: \`$DESTINATION\`
- Unit coverage: dashboard timeline indexes, progress-photo image pipeline
- Launch smoke: \`LogYourBodyUITests/testLaunchPerformance\` enabled=\`$RUN_LAUNCH_PERFORMANCE\`
- Logs: \`$ARTIFACT_DIR\`
SUMMARY

echo "Performance audit logs written to $ARTIFACT_DIR"
