import { z } from 'zod';
import {
  EXERCISE_CATALOG,
  catalogVariantById,
  isEligibleVariant,
  missingEquipment,
  resolveAvailableEquipment,
  type CatalogEquipment,
} from './catalog';
import { volume_landmarks } from './engine';
import { MUSCLE_GROUPS, type Equipment, type MuscleGroup } from './types';

/**
 * One canonical plan document for chat, voice, and direct manipulation.
 * Utterances become typed proposals. The stored plan changes only when a
 * proposal is applied through this module and the ledger port accepts the write.
 */

export const CANVAS_DAYS = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
] as const;
export type CanvasDay = (typeof CANVAS_DAYS)[number];
export type CanvasSlot = 'single' | 'am' | 'pm';
export type CanvasPriority = 'priority' | 'maintenance' | 'standard';

const LOWER_BODY: readonly MuscleGroup[] = ['quads', 'hamstrings', 'glutes', 'calves'];
const REP_RANGE = { min: 8, max: 12 } as const;
const TARGET_REPS = 10;
const TARGET_RIR = 3;
const DAY_INDEX = new Map(CANVAS_DAYS.map((day, index) => [day, index]));
const SLOT_INDEX: Record<CanvasSlot, number> = { am: 0, single: 1, pm: 2 };
const WORD_NUMBERS: Record<string, number> = {
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
};

const daySchema = z.enum(CANVAS_DAYS);
const slotSchema = z.enum(['single', 'am', 'pm']);
const prioritySchema = z.enum(['priority', 'maintenance', 'standard']);
const muscleSchema = z.enum(MUSCLE_GROUPS);

const exerciseSchema = z
  .object({
    instanceId: z.string().min(1),
    variantId: z.string().min(1),
    name: z.string().min(1),
    primaryMuscle: muscleSchema,
    sets: z.number().int().min(1).max(8),
    repRange: z.object({ min: z.literal(8), max: z.literal(12) }),
    targetReps: z.literal(TARGET_REPS),
    targetRir: z.literal(TARGET_RIR),
    priority: prioritySchema,
    emphasis: z.enum(['upper_chest']).nullable(),
    evidenceIds: z.array(z.string().min(1)).min(1),
  })
  .strict();
export type CanvasExercise = z.infer<typeof exerciseSchema>;

const sessionSchema = z
  .object({
    id: z.string().min(1),
    day: daySchema,
    slot: slotSchema,
    title: z.string().min(1),
    exercises: z.array(exerciseSchema).min(1),
  })
  .strict();
export type CanvasSession = z.infer<typeof sessionSchema>;

const policySchema = z
  .object({
    priorityMuscles: z.array(muscleSchema),
    upperChest: z.boolean(),
    maintenanceMuscles: z.array(muscleSchema),
  })
  .strict();

export const canvasPlanSchema = z
  .object({
    id: z.literal('canvas-plan'),
    revision: z.number().int().nonnegative(),
    weekCount: z.union([z.literal(4), z.literal(5), z.literal(6)]),
    equipment: z.enum(['dumbbells', 'full_gym']),
    declaredEquipment: z.array(z.string()),
    goal: z.string().min(1),
    policy: policySchema,
    sessions: z.array(sessionSchema).min(1),
  })
  .strict();
export type CanvasPlan = z.infer<typeof canvasPlanSchema>;

const operationSchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('draft'),
      goal: z.string().min(1).max(500),
      equipment: z.enum(['dumbbells', 'full_gym']),
      weekCount: z.number().int(),
    })
    .strict(),
  z
    .object({
      kind: z.literal('prioritize'),
      muscles: z.array(muscleSchema).min(1),
      upperChest: z.boolean(),
    })
    .strict(),
  z.object({ kind: z.literal('set_training_days'), count: z.number().int() }).strict(),
  z.object({ kind: z.literal('split_day'), day: daySchema }).strict(),
  z
    .object({
      kind: z.literal('swap'),
      exerciseName: z.string().min(1),
      toVariantId: z.string().min(1),
      declareEquipment: z.array(z.string()),
    })
    .strict(),
  z
    .object({
      kind: z.literal('move'),
      instanceId: z.string().min(1),
      toDay: daySchema,
      toSlot: slotSchema,
    })
    .strict(),
  z
    .object({
      kind: z.literal('edit_sets'),
      instanceId: z.string().min(1),
      sets: z.number().int(),
    })
    .strict(),
  z.object({ kind: z.literal('undo') }).strict(),
  z.object({ kind: z.literal('redo') }).strict(),
]);
export type PlanOperation = z.infer<typeof operationSchema>;

const changeSchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('added'),
      instanceId: z.string(),
      day: daySchema,
      slot: slotSchema,
      name: z.string(),
      reason: z.string(),
    })
    .strict(),
  z
    .object({
      kind: z.literal('moved'),
      instanceId: z.string(),
      name: z.string(),
      fromDay: daySchema,
      fromSlot: slotSchema,
      toDay: daySchema,
      toSlot: slotSchema,
      reason: z.string(),
    })
    .strict(),
  z
    .object({
      kind: z.literal('replaced'),
      instanceId: z.string(),
      fromName: z.string(),
      toName: z.string(),
      toVariantId: z.string(),
      reason: z.string(),
    })
    .strict(),
  z
    .object({
      kind: z.literal('updated'),
      instanceId: z.string(),
      name: z.string(),
      previousSets: z.number(),
      sets: z.number(),
      reason: z.string(),
    })
    .strict(),
]);
export type CanvasChange = z.infer<typeof changeSchema>;

const proposalSchema = z
  .object({
    id: z.string().uuid(),
    requestId: z.string().uuid(),
    requestKey: z.string().min(1),
    baseWrite: z.number().int().nonnegative(),
    baseGeneration: z.number().int().nonnegative(),
    baseRevision: z.number().int().nonnegative(),
    operation: operationSchema,
    reason: z.string().min(1),
    changes: z.array(changeSchema),
    preview: canvasPlanSchema,
    createdAt: z.string().datetime({ offset: true }),
  })
  .strict();
export type CanvasProposal = z.infer<typeof proposalSchema>;

const receiptSchema = z
  .object({
    proposalId: z.string().uuid(),
    requestId: z.string().uuid(),
    requestKey: z.string().min(1),
    decision: z.enum(['apply', 'reject']),
    status: z.enum(['applied', 'rejected']),
    generation: z.number().int().nonnegative(),
    revision: z.number().int().nonnegative().nullable(),
    decidedAt: z.string().datetime({ offset: true }),
  })
  .strict();
export type CanvasReceipt = z.infer<typeof receiptSchema>;

const storedProposalSchema = z
  .object({
    proposal: proposalSchema,
    status: z.enum(['proposed', 'applied', 'rejected']),
    receipt: receiptSchema.nullable(),
  })
  .strict();
