#!/usr/bin/env bash
# Runs the real-device chaos-testing harness (ChaosMonkeyUITests +
# ChaosEdgeCaseUITests) against a connected iPhone, then extracts every
# xcresult attachment and writes a compact issues.json summarizing failures.
#
# Usage:
#   scripts/ios/chaos-device.sh
#   LYB_CHAOS_STEPS=40 scripts/ios/chaos-device.sh
#
# Safe to rerun: every invocation gets its own timestamped result bundle,
# attachments directory, and issues.json, so reruns never clobber prior
# evidence. Never commit the .xcresult bundle or its exported attachments.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
PROJECT="${PROJECT:-LogYourBody.xcodeproj}"
SCHEME="${SCHEME:-LogYourBody}"
DESTINATION="${DESTINATION:-platform=iOS,id=00008130-001958C20A2B803A}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-G24T327LXT}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$HOME/.codex/goals/lyb-chaos/DerivedData}"
GOAL_DIR="${GOAL_DIR:-$HOME/.codex/goals/lyb-chaos}"
RESULTS_DIR="${RESULTS_DIR:-$GOAL_DIR/results}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_BUNDLE="${RESULT_BUNDLE:-$RESULTS_DIR/chaos-$STAMP.xcresult}"

LYB_CHAOS_SEED="${LYB_CHAOS_SEED:-20260928}"
LYB_CHAOS_STEPS="${LYB_CHAOS_STEPS:-250}"
LYB_CHAOS_FIXTURE="${LYB_CHAOS_FIXTURE:--lybUITestPhotoTimelineHUDFixture}"
export TEST_RUNNER_LYB_CHAOS_SEED="$LYB_CHAOS_SEED"
export TEST_RUNNER_LYB_CHAOS_STEPS="$LYB_CHAOS_STEPS"
export TEST_RUNNER_LYB_CHAOS_FIXTURE="$LYB_CHAOS_FIXTURE"

mkdir -p "$RESULTS_DIR"
cd "$IOS_DIR"

bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"

# The shared project provisioning settings can carry a stale, manually
# specified profile alongside automatic signing (seen on this device
# destination as of 2026-09-28: "conflicting provisioning settings").
# These are command-line-only overrides for this invocation; they do not
# touch the committed project file.
SIGNING_OVERRIDES=(
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  CODE_SIGN_STYLE=Automatic
  CODE_SIGN_IDENTITY="Apple Development"
  PROVISIONING_PROFILE_SPECIFIER=
  PROVISIONING_PROFILE=
)

COMMON_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -resultBundlePath "$RESULT_BUNDLE"
  -allowProvisioningUpdates
  -only-testing:LogYourBodyUITests/ChaosMonkeyUITests
  -only-testing:LogYourBodyUITests/ChaosEdgeCaseUITests
)

# `test-without-building` skips the build phase entirely and reuses whatever
# binary is already on disk under DERIVED_DATA_PATH -- it cannot detect a
# source change, so it is only safe when the caller *knows* that binary was
# built from these exact sources (e.g. a prior `chaos-device.sh` run from
# this same worktree). Default to `test`, which always resyncs (freshly, or
# incrementally against DERIVED_DATA_PATH's cached artifacts) before running.
SKIP_BUILD="${SKIP_BUILD:-false}"

# A failing test suite is exactly the case this script needs to keep running
# for (to export attachments and write issues.json), so capture xcodebuild's
# exit status instead of letting `set -e` abort the script on it, and exit
# with that status only at the very end, after evidence is written.
xcodebuild_status=0
if [[ "$SKIP_BUILD" == "true" ]]; then
  echo "SKIP_BUILD=true; running test-without-building against $DERIVED_DATA_PATH."
  xcodebuild test-without-building "${COMMON_ARGS[@]}" "${SIGNING_OVERRIDES[@]}" || xcodebuild_status=$?
else
  echo "Running build+test (incremental against $DERIVED_DATA_PATH when possible)."
  xcodebuild test "${COMMON_ARGS[@]}" "${SIGNING_OVERRIDES[@]}" || xcodebuild_status=$?
fi

echo "Result bundle: $RESULT_BUNDLE"
if [[ "$xcodebuild_status" -ne 0 ]]; then
  echo "xcodebuild exited $xcodebuild_status; continuing to extract evidence from the result bundle."
fi

if [[ ! -d "$RESULT_BUNDLE" ]]; then
  echo "No result bundle was written (xcodebuild likely failed before tests ran); nothing to summarize." >&2
  exit "$xcodebuild_status"
fi

attachments_dir="${RESULT_BUNDLE%.xcresult}.attachments"
rm -rf "$attachments_dir"
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$attachments_dir"
echo "Attachments exported to: $attachments_dir"

issues_path="${RESULT_BUNDLE%.xcresult}.issues.json"
xcrun xcresulttool get test-results tests --path "$RESULT_BUNDLE" |
  python3 "$ROOT_DIR/scripts/ios/chaos-issues-from-xcresult.py" \
    --attachments-dir "$attachments_dir" \
    --output "$issues_path" \
    --result-bundle "$RESULT_BUNDLE"

echo "Issues summary: $issues_path"
cat "$issues_path"

exit "$xcodebuild_status"
