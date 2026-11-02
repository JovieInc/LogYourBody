/**
 * Body-shape calibration for LYB-318.
 *
 * Artistic sliders and bucket pictures are not body-fat percentages.
 * A plausible shape is not week-to-week change. Thresholds are declared
 * before the corpus and are not fit to held-out rows. The bundled corpus is
 * synthetic. It checks the evaluator. It is not a consented body scan.
 *
 * Fat-free mass, lean soft tissue, and skeletal muscle stay distinct.
 * FFMI is derived lineage only and is never a shape input.
 */

export {
  figureClaim,
  ILLUSTRATIVE_BADGE,
  MODEL_CHANGE_DISCLOSURE,
  MODEL_ID,
  MODEL_VERSION,
  SAME_MODEL_DISCLOSURE,
  families,
  thresholds,
  tolerances,
  wireframeClaim,
  type BodyFamily,
  type CaptureFixture,
  type ChangePair,
  type Distribution,
  type FamilyGate,
  type MuscleSource,
  type Observation,
  type ShapeDecision,
  type ShapeParameters,
} from './body-shape-calibration-types';
export { corpus } from './body-shape-calibration-corpus';
export {
  compareModelVersions,
  derivedFfmi,
  displayedBucket,
  dxaKey,
  mapObservation,
  readBackBodyFatPercent,
  rmsShape,
  weeklyClaimAllowed,
  type ModelComparison,
} from './body-shape-calibration-map';
export { evaluate } from './body-shape-calibration-evaluate';
