import { isEligibleVariant, type CatalogEquipment, type CatalogVariant } from './catalog';
import {
  effectiveTrainingFeedback,
  hasConflictingFeedbackAtSameTime,
  latestFeedbackPerSession,
} from './engine';
import type { TrainingFeedback } from './types';

export type AlternativeReport = {
  /** Exact catalog variant provoking non-pain back/trunk fatigue. */
  exerciseId: string;
  feedback: readonly TrainingFeedback[];
  /** Applied swaps, not merely candidates. Tolerance must also be observed below. */
  previousSwaps: readonly { fromExerciseId: string; toVariantId: string }[];
  excludedConcerns?: readonly string[];
  /** A request alone is not evidence of tolerance and never changes eligibility. */
  beltRequested?: boolean;
};

export const ALTERNATIVE_REASONS = [
  'supported_exercise_previously_tolerated',
  'supported_setup_previously_tolerated',
] as const;

export type AlternativeOption = {
  variantId: string;
  reason: (typeof ALTERNATIVE_REASONS)[number];
};

export type AlternativeSuggestions = {
  status: 'suggested' | 'not_enough_evidence' | 'no_eligible_alternative';
  differentExercise: AlternativeOption | null;
  sameExerciseSetup: AlternativeOption | null;
};

/** Two separate sessions are a conservative evidence floor, not a clinical threshold.
 * Use the latest sessions so an older success cannot override persistent fatigue.
 * Exercise identity must be explicit: session-level feedback cannot qualify a swap.
 */
function repeatedResponse(
  feedback: TrainingFeedback[],
  exerciseId: string,
  response: (observation: TrainingFeedback) => boolean,
): boolean {
  const scoped = feedback.filter((item) => item.context?.exerciseId === exerciseId);
  const latest = latestFeedbackPerSession(scoped).slice(0, 2);
  return (
    latest.length === 2 &&
    latest.every(
      (item) =>
        Boolean(item.sessionId) &&
        Number.isFinite(Date.parse(item.createdAt)) &&
        !item.transcriptionUncertain &&
        !hasConflictingFeedbackAtSameTime(item, scoped) &&
        !item.interpretations?.some(
          (claim) => claim.timeframe === 'historical' || claim.conflictsWithObservationIds?.length,
        ) &&
        (item.jointPain ?? 0) === 0 &&
        !item.symptomFlags?.length &&
        response(item),
    )
  );
}

/** Pure, advisory selection for non-pain trunk fatigue. Never edits the library,
 * deletes a muscle's exercises, applies a swap, or invents a setup/equipment item.
 * The caller supplies the ACTIVE gym inventory, not a historical gym preset.
 */
export function suggestAlternatives(
  report: AlternativeReport,
  library: readonly CatalogVariant[],
  equipment: ReadonlySet<CatalogEquipment>,
): AlternativeSuggestions {
  const result: AlternativeSuggestions = {
    status: 'not_enough_evidence',
    differentExercise: null,
    sameExerciseSetup: null,
  };
  const feedback = effectiveTrainingFeedback([...report.feedback]);
  if (
    !repeatedResponse(
      feedback,
      report.exerciseId,
      (item) => (item.trunkFatigue ?? 0) > 0 || item.supportingReadiness?.trunk === 'limited',
    )
  )
    return result;

  result.status = 'no_eligible_alternative';
  const current = library.find((variant) => variant.id === report.exerciseId);
  if (!current) return result;
  const baseExerciseId = current.setupOf ?? current.id;
  const previousSwaps = new Set(
    report.previousSwaps
      .filter((swap) => swap.fromExerciseId === current.id)
      .map((swap) => swap.toVariantId),
  );
  const candidates = library
    .filter(
      (variant) =>
        variant.id !== current.id &&
        variant.primaryMuscle === current.primaryMuscle &&
        variant.substitutionEligible !== false &&
        variant.torsoSupport === 'supported' &&
        variant.trunkDemand.level === 'low' &&
        variant.trunkDemand.basis === 'reviewed' &&
        previousSwaps.has(variant.id) &&
        isEligibleVariant(variant, {
          available: equipment,
          excludedConcerns: report.excludedConcerns,
        }) &&
        repeatedResponse(
          feedback,
          variant.id,
          (item) => item.trunkFatigue === 0 && item.supportingReadiness?.trunk !== 'limited',
        ),
    )
    // Code-point ordering is independent of the host's locale and input ordering.
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  for (const variant of candidates) {
    if ((variant.setupOf ?? variant.id) === baseExerciseId) {
      result.sameExerciseSetup ??= {
        variantId: variant.id,
        reason: 'supported_setup_previously_tolerated',
      };
    } else {
      result.differentExercise ??= {
        variantId: variant.id,
        reason: 'supported_exercise_previously_tolerated',
      };
    }
  }
  if (result.differentExercise || result.sameExerciseSetup) result.status = 'suggested';
  return result;
}
