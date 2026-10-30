import {
  catalogVariantById,
  isEligibleVariant,
  resolveAvailableEquipment,
  substitutionCandidates,
  type CatalogEquipment,
} from './catalog';
import { volume_landmarks } from './engine';
import {
  annotationFor,
  gripConflict,
  ruleById,
  sameDayPrimaryOverlaps,
  type DayPart,
  type OptimizerRuleSet,
  OPTIMIZER_RULES,
} from './optimizer-rules';
import { trainingRequestHash } from './revisions';
import { stableTrainingUuid, swappedPrescription } from './service';
import { reviewSessionSequence, sequencingContextSchema, type SequenceReview } from './sequencing';
import {
  rollingScheduleSchema,
  reviewRollingSchedule,
  type RollingScheduleReview,
} from './rolling-schedule';
import {
  MUSCLE_GROUPS,
  type ExercisePrescription,
  type MuscleContribution,
  type MuscleGroup,
  type SetLog,
} from './types';

import { optimizerInputSchema } from './optimizer-schema';
import type {
  OptimizerInput,
  PlanExercise,
  PlanSession,
  SupersetPreference,
} from './optimizer-schema';

export { optimizerInputSchema } from './optimizer-schema';
export type {
  OptimizerInput,
  PlanExercise,
  PlanSession,
  SupersetPreference,
} from './optimizer-schema';

export type ResolvedLocation = {
  id: string | null;
  source: 'user' | 'detected' | 'unknown';
};

type NormalizedInput = Omit<
  OptimizerInput,
  | 'declaredEquipment'
  | 'unavailableEquipment'
  | 'preferences'
  | 'priorityMuscles'
  | 'readiness'
  | 'pain'
  | 'measuredTransitionMinutes'
  | 'considerTimeSupersets'
  | 'requestedSwaps'
  | 'logs'
  | 'targetRir'
  | 'detectedLocationId'
> & {
  sessions: PlanSession[];
  declaredEquipment: string[];
  unavailableEquipment: string[];
  preferences: SupersetPreference[];
  priorityMuscles: MuscleGroup[];
  readiness: NonNullable<OptimizerInput['readiness']>;
  pain: NonNullable<OptimizerInput['pain']>;
  measuredTransitionMinutes: number | null;
  considerTimeSupersets: boolean;
  requestedSwaps: NonNullable<OptimizerInput['requestedSwaps']>;
  logs: SetLog[];
  targetRir: number;
  detectedLocationId: string | null;
};

export type OptimizationFinding = {
  code: string;
  tier: 'safety' | 'bounds' | 'preference';
  sessionId?: string;
  exerciseId?: string;
  muscle?: MuscleGroup;
  message: string;
  ruleId: string;
  confidence: 'low' | 'moderate';
  evidenceIds: string[];
};

export type OptimizationChange =
  | {
      kind: 'reorder';
      sessionId: string;
      moveExerciseId: string;
      beforeExerciseId: string;
      ruleId: string;
    }
  | {
      kind: 'offer_superset';
      sessionId: string;
      exerciseIds: [string, string];
      ruleId: string;
    }
  | { kind: 'retain_preference'; preference: SupersetPreference; ruleId: string }
  | {
      kind: 'swap_variant';
      sessionId: string;
      fromExerciseId: string;
      toVariantId: string;
      historyExerciseId: string;
      painFreeAssumption: false;
      prescription: ExercisePrescription;
      ruleId: string;
    }
  | {
      kind: 'limitation';
      code: 'no_feasible_alternative' | 'equipment_or_setup_infeasible' | 'no_recovery_opportunity';
      sessionId?: string;
      exerciseId?: string;
      message: string;
      ruleId: string;
    }
  | {
      kind: 'prompt';
      code: 'gym_geography' | 'location_permission';
      message: string;
      ruleId: string;
    }
  | {
      kind: 'safety_prompt';
      exerciseId: string;
      sessionId: string;
      message: string;
      ruleId: string;
    };

