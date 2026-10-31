# LogYourBody Product Roadmap And Build Guardrails

Last reconciled: 2026-10-31 (LYB-161 parity inventory; LYB-179 product direction retained)

## October 16 supersession: current product behavior

[LYB-173](https://linear.app/jovie/issue/LYB-173/p0-lyb-north-star-automatic-first-one-decision-coaching-and-living),
dated October 14 and verified October 16, supersedes the timeline-first home and
all-at-once first-run direction in the September 26 v1 roadmap preserved below.
Observe permissioned reliable data automatically; foreground one credible
goal-relative decision/action or earned win; keep steering, correction and
historical detail reachable. Ask only for valuable missing information and use
contextual, skippable onboarding. The deterministic engine still owns training
prescriptions; privacy and safety constraints still apply.

Existing first-run, ingestion, native design, coaching, release and coverage
owners implement that staged contract. This reconciliation creates no second
onboarding/home implementation or web expansion. Golden Path persistence,
auth/paywall and reliability gates remain required regression coverage.

The old activation and D7/D30 definitions below are **v1 cohort history**, not
coaching activation. Use the [current funnel evidence contract](marketing/funnel-evidence-contract.md)
for qualification and missing/mature evidence. A rendered insight is an anonymous
occurrence, never inferred from calculation or navigation. Pro's current registry
references are $9.99 monthly / $69.99 annual USD with a three-day trial; earlier
premium-package proposals are not configured offers. Live terms require receipts.

## Product API and agent parity — October 13 direction (LYB-161)

An authorized agent may be the customer's entire interface. Every iOS capability
needs an equivalent product API and MCP action, or a truthful device, system, or
user handoff. Native controls, Siri/App Intents, HTTP, MCP, and a CLI where justified
must use the same product read/create/correct/delete/handoff actions and execution
semantics. This requirement complements the current automatic-first product
direction and does not authorize a web product, food logger, or general workout tracker.

Every new or materially extended feature specification and completion receipt must:

1. Update the [canonical capability inventory](integrations/chatgpt-app/README.md#canonical-capability-inventory)
   with native source, product API/domain action, MCP mapping, gaps, and owning work.
2. Specify authenticated subject and record ownership, explicit LYB connection and
   consent, least-privilege scopes, entitlement, gates, and revoke/reconnect behavior.
   Shared Jovie identity alone is neither a LYB connection nor consent.
3. Define validation, units, measured time, local date, zone, provenance, stable
   operation/measurement IDs, atomic retry receipts, revision conflicts, correction,
   deletion/tombstones, and native offline reconciliation (or explain inapplicability).
4. Name the execution boundary and completion readback. Distinguish local save,
   sync pending, cloud commit, conflict, and actual device effect; opening a screen
   or returning a dialog does not prove the requested operation completed.
5. Attach relevant HTTP/MCP, native/device, provider, and independently qualified
   agent-client receipts plus real CI execution/coverage for implementation. Keep
   unavailable evidence explicitly pending in [user journeys](USER_JOURNEYS.md#agent-parity-acceptance--october-13-2026).

Compose existing first-party routes, typed actions, ports, and adapters. Adopt the
official MCP client/Inspector for conformance and dogfood; no new durable agent
platform, universal runtime, or mandatory custom CLI. Prioritize the manual-weight
lifecycle (LYB-162), then independent client qualification (LYB-163); extend existing
LYB-108/123/80/38 ownership rather than creating competing implementations.

KPI: successful supported user journeys through an authorized agent, zero duplicate
writes or cross-user disclosure, and truthful handoff outcomes.

**Release exception:** the October 13 current TestFlight beta and held release PR
are grandfathered. LYB-161 and its children do not gate them; fresh latest-main
TestFlight delivery is a separate higher-priority execution task. This is backlog
planning only: no dispatch, admission labels, locks, release dependencies,
implementation, deployment, account connection, or marketplace publication. It
changes no signing, Apple capabilities, release metadata/checklist/workflow, or
release PR. Future implementation needs its own authorized work and evidence.

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
