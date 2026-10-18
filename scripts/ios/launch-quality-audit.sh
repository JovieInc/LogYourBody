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
# Passing hosted invocations took up to 672s (2026-10-12), and a cold first UI
# invocation spent ~10m in xcodebuild startup before any test ran, so 720s
# killed healthy runs. 1020s still stops a hung simulator well inside the step
# budget. A command timeout is not retried; see is_simulator_infra_failure.
XCODEBUILD_COMMAND_TIMEOUT_SECONDS="${XCODEBUILD_COMMAND_TIMEOUT_SECONDS:-1020}"
BUILD_FOR_TESTING_TIMEOUT_SECONDS="${BUILD_FOR_TESTING_TIMEOUT_SECONDS:-600}"
TIMEOUT_BIN="${TIMEOUT_BIN:-}"

if [[ "$AUDIT_MODE" == diagnostic-seven ]]; then
  PROJECT=LogYourBody.xcodeproj
  SCHEME=LogYourBody
  DESTINATION=diagnostic-pending
  XCODEBUILD_SETTINGS="CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO"
  TEST_TIMEOUTS_ENABLED=YES
  DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE=90
  MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE=180
  BUILD_FOR_TESTING_TIMEOUT_SECONDS=600
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
# Record source identity without implying an authenticated production build.
git -C "$ROOT_DIR" rev-parse HEAD > "$ARTIFACT_DIR/source-revision.txt"
git -C "$ROOT_DIR" diff HEAD --binary > "$ARTIFACT_DIR/source-working-tree.patch"

if [[ "$AUDIT_MODE" == full ]]; then
  bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"
fi

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
  -enableCodeCoverage YES
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

  # Retry is only for infrastructure failure before any test executes.
  # Incidental simulator messages cannot erase actual XCTest execution/failure.
  if grep -Eq "Test (Case|Suite) .* started|Executed [0-9]+ tests|XCTAssert.*failed|: error: .*XCTAssert" "$log_file"; then
    return 1
  fi

  # Command-timeout is intentionally absent. Merge-group run 36947770736
  # reached it on the last chaos test while that test was still scanning, then
  # this matcher retried the whole group and the 26-minute step died mid-retry.
  grep -Eq \
    'Failed to get background assertion|Timed out while acquiring background assertion|Failed to install or launch the test runner|Failed to launch app|Mach error -308|server died|Early unexpected exit|operation never finished bootstrapping|Test crashed with signal kill before establishing connection|Restarting after unexpected exit|unexpected exit, crash, or test timeout' \
    "$log_file"
}

# Diagnostic only (never fails the audit): every hosted test invocation spends
# 6-10 min launching the test runner before its first test. Record what the
# simulator and host are doing in that window so the dominant phase can be
# fixed instead of bounded. Writes <label>.launch-probe/ next to the bundle.
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
  local -a xcodebuild_command
  shift 3

  : > "$log_file"

  for attempt in 1 2; do
    cleanup_booted_simulator_apps
    if [[ -e "$result_bundle" ]]; then
      mv "$result_bundle" "${result_bundle%.xcresult}.attempt-$((attempt - 1)).xcresult"
    fi

    echo "Running $label (attempt $attempt)" | tee -a "$log_file"
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
    run_with_timeout \
      "$XCODEBUILD_COMMAND_TIMEOUT_SECONDS" \
      "${xcodebuild_command[@]}" 2>&1 | tee -a "$log_file"
    status="${PIPESTATUS[0]}"
    set -e
    stop_launch_probe "$label"

    if [[ "$status" -eq 124 ]]; then
      echo "xcodebuild command timed out after ${XCODEBUILD_COMMAND_TIMEOUT_SECONDS}s" | tee -a "$log_file"
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

# A diagnostic subset never emits ordinary unit/UI qualification or coverage receipts.
DIAGNOSTIC_SEVEN_TESTS=(
  "ChaosMonkeyUITests/testKeyboardDismissalPreservesDraftWithoutSending"
  "HomeV2LayoutUITests/testLogSheetEditsUnitsWithKeyboardAndCancelsWithoutChangingHome"
  "HomeV2LayoutUITests/testEditorialUnsupportedWeightKeepsRawValueAndReviewVisible"
  "HomeV2LayoutUITests/testBodyFatCheckInRefreshesDataHeroWithoutSavingWeight"
  "HomeV2LayoutUITests/testCompositionHomeShowsBodyFatFirstAndHonestSupportingMetrics"
  "HomeV2LayoutUITests/testEditorialSingleReadingDoesNotClaimAWeightTrendBehindPhotoOrBodyFat"
  "HomeV2LayoutUITests/testBodyFatEditorAtLargestTextPreservesMethodUntilExplicitSelection"
)

