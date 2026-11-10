#!/usr/bin/env bash
set -euo pipefail

# An unknown mode must fail before bootstrap/build; no silent full-suite fallback.
AUDIT_MODE=full
if [[ $# -gt 0 ]]; then
  [[ $# -eq 1 && "$1" == --diagnostic-seven ]] || { echo "Unknown launch-quality mode" >&2; exit 64; }
  AUDIT_MODE=diagnostic-seven
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=LYB Golden iPhone 16}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$IOS_DIR/test_results/launch-quality-audit/$STAMP}"
RUN_SWIFTLINT="${RUN_SWIFTLINT:-true}"
RUN_STATIC_UI_REGRESSION_AUDIT="${RUN_STATIC_UI_REGRESSION_AUDIT:-true}"
RUN_OPTICAL_GRID_AUDIT="${RUN_OPTICAL_GRID_AUDIT:-true}"
RUN_RUNTIME_WARNING_AUDIT="${RUN_RUNTIME_WARNING_AUDIT:-true}"
FAIL_ON_RUNTIME_WARNINGS="${FAIL_ON_RUNTIME_WARNINGS:-false}"
XCODEBUILD_SETTINGS="${XCODEBUILD_SETTINGS:-CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO}"
TEST_TIMEOUTS_ENABLED="${TEST_TIMEOUTS_ENABLED:-YES}"
DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE="${DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE:-90}"
MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE="${MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE:-180}"
XCODEBUILD_COMMAND_TIMEOUT_SECONDS="${XCODEBUILD_COMMAND_TIMEOUT_SECONDS:-1020}"
# Bound the one cold build independently of XCTest execution. Run 40388372132
# missed every Swift package cache and was still compiling test targets at 600s.
# Allow 15m for compilation; keep test timeouts, retries and the outer step cap.
BUILD_FOR_TESTING_TIMEOUT_SECONDS="${BUILD_FOR_TESTING_TIMEOUT_SECONDS:-900}"
# Keep the 1800s UI hang cap after a cold hosted prefix. Run 42695073821's
# 1168s prefix left only 1590s for passing UI cases at 2760s. Run 42795533093
# reached UI at 1375s; deadline 2940 left 1565s and killed still-passing UI
# cases. The same SHA's retry finished those cases in 1697s. 3240s leaves the
# 1800s cap intact and reserves 180s finalization inside the 57-minute step.
# Per-test limits and the UI hang cap still apply.
AUDIT_DEADLINE_SECONDS="${AUDIT_DEADLINE_SECONDS:-3240}"
TIMEOUT_BIN="${TIMEOUT_BIN:-}"

if [[ "$AUDIT_MODE" == diagnostic-seven ]]; then
  PROJECT=LogYourBody.xcodeproj
  SCHEME=LogYourBody
  DESTINATION=diagnostic-pending
  XCODEBUILD_SETTINGS="CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO"
  TEST_TIMEOUTS_ENABLED=YES
  DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE=90
  MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE=180
  # Run 42724350244 was still Swift-compiling at 600s. Same 15m cold allowance as the full audit.
  BUILD_FOR_TESTING_TIMEOUT_SECONDS=900
fi

read -r -a XCODEBUILD_SETTINGS_ARRAY <<< "$XCODEBUILD_SETTINGS"

if [[ "$ARTIFACT_DIR" != /* ]]; then
  ARTIFACT_DIR="$ROOT_DIR/$ARTIFACT_DIR"
fi

if [[ -d "$ARTIFACT_DIR" && -n "$(ls -A "$ARTIFACT_DIR")" ]]; then
  echo "Refusing to reuse nonempty launch-quality artifact directory: $ARTIFACT_DIR" >&2
  exit 65
fi
mkdir -p "$ARTIFACT_DIR"
AUDIT_STARTED_AT="$(date +%s)"

# Phase and budget helpers must exist before the first phase_start call below.
remaining_budget_seconds() {
  local remaining=$(( AUDIT_DEADLINE_SECONDS - $(date +%s) + AUDIT_STARTED_AT ))
  if (( remaining <= 0 )); then
    echo "launch-quality audit deadline exhausted" >&2
    return 124
  fi
  printf '%s\n' "$remaining"
}

# Cap each phase at min(its own bound, what is left of the audit deadline) so a
# slow host fails the audit through its own timeout and evidence instead of a
# silent runner-side step kill.
bounded_seconds() {
  local bound="$1" remaining
  remaining="$(remaining_budget_seconds)" || return "$?"
  (( bound < remaining )) && printf '%s\n' "$bound" || printf '%s\n' "$remaining"
}

PHASE_NAME=""
PHASE_STARTED_AT=0
emit_phase() {
  local line="launch-quality audit: $1 (elapsed $(( $(date +%s) - AUDIT_STARTED_AT ))s)"
  echo "$line"
  printf '%s\n' "$line" >> "$ARTIFACT_DIR/phase-timeline.log"
  # The step summary renders even when the runner later kills the step, which
  # is the only public evidence channel on self-hosted Mac runs.
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$line" >> "$GITHUB_STEP_SUMMARY"
  fi
}

phase_start() {
  PHASE_NAME="$1"
  PHASE_STARTED_AT="$(date +%s)"
  emit_phase "started $PHASE_NAME"
}

phase_end() {
  emit_phase "finished $PHASE_NAME in $(( $(date +%s) - PHASE_STARTED_AT ))s"
  PHASE_NAME=""
}

# Record source identity without implying an authenticated production build.
git -C "$ROOT_DIR" rev-parse HEAD > "$ARTIFACT_DIR/source-revision.txt"
git -C "$ROOT_DIR" diff HEAD --binary > "$ARTIFACT_DIR/source-working-tree.patch"

if [[ "$AUDIT_MODE" == full ]]; then
  # Finish validator shell fixtures before simulator boot competes for host resources.
  phase_start preflight
  python3 "$ROOT_DIR/scripts/ios/test_launch_quality_evidence.py"
  python3 "$ROOT_DIR/scripts/ios/test_xcodebuild_command_timeout.py"
  bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"
fi

if [[ -z "$TIMEOUT_BIN" ]]; then
  TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
fi

if [[ "$DESTINATION" == "auto" ]]; then
  DESTINATION="$(IOS_DIR="$IOS_DIR" PROJECT="$PROJECT" SCHEME="$SCHEME" bash "$ROOT_DIR/scripts/ios/resolve-simulator-destination.sh")"
fi

if [[ "$AUDIT_MODE" == full ]]; then
  phase_end preflight
fi

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  if [[ -n "${XCODEBUILD_RESULT_FINALIZATION_GRACE_SECONDS:-}" ]]; then
    python3 -B "$ROOT_DIR/scripts/ios/xcodebuild-command-timeout.py" \
      --timeout-seconds "$timeout_seconds" --grace-seconds "$XCODEBUILD_RESULT_FINALIZATION_GRACE_SECONDS" -- "$@"
    return $?
  fi
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
  -enableCodeCoverage YES
  -maximum-concurrent-test-simulator-destinations 1
  -test-timeouts-enabled "$TEST_TIMEOUTS_ENABLED"
  -default-test-execution-time-allowance "$DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE"
  -maximum-test-execution-time-allowance "$MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE"
)

cleanup_booted_simulator_apps() {
  # Cold CoreSimulator can block terminate for minutes before the app exists.
  run_with_timeout "${SIMCTL_TERMINATE_TIMEOUT_SECONDS:-20}" xcrun simctl terminate booted com.logyourbody.app >/dev/null 2>&1 || true
  run_with_timeout "${SIMCTL_TERMINATE_TIMEOUT_SECONDS:-20}" xcrun simctl terminate booted com.logyourbody.app.xctrunner >/dev/null 2>&1 || true
}

is_simulator_infra_failure() {
  local log_file="$1"

  # Retry only pre-XCTest launch failures. A timeout restart line is not one (PR #1555).
  if grep -Eq 'Test (Case|Suite) .* started|exceeded execution time allowance' "$log_file"; then
    return 1
  fi
  grep -Eq \
    'Failed to get background assertion|Timed out while acquiring background assertion|Failed to install or launch the test runner|Failed to launch app|Mach error -308|server died|Early unexpected exit|operation never finished bootstrapping|Test crashed with signal kill before establishing connection' \
    "$log_file"
}

# Record host and simulator activity while the test runner launches.
LQ_LAUNCH_PROBE="${LQ_LAUNCH_PROBE:-true}"
LAUNCH_PROBE_PIDS=()

simulator_udid() {
  if [[ "$DESTINATION" =~ id=([0-9A-Fa-f-]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    xcrun simctl list devices booted 2>/dev/null | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | head -1
  fi
}

start_launch_probe() {
  local label="$1"
  [[ "$LQ_LAUNCH_PROBE" == "true" ]] || return 0
  local dir="$ARTIFACT_DIR/$label.launch-probe"
  local udid
  mkdir -p "$dir"
  udid="$(simulator_udid || true)"
  {
    echo "probe-start $(date -u +%FT%T)Z udid=${udid:-unknown}"
    xcrun simctl list devices 2>/dev/null | grep -F "${udid:-none}" || true
  } > "$dir/timeline.txt" 2>&1
  # Host load every 10s: which processes own the CPU while the runner launches.
  (
    while true; do
      echo "== $(date -u +%T)Z load=$(sysctl -n vm.loadavg 2>/dev/null)"
      ps -Ao pcpu=,rss=,comm= -r 2>/dev/null | head -8 || true
      sleep 10
    done
  ) > "$dir/host-top.txt" 2>&1 &
  LAUNCH_PROBE_PIDS+=("$!")
  # Simulator-side runner, test host, testmanagerd and launch services events.
  if [[ -n "$udid" ]]; then
    xcrun simctl spawn "$udid" log stream --style compact --level info --predicate \
      'process CONTAINS "LogYourBody" OR process == "testmanagerd" OR process == "SpringBoard" OR process == "installd" OR subsystem == "com.apple.dt.xctest"' \
      > "$dir/simulator.log" 2>&1 &
    LAUNCH_PROBE_PIDS+=("$!")
  fi
}

stop_launch_probe() {
  local label="$1"
  [[ "$LQ_LAUNCH_PROBE" == "true" ]] || return 0
  local pid
  for pid in ${LAUNCH_PROBE_PIDS[@]+"${LAUNCH_PROBE_PIDS[@]}"}; do
    # The recorded pid may have exec'd into a tool (xcrun -> simctl) whose
    # child (e.g. `simctl spawn ... log stream`) survives its parent and
    # streams forever on a persistent Mac. Kill the children first, or every
    # attempt leaks one unbounded simulator log stream.
    pkill -P "$pid" >/dev/null 2>&1 || true
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  done
  LAUNCH_PROBE_PIDS=()
  local dir="$ARTIFACT_DIR/$label.launch-probe"
  {
    echo "probe-stop $(date -u +%FT%T)Z"
    # First test-runner signals in the xcodebuild log, for the launch gap.
    grep -nE 'Writing result bundle|Running tests\.\.\.|Test Suite .* started|IDETestOperationsObserverDebug' \
      "$ARTIFACT_DIR/$label.log" 2>/dev/null | head -12 || true
  } >> "$dir/timeline.txt" 2>&1 || true
}

run_xcodebuild_test() {
  local label="$1"
  local result_bundle="$2"
  local log_file="$3"
  local attempt
  local status
  local effective_timeout
  local -a xcodebuild_command
  shift 3

  : > "$log_file"

  for attempt in 1 2; do
    cleanup_booted_simulator_apps
    if [[ -e "$result_bundle" ]]; then
      mv "$result_bundle" "${result_bundle%.xcresult}.attempt-$((attempt - 1)).xcresult"
    fi

    echo "Running $label (attempt $attempt)" | tee -a "$log_file"
    effective_timeout="$(bounded_seconds "$XCODEBUILD_COMMAND_TIMEOUT_SECONDS")" || return "$?"
    start_launch_probe "$label"
    xcodebuild_command=(
      xcodebuild
      "${COMMON_XCODEBUILD_ARGS[@]}"
      -resultBundlePath "$result_bundle"
      "$@"
      "${XCODEBUILD_SETTINGS_ARRAY[@]}"
      test-without-building
    )

    set +e
    XCODEBUILD_RESULT_FINALIZATION_GRACE_SECONDS="${XCODEBUILD_RESULT_FINALIZATION_GRACE_SECONDS:-180}" \
    run_with_timeout \
      "$effective_timeout" \
      "${xcodebuild_command[@]}" 2>&1 | tee -a "$log_file"
    status="${PIPESTATUS[0]}"
    set -e
    stop_launch_probe "$label"

    if [[ "$status" -eq 124 ]]; then
      echo "xcodebuild command timed out after ${effective_timeout}s" | tee -a "$log_file"
      return "$status"
    fi

    if [[ "$status" -eq 0 ]]; then
      return 0
    fi

    # A diagnostic has one UI command, even when infrastructure fails before tests.
    # Retain that failure; never hide unknown prior execution behind a retry.
    if [[ "${AUDIT_MODE:-full}" == diagnostic-seven ]]; then
      return "$status"
    fi

    if [[ "$attempt" -eq 1 ]] && is_simulator_infra_failure "$log_file"; then
      echo "Retrying $label after simulator launch failure" | tee -a "$log_file"
      sleep 3
      continue
    fi

    return "$status"
  done
}

assert_xcresult_evidence() {
  local result_bundle="$1"
  shift
  python3 "$ROOT_DIR/scripts/ios/launch-quality-evidence.py" \
    --bundle "$result_bundle" --started-at "$AUDIT_STARTED_AT" "$@"
}

build_for_testing_once() {
  local log_file="$ARTIFACT_DIR/launch-quality-build-for-testing.log"
  local status
  local effective_timeout
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

  effective_timeout="$(bounded_seconds "$BUILD_FOR_TESTING_TIMEOUT_SECONDS")" || return "$?"
  set +e
  run_with_timeout \
    "$effective_timeout" \
    "${xcodebuild_command[@]}" 2>&1 | tee -a "$log_file"
  status="${PIPESTATUS[0]}"
  set -e

  if [[ "$status" -eq 124 ]]; then
    echo "build-for-testing timed out after ${effective_timeout}s" | tee -a "$log_file"
  fi

  return "$status"
}

if [[ "$AUDIT_MODE" == diagnostic-seven ]]; then
  source "$ROOT_DIR/scripts/ios/launch-quality-diagnostic-seven.sh"
fi


cd "$IOS_DIR"

if [[ "$AUDIT_MODE" == diagnostic-seven ]]; then
  run_diagnostic_seven
  exit 0
fi

phase_start static
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

if [[ "$RUN_OPTICAL_GRID_AUDIT" == "true" ]]; then
  # optical-grid-consistent-v1: shrink-only drift ratchet against
  # scripts/ios/optical-grid-baseline.json (spacing, radius, palette, type).
  python3 "$ROOT_DIR/scripts/ios/optical-grid-audit.py" \
    --root "$ROOT_DIR" \
    --artifact-dir "$ARTIFACT_DIR" |
    tee "$ARTIFACT_DIR/optical-grid-audit.log"
else
  echo "Skipping optical grid audit" | tee "$ARTIFACT_DIR/optical-grid-audit.log"
fi

phase_end static

phase_start build-for-testing
build_for_testing_once
phase_end build-for-testing

CHAT_QUALIFICATION_UNIT_TESTS=(
  "ChatServiceTests/testSyntheticChatCompletionRestoresThroughExistingHistoryPort"
  "ChatServiceTests/testSyntheticChatRetryRetainsOriginalIdentity"
  "ChatServiceTests/testSyntheticChatMissingDoneAndCancelledTurnNeverPersistComplete"
  "ChatServiceTests/testTurnRejectsDelayedReplacementTokenBeforeOpeningStream"
  "ChatServiceTests/testTurnDropsHeldMetadataDeltasCompletionAndFailureAfterReplacement"
  "ChatServiceTests/testTurnSuppressesDelayedProviderErrorButPreservesCurrentErrors"
  "ChatServiceTests/testHistoryLoadRejectsDelayedSuccessEmptyAndErrorAfterOwnershipOrLoadChanges"
  "ChatServiceTests/testHistoryLoadRejectsTokenFromReplacementSessionBeforeSending"
  "ChatServiceTests/testCurrentTurnAcceptsRotatedTokenEventsAndRequiresCompletion"
)
CHAT_UNIT_EVIDENCE_ARGS=()
for test_id in "${CHAT_QUALIFICATION_UNIT_TESTS[@]}"; do
  CHAT_UNIT_EVIDENCE_ARGS+=(--expected-test "${test_id}()")
done

# StoreKitPurchaseRestoreTests is skipped here: it shares one StoreKit test environment, is gated by the
# dedicated StoreKit job (ci.yml ios_storekit, test plan StoreKit, merge queue and main) and failed 2 of 13
# Launch Quality runs on 2026-10-25 with the LYB-231 signature (empty StoreKit state at restore).
# Launch Quality gates the general unit target. The StoreKit lifecycle suite
# remains required in the dedicated merge-group and main job.
phase_start unit-tests
run_xcodebuild_test \
  "launch-quality-unit-tests" \
  "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" \
  "$ARTIFACT_DIR/launch-quality-unit-tests.log" \
  -only-testing:LogYourBodyTests \
  -skip-testing:LogYourBodyTests/StoreKitPurchaseRestoreTests
assert_xcresult_evidence \
  "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" --require-biometric-coverage "${CHAT_UNIT_EVIDENCE_ARGS[@]}"

python3 "$ROOT_DIR/scripts/ios/native-coverage-ratchet.py" \
  --coverage "$ARTIFACT_DIR/launch-quality-unit-tests.coverage.json" \
  --evidence "$ARTIFACT_DIR/launch-quality-unit-tests.evidence.json" \
  --baseline "$ROOT_DIR/scripts/ios/native-coverage-baseline.json" \
  --profile quality-unit --source-sha "$(git -C "$ROOT_DIR" rev-parse HEAD)" \
  --base-revision "${BASE_SHA:-}" --source-root "$ROOT_DIR" \
  --scheme "$SCHEME" --only-testing LogYourBodyTests \
  > "$ARTIFACT_DIR/launch-quality-unit-tests.ratchet.json"
phase_end unit-tests

# One UI xcodebuild launch; separate launches overran the step, and each XCTest case keeps its own budget.
LAUNCH_QUALITY_UI_TESTS=(
  "HomeV2TimelineIntegrationUITests/testPhotoHoldScrubsBothDirectionsThenAnotherHoldRestoresTap"
  "HomeV2TimelineIntegrationUITests/testPhotoScrubResetsWhenNavigatingToTheMenuAndBack"
  "HomeV2TimelineIntegrationUITests/testHorizontalPhotoDragPagesPixelsAndMetricsWithoutOpeningViewer"
  "HomeV2PhotoViewerLayoutUITests/testPhotoViewerHoldScrubsAndResetsAfterToolsNavigation"
  "LogYourBodyUITests/testProgressShareKeepsSelectedMetricAndVisibleValue"
  "LogYourBodyUITests/testStatsTruthDrilldownKeepsHeadlineAndFocusWithObservationProvenance"
  "LogYourBodyUITests/testHomeV2AskSyntheticFullTurnRestoresAfterRelaunch"
  "LogYourBodyUITests/testHomeV2AskSyntheticFailedTurnRetriesOriginalIdentity"
  "LogYourBodyUITests/testHomeV2AskSyntheticCancelledTurnRecovers"
  "LogYourBodyUITests/testLaunchQualityGateCapturesCriticalSurfaces"
  "LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFixedCTA"
  "LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFirstPhotoCTA"
  "LogYourBodyUITests/testLaunchQualityGateCapturesTimelineSurfaces"
  "LogYourBodyUITests/testDatedTimelineManualBaselineAndInterruptedPhotoReturn"
  "LogYourBodyUITests/testDatedTimelineSwipeProvenanceOfflineRetryAndAccountIsolation"
  "LogYourBodyUITests/testDatedTimelineExpiredOutcomeOpensEditorWithoutExtendingDate"
  "LogYourBodyUITests/testDatedStatsManualMeasurementDateEditExpiryAndAccountReturn"
  "LogYourBodyUITests/testDatedStatsReadyHasOneReachableRecovery"
  "LogYourBodyUITests/testDatedStatsDenialHasOneReachableRecovery"
  "LogYourBodyUITests/testDatedStatsNoDataHasOneReachableRecovery"
  "LogYourBodyUITests/testDatedStatsOfflineHasOneReachableRecovery"
  "LogYourBodyUITests/testDatedStatsStaleHasOneReachableRecovery"
  "LogYourBodyUITests/testDatedStatsConflictingHasOneReachableRecovery"
  "LogYourBodyUITests/testDatedStatsUnsafeDateHasOneReachableRecovery"
  "LogYourBodyUITests/testDatedStatsImpossibleDateHasOneReachableRecovery"
  "LogYourBodyUITests/testDatedStatsExpiredDateHasOneReachableRecovery"
  "LogYourBodyUITests/testDatedStatsMaintenanceHasOneReachableRecovery"
  "LogYourBodyUITests/testProfileLogoutSignsOutFromPushedDetail"
  "OnboardingGoldenPathUITests/testBodyScoreOnboardingGoldenPathReachesReveal"
  "MesocycleCanvasUITests/testReducedMotionUsesStackedDayCards"
  "MesocycleCanvasUITests/testGoalThroughUndoKeepsTheCanvasAndReadbackTogether"
)

CHAOS_REGRESSIONS=(
  "ChaosEdgeCaseUITests/testChaosLaunchForwardsActualXCTestConfiguration"
  "ChaosEdgeCaseUITests/testIntegrationDirectorySeparatesHealthAccessAndScanHistory"
  "ChaosEdgeCaseUITests/testAddEntryAccepts300CharacterNote"
  "ChaosEdgeCaseUITests/testAccessibilityXXXLHomeSettingsProfileHasNoLayoutAnomalies"
  "ChaosMonkeyUITests/testNativeScrollClippingRequiresActualScrollAncestor"
  "ChaosMonkeyUITests/testWeightEntryPhotoImportControlsAreExcludedFromMonkeyCandidates"
  "ChaosMonkeyUITests/testSystemAlertsRequireKnownDenyOnlyAction"
  "ChaosMonkeyUITests/testKeyboardDismissalPreservesDraftWithoutSending"
  "ChaosMonkeyUITests/testProfilePhotoImportIsExcludedFromMonkeyCandidates"
  "ChaosMonkeyUITests/testMissingActionTargetsDoNotCompleteMonkeySteps"
  "ChaosMonkeyUITests/testExecutedNativeActionsCompleteOnlyTheirOwnBudget"
  "ChaosMonkeyUITests/testFailedActionsExhaustAttemptsWithoutCompletion"
)
UI_SELECTORS=()
UI_EVIDENCE_ARGS=()
for test_id in "${LAUNCH_QUALITY_UI_TESTS[@]}" "${CHAOS_REGRESSIONS[@]}"; do
  UI_SELECTORS+=("-only-testing:LogYourBodyUITests/$test_id")
  UI_EVIDENCE_ARGS+=(--expected-test "$test_id()")
done
UI_RESULT_BUNDLE="$ARTIFACT_DIR/launch-quality-ui.xcresult"
UI_RESULT_BUNDLES=("$UI_RESULT_BUNDLE")
# One UI launch carries the dated-state matrix. Per-test allowances and the
# 57-minute step cap stay; finalization grace is not part of this hang cap.
UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS="${UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS:-1800}" # dated-state matrix; per-test and 57m caps stay
phase_start ui-tests
XCODEBUILD_COMMAND_TIMEOUT_SECONDS="$UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS" run_xcodebuild_test \
  "launch-quality-ui" \
  "$UI_RESULT_BUNDLE" \
  "$ARTIFACT_DIR/launch-quality-ui.log" \
  "${UI_SELECTORS[@]}"
assert_xcresult_evidence "$UI_RESULT_BUNDLE" "${UI_EVIDENCE_ARGS[@]}" \
  --critical-captures --require-settings-row-coverage --require-chaos-accounting-coverage --require-canvas-coverage
phase_end ui-tests

phase_start runtime-warnings
if [[ "$RUN_RUNTIME_WARNING_AUDIT" == "true" ]]; then
  FAIL_ON_RUNTIME_WARNINGS="$FAIL_ON_RUNTIME_WARNINGS" \
    bash "$ROOT_DIR/scripts/ios/xcresult-runtime-audit.sh" \
      "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" \
      "${UI_RESULT_BUNDLES[@]}" |
    tee "$ARTIFACT_DIR/runtime-warnings.log"
else
  echo "Skipping XCTest runtime-warning audit" | tee "$ARTIFACT_DIR/runtime-warnings.log"
fi
phase_end runtime-warnings

{
  printf '# iOS Launch Quality Audit\n\n'
  printf -- '- Destination: `%s`\n' "$DESTINATION"
  printf -- '- Static UI regression audit: `launch-ui-regression-audit.md`\n'
  printf -- '- Optical grid drift ratchet: `optical-grid-audit.md`\n'
  printf -- '- Unit coverage: photo timeline HUD launch policy, Body Score share card layout\n'
  printf -- '- Fixture UI coverage: home hero + chat composer, Jovie swipe/menu Timeline/Stats, one timeline scrubber, home/analytics/onboarding/share screenshot attachments\n'
  printf -- '- Evidence scope: `fixture_ui`; injected auth and entitlement state. Real Sign in with Apple, purchase, and restore remain `not_verified`.\n'
  printf -- '- Required passing test IDs and ten screenshot hashes: `launch-quality-ui.evidence.json`. First failed attempt bundles are retained.\n'
  printf -- '- Source: `source-revision.txt` plus `source-working-tree.patch`; this is not exact deployed-build certification.\n'
  printf -- '- Runtime warning audit: `runtime-warnings.log`, fail-on-warning=`%s`\n' "$FAIL_ON_RUNTIME_WARNINGS"
  printf -- '- Build strategy: one `build-for-testing`, the general unit target (StoreKit lifecycle tests run in the required dedicated job), then one UI invocation covering inherited surface cases, two canvas cases, and twelve bounded chaos regressions with simulator parallelism disabled\n'
  printf -- '- Required native coverage: biometric policy, SettingsRow, chaos action accounting, and executed MesocycleCanvas app/view lines. Canvas captures cover reduced motion, replay/readback, and undo.\n'
  printf -- '- Build timeout: `%ss`; test hang cap: `%ss`; finalization grace: `%ss`; audit deadline: `%ss`\n' "$BUILD_FOR_TESTING_TIMEOUT_SECONDS" "$XCODEBUILD_COMMAND_TIMEOUT_SECONDS" "${XCODEBUILD_RESULT_FINALIZATION_GRACE_SECONDS:-180}" "$AUDIT_DEADLINE_SECONDS"
  printf -- '- Phase timing: `phase-timeline.log` (also emitted to the step summary as each phase starts and ends)\n'
  printf -- '- Logs and result bundles: `%s`\n' "$ARTIFACT_DIR"
} > "$ARTIFACT_DIR/summary.md"

echo "Launch quality audit logs written to $ARTIFACT_DIR"
