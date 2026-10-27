# Storefront production brief — 2026-10-26

The en-US listing is generated and locally validated. The screenshot campaign is
not ready for upload. This brief records the remaining production work against
the checked-out source; it is not an App Store Connect or conversion receipt.

## Listing changes

The source remains `packages/product-registry/src/storefronts/logyourbody.mjs`.
Run `pnpm product:generate` and `pnpm product:check` from the repository root;
Fastlane reads the generated `apps/ios/fastlane/metadata/en-US/` files.

- The description opens with the product outcome, then explains progress,
  logging, privacy, and Pro in that order. Weight uses pounds or kilograms;
  body fat uses a percentage.
- Pro copy distinguishes eligible trials from guaranteed access, discloses
  monthly/annual subscriptions and renewal, and links the canonical Privacy
  Policy and Terms of Use. The App Store supplies localized pricing and actual
  offer eligibility. The metadata validator now requires these disclosures.
- The keyword field replaces `private` with `weight`: the previous app name,
  subtitle, and keywords omitted the core weight-tracker query entirely. The
  field uses 97 UTF-8 bytes of the 100-byte limit, with no repeated indexed
  words. This corrects supported search-intent coverage; it does not establish
  search volume or ranking lift. Privacy remains prominent in the description.
- The current name, subtitle, promotional text, release notes, and screenshot
  narrative remain in the canonical registry. Unverified claims about
  scientific accuracy and exclusivity were removed from obsolete web metadata
  and the unreferenced legacy feature flyout; the brand guard rejects their
  reintroduction.

The keyword and copy changes still need live metadata readback after deployment.
No locale has been invented and no new subscription price has been set.

## Screenshot production specification

Use the existing seven frame IDs and `captureStateId` values. Copy comes from the
registry so the composition cannot silently diverge from generated metadata.
The following is a concrete composition direction for review, not an approved
creative result or a substitute for real app capture.

| Element          | Production specification                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------------------- |
| Export           | 1320 × 2868 portrait, sRGB PNG, opaque RGB, no alpha                                                                |
| Canvas           | Registry background `#08090A`; no gradients behind product UI                                                       |
| Headline         | Inter SemiBold, 88 px / 96 px, `#F7F8F8`, left aligned at x=96, y=136; maximum three lines                          |
| Supporting copy  | Inter Regular, 38 px / 52 px, `#C5C6CA`, x=96; 32 px below headline; maximum three lines                            |
| Real app capture | Full 1320 × 2868 capture scaled proportionally to 936 × 2034, positioned x=192, y=684; retain all UI and status bar |
| Spacing          | 96 px horizontal copy margins; at least 108 px between supporting copy and capture; 150 px below capture            |
| Accent           | Use the app's actual metric colors inside its capture; no promotional badges or simulated notifications             |
| Typography       | Code-rendered text; no rasterized/generated lettering or synthetic device geometry                                  |
| Review           | Inspect at full resolution and at a 220 px wide search-result thumbnail; headlines must remain legible              |

Do not stretch, retouch, reconstruct, or crop away errors in a capture. If copy
does not fit, revise the registry copy and rerun validation. Do not shrink text
until the frame becomes unreadable. Use approved synthetic demo measurements and
consented photo fixtures; never represent them as a real customer's outcome.

| Order | Capture state            | Required visible proof                                                                                       |
| ----- | ------------------------ | ------------------------------------------------------------------------------------------------------------ |
| 1     | `timeline-overview`      | A populated private timeline with an understandable selected date and corresponding measurements             |
| 2     | `stats-trend`            | A longer-term trend with units and an explicit time range; no claimed improvement inferred from a single day |
| 3     | `timeline-photo-metrics` | A consented photo fixture and measurements belonging to the same selected date                               |
| 4     | `weight-entry`           | The actual weight-entry control, unit, and save action, with a valid demo input                              |
| 5     | `stats-composition`      | Supported composition metrics with source and measured/estimated labels retained                             |
| 6     | `healthkit-context`      | Actual supported Apple Health context; no implication that permission or synchronization always succeeds     |
| 7     | `timeline-private`       | The private timeline itself; no invented encryption, anonymity, or social-proof badges                       |

Frames 1–3 must tell a complete story together: understand progress, see the
trend, connect it to photos. The renderer must use a capture from the named
state, never reuse a convenient screenshot for a different claim.

## Current capture evidence

Only these two Fastlane images are tracked:

- `apps/ios/fastlane/screenshots/en-US/01_APP_IPHONE_65.png`: 1242 × 2688.
- `apps/ios/fastlane/screenshots/en-US/01_IPAD_PRO_3GEN_129.png`: 2048 × 2732.

Visual inspection of the iPhone image shows a body-fat ring, an offline banner,
and lower content partially obscured by the bottom controls. It does not supply
the seven capture states above. The marketing asset copier names its output
`weight-log.png`; that filename is not evidence of a weight-entry screen.
The generated manifest's blob hash identifies bytes, not the app build,
capture-state identity, synthetic-data provenance, or approval of the artwork.

Before producing final assets, preserve the source commit, app version/build,
device and OS, locale, demo-fixture revision, capture state, raw image digest,
compositor revision, and final image digest for every frame. Capture with the
real native runner, with a stable clock and animation/keyboard state. Keep the
raw screenshots alongside the composed export for visual review. Validate the
supported dimensions and alpha policy, then inspect every final image before
upload. Missing capture or provenance stays unverified.

## Measurement and release acceptance

The initial baseline is the first live, read-back listing and its exact asset
set, not this brief. Record locale, source, device, first-time downloads and
product-page views using matching App Store reporting windows. Report
suppressed or unavailable counts as unavailable rather than zero.

Start with one screenshot hypothesis: the opening three frames explain the
private timeline more clearly than the existing single ring screenshot. Keep
price, paid acquisition, and unrelated metadata stable during the comparison.
Use the registry's acquisition metric with trial, paid conversion, D7/D30,
refund, and crash guardrails; see `docs/marketing/funnel-evidence-contract.md`.
Do not claim user-level App Store-to-native attribution where the providers
only supply aggregate counts. A low-volume result can remain inconclusive.

Live App Store metadata/price readback, screenshot upload/processing, required
privacy declarations, purchase/restore evidence, native release gates, and
Apple's review outcome remain separate requirements. The existing read-only
`.github/scripts/app-store-readiness.mjs` checks provider state when its release
credentials are available. This Linux session has no native capture or App
Store Connect credentials, and does not complete those requirements.