finish_diagnostic_seven() {
  local command_exit="$1"
  local catalogue_exit=66
  trap - EXIT
  set +e
  if [[ -d "$ARTIFACT_DIR/diagnostic-seven.xcresult" ]]; then
    run_with_timeout 60 xcrun xcresulttool get test-results tests \
      --path "$ARTIFACT_DIR/diagnostic-seven.xcresult" \
      > "$ARTIFACT_DIR/diagnostic-catalogue.json" 2> "$ARTIFACT_DIR/diagnostic-catalogue.stderr"
    catalogue_exit="$?"
  fi
  python3 -I - "$ROOT_DIR" "$ARTIFACT_DIR" "$command_exit" "$catalogue_exit" \
    "$DIAGNOSTIC_PHASE" "$DIAGNOSTIC_BUILD_EXIT" "$DIAGNOSTIC_UI_EXIT" <<'DIAGNOSTIC_RECEIPT_PY'
import collections
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def strict_diagnostic_cases(payload, selected, log_text):
    """Cross-check the complete official catalogue against actual XCTest events."""
    def walk(nodes):
        if not isinstance(nodes, list):
            raise ValueError('Incomplete official test catalogue')
        for node in nodes:
            if not isinstance(node, dict) or not isinstance(node.get('nodeType'), str):
                raise ValueError('Malformed official test node')
            yield node
            yield from walk(node.get('children', []))

    cases = [n for n in walk(payload['testNodes']) if n['nodeType'] == 'Test Case']
    identifiers = [n.get('nodeIdentifier') for n in cases]
    if len(selected) != 7 or len(set(selected)) != 7:
        raise ValueError('Expected exactly seven unique selected identities')
    if collections.Counter(identifiers) != collections.Counter(selected):
        raise ValueError('Extra, missing or duplicate official cases')
    for case in cases:
        if case.get('result') != 'Passed':
            raise ValueError('Skipped, failed or unfinished official case')
        children = list(walk(case.get('children', [])))
        # A single case-run leaf is understood; hidden repetitions/configurations
        # or a changed schema fail closed rather than inventing execution proof.
        if children and (len(children) != 1 or children[0]['nodeType'] != 'Test Case Run'
                         or children[0].get('result') != 'Passed'):
            raise ValueError('Repeated, non-passing or unsupported child executions')
    events = []
    pattern = re.compile(r"^Test Case '-\[LogYourBodyUITests\.([^ ]+) ([^]]+)\]' (started|passed|failed|skipped)(?:[ .])", re.M)
    for event in pattern.finditer(log_text):
        events.append((event.group(1) + '/' + event.group(2) + '()', event.group(3)))
    starts = collections.Counter(i for i, state in events if state == 'started')
    terminals = collections.Counter(i for i, state in events if state != 'started')
    if starts != collections.Counter(selected) or terminals != collections.Counter(selected):
        raise ValueError('Extra, missing, repeated or unfinished XCTest execution events')
    if any(state not in ('started', 'passed') for _, state in events):
        raise ValueError('Non-passing XCTest execution event')
    # Every native Test Case line must belong to the understood module/format.
    native_lines = [line for line in log_text.splitlines() if line.startswith('Test Case ')]
    if len(native_lines) != len(events):
        raise ValueError('Unsupported or foreign XCTest execution event')
    active = set()
    for identifier, state in events:
        if state == 'started':
            if identifier in active:
                raise ValueError('Repeated active execution')
            active.add(identifier)
        elif identifier not in active:
            raise ValueError('Terminal event without its own start')
        else:
            active.remove(identifier)
    if active:
        raise ValueError('Unfinished execution')
    return [{'identifier': i, 'result': 'Passed', 'executionCount': 1} for i in selected]


def write_diagnostic_receipt(root, directory, command_exit, catalogue_exit, phase, build_exit, ui_exit):
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    errors = []
    selected = (directory / 'diagnostic-selected-tests.txt').read_text().splitlines()
    log_path = directory / 'diagnostic-seven.log'
    log_text = log_path.read_text(errors='replace') if log_path.is_file() else ''
    source = git('rev-parse', 'HEAD')
    patch = subprocess.check_output(['git', '-C', str(root), 'diff', 'HEAD', '--binary'])
    untracked = git('ls-files', '--others', '--exclude-standard')
    if (source != os.environ.get('DIAGNOSTIC_EXPECTED_SOURCE_SHA') or patch or untracked
            or (directory / 'source-revision.txt').read_text().strip() != source
            or (directory / 'source-working-tree.patch').read_bytes()):
        errors.append('sourceMismatch')
    if command_exit or build_exit or ui_exit:
        errors.append('commandOrStageFailure')
    if command_exit == 124 or build_exit == 124 or ui_exit == 124:
        errors.append('timeout')
    if log_text.count('Running diagnostic-seven (attempt ') != 1:
        errors.append('uiCommandAttemptMismatch')
    observed = None
    catalogue = None
    if catalogue_exit:
        errors.append('officialCatalogueUnavailable')
    else:
        try:
            catalogue = json.loads((directory / 'diagnostic-catalogue.json').read_text())
            observed = strict_diagnostic_cases(catalogue, selected, log_text)
        except (ValueError, KeyError, TypeError, OSError) as error:
            errors.append(str(error))
    tooling_file = directory / 'trusted-tooling.json'
    receipt = {
        'schemaVersion': 1, 'evidenceKind': 'diagnostic_ui_subset',
        'qualifying': False, 'nativeQualification': False,
        'status': 'failed' if errors else 'passed', 'errors': errors,
        'generatedAt': datetime.now(timezone.utc).isoformat(),
        'profile': 'lyb-ui-seven-v1', 'selectedTests': selected, 'tests': observed,
        'officialCatalogue': catalogue,
        'nativeEventLines': [line for line in log_text.splitlines() if line.startswith('Test Case ')],
        'phase': phase, 'commandExit': command_exit, 'buildExit': build_exit,
        'uiExit': ui_exit, 'catalogueExit': catalogue_exit,
        'sourceRevision': source, 'sourceTree': git('rev-parse', 'HEAD^{tree}'),
        'sourcePatchSha256': hashlib.sha256(patch).hexdigest(), 'untrackedSource': untracked.splitlines(),
        'policyEventSHA': os.environ.get('GITHUB_SHA', 'unknown'),
        'policyWorkflowSHA': os.environ.get('GITHUB_WORKFLOW_SHA', 'unknown'),
        'run': os.environ.get('GITHUB_RUN_ID', 'unknown'),
        'attempt': os.environ.get('GITHUB_RUN_ATTEMPT', 'unknown'),
        'job': os.environ.get('GITHUB_JOB', 'unknown'),
        'auditSha256': digest(root / 'scripts/ios/launch-quality-audit.sh'),
        'trustedTooling': json.loads(tooling_file.read_text()) if tooling_file.is_file() else None,
        'catalogueSha256': digest(directory / 'diagnostic-catalogue.json') if not catalogue_exit else None,
        'logSha256': digest(log_path) if log_path.is_file() else None,
        'uiCommandAttempts': log_text.count('Running diagnostic-seven (attempt '),
        'runnerRestartsObserved': log_text.count('Restarting after unexpected exit'),
        'unitWitnessCoverageRatchetPerformanceProtectedSignedPhysical': 'NOT_EXECUTED_OR_QUALIFIED',
    }
    (directory / 'diagnostic-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return 65 if errors else 0


if __name__ == '__main__':
    sys.exit(write_diagnostic_receipt(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]),
                                    int(sys.argv[4]), sys.argv[5], int(sys.argv[6]), int(sys.argv[7])))
DIAGNOSTIC_RECEIPT_PY
  local receipt_exit="$?"
  if [[ "$command_exit" -ne 0 ]]; then
    exit "$command_exit"
  fi
  exit "$receipt_exit"
}

