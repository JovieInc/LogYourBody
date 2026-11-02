# LYB-313 body-preserving photo presentation

Home's existing 4:5 stage (LYB-79) now mattes the person, draws a token frame behind them, and aligns compatible dates with one similarity. The source photograph is never rewritten. A cross-dissolve is a view over two captures, not a new photo.

## What the stage does

- Segmentation stays on Apple Vision through `BackgroundRemovalService`. The mask is copied into a value grid. No second segmentation provider was added.
- Subject pixels at mask confidence 128 or above are copied unchanged. The background is dimmed and desaturated on its own. Hair just beside the body (64–127) is kept. A small interior hole, such as a phone, is filled so the original pixels show. A hole larger than 8% of the mask, a low-confidence mask, a cropped-off wrist, or an unsupported crop falls back to the intact photograph and can be retried.
- The frame uses the Home tokens: 8pt overlap, 12pt inset, 12pt radius, 2pt stroke at 35% white. Stroke pixels are background only, so the person paints over the frame.
- Registration is translation, rotation, and one positive scale from the torso segment. Shoulder width classifies front versus side and never changes scale. Front versus side, a mirror disagreement, missing landmarks, or an extreme crop stays an honest side-by-side comparison and keeps both photos' metadata.
- The single-photo stage crop is still translation plus uniform aspect-fill. Pairwise rotation is only the comparison derivative.
- Scrubbing reads a prepared target-sized image. It does not segment or decode. When the selection settles, the previous and next photos are prepared into an in-memory cache of five derivatives. Thumbnails under 120pt keep the shared plate and do not enter that cache.
- Dates on the timeline and in compare stay the real capture dates. `BodyPhotoCaptureLog` does not append a transition.

Derivatives live in memory for the session. Durable mask files stay with the existing photo store. Private photos and health values are not fixtures.

## Tests

`BodyPhotoPresentationTests` and `BodyPhotoAlignmentTests` (both on the LogYourBodyTests target, journey 9; alignment cases are their own suite in `BodyPhotoPresentationTests+Alignment.swift`):

- Subject color is unchanged across four skin tones and three sizes.
- Background dim and the frame stroke do not rewrite the source or the subject.
- A 2×2 occlusion hole keeps the black source pixel.
- Low confidence, a large hole, a missing wrist, and an unsupported crop retry with the intact photo.
- A partial body and a soft hair edge keep their silhouette width.
- Torso length sets scale; shoulder width and axis lengths stay uniform; a rotation is one similarity.
- Pose, mirror, and crop mismatches stay honest and keep metadata.
- Stage registration lands the torso without using shoulder width.
- A cross-dissolve keeps both endpoints and is not a capture.
- A scrub frame does no segmentation or full-resolution decode, and the adjacent cache stays bounded.
- Frame constants match `HomeV2Tokens`, including a 320×200 short stage.
- `SubjectPlateRenderer.present` keeps subject pixels on a masked plate.
- `SubjectPlateStore.scrubImage` returns only the prepared plate.
- Previews at 28×36 do not take the stage-derivative path.
- An unsupported crop returns the same image instance.
- A synthetic mirror selfie keeps the phone pixel inside a small hole.

## Evidence on this change

Base revision: `8c0e6a2de` (`origin/main` at branch creation). The shipping revision is the commit that adds this note on `grok/lyb-313-20261101t163928`. No Xcode build setting or bundle version was changed. Deployment targets already in the project stay 17.5 and 26.0.

| Check                                                                                                 | Host  | Result                                                                                                                                        |
| ----------------------------------------------------------------------------------------------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `swiftlint lint --strict --no-cache --config apps/ios/.swiftlint.yml` on the nine changed Swift files | Linux | 0 violations. SourceKit rules were skipped (`custom_rules`, `literal_expression_end_indentation`, `statement_position`, vertical whitespace). |
| `node scripts/ios/swift-arch/guard.mjs`                                                               | Linux | 542 baselined violations, none new, 342 files.                                                                                                |
| `git diff --check`                                                                                    | Linux | Clean.                                                                                                                                        |
| Numeric replay of the registration, hole, cache, and short-stage expectations                         | Linux | Matched the assertions. This is not an XCTest run.                                                                                            |
| `xcodebuild` / XCTest / simulator                                                                     | —     | Not run. This host has no Xcode.                                                                                                              |
| Physical device                                                                                       | —     | Not run.                                                                                                                                      |
| TestFlight or other distributed build                                                                 | —     | Not run.                                                                                                                                      |

LYB-64 installed-build certification is unverified until the existing native runner executes `BodyPhotoPresentationTests` on the exact commit. Source tests do not close that receipt. When Vision throws, which the simulator often does, the stage keeps the LYB-79 dimmed plate and does not show a retry. That path is unchanged.

The compare overlay cross-dissolves only when the two views are aligned. The slider and side-by-side controls are unchanged. The timelapse player does not yet crossfade derivatives.
