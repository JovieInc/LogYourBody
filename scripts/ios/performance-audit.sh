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
RUN_SWIFTUI_PERFORMANCE_SMELL_AUDIT="${RUN_SWIFTUI_PERFORMANCE_SMELL_AUDIT:-true}"
RUN_LAUNCH_PERFORMANCE="${RUN_LAUNCH_PERFORMANCE:-true}"
RUN_TIMELINE_TRACE_WORKFLOW="${RUN_TIMELINE_TRACE_WORKFLOW:-false}"
XCODEBUILD_SETTINGS="${XCODEBUILD_SETTINGS:-CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO}"
TEST_TIMEOUTS_ENABLED="${TEST_TIMEOUTS_ENABLED:-YES}"
DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE="${DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE:-90}"
MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE="${MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE:-180}"

if [[ -z "${RUN_PERFORMANCE_UNIT_TESTS+x}" ]]; then
  if [[ "${GITHUB_ACTIONS:-false}" == "true" && "$RUN_LAUNCH_PERFORMANCE" == "false" ]]; then
    RUN_PERFORMANCE_UNIT_TESTS="false"
  else
    RUN_PERFORMANCE_UNIT_TESTS="true"
  fi
fi

read -r -a XCODEBUILD_SETTINGS_ARRAY <<< "$XCODEBUILD_SETTINGS"

if [[ "$ARTIFACT_DIR" != /* ]]; then
  ARTIFACT_DIR="$ROOT_DIR/$ARTIFACT_DIR"
fi

mkdir -p "$ARTIFACT_DIR"

if [[ "$DESTINATION" == "auto" ]]; then
  DESTINATION="$(IOS_DIR="$IOS_DIR" PROJECT="$PROJECT" SCHEME="$SCHEME" bash "$ROOT_DIR/scripts/ios/resolve-simulator-destination.sh")"
fi

COMMON_XCODEBUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -parallel-testing-enabled NO
  -maximum-concurrent-test-simulator-destinations 1
  -test-timeouts-enabled "$TEST_TIMEOUTS_ENABLED"
  -default-test-execution-time-allowance "$DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE"
  -maximum-test-execution-time-allowance "$MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE"
)

PERFORMANCE_UNIT_TEST_SELECTORS=(
  "LogYourBodyTests/TimelineDataProviderScrubTests/testRenderSignatureConstructionPerformance"
  "LogYourBodyTests/DashboardTimelineProviderPerformanceTests"
  "LogYourBodyTests/ProgressPhotoImagePipelineTests"
  "LogYourBodyTests/ImageCacheServiceTests"
)

PERFORMANCE_UNIT_TEST_ARGS=()
for selector in "${PERFORMANCE_UNIT_TEST_SELECTORS[@]}"; do
  PERFORMANCE_UNIT_TEST_ARGS+=("-only-testing:$selector")
done

cd "$IOS_DIR"

if [[ "$RUN_SWIFTLINT" == "true" ]]; then
  swiftlint lint --strict | tee "$ARTIFACT_DIR/swiftlint.log"
fi

if [[ "$RUN_SWIFTUI_PERFORMANCE_SMELL_AUDIT" == "true" ]]; then
  python3 "$ROOT_DIR/scripts/ios/swiftui-performance-smell-audit.py" \
    --root "$ROOT_DIR" \
    --artifact-dir "$ARTIFACT_DIR" |
    tee "$ARTIFACT_DIR/swiftui-performance-smell-audit.log"
else
  echo "Skipping static SwiftUI performance smell audit" | tee "$ARTIFACT_DIR/swiftui-performance-smell-audit.log"
fi

if [[ "$RUN_PERFORMANCE_UNIT_TESTS" == "true" ]]; then
  xcodebuild \
    "${COMMON_XCODEBUILD_ARGS[@]}" \
    -resultBundlePath "$ARTIFACT_DIR/performance-unit-tests.xcresult" \
    -skip-testing:LogYourBodyUITests \
    "${PERFORMANCE_UNIT_TEST_ARGS[@]}" \
    "${XCODEBUILD_SETTINGS_ARRAY[@]}" \
    test | tee "$ARTIFACT_DIR/performance-unit-tests.log"
else
  echo "Skipping performance-unit XCTest because RUN_PERFORMANCE_UNIT_TESTS=false" | tee "$ARTIFACT_DIR/performance-unit-tests.log"
fi

if [[ "$RUN_LAUNCH_PERFORMANCE" == "true" ]]; then
  xcodebuild \
    "${COMMON_XCODEBUILD_ARGS[@]}" \
    -resultBundlePath "$ARTIFACT_DIR/launch-performance.xcresult" \
    -only-testing:LogYourBodyUITests/LogYourBodyUITests/testLaunchPerformance \
    "${XCODEBUILD_SETTINGS_ARRAY[@]}" \
    test | tee "$ARTIFACT_DIR/launch-performance.log"
else
  echo "Skipping launch-performance XCTest because RUN_LAUNCH_PERFORMANCE=false" | tee "$ARTIFACT_DIR/launch-performance.log"
fi

if [[ "$RUN_TIMELINE_TRACE_WORKFLOW" == "true" ]]; then
  xcodebuild \
    "${COMMON_XCODEBUILD_ARGS[@]}" \
    -resultBundlePath "$ARTIFACT_DIR/timeline-trace-workflow.xcresult" \
    -only-testing:LogYourBodyUITests/LogYourBodyUITests/testTimelinePerformanceTraceWorkflow \
    "${XCODEBUILD_SETTINGS_ARRAY[@]}" \
    test | tee "$ARTIFACT_DIR/timeline-trace-workflow.log"
else
  echo "Skipping timeline trace workflow XCTest because RUN_TIMELINE_TRACE_WORKFLOW=false" | tee "$ARTIFACT_DIR/timeline-trace-workflow.log"
fi

SUMMARY_ARGS=(
  --artifact-dir "$ARTIFACT_DIR"
  --destination "$DESTINATION"
  --unit-xcresult "$ARTIFACT_DIR/performance-unit-tests.xcresult"
  --unit-log "$ARTIFACT_DIR/performance-unit-tests.log"
)

if [[ "$RUN_LAUNCH_PERFORMANCE" == "true" ]]; then
  SUMMARY_ARGS+=(
    --launch-xcresult "$ARTIFACT_DIR/launch-performance.xcresult"
    --launch-log "$ARTIFACT_DIR/launch-performance.log"
  )
else
  SUMMARY_ARGS+=(--launch-skipped)
fi

if [[ "$RUN_TIMELINE_TRACE_WORKFLOW" == "true" ]]; then
  SUMMARY_ARGS+=(
    --timeline-workflow-xcresult "$ARTIFACT_DIR/timeline-trace-workflow.xcresult"
    --timeline-workflow-log "$ARTIFACT_DIR/timeline-trace-workflow.log"
  )
else
  SUMMARY_ARGS+=(--timeline-workflow-skipped)
fi

if [[ "$RUN_PERFORMANCE_UNIT_TESTS" != "true" ]]; then
  SUMMARY_ARGS+=(--unit-skipped)
fi

python3 "$ROOT_DIR/scripts/ios/performance-budget-summary.py" "${SUMMARY_ARGS[@]}"

echo "Performance audit logs written to $ARTIFACT_DIR"