run_diagnostic_seven() {
  local -a selectors=()
  local test_id
  DIAGNOSTIC_PHASE=source
  DIAGNOSTIC_BUILD_EXIT=-1
  DIAGNOSTIC_UI_EXIT=-1
  for test_id in "${DIAGNOSTIC_SEVEN_TESTS[@]}"; do
    selectors+=("-only-testing:LogYourBodyUITests/$test_id")
    printf '%s()\n' "$test_id"
  done > "$ARTIFACT_DIR/diagnostic-selected-tests.txt"
  trap 'finish_diagnostic_seven "$?"' EXIT
  [[ "${DIAGNOSTIC_EXPECTED_SOURCE_SHA:-}" =~ ^[0-9a-f]{40}$ &&
     "$(cat "$ARTIFACT_DIR/source-revision.txt")" == "$DIAGNOSTIC_EXPECTED_SOURCE_SHA" &&
     ! -s "$ARTIFACT_DIR/source-working-tree.patch" &&
     -z "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard)" ]] || return 65
  if [[ -n "${DIAGNOSTIC_TRUSTED_TOOLING_FILE:-}" ]]; then
    cp "$DIAGNOSTIC_TRUSTED_TOOLING_FILE" "$ARTIFACT_DIR/trusted-tooling.json"
  fi
  DIAGNOSTIC_PHASE=bootstrap
  bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"
  DIAGNOSTIC_PHASE=destination
  DESTINATION="$(IOS_DIR="$IOS_DIR" PROJECT="$PROJECT" SCHEME="$SCHEME" bash "$ROOT_DIR/scripts/ios/resolve-simulator-destination.sh")"
  COMMON_XCODEBUILD_ARGS=(
    -project LogYourBody.xcodeproj -scheme LogYourBody -destination "$DESTINATION"
    -parallel-testing-enabled NO -enableCodeCoverage YES
    -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES
    -default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 180
  )
  DIAGNOSTIC_PHASE=build
  if build_for_testing_once; then DIAGNOSTIC_BUILD_EXIT=0; else
    DIAGNOSTIC_BUILD_EXIT="$?"; return "$DIAGNOSTIC_BUILD_EXIT"
  fi
  DIAGNOSTIC_PHASE=ui
  if XCODEBUILD_COMMAND_TIMEOUT_SECONDS=1500 run_xcodebuild_test \
      diagnostic-seven "$ARTIFACT_DIR/diagnostic-seven.xcresult" \
      "$ARTIFACT_DIR/diagnostic-seven.log" "${selectors[@]}"; then DIAGNOSTIC_UI_EXIT=0; else
    DIAGNOSTIC_UI_EXIT="$?"; return "$DIAGNOSTIC_UI_EXIT"
  fi
  DIAGNOSTIC_PHASE=completed
}

cd "$IOS_DIR"

if [[ "$AUDIT_MODE" == diagnostic-seven ]]; then
  run_diagnostic_seven
  exit 0
fi

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

python3 "$ROOT_DIR/scripts/ios/test_launch_quality_evidence.py"
build_for_testing_once

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