export type OptimizationTradeoff = {
  baselineVolume: Record<MuscleGroup, number>;
  candidateVolume: Record<MuscleGroup, number>;
  timeSavedMinutes: number | null;
  timeSavedBasis: 'measured_transition' | null;
  compromises: string[];
  notes: string[];
  noCompromise: boolean;
};

export type OptimizationProposal = {
  version: 1;
  kind: 'mesocycle_optimization';
  id: string;
  status: 'proposed';
  authority: 'self_review_required';
  evidenceVersion: string;
  policyVersion: string;
  baseFingerprint: string;
  sourceHash: string;
  resolvedLocation: ResolvedLocation;
  findings: OptimizationFinding[];
  changes: OptimizationChange[];
  tradeoff: OptimizationTradeoff;
  rationale: string[];
  sequencing: SequenceReview[];
  rollingSchedule?: RollingScheduleReview;
  persisted: false;
};

export type OptimizerEvaluation = {
  resolvedLocation: ResolvedLocation;
  findings: OptimizationFinding[];
  changes: OptimizationChange[];
  tradeoff: OptimizationTradeoff;
  rationale: string[];
  sequencing: SequenceReview[];
  rollingSchedule?: RollingScheduleReview;
};

export const PAIN_PAUSE_MESSAGE =
  'Pain was reported at a high level. Pause the affected exercise and consider qualified clinical guidance if it persists or worsens. Replacement equipment is not assumed to be pain-free.';

const NO_ALTERNATIVE_MESSAGE =
  'No reviewed alternative fits the equipment and exclusions. Nothing was substituted.';

export function optimizationPlanFingerprint(sessions: readonly PlanSession[]): string {
  return trainingRequestHash(
    sessions.map((session) => ({
      id: session.id,
      day: session.day,
      part: session.part,
      exercises: session.exercises.map((exercise) => ({
        id: exercise.id,
        sets: exercise.sets,
        ...(exercise.targetRir !== undefined ? { targetRir: exercise.targetRir } : {}),
        userEdited: exercise.userEdited === true,
        ...(exercise.phase ? { phase: exercise.phase } : {}),
      })),
    })),
  );
}

export function resolveOptimizerLocation(input: {
  locationId: string | null;
  locationPermission: 'granted' | 'denied' | 'unknown';
  detectedLocationId?: string | null;
}): ResolvedLocation {
  if (input.locationId) return { id: input.locationId, source: 'user' };
  if (input.locationPermission === 'granted' && input.detectedLocationId) {
    return { id: input.detectedLocationId, source: 'detected' };
  }
  return { id: null, source: 'unknown' };
}

function normalize(input: OptimizerInput): NormalizedInput {
  const { sessions, ...rest } = input;
  return {
    ...rest,
    sessions: sessions.map((session) => ({
      id: session.id,
      day: session.day,
      part: session.part as DayPart,
      exercises: session.exercises.map((exercise) => ({ ...exercise })),
    })),
    declaredEquipment: input.declaredEquipment ?? [],
    unavailableEquipment: input.unavailableEquipment ?? [],
    preferences: [...(input.preferences ?? [])].sort((a, b) => a.id.localeCompare(b.id)),
    priorityMuscles: input.priorityMuscles ?? [],
    readiness: [...(input.readiness ?? [])].sort((a, b) => a.sessionId.localeCompare(b.sessionId)),
    pain: [...(input.pain ?? [])].sort((a, b) => a.exerciseId.localeCompare(b.exerciseId)),
    measuredTransitionMinutes: input.measuredTransitionMinutes ?? null,
    considerTimeSupersets: input.considerTimeSupersets === true,
    requestedSwaps: [...(input.requestedSwaps ?? [])].sort((a, b) =>
      a.fromExerciseId.localeCompare(b.fromExerciseId),
    ),
    logs: input.logs ?? [],
    targetRir: input.targetRir ?? 2,
    detectedLocationId: input.detectedLocationId ?? null,
  };
}

