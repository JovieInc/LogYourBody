# Body-shape calibration and longitudinal change (LYB-318)

Recorded: 2026-11-02. Parent: LYB-311.

## Result

Only the illustrative wireframe tier passes. A personalized shape estimate, a calibrated composition appearance, and a longitudinal interpretation stay closed. The Home wireframe and the older body-fat bucket picture stay on screen as illustrations. They do not show a body-fat percentage, and a body-fat percentage does not choose the picture.

| Tier                              | Pass | What the UI may say                                                                                                                                                        |
| --------------------------------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Illustrative wireframe            | Yes  | "Illustrative, not body fat." VoiceOver: "Illustrative male/female wireframe. Not a body-fat percentage." or "Illustrative male/female figure. Not a body-fat percentage." |
| Personalized shape estimate       | No   | Nothing. The mapping can run, and the picture does not follow it.                                                                                                          |
| Calibrated composition appearance | No   | Nothing. Out-of-range percentages stay on the illustrative picture.                                                                                                        |
| Longitudinal interpretation       | No   | Nothing. No weekly change claim.                                                                                                                                           |

Failure of a higher tier leaves the illustrative tier in place.

## Families and mapping

Adult male and adult female are the only families. Ages 18 through 80. The numeric gates in `packages/shared-lib/src/body-shape-calibration.ts` and `BodyShapeCalibration.swift` are engineering abstention limits. They are not population norms, user targets, or a licensed scan corpus.

Body-fat percentage alone does not set muscularity, frame, or fat distribution. The same percentage at a different height, mass, or distribution is a different shape parameter set. Values outside a gate abstain. They are not clamped to the nearest extreme.

Fat mass, fat-free mass, lean soft tissue, and skeletal muscle stay separate. Muscularity uses skeletal muscle when that compartment is present and consistent, otherwise lean soft tissue, otherwise fat-free mass minus bone mineral. Fat-free mass alone is not muscle. FFMI uses the existing normalized formula, `fat-free mass / height² + 6.1 × (1.8 − height)`, and is lineage only. A supplied FFMI does not enter the shape.

A DXA observation is comparable only when device, software, and study date are all present and unchanged. Missing provenance raises uncertainty and blocks a calibrated claim.

## Evidence

The fixed corpus is synthetic. Training subjects `T1` and `T2` are disjoint from held-out subjects `H1` through `H8`. Thresholds are declared before that corpus: 30 consented subjects per sex, composition error at most 2 percentage points, same-day shape drift at most 0.05, and at least 20 consented within-person pairs spaced 5 to 9 days inside a study no longer than 9 days. Evaluation does not rewrite those gates.

This run has zero consented or licensed paired scans. The independent synthetic composition error is about 7.2 percentage points. Capture fixtures for repeat, angle, distance, mirror, posture, lighting, clothing, and phone occlusion report alignment error, shape drift, composition error, and same-day longitudinal error as separate fields. Photo reconstruction in this build is unavailable, so a zero drift is not reported for it. Same-day fixture movement is capture noise.

A 151-day series, and a 7-day slice of a 151-day series, are excluded from weekly sensitivity. Cross-sectional pairs are not within-person evidence. A model change from `1.0.0` to `1.1.0` that moves adiposity by −0.12 is quantified and marked not comparable. Apparent progress is empty. No historical shape archive is rewritten.

[3DBODY.TECH abstract 2661](https://www.proc.3dbody.tech/abstracts/2026/2661.html) is male-only CGI stimulus work, not a clinical mapping. [Paper 2629](https://www.proc.3dbody.tech/papers/2026/2629.pdf) uses standardized capture on a small population over months. [DXA method differences](https://www.nature.com/articles/s41366-026-02148-6) stay source-specific. None of those datasets are bundled.

## Native behavior

`AvatarBodyFatCatalog.match` keeps the sex-specific default asset until the calibrated tier passes. The share badge reads "Illustrative, not body fat." The wireframe shape panel shows the wireframe claim and does not read a body-fat value. This extends the LYB-64 path by keeping `testEmptyPhotoStageOpensAttachSheetForThatDay`.

Source checks are `packages/shared-lib/src/body-shape-calibration.test.ts` and `apps/ios/LogYourBodyTests/BodyShapeCalibrationTests.swift`. Simulator, physical-device, and distributed-build journeys were not run for this revision. The corpus contains no photos and no personal health values.

Claims stay inside [body-composition visual claims](body-composition-visual-claims.md). The wireframe asset stays inside [wireframe avatar family](wireframe-avatar-family.md).