# Actual same-producer calibration and all current Context safety bodies must pass BEFORE mounted fixture zero claims.
CORRECTION_FIXTURE_UNIT_TESTS=(
  "HomeV2ContextPolicyTests/testProvenanceNamesTheSourceAndTheTime"
  "HomeV2ContextPolicyTests/testWeekStripCoversSevenDaysAroundTheDate"
  "HomeV2ContextPolicyTests/testDeleteScopeIsSpelledOut"
  "HomeV2ContextPolicyTests/testEntriesGroupByMonthNewestFirstWithTheMonthsChange"
  "HomeV2ContextPolicyTests/testEntriesOrderSeptemberAndOctoberChronologicallyAtMonthBoundary"
  "HomeV2ContextPolicyTests/testEntriesOrderDecemberAndJanuaryAcrossYearBoundary"
  "HomeV2ContextPolicyTests/testDailyStepsCanReadTodayWithoutFabricatingABodyMetric"
  "HomeV2ContextPolicyTests/testDailyStepsDoesNotInventAZeroFromMissingOrAmbiguousStoredSteps"
  "HomeV2ContextPolicyTests/testDailyStepsFiltersOwnerAndHalfOpenDayBeforeSelectingNewestDuplicate"
  "HomeV2ContextPolicyTests/testDailyStepsMissingOrNegativeNewestValueDoesNotBorrowAnOlderValue"
  "HomeV2ContextPolicyTests/testDailyStepsFetchesOldSelectedDayWithoutThirtyDayLimitOrTodayFallback"
  "HomeV2ContextPolicyTests/testDailyStepsUsesCalendarDayAcrossDaylightSavingChange"
  "HomeV2ContextPolicyTests/testDailyStepsLateDayReadCannotReplaceNewSelection"
  "HomeV2ContextPolicyTests/testDailyStepsLateSameDayReadCannotOverwriteReload"
  "HomeV2ContextPolicyTests/testDailyStepsHeldAccountAReadCannotReplaceAccountB"
  "HomeV2ContextPolicyTests/testDailyStepsHeldOldLifetimeCannotReplaceSameSubjectNewLifetime"
  "HomeV2ContextPolicyTests/testDailyStepsRenderHidesOldLifetimeBeforeReplacementLoadStarts"
  "HomeV2ContextPolicyTests/testDailyStepsRejectsMismatchedMetricOrStaleOwnershipBeforeReading"
  "HomeV2ContextPolicyTests/testDailyStepsCancelledHeldReadDoesNotPublishItsValue"
  "HomeV2ContextPolicyTests/testHistoricalSamplesKeepTimestampSourceAndReviewWarning"
  "HomeV2ContextPolicyTests/testCorrectionTargetsOneRecordAndPreservesItsImportLineage"
  "HomeV2ContextPolicyTests/testCorrectionUsesChosenMethodAndOnlyExplicitlyClearsBodyFat"
  "HomeV2ContextPolicyTests/testHeldCorrectionRejectsReplacementLogoutAndCancellationInsideActualStore"
  "HomeV2ContextPolicyTests/testCorrectionCurrentOwnerPersistsExactRecordAndSuppressesPostWriteStaleCompletion"
  "HomeV2ContextPolicyTests/testCorrectionRefusesDeletedMissingAndNewerExactTargetRecords"
  "HomeV2ContextPolicyTests/testCorrectionAdmissionRejectsOwnedAndEmptyOwnerDuplicateWriterCandidates"
  "HomeV2ContextPolicyTests/testCorrectionNeutralProvenanceAndActualImperialEditorConversion"
  "HomeV2ContextPolicyTests/testCorrectionEditorOriginalReceiptCannotRebaseToSameAccountGeneration"
  "HomeV2ContextPolicyTests/testEntriesSelectExactRawRecordAcrossSameDayReorderAndRejectReplacement"
  "HomeV2ContextPolicyTests/testEntriesPreserveBFOnlyAndFlaggedWeightMetadataWithoutInference"
  "HomeV2ContextPolicyTests/testEntriesCalendarTieIsDeterministicAndExplicitSelectionWins"
  "HomeV2ContextPolicyTests/testEntriesDestinationRejectsCorrectionDeletionGenerationAndABAReturn"
  "HomeV2ContextPolicyTests/testPresentationAndEntriesReadLeaveActualStoredRecordsUnchanged"
  "HomeV2ContextPolicyTests/testOwnContextCorrectionRestoresVerifiedStoredRevisionAfterRefresh"
  "HomeV2ContextPolicyTests/testHeldContextCorrectionRejectsExternalRevisionAndDestinationABA"
  "HomeV2ContextPolicyTests/testHeldContextCorrectionRejectsSameSubjectGenerationAfterStoredWrite"
  "HomeV2ContextPolicyTests/testFailedCaseCleanupRejectsForeignOwnershipAndTerminatesActualHeldWriterBeforeDisposal"
  "HomeV2ContextPolicyTests/testFixtureHeldWriterRejectsCancellationInActualStoreAndWaitsForTaskTerminal"
  "HomeV2ContextPolicyTests/testFixtureHeldWriterRequiresFullReceiptWhenEditorUUIDIsReused"
  "HomeV2ContextPolicyTests/testAppSeedReadbackAcceptsActualOwnedRowsAndPreservesRawMetadata"
  "HomeV2ContextPolicyTests/testAppSeedReadbackRejectsWholePartialCachedConversionAndRecovers"
  "HomeV2ContextPolicyTests/testAppSeedReadbackRejectsEmptyAndMismatchedOwnerData"
  "HomeV2ContextPolicyTests/testCorrectionFixtureTransportCalibratesActualProductAPIAndInvalidation"
  "HomeV2ContextPolicyTests/testCorrectionFixtureFreshSessionZeroCannotBorrowAnotherSessionsCalibration"
  "HomeV2ContextPolicyTests/testBodyFatEditorGateRequiresExplicitRolloutOrAuthenticatedExclusiveFixture"
  "HomeV2ContextPolicyTests/testContextStepsDoesNotInventAValueForMissingData"
  "HomeV2ContextPolicyTests/testContextStepsPreservesPositiveCountFormatting"
  "HomeV2ContextPolicyTests/testContextStepsRejectsNegativeCounts"
  "HomeV2ContextPolicyTests/testContextStepsRetainsAnExplicitZero"
  "HomeV2ContextPolicyTests/testEditorDisplayFontIsBundledAndRegistered"
  "HomeV2ContextPolicyTests/testEntryEditHistoricalReadingsSurviveButReplacementValuesAreValidated"
  "HomeV2ContextPolicyTests/testEntryEditMissingWeightStaysMissingAndExistingWeightCannotBeCleared"
  "HomeV2ContextPolicyTests/testEntryEditPreservationRequiresItsOwnGateOrAuthenticatedTestFixture"
  "HomeV2ContextPolicyTests/testEntryEditRejectsInvalidNumbersWithoutSubstitutingDefaults"
  "HomeV2ContextPolicyTests/testEntrySavedConfirmationDoesNotInventWeight"
  "HomeV2ContextPolicyTests/testCurrentMainHistoricalEntriesPreserveFlaggedTimesAndImportProvenance"
  "HomeV2ContextPolicyTests/testCurrentMainLegacyCorrectionPreservesImportOriginAndManualFieldProvenance"
  "HomeV2ContextPolicyTests/testCorrectionWriterDirtyTargetAndMovedCommittedIdentityKeepEveryPendingDraft"
  "HomeV2ContextPolicyTests/testCorrectionWriterComparesActualFetchedFullPreimageAfterFirstInsideAdmission"
  "HomeV2ContextPolicyTests/testCorrectionWriterKeepsOpaqueColumnsAndUnrelatedDraftThroughRealIndependentRead"
  "HomeV2ContextPolicyTests/testCorrectionWriterOrdersTwoInsideAdmissionsOneObserverAndImmediateActualStoredDTO"
  "HomeV2ContextPolicyTests/testCorrectionWriterRejectsSecondAdmissionOrLateDirtyTargetBeforeObserverSuccessAndCommit"
  "HomeV2ContextPolicyTests/testCorrectionPostcommitFailuresKeepDurableDataAndNeverBecomeAdmissionRejections"
  "HomeV2ContextPolicyTests/testCorrectionWriterGenericNilRetainsButExplicitMethodNilAndClearUseActualStoredValues"
  "HomeV2ContextPolicyTests/testDisplayedCorrectionIntentPreservesRawNoOpPrecisionAndParsesOnlyGenuineUnitEdits"
  "HomeV2ContextPolicyTests/testCorrectionSaveSkipsSemanticNoOpEffectsButPersistsExplicitMethodChanges"
  "HomeV2ContextPolicyTests/testTodayCorrectionReceiptUsesActualWriterPreviousAndCommittedChangedWeight"
  "HomeV2ContextPolicyTests/testTodayCorrectionReceiptRejectsActualBodyFatOnlyMissingWeightAndNoOpWriterResults"
)
CORRECTION_FIXTURE_UNIT_EVIDENCE_ARGS=()
for test_id in "${CORRECTION_FIXTURE_UNIT_TESTS[@]}"; do
  CORRECTION_FIXTURE_UNIT_EVIDENCE_ARGS+=(--expected-test "${test_id}()")
done

