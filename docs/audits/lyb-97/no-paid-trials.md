# LYB-97 audit: are the Pro intro offers free trials or paid ones?

Date: 2026-10-03. Base: `main` at `d901d33d0` (`d901d33d0c19f1d7f07c45c381575967bf865846`).

This is a read-only audit. No paywall, product, metadata, StoreKit, or App Store Connect change was made. Any trial change waits until after the 1.2.0 submit and Tim's decision, because it conflicts with the 3-day trials in LYB-33.

## Answer

Both current products have a **3-day free introductory trial**. Neither checked-in source configures a paid introductory offer (Apple pay as you go, or pay up front).

| Plan | Product ID | Intro offer | Evidence |
| --- | --- | --- | --- |
| Monthly Pro | `com.logyourbody.app.pro1.monthly.3daytrial` | Free trial, 3 days, then the subscription renews at the monthly price | `apps/ios/LogYourBody.storekit` `introductoryOffer.paymentMode` = `free`, `subscriptionPeriod` = `P3D`, `numberOfPeriods` = `1`. Renewal `displayPrice` = `9.99`, `recurringSubscriptionPeriod` = `P1M`. |
| Annual Pro | `com.logyourbody.app.pro1.annual.3daytrial` | Free trial, 3 days, then the subscription renews at the annual price | Same file. `paymentMode` = `free`, `subscriptionPeriod` = `P3D`, `numberOfPeriods` = `1`. Renewal `displayPrice` = `69.99`, `recurringSubscriptionPeriod` = `P1Y`. |

Apple's StoreKit configuration uses `paymentMode` `free` for a free trial. A paid intro would be `payAsYouGo` or `payUpFront`, usually with an intro price. Those modes are absent from `LogYourBody.storekit`. `adHocOffers` and `codeOffers` are empty arrays on both subscriptions. There are no other products in that file (`products` and `nonRenewingSubscriptions` are empty).

The product-registry field `plans[0].trialDays` is `3`. It records length only. It does not record free versus paid. The product IDs contain `3daytrial`, which names a trial and does not say whether the trial is free.

Live App Store Connect introductory offers were **not** read. This environment has no App Store Connect API key. The public iTunes lookup for app id `6755209876` returned `resultCount: 0`, so the public listing does not confirm the offer either. RevenueCat's live offering was not read (`REVENUE_CAT_PUBLIC_KEY` is unset). The release verifier `.github/scripts/verify-app-store-subscriptions.rb` checks that these two product IDs exist and that `state` is `READY_TO_SUBMIT` or `APPROVED`. It requests `fields[subscriptions]=name,productId,state` and does not read `introductoryOffers` or `offerMode`.

Until someone reads App Store Connect `GET /v1/subscriptions/{id}/introductoryOffers` (`offerMode`, `duration`, `numberOfPeriods`) for each product, the live store can still differ from the local StoreKit file.

## What "no paid trials" would change

Two different decisions fit the phrase. They do not touch the same fields. LYB-97's issue body was not readable here (see self-review), so this audit does not pick one.

### A. Forbid paid introductory offers

Paid means Apple `PAY_AS_YOU_GO` or `PAY_UP_FRONT`. Free means `FREE_TRIAL` / StoreKit `paymentMode` `free`.

On the checked-in StoreKit file, this decision is already met. A later enforcement pass would still add a guard, because nothing in CI reads offer mode today.

Fields a guard or a correction would use:

| File | Field |
| --- | --- |
| `apps/ios/LogYourBody.storekit` | `subscriptionGroups[0].subscriptions[].introductoryOffer.paymentMode` must stay `free`. A paid offer would also set an intro price and use `payAsYouGo` or `payUpFront`. |
| App Store Connect (not in git) | Each subscription's introductory offer `offerMode`. Must be `FREE_TRIAL`. Duration `THREE_DAYS` (API) matching local `P3D`. |
| `.github/scripts/verify-app-store-subscriptions.rb` | Today: product id and `state` only. A guard would also require `introductoryOffers.offerMode == FREE_TRIAL` for `com.logyourbody.app.pro1.monthly.3daytrial` and `com.logyourbody.app.pro1.annual.3daytrial`. |

The iOS paywall already treats a non-free intro as "no trial copy": `getTrialDurationText` returns text only when `introductoryDiscount.paymentMode == .freeTrial`. Pay as you go and pay up front fall through to purchase button title `Subscribe` and no trial line. That hides a paid intro in the UI. It does not stop StoreKit from charging it.

Do not start this while 1.2.0 is in submission. Confirming or editing introductory offers in App Store Connect is an App Store change.

### B. Remove the 3-day trial (the change that conflicts with LYB-33)

