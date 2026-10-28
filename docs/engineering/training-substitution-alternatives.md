# Back/trunk fatigue alternatives (LYB-256)

`suggestAlternatives(report, library, equipment)` in
`apps/web/src/lib/training/substitutions.ts` is a pure, proposal-only engine
function. Pass the existing exercise catalog, account-scoped feedback and the
active gym's resolved equipment set. It returns at most one `differentExercise`
and one `sameExerciseSetup`, with strings from `ALTERNATIVE_REASONS`.

Catalog IDs remain the exact variant/history identity. The optional
`setupForExerciseId` explicitly links `lying_dumbbell_curl` to `dumbbell_curl`
and `supported_cable_curl` to `cable_curl`. Other IDs remain distinct exercises;
names, support and target muscle never establish same-exercise identity.
Incline dumbbell and machine preacher curls are distinct exercise alternatives.

The latest two distinct sessions must explicitly report back/trunk fatigue on
the current variant. A candidate must be supported, target the same muscle,
pass the shared `isEligibleVariant` equipment/concern filter, and belong to a
previously successful swap from this exact variant. It also needs two distinct
sessions reporting zero trunk fatigue and full usable ROM. Zero **reported
fatigue** does not establish zero spinal loading, safety or a growth advantage.
This is a conservative evidence sufficiency rule, not a physiological threshold.

Missing feedback, single-session reports, uncertain transcripts, historical
interpretations and uncorrected conflicting responses cannot establish repeated
tolerance. Existing feedback correction/source deduplication applies before
session aggregation. Newer failed/unknown responses cannot be hidden by older
successes. Floor-limited ROM and explicitly blocked variants exclude those
setups. A belt request cannot override the reported response or equipment filter.
Ties between qualifying candidates resolve by catalog ID, independent of input
ordering. Input objects and the library remain unchanged.

An empty result never deletes a movement or removes training for a muscle.
`not_enough_evidence` abstains from a recommendation;
`no_feasible_alternative` leaves the existing exercise untouched. Pain/medical
pathways, swap approval/application, persistence and UI remain with LYB-176.
This slice adds no API, automatic prescription change or user-visible rollout.
Any future caller must use the existing gated coach/revision path.

Dependency reconciliation: LYB-255 / PR #1559 was in review when this slice
started. It adds strict catalog schemas and curated support/ROM annotations;
this slice reuses the current setup and eligibility fields. When integrating
the two, retain optional `setupForExerciseId` in `catalogVariantSchema` so strict
parsing preserves these two explicit relationships. No tag text is parsed as
an exercise identity, observed response or eligibility override.

Table-driven regression cases are in `substitutions.test.ts`. Real-device and
TestFlight acceptance remains with LYB-176.
