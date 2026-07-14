# Landing page agent guide

The LogYourBody landing system is a bounded generator, not a blank canvas.
Agents may create experiments by changing registry data and approved media;
they must not fork the page component or invent a new visual system for each
campaign.

## Inputs

- `audience`: `men` or `women`
- `goal`: `recomposition`, `fat-loss`, or `muscle-gain`
- `trafficSource`: experiment, campaign, or returning visitor
- approved editorial media with the shared 3:2 crop and dark negative space
- canonical product proof from the iOS marketing asset manifest

## Stable recipe

`hero → capture → product-proof → closing-line`

The mobile recipe hides editorial photography and puts the email action before
product proof. Desktop keeps the same action inline and introduces the
editorial media on the right. Navigation remains hidden until product scope
changes explicitly.

## Adding a variant

1. Add copy or media to `landing-registry.ts`; do not add a page route.
2. Keep the current content budgets and the single-CTA contract.
3. Add a hypothesis and complete experiment metadata before random allocation.
4. Run the configuration evaluation and browser QA at 390 x 844 and 1440 x 900.
5. Refresh the iOS capture through the source pipeline; never redraw app UI for
   a marketing screenshot.
6. Promote or retire the variant at its kill date and update the registry.

## Proof policy

Until verified data exists, social-proof and stats sections are illegal. A real
product capture is evidence of what the app is; it is not evidence of user
outcomes. Keep those categories separate.

## Reuse boundary with Jovie

This system deliberately mirrors Jovie's typed registry, deterministic recipe,
zero-proof gate, responsive contract, screenshot manifest, and QA ratchets.
Product copy and photography remain LogYourBody-specific. Shared-company
extraction should move those generic contracts and primitives into a versioned
package; do not couple either production deploy to a sibling repository path or
symlink.
