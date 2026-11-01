# LogYourBody Product Roadmap And Build Guardrails

Last reconciled: 2026-11-01 (LYB-173 October 28 home contract; LYB-274 parity-slice decision; LYB-275 client-qualification order; preserves LYB-161 and LYB-179)

## October 16 supersession: current product behavior

[LYB-173](https://linear.app/jovie/issue/LYB-173/p0-lyb-north-star-automatic-first-one-decision-coaching-and-living)
is the product behavior and release-sequencing contract. The October 14 text,
verified October 16, still supersedes all-at-once first-run and a raw
provider-metadata home in the September 26 v1 roadmap preserved below. Observe
permissioned reliable data automatically. Foreground one credible goal-relative
decision, action, or earned win. Keep steering, correction, and provenance
reachable. Ask only for valuable missing information. Use contextual, skippable
onboarding. The deterministic engine still owns training prescriptions. Privacy
and safety constraints still apply. Avoid medical diagnosis. Do not take an
unsupported action or silently change a consequential plan.

### October 28, 2026: body-through-time Home

Founder direction on October 28 updates the older line that timeline and stats
are not the home default. Home is the user's body through time: easy weekly
photos, a subdued background, consistent framing, and a scrub timeline. When
photos are absent, show a selectable male or female wireframe. One useful
contextual action stays on that canvas, with progressive skippable capture
guidance, authentic source photos, provenance, and supported uncertainty. Raw
timeline and provider metadata stay inspectable and do not dominate Home. Chat
remains a control plane, not the whole UI.

Optional rotatable personal 3D is in scope only inside LYB-311. That bounded
program replaces a blanket deferral of all 3D work. Generic avatars stay
illustrative until calibrated. Personalized reconstruction and body-change
claims wait for their recorded validation gates. An AI weekly average or other
synthetic transformation is never shown as captured evidence.

Paid R1 is the body timeline, Stats, and imports, and it can ship on its own.
R2 chat and R3 programming stay separate releases. Paid R1 has no mandatory
composer, chat, or advanced-3D dependency. LYB-100 keeps web landing-only.
LYB-164 does not authorize an authenticated web app. Canonical planning UI is
iOS native responsive cards until a separate product and platform approval.
[LYB-174](https://linear.app/jovie/issue/LYB-174/p0-rolling-hypertrophy-schedule-adherence-aware-sessions-and)
owns rolling, adherence-aware sessions and the optional time budget. Session
duration is computed from useful volume, exercise and rest selection, and
recovery. A daily duration target is not default onboarding.

Existing first-run, ingestion, native design, coaching, release, and coverage
owners implement their stages. This reconciliation creates no second
onboarding or Home implementation, takes over no active PR, flag, or
certification, and invents no BodySpec MCP event support. Golden Path
persistence, auth, paywall, and reliability gates remain required regression
coverage. Stage completion still needs installed TestFlight journey proof,
source-permission variations, offline, empty, and error paths, and the
self-improving failed-fixture path in JOV-8332. A merge alone does not complete
a stage.

The old activation and D7/D30 definitions below are **v1 cohort history**, not
coaching activation. Use the [current funnel evidence contract](marketing/funnel-evidence-contract.md)
for qualification and missing/mature evidence. A rendered insight is an anonymous
occurrence, never inferred from calculation or navigation. Pro's current registry
references are $9.99 monthly / $69.99 annual USD with a three-day trial; earlier
premium-package proposals are not configured offers. Live terms require receipts.

## Product API and MCP parity — LYB-161

Founder direction, October 13, 2026: an authorized agent may be the customer's
entire interface. Every iOS capability needs an equivalent product API and MCP
action, or a truthful device, system, or user handoff. This applies to every new
or materially extended feature from specification through completion evidence.
The [canonical capability inventory and entry-point mapping](integrations/chatgpt-app/README.md#canonical-ios-capability-inventory)
records existing source, gaps, and execution boundaries. Update its affected rows
in the same feature PR; source availability alone does not establish parity.

### Feature specification and completion contract

Each feature specification must record:

- The supported user journey, its trigger and KPI; native control, Siri/App
  Intent, product HTTP, and MCP mappings at the same read/create/correct/delete
  or device-handoff level. Mark unsupported actions explicitly. A CLI is optional
  only for a demonstrated scripting gap.
- Authenticated subject, resource audience, least-privilege scopes, explicit LYB
  connection/consent, ownership, entitlement and default-off gates. Shared Jovie
  identity alone grants no LYB connection or delegated permission.
- Validation, units, measured time, local date/zone, source/provenance and stable
  measurement identity; distinguish measured values, estimates and selected goals.
- Stable retry/operation IDs, intentional repeat entries, atomic mutation/receipt
  persistence, correction revisions, conflicts, tombstones and offline/native
  reconciliation. Generic table sync is not an agent product action.
- Execution boundary and user confirmation, including denied/unavailable/cancelled
  outcomes. Report local saved, sync pending, cloud committed, conflict, and
  device-effect states separately, with persisted readback for claimed completion.
- Named HTTP/MCP/native/provider regression and failure-path tests, actual CI
  execution/coverage, and [independent agent dogfood receipts](USER_JOURNEYS.md#agent-parity-completion-evidence).
  Missing or simulated evidence stays pending; a tool response or local dialog
  alone is not end-to-end completion.

Compose existing first-party routes, typed domain actions, ports and adapters.
Adopt the official MCP client/Inspector for conformance and dogfood. Preserve Core
Data/offline authority, per-user isolation, health-data boundaries and engine-only
numeric training prescriptions. No new durable agent platform, universal runtime,
food logger, general workout tracker, or mandatory custom CLI is implied.

**Release exception and planning boundary:** the October 13 TestFlight beta and
held release PR are grandfathered. LYB-161 and its children do not gate that
release or the separate, higher-priority latest-main TestFlight delivery. Except
for the single post-shipment inventory check recorded in LYB-274, this plan
authorizes no implementation, deployment, account connection, dependency
installation, marketplace publication, Apple capability/signing change, release
metadata/checklist/workflow change, or release-PR mutation. LYB-275 is a further
exception limited to synthetic-fixture qualification of Claude Code, then
ChatGPT, then Jovie. That exception still authorizes no account connection,
client registration, credential storage, admission label, or real user data.
Keep linked planning
items in Backlog without dispatch, admission labels, locks or release-blocking
relations; retain existing owners and branches.

### LYB-274 next slice only

Recommended default adopted under LYB-274's ships-if-unanswered instruction.
LYB-274 authorizes only a CI parity-inventory check after the current TestFlight
release ships. Feature slices stay unauthorized. The check maps every iOS
capability to a product API or MCP action or a declared device, system, or user
handoff. It is not feature work. It adds no tool, route, account connection,
deployment, or release gate, and it leaves the grandfathered October 13 beta
and the in-flight TestFlight delivery ungated.

Recorded child slices: inventory check, goals/preferences, trends,
photos/imports, GLP-1, export/deletion, and integration status. Only the
inventory check is implementation-authorized, and only on the terms above. The
other six stay unauthorized. LYB-162 remains the in-progress weight slice.
Repository slice keys are not Linear issue IDs, admission labels, or dispatch.
Real-device TestFlight evidence stays with LYB-161. The
[slice record](../packages/shared-lib/decisions/agent-parity-slices.md) is the
specification.

### LYB-275 client qualification order

Recommended default adopted under LYB-275's ships-if-unanswered instruction.
LYB-275 qualifies Claude Code first on a synthetic fixture account only, then
ChatGPT, then Jovie. Real consented accounts and client registrations are not
provided. The account owner provides those accounts, public client IDs, and
exact approved redirects, and only after that client's synthetic run passes.
This decision provides two synthetic fixtures only: fixture-a and fixture-b,
with no real user data and no credentials.

Only Claude Code may start, and only on those synthetic fixtures. ChatGPT
starts after the Claude Code synthetic run passes. Jovie starts after the
ChatGPT synthetic run passes. A synthetic pass does not qualify another client
and does not authorize a real account connection. Recorded qualification slices
are Claude Code, ChatGPT, and Jovie. Repository slice keys are not Linear issue
IDs, admission labels, or dispatch. This record connects no account and
registers no client. Real-device TestFlight evidence stays with LYB-161. The
[qualification record](../packages/shared-lib/decisions/client-qualification-order.md)
is the specification.

## September 26 roadmap — preserved v1 history

## Operating Principle

LogYourBody is an iOS-first paid product centered on body-composition progress. It also includes an evidence-grounded hypertrophy coach whose deterministic programming engine supplies training prescriptions. Keep training focused on engine-led programs rather than a general-purpose workout tracker, and do not add a food logger. The job is to answer one question with almost no input:

> How am I doing?

The first shippable wedge is a native iOS app where a user can sign in, pay, log weight/body composition/progress photos, and see a clear body-composition trend. Everything else waits for measured user pull.

Product decisions must follow the [LogYourBody Brand Ethos](product/brand-ethos.md) and [Evidence and Recommendation Standard](product/evidence-and-recommendation-standard.md). The product optimizes changeable aspects of appearance within health and user agency; population reference ranges must never become silent personal targets.

## Design System Direction

- Use the Joby/Jovie-style product language: dark-only, minimal, quiet, high-contrast, generous white space, and crisp system typography.
- Prefer neutral black, near-black, white, and gray surfaces. Use Geist-like accents only for metric meaning, status, focus, and small visual cues.
- Auth controls should be pill-shaped, concise, and touch-friendly. Avoid square, boxy login CTAs.
- Metrics keep stable accent colors:
  - Body fat: pink/red
  - Weight: violet
  - FFMI/FMI: purple
  - Steps/activity: amber
  - Waist/measurements: blue
- No decorative gradients, heavy marketing surfaces, or dense product education inside the app.

## North Star

The app should feel like a body-composition heads-up display:

- Open app.
- See the latest body/photo state immediately.
- Know whether weight/body fat/FFMI are moving in the right direction.
- Scrub the timeline to understand how the body changed over time.
- Get a short, low-friction signal like "cutting", "maintenance", or "gaining" only when the data supports it.
- Compare trends against goals the user explicitly selected, not sex-based aesthetic defaults.

## KPI Ladder

These metrics decide what gets built next:

- Activation: user signs in, completes paywall/free trial decision, and logs at least one weight or imports one HealthKit weight within 24 hours.
- Photo activation: user adds or imports at least one progress photo.
- Core retention: user opens the app and views or logs data on day 7 and day 30.
- Paid signal: trial start rate, paid conversion rate, refund/cancel reasons.
- Reliability: crash-free sessions above 99.5 percent and no auth/paywall dead ends.
- Pull signals: support requests, bug reports, App Store reviews, and repeated user asks.

## Phase 0: Paid iOS MVP

Ship only the paid native iOS loop:

- Apple Sign In as the single primary authentication path.
- Working paywall/free trial with a logout escape.
- Manual weight logging.
- HealthKit weight import where already stable.
- Minimal dashboard showing latest weight/body-composition state.
- Stable settings screen with account, subscription, export/delete, HealthKit, and support.
- Deterministic App Store screenshot generation based on the Jovie public-profile carousel style: iPhone aspect-ratio screenshots, concise copy above, dark product system, no one-off manual screenshots.

Do not expand scope if this loop is not stable.

## Phase 1: Photo-First Timeline

Build the product around a 4:5 full-width progress photo surface with a timeline scrubber below it.

Core interactions:

- Swipe progress photos left and right.
- Scrub the timeline by date.
- Switch timeline mode between photo date, body fat percentage, weight, and FFMI/FMI.
- Start with body fat percentage plus photo first.
- Show weight/body fat/FFMI as compact metric cards, not a dense analytics console.

The timeline is the product. A feature that does not improve timeline clarity, data import, or daily "how am I doing" feedback should be deferred.

## Phase 2: Analytics And Import

After activation and retention are healthy, expand into Apple Health-style analytics:

- Individual metric cards over time.
- Better HealthKit import and scale-data ingestion.
- DEXA/body-composition events.
- Interpolation between strong composition measurements and photo/weight trends.
- Bulk progress photo import when photo activation and user requests justify it.

Photo import should eventually identify likely progress photos and crop them consistently for comparison and morphing, but this is not Phase 0 scope.

## Expansion Triggers

Do not spend meaningful build tokens on these surfaces before their trigger is met.

### Web

Build a web version only after one of these is true:

- 1,000 activated iOS users, or
- 250 paying subscribers and web access is a top recurring support request.

Until then, web work is limited to marketing, legal, support, and account/billing surfaces that unblock the iOS app.

### iPad

Build iPad-specific UI only after one of these is true:

- 100 active iPad users, or
- 25 explicit iPad/kiosk requests, or
- a founder-approved kiosk experiment with a clear validation goal.

Target layout: portrait behaves like iPhone; landscape uses photo on the left, stats on the right, and timeline across the bottom. Kiosk mode is a future premium/experimentation surface, not the first paid MVP.

### Apple Watch

Do not build a Watch app speculatively. Start only after repeated user pull:

- 25 explicit Apple Watch requests, or
- 10 paying users asking for watch-visible basic stats.

Initial Watch scope is read-only basic stats and latest trend direction. No logging-first Watch app unless usage proves it.

### Hypertrophy Coach

The deterministic programming engine owns training plans and every numeric prescription. The conversation model may narrate engine-returned output, explain its evidence, cite the opaque knowledge IDs it receives, and record user feedback. It must never invent, calculate, select, or modify exercises, sets, reps, loads, volume, progression, or schedule. When an authorized engine plan or its supporting evidence is absent, the coach says that it has no authorized training guidance to provide.

Keep responses concise and non-medical. Preserve the existing consent, health-data, evidence, and body-image safeguards. Do not provide prescriptive aesthetic coaching to minors, pregnant or postpartum users, people with known eating-disorder risk, or people pursuing unsafe targets.

### Food And Training Scope

Do not build a food logger or a general-purpose workout tracker. The hypertrophy programming engine and its bounded coaching interface are in scope alongside the body-composition timeline.

## Agent Build Rules

- Build the smallest iOS-native product increment that improves activation, retention, paid conversion, or reliability.
- Put risky/new user-visible behavior behind Statsig gates.
- Prefer follow-up PRs over bloating an active PR.
- Treat App Store/TestFlight, RevenueCat, Jovie Auth, HealthKit, Neon, and device validation as real closeout surfaces.
- Open issues only after the roadmap item has a clear trigger, KPI, and acceptance criteria.
- When a user asks for Watch, iPad, web, AI, or bulk import, first check whether the trigger is met. If it is not met, propose the smallest validation step instead.
