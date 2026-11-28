# Home photo visibility and unset preferences (LYB-320, LYB-366)

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
The October 28 Home, the user's body through time, uses this same chosen wireframe when a
photo is absent or the user has hidden photos.

## Unset preferences (LYB-366)

Recorded: 2026-11-11. Parent: LYB-311.
Status: recommended default adopted; no override.

When no photo/privacy view preference is set and an authentic photo exists,
Home's body stage shows the latest on-device photo for the selected date. An
explicit saved non-photo preference takes precedence, even when a newer photo
exists. Showing the photo does not require a wireframe choice.

Male or female wireframe presentation requires an explicit saved user choice.
Do not infer that choice from a name, photo, or measurement. Until the user
chooses, show no sexed wireframe; do not default an unset choice to male or
female. This supersedes LYB-324's earlier male default for an unset Home
wireframe presentation.

This follows the brand ethos's user-agency constraint: an authentic capture may
answer the default view without assigning a sexed illustration to the user.
The presentation resolver and Home stage UI follow this decision in their own
implementation slices, behind a Statsig gate defaulted off. LYB-87 retains
ownership of the empty stage and first-photo repair, including when no photo
may be shown and no explicit wireframe choice is stored.

## Boundary

This records visibility only; it does not implement or verify native behavior.
Existing storage consent, storage, deletion, telemetry schemas, LYB-87
empty-stage and first-photo repair, and JOV-6016 timeline selection remain with
their current owners. Native app source, photo fixtures, and health fixtures
are unchanged. LYB-85, JOV-6014, and all other LYB-311 work remain outside this
slice.

For LYB-366, run from the repository root before handoff:

```sh
git diff --check
git diff --exit-code origin/main -- . ':(exclude)docs/product/home-photo-visibility.md' ':(exclude)docs/product/selfie-background-wireframe.md'
```

The second check fails on any tracked change outside these two decision
documents, including application source, image or health fixtures, and
telemetry schemas. The appearance document only replaces its conflicting
unset male default with this decision.