# Current-main and combined optional-step/lifetime witnesses must pass before mounted UI.
CURRENT_COMPOSITION_UNIT_TESTS=(
  "DashboardStepPersistenceTests/testMissingHealthKitStepsDoNotCreateAnEmptyDashboardDay"
  "DashboardStepPersistenceTests/testMissingHealthKitStepsLeaveExistingDashboardRowUnchanged"
  "DashboardStepPersistenceTests/testObservedHealthKitZeroStillPersistsThroughDashboard"
  "HealthKitImportOwnershipTests/testCancelledMissingTodayQueryCannotClearCurrentReading"
  "HealthKitImportOwnershipTests/testLateMissingTodayQueryCannotClearReplacementAccountReading"
  "HealthKitImportOwnershipTests/testObservedTodayZeroPublishesAndPersistsAsAnActualReading"
  "HealthKitImportOwnershipTests/testTodayMissingQuantityAndHealthKitNoDataDoNotPublishAReading"
  "HealthKitStepCountPolicyTests/testMissingQuantityRemainsAbsentWhileMeasuredZeroIsPreserved"
  "HealthKitStepCountPolicyTests/testNoDataIsRecognizedWithoutInventingAStepCount"
  "PhotoMetadataServiceTests/testBodyFatEstimateBecomesAbsentWhenTheLastValueIsRemoved"
  "PhotoMetadataServiceTests/testBodyFatEstimateDoesNotCollideOnCommaSeparatedIDs"
  "PhotoMetadataServiceTests/testBodyFatEstimateDoesNotReuseAnotherOwnersSameRecordID"
  "PhotoMetadataServiceTests/testBodyFatEstimatePreservesUnsortedInterpolationAndEqualDateSelection"
  "PhotoMetadataServiceTests/testBodyFatEstimateReflectsChangedDatesWithStableRecordIDs"
  "PhotoMetadataServiceTests/testBodyFatEstimateReflectsChangedValuesWithStableRecordIDs"
  "ProfileSettingsPolicyTests/testBirthdayAgeChangesOnTheLocalBirthdayAcrossTimeZones"
  "ProfileSettingsPolicyTests/testBirthdayAgeRetainsLeapDayAndIgnoresLegacyTimestampTimeOfDay"
  "ProfileSettingsPolicyTests/testBirthdayAgeUsesGregorianYearsWithANonGregorianUserCalendar"
  "ProfileSettingsPolicyTests/testBirthdayPickerCalendarRoundTripsThroughTheActualProfilePayload"
  "ProfileSettingsPolicyTests/testBirthdayPresentationAndBirthYearPreserveTheAPIJanFirstDate"
  "ProfileSettingsPolicyTests/testBirthdayTodayBoundaryUsesTheLocalDayOnEitherSideOfTheDateLine"
  "ProfileSettingsPolicyTests/testBirthdayValidationDoesNotAdmitAnUnderageUserBeforeTheirLocalBirthday"
  "SyncIntegrationRemotePayloadTests/testMalformedProfilePullDoesNotInsertOrPoisonFollowingValidSave"
  "SyncIntegrationRemotePayloadTests/testMobileProfilePullPersistsRequiredFieldsIntoIndependentContext"
  "SyncIntegrationRemotePayloadTests/testProfilePullDoesNotEraseBirthDateForMalformedMissingOrNullValues"
  "SyncIntegrationRemotePayloadTests/testProfilePullPersistsDateOnlyBirthDateFromMobileAPI"
  "SyncIntegrationRemotePayloadTests/testProfilePullPreservesKnownMetadataWhenMobilePayloadOmitsIt"
  "SyncIntegrationRemotePayloadTests/testProfilePullRetainsWholeAndFractionalTimestampBirthDates"
  "SyncIntegrationRemotePayloadTests/testProfilePullUpdatesEmailAndVersionWithoutReplacingCreationDate"
  "DashboardViewModelHealthSyncWiringTests/testSupersededRefreshMissingStepsCannotFinishNewerSameOwnerRefresh"
  "DashboardViewModelHealthSyncWiringTests/testCurrentObservedZeroSavesAndReadsBackBeforeReceiptPublicationAndSync"
  "DashboardViewModelHealthSyncWiringTests/testHeldObservedZeroIsRejectedInsideStoreAfterSupersessionOrCancellation"
)
CURRENT_COMPOSITION_UNIT_EVIDENCE_ARGS=()
for test_id in "${CURRENT_COMPOSITION_UNIT_TESTS[@]}"; do
  CURRENT_COMPOSITION_UNIT_EVIDENCE_ARGS+=(--expected-test "${test_id}()")
done

