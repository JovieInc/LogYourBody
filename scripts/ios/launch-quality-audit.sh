#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=LYB Golden iPhone 16}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$IOS_DIR/test_results/launch-quality-audit/$STAMP}"
RUN_SWIFTLINT="${RUN_SWIFTLINT:-true}"
RUN_RUNTIME_WARNING_AUDIT="${RUN_RUNTIME_WARNING_AUDIT:-true}"
FAIL_ON_RUNTIME_WARNINGS="${FAIL_ON_RUNTIME_WARNINGS:-false}"
XCODEBUILD_SETTINGS="${XCODEBUILD_SETTINGS:-CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO}"

read -r -a XCODEBUILD_SETTINGS_ARRAY <<< "$XCODEBUILD_SETTINGS"

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
)

cleanup_booted_simulator_apps() {
  xcrun simctl terminate booted com.logyourbody.app >/dev/null 2>&1 || true
  xcrun simctl terminate booted com.logyourbody.app.xctrunner >/dev/null 2>&1 || true
}

is_simulator_infra_failure() {
  local log_file="$1"

  grep -Eq \
    'Failed to get background assertion|Timed out while acquiring background assertion|Failed to install or launch the test runner|Failed to launch app|Mach error -308|server died|Early unexpected exit|operation never finished bootstrapping|Test crashed with signal kill before establishing connection|Restarting after unexpected exit|unexpected exit, crash, or test timeout' \
    "$log_file"
}

run_xcodebuild_test() {
  local label="$1"
  local result_bundle="$2"
  local log_file="$3"
  local attempt
  local status
  shift 3

  : > "$log_file"

  for attempt in 1 2; do
    cleanup_booted_simulator_apps
    rm -rf "$result_bundle"

    echo "Running $label (attempt $attempt)" | tee -a "$log_file"
    set +e
    xcodebuild \
      "${COMMON_XCODEBUILD_ARGS[@]}" \
      -resultBundlePath "$result_bundle" \
      "$@" \
      "${XCODEBUILD_SETTINGS_ARRAY[@]}" \
      test 2>&1 | tee -a "$log_file"
    status="${PIPESTATUS[0]}"
    set -e

    if [[ "$status" -eq 0 ]]; then
      return 0
    fi

    if [[ "$attempt" -eq 1 ]] && is_simulator_infra_failure "$log_file"; then
      echo "Retrying $label after simulator launch failure" | tee -a "$log_file"
      sleep 3
      continue
    fi

    return "$status"
  done
}

run_ui_test() {
  local test_name="$1"
  local result_bundle="$2"

  run_xcodebuild_test \
    "$test_name" \
    "$result_bundle" \
    "$ARTIFACT_DIR/launch-quality-ui-$test_name.log" \
    "-only-testing:LogYourBodyUITests/LogYourBodyUITests/$test_name"
}

cd "$IOS_DIR"

if [[ "$RUN_SWIFTLINT" == "true" ]]; then
  swiftlint lint --strict | tee "$ARTIFACT_DIR/swiftlint.log"
fi

run_xcodebuild_test \
  "launch-quality-unit-tests" \
  "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" \
  "$ARTIFACT_DIR/launch-quality-unit-tests.log" \
  -only-testing:LogYourBodyTests/PhotoTimelineHUDPolicyTests \
  -only-testing:LogYourBodyTests/BodyScoreShareCardTests

UI_TESTS=(
  "testLaunchQualityGateCapturesOnboardingFixedCTA"
  "testLaunchQualityGateCapturesTimelineHomeSurface"
  "testPhotoHUDFixtureRoutesToIntendedPostMVPDashboard"
  "testLaunchQualityGateCapturesOnboardingFirstPhotoCTA"
  "testLaunchQualityGateCapturesBodyScoreShareSheet"
)

UI_RESULT_BUNDLES=()
for test_name in "${UI_TESTS[@]}"; do
  result_bundle="$ARTIFACT_DIR/launch-quality-ui-$test_name.xcresult"
  UI_RESULT_BUNDLES+=("$result_bundle")
  run_ui_test "$test_name" "$result_bundle"
done

if [[ "$RUN_RUNTIME_WARNING_AUDIT" == "true" ]]; then
  FAIL_ON_RUNTIME_WARNINGS="$FAIL_ON_RUNTIME_WARNINGS" \
    bash "$ROOT_DIR/scripts/ios/xcresult-runtime-audit.sh" \
      "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" \
      "${UI_RESULT_BUNDLES[@]}" |
    tee "$ARTIFACT_DIR/runtime-warnings.log"
else
  echo "Skipping XCTest runtime-warning audit" | tee "$ARTIFACT_DIR/runtime-warnings.log"
fi

{
  printf '# iOS Launch Quality Audit\n\n'
  printf -- '- Destination: `%s`\n' "$DESTINATION"
  printf -- '- Unit coverage: photo timeline HUD policy, Body Score share card layout\n'
  printf -- '- UI coverage: timeline routing, no bottom stats switch card, home/analytics/onboarding/share screenshot attachments\n'
  printf -- '- Runtime warning audit: `runtime-warnings.log`, fail-on-warning=`%s`\n' "$FAIL_ON_RUNTIME_WARNINGS"
  printf -- '- Build strategy: unit and UI selectors run separately with simulator parallelism disabled\n'
  printf -- '- Logs and result bundles: `%s`\n' "$ARTIFACT_DIR"
} > "$ARTIFACT_DIR/summary.md"

echo "Launch quality audit logs written to $ARTIFACT_DIR"
