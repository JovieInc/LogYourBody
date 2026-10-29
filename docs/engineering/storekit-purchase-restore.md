# StoreKit purchase and restore evidence

CI's **iOS StoreKit Purchase and Restore** job runs on every `main` push,
including commits for which Unit was already verified by the merge queue. It
also gates merge groups that change iOS inputs (not the pull request run: the
queue reruns it on the exact tree that lands). CI Summary
requires this job to succeed when selected. No release, submission or App Store
Connect operation runs in this job, and it requires no credentials.

`StoreKitPurchaseRestoreTests` uses the bundled `apps/ios/LogYourBody.storekit`
with `SKTestSession`. Four named XCTest cases cover annual and monthly pro1
subscriptions separately, each with expiration and refund variants:

- `testAnnualTrialPurchaseRestoreExpiration`
- `testMonthlyTrialPurchaseRestoreExpiration`
- `testAnnualTrialPurchaseRestoreRefund`
- `testMonthlyTrialPurchaseRestoreRefund`

Each case loads both product IDs from StoreKit, checks eligibility and the
free three-day introductory offer, purchases the selected product through the
app's package purchase action, and checks a verified Xcode-environment trial
transaction and the app's published and cached entitlement. It clears app-side
access while retaining StoreKit history, calls the app's restore action, and
checks that access returns. Expiration/refund must then remove published and
cached access; another restore must not resurrect it.

The adapter exists only in the test target and derives billing snapshots from
verified StoreKit transactions. The app's existing `RevenueCatManager`, package
selection, purchase, restore and entitlement/cache consumer execute unchanged.
This provides local StoreKit configuration and in-app entitlement evidence. It
does **not** verify `LiveRevenueCatPurchasesClient`, RevenueCat's hosted product
mapping/receipt validation, App Store sandbox accounts, or the installed signed
TestFlight binary. Preserve the existing live TestFlight submission gate.

StoreKit has one shared test environment per simulator. The runner uses the
existing destination resolver to choose a compatible device type and runtime,
then creates a fresh simulator and test process for each of the four lifecycles.
It shuts down and deletes only the devices it creates, including on failure.
The dedicated `StoreKit` plan still disables parallel execution and uses
real-time dates with explicit expiration/refund. Each case passes the existing
evidence validator before the next starts; a failed case stops the runner
without retry. Unit excludes this simulator suite; its selectors and coverage
floors are unchanged. Run 40300882343 failed the fourth case's restore despite
one transaction before restore; transaction count alone does not prove access.

Cleanup deletes the existing transaction IDs once, then waits for both
`SKTestSession.allTransactions()` and `Transaction.all` to become empty. This
includes expired and refunded history, which is absent from current entitlements.
Setup, teardown and warm-up share this bounded cleanup; a timeout throws before
another purchase can start. No repeated global clear can erase a later purchase.

On a Mac with the repo's Xcode toolchain, from a clean checkout:

```bash
pnpm ios:bootstrap-local-config
bash scripts/ios/storekit-purchase-restore.sh
```

The runner resolves a simulator using the existing repo helper. It refuses stale
output or tracked source changes, propagates build/test failures through `tee`,
and requires all four exact XCTest identifiers to pass through the existing
XCTest evidence validator. Skipped, missing and duplicate required cases fail.
CI always uploads `ios-storekit-<commit>-<attempt>`, including failure receipts:

- `<test-name>.xcresult` and the combined `storekit.log`
- `<test-name>.evidence.json` and `<test-name>.coverage.json` on successful validation
- `source-revision.txt`, before/after source patches, and `<test-name>.destination.txt`

The required runner-routing regressions execute this runner with fake native
tools and the real evidence validator. They reject shared destinations, skipped
or duplicate cases, coverage failures, build/test failures and dirty source,
and verify device cleanup on failures. These are orchestration regressions;
only a passing macOS run establishes native StoreKit behavior.

For LYB-199 closeout, select a successful **main-branch** CI run whose source
revision is the latest TestFlight-uploading Release Loop revision or a
descendant. Check the four passing case identifiers in the receipt and post
that run's link with the source revision and artifact name. A PR or merge-group
run, a merge alone, or this document is not runtime acceptance evidence. The
receipt deliberately leaves live-provider and exact deployed-build claims as
`not_verified`.
