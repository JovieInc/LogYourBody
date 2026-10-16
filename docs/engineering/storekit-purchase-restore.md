# StoreKit purchase and restore evidence

CI's **iOS StoreKit Purchase and Restore** job runs on every `main` push, including commits whose Unit lane was already verified by the merge queue. It also runs for pull requests and merge groups that change iOS inputs. CI Summary requires the job to succeed whenever it is selected. The job does not upload a build, sign with a distribution identity, read credentials, or call App Store Connect.

`StoreKitPurchaseRestoreTests` loads `apps/ios/LogYourBody.storekit` through `SKTestSession` on a simulator. Four cases cover both pro1 subscriptions:

- `testAnnualTrialPurchaseRestoreExpiration`
- `testMonthlyTrialPurchaseRestoreExpiration`
- `testAnnualTrialPurchaseRestoreRefund`
- `testMonthlyTrialPurchaseRestoreRefund`

Each case loads both product IDs, checks introductory-offer eligibility and the free three-day period, purchases through the app's package action, and checks the verified Xcode trial transaction plus the published and cached entitlement. It then clears app-side access, restores, and requires the entitlement to return. Expiration or refund must remove that access, and a later restore must not bring it back.

The purchase adapter exists only in the test target and derives billing snapshots from verified StoreKit transactions. `RevenueCatManager` purchase, restore, and entitlement caching run unchanged. This is local StoreKit configuration evidence. It does not verify `LiveRevenueCatPurchasesClient`, RevenueCat's hosted receipt validation, App Store sandbox accounts, or the installed TestFlight binary.

Unit keeps its existing selectors and coverage floors. The new class is skipped there because StoreKit testing has one shared session and its own required job. The StoreKit plan disables parallel execution.

On a Mac, from a clean checkout:

```bash
pnpm ios:bootstrap-local-config
bash scripts/ios/storekit-purchase-restore.sh
```

The runner refuses a dirty tree, propagates xcodebuild failures, and requires all four XCTest identifiers to pass. Skipped, missing, or duplicate required cases fail. CI uploads `ios-storekit-<commit>-<attempt>` on success and failure.

A passing **main-branch** CI run is the acceptance receipt. Its source revision must be the latest TestFlight-uploading Release Loop revision or a descendant. A pull-request run, a merge-group run, or this document is not that receipt.
