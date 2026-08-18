# App Store listing readiness (bounded) — 2026-08-13

Related: JOV-4586 (do not treat this note as completing the storefront epic), JOV-2855.

This is a listing-truth pass against `packages/product-registry` and Fastlane outputs. It is not App Store Connect submission proof, screenshot capture proof, or IAP merchandising completion.

## Current main / ASC receipts (read-only)

- Repo main at audit start: `5486bb7e249aaedd01ce9073367ea19f99fd2839`
- Last known App Store Connect accepted version from the 2026-08-09 closeout: `1.2.0`, build `20260809095740` at 2026-08-09T10:08:03Z
- Last successful TestFlight tag around then: `ios-v1.2.0-testflight.20260809093119` (PR #770, run 31305345052)
- Run 31306434865 cancelled at 60 minutes waiting on processing; do not claim Production Testers availability
- Physical-device login/onboarding: no receipt from this cloud VM

## Copy vs canonical product truth

Source: `packages/product-registry/src/products/logyourbody.mjs` and `packages/product-registry/src/storefronts/logyourbody.mjs`.

| Field | Before this pass | After this pass | Notes |
| --- | --- | --- | --- |
| Name | LogYourBody | unchanged | 11 chars; limit 30 |
| Subtitle | Weight and body metrics | Know if the work is working. | 29 chars; registry slogan / lead message |
| Keywords | progress,photos,…recomposition | unchanged | 100-byte budget; no name/subtitle duplicates |
| Promotional text | private photo-first timeline | unchanged | No medical or before/after claims |
| Description | “swipeable body timeline” | “private, time-weighted body timeline” | Matches JOV-2855 scrubber contract, not a thumbnail strip |
| What’s New | “Photo-first MVP release…” | Current paid timeline + restore/export/deletion | Removes stale MVP framing |
| URLs | privacy / support / marketing | unchanged | Match registry links |
| Chat | not listed | still not listed | LYB-5 is Done as a peer tab, but chat is not `marketing: true` |

Not claimed in listing copy (correct): food logging, workout tracking, Watch app, iPad-specific layout, GLP-1, medical advice, fabricated social proof.

## Screenshots

Tracked files today:

- `apps/ios/fastlane/screenshots/en-US/01_APP_IPHONE_65.png` — 1242×2688 RGB, no alpha (6.5-inch class)
- `apps/ios/fastlane/screenshots/en-US/01_IPAD_PRO_3GEN_129.png` — 2048×2732 RGB, no alpha

Gaps (do not invent captures):

- Preferred 6.9-inch 1320×2868 set is missing
- Only one iPhone frame; storefront hypothesis asks for seven narrative frames
- `screenshotSets[0].status` is `hypothesis`; `creative.approvedDirection` is null
- Directory is gitignored but these two PNGs are tracked; CI/local checkouts can drift
- No deterministic `StorefrontDemoMode` / capture harness on this Linux VM, so no new real-app screenshots were generated

## Privacy / IAP merchandising

- Privacy URL is present and matches the registry
- Fastlane `submit_app_store` still requires `paywall_testflight_verified=true` before review submission — do not weaken
- Product IDs in the registry (`com.logyourbody.app.pro1.monthly.3daytrial` / `annual`) are the merchandising source of truth; this pass did not change prices or invent subscription screenshots
- In-app purchase App Store Connect merchandising images/copy were not audited in ASC (no ASC write from this VM)

## What this pass does not finish (JOV-4586 remainder)

Phase 0 research packet, capture harness, compositor, 6.9-inch real UI set, Custom Product Pages, Product Page Optimization, and analytics ingestion remain out of scope.
