# Back/trunk fatigue alternatives (LYB-256)

`apps/web/src/lib/training/alternatives.ts` exports the pure function
`suggestAlternatives(report, library, equipment)`. Supply exact catalog variants,
the active gym's concrete equipment set, exercise-scoped `TrainingFeedback`, and
previously applied `{ fromExerciseId, toVariantId }` swaps. A swap record alone
does not prove tolerance.

The result contains a `status` and up to two options: `differentExercise` and
`sameExerciseSetup`, each nullable and containing a catalog `variantId` and fixed
`reason`. Resolve the ID against the supplied library for setup details and cues.
`CatalogVariant.setupOf` explicitly links a setup to its base movement; names do
not establish identity. Floor curl setups honor the `floor_rom_blocked` concern.

Both latest independent sessions must show fatigue for the reported variant.
For each candidate, both latest independent sessions must explicitly report zero
trunk fatigue without limited trunk readiness. This two-session floor is a
conservative engine policy, not a clinical threshold or proof of causality.
Missing, single-session, conflicting, historical or uncertain observations cannot
establish repeated tolerance. Copies and superseded observations add no evidence.
Older successes cannot override newer fatigue. Feedback must identify the exact
exercise variant in `context`.

Candidates must have a recorded swap from the reported variant, the same primary
muscle, reviewed low trunk demand, torso support, and pass the existing equipment
and concern filters. Eligible IDs are sorted by code point for deterministic
selection, independent of library order or host locale. Reasons are limited to
`supported_exercise_previously_tolerated` and
`supported_setup_previously_tolerated`. A belt request adds no tolerance evidence
and does not change the options.

No feedback or insufficient repeated fatigue returns `not_enough_evidence` with
no options. Established fatigue with no eligible tolerated alternative returns
`no_eligible_alternative`. The function never removes exercises or edits the plan,
library, feedback, or inventory. It supplies no pain/medical decision pathway.

This slice adds no endpoint or user-facing activation. Applying suggestions,
confirmation, feature-gated runtime integration and real-device evidence remain
with LYB-176. Existing training gates and swap authorization remain in place.

Scoped validation from the repository root:

```bash
pnpm --filter logyourbody test:watch --watch=false --runInBand --runTestsByPath src/lib/training/alternatives.test.ts src/lib/training/catalog.test.ts
pnpm lint
pnpm typecheck
pnpm test
```
