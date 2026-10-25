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

StoreKit has one shared test environment. The dedicated `StoreKit` test plan and
runner disable parallel execution, reset transactions/settings between cases,
and use real-time subscription dates with explicit expiration/refund. Unit
excludes this new simulator integration suite; its other selectors and coverage
floors are unchanged.

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

- `storekit.xcresult` and `storekit.log`
- `storekit.evidence.json` and `storekit.coverage.json` on successful validation
- `source-revision.txt`, before/after source patches, and `destination.txt`

For LYB-199 closeout, select a successful **main-branch** CI run whose source
revision is the latest TestFlight-uploading Release Loop revision or a
descendant. Check the four passing case identifiers in the receipt and post
that run's link with the source revision and artifact name. A PR or merge-group
run, a merge alone, or this document is not runtime acceptance evidence. The
receipt deliberately leaves live-provider and exact deployed-build claims as
`not_verified`.