function finding(
  rules: OptimizerRuleSet,
  ruleId: string,
  fields: Omit<OptimizationFinding, 'ruleId' | 'tier' | 'confidence' | 'evidenceIds'>,
): OptimizationFinding {
  const rule = ruleById(rules, ruleId);
  if (!rule) throw new Error(`missing_optimizer_rule:${ruleId}`);
  return {
    ...fields,
    ruleId,
    tier: rule.tier,
    confidence: rule.confidence,
    evidenceIds: [...rule.evidenceIds],
  };
}

function emptyVolume(): Record<MuscleGroup, number> {
  return Object.fromEntries(MUSCLE_GROUPS.map((muscle) => [muscle, 0])) as Record<
    MuscleGroup,
    number
  >;
}

function contributionOf(exercise: PlanExercise): MuscleContribution {
  if (exercise.muscleContribution) return exercise.muscleContribution;
  return catalogVariantById(exercise.id)?.muscleContribution ?? { [exercise.primaryMuscle]: 1 };
}

function volumeFor(
  sessions: readonly PlanSession[],
  swaps: readonly Extract<OptimizationChange, { kind: 'swap_variant' }>[],
): Record<MuscleGroup, number> {
  const replaced = new Map(
    swaps.map((swap) => [swap.fromExerciseId, swap.prescription.muscleContribution]),
  );
  const volume = emptyVolume();
  for (const session of sessions) {
    for (const exercise of session.exercises) {
      const contribution = replaced.get(exercise.id) ?? contributionOf(exercise);
      for (const [muscle, fraction] of Object.entries(contribution)) {
        if (!(MUSCLE_GROUPS as readonly string[]).includes(muscle)) continue;
        volume[muscle as MuscleGroup] += exercise.sets * Number(fraction);
      }
    }
  }
  return volume;
}

function asPrescription(exercise: PlanExercise, targetRir: number): ExercisePrescription {
  const variant = catalogVariantById(exercise.id);
  return {
    id: exercise.id,
    name: variant?.name ?? exercise.name,
    primaryMuscle: exercise.primaryMuscle,
    muscleContribution: contributionOf(exercise),
    sets: exercise.sets,
    repRange: { min: 8, max: 12 },
    targetReps: 8,
    targetRir: exercise.targetRir ?? targetRir,
    targetLoadKg: null,
    loadInstruction: null,
    progression: 'hold',
    evidenceIds: [],
    // This optimizer input has no session-specific execution allowlist.
    // Reviewing one variant does not authorize further in-session swaps.
    substitutions: [],
  };
}

function preferenceBlocks(
  preferences: readonly SupersetPreference[],
  locationId: string | null,
  muscle: MuscleGroup,
): boolean {
  return preferences.some((preference) => {
    if (preference.muscle && preference.muscle !== muscle) return false;
    if (preference.scope === 'durable') return true;
    return locationId !== null && preference.locationId === locationId;
  });
}

function equipmentReady(
  exerciseId: string,
  available: ReadonlySet<CatalogEquipment>,
  input: NormalizedInput,
): boolean {
  const variant = catalogVariantById(exerciseId);
  if (!variant) return false;
  return isEligibleVariant(variant, {
    available,
    excludedConcerns: input.sequencingContext?.excludedConcerns,
    excludedExerciseIds: input.sequencingContext?.excludedExerciseIds,
  });
}

type PairStatus =
  'skip' | 'offer' | 'blocked' | 'infeasible_equipment' | 'infeasible_setup' | 'unknown_geography';

function gripsCompete(left: string, right: string, rules: OptimizerRuleSet): boolean {
  const grips = [annotationFor(rules, left).grip, annotationFor(rules, right).grip];
  return grips.every((grip) => grip !== 'none');
}

