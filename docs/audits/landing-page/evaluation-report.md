# Landing page evaluation report

Date: 2026-07-14

Result: passed — 100/100

| Area                   | Score | Evidence                                                                                                     |
| ---------------------- | ----: | ------------------------------------------------------------------------------------------------------------ |
| Conversion clarity     | 30/30 | One headline, one email field, one CTA; action is visible in the first 390 × 844 frame                       |
| ICP resonance          | 20/20 | Body-composition language, private beta framing, premium performance-studio creative                         |
| Honest trust           | 15/15 | Fastlane screenshot hash-checked against the iOS source; no testimonials, counts, ratings, or outcome claims |
| Mobile usability       | 15/15 | 54 px pill targets, no horizontal overflow, editorial photo hidden, stable validation state                  |
| Design-system fidelity | 10/10 | Dark-only neutral surfaces, generous spacing, restrained metric color, fully rounded controls                |
| Accessibility          | 10/10 | Named field, visible focus treatment, live status, invalid focus recovery, reduced-motion branch             |

## Hard gates

All seven gates in `docs/marketing/landing-page-evaluation.md` pass:

1. No navigation or unverified social proof.
2. Product evidence comes from the registered iOS Fastlane capture.
3. Men and women creatives share one recipe and dimensions.
4. Recomposition, fat-loss, and muscle-gain framing are registry data.
5. Idle, submitting, invalid, success, duplicate, and error states exist without
   changing the surrounding recipe.
6. Design QA has no remaining actionable P0, P1, or P2 finding.
7. Browser QA covers responsive layout, validation focus, console output,
   horizontal overflow, metadata, and motion behavior; isolated tests cover
   success states without inserting fake waitlist records.

## Experiment readiness

The active experiment randomizes audience creative only, with a sticky assignment.
Goal messaging is available for matched outreach links but remains a planned test,
so the first read is interpretable. The registry declares hypothesis, primary
metric, baseline, minimum detectable effect, sample target, allocation, start date,
and kill date.

The landing remains behind `NEXT_PUBLIC_LYB_WAITLIST_V2`, default off, until the
release owner enables the experiment in the production environment.
