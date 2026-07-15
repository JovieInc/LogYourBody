# LogYourBody Product Roadmap And Build Guardrails

Last updated: 2026-06-05

## Operating Principle

LogYourBody is an iOS-first paid product. It should not become another food logger, workout tracker, or dashboard suite. The job is to answer one question with almost no input:

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

- Apple Sign In and email OTP.
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

### AI

AI starts as deterministic, low-text insight, not chat.

First AI-adjacent surface:

- Classify current phase from weight/body-fat trend: cutting, maintenance, gaining.
- Warn when a cut or bulk has likely gone on too long.
- Keep copy short and non-medical.

Only consider a Jovie-style chat after the core timeline is retained and users are asking for interactive recommendations. The app should "just tell me" before it asks the user to have a conversation.

### Food And Workouts

Do not build a food logger or workout tracker. This product is for people who already have those systems and want a body-composition HUD.

## Agent Build Rules

- Build the smallest iOS-native product increment that improves activation, retention, paid conversion, or reliability.
- Put risky/new user-visible behavior behind Statsig gates.
- Prefer follow-up PRs over bloating an active PR.
- Treat App Store/TestFlight, RevenueCat, Clerk, HealthKit, Supabase, and device validation as real closeout surfaces.
- Open issues only after the roadmap item has a clear trigger, KPI, and acceptance criteria.
- When a user asks for Watch, iPad, web, AI, or bulk import, first check whether the trigger is met. If it is not met, propose the smallest validation step instead.
