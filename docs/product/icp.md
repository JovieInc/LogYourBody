---
title: Ideal customer profile
status: decided by Tim 2026-09-27; sizing is research, revisit when funnel data exists
supersedes: docs/product/outcome-map.md section 2 (ICP proposal)
---

# Who LogYourBody is for

**One sentence:** adults who already spend money to look better naked, and want proof that the money is working.

This is an aesthetics product, not a fitness or health product. The customer cares about how their body looks without clothes, and about keeping the muscle that shows while the fat comes off. Everything the app says and shows is framed as appearance, never as general fitness, wellness, or clinical health. The [Brand Ethos](brand-ethos.md) safety boundaries still apply in full.

## Purchase signals that identify them

We do not find these people by asking about goals. We find them by what they already pay for.

| Signal | What it proves | Size and price (sourced in the research note) |
| --- | --- | --- |
| Pays for DEXA or InBody scans | Wants the truth about fat versus muscle, not a scale number | Consumer DEXA providers report 300,000+ clients at $40 to $180 per scan, rescanning monthly to quarterly |
| Uses a GLP-1 for weight loss | Is spending hundreds of dollars a month on appearance and is worried that a quarter to two fifths of the loss is muscle | Roughly 15 million US adults; 12% of adults have used a GLP-1 |
| Pays for a hypertrophy programming app | Already buys software to build muscle for looks | $72 to $300 per year per user in the leading apps |

The strongest customer has the first two signals at once: a GLP-1 user who scans. They already pay more for one scan than for a year of this app, they rescan on a cadence that gives us a natural retention loop, and their daily question is exactly the one the timeline answers.

## The job to be done, in their words

1. "Prove the weight is coming off the right place."
2. "Keep the muscle that keeps me looking good and keeps the weight off."
3. "Make the gap between scans mean something."

## What the product must do for them

- Import a DEXA or InBody result on iOS as a first-class journey, and place it on the same timeline as weight, body-fat trend, and progress photos.
- Answer "fat or muscle?" on the home surface, not behind a stats tab.
- Coach toward the muscle that shows, through the deterministic hypertrophy engine and Jovie, inside the evidence and claims boundaries.
- Log GLP-1 doses as a medication reminder in the style of Apple Health's Medications feature: tracking only, never a recommendation, never dosing or titration guidance. If any medication surface risks App Review, the surface is cut and the signal is kept only in onboarding and segmentation copy.
- Progress photos are the proof; the timeline exists so the photos are never lost and always comparable.

## Positioning lines to test

- "Losing weight? Make sure it's fat."
- "The scoreboard between your scans."
- "Fat off. Muscle on. Photos that prove it."

## Where to reach them, in order of reachability

1. The GLP-1 weight-loss subreddits (about 620,000 combined members across the three largest), where body-composition questions are a daily thread.
2. DEXA providers as partners; the largest has no native app and 300,000+ clients.
3. GLP-1 Facebook groups (older, higher scan spend).
4. Physique-science creators whose audiences already pay for apps.
5. Telehealth GLP-1 providers that need a muscle-preservation companion to reduce churn.

## Sizing (research estimate, not a forecast)

- Usable TAM: about 15 million US adults on a GLP-1 for weight loss.
- Beachhead SAM: GLP-1 users who pay for scans, estimated at 100,000 to 280,000 people per year.
- Realistic year one to two SOM: 1% to 3% of the beachhead, or 2,000 to 8,000 paid subscribers, which covers the company's $5,000 MRR target several times over at current prices.

Arithmetic, sources, competitor scan, and risks are in the research note kept outside this repo; the numbers above are estimates and will be replaced by observed funnel data.

## Risks to watch

- Wearable platforms partnering with drug makers can compress the wedge; speed matters.
- These communities are evidence-literate; mixing BIA or photo estimates with DEXA carelessly loses trust.
- Anything that reads as dosing or treatment advice invites regulatory and App Review trouble; tracking-only is the line.

## What this changes in the outcome map

Section 2 of the outcome map is replaced by this document. In section 5, GLP-1 dose logging and check-in move from "remove" to "keep as tracking-only reminder"; DEXA import gains an iOS journey requirement; the home surface headline becomes fat versus muscle.
