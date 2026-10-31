# Home photo visibility (LYB-320)

Recorded: 2026-10-31. Parent: LYB-311. Informed by LYB-173.
Status: recommended default adopted for this decision-only slice.

## Decision

When a latest mirror selfie exists but an explicit saved privacy or view
preference hides photos, Home's 4:5 body stage shows the user's chosen male or
female wireframe. The authentic photo stays hidden even when a newer photo
exists, until the user explicitly opts into showing the photo. Photo recency
does not override that preference.

This follows the [brand ethos](brand-ethos.md)'s user-agency constraint and
retains the [LYB-173 product direction](../product-development-roadmap.md#october-16-supersession-current-product-behavior).

## Boundary

This records visibility only; it does not implement or verify native behavior.
Storage, deletion, LYB-87 empty-stage repair, and JOV-6016 timeline selection
remain with their current owners. LYB-85, JOV-6014, and all other LYB-311 work
remain outside this slice.
