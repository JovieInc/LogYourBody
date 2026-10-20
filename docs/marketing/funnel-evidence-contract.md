# Funnel evidence and release contract

Engineering assessment at source `d83b3466`, October 6, 2026. This contract
defines evidence to collect; it does not claim live users, revenue, provider
configuration or App Store readiness. Acquisition is for a private iOS
body-composition timeline. The separate GTM brief owns positioning and channels.

## Ownership and first slice

The acquisition slice owns the existing web analytics port/adapters, waitlist
port/store/API/form, their tests and this documentation. It adds closed
metadata values, drops email/name traits, bounds attribution, preserves the
anti-enumeration response and reports durable unclassified registrations.
It does not alter existing gates or SDK initialization/consent defaults.

PRs #1209 and #1211 / LYB-106 retain onboarding and reminder ownership. Native
auth, HealthKit, profile, sync, training persistence, subscription readiness and
R2 photo-access work remain with the reliability owner. Native visual parity
remains with the design owner. Native `AnalyticsService.swift` requires a
separate allowlist/consent slice after reconciliation with these owners.

## Metric definitions

| Stage                   | Numerator / evidence                                                                                                                    | Denominator / limits                                                                                                                                                                            |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Acquisition             | New durable unique waitlist rows in `[from, to)`                                                                                        | Eligible unique landing sessions in the same cohort; current browser view events are not a verified unique-session denominator. Historical rows are unclassified.                               |
| Activation, proposed    | Authenticated principal + explicit paywall decision + first durably saved measurement + visible timeline within 24h, once per principal | Eligible new product principals, excluding founder/QA/synthetic; inputs and `onboarding_completed` alone do not qualify. Coordinate persistence and visibility receipts with onboarding owners. |
| D7 retention, proposed  | Activated principal returns to the timeline in `[activation+7d, activation+8d)`                                                         | Only activated principals whose full observation window has closed by the data watermark; include counts and dates.                                                                             |
| D30 retention, proposed | Same in `[activation+30d, activation+31d)`                                                                                              | Same mature-cohort rule; exclude incomplete observation windows.                                                                                                                                |
| Trial / paid conversion | Receipt-backed production trial / first paid charge for an eligible principal                                                           | Explicit eligible activation/trial cohort; sandbox, TestFlight, restore and local entitlement transitions are not new cash.                                                                     |
| Revenue                 | Verified production transaction amounts, currency, refunds and reconciliation status                                                    | Report gross proceeds and net proceeds separately; unknown settlement stays unknown. Registry prices and trial duration are reference only.                                                     |

Reports must identify schema version, environment, source revision, generation
time, source watermark, numerator, denominator, cohort bounds, applied
exclusions, missing-data coverage and evidence receipts. Summer receives
aggregate outcomes only. Report interface readiness does not commission a
runtime, scheduler, campaign or provider. Do not join email to health history
or generate marketing audiences from measurements, workout or chat content.

## Actual data flows requiring disclosure review

These are source-observed capabilities, not proof that any unknown provider
transmission occurred in production. Binding policies remain unchanged.

| Flow                    | Current source evidence                                                                                                                                                                                           | Reconciliation needed                                                                                                                                                                                                                                               |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Account                 | `AuthManager.swift`, `ProductAuthContext.tsx`, Jovie OAuth and Neon user directory                                                                                                                                | Both policy copies list encrypted passwords but later say passwords are not stored. Verify Jovie issuer/operator responsibility and identity retention.                                                                                                             |
| Health and profile      | Core Data, first-party bearer APIs, Neon native records/body metrics adapters                                                                                                                                     | Confirm actual synced types, deletion coverage, retention and withdrawal semantics with the reliability owner. No health payload enters marketing analytics.                                                                                                        |
| Progress photos         | Native photo flow and server `r2-progress-photo-store.ts`                                                                                                                                                         | Access controls and public-URL interpretation belong to the reliability owner. Do not infer confidentiality from an unverified storage claim.                                                                                                                       |
| Product analytics       | Native `AnalyticsService.swift` forwards arbitrary strings and email/country/locale traits; ports track onboarding, durable-save, chat interaction and subscription transition events                             | Add closed native metadata and explicit consent semantics separately. Current callsites mostly send interaction markers; this assessment does not claim health values were transmitted. Audit SDK auto-collected metadata and identity/exposure logging separately. |
| Web analytics           | `analytics.ts` fans out to Statsig and Vercel; auth previously supplied email/name traits, now dropped by the acquisition slice                                                                                   | Custom events use closed values; opaque principal identification remains pseudonymous. Audit automatic page views, request URLs, SDK defaults and consent separately. Custom metadata filtering does not certify those layers.                                      |
| Voice input             | `VoiceCaptureService.swift` requests microphone/Apple Speech authorization, requires on-device recognition when supported; otherwise network recognition may occur                                                | Voice exists. Confirm the applicable Apple Speech processing/retention and disclosure. Do not remove voice text based on an older audit.                                                                                                                            |
| Voice intent / playback | `/api/auth/mobile/voice/v1/intent` parses transcript and exercise context locally on the server; `/speak` sends response text to the configured direct ElevenLabs adapter or Fish Audio through Vercel AI Gateway | Verify actual selected provider, gate, allowlist, retention and subprocessors; no transcript or response text in acquisition analytics.                                                                                                                             |
| Subscription            | RevenueCat client and subscription transition policy                                                                                                                                                              | Separate entitlements from receipt-backed cash and verify the live offer with the subscription owner. Do not change prices.                                                                                                                                         |
| Waitlist                | Dedicated Neon, unique email, source, status and timestamps                                                                                                                                                       | Purpose/version/time consent, durable suppression history, approved outbox, unsubscribe handling and provider receipts require a separate migration and reviewed copy. Existing consent cannot be broadened retroactively.                                          |

## Release gates and evidence limits

Keep outbound provider calls disabled in tests and runtime preparation. Use
synthetic contacts and mocked persistence/analytics; never send invitations,
enroll contacts, activate campaigns, create credentials, spend, accept legal
terms or submit to the App Store as part of this slice.

App Store readiness still requires installed native acceptance, verified live
ASC/RevenueCat offers, factual privacy/App Privacy reconciliation, account
deletion and support paths, permitted screenshots and current required checks.
Distributed TestFlight 1.2.0 build 20261006222024 is sandbox evidence; installed
acceptance remains open. A draft PR or interface test does not close those gates.