This is the decision that changes what 1.2.0 sells: no intro period, customer is billed at the renewal price from the start. It conflicts with LYB-33's 3-day trials and with open PR [#1197](https://github.com/JovieInc/LogYourBody/pull/1197), which sets 1.2.0 What's New to: "LogYourBody Pro is a monthly or annual subscription, and each plan includes a 3-day free trial."

On `main` today, What's New does **not** mention a trial. The sentence above exists only on that open PR.

Exact files and fields for that later change:

**Source of truth**

| File | Field | Current value |
| --- | --- | --- |
| `packages/product-registry/src/products/logyourbody.mjs` | `plans[0].trialDays` | `3` |
| same | `plans[0].pricing.monthly.productId` | `com.logyourbody.app.pro1.monthly.3daytrial` |
| same | `plans[0].pricing.monthly.amount` | `9.99` |
| same | `plans[0].pricing.monthly.packageId` | `$rc_monthly` |
| same | `plans[0].pricing.annual.productId` | `com.logyourbody.app.pro1.annual.3daytrial` |
| same | `plans[0].pricing.annual.amount` | `69.99` |
| same | `plans[0].pricing.annual.packageId` | `$rc_annual` |
| same | `plans[0].pricing.source` | `app-store-connect` |
| `packages/product-registry/src/types.ts` | `ProductPlan.trialDays` | `number` (length only; no offer-mode field) |

Generated from that registry. Do not hand-edit. Regenerate with `pnpm product:generate`:

| File | Field |
| --- | --- |
| `apps/ios/LogYourBody/GeneratedProductRegistry.swift` | `ProductRegistry.Paywall.trialDays`, `monthlyProductID`, `annualProductID`, `monthlyPackageID`, `annualPackageID`, reference prices |
| `docs/product/product-registry.generated.md` | Plan line `Pro: Premium; 3-day trial; USD 9.99/month or USD 69.99/year.` |
| `packages/product-registry/scripts/generate.mjs` | Emits `trialDays` and the `N-day trial` sentence. The generator does not emit the word `free`. |

**StoreKit local config**

| File | Field |
| --- | --- |
| `apps/ios/LogYourBody.storekit` | Monthly and annual `introductoryOffer` (`paymentMode`, `subscriptionPeriod`, `numberOfPeriods`, `internalID` `MONTHLYTRIAL` / `ANNUALTRIAL`) |
| same | `productID`, `referenceName` (`LogYourBody Pro Monthly (3-Day Trial)`, `LogYourBody Pro Annual (3-Day Trial)`) |
| same | `localizations[].description` (`… with 3-day free trial`) and `displayName` |

**Paywall copy (driven by StoreKit, not by `trialDays`)**

| File | Field | Current behavior |
| --- | --- | --- |
| `apps/ios/LogYourBody/Services/RevenueCatManager+Part01.swift` | `getTrialDurationText` | Returns `"\(value) \(unit) free"` only for `.freeTrial`. For 3 days the unit string is `"day"` (`SubscriptionPeriod.Unit.description` in `RevenueCatManager.swift`), so the live line is `3 day free`. |
| same | `makePaywallPackageDisplay.purchaseButtonTitle` | `Start trial` when `trialText` is set, otherwise `Subscribe` |
| same | DEBUG `applyCachedPaywallOfferingUITestFixture` | Hard-codes `trialText: "3 days free"` for both product IDs |
| `apps/ios/LogYourBody/Views/PaywallView.swift` | `pricingOption` | Renders `package.trialText` when there is no savings badge (lines around the `trialText` branch) |
| same | `purchaseButton` | Renders `package.purchaseButtonTitle` |
| `apps/ios/LogYourBody/Services/RevenueCatManager.swift` | `PaywallPackageDisplay.trialText`, `purchaseButtonTitle` | Display model only. No offer-mode enum. |
| `packages/product-registry/src/products/logyourbody.mjs` | `messages.paywall.title`, `subtitle`, `valueProposition` | No trial sentence. Paywall trial copy is not in the registry messages. |

**Release notes and review notes**

| File | Field | On `main` now |
| --- | --- | --- |
| `apps/ios/fastlane/metadata/en-US/release_notes.txt` | whole file | No trial mention. Describes the timeline, logging, Health, Stats, restore, export, and account deletion. |
| `packages/product-registry/src/storefronts/logyourbody.mjs` | `releaseNotes` | Same sentence as the metadata file. |
| `apps/ios/fastlane/storefront-manifest.generated.json` | `releaseNotes` | Generated from the storefront registry. |
| `apps/ios/fastlane/metadata/en-US/description.txt`, `promotional_text.txt`, `subtitle.txt`, `keywords.txt`, `name.txt` | listing copy | No trial sentence. Description says "Keep access managed through LogYourBody Pro". |
| `apps/ios/fastlane/Fastfile.release` | default `APP_REVIEW_NOTES` | Tells review to tap `Start trial` and says subscriptions "include a 3-day trial". |