export type StoredCanvasProposal = z.infer<typeof storedProposalSchema>;

export const canvasLedgerSchema = z
  .object({
    version: z.literal(1),
    write: z.number().int().nonnegative(),
    generation: z.number().int().nonnegative(),
    head: canvasPlanSchema.nullable(),
    undo: z.array(canvasPlanSchema),
    redo: z.array(canvasPlanSchema),
    proposals: z.array(storedProposalSchema),
  })
  .strict();
export type CanvasLedger = z.infer<typeof canvasLedgerSchema>;

export type MuscleGoal = {
  id: string;
  label: string;
  role: CanvasPriority;
  weeklySets: number;
};

export type ExecutionExercise = {
  instanceId: string;
  variantId: string;
  name: string;
  sets: number;
  targetReps: number;
  targetRir: number;
};

export type ExecutionSession = {
  sessionId: string;
  day: CanvasDay;
  slot: CanvasSlot;
  title: string;
  exercises: ExecutionExercise[];
};

export type CanvasReadback = {
  version: 1;
  /** Null until the first ledger row exists. A stored row uses its write token. */
  write: number | null;
  generation: number;
  plan: CanvasPlan | null;
  goals: MuscleGoal[];
  weeklyTotals: Record<string, number>;
  execution: ExecutionSession[];
  proposal: StoredCanvasProposal | null;
  narration: string;
};

export type CanvasFailure =
  | 'canonical_revision_required'
  | 'stale_context'
  | 'request_conflict'
  | 'already_decided'
  | 'proposal_not_found'
  | 'unsupported_or_invalid_intent'
  | 'unsupported_equipment'
  | 'plan_missing'
  | 'missed_update'
  | 'nothing_to_undo'
  | 'nothing_to_redo'
  | 'ambiguous_exercise'
  | 'exercise_not_found'
  | 'variant_not_found'
  | 'would_drop_training_day'
  | 'day_not_trainable'
  | 'session_conflict'
  | 'invalid_sets'
  | 'missing_evidence'
  | 'ledger_invalid';

export type CanvasCommandResult =
  | { kind: 'read'; readback: CanvasReadback }
  | {
      kind: 'proposed';
      proposal: CanvasProposal;
      readback: CanvasReadback;
      missing?: CatalogEquipment[];
    }
  | { kind: 'decided'; receipt: CanvasReceipt; readback: CanvasReadback }
  | { kind: CanvasFailure; missing?: CatalogEquipment[]; readback: CanvasReadback };

export interface CanvasLedgerPort {
  load(subject: string): Promise<CanvasLedger | null>;
  /**
   * Persist only when the stored write token still matches `expectedWrite`.
   * `null` inserts the first ledger. A refused write leaves storage unchanged.
   */
  save(
    subject: string,
    expectedWrite: number | null,
    ledger: CanvasLedger,
  ): Promise<
    | { kind: 'saved' }
    | { kind: 'stale' }
    | { kind: 'missed_update' }
    | { kind: 'canonical_revision_required' }
  >;
}

export function emptyCanvasLedger(): CanvasLedger {
  return { version: 1, write: 0, generation: 0, head: null, undo: [], redo: [], proposals: [] };
}

