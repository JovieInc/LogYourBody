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
RUN_STATIC_UI_REGRESSION_AUDIT="${RUN_STATIC_UI_REGRESSION_AUDIT:-true}"
RUN_RUNTIME_WARNING_AUDIT="${RUN_RUNTIME_WARNING_AUDIT:-true}"
FAIL_ON_RUNTIME_WARNINGS="${FAIL_ON_RUNTIME_WARNINGS:-false}"
XCODEBUILD_SETTINGS="${XCODEBUILD_SETTINGS:-CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO}"
TEST_TIMEOUTS_ENABLED="${TEST_TIMEOUTS_ENABLED:-YES}"
DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE="${DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE:-90}"
MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE="${MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE:-180}"
XCODEBUILD_COMMAND_TIMEOUT_SECONDS="${XCODEBUILD_COMMAND_TIMEOUT_SECONDS:-420}"
BUILD_FOR_TESTING_TIMEOUT_SECONDS="${BUILD_FOR_TESTING_TIMEOUT_SECONDS:-600}"
TIMEOUT_BIN="${TIMEOUT_BIN:-}"

read -r -a XCODEBUILD_SETTINGS_ARRAY <<< "$XCODEBUILD_SETTINGS"

if [[ "$ARTIFACT_DIR" != /* ]]; then
  ARTIFACT_DIR="$ROOT_DIR/$ARTIFACT_DIR"
fi

mkdir -p "$ARTIFACT_DIR"

bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"

if [[ -z "$TIMEOUT_BIN" ]]; then
  TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
fi

if [[ "$DESTINATION" == "auto" ]]; then
  DESTINATION="$(IOS_DIR="$IOS_DIR" PROJECT="$PROJECT" SCHEME="$SCHEME" bash "$ROOT_DIR/scripts/ios/resolve-simulator-destination.sh")"
fi

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" --kill-after=30s "${timeout_seconds}s" "$@"
    return $?
  fi

  python3 - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
command = sys.argv[2:]

process = subprocess.Popen(command, start_new_session=True)
try:
    sys.exit(process.wait(timeout=timeout_seconds))
except subprocess.TimeoutExpired:
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=30)
    except ProcessLookupError:
        pass
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(124)
PY
}

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

cleanup_booted_simulator_apps() {
  xcrun simctl terminate booted com.logyourbody.app >/dev/null 2>&1 || true
  xcrun simctl terminate booted com.logyourbody.app.xctrunner >/dev/null 2>&1 || true
}

is_simulator_infra_failure() {
  local log_file="$1"

  grep -Eq \
    'Failed to get background assertion|Timed out while acquiring background assertion|Failed to install or launch the test runner|Failed to launch app|Mach error -308|server died|Early unexpected exit|operation never finished bootstrapping|Test crashed with signal kill before establishing connection|Restarting after unexpected exit|unexpected exit, crash, or test timeout|xcodebuild command timed out' \
    "$log_file"
}

run_xcodebuild_test() {
  local label="$1"
  local result_bundle="$2"
  local log_file="$3"
  local attempt
  local status
  local -a xcodebuild_command
  shift 3

  : > "$log_file"

  for attempt in 1 2; do
    cleanup_booted_simulator_apps
    rm -rf "$result_bundle"

    echo "Running $label (attempt $attempt)" | tee -a "$log_file"
    xcodebuild_command=(
      xcodebuild
      "${COMMON_XCODEBUILD_ARGS[@]}"
      -resultBundlePath "$result_bundle"
      "$@"
      "${XCODEBUILD_SETTINGS_ARRAY[@]}"
      test-without-building
    )

    set +e
    run_with_timeout \
      "$XCODEBUILD_COMMAND_TIMEOUT_SECONDS" \
      "${xcodebuild_command[@]}" 2>&1 | tee -a "$log_file"
    status="${PIPESTATUS[0]}"
    set -e

    if [[ "$status" -eq 124 ]]; then
      echo "xcodebuild command timed out after ${XCODEBUILD_COMMAND_TIMEOUT_SECONDS}s" | tee -a "$log_file"
    fi

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

assert_xcresult_has_test_cases() {
  local label="$1"
  local result_bundle="$2"
  local case_count

  if [[ ! -d "$result_bundle" ]]; then
    echo "Missing xcresult bundle for $label: $result_bundle" >&2
    exit 66
  fi

  case_count="$(
    xcrun xcresulttool get test-results tests \
      --path "$result_bundle" \
      --format json |
      python3 -c '
import json
import sys

payload = json.load(sys.stdin)

def count_cases(node):
    count = 1 if node.get("nodeType") == "Test Case" else 0
    for child in node.get("children", []):
        count += count_cases(child)
    return count

print(sum(count_cases(root) for root in payload.get("testNodes", [])))
'
  )"

  if [[ "$case_count" == "0" ]]; then
    echo "$label executed 0 XCTest cases; check -only-testing selectors and Xcode target membership." >&2
    exit 65
  fi

  echo "$label executed $case_count XCTest case(s)."
}

build_for_testing_once() {
  local log_file="$ARTIFACT_DIR/launch-quality-build-for-testing.log"
  local status
  local -a xcodebuild_command

  : > "$log_file"
  cleanup_booted_simulator_apps

  echo "Building launch-quality test bundle once" | tee -a "$log_file"
  xcodebuild_command=(
    xcodebuild
    "${COMMON_XCODEBUILD_ARGS[@]}"
    "${XCODEBUILD_SETTINGS_ARRAY[@]}"
    build-for-testing
  )

  set +e
  run_with_timeout \
    "$BUILD_FOR_TESTING_TIMEOUT_SECONDS" \
    "${xcodebuild_command[@]}" 2>&1 | tee -a "$log_file"
  status="${PIPESTATUS[0]}"
  set -e

  if [[ "$status" -eq 124 ]]; then
    echo "build-for-testing timed out after ${BUILD_FOR_TESTING_TIMEOUT_SECONDS}s" | tee -a "$log_file"
  fi

  return "$status"
}

run_ui_test_group() {
  local label="$1"
  local result_bundle="$ARTIFACT_DIR/$label.xcresult"
  local log_file="$ARTIFACT_DIR/$label.log"
  local test_name
  local -a only_testing_args=()
  shift

  for test_name in "$@"; do
    only_testing_args+=("-only-testing:LogYourBodyUITests/LogYourBodyUITests/$test_name")
  done

  UI_RESULT_BUNDLES+=("$result_bundle")
  run_xcodebuild_test \
    "$label" \
    "$result_bundle" \
    "$log_file" \
    "${only_testing_args[@]}"
  assert_xcresult_has_test_cases "$label" "$result_bundle"
}

cd "$IOS_DIR"

if [[ "$RUN_SWIFTLINT" == "true" ]]; then
  swiftlint lint --strict | tee "$ARTIFACT_DIR/swiftlint.log"
fi

if [[ "$RUN_STATIC_UI_REGRESSION_AUDIT" == "true" ]]; then
  python3 "$ROOT_DIR/scripts/ios/launch-ui-regression-audit.py" \
    --root "$ROOT_DIR" \
    --artifact-dir "$ARTIFACT_DIR" |
    tee "$ARTIFACT_DIR/launch-ui-regression-audit.log"
else
  echo "Skipping static launch UI regression audit" | tee "$ARTIFACT_DIR/launch-ui-regression-audit.log"
fi

build_for_testing_once

# The whole unit target is the gate: every journey test in docs/USER_JOURNEYS.md
# runs on every PR (all 67 files are registered in the target as of the orphan rescue).
run_xcodebuild_test \
  "launch-quality-unit-tests" \
  "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" \
  "$ARTIFACT_DIR/launch-quality-unit-tests.log" \
  -only-testing:LogYourBodyTests
assert_xcresult_has_test_cases \
  "launch-quality-unit-tests" \
  "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult"

UI_RESULT_BUNDLES=()
run_ui_test_group \
  "launch-quality-ui-critical-surfaces" \
  "testLaunchQualityGateCapturesCriticalSurfaces"

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
  printf -- '- Static UI regression audit: `launch-ui-regression-audit.md`\n'
  printf -- '- Unit coverage: photo timeline HUD policy, Body Score share card layout\n'
  printf -- '- UI coverage: timeline routing, no bottom stats switch card, home/analytics/onboarding/share screenshot attachments\n'
  printf -- '- Runtime warning audit: `runtime-warnings.log`, fail-on-warning=`%s`\n' "$FAIL_ON_RUNTIME_WARNINGS"
  printf -- '- Build strategy: one `build-for-testing`, unit selectors in one `test-without-building` run, and one composite launch-quality UI selector that captures all required screenshot surfaces with simulator parallelism disabled\n'
  printf -- '- Build timeout: `%ss`; test command timeout: `%ss` per xcodebuild invocation\n' "$BUILD_FOR_TESTING_TIMEOUT_SECONDS" "$XCODEBUILD_COMMAND_TIMEOUT_SECONDS"
  printf -- '- Logs and result bundles: `%s`\n' "$ARTIFACT_DIR"
} > "$ARTIFACT_DIR/summary.md"

echo "Launch quality audit logs written to $ARTIFACT_DIR"
