# Marketing truth and shared-system audit — 2026-10-14

This corrective audit preserves the launch landing composition and authentic LYB
product artwork. It covers public marketing, legal/support, recovery, and native
acquisition routes. It does not qualify a live subscription, app release, provider
security guarantee, or customer outcome.

## Source and ownership receipts

- Canonical repository: `JovieInc/LogYourBody`; live host: `www.logyourbody.com`.
- Production baseline: `3e7cf1a7775936dfc987b0e7fc057a5314698290`, Vercel
  `dpl_3M1PPATs27CCVPH6Ay89BTCDKAJX`. Local integration base:
  `7c1e9d9d1` after the independent training-controller PR landed.
- Followed root `AGENTS.md`, `CODEX.md`, product brand/evidence standards, Jovie
  `DESIGN.md`, UI/Pen rules, marketing invariants, and `JOV-INV-019`.
- Canonical Jovie source: `ac0833d8cac40fb32edcd4404a505f108c7728e5`.
  [UI import receipt](../../../packages/jovie-ui/source.json),
  [consumer ownership](../../../packages/jovie-ui/README.md), and
  [semantic-token receipt](../../../packages/design-tokens/web/jovie-marketing-source.json).
  The five actual upstream control files are byte-identical. Exact imports alone
  are excluded from local autoformatting; staged checksum validation and web CI
  tests reject missing or modified bytes. All surrounding consumer checks remain.
- Reused completed migration/launch/waitlist/footer context in JOV-3099,
  JOV-3100, JOV-3109, JOV-3306, JOV-6071, LYB-18 and LYB-97. Prior owners and
  completed issues were not reopened or reassigned. GitHub issue #1394 records
  only the newly verified gaps. Work was isolated on `fix/marketing-truth-design`.

## Claim disposition

| Material statement/path                              | Evidence and disposition                                                                                                                                                                                                                                                                                                    |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Weight and supported activity read from Apple Health | `HealthKitManager` source supports reads; keep the supported-data qualification. No write/sync guarantee added.                                                                                                                                                                                                             |
| Private body-metrics/photo timeline                  | Canonical product registry, body-metric logging, photo services, and actual committed iPhone screenshot. Preserve description; do not claim an outcome.                                                                                                                                                                     |
| Composition numbers, FFMI, genetic potential         | Distinguish measurement/estimate/source. Remove “genetic potential” or health diagnosis inference; health disclosure now distinguishes measured weight from derived estimates.                                                                                                                                              |
| $9.99 monthly / $69.99 annual / free trial           | Registry and local StoreKit fixture support reference USD prices only. Removed guaranteed three-day trial and no-cost free-tier assertion. App Store confirms price, eligibility and terms before purchase. LYB-97 provider audit does not prove live offers.                                                               |
| Download/release availability                        | Public iTunes lookup for ID 6755209876 returned zero results during audit. Existing App Store-live gate remains off. One honest iPhone early-access funnel; Android explicitly unreleased without a promised date.                                                                                                          |
| Waitlist completion/email                            | API accepts requests; waitlist storage documentation explicitly separates durable registration and delivery. Copy acknowledges receipt without promising an email or invitation date. Browser tests intercept responses and create no real entries.                                                                         |
| About/careers proof                                  | Removed invented user/outcome numbers, team biographies, open roles, benefits, equity and insurance claims. No replacement numbers or people invented.                                                                                                                                                                      |
| Blog health/fitness prescriptions                    | Five legacy articles lacked recoverable primary evidence under the product standard. Preserve as unpublished drafts outside `public/`; exclude drafts from indexes/tags/direct routes/static generation. Raw public URLs also recover with 404. No replacement research invented.                                           |
| Changelog                                            | Git commits are not app-release proof. Replace fabricated release fallbacks and commit-as-release presentation with a clearly described source-history handoff.                                                                                                                                                             |
| Privacy/security/delete-account                      | Removed password contradiction, regular-audit assertion, blanket encryption/access assurances and unsupported deletion deadline. Kept service-provider disclosure; safe email/request handoffs. Account deletion does not cancel Apple's subscription. Reporting link opens a private-report draft, not a submitted report. |
| Crisis resources                                     | Health disclosure uses the current U.S. Alliance for Eating Disorders helpline and Crisis Text Line, with first-party references. Shared legal sources and the three native legal resource copies remain byte-identical.                                                                                                    |