# Require the added timeline/ruler/viewer witnesses in the whole-unit result.
# Selecting the target alone cannot prove that each required test executed.
TIMELINE_REPAIR_UNIT_TESTS=(
  "HomeV2PhotoJourneyPolicyTests/testPhotoScrubRequiresMoreThanASecondAndMapsBothDirectionsWithoutAnInitialJump"
  "HomeV2PhotoJourneyPolicyTests/testPhotoScrubRejectsEmptySingleOrInvalidSelectionsAndGeometry"
  "HomeV2PhotoJourneyPolicyTests/testPhotoScrubGateDefaultsOffAndUsesThePlatformPort"
  "HomeV2PhotoJourneyPolicyTests/testAdaptiveRulerCapsTenYearDailyHistoryAndKeepsSelectedObservation"
  "HomeV2PhotoJourneyPolicyTests/testAdaptiveRulerSparseTenYearHistoryDoesNotGenerateCalendarNoise"
  "HomeV2PhotoJourneyPolicyTests/testAdaptiveRulerNeverLosesASelectedCoincidentOriginalIndex"
  "HomeV2PhotoJourneyPolicyTests/testAdaptiveRulerRapidForwardReverseSelectionRetainsEveryRawSelectableDate"
  "HomeV2PhotoJourneyPolicyTests/testAdaptiveRulerReversedInputPreservesOriginalIndicesAndTimestamps"
  "HomeV2PhotoJourneyPolicyTests/testAdaptiveRulerBoundsExtremeHistoryBeforeIteratingCalendarMarks"
  "HomeV2PhotoJourneyPolicyTests/testAdaptiveRulerCalendarLocaleAndLargeTypeRespectActualLabelSpacing"
  "HomeV2PhotoJourneyPolicyTests/testAdaptiveRulerInvalidGeometryStaysFiniteAndSelectedIsVisible"
  "HomeV2PhotoJourneyPolicyTests/testAdaptiveRulerRTLAndLTRMapTheSameObservedMomentAndClampEdges"
  "HomeV2PhotoJourneyPolicyTests/testHomeWeightScaleUsesSupportedObservedBoundsWithoutInventingReadings"
  "HomeV2PhotoJourneyPolicyTests/testHomeWeightScaleSnapshotExcludesForeignOwnersAndReflectsSameRowCorrection"
  "HomeV2PhotoJourneyPolicyTests/testHomeWeightScaleUnitChangeConvertsOnceAndKeepsCanonicalBounds"
  "HomeV2PhotoJourneyPolicyTests/testHomeFixedChartScaleSurvivesVisibleDateChangesWhenItEnclosesObservedValues"
  "HomeV2PhotoJourneyPolicyTests/testHomeFixedChartScaleRejectsClippingInvalidBoundsAndZeroAnchorContradictions"
  "HomeV2PhotoJourneyPolicyTests/testHeroCacheMethodOnlyCorrectionRevokesAndRestoresWideDEXAEstimate"
  "HomeV2PhotoJourneyPolicyTests/testHeroCacheFieldSourceOnlyCorrectionRevokesAndRestoresWideDEXAEstimate"
  "HomeV2PhotoJourneyPolicyTests/testHeroCacheHeightChangePreservesMeasurementsAndRecomputesCanonicalFFMI"
  "HomeV2PhotoJourneyPolicyTests/testHeroReadingMissingRequestedMetricCannotSubstituteAnotherAvailableKind"
  "HomeV2PhotoJourneyPolicyTests/testHeroReadingRejectsInvalidCompositionGeometryWithoutRewritingDisplayValue"
  "HomeV2PhotoJourneyPolicyTests/testContextualShareStartsWithChosenMetricAndKeepsTheFrozenMomentAcrossPickerChanges"
  "HomeV2PhotoJourneyPolicyTests/testContextualShareUnavailableChosenMetricStaysChosenAndCannotExport"
  "HomeV2PhotoJourneyPolicyTests/testContextualSharePrivacyDefaultsDoNotAddUnselectedHealthFieldsOrVisuals"
  "HomeV2PhotoJourneyPolicyTests/testScreenshotOfferRequiresActiveVisibleAndNoExistingPresentation"
  "HomeV2PhotoJourneyPolicyTests/testMVPTopLevelSidebarHasOnlyTodayAndProgress"
  "HomeV2PhotoJourneyPolicyTests/testFrozenHomeShareRejectsLogoutAccountReplacementAndSameSubjectGenerationChange"
  "HomeV2PhotoJourneyPolicyTests/testRulerDropsLabelsWhoseActualClampedFramesOverlapAtEitherEdge"
  "HomeV2PhotoJourneyPolicyTests/testRulerActualLabelGeometryStaysBoundedAtAccessibilitySpacingAndNarrowWidths"
  "HomeV2PhotoJourneyPolicyTests/testLoadingSelectedShareSnapshotCannotExportOrReuseAStaleNumber"
  "HomeV2PhotoJourneyPolicyTests/testShareDetailControlsUseOnlyNonblankFieldsOfTheSelectedFrozenSnapshot"
  "HomeV2TimelinePolicyTests/testChosenMetricAdapterRetainsActualBracketedValuesAnchorsAndCanonicalFFMI"
  "HomeV2TimelinePolicyTests/testChosenMetricAdapterConvertsWeightOnceAndPreservesInferenceAcrossUnitChanges"
  "HomeV2TimelinePolicyTests/testChosenMetricAdapterExactSelectedRecordWinsOverBracketedHistory"
  "HomeV2TimelinePolicyTests/testChosenMetricAdapterKeepsUnavailableKindAndDoesNotClaimFFMIWasLogged"
  "HomeV2TimelinePolicyTests/testNonPhotoPresentationAdmitsValidOwnedMomentWithoutAuthorizingPhotoWork"
  "HomeV2TimelinePolicyTests/testNonPhotoPresentationRejectsDeletedCorrectedAndReconciledReplacementRows"
  "HomeV2TimelinePolicyTests/testOrdinaryTimelineSwipeRequiresHorizontalIntentBeforeRecognition"
  "HomeV2TimelinePolicyTests/testOrdinaryTimelineSlowSwipeUsesIndependentWidthThresholdsAndDirection"
  "HomeV2TimelinePolicyTests/testOrdinaryTimelineFastReverseFlickUsesFinalVelocityAndMinimumTravel"
  "HomeV2TimelinePolicyTests/testOrdinaryTimelineSwipeMirrorsRTLAndRejectsMalformedOrVerticalGeometry"
  "HomeV2TimelinePolicyTests/testRapidReverseSwipeResolvesExistingIDsAndKeepsTheRequestedMissingMetric"
  "HomeV2TimelinePolicyTests/testPhotoViewerAdmissionRequiresTheExactOpeningEvenWhenOwnerRowsAndPhotoAreUnchanged"
  "HomeV2TimelinePolicyTests/testPhotoViewerAdmissionRejectsDismissalNonactiveRootAndEveryCompetingRoute"
  "HomeV2TimelinePolicyTests/testPhotoViewerAdmissionRetainsActualSelectionSessionAndRawPhotoRevisionFences"
  "HomeV2TimelinePolicyTests/testPhotoViewerAdmissionCannotUseGeneralNonPhotoAdmissionToAuthorizeViewerWork"
  "HomeV2TimelinePolicyTests/testHeldPhotoViewerCallbackCannotActAfterSameOwnerDataAndPhotoCloseReopen"
  "HomeV2ContextPolicyTests/testBodyFatEditorGateRequiresExplicitRolloutOrAuthenticatedExclusiveFixture"
  "HomeV2ContextPolicyTests/testContextStepsDoesNotInventAValueForMissingData"
  "HomeV2ContextPolicyTests/testContextStepsPreservesPositiveCountFormatting"
  "HomeV2ContextPolicyTests/testContextStepsRejectsNegativeCounts"
  "HomeV2ContextPolicyTests/testContextStepsRetainsAnExplicitZero"
  "HomeV2ContextPolicyTests/testEditorDisplayFontIsBundledAndRegistered"
  "HomeV2ContextPolicyTests/testEntryEditHistoricalReadingsSurviveButReplacementValuesAreValidated"
  "HomeV2ContextPolicyTests/testEntryEditMissingWeightStaysMissingAndExistingWeightCannotBeCleared"
  "HomeV2ContextPolicyTests/testEntryEditPreservationRequiresItsOwnGateOrAuthenticatedTestFixture"
  "HomeV2ContextPolicyTests/testEntryEditRejectsInvalidNumbersWithoutSubstitutingDefaults"
  "HomeV2ContextPolicyTests/testEntrySavedConfirmationDoesNotInventWeight"
  "HomeV2ContextPolicyTests/testCurrentMainHistoricalEntriesPreserveFlaggedTimesAndImportProvenance"
  "HomeV2ContextPolicyTests/testCurrentMainLegacyCorrectionPreservesImportOriginAndManualFieldProvenance"
  "HomeV2ContextPolicyTests/testCorrectionWriterDirtyTargetAndMovedCommittedIdentityKeepEveryPendingDraft"
  "HomeV2ContextPolicyTests/testCorrectionWriterComparesActualFetchedFullPreimageAfterFirstInsideAdmission"
  "HomeV2ContextPolicyTests/testCorrectionWriterKeepsOpaqueColumnsAndUnrelatedDraftThroughRealIndependentRead"
  "HomeV2ContextPolicyTests/testCorrectionWriterOrdersTwoInsideAdmissionsOneObserverAndImmediateActualStoredDTO"
  "HomeV2ContextPolicyTests/testCorrectionWriterRejectsSecondAdmissionOrLateDirtyTargetBeforeObserverSuccessAndCommit"
  "HomeV2ContextPolicyTests/testCorrectionPostcommitFailuresKeepDurableDataAndNeverBecomeAdmissionRejections"
  "HomeV2ContextPolicyTests/testCorrectionWriterGenericNilRetainsButExplicitMethodNilAndClearUseActualStoredValues"
  "HomeV2ContextPolicyTests/testDisplayedCorrectionIntentPreservesRawNoOpPrecisionAndParsesOnlyGenuineUnitEdits"
  "HomeV2ContextPolicyTests/testCorrectionSaveSkipsSemanticNoOpEffectsButPersistsExplicitMethodChanges"
  "HomeV2ContextPolicyTests/testTodayCorrectionReceiptUsesActualWriterPreviousAndCommittedChangedWeight"
  "HomeV2ContextPolicyTests/testTodayCorrectionReceiptRejectsActualBodyFatOnlyMissingWeightAndNoOpWriterResults"
  "DashboardViewModelHealthSyncWiringTests/testHeldLatestLoadCannotPublishAcrossOwnerOrGenerationReplacement"
  "DashboardViewModelHealthSyncWiringTests/testCancelledHeldLoadCannotPublishAndCurrentOwnerCanRecover"
  "DashboardViewModelHealthSyncWiringTests/testNewerSameOwnerLoadKeepsDailyTailWhenOlderLatestReturns"
  "DashboardViewModelHealthSyncWiringTests/testPublishedLifetimeClearsWithoutHeldReaderReturning"
  "DashboardViewModelHealthSyncWiringTests/testNilOwnerAndOwnedEmptyLoadHaveDifferentCompletionSemantics"
  "DashboardViewModelHealthSyncWiringTests/testQueuedNilCaptureCannotRebaseOrClearNewerHeldRefresh"
  "DashboardViewModelHealthSyncWiringTests/testActualStartupPaintsLatestBeforeHeldCoordinatorAndThenLoadsHistory"
  "DashboardViewModelHealthSyncWiringTests/testSupersededStartupCannotReplaceNewerSameOwnerHeldRefresh"
  "DashboardViewModelHealthSyncWiringTests/testSupersededStartupCannotRestartAfterNewerSameOwnerLoadCompletes"
  "DashboardViewModelHealthSyncWiringTests/testSameLifetimeProfilePublicationPreservesHeldRequest"
  "DashboardViewModelHealthSyncWiringTests/testActualPublishedPayloadsCarryReceiptBeforeStoredGetterChanges"
  "DashboardViewModelHealthSyncWiringTests/testCoordinatorErrorStillCompletesOwnedLocalRefreshWithoutStuckSpinner"
  "DashboardViewModelHealthSyncWiringTests/testHistoricalTaskUsesOriginalLifetimeAndCurrentOwnerRecovers"
  "DashboardViewModelHealthSyncWiringTests/testOlderHeldRefreshCannotClearNewerRefreshTerminalState"
  "DashboardViewModelHealthSyncWiringTests/testStaleExplicitRefreshReceiptCannotInvalidateCurrentPublication"
  "DashboardViewModelHealthSyncWiringTests/testHeldRefreshCannotAdoptReplacementOrFinishAfterCancellation"
)
TIMELINE_REPAIR_UNIT_EVIDENCE_ARGS=()
for test_id in "${TIMELINE_REPAIR_UNIT_TESTS[@]}"; do
  TIMELINE_REPAIR_UNIT_EVIDENCE_ARGS+=(--expected-test "${test_id}()")
