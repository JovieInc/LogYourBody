# LogYourBody App Store Storefront

This directory documents the closed-loop system that keeps the LogYourBody App Store listing truthful, current, and measurable.

## Source of truth

The canonical storefront definition lives at:

- `packages/product-registry/src/storefronts/logyourbody.mjs`

It owns:

- localized App Store metadata;
- search-intent clusters and Custom Product Page candidates;
- screenshot narrative, order, capture-state IDs, and feature references;
- accepted screenshot formats and dimensions;
- GPT Image 2 guardrails.

Run `pnpm product:generate` after changing storefront truth. Generated Fastlane metadata and `apps/ios/fastlane/storefront-manifest.generated.json` are checked in so changes are reviewable and deployable.

`pnpm product:check` fails when:

- generated metadata is stale;
- Apple metadata limits are exceeded;
- keywords are duplicated or waste terms already indexed from the name, subtitle, or company name;
- copy or screenshots reference unavailable or non-marketable features;
- screenshot order, capture states, dimensions, alpha-channel policy, or screenshot provenance drift;
- GPT Image 2 is not pinned or is allowed to fabricate product UI or body-transformation proof.

The iOS release source gate runs the same storefront validator before an App Store release can proceed.

## Research contract

Creative and ASO decisions are evidence-backed, not taste-only.

Before approving a new narrative, keyword set, Custom Product Page, or experiment:

1. Query G-Brain for prior LogYourBody product, positioning, design, screenshot, ASO, pricing, privacy, and launch decisions.
2. Run `/last30days` for current customer language, complaints, competitor movement, privacy concerns, and App Store creative/ASO discussion.
3. Verify platform behavior and limits against current Apple documentation.
4. Create an evidence matrix with source, date, authority or engagement, confidence, product implication, and action.
5. Write accepted decisions and experiment outcomes back to G-Brain.

Required initial sweeps:

```text
/last30days "body composition tracker progress photo app complaints reviews" --days 30
/last30days "weight tracker body fat app competitors complaints" --days 30
/last30days "App Store health fitness screenshot design conversion ASO" --days 30
/last30days "private progress photos body tracking trust privacy concerns" --days 30
```

Store raw evidence and syntheses under `docs/marketing/app-store/research/`. The current Apple platform evidence is recorded in [`research/platform-contract.md`](research/platform-contract.md).

## Creative system

Final product UI must always come from deterministic real-app capture with synthetic, privacy-safe demo data.

GPT Image 2 may be used for:

- art-direction exploration;
- non-semantic editorial background plates;
- texture and lighting exploration;
- comparison-board variants.

It must not generate:

- product UI;
- final typography or localization;
- device geometry;
- before-and-after bodies;
- body transformations;
- fabricated measured outcomes.

The pinned production model is recorded in the storefront definition and generated manifest.

## Screenshot narrative

The current seven-frame narrative is a hypothesis until the research packet and human taste gate are complete. Each frame references a deterministic `captureStateId`; the capture harness and compositor must implement those IDs rather than hand-authoring screenshots.

The final pipeline is:

```text
product truth + research
        -> storefront registry
        -> deterministic iOS capture
        -> code-rendered composition
        -> claim/privacy/dimension validation
        -> Fastlane metadata and screenshots
        -> App Store Connect
        -> acquisition + activation + revenue outcomes
        -> experiment decision
        -> G-Brain and storefront registry
```

## Delivery status

This foundation ships canonical metadata generation, strict validation, screenshot policy, a first narrative hypothesis, and the release freshness gate.

Still required before calling the storefront system complete:

- G-Brain and `/last30days` research packet;
- deterministic `StorefrontDemoMode` and capture-state harness;
- GPT Image 2 comparison board and approved visual direction;
- code-rendered compositor and visual-diff gallery;
- App Store Connect analytics ingestion;
- Product Page Optimization and Custom Product Page experiment automation.
