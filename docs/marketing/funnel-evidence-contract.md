# Funnel evidence and release contract

## Current contract — October 16, 2026 (LYB-179)

This section supersedes the October 6 timeline-first positioning and proposed
activation interpretation below. The original assessment remains **v1 history**;
do not relabel its cohorts or compare their rates with a new coaching definition.
[LYB-173](https://linear.app/jovie/issue/LYB-173/p0-lyb-north-star-automatic-first-one-decision-coaching-and-living),
read October 16, is the product behavior and release sequencing authority:
permissioned automatic observation, one credible decision/action, persistent
steering, contextual skippable onboarding, and inspectable/correctable history.
Timeline and stats are detail surfaces. This measurement slice adds no onboarding,
import, sharing, coaching or home implementation.

### What qualifies

`first_insight_rendered` is an anonymous **render occurrence**, emitted through
`AppServicePorts.analyticsTracker` and the `AnalyticsService` sanitizer. Its
metadata allowlist is empty, including no entry context, health values, account
identity, result text, source, or goal. The existing fat/lean summary must be valid,
its reveal must finish, at least half the summary row must be in the scroll
viewport, and the scene must be active. Loading/error/fallback content does not
qualify. Emission is default-off behind `growth_first_insight_rendered_v1`; this
change does not configure that gate or change analytics startup/consent defaults.

Deduplication lasts for the existing in-memory first-run view model. A new flow,
relaunch or device may emit again. There is no durable account identity in this
marker and no claim of unique people, lifetime first impressions, successful
learning, time to insight, or coaching activation. SDK automatic metadata and
consent still need their own commissioning/disclosure audit.

Calculation success, `onboarding_step_advanced` to `bodyScore`, onboarding
completion, chat completion, purchase success and entitlement phase changes
are neither rendered-insight impressions nor receipt-backed customer outcomes.
The private report rejects those event names as insight/activation inputs.

| Evidence                      | Qualification and denominator                                                                                                                                                                                                                                                                                                                        |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| First insight                 | Statsig count of the generic rendered marker, with production/exclusion and gate coverage receipts; anonymous occurrences only. `onboarding_started` is a separate occurrence count, never a unique-person conversion denominator.                                                                                                                   |
| Activation v1, historical     | Eligible new principal created in `[from,to)` signs in, makes an explicit paywall decision, durably saves/imports a measurement and sees its dated timeline within 24 hours. Denominator: all eligible new principals in that creation cohort, with unknown outcomes counted as missing. Existing input and transition events do not establish this. |
| D7/D30 v1, historical         | Those same v1 activated principals return to view/log the timeline in `[activation+7d,activation+8d)` or `[activation+30d,activation+31d)`. Denominator must equal the cohort's v1 activation numerator. Entire cohort must mature, including the possible 24-hour activation delay.                                                                 |
| Qualified coaching activation | Unknown. LYB-173's credible, goal-relative decision, source freshness/confidence, user steering and verified benefit need an owner-approved qualification and first-party outcome receipt. This slice invents no activation event or numeric proxy.                                                                                                  |
| Money                         | Only the bounded production aggregates from the existing [RevenueCat ledger query](../integrations/revenuecat-ledger.md). Actual charges and normalized supported MRR stay separate. Local purchase/restore/trial markers do not qualify. Net revenue, trial-to-paid conversion and customer outcomes stay unknown/unreconciled.                     |

### Private operator command and input

From the repository root:

```bash
pnpm --silent growth:report docs/marketing/growth-evidence.empty.json
pnpm --silent growth:report /tmp/private-growth-aggregate.json
```

The committed empty input is a dated source-only inventory with **no receipts**;
every metric is unknown. Replace its revision/window/as-of for an actual private
run. The CLI reads one regular local JSON file, at most 64 KiB, and prints JSON.
It makes no provider requests, database connections, public routes, schedules or
outbound sends. Keep actual inputs and outputs in access-controlled operator
storage, outside git, public artifacts and marketing audiences. Do not feed it
raw Statsig, RevenueCat, Core Data or Neon exports.

Top-level fields are exactly `schema_version: 1`, `environment: "production"`,
`source_revision` (40 lowercase hex characters identifying the assessed build),
`as_of` (not later than generation), `window: {from,to}` and `sources` (0–3
snapshots). All dates use `YYYY-MM-DDTHH:mm:ssZ`; `from < to <= as_of`, with at
most 90 days in `[from,to)`. Unknown fields at every level are rejected, including
health values, identity, free text, tokens, URLs and provider payloads. Errors
never echo an untrusted key, value or file path. Duplicate JSON keys, including
escaped aliases, are rejected before overwritten evidence can reach the schema.

Each snapshot has exactly these fields:

| Field                        | Required value                                                                                                                                                                                   |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `source`                     | `statsig`, `core_data_neon`, or `revenuecat`, at most one of each                                                                                                                                |
| `environment`                | `production`; sandbox/TestFlight/QA evidence is rejected                                                                                                                                         |
| `receipt_sha256`             | 64 lowercase hex characters; no reused receipt hashes across snapshots                                                                                                                           |
| `from`, `to`                 | Exactly the requested creation/event cohort bounds; no mixed windows                                                                                                                             |
| `watermark`                  | Latest fully covered source time, no later than `as_of`; never substitute export time for coverage                                                                                               |
| `commissioned`, `reconciled` | Boolean operator attestations backed by separately retained receipts; false withholds qualified values                                                                                           |
| `exclusions`                 | Exactly `sandbox`, `testflight`, `qa`, `synthetic`, `duplicates`; attest exclusions were applied before aggregation, including transaction deduplication rather than just event-ID deduplication |
| `metrics`                    | Only the source-specific fields below; omit missing evidence rather than inventing zero                                                                                                          |

| Source           | Accepted metrics                                                                                                                                                                                                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `statsig`        | `onboarding_started`, `first_insight_rendered`: nonnegative integer occurrence counts                                                                                                                                                                                                                         |
| `core_data_neon` | `activation_v1`, `d7_retention_v1`, `d30_retention_v1`: each `{numerator,denominator,missing}`, nonnegative integer counts with denominator > 0 and numerator + missing <= denominator. Retention requires the matching activation observation; no empty or sampled denominator masquerades as a full cohort. |
| `revenuecat`     | Existing production SQL fields `supported_charge_count` (integer count), `observed_gross_purchase_usd`, `supported_observed_mrr_usd` (finite nonnegative USD amounts or null). Preserve SQL null MRR. Never combine local currencies or substitute registry prices.                                           |

Counts are bounded at 10 million; amounts at 1 billion. The existing RevenueCat
SQL's exclusion/ambiguity counters remain in the private source receipt; reconcile
them before attesting completeness. Core Data/Neon extraction requires authorized
first-party durable-save and visibility receipts. There is no new cross-provider
identity join, customer export or health-data audience.

The ledger's `refund_or_reversal_event_count` diagnostic spans observed history
and can include sandbox events; it is deliberately rejected as a production
window metric here. Refund reconciliation remains explicitly unknown, alongside
net revenue, until separately qualified by its existing owner.

The result preserves each observation, numerator/denominator/missing count,
receipt hash, source watermark, required observation close, revision, generation
time and as-of. `value` is null for absent/null evidence (`unknown`), coverage
ending before `to` or more than 24 hours behind `as_of` (`stale`), false
attestations (`uncommissioned`, `unreconciled`), incomplete coverage, or an immature
cohort. Reasons accumulate. Activation closes at `to+1d`, D7 at `to+9d`, D30 at
`to+32d`, allowing the full activation delay and exclusive return window.
An as-of older than 24 hours is also labeled a stale snapshot. A recorded zero is
distinct from unknown. No qualified rate is shown for partial cohorts.

`qualified` means only that the supplied aggregate meets this schema and its
operator attestations. Hash syntax does not authenticate a receipt. Provider
commissioning always remains `not_independently_verified` by this offline tool;
the report never certifies installed behavior or actual customer benefit. Its
Node behavior suite runs through the existing shared-lib `pnpm test` discovery
with production-code coverage; no CI gate or workflow is changed.

### Measurement repair and iteration

The private report now emits `iteration.next_actions` from the same qualification
rules as its metrics. Actions identify the fixed source and metric IDs requiring
missing aggregates, commissioning, reconciliation, source coverage refresh, or
complete cohort evidence. `wait_for_cohort_maturity.not_before` is the latest
required close across the affected cohorts; waiting alone does not replace a
source watermark that covers that close. A stale report adds
`refresh_report_snapshot`, even when its historical aggregates qualify.

`repair_measurement` means resolve the listed evidence gaps before comparing
results. `review_qualified_aggregates` means the supplied aggregates can be
reviewed under this contract; it does not certify a release, live provider, or
winning experiment. `experiment_decision` remains `not_evaluated` because this
input contains no randomized assignments, comparison cohort, predeclared outcome
or uncertainty calculation. Anonymous event occurrences must not become a
user-conversion rate by dividing independent event totals.

The operator closes the loop as follows:

1. Verify installed-build behavior and source receipts for the assessed revision,
   then obtain the bounded production aggregates using the source owner's query.
2. Run `growth:report` privately. Resolve its actions, retaining corrected source
   receipts; rerun until the relevant metric and snapshot are current and complete.
3. Before an experiment, record one hypothesis, assigned population, primary
   outcome, minimum observation window, decision rule and guardrails. Use the
   existing Statsig gate/assignment path. Keep crashes, purchase errors, account
   deletion and support complaints alongside the outcome; do not optimize a click
   count at the expense of these safeguards.
4. Evaluate the predeclared comparison only after both cohorts mature and source
   coverage reconciles. Record the decision and evidence privately, ship through
   the repository release gates, then verify the new installed build and repeat.

No schedule, experiment, provider configuration or automatic gate change is
created by this offline tool. LYB-265's separate coaching-benefit work owns its
new qualification; this historical report does not substitute a proxy for it.

Both existing waitlist forms now emit `web_waitlist_started` once per mounted
form, `web_waitlist_submit_attempted` for a request, and
`web_waitlist_submit_result` with closed `invalid`, `accepted`, `rate_limited`, or
`server_error` outcomes. Result events preserve the same allowlisted landing
attribution so failures can be inspected by rendering variant. Neither the
email, raw error, nor server duplicate status is sent to analytics. Accepted
requests, including duplicates and honeypots, retain one indistinguishable UI
outcome; durable registration counts remain server-owned. SDK failures do not
interrupt the form or prevent the other analytics adapter from receiving events.
These source changes still require production delivery and consent receipts.

### Owners, offers and release evidence

LYB-106/171 retain first-run/automatic ingestion ownership; LYB-134 retains
provider/revenue commissioning, LYB-138 App Store/account actions, LYB-56 native
coverage. Active release, import and sharing PRs are not absorbed here. Native
runner receipts must name this head and the changed tests; installed-build proof
must name the build, commit, gate/environment and actual journey. Code, lint,
source audit or a report fixture cannot close those requirements.

The [product registry](../../packages/product-registry/src/products/logyourbody.mjs)
currently defines **Pro**: USD reference $9.99/month or $69.99/year, three-day
trial, existing monthly/annual package IDs and `Premium` entitlement. These are
reference terms, not proof of a configured live offer or customer eligibility.
Earlier proposed premium bundles, coaching packages, weekly prices, longer
trials and research examples are not configured offers. No price, trial, paywall,
vendor, legal, provider, outreach or spending authority changes here.

[Five reference teardowns and three exact demo drafts](growth-reference-demos-2026-10-16.md)
are private preparation, not published campaigns or installed-build evidence.

## October 6, 2026 assessment — preserved v1 history

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
