import { isEligibleVariant, type CatalogEquipment, type CatalogVariant } from './catalog';
import { effectiveTrainingFeedback } from './engine';
import type { TrainingFeedback } from './types';

export const ALTERNATIVE_REASONS = {
  differentExercise:
    'A supported exercise for the same muscle was tolerated across repeated sessions.',
  sameExerciseSetup: 'A supported setup of this exercise was tolerated across repeated sessions.',
  notEnoughEvidence: 'Not enough evidence.',
  noFeasibleAlternative: 'No supported alternative fits the equipment and recorded constraints.',
} as const;

export type AlternativeReport = {
  /** Exact catalog variant on which back/trunk fatigue was reported. */
  variantId: string;
  feedback: readonly TrainingFeedback[];
  /** Previously successful, user-confirmed swaps; approval alone is not tolerance evidence. */
  successfulSwaps: readonly { fromVariantId: string; toVariantId: string }[];
  blockedVariantIds?: readonly string[];
  excludedConcerns?: readonly string[];
};

export type ExerciseAlternative = {
  variantId: string;
  exerciseId: string;
  reason:
    typeof ALTERNATIVE_REASONS.differentExercise | typeof ALTERNATIVE_REASONS.sameExerciseSetup;
};

export type AlternativesResult =
  | {
      kind: 'suggested';
      differentExercise: ExerciseAlternative | null;
      sameExerciseSetup: ExerciseAlternative | null;
    }
  | {
      kind: 'not_enough_evidence' | 'no_feasible_alternative';
      reason:
        | typeof ALTERNATIVE_REASONS.notEnoughEvidence
        | typeof ALTERNATIVE_REASONS.noFeasibleAlternative;
      differentExercise: null;
      sameExerciseSetup: null;
    };

const exerciseId = (variant: CatalogVariant) => variant.setupForExerciseId ?? variant.id;
const observedAt = (row: TrainingFeedback) => Date.parse(row.observedAt ?? row.createdAt);

function usableObservation(row: TrainingFeedback): boolean {
  return (
    Number.isFinite(observedAt(row)) &&
    !row.transcriptionUncertain &&
    !row.interpretations?.some((claim) => claim.timeframe === 'historical') &&
    !(row.jointPain !== undefined && row.jointPain > 0) &&
    !row.symptomFlags?.length &&
    row.trunkFatigue !== undefined &&
    Number.isFinite(row.trunkFatigue) &&
    row.trunkFatigue >= 0 &&
    row.trunkFatigue <= 10
  );
}

/** A session is one evidence unit, regardless of set count or repeated reports.
 * Evaluate the latest two sessions before filtering their outcomes so a newer
 * failed/unknown response cannot be hidden by older successful experiences.
 * Conflicting uncorrected reports within a session cannot establish tolerance. */
function repeatedResponse(
  observations: readonly TrainingFeedback[],
  variant: CatalogVariant,
  response: (row: TrainingFeedback) => boolean,
): boolean {
  const sessions = new Map<string, TrainingFeedback[]>();
  for (const row of observations) {
    if (row.context?.exerciseId !== variant.id) continue;
    sessions.set(row.sessionId, [...(sessions.get(row.sessionId) ?? []), row]);
  }
  const recent = [...sessions.values()]
    .sort((a, b) => Math.max(...b.map(observedAt)) - Math.max(...a.map(observedAt)))
    .slice(0, 2);
  return (
    recent.length === 2 &&
    recent.every((session) =>
      session.every(
        (row) =>
          usableObservation(row) &&
          (!row.targetMuscle || row.targetMuscle === variant.primaryMuscle) &&
          response(row),
      ),
    )
  );
}

/** Pure suggestions only: never deletes an exercise, changes a prescription,
 * infers spinal loading from reported fatigue, or handles pain/medical decisions.
 * Callers supply account-scoped, current feedback and the active gym's inventory.
 */
export function suggestAlternatives(
  report: AlternativeReport,
  library: readonly CatalogVariant[],
  equipment: ReadonlySet<CatalogEquipment>,
): AlternativesResult {
  const empty = (kind: 'not_enough_evidence' | 'no_feasible_alternative'): AlternativesResult => ({
    kind,
    reason:
      kind === 'not_enough_evidence'
        ? ALTERNATIVE_REASONS.notEnoughEvidence
        : ALTERNATIVE_REASONS.noFeasibleAlternative,
    differentExercise: null,
    sameExerciseSetup: null,
  });
  const current = library.find((variant) => variant.id === report.variantId);
  const observations = effectiveTrainingFeedback([...report.feedback]);
  if (!current || !repeatedResponse(observations, current, (row) => row.trunkFatigue! > 0))
    return empty('not_enough_evidence');

  const successful = new Set(
    report.successfulSwaps
      .filter((swap) => swap.fromVariantId === current.id)
      .map((swap) => swap.toVariantId),
  );
  const blocked = new Set(report.blockedVariantIds ?? []);
  const candidates = library
    .filter(
      (variant) =>
        variant.id !== current.id &&
        variant.primaryMuscle === current.primaryMuscle &&
        variant.torsoSupport === 'supported' &&
        variant.substitutionEligible !== false &&
        successful.has(variant.id) &&
        !blocked.has(variant.id) &&
        isEligibleVariant(variant, {
          available: equipment,
          excludedConcerns: report.excludedConcerns,
        }) &&
        repeatedResponse(
          observations,
          variant,
          (row) => row.trunkFatigue === 0 && row.context?.rangeOfMotion === 'full',
        ),
    )
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const option = (sameExercise: boolean): ExerciseAlternative | null => {
    const variant = candidates.find(
      (candidate) => (exerciseId(candidate) === exerciseId(current)) === sameExercise,
    );
    return variant
      ? {
          variantId: variant.id,
          exerciseId: exerciseId(variant),
          reason: sameExercise
            ? ALTERNATIVE_REASONS.sameExerciseSetup
            : ALTERNATIVE_REASONS.differentExercise,
        }
      : null;
  };
  const differentExercise = option(false);
  const sameExerciseSetup = option(true);
  if (!differentExercise && !sameExerciseSetup) return empty('no_feasible_alternative');
  return { kind: 'suggested', differentExercise, sameExerciseSetup };
}