PR #1197 changes `releaseNotes` in the storefront registry, the generated manifest, and `release_notes.txt` to the 3-day free trial sentence. That PR is the in-flight 1.2.0 What's New edit. Leave it alone for this audit.

**Checks that pin the product IDs**

| File | What it pins |
| --- | --- |
| `.github/scripts/verify-app-store-subscriptions.rb` | `DEFAULT_REQUIRED_PRODUCTS` lists both `pro1` `3daytrial` IDs |
| `apps/ios/Scripts/verify_revenuecat_offerings.sh` | `REVENUECAT_REQUIRED_PACKAGES` default `$rc_annual:…annual.3daytrial,$rc_monthly:…monthly.3daytrial` |
| `apps/ios/docs/development/RELEASE_CHECKLIST.md` | Same RevenueCat package mapping |

**Tests and fixtures that would fail if the intro or the IDs change**

| File | Assertion |
| --- | --- |
| `apps/ios/LogYourBodyTests/CachedPaywallOfferingDisplayTests.swift` | `trialText` `3 days free` on both product IDs |
| `apps/ios/LogYourBodyTests/RevenueCatProductConfigurationTests.swift` | Both `pro1` `3daytrial` product IDs |
| `apps/ios/LogYourBodyTests/RevenueCatPurchaseRestoreFlowTests.swift` | Annual `pro1` product ID |
| `apps/web/src/app/__tests__/launch-landing.test.tsx` | Pricing line contains `3-day free trial` |

**Web copy that already says the trial is free**

The registry does not say `free`. These call sites add it:

| File | Field |
| --- | --- |
| `apps/web/src/constants/app.ts` | `trialLengthDays` from `trialDays`; `trialLengthText` is `` `${trialDays}-day free trial` `` |
| `apps/web/src/app/launch-landing-copy.ts` | `pricingLine` uses `` `${trialDays}-day free trial, then …` `` |
| `apps/web/src/components/LandingPageConversionSections.tsx` | `{trialLengthDays} days free. Then $…`; hardcoded `3-day free trial`; `No credit card required` |
| `apps/web/src/components/Prefooter.tsx` | `APP_CONFIG.trialLengthText` |
| `apps/web/src/components/LandingPage.tsx` | `No credit card required` |
| `apps/web/src/app/about/page.tsx` | Button `Start Free Trial`; line `No credit card • 3-day trial • Cancel anytime` |
| `apps/web/src/app/settings/subscription/page.tsx` | Local mock: `days left in your free trial` using `trialLengthDays` |

**Docs that state the offer, and would go stale**

| File | Statement |
| --- | --- |
| `docs/product/outcome-map.md` | Table rows: intro offer `3 days free, then monthly renewal` / `3 days free, then annual renewal` |
| `docs/design/app-walk-staging-2026-09-28.md` | Paywall has the three-day trial |
| `docs/RELEASE_APP_STORE.md` | 1.2.0 submission runbook. Purchase path assumes the current products. |
| `docs/product-development-roadmap.md` | Activation includes a paywall/free trial decision |

Archive docs under `docs/archive/` still name the older IDs `com.logyourbody.app.pro.monthly.3daytrial` and `com.logyourbody.app.pro.annual.3daytrial` (no `pro1`). Those are not the current registry IDs. Do not revive them as part of a trial change.

**Outside the repo, required for either decision that changes what customers are billed**

- App Store Connect introductory offer on each subscription (`offerMode`, duration, number of periods). Removing or replacing an intro on a product that has already been submitted may require a new product ID. The current IDs contain `3daytrial`, so a no-trial product should not keep that ID.
- RevenueCat current iOS offering packages `$rc_monthly` and `$rc_annual` pointed at those product IDs.
- App Review notes if the button stops saying `Start trial`.

Pushing `apps/ios/**` to `main` starts the TestFlight workflow and changes the 1.2.0 build Tim is submitting. That is why this audit does not edit those files.

## Paywall and release notes, as read

`PaywallView` has no hard-coded "free trial" or "paid trial" string. It shows StoreKit-derived `trialText` and `purchaseButtonTitle`.

`messages.paywall` in the product registry is:

- title: `Keep the answer current.`
- subtitle: `Your first score is ready. Pro keeps it updated as new measurements and photos arrive.`
- valueProposition: `Track weight, body fat, FFMI, and honest visual change with one private history.`

`apps/ios/fastlane/metadata/en-US/release_notes.txt` on this commit does not mention a trial, a price, or an intro offer.

## App Store Connect

Not read.

