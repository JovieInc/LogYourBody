# Growth reference teardowns and demo drafts

October 16, 2026 · LYB-179 · private preparation, not published or sent.
Authority: [current funnel contract](funnel-evidence-contract.md), LYB-173,
[brand ethos](../product/brand-ethos.md) and
[evidence standard](../product/evidence-and-recommendation-standard.md).

## Five references

Method: read the five first-party pages linked below on October 16. These are
documented product mechanics, not installed-app teardowns, paywall receipts,
clinical evidence, conversion benchmarks or endorsements. The adaptation and
test columns are our hypotheses. No competitor trial or purchase was started.

| Reference and dated primary evidence                                                                                                                                        | Documented mechanic                                                                                                                                                   | LYB hypothesis and bounded test                                                                                                                                                           | Boundary / evidence still missing                                                                                                                    |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Apple Health: view data](https://support.apple.com/en-in/guide/iphone/iphe3d379c32/ios), read Oct 16                                                                       | Summary highlights and trends open into details; trend lines expose direction and duration.                                                                           | Foreground one useful interpretation, retain a provenance/detail tap. In an installed LYB journey, ask whether a user can explain the observation and find its source without more entry. | Documentation only; no measured comprehension or time saved. Follow LYB-173 rather than copying a dashboard full of highlights.                      |
| [Happy Scale](https://happyscale.com/), read Oct 16                                                                                                                         | Moving-average weight trends, conditional predictions and automatic Apple Health weight import.                                                                       | Explain a noisy weigh-in in the context of its trend; let a current import avoid a manual prompt. Compare duplicate prompts and correction success with ingestion owners.                 | Marketing claims do not prove algorithm accuracy or retention. No guaranteed loss, manufactured wins or automatic aesthetic goals.                   |
| [MacroFactor: Weight Trend](https://help.macrofactorapp.com/dashboard/weight_trend), read Oct 16                                                                            | Distinguishes raw scale values from a trend estimate; explains interpolation and direct access to raw entries.                                                        | Preserve measured/estimated/interpolated labels when showing one decision. Have a user inspect and correct a synthetic raw entry without mistaking its trend for a measurement.           | No calorie engine, food logger or copied prescription. Scientific evidence and deterministic authorization remain necessary for LYB guidance.        |
| [Hevy: measurements and progress photos](https://help.hevyapp.com/hc/en-us/articles/35385479603479-Body-Composition-Tracking-Measurements-and-Progress-Photos), read Oct 16 | Dated photo/measurement entries, optional photos without measurements, previous-photo capture overlay and comparison; photos remain private unless externally shared. | Keep optional photos in dated context; verify a synthetic photo attaches to the intended date and compare privately. Reuse existing photo/share owner work.                               | Vendor privacy statement is not an audit of LYB storage. No automatic sharing, contact access, audience construction or second photo implementation. |
| [Bevel: How to View Insights](https://help.bevel.health/en/articles/10437057), page edited Mar 25, read Oct 16                                                              | Recovery/Sleep details expose statistical behavior correlations and explicitly caution against causal interpretation.                                                 | Put uncertainty beside the interpretation and suggest one reversible observation/action. Check whether users understand the limitation before accepting a decision.                       | Correlation is not causation. No medical claim, invented progress or expanding LYB into sleep/nutrition logging.                                     |

## Three exact demo drafts

These are recording scripts, not produced videos or evidence of shipping
behavior. Use a synthetic adult fixture with a user-selected goal, no account
identity and no real health/photos. A screen that does not exist in the exact
installed build must be visibly labeled **Concept** throughout; never splice it
into an unlabeled current-build walkthrough. Keep clips private until factual
claims, permitted imagery and release receipts are checked by existing owners.
No prices, trials, scarcity, medical outcomes or unproven time-saving quantities
appear in the scripts. End cards ask for no referrals or contact information.

### Draft 1 — “What does that number mean?” (20 seconds)

| Time   | Picture / action                                                                                         | Exact narration or on-screen copy                                                                         |
| ------ | -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 0–4s   | Synthetic first-run weight and body-fat inputs; avoid name/profile screens.                              | “A weight alone leaves a question: what makes up that number?”                                            |
| 4–11s  | Current fat/lean reveal, with its measured or estimated body-fat source visible. Pause after the reveal. | “LogYourBody shows fat and lean mass from your weight and body fat. Lean mass includes more than muscle.” |
| 11–16s | Open the existing edit path and return to the same reveal.                                               | “Check the source. Correct an input when you need to.”                                                    |
| 16–20s | Private end card.                                                                                        | “Understand your starting point.”                                                                         |

Proof needed: exact build/commit, manual and denied/empty HealthKit paths,
source labels, Reduce Motion/Dynamic Type and edit/revisit behavior. On the
controlled staff gate, observe only the sanitized generic marker after visible
render, once per flow. Calculation or transition logs are insufficient. The
marker does not prove the viewer understood the result.

### Draft 2 — “Use what is already there” (20 seconds, Concept)

| Time   | Picture / action                                                                             | Exact narration or on-screen copy                                               |
| ------ | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 0–5s   | Persistent Concept label; permissioned synthetic HealthKit fixture imports a current weight. | “Your scale already recorded it.”                                               |
| 5–12s  | One focus card; source and observed date available on tap. No repeat weight form.            | “Use a current measurement when it is available. Keep its source within reach.” |
| 12–16s | Open correction detail, then return.                                                         | “You can inspect it and correct a mistake.”                                     |
| 16–20s | Private Concept end card.                                                                    | “Less repeated entry. You stay in control.”                                     |

Proof needed from LYB-171/81: permitted import, freshness, deduplication,
wrong-date correction, denied/offline/stale fallbacks, installed replay and
actual manual prompts avoided. Do not describe this concept as available until
those owners prove it. This task does not implement or publish it.

### Draft 3 — “One decision, still yours” (25 seconds, Concept)

| Time   | Picture / action                                                                             | Exact narration or on-screen copy                      |
| ------ | -------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| 0–6s   | Persistent Concept label; synthetic goal-relative observation with confidence/source detail. | “Start with what your data can support.”               |
| 6–12s  | One authorized engine-returned recommendation; no invented training quantities.              | “See one useful next step, with the reason behind it.” |
| 12–19s | User chooses defer through the existing composer concept; bounded change receipt visible.    | “Say ‘not yet.’ Keep the plan steerable.”              |
| 19–25s | Show review checkpoint or calm no-action state, then private end card.                       | “A clear decision. Room to change your mind.”          |

Proof needed from coaching owners: source freshness and uncertainty, authorized
engine output, safe deferral/override, durable reversible change receipt, review
checkpoint and installed empty/error/offline replay. No rendered-insight marker,
chat response or animation certifies coaching activation or customer benefit.

## Closeout boundaries

No campaigns, messages, invites, uploads to providers, new vendors, credentials,
price/trial changes, purchases, paid creative or outreach were performed. The
older growth-playbook creator budget and proposed premium packages remain
research. Commissioned Statsig delivery, RevenueCat/Neon receipts, exact native
runner coverage and installed/TestFlight acceptance are separate missing
evidence; these drafts and source observations cannot close LYB-179.