function pairStatus(
  left: PlanExercise,
  right: PlanExercise,
  input: NormalizedInput,
  rules: OptimizerRuleSet,
  available: ReadonlySet<CatalogEquipment>,
  locationId: string | null,
  sessionDeclined: boolean,
): PairStatus {
  if (left.primaryMuscle === right.primaryMuscle) return 'skip';
  if (gripsCompete(left.id, right.id, rules)) return 'skip';
  const calfPair = left.primaryMuscle === 'calves' || right.primaryMuscle === 'calves';
  if (!calfPair && !input.considerTimeSupersets) return 'skip';
  if (
    sessionDeclined ||
    preferenceBlocks(input.preferences, locationId, left.primaryMuscle) ||
    preferenceBlocks(input.preferences, locationId, right.primaryMuscle)
  ) {
    return 'blocked';
  }
  if (!equipmentReady(left.id, available, input) || !equipmentReady(right.id, available, input)) {
    return 'infeasible_equipment';
  }
  const leftStation = annotationFor(rules, left.id).stationClass;
  const rightStation = annotationFor(rules, right.id).stationClass;
  if (leftStation === rightStation || input.stationGeography === 'colocated') return 'offer';
  if (input.stationGeography === 'separated') return 'infeasible_setup';
  return 'unknown_geography';
}

function tradeoffSentence(tradeoff: OptimizationTradeoff): string {
  if (tradeoff.timeSavedMinutes === null) {
    return 'Time saved is not estimated; no measured transition time was supplied.';
  }
  if (tradeoff.noCompromise) {
    return `${tradeoff.timeSavedMinutes} minutes saved from measured transition time, with no safety, volume, or scheduling compromise.`;
  }
  return `${tradeoff.timeSavedMinutes} minutes of measured transition time would be saved, with compromises: ${tradeoff.compromises.join(', ')}.`;
}

