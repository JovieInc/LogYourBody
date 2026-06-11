# JOV-2941 RevenueCat Product ID Audit

Date: 2026-06-10

## Autoplan Decision

Decision: close as a guarded configuration audit, not a product ID rename.

The Linear issue asserted that StoreKit used `pro1` while the RevenueCat dashboard expected `pro`. Current release evidence says the opposite: `pro1` is the verified paid-MVP product namespace. Renaming local StoreKit products to `pro` would contradict the active release preflight and could break the paywall.

## Current Source Of Truth

- StoreKit config: `apps/ios/LogYourBody.storekit`
  - `com.logyourbody.app.pro1.annual.3daytrial`
  - `com.logyourbody.app.pro1.monthly.3daytrial`
- Release preflight: `apps/ios/Scripts/verify_revenuecat_offerings.sh`
  - requires `$rc_annual:com.logyourbody.app.pro1.annual.3daytrial`
  - requires `$rc_monthly:com.logyourbody.app.pro1.monthly.3daytrial`
- Provisioning note: `docs/revenuecat-agentmail-provisioning.md`
  - records the RevenueCat current offering `default` returning the same two `pro1` product identifiers.
- Release checklist: `apps/ios/docs/development/RELEASE_CHECKLIST.md`
  - requires the release workflow to verify those same two `pro1` product identifiers.

Older root-level RevenueCat fix documents still mention `com.logyourbody.app.pro.*`; they are treated as historical evidence from an earlier setup pass, not the current launch configuration.

## Guardrail Added

`RevenueCatProductConfigurationTests.testStoreKitProductIdentifiersMatchReleasePreflight` now parses `LogYourBody.storekit` and checks that the annual/monthly product IDs exactly match the release preflight script. It also rejects the stale `.pro.` namespace in the StoreKit products.

## Validation

Environment:

- Simulator: iPhone 17, iOS 26.5, id `7A8ECED1-02CF-40F6-BD43-0A2F127D6A74`.

Commands:

- `rg -n "\\.pro\\." apps/ios/LogYourBody.storekit apps/ios/Scripts/verify_revenuecat_offerings.sh docs/revenuecat-agentmail-provisioning.md apps/ios/docs/development/RELEASE_CHECKLIST.md || true`
  - Result: no stale `.pro.` identifiers found in the active StoreKit/preflight/checklist source set.
- `rg -n "pro1\\." apps/ios/LogYourBody.storekit apps/ios/Scripts/verify_revenuecat_offerings.sh docs/revenuecat-agentmail-provisioning.md apps/ios/docs/development/RELEASE_CHECKLIST.md`
  - Result: all active sources point at the same annual/monthly `pro1` identifiers.
- `swiftlint lint --strict`
  - Result: passed; 0 violations in 256 files.
- `xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=7A8ECED1-02CF-40F6-BD43-0A2F127D6A74' -only-testing:LogYourBodyTests/RevenueCatProductConfigurationTests test`
  - Result: passed; `RevenueCatProductConfigurationTests.testStoreKitProductIdentifiersMatchReleasePreflight()` completed in 0.005 seconds.
  - Result bundle: `/Users/timwhite/Library/Developer/Xcode/DerivedData/LogYourBody-anevozwzdzcspsguqxcsynbxjfwk/Logs/Test/Test-LogYourBody-2026.06.10_18-57-56--0700.xcresult`.
- `xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=7A8ECED1-02CF-40F6-BD43-0A2F127D6A74' build-for-testing`
  - Result: passed; `** TEST BUILD SUCCEEDED **`.
- `set -a; source /Users/timwhite/.codex/secrets/logyourbody-revenuecat-agentmail.env; set +a; REVENUE_CAT_PUBLIC_KEY="$REVENUECAT_APP_STORE_PUBLIC_SDK_KEY" apps/ios/Scripts/verify_revenuecat_offerings.sh`
  - Result: passed; RevenueCat current offering `default` includes `$rc_annual:com.logyourbody.app.pro1.annual.3daytrial` and `$rc_monthly:com.logyourbody.app.pro1.monthly.3daytrial`.
  - Note: the private local env file stores the App Store public SDK key as `REVENUECAT_APP_STORE_PUBLIC_SDK_KEY`; the release workflow supplies the same value through `REVENUE_CAT_PUBLIC_KEY`.
- `pnpm lint`
  - Result: passed; cached web/package lint tasks replayed. Existing warnings included local Node `v22.22.1` versus expected `20.x`, deprecated `next lint`, stale `.eslintignore`, and unused eslint-disable comments in `apps/web/src/app/signin/__tests__/page.test.tsx`.
- `pnpm typecheck`
  - Result: passed; cached web/package typecheck tasks replayed. Existing warning: local Node `v22.22.1` versus expected `20.x`.
- `pnpm test:ci`
  - Result: passed; 8 turbo tasks successful. Existing cached output included Node engine warnings, Next build warnings for `read-excel-file/web`, expected noisy PDF/parser test logging, and design-token contrast warnings that the validator reports without failing.

## Out Of Scope

- No RevenueCat dashboard, App Store Connect, product, package, price, entitlement, or billing metadata changes.
- No paywall UI or purchase flow changes.
- No production auth, billing, or privacy bypass.

Done when the guard test passes locally, the PR lands through the normal gates, and Linear records that `pro1` is the current verified configuration unless a fresh RevenueCat/App Store Connect audit proves otherwise.
