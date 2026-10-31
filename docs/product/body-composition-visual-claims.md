# Body-composition and 3D visual claims (LYB-322)

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
  their respective evidence gates pass. This decision supplies no validation or
  approval for either capability or for later accuracy claims.

This follows the [brand ethos](brand-ethos.md),
[evidence standard](evidence-and-recommendation-standard.md), and
[claims policy](../compliance/claims-policy.md). Existing numerical values must
retain their source and measured, estimated, or interpolated status; a visual
does not supply additional evidence.

## Boundary

This records the claims boundary only; it does not implement or verify native
behavior. Numerical evidence and fusion remain with JOV-6014. Import work in
LYB-80, LYB-81, and LYB-171, and all other LYB-311 work remain outside this slice.
