import { z } from 'zod';
import {
  CATALOG_EQUIPMENT,
  catalogVariantById,
  isEligibleVariant,
  resolveAvailableEquipment,
  substitutionCandidates,
} from './catalog';
import { exerciseDemands, type OptimizerRuleSet } from './optimizer-rules';
import { MUSCLE_TARGETS, type MuscleTarget, type ProgrammingDecision, type SetLog } from './types';

const scopeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('persistent') }).strict(),
  z.object({ kind: z.literal('block'), blockId: z.string().min(1) }).strict(),
]);
export const muscleIntentSchema = z
  .object({
    muscle: z.enum(MUSCLE_TARGETS),
    intent: z.enum(['emphasize', 'grow', 'maintain']),
    scope: scopeSchema,
  })
  .strict();
export const sequencingContextSchema = z
  .object({
    blockId: z.string().min(1),
    asOf: z.string().datetime({ offset: true }),
    intents: z
      .array(muscleIntentSchema)
      .refine(
        (rows) =>
          new Set(
            rows.map(
              (row) =>
                `${row.muscle}:${row.scope.kind}:${row.scope.kind === 'block' ? row.scope.blockId : ''}`,
            ),
          ).size === rows.length,
        'duplicate_intent_scope',
      ),
    muscleReadiness: z
      .array(
        z
          .object({
            sessionId: z.string().min(1),
            muscle: z.enum(MUSCLE_TARGETS),
            reported: z.enum(['ready', 'limited', 'unknown']),
          })
          .strict(),
      )
      .optional(),
    /** Concrete inventory replaces a preset; omitted inventory keeps legacy behavior. */
    inventory: z.array(z.enum(CATALOG_EQUIPMENT)).optional(),
    excludedExerciseIds: z.array(z.string().min(1)).optional(),
    excludedConcerns: z.array(z.string().min(1)).optional(),
    segments: z
      .array(
        z
          .object({
            id: z.string().min(1),
            parentSessionId: z.string().min(1),
            startedAt: z.string().datetime({ offset: true }),
            status: z.enum(['active', 'paused', 'completed', 'canceled']),
          })
          .strict(),
      )
      .optional(),
    limitations: z
      .array(
        z
          .object({
            id: z.string().min(1),
            sessionId: z.string().min(1),
            exerciseId: z.string().min(1),
            observedAt: z.string().datetime({ offset: true }),
            kind: z.enum([
              'target_muscle',
              'assisting_muscle',
              'grip',
              'trunk',
              'joint_tolerability',
            ]),
            muscle: z.enum(MUSCLE_TARGETS).optional(),
          })
          .strict(),
      )
      .optional(),
  })
  .strict();
export type SequencingContext = z.infer<typeof sequencingContextSchema>;
export type ScopedMuscleIntent = z.infer<typeof muscleIntentSchema>;

/** Block preferences override only their named muscles. Expiry reveals the
 * persistent intent; it never turns all unspecified muscles into maintenance. */
export function resolveMuscleIntents(intents: readonly ScopedMuscleIntent[], blockId: string) {
  const resolved: Partial<Record<MuscleTarget, ScopedMuscleIntent['intent']>> = {};
  for (const row of intents) if (row.scope.kind === 'persistent') resolved[row.muscle] = row.intent;
  for (const row of intents) {
    if (row.scope.kind === 'block' && row.scope.blockId === blockId)
      resolved[row.muscle] = row.intent;
  }
  return resolved;
}

type SequenceExercise = {
  id: string;
  primaryMuscle: string;
  sets: number;
  phase?: 'warmup' | 'working';
  userEdited?: boolean;
};
type SequenceSession = { id: string; exercises: readonly SequenceExercise[] };
export type SequenceReview = {
  sessionId: string;
  remaining: Array<{ exerciseId: string; setNumbers: number[] }>;
  completedSetIds: string[];
  /** Observed completed work survives segment and date boundaries. No reset claim. */
  priorDemands: Array<{
    setId: string;
    exerciseId: string;
    completedAt: string;
    demands: ReturnType<typeof exerciseDemands>;
  }>;
  plannedDemands: Array<{ exerciseId: string; demands: ReturnType<typeof exerciseDemands> }>;
  limitations: NonNullable<SequencingContext['limitations']>;
  conflicts: Array<{ code: 'priority_ineligible'; exerciseId: string; alternatives: string[] }>;
  blockedExerciseIds: string[];
  decision: ProgrammingDecision;
  move: { exerciseId: string; beforeExerciseId: string } | null;
};

