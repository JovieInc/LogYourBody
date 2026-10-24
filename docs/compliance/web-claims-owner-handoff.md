# LYB-230 web claims handoff

Routing: public website copy owner, through LYB-230. Preserve existing copy
ownership. This is a source review inventory, not a copy rewrite or a claim that
each legacy component is currently reachable on the public homepage.

The claims scanner found the following 11 existing statements at base
`1c2da2e0c`. They are retained unchanged in the reviewed
[baseline](../../scripts/knowledge/web-claims-baseline.json). CI emits warnings
for these occurrences and blocks new, changed, moved or additional findings.
Existing agent and storefront claims remain strict.

| Source                                                      | Existing statements for copy-owner disposition                                                                                         | Count |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ----: |
| `apps/web/src/components/LandingPage.tsx`                   | “Know your genetic potential. Track lean muscle gains without the guesswork.”; “Start Free Trial”                                      |     2 |
| `apps/web/src/components/LandingPageConversionSections.tsx` | “Start Free Trial”; `{APP_CONFIG.trialLengthDays} days free. Then $`; “3-Day Free Trial”; “Start 3-Day Free Trial”; “3-day free trial” |     5 |
| `apps/web/src/components/Prefooter.tsx`                     | “Start Free Trial”                                                                                                                     |     1 |
| `apps/web/src/constants/app.ts`                             | Trial-length text derived from `proPlan.trialDays`, ending in “-day free trial”                                                        |     1 |
| `apps/web/src/app/settings/subscription/page.tsx`           | “Free Trial”; remaining-days sentence describing “your free trial”                                                                     |     2 |

LYB-230 also identifies “fitness journey” in `signup/page.tsx` and
`signin/page.tsx`. Those phrases remain unchanged for the copy owner; they are
editorial review items, not prohibited health claims under the deterministic
rules. The same wording also appears on the subscription page. These routes
are scanned, so adding a prohibited claim there will block CI.

The owner should assess eligibility/provider evidence for trial wording and
the evidence standard for genetic-potential wording, using the
[marketing audit](../audits/marketing-2026-10-14/README.md) and
[claims policy](claims-policy.md). No trial, health, or copy approval is inferred
from inclusion in the baseline. Resolve copy in the owner's separate change;
then remove its resolved findings with the existing baseline updater:

```sh
node packages/shared-lib/scripts/correction-ratchet.mjs --base-ref origin/main --update-baselines
pnpm lint:knowledge
pnpm test:knowledge-lint
```

The updater compares the baseline to the immutable base and cannot add a new
claim allowance. A stale allowance also fails CI, preventing later
reintroduction after an owner resolves a finding.