- No `APP_STORE_CONNECT_API_KEY`, key id, issuer, or `APP_STORE_CONNECT_API_KEY_PATH` in this environment.
- Doppler token is unset. Secrets were not fetched.
- `https://itunes.apple.com/lookup?id=6755209876&country=us` returned `resultCount: 0`.
- Linear pages [LYB-97](https://linear.app/jovie/issue/LYB-97) and [LYB-33](https://linear.app/jovie/issue/LYB-33) exist. Their bodies did not load here (Linear needs Cursor desktop authentication). GitHub search in `JovieInc/LogYourBody` returned no issues with those IDs.

## Self-review

### 1. Gaps in the ask

- The words "paid trial" are not defined in a source this audit could open. Apple has three intro modes. A free trial still requires a payment method and then auto-renews. Someone may mean "no pay-as-you-go or pay-up-front intro" (already true in StoreKit) or "remove the 3-day free trial" (the LYB-33 conflict). Tim has to pick one.
- Live App Store Connect `offerMode` is unverified. The local StoreKit file can drift from the subscription Apple will review.
- RevenueCat's current offering intro price was not verified in this run.
- LYB-97 and LYB-33 issue text, and any meeting note, were unavailable. Granola had no matching notes in the last 30 days.
- `trialDays` does not store offer mode, so a registry read alone cannot prove free versus paid. The StoreKit `paymentMode` is what proves it in git.

### 2. Conflicts with in-flight work

- LYB-33's 3-day trials are the 1.2.0 products. Changing them before submit changes the build under review.
- Open PR [#1197](https://github.com/JovieInc/LogYourBody/pull/1197) (`cursor/testflight-whats-new-a4e6`) edits `apps/ios/fastlane/metadata/en-US/release_notes.txt`, `apps/ios/fastlane/storefront-manifest.generated.json`, and `packages/product-registry/src/storefronts/logyourbody.mjs` to say each plan includes a 3-day free trial. That is the What's New text for the submit. This audit does not edit those lines.
- Open PR titles matching paywall, trial, registry, StoreKit, or subscription returned only #1197. That is a title scan, not a diff of every open PR. `main` at this commit still has the free-trial StoreKit config above.
- Any follow-up that touches `apps/ios/**` before 1.2.0 is submitted will trigger TestFlight via the iOS workflows.

### 3. Adjacent issues

- Web marketing says "No credit card required" (`LandingPageConversionSections.tsx`, `LandingPage.tsx`, `about/page.tsx`). An App Store free trial still asks for a payment method. That line is a separate copy bug from offer mode.
- The paywall formats a 3-day free trial as `3 day free`. UI-test fixtures and the web say `3 days free`.
- Subscription CI never asserts `offerMode`, so a paid intro could ship while product IDs and states still pass.
- `docs/archive/` still documents `com.logyourbody.app.pro.*.3daytrial` without `pro1`. Current IDs use `pro1`.

## Proposed follow-up issue

No implementation issue exists yet. Do not file it until 1.2.0 is submitted. Suggested Linear issue (team LYB):

**Title:** After 1.2.0 submission, apply Tim's intro-offer decision to both Pro products

**Blocked by:** 1.2.0 submitted, and Tim's choice between (A) and (B) below.

**Context:** LYB-97 audit (`docs/audits/lyb-97/no-paid-trials.md`) found both `com.logyourbody.app.pro1.monthly.3daytrial` and `com.logyourbody.app.pro1.annual.3daytrial` configured as 3-day free trials in `LogYourBody.storekit` (`paymentMode: free`, `P3D`, one period). That conflicts with changing trials during the 1.2.0 submit (LYB-33, PR #1197).

**If Tim chooses A (no paid intro; keep the free trial):** Read App Store Connect introductory offers for both products. If `offerMode` is already `FREE_TRIAL` for three days, make no customer-facing change. Add a check in `.github/scripts/verify-app-store-subscriptions.rb` that `offerMode` is `FREE_TRIAL` and the duration is three days. Leave product IDs in place.

**If Tim chooses B (remove the 3-day trial):** This is the change. After the 1.2.0 submit, replace or clear the introductory offer in App Store Connect, point RevenueCat `$rc_monthly` and `$rc_annual` at the products customers should buy, and update every field in the "Remove the 3-day trial" tables in the audit. Set `trialDays` to `0` or remove it. Paywall button becomes `Subscribe`. Drop "free trial" and "No credit card required" from web pricing copy. Update What's New and `APP_REVIEW_NOTES` only after the binary and the App Store products match. Expect new product IDs if Apple will not remove the intro from the existing `3daytrial` products. Do not push `apps/ios/**` until Tim says the 1.2.0 submit no longer depends on the current build.

**Out of scope for that issue:** editing the 1.2.0 binary or metadata that is already queued for review.