export function evaluateMesocycle(
  input: NormalizedInput,
  rules: OptimizerRuleSet,
): OptimizerEvaluation {
  const resolvedLocation = resolveOptimizerLocation(input);
  const available = input.sequencingContext?.inventory
    ? new Set(input.sequencingContext.inventory)
    : resolveAvailableEquipment({
        profile: input.equipmentProfile,
        declared: input.declaredEquipment,
        sessionUnavailable: input.unavailableEquipment,
      });
  for (const item of input.unavailableEquipment) available.delete(item as CatalogEquipment);
  const findings: OptimizationFinding[] = [];
  const changes: OptimizationChange[] = [];
  const handled = new Set<string>();
  const rollingSchedule = input.rollingSchedule
    ? reviewRollingSchedule({
        sessions: input.sessions,
        context: input.rollingSchedule,
        logs: input.logs,
        targetRir: input.targetRir,
        excludedExerciseIds: input.sequencingContext?.excludedExerciseIds,
        excludedConcerns: input.sequencingContext?.excludedConcerns,
      })
    : undefined;
  if (rollingSchedule) {
    findings.push(
      finding(rules, 'rolling_schedule_v1', {
        code: 'rolling_readiness_conditional',
        message:
          'Timestamped allocations remain conditional on current dose, completed work and tolerability. Template-volume totals describe the original rotation; the rolling receipt identifies completed, dropped and pending work.',
      }),
    );
    if (rollingSchedule.unallocated.length || rollingSchedule.dropped.length)
      findings.push(
        finding(rules, 'rolling_schedule_v1', {
          code: 'rolling_allocation_tradeoff',
          message:
            'Some approved work is dropped by a reviewed recovery reduction or remains unallocated. Review the explicit move, reduce, rest or opportunity tradeoff; it is not catch-up debt.',
        }),
      );
  }

  const sequencing = input.sessions.map((session) =>
    reviewSessionSequence({
      session,
      context: input.sequencingContext,
      legacyPriorities: input.priorityMuscles,
      equipmentProfile: input.equipmentProfile,
      declaredEquipment: input.declaredEquipment,
      unavailableEquipment: input.unavailableEquipment,
      logs: input.logs,
      lowReadiness: input.readiness.some(
        (row) => row.sessionId === session.id && row.reported === 'low',
      ),
      painfulExerciseIds: input.pain
        .filter((row) => row.jointPain > 0)
        .map((row) => row.exerciseId),
      rules,
    }),
  );

  for (const session of input.sessions) {
    for (const exercise of session.exercises) {
      const pain = input.pain.find((item) => item.exerciseId === exercise.id);
      if (!pain || pain.jointPain < 1) continue;
      if (pain.jointPain >= 4) {
        findings.push(
          finding(rules, 'pain_pause_v1', {
            code: 'high_joint_pain',
            sessionId: session.id,
            exerciseId: exercise.id,
            message: PAIN_PAUSE_MESSAGE,
          }),
        );
        changes.push({
          kind: 'safety_prompt',
          exerciseId: exercise.id,
          sessionId: session.id,
          message: PAIN_PAUSE_MESSAGE,
          ruleId: 'pain_pause_v1',
        });
        handled.add(exercise.id);
        continue;
      }
      const alternative = substitutionCandidates({
        primaryMuscle: exercise.primaryMuscle,
        currentExerciseId: exercise.id,
        currentContribution: contributionOf(exercise),
        available,
        excludedConcerns: [
          ...(input.sequencingContext?.excludedConcerns ?? []),
          ...(pain.concern ? [pain.concern] : []),
        ],
        excludedExerciseIds: input.sequencingContext?.excludedExerciseIds,
        preferTorsoSupport: true,
        maxTrunkDemand: 'low',
      })[0];
      if (!alternative) {
        changes.push({
          kind: 'limitation',
          code: 'no_feasible_alternative',
          sessionId: session.id,
          exerciseId: exercise.id,
          message: NO_ALTERNATIVE_MESSAGE,
          ruleId: 'pain_alternative_v1',
        });
        handled.add(exercise.id);
        continue;
      }
      const prescription = swappedPrescription(
        asPrescription(exercise, input.targetRir),
        alternative.id,
        input.logs,
        input.targetRir,
      );
      if (!prescription) {
        changes.push({
          kind: 'limitation',
          code: 'no_feasible_alternative',
          sessionId: session.id,
          exerciseId: exercise.id,
          message: NO_ALTERNATIVE_MESSAGE,
          ruleId: 'pain_alternative_v1',
        });
        handled.add(exercise.id);
        continue;
      }
      findings.push(
        finding(rules, 'pain_alternative_v1', {
          code: 'conservative_alternative',
          sessionId: session.id,
          exerciseId: exercise.id,
          message: `${alternative.name} is a more supported reviewed setup. It is not assumed to be pain-free.`,
        }),
      );
      changes.push({
        kind: 'swap_variant',
        sessionId: session.id,
        fromExerciseId: exercise.id,
        toVariantId: alternative.id,
        historyExerciseId: alternative.id,
        painFreeAssumption: false,
        prescription,
        ruleId: 'pain_alternative_v1',
      });
      handled.add(exercise.id);
    }
  }

  for (const request of input.requestedSwaps) {
    if (handled.has(request.fromExerciseId)) continue;
    const session = input.sessions.find((item) => item.id === request.sessionId);
    const exercise = session?.exercises.find((item) => item.id === request.fromExerciseId);
    if (!session || !exercise) {
      changes.push({
        kind: 'limitation',
        code: 'no_feasible_alternative',
        sessionId: request.sessionId,
        exerciseId: request.fromExerciseId,
        message: NO_ALTERNATIVE_MESSAGE,
        ruleId: 'variant_swap_v1',
      });
      continue;
    }
    if (exercise.userEdited) {
      findings.push(
        finding(rules, 'user_edit_v1', {
          code: 'user_edit_preserved',
          sessionId: session.id,
          exerciseId: exercise.id,
          message: `${exercise.name} was edited by the user and was left unchanged.`,
        }),
      );
      continue;
    }
    const variant = catalogVariantById(request.toVariantId);
    const eligible =
      variant !== undefined &&
      variant.primaryMuscle === exercise.primaryMuscle &&
      isEligibleVariant(variant, {
        available,
        excludedConcerns: input.sequencingContext?.excludedConcerns,
        excludedExerciseIds: input.sequencingContext?.excludedExerciseIds,
      });
    const prescription = eligible
      ? swappedPrescription(
          asPrescription(exercise, input.targetRir),
          variant.id,
          input.logs,
          input.targetRir,
        )
      : null;
    if (!variant || !prescription) {
      changes.push({
        kind: 'limitation',
        code: 'no_feasible_alternative',
        sessionId: session.id,
        exerciseId: exercise.id,
        message: NO_ALTERNATIVE_MESSAGE,
        ruleId: 'variant_swap_v1',
      });
      continue;
    }
    changes.push({
      kind: 'swap_variant',
      sessionId: session.id,
      fromExerciseId: exercise.id,
      toVariantId: variant.id,
      historyExerciseId: variant.id,
      painFreeAssumption: false,
      prescription,
      ruleId: 'variant_swap_v1',
    });
    findings.push(
      finding(rules, 'variant_swap_v1', {
        code: 'variant_swap',
        sessionId: session.id,
        exerciseId: exercise.id,
        message: `${exercise.name} can swap to ${variant.name}. Logged history stays on ${variant.name} and is not copied from ${exercise.name}.`,
      }),
    );
  }

  for (const session of input.sessions) {
    const review = sequencing.find((row) => row.sessionId === session.id)!;
    const remaining = new Set(review.remaining.map((row) => row.exerciseId));
    const working = session.exercises.filter(
      (exercise) => exercise.phase !== 'warmup' && remaining.has(exercise.id),
    );
    const conflict = gripConflict(
      working.map((exercise) => exercise.id),
      rules,
    );
    if (!conflict) continue;
    const direct = session.exercises.find((exercise) => exercise.id === conflict.directId);
    const support = session.exercises.find((exercise) => exercise.id === conflict.supportId);
    findings.push(
      finding(rules, 'grip_interference_v1', {
        code: 'possible_grip_interference',
        sessionId: session.id,
        exerciseId: conflict.directId,
        message: `${direct?.name ?? conflict.directId} before ${support?.name ?? conflict.supportId} is possible grip interference. Direct forearm work may tire the grip a later pull needs. This is not a measured fatigue score.`,
      }),
    );
    const crossed = session.exercises.slice(
      session.exercises.findIndex((row) => row.id === conflict.directId),
      session.exercises.findIndex((row) => row.id === conflict.supportId) + 1,
    );
    if (crossed.some((row) => row.userEdited)) {
      findings.push(
        finding(rules, 'user_edit_v1', {
          code: 'user_edit_preserved',
          sessionId: session.id,
          exerciseId: direct?.userEdited ? direct.id : support?.id,
          message: 'The edited exercise order was kept. The grip note is only a flag.',
        }),
      );
      continue;
    }
    if (
      input.readiness.some((row) => row.sessionId === session.id && row.reported === 'low') ||
      crossed.some((row) => row.phase === 'warmup') ||
      input.pain.some((row) => row.exerciseId === conflict.supportId && row.jointPain > 0) ||
      review.blockedExerciseIds.includes(conflict.supportId) ||
      review.decision.exceptions.includes('unfinished_work_requires_reconciliation')
    )
      continue;
    if (
      review.move?.exerciseId === conflict.supportId &&
      review.move.beforeExerciseId === conflict.directId
    )
      continue;
    changes.push({
      kind: 'reorder',
      sessionId: session.id,
      moveExerciseId: conflict.supportId,
      beforeExerciseId: conflict.directId,
      ruleId: 'grip_interference_v1',
    });
  }

  for (const review of sequencing) {
    if (!review.move) continue;
    changes.push({
      kind: 'reorder',
      sessionId: review.sessionId,
      moveExerciseId: review.move.exerciseId,
      beforeExerciseId: review.move.beforeExerciseId,
      ruleId: 'priority_sequence_v1',
    });
  }
  for (const review of sequencing) {
    const ordered = [...review.remaining];
    for (const change of changes) {
      if (change.kind !== 'reorder' || change.sessionId !== review.sessionId) continue;
      const index = ordered.findIndex((row) => row.exerciseId === change.moveExerciseId);
      if (index < 0) continue;
      const [moved] = ordered.splice(index, 1);
      const before = ordered.findIndex((row) => row.exerciseId === change.beforeExerciseId);
      if (before < 0) ordered.splice(index, 0, moved!);
      else ordered.splice(before, 0, moved!);
    }
    review.remaining = ordered;
  }

  for (const overlap of sameDayPrimaryOverlaps(input.sessions, rules)) {
    const later = input.readiness.find((item) => item.sessionId === overlap.laterSessionId);
    const readiness =
      later?.reported === 'low' ? ' Reported readiness for the later session was low.' : '';
    const separatingDay = input.sessions.some(
      (session) =>
        session.day !== overlap.day &&
        !session.exercises.some((exercise) => exercise.primaryMuscle === overlap.muscle),
    );
    findings.push(
      finding(rules, 'same_day_overlap_v1', {
        code: 'same_day_local_overlap',
        sessionId: overlap.laterSessionId,
        muscle: overlap.muscle,
        message: `${overlap.day} AM and PM both train ${overlap.muscle}. The later session is not assumed recovered and a new start does not reset earlier observations.${readiness} This is possible overlap, not a measured recovery time.`,
      }),
    );
    changes.push({
      kind: 'limitation',
      code: 'no_recovery_opportunity',
      sessionId: overlap.laterSessionId,
      message: separatingDay
        ? `${overlap.muscle} repeats on ${overlap.day}. It was not moved to another day automatically.`
        : `No other day in this plan separates ${overlap.muscle} from the earlier ${overlap.day} session, so the overlap is left in place.`,
      ruleId: 'same_day_overlap_v1',
    });
  }

  for (const report of input.readiness) {
    if (report.reported !== 'low') continue;
    findings.push(
      finding(rules, 'readiness_report_v1', {
        code: 'reported_low_readiness',
        sessionId: report.sessionId,
        message:
          'Reported readiness is low, so this session is not a candidate for added work. No set count was changed.',
      }),
    );
  }

  const baselineVolume = volumeFor(input.sessions, []);
  for (const muscle of MUSCLE_GROUPS) {
    const caution = volume_landmarks[muscle].highVolumeCaution;
    if (baselineVolume[muscle] <= caution) continue;
    findings.push(
      finding(rules, 'volume_caution_v1', {
        code: 'volume_above_reviewed_caution',
        muscle,
        message: `${muscle} fractional volume is above the reviewed high-volume caution of ${caution}. Sets were not rewritten.`,
      }),
    );
  }

  const sessionDeclined = input.declineSupersets !== undefined;
  if (input.declineSupersets) {
    const scope = input.declineSupersets.scope;
    if (scope === 'location' && !resolvedLocation.id) {
      changes.push({
        kind: 'prompt',
        code: 'location_permission',
        message:
          'This decline was not saved as a gym block or as a never-again block. Name the gym, or say never. Location is not detected without permission.',
        ruleId: 'preference_scope_v1',
      });
    } else {
      const locationId = scope === 'location' ? resolvedLocation.id : null;
      changes.push({
        kind: 'retain_preference',
        preference: {
          id: `decline:${scope}:${locationId ?? 'none'}:${input.declineSupersets.muscle ?? 'any'}`,
          scope,
          locationId,
          muscle: input.declineSupersets.muscle,
          reason: input.declineSupersets.reason,
        },
        ruleId: 'preference_scope_v1',
      });
    }
  }

  let promptedGeography = false;
  for (const session of input.sessions) {
    const ordered = [...session.exercises].sort((a, b) => a.id.localeCompare(b.id));
    let offer: [string, string] | null = null;
    let infeasible: PairStatus | null = null;
    let unknown = false;
    for (let leftIndex = 0; leftIndex < ordered.length; leftIndex += 1) {
      for (let rightIndex = leftIndex + 1; rightIndex < ordered.length; rightIndex += 1) {
        const left = ordered[leftIndex];
        const right = ordered[rightIndex];
        if (!left || !right) continue;
        const status = pairStatus(
          left,
          right,
          input,
          rules,
          available,
          resolvedLocation.id,
          sessionDeclined,
        );
        if (status === 'offer' && !offer) offer = [left.id, right.id];
        if ((status === 'infeasible_equipment' || status === 'infeasible_setup') && !infeasible) {
          infeasible = status;
        }
        if (status === 'unknown_geography') unknown = true;
      }
    }
    if (offer) {
      changes.push({
        kind: 'offer_superset',
        sessionId: session.id,
        exerciseIds: offer,
        ruleId: 'superset_feasibility_v1',
      });
      continue;
    }
    if (sessionDeclined) continue;
    if (unknown && !promptedGeography) {
      promptedGeography = true;
      changes.push({
        kind: 'prompt',
        code: 'gym_geography',
        message:
          'A non-competing pairing depends on whether those stations are next to each other. Layout is unknown, so no superset was added.',
        ruleId: 'context_prompt_v1',
      });
      continue;
    }
    if (infeasible) {
      changes.push({
        kind: 'limitation',
        code: 'equipment_or_setup_infeasible',
        sessionId: session.id,
        message:
          infeasible === 'infeasible_equipment'
            ? 'The non-competing pairing needs equipment that is not available here, so it was not offered.'
            : 'The stations for that pairing are not a shared setup, so the superset was not offered.',
        ruleId: 'superset_feasibility_v1',
      });
    }
  }

  const swaps = changes.filter(
    (change): change is Extract<OptimizationChange, { kind: 'swap_variant' }> =>
      change.kind === 'swap_variant',
  );
  const candidateVolume = volumeFor(input.sessions, swaps);
  const offerCount = changes.filter((change) => change.kind === 'offer_superset').length;
  const timeSavedMinutes =
    input.measuredTransitionMinutes === null ? null : offerCount * input.measuredTransitionMinutes;
  const compromises = [
    ...new Set(
      findings
        .filter((item) => item.tier === 'safety' || item.tier === 'bounds')
        .map((item) => item.code),
    ),
  ].sort();
  const notes = [
    ...findings.map((item) => item.message),
    ...changes
      .filter((change) => change.kind === 'limitation' || change.kind === 'prompt')
      .map((change) => change.message),
  ];
  const tradeoff: OptimizationTradeoff = {
    baselineVolume,
    candidateVolume,
    timeSavedMinutes,
    timeSavedBasis: timeSavedMinutes === null ? null : 'measured_transition',
    compromises,
    notes,
    noCompromise: timeSavedMinutes !== null && compromises.length === 0,
  };
  const rationale = [...notes, tradeoffSentence(tradeoff)];
  return {
    resolvedLocation,
    findings,
    changes,
    tradeoff,
    rationale,
    sequencing,
    ...(rollingSchedule ? { rollingSchedule } : {}),
  };
}

