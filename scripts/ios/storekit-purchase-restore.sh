#!/usr/bin/env bash
# Secret-free simulator evidence. Never uploads a build or contacts App Store Connect.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
RESULTS="${STOREKIT_RESULTS:-$ROOT_DIR/apps/ios/test_results/storekit/${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}}"
[[ ! -e "$RESULTS" ]] || { echo "Refusing stale StoreKit output: $RESULTS" >&2; exit 65; }
mkdir -p "$RESULTS"
RESULTS="$(cd "$RESULTS" && pwd)"
git rev-parse HEAD > "$RESULTS/source-revision.txt"
git diff HEAD --binary > "$RESULTS/source-before-tests.patch"
[[ ! -s "$RESULTS/source-before-tests.patch" ]] || { echo "Refusing dirty StoreKit input" >&2; exit 65; }
# Capture source changes on success and failure, including build-time generators.
# Surface any bounded StoreKit warm-up retries (LYB-231) as visible warnings; never hides a test failure.
emit_warmup_warnings() {
  local n
  n="$(grep -c 'STOREKIT_WARMUP_RETRY' "$RESULTS/storekit.log" 2>/dev/null || true)"
  if [[ "${n:-0}" -gt 0 ]]; then
    echo "::warning title=StoreKit warm-up retried::StoreKit test-session warm-up logged $n retry/exhaustion event(s); see storekit.log"
  fi
}
# On failure, name the known StoreKit failure signature (LYB-231) so a recurrence is diagnosable from the job
# annotations alone. Annotation only: it never changes the exit status or retries anything.
classify_failure() {
  local log="$RESULTS/storekit.log"
  [[ -f "$log" ]] || return 0
  if grep -q -- '-67818' "$log"; then
    echo "::error title=StoreKit failure signature::certificate-expired (-67818 present in log; a warm-up-absorbed one also matches, check STOREKIT_WARMUP_RETRY)"
  fi
  if grep -q 'No active subscriptions found' "$log"; then
    echo "::error title=StoreKit failure signature::restore-found-no-entitlement: restore returned no active entitlement (see STOREKIT_STATE_DIAG; transaction count alone does not prove access)"
  fi
  grep -h 'STOREKIT_STATE_DIAG' "$log" | sed 's/^.*STOREKIT_STATE_DIAG/::notice::STOREKIT_STATE_DIAG/' || true
}
finish() {
  local status=$?
  git -C "$ROOT_DIR" diff HEAD --binary > "$RESULTS/source-working-tree.patch"
  emit_warmup_warnings
  if [[ "$status" -ne 0 ]]; then classify_failure; fi
}
trap finish EXIT

(
  cd apps/ios
  SEED_DESTINATION=$(SCHEME=LogYourBodyTiers bash ../../scripts/ios/resolve-simulator-destination.sh)
  SEED_ID="${SEED_DESTINATION##*id=}"
  # Reuse the resolver's compatible device/runtime selection without its data.
  DEVICE_CONFIG=$(xcrun simctl list devices available --json | ruby -rjson -e '
    JSON.parse(STDIN.read).fetch("devices").each do |runtime, devices|
      device = devices.find { |item| item["udid"] == ARGV.fetch(0) }
      next unless device
      puts "#{device.fetch("deviceTypeIdentifier")} #{runtime}"
      exit 0
    end
    abort "Selected simulator is missing from simctl devices"
  ' "$SEED_ID")
  read -r DEVICE_TYPE RUNTIME_ID <<< "$DEVICE_CONFIG"
  xcrun simctl shutdown "$SEED_ID"
  SIMULATOR_ID=""
  cleanup_simulator() {
    if [[ -n "$SIMULATOR_ID" ]]; then
      xcrun simctl shutdown "$SIMULATOR_ID" || true
      xcrun simctl delete "$SIMULATOR_ID"
    fi
  }
  trap cleanup_simulator EXIT
  # StoreKit has one test server per simulator. A serial test plan still lets
  # expiration/refund and cleanup from earlier cases affect a later restore.
  # Give every lifecycle a fresh device and process; never retry a failed case.
  for TEST in testAnnualTrialPurchaseRestoreExpiration testMonthlyTrialPurchaseRestoreExpiration \
              testAnnualTrialPurchaseRestoreRefund testMonthlyTrialPurchaseRestoreRefund; do
    SIMULATOR_ID=$(xcrun simctl create "LYB StoreKit $TEST" "$DEVICE_TYPE" "$RUNTIME_ID")
    xcrun simctl boot "$SIMULATOR_ID"
    xcrun simctl bootstatus "$SIMULATOR_ID" -b
    DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
    echo "$DESTINATION" > "$RESULTS/$TEST.destination.txt"
    CASE_STARTED_AT="$(date +%s)"
    xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBodyTiers \
      -testPlan StoreKit -configuration Debug -destination "$DESTINATION" \
      -only-testing:"LogYourBodyTests/StoreKitPurchaseRestoreTests/$TEST" \
      -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
      -enableCodeCoverage YES -resultBundlePath "$RESULTS/$TEST.xcresult" \
      CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO test
    git -C "$ROOT_DIR" diff HEAD --binary > "$RESULTS/source-working-tree.patch"
    [[ ! -s "$RESULTS/source-working-tree.patch" ]] || { echo "StoreKit build modified source" >&2; exit 65; }
    python3 ../../scripts/ios/launch-quality-evidence.py --bundle "$RESULTS/$TEST.xcresult" \
      --started-at "$CASE_STARTED_AT" --export-coverage \
      --expected-test "StoreKitPurchaseRestoreTests/$TEST()"
    cleanup_simulator
    SIMULATOR_ID=""
  done
) 2>&1 | tee "$RESULTS/storekit.log"
git diff HEAD --binary > "$RESULTS/source-working-tree.patch"
[[ ! -s "$RESULTS/source-working-tree.patch" ]] || { echo "StoreKit build modified source" >&2; exit 65; }

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo '## StoreKit configuration purchase and restore'
    echo "Source: $(git rev-parse HEAD)"
    echo '- Annual and monthly pro1: product load, 3-day introductory trial, app access, restore, expiration and refund passed.'
    echo '- Receipts: one xcresult, evidence.json, coverage.json and destination.txt per lifecycle; shared source-revision.txt and storekit.log.'
    echo '- Scope: local StoreKit plus the app billing port; hosted RevenueCat and the installed TestFlight build remain unverified.'
    echo "Run: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
  } >> "$GITHUB_STEP_SUMMARY"
fi