## Design and conversion changes

- Inter body/controls, Satoshi display, exact shared semantic roles/weights,
  canonical 1298px public and 680px prose aliases, actual Jovie Button/Input.
- Preserve the existing dark LYB hierarchy, real app icon and phone composition.
  Remove competing palettes, decorative motion/icon plates and optical drift.
- Canonical text Button has a 28px visible face and at least 44px interactive
  target. Email Input uses 44px/16px. Keyboard, hover, loading and async states
  retain geometry and accessible labels. Retry retains the entered email.
- One main/one H1, skip link, semantic Markdown lists/headings, labelled navigation,
  mobile menu Escape/focus recovery, no nested interactive controls, browser zoom.
- Marketing routes suppress competing PWA install/update prompts. A real iPhone
  Safari stimulus and protected-route positive control verify suppression.
- `/landing` redirects home; `/mobile` and `/download` reach `/download/ios`.
  Draft articles and unknown paths recover without requiring an auth provider.
- New legal-acceptance records stamp the published document content revision; authentication/admission logic and existing consent records are unchanged.
- The honeypot uses clipped screen-reader-only geometry to avoid RTL scroll
  expansion; bot-field semantics remain intact.

## Browser and test coverage

Production baseline and candidate receipts: [before](before-routes.json),
[after](after-routes.json). Screenshots are full page at 393px and 1440px.
The route matrix covers `/`, `/download/ios`, `/download/android`, `/about`,
`/careers`, `/brand`, `/support`, `/security`, `/privacy`, `/terms`,
`/health-disclosure`, `/blog`, `/changelog` and `/delete-account`.
Alias and retired-article recovery are exercised separately.

Additional boundary coverage: 320, 390/393, 768, 1024, 1440 and 1920px; 720px
with 200% text growth, RTL and reduced motion. Checks include document overflow,
loaded images, landmarks, controls, runtime errors, keyboard and unchanged hover
geometry. The existing 1% screenshot-comparison threshold is retained for the
full landing, hero, features, pricing and waitlist on both projects. New baselines
are intentional audit corrections, reviewed alongside the production baseline.

Safe conversion tests cover 202/400/429/500 responses at four widths, pending
submission, native/custom validation, retry/success and retained layout. Requests
are intercepted. No real registration, purchase, email, private report or account
deletion was performed. Public status URL responded successfully; contacts and
private-report destinations are verified as handoffs, not delivery proof.

Validation: normal lint/type/build scripts passed; 107 Jest suites (889 tests) and 3 voice-adapter tests passed; all 18 Playwright browser checks passed without snapshot-update mode. Product registry, URL/legal parity, knowledge lint and vendor-boundary checks passed. The integrity CLI passed unchanged source and failed deliberately altered/missing fixtures. Independent exact-head review is recorded in the PR. Landing and
deployment are separate receipts; local screenshots alone do not prove shipment.

## Before/after samples

| Screen          | Production baseline                              | Corrected candidate                            |
| --------------- | ------------------------------------------------ | ---------------------------------------------- |
| Home mobile     | [before](screenshots/before-home-mobile.png)     | [after](screenshots/after-home-mobile.png)     |
| Home desktop    | [before](screenshots/before-home-desktop.png)    | [after](screenshots/after-home-desktop.png)    |
| Brand mobile    | [before](screenshots/before-brand-mobile.png)    | [after](screenshots/after-brand-mobile.png)    |
| Support desktop | [before](screenshots/before-support-desktop.png) | [after](screenshots/after-support-desktop.png) |

## Exact remaining verification limits

The native Pen semantic inspector is unavailable in this environment. The
fail-closed cold readback preflight returned `safe_cold_manifest_unavailable`;
[receipt](pen-cold-readback.json). The canonical file was not opened, saved,
modified or reconstructed. Source-backed Footer identity and token receipts are
retained, but this audit does not claim native Pen parity certification.

Gbrain's local MCP initialization failed and fallback execution was disabled.
Repository instructions, committed evidence and existing issue records provided
the available source trail; no Gbrain writeback is claimed. Live App Store offer,
email-delivery and provider-security proof remain unverified and are no longer
promised by the corrected public copy.