export function reviewedSwapPrescription(
  exercise: PlanExercise,
  variantId: string,
  logs: readonly SetLog[],
  targetRir: number,
): ExercisePrescription | null {
  return swappedPrescription(
    asPrescription(exercise, targetRir),
    variantId,
    [...logs],
    exercise.targetRir ?? targetRir,
  );
}

export function optimizeMesocycle(
  body: unknown,
  rules: OptimizerRuleSet = OPTIMIZER_RULES,
): { kind: 'proposal'; proposal: OptimizationProposal } | { kind: 'invalid' } {
  const parsed = optimizerInputSchema.safeParse(body);
  if (!parsed.success) return { kind: 'invalid' };
  const input = normalize(parsed.data);
  const evaluation = evaluateMesocycle(input, rules);
  const sourceHash = trainingRequestHash(input);
  const baseFingerprint = input.baseFingerprint ?? optimizationPlanFingerprint(input.sessions);
  return {
    kind: 'proposal',
    proposal: {
      version: 1,
      kind: 'mesocycle_optimization',
      id: stableTrainingUuid('mesocycle-optimizer', sourceHash, rules.version),
      status: 'proposed',
      authority: 'self_review_required',
      evidenceVersion: rules.version,
      policyVersion: rules.version,
      baseFingerprint,
      sourceHash,
      persisted: false,
      ...evaluation,
    },
  };
}

export function normalizeOptimizerInput(body: unknown): NormalizedInput | null {
  const parsed = optimizerInputSchema.safeParse(body);
  if (!parsed.success) return null;
  return normalize(parsed.data);
}
