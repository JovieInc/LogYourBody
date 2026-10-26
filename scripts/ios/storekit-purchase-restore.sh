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
STARTED_AT="$(date +%s)"
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
    echo "::error title=StoreKit failure signature::restore-found-no-entitlement: purchase succeeded but StoreKit state was empty at restore (see STOREKIT_STATE_DIAG)"
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
  DESTINATION=$(SCHEME=LogYourBodyTiers bash ../../scripts/ios/resolve-simulator-destination.sh)
  echo "$DESTINATION" > "$RESULTS/destination.txt"
  xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBodyTiers \
    -testPlan StoreKit -configuration Debug -destination "$DESTINATION" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -enableCodeCoverage YES -resultBundlePath "$RESULTS/storekit.xcresult" \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO test
) 2>&1 | tee "$RESULTS/storekit.log"
git diff HEAD --binary > "$RESULTS/source-working-tree.patch"
[[ ! -s "$RESULTS/source-working-tree.patch" ]] || { echo "StoreKit build modified source" >&2; exit 65; }

python3 scripts/ios/launch-quality-evidence.py --bundle "$RESULTS/storekit.xcresult" \
  --started-at "$STARTED_AT" --export-coverage \
  --expected-test 'StoreKitPurchaseRestoreTests/testAnnualTrialPurchaseRestoreExpiration()' \
  --expected-test 'StoreKitPurchaseRestoreTests/testMonthlyTrialPurchaseRestoreExpiration()' \
  --expected-test 'StoreKitPurchaseRestoreTests/testAnnualTrialPurchaseRestoreRefund()' \
  --expected-test 'StoreKitPurchaseRestoreTests/testMonthlyTrialPurchaseRestoreRefund()'

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo '## StoreKit configuration purchase and restore'
    echo "Source: $(git rev-parse HEAD)"
    echo '- Annual and monthly pro1: product load, 3-day introductory trial, app access, restore, expiration and refund passed.'
    echo '- Receipts: storekit.xcresult, storekit.evidence.json, storekit.coverage.json and source-revision.txt.'
    echo '- Scope: local StoreKit plus the app billing port; hosted RevenueCat and the installed TestFlight build remain unverified.'
    echo "Run: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
  } >> "$GITHUB_STEP_SUMMARY"
fi
