# Exercise variant metadata (LYB-255)

The training engine's existing `apps/web/src/lib/training/catalog.ts` remains
the exercise library and substitution source. `catalog-variant-seed.json` adds
curated metadata to 25 existing IDs: upper chest, lateral delts, lats, biceps,
triceps and lower body. It adds no exercises or prescriptions. Other catalog
entries remain available with unspecified variant metadata.

`catalogVariantSchema` validates complete entries at load time. The seed schema
rejects duplicate IDs; catalog assembly rejects IDs absent from the existing
library. Objects reject unknown fields, including nested setup and tag fields.

Existing `primaryMuscle` and `muscleContribution` retain the engine's muscle
groups and volume accounting. `variantMetadata.targetRegion` describes the
more specific intended target and must map to the same primary muscle group.
Existing `bodyPosition`, `requires`, `benchAngleDeg` and `pulley` remain the
setup/equipment fields; the extension does not duplicate them.

`variantMetadata.support` means torso contact (`none`, `back`, `chest`). The
older `torsoSupport` field also includes thigh/arm anchoring and continues to
serve existing eligibility/ranking behavior. A thigh pad on a pulldown or an
arm pad on a preacher curl does not constitute back/chest support. A hip thrust
has upper-back contact only, as its caveat states. `romSetupCaveat` records
movement-specific setup/range limitations in curated free text.

`variantMetadata.toleranceTags` has four required, separate editable string
arrays: `axialTrunkFatigue`, `jointDiscomfort`, `stability`, and `rom`. These are
advisory setup annotations, not measurements, symptoms, a combined score or
individual safety assurances. Empty arrays mean unspecified. The schema accepts
user-edited tags independently for each dimension; consumers can validate a
personal copy without mutating the curated defaults. Persistence and editing UI
remain with the parent workstream. Tags do not change eligibility, override
existing exclusions, or authorize prescriptions.

## Dependency reconciliation

Checked Linear and the merged source before implementation on October 25, 2026:

- `LYB-114` owns reported observations in
  `TrainingFeedback` / `TrainingSetContext`: muscle readiness, joint pain, trunk
  fatigue, observed ROM/setup, provenance and corrections. Catalog tags describe
  setup context; they neither duplicate these observation fields nor populate
  them with assumed recovery or comfort.
- `LYB-124` owns approved native training
  component/property/action contracts and rendering. This slice adds no card,
  action, transport, database or native model contract. Future consumers resolve
  metadata through the existing exercise ID rather than creating another library.

## Checks

`catalog.test.ts` validates the complete library and seed, rejects unknown and
invalid fields, checks target/group agreement, and proves the four tag arrays
can be edited independently. Existing catalog/swap tests retain eligibility and
substitution coverage.

The existing `pnpm lint:knowledge` / `pnpm test:knowledge-lint` claims policy
scans every decoded seed string separately, including nested tags. It reuses the
shared medical-claims rules and adds exercise-specific bans for clinical claims,
zero axial/spinal load assurances and numeric SFR text. Regression fixtures
exercise each ban, escaped strings and neighboring disclaimers. These text
checks supplement editorial review; they are not semantic medical certification.

This metadata-only slice adds no visible behavior or new rollout path. Native
cards, personal tag storage, exercise selection changes and real-device
TestFlight evidence remain outside LYB-255 and with their existing owners.
