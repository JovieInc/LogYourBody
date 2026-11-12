# Body-composition and 3D visual claims (LYB-322, LYB-368)

Recorded: 2026-10-31. Parent: LYB-311.
Status: recommended default adopted for this decision-only slice; no override.

## Decision

No. Home, shape controls, and any later 3D view must follow this claims rule:

- Shape sliders are not body-fat percentages. Adiposity, muscularity, and
  proportions remain independent artistic parameters, with no unique mapping to
  body-fat percentage. Do not label or interpret a slider value or rendered shape
  as a calibrated composition measurement or estimate.
- FFMI is a derived value, not independent evidence of body composition. Do not
  use it to corroborate its own inputs, validate a shape-to-percentage mapping,
  or increase confidence as though it were a separate measurement.
- The UI makes no measurement accuracy or clinical accuracy claim, no 3D fidelity
  claim, and no weekly-sensitivity claim. A rendered shape or visual difference
  must not be presented as proof of week-to-week physical change.
- Calibrated composition visuals and Gaussian rendering remain unpromoted until
  their respective evidence gates pass. LYB-319 can cache an on-device photo
  texture behind its own gate. That cache is not a measurement, and this
  decision supplies no validation or approval for either capability or for
  later accuracy claims.

This follows the [brand ethos](brand-ethos.md),
[evidence standard](evidence-and-recommendation-standard.md), and
[claims policy](../compliance/claims-policy.md). Existing numerical values must
retain their source and measured, estimated, or interpolated status; a visual
does not supply additional evidence.

## Boundary

This records the claims boundary only. Numerical evidence and fusion remain with
JOV-6014. Import work in LYB-80, LYB-81, and LYB-171, and all other LYB-311 work
remain outside this slice.

## Implementation note (LYB-318, 2026-11-02)

[Body-shape calibration](body-shape-calibration.md) keeps this boundary in the
native wireframe and bucket avatar. The illustrative tier is the only promoted
tier. Higher tiers stay closed, and a body-fat percentage does not select the
picture.

## Home claims decision (LYB-368)

Recorded: 2026-11-11. Parent: LYB-311.
Status: recommended default adopted for this decision-only slice; no override.

**Mission:** Define what Home body visuals may say or store.
**Audience:** Parameter-model and Home stage implementers and reviewers.

**Question:** Which claims about body-fat, FFMI, weekly change, and 3D or Gaussian fidelity may this program show or store?

**Answer:** Make none of the generated visuals a measurement claim. Apply these limits to displayed copy and persisted classifications alike:

| Subject                                                                                  | May show or store                                                                                                                                            | Claim limit                                                                                                                                               |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Authentic photo                                                                          | The user's actual dated capture, with the existing alignment and background treatment.                                                                       | No body reshaping, synthesized hidden anatomy, or implied body-composition measurement.                                                                   |
| Artistic wireframe                                                                       | A generic, non-photoreal illustration with independent adiposity, muscularity, and proportion controls. Label it illustrative.                               | Body-fat does not uniquely set appearance. Slider values and rendered shapes are not body-fat percentages or measured anatomy.                            |
| Body-fat                                                                                 | Existing numerical observations or estimates with their source, date, uncertainty, and measured, estimated, interpolated, or self-reported status preserved. | A photo, slider, or wireframe supplies no new body-fat observation, calibrated mapping, or accuracy claim. Evidence classification remains with JOV-6014. |
| FFMI                                                                                     | A derived value with lineage to its fat-free-mass and height inputs.                                                                                         | FFMI computed from the same inputs is not independent evidence, an extra confidence vote, or validation of a body shape.                                  |
| Weekly change                                                                            | Comparisons of eligible dated numerical observations under JOV-6014's evidence rules; authentic photos remain dated visual records.                          | Rendered differences do not prove weekly physical change or weekly sensitivity. Capture noise and model or calibration changes are not progress.          |
| Interpolated frames                                                                      | A derived transition between comparable saved endpoints, explicitly classified as interpolation with endpoint lineage.                                       | An in-between frame is not a new observation, a measurement on a missing date, or evidence of weekly change.                                              |
| Calibrated composition, personalized 3D, third-party body meshes, and Gaussian rendering | No promotion in this program. Existing experimental records retain their estimate or derived-artifact status and provenance.                                 | No calibrated-composition, personalized-anatomy, clinical-accuracy, or 3D-fidelity claim. Rendering realism supplies no measurement evidence.             |

Measured values, estimates, illustrations, population references, and user-selected targets remain distinct. A derived visual must not be stored as a measured observation or feed back as independent evidence. Existing [snapshot lineage and representation rules](../engineering/body-visualization-snapshots.md) apply; this decision adds no schema or storage path.

### Evidence gate and fallback

The [calibration record](body-shape-calibration.md) passes only the illustrative tier. Personalized shape estimates, calibrated composition, and longitudinal interpretation remain closed. The [personal 3D engine](personal-3d-engine.md) remains disabled for production, and [photographic appearance](photographic-appearance.md) remains unpromoted. Calibrated composition visuals, third-party body meshes, personalized 3D, and Gaussian rendering stay outside this program; earlier experimental implementation does not authorize promotion.

Reconsideration needs a separately scoped decision linking a passed evidence gate for the exact claim, model and calibration version, applicable population, and capture method. The record must retain source provenance, uncertainty, and limitations under the [evidence standard](evidence-and-recommendation-standard.md) and the applicable calibration, engine, or appearance gate. A weekly-sensitivity claim needs its own passed longitudinal gate; an appearance or reconstruction result does not pass it. Passing an appearance gate likewise does not establish body-fat accuracy or observed hidden anatomy. This decision passes no gate and changes no existing threshold.

A feature flag, synthetic fixture, source test, simulator run, vendor demo, or convincing render alone is not a passed evidence gate. Any later user-visible implementation must also follow the existing Statsig rollout rule, default off; flag enablement does not replace evidence.

**Fallback: the authentic photo plus the artistic wireframe.** When any 3D or calibration approach lacks a passed evidence gate, keep the authentic aligned capture where available and the existing generic artistic wireframe for the no-photo state. Preserve the photo's subject pixels and label the wireframe as illustrative. Missing evidence does not justify inventing a measurement or unseen body surface. The photo loop remains independently shippable without a new capture requirement.

### Scope and verification

This is a claims decision for the parameter model and Home stage UI to follow. It changes no application source, package dependencies, model runtimes, feature flags, release dates, or release configuration. Deployment protections remain unchanged. JOV-6014 retains numerical evidence and fusion ownership; LYB-80, LYB-81, and LYB-171 retain imports. Other LYB-311 work remains out of scope.

Run from the repository root against this slice's base:

```sh
git diff --check origin/main
git diff --exit-code origin/main -- . ':(exclude)docs/product/body-composition-visual-claims.md'
```

The second check fails on any tracked change outside this decision record, including application source, dependencies, model runtimes, or release configuration. It verifies diff scope, not clinical validation, a rendered result, or a passed evidence gate.
