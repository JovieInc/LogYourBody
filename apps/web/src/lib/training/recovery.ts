import { CONTROLLER_POLICY } from './controller';
import { effectiveTrainingFeedback, hasConflictingFeedbackAtSameTime } from './engine';
import type { ExercisePrescription, MuscleGroup, SetLog, TrainingFeedback } from './types';

/** Reuses the shipped recovery reduction dose, not a new personal volume landmark.
 * No reviewed increase increment/cap exists in this revision. Only escalation is disabled. */
export const RECOVERY_POLICY = {
  version: 'adaptive-recovery-v1',
  reducedSets: 1,
  repeatedDeclineCount: CONTROLLER_POLICY.declineInvestigationCount,
  highSoreness: CONTROLLER_POLICY.deloadSorenessThreshold,
  evidenceIds: ['k:76bf778c', 'k:b1e1dc5b', 'k:e95f2199', 'k:0b3ea5bb'],
  increaseBounds: null,
} as const;

export type RecoveryAction =
  | 'hold'
  | 'propose_increase'
  | 'reduce'
  | 'respace'
  | 'substitute'
  | 'recovery_review'
  | 'insufficient_evidence';
export type RecoveryExposure = {
  sessionId: string;
  prescription: ExercisePrescription;
  completed: SetLog[];
};
export type RecoveryEvaluation = {
  action: RecoveryAction;
  rationale: string;
  uncertainty: 'moderate' | 'high';
  evidenceIds: string[];
  observationIds: string[];
  completedSetIds: string[];
  comparableSessionIds: string[];
  change: { kind: 'sets'; from: number; to: number } | null;
  parameterProposal: {
    status: 'needs_policy_review';
    scope: 'side_delt_specialization';
    missing: string[];
    evidenceIds: string[];
  } | null;
};

function local(observation: TrainingFeedback, muscle: MuscleGroup) {
  // Session-level reports cannot establish readiness of a particular muscle.
  return observation.muscles?.[muscle];
}

function relevant(observation: TrainingFeedback, muscle: MuscleGroup, exerciseId: string) {
  return (
    (!observation.context?.exerciseId || observation.context.exerciseId === exerciseId) &&
    (!observation.targetMuscle || observation.targetMuscle === muscle)
  );
}

/** Compare the corresponding FIRST work set across sessions. Losing reps later
 * in one session is not between-session deterioration. Setup/effort/rest/order
 * must be known and equal; a different machine or effort is a new context. */
function comparable(
  left: RecoveryExposure,
  right: RecoveryExposure,
  observations: TrainingFeedback[],
) {
  const first = (exposure: RecoveryExposure) =>
    exposure.completed.find((log) => log.setNumber === 1);
  const a = first(left);
  const b = first(right);
  const context = (exposure: RecoveryExposure) =>
    observations.find(
      (observation) =>
        observation.sessionId === exposure.sessionId &&
        observation.context?.exerciseId === exposure.prescription.id &&
        observation.context.setNumber === 1,
    )?.context;
  const x = context(left);
  const y = context(right);
  return Boolean(
    a &&
    b &&
    x &&
    y &&
    a.loadKg !== null &&
    a.loadKg === b.loadKg &&
    a.rir === b.rir &&
    left.prescription.id === right.prescription.id &&
    ['setup', 'restSeconds', 'setOrder', 'rangeOfMotion', 'setFormat'].every((key) => {
      const field = key as keyof typeof x;
      return x[field] !== undefined && x[field] !== 'unknown' && x[field] === y[field];
    }),
  );
}

