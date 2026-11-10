#!/usr/bin/env bash
# Diagnostic-seven machinery for launch-quality-audit.sh (invoked with
# --diagnostic-seven). Sourced by that script, so these functions share its
# variables and helpers at call time. Kept in its own file to respect the
# company size-500 ratchet on launch-quality-audit.sh - the same extraction
# pattern as the launch-ui-regression report writer.

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