export function memoryCanvasPort(): CanvasLedgerPort & { failNextSave(): void } {
  let ledger: CanvasLedger | null = null;
  let misses = 0;
  let chain: Promise<void> = Promise.resolve();
  function exclusive<T>(work: () => T): Promise<T> {
    const run = chain.then(work, work);
    chain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }
  return {
    failNextSave() {
      misses += 1;
    },
    load(subject) {
      void subject;
      return exclusive(() => (ledger ? canvasLedgerSchema.parse(clone(ledger)) : null));
    },
    save(subject, expectedWrite, next) {
      void subject;
      return exclusive(() => {
        const current = ledger?.write ?? null;
        if (current !== expectedWrite) return { kind: 'stale' as const };
        if (misses > 0) {
          misses -= 1;
          return { kind: 'missed_update' as const };
        }
        ledger = canvasLedgerSchema.parse(clone(next));
        return { kind: 'saved' as const };
      });
    },
  };
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function requestKey(value: unknown): string {
  function canonical(item: unknown): unknown {
    if (Array.isArray(item)) return item.map(canonical);
    if (item && typeof item === 'object') {
      return Object.fromEntries(
        Object.entries(item)
          .sort(([a], [b]) => a.localeCompare(b))
          .map(([key, val]) => [key, canonical(val)]),
      );
    }
    return item;
  }
  return JSON.stringify(canonical(value));
}

function normalizeName(value: string): string {
  return value
    .toLocaleLowerCase('en-US')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function dayLabel(day: CanvasDay): string {
  return day.charAt(0).toUpperCase() + day.slice(1);
}

function sessionTitle(day: CanvasDay, slot: CanvasSlot): string {
  return slot === 'single' ? dayLabel(day) : `${dayLabel(day)} ${slot.toUpperCase()}`;
}

function sortSessions(sessions: CanvasSession[]): CanvasSession[] {
  return [...sessions].sort((a, b) => {
    const day = (DAY_INDEX.get(a.day) ?? 0) - (DAY_INDEX.get(b.day) ?? 0);
    return day !== 0 ? day : SLOT_INDEX[a.slot] - SLOT_INDEX[b.slot];
  });
}

function evidenceFor(muscle: MuscleGroup): string[] {
  const evidence = volume_landmarks[muscle]?.evidenceIds ?? [];
  if (evidence.length === 0) throw new Error('missing_evidence');
  return [...evidence];
}

function prescribed(
  variantId: string,
  sets: number,
  day: CanvasDay,
  slot: CanvasSlot,
  index: number,
  priority: CanvasPriority = 'standard',
): CanvasExercise {
  const variant = catalogVariantById(variantId);
  if (!variant) throw new Error(`missing_variant:${variantId}`);
  return {
    instanceId: `${variantId}:${day}:${slot}:${index}`,
    variantId,
    name: variant.name,
    primaryMuscle: variant.primaryMuscle,
    sets,
    repRange: { ...REP_RANGE },
    targetReps: TARGET_REPS,
    targetRir: TARGET_RIR,
    priority,
    emphasis: null,
    evidenceIds: evidenceFor(variant.primaryMuscle),
  };
}

function session(day: CanvasDay, slot: CanvasSlot, rows: Array<[string, number]>): CanvasSession {
  return {
    id: `session:${day}:${slot}`,
    day,
    slot,
    title: sessionTitle(day, slot),
    exercises: rows.map(([variantId, sets], index) =>
      prescribed(variantId, sets, day, slot, index),
    ),
  };
}

function draftSessions(equipment: Equipment): CanvasSession[] {
  if (equipment === 'full_gym') {
    return [
      session('monday', 'single', [
        ['incline_dumbbell_press', 3],
        ['seated_cable_row', 3],
        ['cable_triceps_pressdown', 2],
        ['cable_lateral_raise', 2],
      ]),
      session('tuesday', 'single', [
        ['leg_press', 3],
        ['barbell_romanian_deadlift', 3],
        ['hip_thrust', 2],
        ['standing_calf_raise', 2],
      ]),
      session('thursday', 'single', [
        ['machine_chest_press', 3],
        ['lat_pulldown', 3],
        ['overhead_dumbbell_triceps_extension', 2],
        ['cable_curl', 2],
      ]),
      session('friday', 'single', [
        ['goblet_squat', 3],
        ['dumbbell_romanian_deadlift', 2],
        ['dumbbell_hip_thrust', 2],
        ['seated_calf_raise', 2],
      ]),
    ];
  }
  return [
    session('monday', 'single', [
      ['dumbbell_floor_press', 3],
      ['one_arm_dumbbell_row', 3],
      ['overhead_dumbbell_triceps_extension', 2],
      ['dumbbell_lateral_raise', 2],
    ]),
    session('tuesday', 'single', [
      ['goblet_squat', 3],
      ['dumbbell_romanian_deadlift', 3],
      ['dumbbell_split_squat', 2],
      ['standing_calf_raise', 2],
    ]),
    session('thursday', 'single', [
      ['dumbbell_curl', 3],
      ['bird_dog', 2],
      ['single_leg_calf_raise', 2],
    ]),
    session('friday', 'single', [
      ['lying_dumbbell_curl', 2],
      ['dead_bug', 2],
    ]),
  ];
}

const EMPTY_POLICY = {
  priorityMuscles: [] as MuscleGroup[],
  upperChest: false,
  maintenanceMuscles: [] as MuscleGroup[],
};

function planFrom(
  source: CanvasPlan | null,
  sessions: CanvasSession[],
  patch: Partial<Omit<CanvasPlan, 'sessions' | 'id'>> = {},
): CanvasPlan {
  return canvasPlanSchema.parse({
    id: 'canvas-plan',
    revision: source?.revision ?? 0,
    weekCount: source?.weekCount ?? 4,
    equipment: source?.equipment ?? 'full_gym',
    declaredEquipment: source?.declaredEquipment ?? [],
    goal: source?.goal ?? 'Hypertrophy',
    policy: source?.policy ?? EMPTY_POLICY,
    ...patch,
    sessions: sortSessions(sessions),
  });
}

function exercisesOf(plan: CanvasPlan): CanvasExercise[] {
  return plan.sessions.flatMap((item) => item.exercises);
}

function findExercise(plan: CanvasPlan, instanceId: string) {
  for (const item of plan.sessions) {
    const exercise = item.exercises.find((row) => row.instanceId === instanceId);
    if (exercise) return { session: item, exercise };
  }
  return null;
}

function trainingDays(plan: CanvasPlan): CanvasDay[] {
  return CANVAS_DAYS.filter((day) => plan.sessions.some((item) => item.day === day));
}

function isUpperChest(exercise: CanvasExercise): boolean {
  return exercise.primaryMuscle === 'chest' && exercise.variantId.includes('incline');
}

export function weeklyTotals(plan: CanvasPlan): Record<string, number> {
  const totals: Record<string, number> = { upper_chest: 0 };
  for (const muscle of MUSCLE_GROUPS) totals[muscle] = 0;
  for (const exercise of exercisesOf(plan)) {
    const variant = catalogVariantById(exercise.variantId);
    const contribution = variant?.muscleContribution ?? { [exercise.primaryMuscle]: 1 };
    for (const [muscle, fraction] of Object.entries(contribution)) {
      totals[muscle] = Number(totals[muscle] ?? 0) + exercise.sets * Number(fraction);
    }
    if (isUpperChest(exercise)) totals.upper_chest += exercise.sets;
  }
  return totals;
}

export function muscleGoals(plan: CanvasPlan): MuscleGoal[] {
  const totals = weeklyTotals(plan);
  const goals: MuscleGoal[] = [];
  if (totals.upper_chest > 0 || plan.policy.upperChest) {
    goals.push({
      id: 'upper_chest',
      label: 'Upper chest',
      role: plan.policy.upperChest ? 'priority' : 'standard',
      weeklySets: totals.upper_chest,
    });
  }
  for (const muscle of MUSCLE_GROUPS) {
    const weeklySets = totals[muscle] ?? 0;
    if (weeklySets <= 0 && !plan.policy.priorityMuscles.includes(muscle)) continue;
    const role: CanvasPriority = plan.policy.priorityMuscles.includes(muscle)
      ? 'priority'
      : plan.policy.maintenanceMuscles.includes(muscle)
        ? 'maintenance'
        : 'standard';
    goals.push({
      id: muscle,
      label: muscle.charAt(0).toUpperCase() + muscle.slice(1),
      role,
      weeklySets,
    });
  }
  return goals;
}

export function executionSessions(plan: CanvasPlan): ExecutionSession[] {
  return sortSessions(plan.sessions).map((item) => ({
    sessionId: item.id,
    day: item.day,
    slot: item.slot,
    title: item.title,
    exercises: item.exercises.map((exercise) => ({
      instanceId: exercise.instanceId,
      variantId: exercise.variantId,
      name: exercise.name,
      sets: exercise.sets,
      targetReps: exercise.targetReps,
      targetRir: exercise.targetRir,
    })),
  }));
}

export function canvasAgrees(plan: CanvasPlan): boolean {
  const execution = executionSessions(plan);
  const cards = sortSessions(plan.sessions);
  if (execution.length !== cards.length) return false;
  return cards.every((card, index) => {
    const workout = execution[index];
    if (
      !workout ||
      workout.sessionId !== card.id ||
      workout.exercises.length !== card.exercises.length
    ) {
      return false;
    }
    return card.exercises.every((exercise, exerciseIndex) => {
      const performed = workout.exercises[exerciseIndex];
      return (
        performed?.instanceId === exercise.instanceId &&
        performed.variantId === exercise.variantId &&
        performed.sets === exercise.sets &&
        performed.targetReps === exercise.targetReps
      );
    });
  });
}

function openProposal(ledger: CanvasLedger): StoredCanvasProposal | null {
  const open = ledger.proposals.filter((item) => item.status === 'proposed');
  return open.length > 0 ? open[open.length - 1]! : null;
}

function narrate(changes: CanvasChange[], saved: boolean): string {
  if (changes.length === 0)
    return saved ? 'Saved. The plan is unchanged.' : 'Preview. The plan is unchanged.';
  const detail = changes
    .map((change) => {
      if (change.kind === 'added') return `added ${change.name} on ${dayLabel(change.day)}`;
      if (change.kind === 'moved')
        return `moved ${change.name} from ${dayLabel(change.fromDay)} to ${dayLabel(change.toDay)} ${change.toSlot}`;
      if (change.kind === 'replaced') return `replaced ${change.fromName} with ${change.toName}`;
      return `set ${change.name} from ${change.previousSets} to ${change.sets} sets`;
    })
    .join('; ');
  return saved ? `Saved. ${detail}.` : `Preview, not saved. ${detail}.`;
}

export function readCanvasLedger(ledger: CanvasLedger | null, narration = ''): CanvasReadback {
  const source = ledger ?? emptyCanvasLedger();
  const plan = source.head;
  const proposal = ledger ? openProposal(source) : null;
  return {
    version: 1,
    write: ledger ? ledger.write : null,
    generation: source.generation,
    plan,
    goals: plan ? muscleGoals(plan) : [],
    weeklyTotals: plan ? weeklyTotals(plan) : {},
    execution: plan ? executionSessions(plan) : [],
    proposal,
    narration:
      narration ||
      (proposal ? narrate(proposal.proposal.changes, false) : plan ? 'Saved plan.' : ''),
  };
}

const FAILURE_NARRATION: Partial<Record<CanvasFailure, string>> = {
  stale_context: 'That edit is stale. The saved plan is unchanged.',
  missed_update: 'The save did not land. The saved plan is unchanged.',
  unsupported_equipment: 'Unsupported equipment. The saved plan is unchanged.',
  request_conflict: 'That edit conflicts with one already stored. The saved plan is unchanged.',
  already_decided: 'That edit was already decided. The saved plan is unchanged.',
  would_drop_training_day: 'That edit would drop a training day. The saved plan is unchanged.',
  unsupported_or_invalid_intent: 'That message is not a plan edit. Nothing was saved.',
  plan_missing: 'There is no saved plan yet. Nothing was saved.',
  nothing_to_undo: 'There is nothing to undo. The saved plan is unchanged.',
  nothing_to_redo: 'There is nothing to redo. The saved plan is unchanged.',
};

function fail(
  kind: CanvasFailure,
  ledger: CanvasLedger | null,
  missing?: CatalogEquipment[],
): CanvasCommandResult {
  const base = readCanvasLedger(ledger);
  return {
    kind,
    ...(missing ? { missing } : {}),
    readback: { ...base, narration: FAILURE_NARRATION[kind] ?? base.narration },
  };
}

function clonePlan(plan: CanvasPlan): CanvasPlan {
  return canvasPlanSchema.parse(clone(plan));
}

type Built =
  | { ok: true; preview: CanvasPlan; changes: CanvasChange[]; reason: string }
  | { ok: false; kind: CanvasFailure; missing?: CatalogEquipment[] };

function buildDraft(operation: Extract<PlanOperation, { kind: 'draft' }>): Built {
  if (operation.weekCount !== 4 && operation.weekCount !== 5 && operation.weekCount !== 6) {
    return { ok: false, kind: 'unsupported_or_invalid_intent' };
  }
  const sessions = draftSessions(operation.equipment);
  for (const item of sessions) {
    for (const exercise of item.exercises) {
      const variant = catalogVariantById(exercise.variantId);
      if (!variant || exercise.evidenceIds.length === 0)
        return { ok: false, kind: 'missing_evidence' };
      const available = resolveAvailableEquipment({ profile: operation.equipment });
      if (!isEligibleVariant(variant, { available })) {
        return {
          ok: false,
          kind: 'unsupported_equipment',
          missing: missingEquipment(variant, available),
        };
      }
    }
  }
  const preview = planFrom(null, sessions, {
    revision: 1,
    weekCount: operation.weekCount,
    equipment: operation.equipment,
    goal: operation.goal,
    policy: EMPTY_POLICY,
    declaredEquipment: [],
  });
  return {
    ok: true,
    preview,
    reason: 'Coach draft from the goal. The reviewed catalog supplies every exercise.',
    changes: preview.sessions.flatMap((item) =>
      item.exercises.map((exercise) => ({
        kind: 'added' as const,
        instanceId: exercise.instanceId,
        day: item.day,
        slot: item.slot,
        name: exercise.name,
        reason: 'Initial coach draft',
      })),
    ),
  };
}

function locate(preview: CanvasPlan, exercise: CanvasExercise) {
  const item = preview.sessions.find((session) =>
    session.exercises.some((row) => row.instanceId === exercise.instanceId),
  );
  if (!item) throw new Error('missing_exercise');
  return item;
}

function buildPrioritize(
  plan: CanvasPlan,
  operation: Extract<PlanOperation, { kind: 'prioritize' }>,
): Built {
  const maintenance = LOWER_BODY.filter((muscle) => !operation.muscles.includes(muscle));
  const changes: CanvasChange[] = [];
  const sessions = plan.sessions.map((item) => ({
    ...item,
    exercises: item.exercises.map((exercise) => {
      const upper = operation.upperChest && isUpperChest(exercise);
      const musclePriority =
        operation.muscles.includes(exercise.primaryMuscle) &&
        !(operation.upperChest && exercise.primaryMuscle === 'chest');
      const prioritized = upper || musclePriority;
      const maintain = maintenance.includes(exercise.primaryMuscle);
      if (!prioritized && !maintain) return exercise;
      const sets = prioritized ? Math.min(8, exercise.sets + 1) : exercise.sets;
      const next: CanvasExercise = {
        ...exercise,
        sets,
        priority: prioritized ? 'priority' : 'maintenance',
        emphasis: upper ? 'upper_chest' : exercise.emphasis,
      };
      if (next.sets !== exercise.sets || next.priority !== exercise.priority) {
        changes.push({
          kind: 'updated',
          instanceId: exercise.instanceId,
          name: exercise.name,
          previousSets: exercise.sets,
          sets: next.sets,
          reason: prioritized
            ? upper
              ? 'Priority for upper chest'
              : `Priority for ${exercise.primaryMuscle}`
            : 'Kept for lower-body maintenance',
        });
      }
      return next;
    }),
  }));
  const preview = planFrom(plan, sessions, {
    policy: {
      priorityMuscles: operation.muscles.filter(
        (muscle) => !(operation.upperChest && muscle === 'chest'),
      ),
      upperChest: operation.upperChest,
      maintenanceMuscles: maintenance,
    },
  });
  const beforeLower = exercisesOf(plan).filter((exercise) =>
    LOWER_BODY.includes(exercise.primaryMuscle),
  );
  const after = exercisesOf(preview);
  if (
    beforeLower.some(
      (exercise) =>
        !after.some((row) => row.instanceId === exercise.instanceId && row.sets >= exercise.sets),
    )
  ) {
    return { ok: false, kind: 'would_drop_training_day' };
  }
  return {
    ok: true,
    preview,
    changes,
    reason: 'Prioritize the requested muscles and keep lower-body work as maintenance.',
  };
}

function accessorySession(day: CanvasDay, equipment: Equipment): CanvasSession {
  const rows: Array<[string, number]> =
    equipment === 'full_gym'
      ? [
          ['one_arm_dumbbell_row', 3],
          ['dumbbell_curl', 2],
          ['dead_bug', 2],
        ]
      : [
          ['one_arm_dumbbell_row', 3],
          ['dumbbell_lateral_raise', 2],
          ['dead_bug', 2],
        ];
  return session(day, 'single', rows);
}

function buildTrainingDays(plan: CanvasPlan, count: number): Built {
  if (count < 2 || count > 6) return { ok: false, kind: 'unsupported_or_invalid_intent' };
  const current = trainingDays(plan);
  if (count < current.length) return { ok: false, kind: 'would_drop_training_day' };
  if (count === current.length) return { ok: false, kind: 'unsupported_or_invalid_intent' };
  const additions = CANVAS_DAYS.filter((day) => !current.includes(day)).slice(
    0,
    count - current.length,
  );
  const added = additions.map((day) => accessorySession(day, plan.equipment));
  const preview = planFrom(plan, [...plan.sessions, ...added]);
  return {
    ok: true,
    preview,
    reason: `Train ${count} days without removing the current days.`,
    changes: added.flatMap((item) =>
      item.exercises.map((exercise) => ({
        kind: 'added' as const,
        instanceId: exercise.instanceId,
        day: item.day,
        slot: item.slot,
        name: exercise.name,
        reason: `Added ${dayLabel(item.day)} to reach ${count} training days`,
      })),
    ),
  };
}

function buildSplit(plan: CanvasPlan, day: CanvasDay): Built {
  const onDay = plan.sessions.filter((item) => item.day === day);
  if (onDay.length !== 1 || onDay[0]!.slot !== 'single' || onDay[0]!.exercises.length < 2) {
    return { ok: false, kind: 'day_not_trainable' };
  }
  const source = onDay[0]!;
  const midpoint = Math.ceil(source.exercises.length / 2);
  const amExercises = source.exercises.slice(0, midpoint);
  const pmExercises = source.exercises.slice(midpoint);
  const make = (slot: CanvasSlot, rows: CanvasExercise[]): CanvasSession => ({
    id: `session:${day}:${slot}`,
    day,
    slot,
    title: sessionTitle(day, slot),
    exercises: rows,
  });
  const am = make('am', amExercises);
  const pm = make('pm', pmExercises);
  const preview = planFrom(
    plan,
    plan.sessions.filter((item) => item.id !== source.id).concat([am, pm]),
  );
  const changes: CanvasChange[] = [...am.exercises, ...pm.exercises].map((exercise) => ({
    kind: 'moved',
    instanceId: exercise.instanceId,
    name: exercise.name,
    fromDay: day,
    fromSlot: 'single',
    toDay: day,
    toSlot: locate(preview, exercise).slot,
    reason: `Stacked ${dayLabel(day)} into AM and PM`,
  }));
  return {
    ok: true,
    preview,
    changes,
    reason: `Split ${dayLabel(day)} into stacked AM and PM sessions.`,
  };
}

function buildSwap(plan: CanvasPlan, operation: Extract<PlanOperation, { kind: 'swap' }>): Built {
  const wanted = normalizeName(operation.exerciseName);
  const matches = exercisesOf(plan).filter((exercise) => normalizeName(exercise.name) === wanted);
  if (matches.length === 0) return { ok: false, kind: 'exercise_not_found' };
  if (matches.length > 1) return { ok: false, kind: 'ambiguous_exercise' };
  const current = matches[0]!;
  const variant = catalogVariantById(operation.toVariantId);
  if (!variant || variant.primaryMuscle !== current.primaryMuscle)
    return { ok: false, kind: 'variant_not_found' };
  const declared = [...plan.declaredEquipment, ...operation.declareEquipment];
  const available = resolveAvailableEquipment({ profile: plan.equipment, declared });
  if (!isEligibleVariant(variant, { available })) {
    return {
      ok: false,
      kind: 'unsupported_equipment',
      missing: missingEquipment(variant, available),
    };
  }
  const evidence = evidenceFor(variant.primaryMuscle);
  const sessions = plan.sessions.map((item) => ({
    ...item,
    exercises: item.exercises.map((exercise) =>
      exercise.instanceId === current.instanceId
        ? {
            ...exercise,
            variantId: variant.id,
            name: variant.name,
            primaryMuscle: variant.primaryMuscle,
            evidenceIds: evidence,
            emphasis: isUpperChest({ ...exercise, variantId: variant.id })
              ? exercise.emphasis
              : exercise.emphasis,
          }
        : exercise,
    ),
  }));
  const preview = planFrom(plan, sessions, {
    declaredEquipment: [...new Set(declared.filter((item) => item.length > 0))],
  });
  return {
    ok: true,
    preview,
    reason: `Swap ${current.name} for ${variant.name}.`,
    changes: [
      {
        kind: 'replaced',
        instanceId: current.instanceId,
        fromName: current.name,
        toName: variant.name,
        toVariantId: variant.id,
        reason: `Matched the requested ${variant.name} variant`,
      },
    ],
  };
}

function withoutExercise(plan: CanvasPlan, instanceId: string): CanvasSession[] {
  return plan.sessions
    .map((item) => ({
      ...item,
      exercises: item.exercises.filter((exercise) => exercise.instanceId !== instanceId),
    }))
    .filter((item) => item.exercises.length > 0);
}

function resolveToken(
  plan: CanvasPlan,
  token: string,
): { ok: true; instanceId: string } | { ok: false; kind: CanvasFailure } {
  if (findExercise(plan, token)) return { ok: true, instanceId: token };
  const named = exercisesOf(plan).filter(
    (exercise) => normalizeName(exercise.name) === normalizeName(token),
  );
  if (named.length > 1) return { ok: false, kind: 'ambiguous_exercise' };
  if (named.length === 1) return { ok: true, instanceId: named[0].instanceId };
  return { ok: false, kind: 'exercise_not_found' };
}

function buildMove(plan: CanvasPlan, operation: Extract<PlanOperation, { kind: 'move' }>): Built {
  const resolved = resolveToken(plan, operation.instanceId);
  if (!resolved.ok) return resolved;
  const found = findExercise(plan, resolved.instanceId);
  if (!found) return { ok: false, kind: 'exercise_not_found' };
  if (found.session.day === operation.toDay && found.session.slot === operation.toSlot) {
    return { ok: false, kind: 'unsupported_or_invalid_intent' };
  }
  const onTarget = plan.sessions.filter(
    (item) => item.day === operation.toDay && item.id !== found.session.id,
  );
  if (operation.toSlot === 'single' && onTarget.some((item) => item.slot !== 'single')) {
    return { ok: false, kind: 'session_conflict' };
  }
  if (operation.toSlot !== 'single' && onTarget.some((item) => item.slot === 'single')) {
    return { ok: false, kind: 'session_conflict' };
  }
  const remaining = withoutExercise(plan, resolved.instanceId);
  const host = remaining.find(
    (item) => item.day === operation.toDay && item.slot === operation.toSlot,
  );
  const moved = found.exercise;
  const nextSessions = host
    ? remaining.map((item) =>
        item.id === host.id ? { ...item, exercises: [...item.exercises, moved] } : item,
      )
    : remaining.concat([
        {
          id: `session:${operation.toDay}:${operation.toSlot}`,
          day: operation.toDay,
          slot: operation.toSlot,
          title: sessionTitle(operation.toDay, operation.toSlot),
          exercises: [moved],
        },
      ]);
  const preview = planFrom(plan, nextSessions);
  return {
    ok: true,
    preview,
    reason: `Move ${moved.name} to ${sessionTitle(operation.toDay, operation.toSlot)}.`,
    changes: [
      {
        kind: 'moved',
        instanceId: moved.instanceId,
        name: moved.name,
        fromDay: found.session.day,
        fromSlot: found.session.slot,
        toDay: operation.toDay,
        toSlot: operation.toSlot,
        reason: 'Direct move',
      },
    ],
  };
}

function buildSets(
  plan: CanvasPlan,
  operation: Extract<PlanOperation, { kind: 'edit_sets' }>,
): Built {
  if (operation.sets < 1 || operation.sets > 8) return { ok: false, kind: 'invalid_sets' };
  const resolved = resolveToken(plan, operation.instanceId);
  if (!resolved.ok) return resolved;
  const found = findExercise(plan, resolved.instanceId);
  if (!found) return { ok: false, kind: 'exercise_not_found' };
  if (found.exercise.sets === operation.sets)
    return { ok: false, kind: 'unsupported_or_invalid_intent' };
  const sessions = plan.sessions.map((item) => ({
    ...item,
    exercises: item.exercises.map((exercise) =>
      exercise.instanceId === found.exercise.instanceId
        ? { ...exercise, sets: operation.sets }
        : exercise,
    ),
  }));
  return {
    ok: true,
    preview: planFrom(plan, sessions),
    reason: `Set ${found.exercise.name} to ${operation.sets} sets.`,
    changes: [
      {
        kind: 'updated',
        instanceId: found.exercise.instanceId,
        name: found.exercise.name,
        previousSets: found.exercise.sets,
        sets: operation.sets,
        reason: 'Set edit',
      },
    ],
  };
}

function guardPreview(base: CanvasPlan | null, preview: CanvasPlan): CanvasFailure | null {
  if (!canvasAgrees(preview)) return 'ledger_invalid';
  if (exercisesOf(preview).some((exercise) => exercise.evidenceIds.length === 0))
    return 'missing_evidence';
  if (!base) return null;
  const kept = exercisesOf(base).filter((exercise) =>
    base.policy.maintenanceMuscles.includes(exercise.primaryMuscle),
  );
  if (
    kept.some(
      (exercise) =>
        !exercisesOf(preview).some(
          (row) => row.instanceId === exercise.instanceId && row.sets >= 1,
        ),
    )
  ) {
    return 'would_drop_training_day';
  }
  return null;
}

export function buildOperation(plan: CanvasPlan | null, operation: PlanOperation): Built {
  if (operation.kind === 'draft') {
    if (plan) return { ok: false, kind: 'unsupported_or_invalid_intent' };
    return buildDraft(operation);
  }
  if (!plan) return { ok: false, kind: 'plan_missing' };
  if (operation.kind === 'prioritize') return buildPrioritize(plan, operation);
  if (operation.kind === 'set_training_days') return buildTrainingDays(plan, operation.count);
  if (operation.kind === 'split_day') return buildSplit(plan, operation.day);
  if (operation.kind === 'swap') return buildSwap(plan, operation);
  if (operation.kind === 'move') return buildMove(plan, operation);
  if (operation.kind === 'edit_sets') return buildSets(plan, operation);
  if (operation.kind === 'undo') {
    return { ok: false, kind: 'nothing_to_undo' };
  }
  return { ok: false, kind: 'nothing_to_redo' };
}

function sessionFor(plan: CanvasPlan, instanceId: string): CanvasSession | null {
  return (
    plan.sessions.find((item) =>
      item.exercises.some((exercise) => exercise.instanceId === instanceId),
    ) ?? null
  );
}

function diffPlans(from: CanvasPlan, to: CanvasPlan, reason: string): CanvasChange[] {
  const changes: CanvasChange[] = [];
  for (const exercise of exercisesOf(to)) {
    const previous = exercisesOf(from).find((row) => row.instanceId === exercise.instanceId);
    const nextSession = sessionFor(to, exercise.instanceId);
    if (!nextSession) continue;
    if (!previous) {
      changes.push({
        kind: 'added',
        instanceId: exercise.instanceId,
        day: nextSession.day,
        slot: nextSession.slot,
        name: exercise.name,
        reason,
      });
      continue;
    }
    const previousSession = sessionFor(from, previous.instanceId);
    if (
      previousSession &&
      (previousSession.day !== nextSession.day || previousSession.slot !== nextSession.slot)
    ) {
      changes.push({
        kind: 'moved',
        instanceId: exercise.instanceId,
        name: exercise.name,
        fromDay: previousSession.day,
        fromSlot: previousSession.slot,
        toDay: nextSession.day,
        toSlot: nextSession.slot,
        reason,
      });
    }
    if (previous.variantId !== exercise.variantId) {
      changes.push({
        kind: 'replaced',
        instanceId: exercise.instanceId,
        fromName: previous.name,
        toName: exercise.name,
        toVariantId: exercise.variantId,
        reason,
      });
    }
    if (previous.sets !== exercise.sets) {
      changes.push({
        kind: 'updated',
        instanceId: exercise.instanceId,
        name: exercise.name,
        previousSets: previous.sets,
        sets: exercise.sets,
        reason,
      });
    }
  }
  return changes;
}

function historyOperation(
  ledger: CanvasLedger,
  operation: Extract<PlanOperation, { kind: 'undo' | 'redo' }>,
): Built {
  const plan = ledger.head;
  if (!plan) return { ok: false, kind: 'plan_missing' };
  const stack = operation.kind === 'undo' ? ledger.undo : ledger.redo;
  const preview = stack[stack.length - 1];
  if (!preview)
    return { ok: false, kind: operation.kind === 'undo' ? 'nothing_to_undo' : 'nothing_to_redo' };
  const reason = operation.kind === 'undo' ? 'Undo the last accepted edit' : 'Redo the undone edit';
  return {
    ok: true,
    preview: clonePlan(preview),
    changes: diffPlans(plan, preview, reason),
    reason,
  };
}

function musclesIn(text: string): { muscles: MuscleGroup[]; upperChest: boolean } | null {
  const normalized = normalizeName(text);
  const upperChest = normalized.includes('upper chest');
  const muscles = MUSCLE_GROUPS.filter((muscle) => normalized.includes(muscle));
  if (upperChest && !muscles.includes('chest')) muscles.unshift('chest');
  return muscles.length > 0 ? { muscles, upperChest } : null;
}

function variantFromPhrase(phrase: string): { id: string; declareEquipment: string[] } | null {
  const normalized = normalizeName(phrase);
  const variant =
    normalized.includes('smith') && normalized.includes('incline')
      ? catalogVariantById('smith_incline_press')
      : EXERCISE_CATALOG.find((item) => normalizeName(item.name) === normalized);
  if (!variant) return null;
  return {
    id: variant.id,
    declareEquipment: variant.requires.filter((item) => item === 'smith' || item === 'ez_bar'),
  };
}

export function interpretPlanUtterance(transcript: string): PlanOperation | null {
  const text = transcript.trim().replace(/\s+/g, ' ');
  if (!text) return null;
  if (/^undo$/i.test(text)) return { kind: 'undo' };
  if (/^redo$/i.test(text)) return { kind: 'redo' };
  const days = text.match(/\b(one|two|three|four|five|six|\d+)\s+training days\b/i);
  if (days?.[1]) {
    const raw = days[1].toLowerCase();
    const count = WORD_NUMBERS[raw] ?? Number(raw);
    return { kind: 'set_training_days', count };
  }
  const split = text.match(
    /\bsplit\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b(?:\s+into)?\s+am\s*\/?\s*pm\b/i,
  );
  if (split?.[1]) return { kind: 'split_day', day: split[1].toLowerCase() as CanvasDay };
  const prioritize = text.match(/\bprioriti[sz]e\s+(.+)$/i);
  if (prioritize?.[1]) {
    const parsed = musclesIn(prioritize[1]);
    if (!parsed) return null;
    return { kind: 'prioritize', muscles: parsed.muscles, upperChest: parsed.upperChest };
  }
  const swap = text.match(/\bswap\s+(.+?)\s+for\s+(?:the\s+)?(.+)$/i);
  if (swap?.[1] && swap[2]) {
    const target = variantFromPhrase(swap[2]);
    if (!target) return null;
    return {
      kind: 'swap',
      exerciseName: swap[1],
      toVariantId: target.id,
      declareEquipment: target.declareEquipment,
    };
  }
  const move = text.match(
    /\bmove\s+(.+?)\s+to\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s+(am|pm))?\b/i,
  );
  if (move?.[1] && move[2]) {
    return {
      kind: 'move',
      instanceId: move[1],
      toDay: move[2].toLowerCase() as CanvasDay,
      toSlot: (move[3]?.toLowerCase() as CanvasSlot) || 'single',
    };
  }
  const sets = text.match(/\bset\s+(.+?)\s+to\s+(\d+)\s+sets?\b/i);
  if (sets?.[1] && sets[2]) {
    return { kind: 'edit_sets', instanceId: sets[1], sets: Number(sets[2]) };
  }
  if (
    /\b(plan|mesocycle|program)\b/i.test(text) &&
    /\b(build|draft|make|create|start)\b/i.test(text)
  ) {
    const week = text.match(/\b(\d+)\s*-?\s*weeks?\b/i);
    const equipment: Equipment =
      /\bdumbbells?\b/i.test(text) && !/\bgym\b/i.test(text) ? 'dumbbells' : 'full_gym';
    return {
      kind: 'draft',
      goal: text,
      equipment,
      weekCount: week?.[1] ? Number(week[1]) : 4,
    };
  }
  return null;
}

/** Chat and voice both stop here. Naming an edit does not store or apply it. */
export function planUtteranceProposal(
  transcript: string,
):
  | { kind: 'plan_edit'; requiresConfirmation: true; applied: false; operation: PlanOperation }
  | { kind: 'message' } {
  const operation = interpretPlanUtterance(transcript);
  if (!operation) return { kind: 'message' };
  return { kind: 'plan_edit', requiresConfirmation: true, applied: false, operation };
}

function storedByRequest(ledger: CanvasLedger, requestId: string) {
  return ledger.proposals.find((item) => item.proposal.requestId === requestId) ?? null;
}

async function commit(
  port: CanvasLedgerPort,
  subject: string,
  expectedWrite: number | null,
  ledger: CanvasLedger,
  narration: string,
  result: (readback: CanvasReadback) => CanvasCommandResult,
): Promise<CanvasCommandResult> {
  const parsed = canvasLedgerSchema.safeParse(ledger);
  if (!parsed.success) return fail('ledger_invalid', null);
  const saved = await port.save(subject, expectedWrite, parsed.data);
  if (saved.kind === 'canonical_revision_required') return fail(saved.kind, null);
  if (saved.kind === 'missed_update') return fail('missed_update', await port.load(subject));
  if (saved.kind === 'stale') return fail('stale_context', await port.load(subject));
  return result(readCanvasLedger(parsed.data, narration));
}

export async function readCanvas(
  port: CanvasLedgerPort,
  subject: string,
): Promise<CanvasCommandResult> {
  const loaded = await port.load(subject);
  if (loaded && !canvasLedgerSchema.safeParse(loaded).success) return fail('ledger_invalid', null);
  return { kind: 'read', readback: readCanvasLedger(loaded) };
}

export async function proposeCanvasEdit(
  port: CanvasLedgerPort,
  subject: string,
  input: { requestId: string; expectedWrite: number | null; operation: PlanOperation; now: string },
): Promise<CanvasCommandResult> {
  if (!z.string().uuid().safeParse(input.requestId).success)
    return fail('unsupported_or_invalid_intent', await port.load(subject));
  const loaded = await port.load(subject);
  const ledger = loaded ?? emptyCanvasLedger();
  if (
    (loaded?.write ?? null) !== input.expectedWrite &&
    storedByRequest(ledger, input.requestId) === null
  ) {
    return fail('stale_context', loaded);
  }
  const key = requestKey(input.operation);
  const existing = storedByRequest(ledger, input.requestId);
  if (existing) {
    return existing.proposal.requestKey === key
      ? {
          kind: 'proposed',
          proposal: existing.proposal,
          readback: readCanvasLedger(ledger, narrate(existing.proposal.changes, false)),
        }
      : fail('request_conflict', ledger);
  }
  const parsedOperation = operationSchema.safeParse(input.operation);
  if (!parsedOperation.success) return fail('unsupported_or_invalid_intent', ledger);
  const built =
    parsedOperation.data.kind === 'undo' || parsedOperation.data.kind === 'redo'
      ? historyOperation(ledger, parsedOperation.data)
      : buildOperation(ledger.head, parsedOperation.data);
  if (!built.ok) return fail(built.kind, ledger, built.missing);
  const guard = guardPreview(ledger.head, built.preview);
  if (guard) return fail(guard, ledger);
  const proposal = proposalSchema.parse({
    id: input.requestId,
    requestId: input.requestId,
    requestKey: key,
    baseWrite: ledger.write,
    baseGeneration: ledger.generation,
    baseRevision: ledger.head?.revision ?? 0,
    operation: parsedOperation.data,
    reason: built.reason,
    changes: built.changes,
    preview: built.preview,
    createdAt: input.now,
  });
  const next: CanvasLedger = {
    ...ledger,
    write: ledger.write + 1,
    proposals: [...ledger.proposals, { proposal, status: 'proposed', receipt: null }],
  };
  return commit(
    port,
    subject,
    loaded?.write ?? null,
    next,
    narrate(built.changes, false),
    (readback) => ({
      kind: 'proposed',
      proposal,
      readback,
    }),
  );
}

export async function amendCanvasProposal(
  port: CanvasLedgerPort,
  subject: string,
  input: { proposalId: string; instanceId: string; sets: number; expectedWrite: number | null },
): Promise<CanvasCommandResult> {
  const loaded = await port.load(subject);
  if (!loaded || loaded.write !== input.expectedWrite) return fail('stale_context', loaded);
  if (input.sets < 1 || input.sets > 8) return fail('invalid_sets', loaded);
  const stored = loaded.proposals.find((item) => item.proposal.id === input.proposalId) ?? null;
  if (!stored) return fail('proposal_not_found', loaded);
  if (stored.status !== 'proposed') return fail('already_decided', loaded);
  const found = findExercise(stored.proposal.preview, input.instanceId);
  if (!found) return fail('exercise_not_found', loaded);
  const preview = planFrom(
    stored.proposal.preview,
    stored.proposal.preview.sessions.map((item) => ({
      ...item,
      exercises: item.exercises.map((exercise) =>
        exercise.instanceId === input.instanceId ? { ...exercise, sets: input.sets } : exercise,
      ),
    })),
  );
  const guard = guardPreview(loaded.head, preview);
  if (guard) return fail(guard, loaded);
  const changes = stored.proposal.changes.filter(
    (change) =>
      !(
        change.kind === 'updated' &&
        change.instanceId === input.instanceId &&
        change.reason === 'Selective edit before accept'
      ),
  );
  changes.push({
    kind: 'updated',
    instanceId: input.instanceId,
    name: found.exercise.name,
    previousSets: found.exercise.sets,
    sets: input.sets,
    reason: 'Selective edit before accept',
  });
  const proposal = proposalSchema.parse({ ...stored.proposal, preview, changes });
  const next: CanvasLedger = {
    ...loaded,
    write: loaded.write + 1,
    proposals: loaded.proposals.map((item) =>
      item.proposal.id === proposal.id ? { ...item, proposal } : item,
    ),
  };
  return commit(port, subject, loaded.write, next, narrate(changes, false), (readback) => ({
    kind: 'proposed',
    proposal,
    readback,
  }));
}

export async function decideCanvasProposal(
  port: CanvasLedgerPort,
  subject: string,
  input: {
    requestId: string;
    proposalId: string;
    decision: 'apply' | 'reject';
    expectedWrite: number | null;
    now: string;
  },
): Promise<CanvasCommandResult> {
  if (
    !z.string().uuid().safeParse(input.requestId).success ||
    !z.string().uuid().safeParse(input.proposalId).success
  ) {
    return fail('unsupported_or_invalid_intent', await port.load(subject));
  }
  const loaded = await port.load(subject);
  if (!loaded) return fail('proposal_not_found', null);
  const decisionKey = requestKey({ proposalId: input.proposalId, decision: input.decision });
  const replay =
    loaded.proposals.find((item) => item.receipt?.requestId === input.requestId) ?? null;
  if (replay?.receipt) {
    return replay.receipt.requestKey === decisionKey
      ? { kind: 'decided', receipt: replay.receipt, readback: readCanvasLedger(loaded) }
      : fail('request_conflict', loaded);
  }
  if (loaded.write !== input.expectedWrite) return fail('stale_context', loaded);
  const stored = loaded.proposals.find((item) => item.proposal.id === input.proposalId) ?? null;
  if (!stored) return fail('proposal_not_found', loaded);
  if (stored.status !== 'proposed' || stored.receipt) return fail('already_decided', loaded);
  if (
    stored.proposal.baseGeneration !== loaded.generation ||
    (loaded.head?.revision ?? 0) !== stored.proposal.baseRevision
  ) {
    return fail('stale_context', loaded);
  }
  const guard = guardPreview(loaded.head, stored.proposal.preview);
  if (input.decision === 'apply' && guard) return fail(guard, loaded);
  const applied = input.decision === 'apply';
  let head = loaded.head;
  let undo = loaded.undo;
  let redo = loaded.redo;
  let revision: number | null = null;
  if (applied) {
    const preview = clonePlan(stored.proposal.preview);
    preview.revision = (loaded.head?.revision ?? 0) + 1;
    revision = preview.revision;
    if (stored.proposal.operation.kind === 'undo') {
      redo = loaded.head ? [...loaded.redo, clonePlan(loaded.head)] : loaded.redo;
      undo = loaded.undo.slice(0, -1);
    } else if (stored.proposal.operation.kind === 'redo') {
      undo = loaded.head ? [...loaded.undo, clonePlan(loaded.head)] : loaded.undo;
      redo = loaded.redo.slice(0, -1);
    } else if (loaded.head) {
      undo = [...loaded.undo, clonePlan(loaded.head)];
      redo = [];
    }
    head = canvasPlanSchema.parse(preview);
  }
  const receipt = receiptSchema.parse({
    proposalId: stored.proposal.id,
    requestId: input.requestId,
    requestKey: decisionKey,
    decision: input.decision,
    status: applied ? 'applied' : 'rejected',
    generation: loaded.generation + 1,
    revision,
    decidedAt: input.now,
  });
  const next: CanvasLedger = {
    ...loaded,
    write: loaded.write + 1,
    generation: loaded.generation + 1,
    head,
    undo,
    redo,
    proposals: loaded.proposals.map((item) =>
      item.proposal.id === stored.proposal.id ? { ...item, status: receipt.status, receipt } : item,
    ),
  };
  const narration = applied
    ? narrate(stored.proposal.changes, true)
    : 'Rejected. The saved plan is unchanged.';
  return commit(port, subject, loaded.write, next, narration, (readback) => ({
    kind: 'decided',
    receipt,
    readback,
  }));
}

export function resolveMoveTarget(plan: CanvasPlan, name: string): string | null {
  const matches = exercisesOf(plan).filter(
    (exercise) => normalizeName(exercise.name) === normalizeName(name),
  );
  return matches.length === 1 ? matches[0]!.instanceId : null;
}
