# Selfie background and wireframe appearance (LYB-324)

Recorded: 2026-11-02. Parent: LYB-311. Informed by the October 28 stage wording and the completed LYB-79 torso baseline.
Status: recommended default adopted for this decision-only slice; no override.

## Decision

**Question:** How subdued should the weekly mirror-selfie background be, and what style should the male and female wireframes use?

**Answer:** Dim and desaturate the separated background so the body stays dominant, and use a non-photoreal wireframe for the saved male or female presentation.

The 4:5 stage keeps the October 28 wording already recorded for Home: a subdued background, consistent framing, and a selectable male or female wireframe. This record adds no stage label.

## Background

On a weekly mirror selfie, separate the room from the person. Subject pixels stay the authentic photograph. The separated background is dimmed and desaturated strongly enough that the body stays dominant and the room no longer competes with it.

Strength matches the plate already saved for that stage:

- The background is blurred, then desaturated to saturation `0.05`, then dimmed to `0.28` of capture brightness (`SubjectPlateRenderer.backgroundSaturation`, `SubjectPlateRenderer.backgroundDim`, blur sigma `width / 24`).
- The person stays at capture sharpness, color, and brightness.
- The room remains that capture's own background. A generated scene does not replace it.

This adopts the saved strength. A second treatment is out of scope.

## Wireframe

When the stage draws a body without showing the authentic photo, draw the non-photoreal wire already saved for the explicit presentation.

- Style is an unfilled, unlit line wire: material `kind` `wire`, `fill` false, lighting `unlit-wire`, on model `lyb.wireframe.torso`.
- Male or female follows the saved presentation `lyb.wireframe.presentation`. An unset value stays the saved default, male. Profile fields and the photograph do not choose it.
- The wireframe uses the same 4:5 stage height as the photo and leaves framing unchanged.

Claims stay inside [body-composition visual claims](body-composition-visual-claims.md). Visibility stays inside [home photo visibility](home-photo-visibility.md). The mesh family stays inside [wireframe avatar family](wireframe-avatar-family.md).

## Authentic photo

Framing stays the completed LYB-79 torso baseline on the 4:5 stage (`HomeV2Tokens.photoAspectRatio` is `4/5`). Registration stays one similarity: translation, rotation, and one positive uniform scale taken from the torso segment. Shoulder width classifies viewpoint and leaves scale unchanged.

The authentic photograph stays unrewritten. These acts stay forbidden on that photo:

- waist reshaping
- physique retouching
- synthesized hidden anatomy

Occluded or out-of-frame body is not invented and painted onto the photograph. A comparison that cannot share one similarity stays an honest side-by-side, as [LYB-313](../engineering/lyb-313-body-photo-presentation.md) already records. This decision does not re-implement LYB-79.

## Boundary

This records the visual rule only. It changes no native app code, shaders, or image assets, and it does not verify a device render. LYB-313 owns the compositor. LYB-314 owns the mesh. LYB-320 owns visibility. LYB-321 owns reconstruction consent. LYB-322 owns visual claims. All other LYB-311 work stays outside this slice.
