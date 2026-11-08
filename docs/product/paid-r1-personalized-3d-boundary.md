# Paid R1 boundary for personalized 3D (LYB-326)

Recorded: 2026-11-02. Parent: LYB-311.
Status: recommended default adopted for this decision-only slice; no override.

## Decision

**Question:** Do personalized 3D, calibrated composition, or Gaussian rendering enter or gate paid R1?

**Answer: No.** Apply the issue's authorized default. No override is recorded.

Personalized 3D, calibrated composition visuals, and photographic or Gaussian
rendering stay outside paid R1 and outside the October 16 release blockers.
Advanced 3D stays outside paid R1 and outside those blockers with them.

Paid R1 remains the body timeline, Stats, and imports. Timeline, Stats, and
imports stay independently shippable. The current
[roadmap](../product-development-roadmap.md) line stands: Paid R1 has no
mandatory composer, chat, or advanced-3D dependency.

This record adds no price gate. Release dates, issue owners, in-flight
branches, and deployment protections stay as they are.

Later visual claims stay inside
[body-composition visual claims](body-composition-visual-claims.md).
Reconstruction consent stays inside
[LYB-321](../architecture/body-reconstruction-consent.md).

## Boundary

This records the release boundary only. It changes no native app code, feature
flags, store configuration, or release-lifecycle settings.

LYB-64 and LYB-45 keep certification and installed-build ownership. JOV-6016
remains the timeline owner. LYB-173 remains the product behavior and
release-sequencing contract. LYB-80, LYB-81, LYB-171, and the rest of LYB-311
stay outside this slice.