done

# The whole unit target is the gate: every journey test in docs/USER_JOURNEYS.md
# runs on every PR (all 67 files are registered in the target as of the orphan rescue).
run_xcodebuild_test \
  "launch-quality-unit-tests" \
  "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" \
  "$ARTIFACT_DIR/launch-quality-unit-tests.log" \
  -only-testing:LogYourBodyTests
assert_xcresult_evidence \
  "$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" --require-biometric-coverage "${CHAT_UNIT_EVIDENCE_ARGS[@]}" "${CORRECTION_FIXTURE_UNIT_EVIDENCE_ARGS[@]}" "${CURRENT_COMPOSITION_UNIT_EVIDENCE_ARGS[@]}" "${TIMELINE_REPAIR_UNIT_EVIDENCE_ARGS[@]}"

python3 "$ROOT_DIR/scripts/ios/native-coverage-ratchet.py" \
  --coverage "$ARTIFACT_DIR/launch-quality-unit-tests.coverage.json" \
  --evidence "$ARTIFACT_DIR/launch-quality-unit-tests.evidence.json" \
  --baseline "$ROOT_DIR/scripts/ios/native-coverage-baseline.json" \
  --profile quality-unit --source-sha "$(git -C "$ROOT_DIR" rev-parse HEAD)" \
  --base-revision "${BASE_SHA:-}" --source-root "$ROOT_DIR" \
  --scheme "$SCHEME" --only-testing LogYourBodyTests \
  > "$ARTIFACT_DIR/launch-quality-unit-tests.ratchet.json"

