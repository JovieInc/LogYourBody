# Landing page evaluation contract

This is the blocking acceptance contract for the pre-launch LogYourBody landing
page. It is adapted from Jovie's marketing registry discipline: the layout and
design system stay stable while copy and media are controlled variants.

## Pass rule

The page passes only when it scores at least 90/100 and every hard gate passes.
A strong aggregate score cannot offset a failed gate.

| Area                   | Weight | Evidence                                                                                   |
| ---------------------- | -----: | ------------------------------------------------------------------------------------------ |
| Conversion clarity     |     30 | One promise, one email field, one primary CTA, action visible in the first mobile viewport |
| ICP resonance          |     20 | Precise body-composition language, private/premium tone, campaign-matched media            |
| Honest trust           |     15 | Real app capture, source manifest, no unverified proof or outcome claims                   |
| Mobile usability       |     15 | 390 x 844 capture, 48 px targets, no overflow, stable form states                          |
| Design-system fidelity |     10 | Dark-only tokens, pill controls, restrained blue metric accent, stable section recipe      |
| Accessibility          |     10 | Named field, focus states, live status, reduced motion, contrast and keyboard checks       |

## Hard gates

1. No navigation links, menu, testimonials, ratings, user counts, press logos,
   fake App Store badges, or quantified outcome claims.
2. Product evidence must come from the iOS screenshot source registered in
   `marketing-product-assets.json`; hand-drawn marketing screenshots do not
   qualify.
3. Men and women creative variants use the same layout and dimensions so the
   experiment changes media rather than page structure.
4. Goal framing is registry data (`recomposition`, `fat-loss`,
   `muscle-gain`), not a separate page implementation.
5. The email flow exposes idle, submitting, invalid, success, duplicate, and
   error states without moving the surrounding layout.
6. Design QA has no actionable P0, P1, or P2 findings at mobile and desktop
   reference viewports.
7. Browser QA checks the primary conversion path, keyboard focus, console
   errors, horizontal overflow, and reduced-motion behavior.

## Experiment discipline

The first randomized experiment changes audience creative only. Goal-message
variants are available for campaign-matched links but remain a planned test so
the first result stays interpretable. Every active experiment declares a
hypothesis, primary metric, baseline assumption, minimum detectable effect,
sample-size target, allocation, start date, and kill date.

Primary metric: unique landing session to confirmed waitlist submission.

Guardrails: form-error rate, duplicate rate, page performance, accessibility,
and complaint/unsubscribe signals.

## Screenshot truth loop

Run `pnpm --filter logyourbody sync:marketing-assets` whenever the iOS capture
changes. The sync copies the canonical Fastlane screenshot and app icon,
records source/output hashes and actual PNG dimensions, and fails tests if the
public asset drifts from the iOS source. Marketing code consumes only the
registry URL, never a manually recreated dashboard.