export function reviewSessionSequence(input: {
  session: SequenceSession;
  context?: SequencingContext;
  legacyPriorities: readonly string[];
  equipmentProfile: 'dumbbells' | 'full_gym';
  declaredEquipment: readonly string[];
  unavailableEquipment: readonly string[];
  logs: readonly SetLog[];
  lowReadiness: boolean;
  painfulExerciseIds: readonly string[];
  rules: OptimizerRuleSet;
}): SequenceReview {
  const { session, context, rules } = input;
  const asOf = context ? Date.parse(context.asOf) : Infinity;
  const completed = input.logs.filter(
    (log) => log.sessionId === session.id && Date.parse(log.completedAt) <= asOf,
  );
  const remaining = session.exercises
    .map((exercise) => ({
      exerciseId: exercise.id,
      setNumbers: Array.from({ length: exercise.sets }, (_, index) => index + 1).filter(
        (number) =>
          !completed.some((log) => log.exerciseId === exercise.id && log.setNumber === number),
      ),
    }))
    .filter((row) => row.setNumbers.length > 0);
  const pending = new Set(remaining.map((row) => row.exerciseId));
  const intents = context ? resolveMuscleIntents(context.intents, context.blockId) : {};
  const priorities = new Set<string>([
    ...input.legacyPriorities.filter((muscle) => intents[muscle as MuscleTarget] === undefined),
    ...Object.entries(intents)
      .filter(([, intent]) => intent === 'emphasize')
      .map(([muscle]) => muscle),
  ]);
  const available = context?.inventory
    ? new Set(context.inventory)
    : resolveAvailableEquipment({
        profile: input.equipmentProfile,
        declared: input.declaredEquipment,
        sessionUnavailable: input.unavailableEquipment,
      });
  for (const item of input.unavailableEquipment)
    available.delete(item as (typeof CATALOG_EQUIPMENT)[number]);
  const limitations = (context?.limitations ?? []).filter(
    (row) => row.sessionId === session.id && Date.parse(row.observedAt) <= asOf,
  );
  const exceptions: string[] = [];
  const conflicts: SequenceReview['conflicts'] = [];
  const eligible = (exercise: SequenceExercise) => {
    const variant = catalogVariantById(exercise.id);
    const demands = exerciseDemands(rules, exercise.id);
    return (
      variant &&
      !context?.excludedExerciseIds?.includes(exercise.id) &&
      isEligibleVariant(variant, {
        available,
        excludedConcerns: context?.excludedConcerns,
        excludedExerciseIds: context?.excludedExerciseIds,
      }) &&
      !input.painfulExerciseIds.includes(exercise.id) &&
      !context?.muscleReadiness?.some(
        (row) =>
          row.sessionId === session.id &&
          row.reported === 'limited' &&
          (demands.targets.includes(row.muscle) ||
            demands.assisting?.includes(row.muscle) ||
            row.muscle === exercise.primaryMuscle),
      ) &&
      !limitations.some((row) => row.exerciseId === exercise.id && row.kind !== 'target_muscle')
    );
  };
  const isPriority = (exercise: SequenceExercise) =>
    exerciseDemands(rules, exercise.id).targets.some((muscle) =>
      intents[muscle] !== undefined
        ? intents[muscle] === 'emphasize'
        : priorities.has(muscle) ||
          (muscle !== 'forearms' && priorities.has(exercise.primaryMuscle)),
    );
  const candidates = session.exercises.filter(
    (exercise) => exercise.phase !== 'warmup' && pending.has(exercise.id) && isPriority(exercise),
  );
  for (const exercise of candidates) {
    if (eligible(exercise)) continue;
    exceptions.push(`ineligible:${exercise.id}`);
    const current = catalogVariantById(exercise.id);
    conflicts.push({
      code: 'priority_ineligible',
      exerciseId: exercise.id,
      alternatives: current
        ? substitutionCandidates({
            primaryMuscle: current.primaryMuscle,
            currentExerciseId: current.id,
            currentContribution: current.muscleContribution,
            available,
            excludedConcerns: context?.excludedConcerns,
            excludedExerciseIds: context?.excludedExerciseIds,
          })
            .filter(
              (variant) =>
                eligible({
                  id: variant.id,
                  primaryMuscle: variant.primaryMuscle,
                  sets: exercise.sets,
                }) &&
                isPriority({
                  id: variant.id,
                  primaryMuscle: variant.primaryMuscle,
                  sets: exercise.sets,
                }),
            )
            .map((row) => row.id)
        : [],
    });
  }
  // A canceled continuation never authorizes another allocation or banks set debt.
  const segments = (context?.segments ?? []).filter(
    (row) => row.parentSessionId === session.id && Date.parse(row.startedAt) <= asOf,
  );
  const latestSegment = [...segments].sort(
    (a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt) || a.id.localeCompare(b.id),
  )[0];
  const blocked = input.lowReadiness || latestSegment?.status === 'canceled';
  if (input.lowReadiness) exceptions.push('reported_low_readiness');
  if (latestSegment?.status === 'canceled')
    exceptions.push('unfinished_work_requires_reconciliation');
  const priority = blocked ? undefined : candidates.find(eligible);
  let move: SequenceReview['move'] = null;
  if (priority) {
    const priorityIndex = session.exercises.findIndex((row) => row.id === priority.id);
    const warmupEnd = session.exercises.reduce(
      (last, row, index) => (row.phase === 'warmup' ? index : last),
      -1,
    );
    const first = session.exercises.findIndex(
      (row, index) => index > warmupEnd && pending.has(row.id) && row.phase !== 'warmup',
    );
    if (first >= 0 && first < priorityIndex) {
      if (session.exercises.slice(first, priorityIndex + 1).some((row) => row.userEdited)) {
        exceptions.push('user_order_requires_review');
      } else {
        move = { exerciseId: priority.id, beforeExerciseId: session.exercises[first]!.id };
        const index = remaining.findIndex((row) => row.exerciseId === priority.id);
        const [moved] = remaining.splice(index, 1);
        remaining.splice(
          remaining.findIndex((row) => row.exerciseId === move!.beforeExerciseId),
          0,
          moved!,
        );
      }
    }
  }
  const rationale = move
    ? 'Eligible specialization work leads the remaining working sets after warm-up. Approved set counts and other growth goals are retained; individual interference remains uncertain.'
    : 'Retain the planned remaining work. Completed sets, warm-up, reported limitations and user edits constrain priority ordering.';
  return {
    sessionId: session.id,
    remaining,
    completedSetIds: completed.map((row) => row.id),
    priorDemands: completed.map((row) => ({
      setId: row.id,
      exerciseId: row.exerciseId,
      completedAt: row.completedAt,
      demands: exerciseDemands(rules, row.exerciseId),
    })),
    plannedDemands: session.exercises.map((row) => ({
      exerciseId: row.id,
      demands: exerciseDemands(rules, row.id),
    })),
    limitations,
    conflicts,
    move,
    blockedExerciseIds: session.exercises
      .filter((row) => pending.has(row.id) && row.phase !== 'warmup' && !eligible(row))
      .map((row) => row.id),
    decision: {
      variable: 'sequencing',
      observations: [
        JSON.stringify({
          intents,
          planned: session.exercises,
          completedSetIds: completed.map((row) => row.id),
          segments,
          limitations,
          lowReadiness: input.lowReadiness,
          muscleReadiness: context?.muscleReadiness ?? [],
          inventory: [...available],
          excludedExerciseIds: context?.excludedExerciseIds ?? [],
          excludedConcerns: context?.excludedConcerns ?? [],
          painfulExerciseIds: input.painfulExerciseIds,
        }),
      ],
      ruleId: 'priority_sequence_v1',
      ruleVersion: rules.version,
      evidenceClass: 'reviewed_product_policy',
      evidenceIds: ['rule:priority-sequence-v1'],
      approvalScope: 'proposal_only',
      uncertainty: 'individual_response_unknown',
      exceptions,
      rationale,
      regressionFixture: 'priority sequencing golden scenarios',
    },
  };
}
