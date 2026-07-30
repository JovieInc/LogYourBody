# Apple storefront platform contract

Verified: 2026-07-29

This file records the platform facts that the storefront generator and validator currently enforce. Apple documentation is authoritative; practitioner advice may inform later experiments but must not override these constraints.

| Signal | Source | Recency | Authority | Confidence | Product implication | Action |
|---|---|---:|---:|---:|---|---|
| App name is 2–30 characters; subtitle is at most 30 characters. | [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) | Verified 2026-07-29 | Apple | High | These fields are hard limits, not creative guidelines. | Validate character counts before generation. |
| Promotional text is at most 170 characters; description and What’s New are at most 4,000 characters. | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) | Verified 2026-07-29 | Apple | High | Over-limit copy must never reach Fastlane. | Validate character counts for every locale. |
| Keywords are limited to 100 bytes, must be longer than two characters, and should not repeat app-name, subtitle, company-name, category, plural, or filler terms. Competing app names and unauthorized trademarks are prohibited. | [App Store search](https://developer.apple.com/app-store/search/) and [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) | Verified 2026-07-29 | Apple | High | Keyword allocation is a constrained search-intent problem. | Validate UTF-8 bytes, formatting, duplicates, and indexed-word waste. Keep third-party trademarks out of the keyword field. |
| Search results can show the name, subtitle, rating, and up to three screenshots or previews. | [App Store search](https://developer.apple.com/app-store/search/) | Verified 2026-07-29 | Apple | High | The opening three frames must work as a complete conversion story. | Treat frames 1–3 as one required narrative unit. |
| One to ten screenshots are accepted per device size and localization. Screenshots must be RGB PNG or JPEG without transparency. | [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) | Verified 2026-07-29 | Apple | High | Screenshot count, dimensions, and alpha are release-blocking properties. | Parse PNG headers and fail invalid assets before Fastlane. |
| Current 6.9-inch portrait sizes are 1260×2736, 1290×2796, or 1320×2868. Apple also accepts 6.5-inch fallbacks including 1242×2688 and 1284×2778. | [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) | Verified 2026-07-29 | Apple | High | Existing 1242×2688 capture remains valid, but the new canonical capture should use a current 6.9-inch export. | Accept the current fallback while making 1320×2868 the preferred target. |
| Product Page Optimization supports up to three treatments per test, runs for at most 90 days, and evaluates conversion lift and confidence. Apple recommends waiting for at least 90% confidence before applying a result. | [Create a test](https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/create-a-test/) and [Product Page Optimization](https://developer.apple.com/app-store/product-page-optimization/) | Verified 2026-07-29 | Apple | High | Low-volume tests must be allowed to end inconclusive rather than forcing a winner. | Record baseline, treatments, confidence, duration, and winner/loser/inconclusive state. |
| An app can have up to 70 Custom Product Pages with localized screenshots, previews, promotional text, keywords, and unique URLs. Page metrics appear after at least five first-time downloads. | [Configure multiple product page versions](https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions) | Verified 2026-07-29 | Apple | High | Capacity is not a mandate to create dozens of weak pages. | Start with only the highest-confidence intent pages and require unique keyword assignments. |
| App Analytics exposes impressions, product-page views, downloads, conversion rate, source, proceeds, and paying users. | [App Analytics](https://developer.apple.com/app-store-connect/analytics/) and [Analytics dashboard](https://developer.apple.com/help/app-store-connect-analytics/overview/analytics-dashboard) | Verified 2026-07-29 | Apple | High | Store conversion must be joined to downstream activation and revenue before declaring a business winner. | Use first-time-download conversion as the acquisition objective, with paid conversion, retention, refunds, and stability as guardrails. |
| App tags are generated from en-US metadata using models and human curation and currently display in the United States. | [Manage app tags](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-tags/) | Verified 2026-07-29 | Apple | High | Metadata also influences glanceable tag assignment. | Review generated tags in App Store Connect as part of each listing release. |

## Current implementation decisions

- Preferred screenshot target: `1320x2868`.
- Existing `1242x2688` iPhone screenshot remains an accepted transition fallback.
- Final product UI must be a real-app capture with deterministic, synthetic demo data.
- Screenshot blobs are provenance-tracked in the generated storefront manifest.
- GPT Image 2 is pinned for art direction and non-semantic visual layers only; it cannot generate product UI, copy, device geometry, or body-transformation proof.
- The keyword field is mechanically deduplicated against the app name, subtitle, and company name. Market-volume and customer-language ranking remains subject to the required G-Brain and `/last30days` research packet.

## Evidence still required locally

The connected implementation session cannot access the machine-local G-Brain database or execute the Claude `/last30days` runtime. Before approving final positioning, keywords, screenshot copy, or visual direction, the Codex/Hermes workflow must preserve:

- G-Brain queries and returned decision IDs;
- raw `/last30days` outputs for the required sweeps;
- named-competitor follow-up sweeps;
- conflict resolution and accepted decisions;
- writeback IDs for new durable decisions.