# Every UI check runs in ONE xcodebuild invocation. On hosted macOS each
# test-without-building invocation pays 3-6 min launching the UI test runner
# before its first test (xcresult action log, run 38320479871: runner launch
# 340-537s per invocation). Three separate UI invocations plus the unit target
# overran the 40-minute step with every test passing. Same tests, same exact
# evidence checks, one runner launch.
LAUNCH_QUALITY_UI_TESTS=(
  "HomeV2LayoutUITests/testSelectedMomentUnavailableWeightDoesNotCarryPastReading"
  "HomeV2LayoutUITests/testSelectedMomentBodyFatOnlyKeepsSourceWithoutFalseAbsence"
  "HomeV2LayoutUITests/testSelectedInferredWeightHasRealFocusWithZeroPastSamples"
  "HomeV2LayoutUITests/testSelectedInferredWeightHasRealFocusWithOnePastSample"
  "HomeV2TimelineIntegrationUITests/testMountedHeldCorrectionKeepsOriginalContextThroughActualStoredReturn"
  "HomeV2TimelineIntegrationUITests/testMountedHeldCorrectionRejectsOldTaskAfterSameSubjectNewEditorABA"
  "HomeV2LayoutUITests/testLogSheetHasOneHeadingAndKeepsEntryControls"
  "HomeV2LayoutUITests/testLogSheetEditsUnitsWithKeyboardAndCancelsWithoutChangingHome"
  "HomeV2LayoutUITests/testLogSheetAtLargestTextKeepsValueAndDetailsReachable"
  "HomeV2LayoutUITests/testEditorialDataHeroLabelsVisualEstimate"
  "HomeV2LayoutUITests/testEditorialSingleWeightDoesNotInventAHistory"
  "HomeV2LayoutUITests/testEditorialSingleReadingDoesNotClaimAWeightTrendBehindPhotoOrBodyFat"
  "HomeV2LayoutUITests/testCompositionHomeShowsBodyFatFirstAndHonestSupportingMetrics"
  "HomeV2LayoutUITests/testSupportingMetricTapsOpenTheirOwnProgressWorkspace"
  "HomeV2LayoutUITests/testBodyFatCheckInRefreshesDataHeroWithoutSavingWeight"
  "HomeV2LayoutUITests/testCompositionContextAtLargestTextKeepsEachSupportingMetricReachable"
  "HomeV2LayoutUITests/testBodyFatEditorAtLargestTextPreservesMethodUntilExplicitSelection"
  "HomeV2TimelineIntegrationUITests/testHorizontalPhotoDragPagesPixelsAndMetricsWithoutOpeningViewer"
  "HomeV2TimelineIntegrationUITests/testSelectedWeightOnlyDayNeverBorrowsTodaysBodyFat"
  "HomeV2TimelineIntegrationUITests/testBodyFatCheckInUpdatesSelectedHistoricalPhotoWithoutChangingWeight"
  "HomeV2TimelineIntegrationUITests/testSelectedDayStepsAtLargestTextFollowThePhotoAndRemainReachable"
  "LogYourBodyUITests/testHomeV2PhotoFirstKeepsTheNumberBelowThePhoto"
  "LogYourBodyUITests/testHomeV2ProgressIsOneMetricWorkspace"
  "LogYourBodyUITests/testHomeV2MetricFirstLogsWeightAndConfirmsInPlace"
  "LogYourBodyUITests/testHomeV2ProgressRefreshesAfterEditingAnExistingDay"
  "HomeV2TimelineIntegrationUITests/testVerticalRulerDragDoesNotSelectOrNavigateAndHorizontalScrubStillWorks"
  "HomeV2LayoutUITests/testEditorialWeightOnlyHeroShowsActualSparseReadings"
  "LogYourBodyUITests/testHomeV2ChangingLogDateDoesNotCreateATodayUndoReceipt"
  "ChaosEdgeCaseUITests/testBodyFatEntryRejectsOutOfRangeValues"
  "LogYourBodyUITests/testHomeV2SwipeMovesPhotoDateAndMetricsTogether"
  "LogYourBodyUITests/testHomeV2ScrubberJumpsThroughBodyHistory"
  "LogYourBodyUITests/testHomeV2TimelineCoachMarkDismissesPermanently"
  "HomeV2TimelineIntegrationUITests/testDiagnosticMountedCurrentPhotoCodeRejectsHistoricalIdentity"
  "HomeV2TimelineIntegrationUITests/testDiagnosticMountedHistoricalPhotoCodeRejectsCurrentIdentity"
  "HomeV2TimelineIntegrationUITests/testDiagnosticMountedDefaultGrayAndBlankRejectPhotoIdentity"
  "HomeV2TimelineIntegrationUITests/testSelectedMomentInfersBracketedBodyFatWithProvenance"
  "LogYourBodyUITests/testProgressShareKeepsSelectedMetricAndVisibleValue"
  "HomeV2LayoutUITests/testEditorialUnsupportedWeightKeepsRawValueAndReviewVisible"
  "LogYourBodyUITests/testHomeV2AskSyntheticFullTurnRestoresAfterRelaunch"
  "LogYourBodyUITests/testHomeV2AskSyntheticFailedTurnRetriesOriginalIdentity"
  "LogYourBodyUITests/testHomeV2AskSyntheticCancelledTurnRecovers"
  "LogYourBodyUITests/testLaunchQualityGateCapturesCriticalSurfaces"
  "LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFixedCTA"
  "LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFirstPhotoCTA"
  "LogYourBodyUITests/testLaunchQualityGateCapturesTimelineSurfaces"
  "LogYourBodyUITests/testProfileLogoutSignsOutFromPushedDetail"
  "OnboardingGoldenPathUITests/testBodyScoreOnboardingGoldenPathReachesReveal"
  "HomeV2TimelineIntegrationUITests/testPhotoHoldScrubsBothDirectionsThenAnotherHoldRestoresTap"
  "HomeV2TimelineIntegrationUITests/testPhotoScrubResetsWhenNavigatingToTheMenuAndBack"
  "HomeV2PhotoViewerLayoutUITests/testPhotoViewerHoldScrubsAndResetsAfterToolsNavigation"
  "MesocycleCanvasUITests/testReducedMotionUsesStackedDayCards"
  "MesocycleCanvasUITests/testGoalThroughUndoKeepsTheCanvasAndReadbackTogether"
  "LogYourBodyUITests/testBodyFatEditorImportedCorrectionAndDeleteCancelPreserveSource"
  "LogYourBodyUITests/testBodyFatEditorLargestTextKeepsFocusedMetricAndDoneVisible"
  "LogYourBodyUITests/testBodyFatEditorPreservesMissingWeightAndRecoversFromValidation"
  "LogYourBodyUITests/testHomeV2ManualCorrectionKeepsImportedSiblingAndUndoSource"
  "LogYourBodyUITests/testHomeV2PhotoOnlyEditorDoesNotInventWeight"
)

# Security-sensitive chaos regressions use the same native execution and
# exact-test evidence validator as the existing launch quality checks.
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
# One runner launch (up to ~9 min hosted) plus all selected UI tests
# replaces three separately bounded invocations, so its own bound is the
# per-invocation limit plus the work the other two used to carry.
UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS="${UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS:-1500}"
XCODEBUILD_COMMAND_TIMEOUT_SECONDS="$UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS" run_xcodebuild_test \
  "launch-quality-ui" \
  "$UI_RESULT_BUNDLE" \
  "$ARTIFACT_DIR/launch-quality-ui.log" \
  "${UI_SELECTORS[@]}"
assert_xcresult_evidence "$UI_RESULT_BUNDLE" "${UI_EVIDENCE_ARGS[@]}" \
  --critical-captures --require-settings-row-coverage --require-chaos-accounting-coverage --require-canvas-coverage

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
  printf -- '- Optical grid drift ratchet: `optical-grid-audit.md`\n'
  printf -- '- Unit coverage: photo timeline HUD launch policy, Body Score share card layout\n'
  printf -- '- Fixture UI coverage: home hero + chat composer, Jovie swipe/menu Timeline/Stats, one timeline scrubber, home/analytics/onboarding/share screenshot attachments\n'
  printf -- '- Evidence scope: `fixture_ui`; injected auth and entitlement state. Real Sign in with Apple, purchase, and restore remain `not_verified`.\n'
  printf -- '- Required passing test IDs and ten screenshot hashes: `launch-quality-ui.evidence.json`. First failed attempt bundles are retained.\n'
  printf -- '- Source: `source-revision.txt` plus `source-working-tree.patch`; this is not exact deployed-build certification.\n'
  printf -- '- Runtime warning audit: `runtime-warnings.log`, fail-on-warning=`%s`\n' "$FAIL_ON_RUNTIME_WARNINGS"
  printf -- '- Build strategy: one `build-for-testing`, the complete unit target, then one UI invocation covering inherited surface cases, two canvas cases, and twelve bounded chaos regressions with simulator parallelism disabled\n'
  printf -- '- Required native coverage: biometric policy, SettingsRow, chaos action accounting, and executed MesocycleCanvas app/view lines. Canvas captures cover reduced motion, replay/readback, and undo.\n'
  printf -- '- Build timeout: `%ss`; test command timeout: `%ss` per xcodebuild invocation\n' "$BUILD_FOR_TESTING_TIMEOUT_SECONDS" "$XCODEBUILD_COMMAND_TIMEOUT_SECONDS"
  printf -- '- Logs and result bundles: `%s`\n' "$ARTIFACT_DIR"
} > "$ARTIFACT_DIR/summary.md"

echo "Launch quality audit logs written to $ARTIFACT_DIR"