export function evaluateRecovery(input: {
  muscle: MuscleGroup;
  exerciseId: string;
  goal: 'emphasize' | 'grow' | 'maintain';
  exposures: RecoveryExposure[];
  feedback: TrainingFeedback[];
  now: Date;
  deload: boolean;
}): RecoveryEvaluation {
  const exposureIds = new Set(input.exposures.map((item) => item.sessionId));
  const observations = effectiveTrainingFeedback(input.feedback)
    .filter(
      (item) =>
        exposureIds.has(item.sessionId) &&
        relevant(item, input.muscle, input.exerciseId) &&
        !item.interpretations?.some((claim) => claim.timeframe === 'historical'),
    )
    .sort(
      (a, b) =>
        Date.parse(b.observedAt ?? b.createdAt) - Date.parse(a.observedAt ?? a.createdAt) ||
        a.id.localeCompare(b.id),
    );
  const ordered = [...input.exposures]
    .filter((item) => item.completed.length > 0)
    .sort(
      (a, b) =>
        Math.max(...b.completed.map((log) => Date.parse(log.completedAt))) -
        Math.max(...a.completed.map((log) => Date.parse(log.completedAt))),
    );
  const current = ordered[0];
  const observation = current && observations.find((item) => item.sessionId === current.sessionId);
  const result = (
    action: RecoveryAction,
    rationale: string,
    change: RecoveryEvaluation['change'] = null,
  ): RecoveryEvaluation => ({
    action,
    rationale,
    change,
    uncertainty: 'high',
    evidenceIds: [...RECOVERY_POLICY.evidenceIds],
    observationIds: [...new Set(observations.map((item) => item.id))],
    completedSetIds: ordered.flatMap((item) => item.completed.map((log) => log.id)),
    comparableSessionIds: current
      ? ordered
          .filter((item) => comparable(current, item, observations))
          .map((item) => item.sessionId)
      : [],
    parameterProposal: null,
  });
  const symptoms = observations.filter((item) => current?.sessionId === item.sessionId);
  if (symptoms.some((item) => (item.jointPain ?? 0) > 0 || item.symptomFlags?.length))
    return result(
      'recovery_review',
      'Pause the implicated movement and review the reported pain or concerning symptom before another exposure.',
    );
  if (input.deload)
    return result(
      'recovery_review',
      'Deload changes the starting context. Review a new baseline rather than carrying forward a peak dose or escalation.',
    );
  if (!current || !observation)
    return result(
      'insufficient_evidence',
      'Completed work and a current muscle-specific check-in are needed. Missing feedback cannot authorize escalation.',
    );
  const observedAt = Date.parse(observation.observedAt ?? observation.createdAt);
  if (
    !Number.isFinite(observedAt) ||
    observedAt > input.now.getTime() ||
    input.now.getTime() - observedAt > CONTROLLER_POLICY.staleSignalDays * 86400000
  )
    return result(
      'insufficient_evidence',
      'The response observation is stale or future-dated. Obtain current context before changing the dose.',
    );
  if (
    observations.some(
      (item) =>
        hasConflictingFeedbackAtSameTime(item, observations) ||
        observations.some(
          (other) =>
            other.id !== item.id &&
            other.sessionId === item.sessionId &&
            (other.observedAt ?? other.createdAt) === (item.observedAt ?? item.createdAt) &&
            JSON.stringify(other.context) === JSON.stringify(item.context) &&
            JSON.stringify(local(other, input.muscle)) !==
              JSON.stringify(local(item, input.muscle)),
        ) ||
        item.transcriptionUncertain ||
        item.interpretations?.some((claim) => claim.conflictsWithObservationIds?.length),
    )
  )
    return result(
      'insufficient_evidence',
      'Available observations conflict or are uncertain. Hold escalation and clarify only the consequential context.',
    );
  if (observation.generalReadiness === 'limited')
    return result(
      'recovery_review',
      'Whole-body readiness limits training even if the target muscle feels ready. Review recovery work or deload across the plan.',
    );
  const supporting = observation.supportingReadiness;
  const supportingStates = [
    supporting?.grip,
    supporting?.trunk,
    ...Object.values(supporting?.muscles ?? {}),
  ];
  if (supportingStates.includes('limited'))
    return result(
      'substitute',
      'A supporting muscle, grip or trunk is limiting. Use the existing reviewed exercise-selection pathway; do not infer local muscle under-recovery.',
    );
  const signal = local(observation, input.muscle);
  const previous = ordered[1];
  const limited = signal?.recovery === 'limited' || observation.targetMuscleReadiness === 'limited';
  if (!previous || !comparable(current, previous, observations))
    return result(
      limited ? 'respace' : 'insufficient_evidence',
      'Setup, load, effort, rest or order is missing or changed. Hold escalation; offer rest or rescheduling without inferring a recovery-hour constant.',
    );
  const reps = (exposure: RecoveryExposure) =>
    exposure.completed.find((log) => log.setNumber === 1)!.reps;
  const down = reps(current) < reps(previous);
  if (
    (signal?.performance === 'up' && down) ||
    (signal?.performance === 'down' && reps(current) > reps(previous))
  )
    return result(
      'insufficient_evidence',
      'Reported performance conflicts with comparable completed work. Hold escalation pending clarification.',
    );
  const priorObservation = observations.find((item) => item.sessionId === previous.sessionId);
  const repeated =
    signal?.performance === 'down' &&
    local(priorObservation ?? observation, input.muscle)?.performance === 'down' &&
    (signal.soreness ?? -1) >= RECOVERY_POLICY.highSoreness;
  if (down && (limited || repeated) && current.prescription.sets > RECOVERY_POLICY.reducedSets)
    return result(
      'reduce',
      'Unexpected comparable decline with limited local readiness supports a reversible lower-dose trial. This does not establish its cause or permanent capacity.',
      { kind: 'sets', from: current.prescription.sets, to: RECOVERY_POLICY.reducedSets },
    );
  if ((down || limited) && current.prescription.sets <= RECOVERY_POLICY.reducedSets)
    return result(
      'recovery_review',
      'Adverse response persists at the reduced dose. Review recovery sessions, spacing or deload; do not restore a higher dose automatically.',
    );
  if (down || limited)
    return result(
      'respace',
      'Hold escalation and offer additional rest or a later eligible slot. Continued adverse response warrants recovery review, including reducing the existing dose. No exact recovery interval is inferred.',
    );
  if (
    !signal ||
    signal.recovery !== 'ready' ||
    signal.performance === undefined ||
    signal.soreness === undefined ||
    observation.jointPain !== 0 ||
    observation.generalReadiness !== 'ready' ||
    supportingStates.some((value) => value !== 'ready') ||
    (observation.generalExhaustion ?? 0) > 0 ||
    (observation.trunkFatigue ?? 0) > 0 ||
    signal.workload === 'above_expected' ||
    current.completed.length < current.prescription.sets
  )
    return result(
      'insufficient_evidence',
      'Local, supporting-muscle and whole-body tolerance are not all established. Hold the current dose; a positive pump alone cannot authorize more work.',
    );
  const held = result(
    'hold',
    'Comparable performance and tolerance support holding. A new week is a review opportunity, not a mandatory increase.',
  );
  if (
    input.goal === 'emphasize' &&
    ['dumbbell_lateral_raise', 'cable_lateral_raise'].includes(input.exerciseId)
  ) {
    held.parameterProposal = {
      status: 'needs_policy_review',
      scope: 'side_delt_specialization',
      missing: [
        'reviewed set increment',
        'per-person dose cap including overlapping work',
        'trial duration and review bound',
        'time and allocation bounds',
      ],
      evidenceIds: [...RECOVERY_POLICY.evidenceIds],
    };
    held.rationale +=
      ' Side-delt exploration is eligible for policy review; numerical escalation remains disabled until these bounds are reviewed.';
  }
  return held;
}
