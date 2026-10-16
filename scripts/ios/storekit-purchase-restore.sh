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
trap 'git -C "$ROOT_DIR" diff HEAD --binary > "$RESULTS/source-working-tree.patch"' EXIT

set +e
(
  set -e
  cd apps/ios
  DESTINATION=$(SCHEME=LogYourBodyTiers bash ../../scripts/ios/resolve-simulator-destination.sh)
  echo "$DESTINATION" > "$RESULTS/destination.txt"
  xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBodyTiers \
    -testPlan StoreKit -configuration Debug -destination "$DESTINATION" \
    -only-testing:LogYourBodyTests/StoreKitPurchaseRestoreTests \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -enableCodeCoverage YES -resultBundlePath "$RESULTS/storekit.xcresult" \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO test
) 2>&1 | tee "$RESULTS/storekit.log"
STATUS=${PIPESTATUS[0]}
set -e
git diff HEAD --binary > "$RESULTS/source-working-tree.patch"
[[ "$STATUS" -eq 0 ]] || exit "$STATUS"
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
    echo '- Annual and monthly pro1: product load, 3-day free trial, entitlement, restore, expiration, and refund passed.'
    echo '- Receipts: storekit.xcresult, storekit.evidence.json, storekit.coverage.json, and source-revision.txt.'
    echo '- Scope: local StoreKit plus the app billing port. Hosted RevenueCat and the installed TestFlight build stay unverified.'
    echo "Run: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
  } >> "$GITHUB_STEP_SUMMARY"
fi
