import {
  catalogVariantById,
  CATALOG_EQUIPMENT,
  missingEquipment,
  type CatalogEquipment,
} from './catalog';
import { MUSCLE_GROUPS, type Equipment, type MuscleGroup, type Session } from './types';

/** Plans are JSON data. A local clone avoids host globals that jsdom omits. */
function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

/** Smith incline is a catalog variant, never inferred from a generic press. */
export const SMITH_INCLINE_VARIANT_ID = 'smith_machine_incline_press';
export const INCLINE_DUMBBELL_PRESS_ID = 'incline_dumbbell_press';

export const CANVAS_DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const;
export type CanvasDayId = (typeof CANVAS_DAYS)[number];
const WEEKDAY: CanvasDayId[] = ['mon', 'tue', 'wed', 'thu', 'fri'];
const LOWER_MUSCLES = new Set<MuscleGroup>(['quads', 'hamstrings', 'glutes', 'calves']);
const DAY_LABEL: Record<CanvasDayId, string> = {
  mon: 'Monday',
  tue: 'Tuesday',
  wed: 'Wednesday',
  thu: 'Thursday',
  fri: 'Friday',
  sat: 'Saturday',
  sun: 'Sunday',
};

export type CanvasPriority = 'priority' | 'maintenance' | 'standard';
export type CanvasChange = 'added' | 'moved' | 'replaced' | 'updated' | 'kept';

export type CanvasExercise = {
  instanceId: string;
  variantId: string;
  name: string;
  primaryMuscle: MuscleGroup;
  muscleContribution: Partial<Record<MuscleGroup, number>>;
  sets: number;
  repRange: { min: number; max: number };
  targetReps: number;
  targetRir: number;
  priority: CanvasPriority;
  evidenceIds: string[];
};

export type CanvasSession = {
  id: string;
  period: 'day' | 'am' | 'pm';
  title: string;
  exercises: CanvasExercise[];
};

export type CanvasDay = {
  id: CanvasDayId;
  label: string;
  sessions: CanvasSession[];
};

export type CanvasGoal = {
  id: string;
  label: string;
  role: CanvasPriority;
  weeklySets: number;
};

export type CanvasPlan = {
  version: 1;
  policyVersion: 'mesocycle-canvas-v1';
  weekCount: 4 | 5 | 6;
  currentWeek: number;
  equipmentProfile: Equipment;
  availableEquipment: CatalogEquipment[];
  goals: CanvasGoal[];
  days: CanvasDay[];
  weeklyTotals: Record<string, number>;
};

export type CanvasHighlight = {
  instanceId: string;
  change: CanvasChange;
  reason: string;
};

export type CanvasOp =
  | { id: string; kind: 'draft' }
  | { id: string; kind: 'prioritize'; target: 'upper_chest' | 'triceps' }
  | { id: string; kind: 'training_days'; count: 5 }
  | { id: string; kind: 'split_day'; day: 'wed' }
  | { id: string; kind: 'swap_variant'; toVariantId: typeof SMITH_INCLINE_VARIANT_ID }
  | { id: string; kind: 'declare_equipment'; item: CatalogEquipment }
  | {
      id: string;
      kind: 'move';
      instanceId: string;
      toDay: CanvasDayId;
      toSessionId: string;
      toIndex: number;
    }
  | { id: string; kind: 'set_sets'; instanceId: string; sets: number }
  | { id: string; kind: 'undo' }
  | { id: string; kind: 'redo' };

export type CanvasSource = 'chat' | 'voice' | 'direct';

export type CanvasProposeCommand = {
  type: 'propose';
  requestId: string;
  expectedGeneration: number;
  baseRevisionId: string | null;
  source: CanvasSource;
  text?: string;
  ops?: CanvasOp[];
};

export type CanvasDecideCommand = {
  type: 'decide';
  requestId: string;
  proposalId: string;
  expectedGeneration: number;
  decision: 'apply' | 'reject';
  acceptedOpIds?: string[];
  setEdits?: Array<{ instanceId: string; sets: number }>;
};

export type CanvasCommand = CanvasProposeCommand | CanvasDecideCommand;

const GUARDED_KINDS = new Set<CanvasOp['kind']>([
  'prioritize',
  'training_days',
  'split_day',
  'swap_variant',
  'declare_equipment',
]);

export type CanvasReceipt = {
  version: 1;
  proposalId: string;
  requestId: string;
  decision: 'apply' | 'reject';
  status: 'applied' | 'rejected';
  revisionId: string | null;
  priorRevisionId: string | null;
  planFingerprint: string | null;
  decidedAt: string;
};

export type CanvasProposal = {
  id: string;
  requestId: string;
  requestHash: string;
  generation: number;
  baseRevisionId: string | null;
  source: CanvasSource;
  utterance: string | null;
  ops: CanvasOp[];
  basePlan: CanvasPlan | null;
  preview: CanvasPlan;
  highlights: CanvasHighlight[];
  status: 'proposed' | 'applied' | 'rejected';
  decision: { requestId: string; requestHash: string; receipt: CanvasReceipt } | null;
};

export type CanvasRevision = {
  id: string;
  proposalId: string;
  plan: CanvasPlan;
};

export type CanvasJournal = {
  version: 1;
  generation: number;
  applied: CanvasRevision[];
  head: number;
  proposals: CanvasProposal[];
};

export type CanvasFailure =
  | { kind: 'stale_context' }
  | { kind: 'request_conflict' }
  | { kind: 'already_decided' }
  | { kind: 'proposal_not_found' }
  | { kind: 'unsupported_command' }
  | { kind: 'unsupported_equipment'; missing: string[] }
  | { kind: 'invalid_operation'; reason: string }
  | { kind: 'nothing_to_undo' }
  | { kind: 'nothing_to_redo' }
  | { kind: 'owner_missing' };

export type CanvasSuccess =
  | { kind: 'proposed'; proposal: CanvasProposal; narration: string; replay: boolean }
  | {
      kind: 'decided';
      receipt: CanvasReceipt;
      plan: CanvasPlan | null;
      narration: string;
      replay: boolean;
    };

export type CanvasResult = CanvasSuccess | CanvasFailure;

export type CanvasPort = {
  read(subject: string): Promise<CanvasJournal | null>;
  write(
    subject: string,
    expectedGeneration: number,
    journal: CanvasJournal,
  ): Promise<'ok' | 'conflict' | 'owner_missing'>;
};

type OpOk = { ok: true; plan: CanvasPlan; highlights: CanvasHighlight[] };
type OpFail = { ok: false; result: CanvasFailure };
type OpResult = OpOk | OpFail;

function canonicalize(item: unknown): unknown {
  if (Array.isArray(item)) return item.map(canonicalize);
  if (item && typeof item === 'object') {
    return Object.fromEntries(
      Object.entries(item)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([key, value]) => [key, canonicalize(value)]),
    );
  }
  return item;
}

/** Stable request identity shared by chat, voice, and direct edits. */
export function canvasRequestHash(value: unknown): string {
  const text = JSON.stringify(canonicalize(value));
  let h1 = 0x811c9dc5;
  let h2 = 0x811c9dc5 ^ 0x01000193;
  for (let i = 0; i < text.length; i += 1) {
    const code = text.charCodeAt(i);
    h1 ^= code;
    h1 = Math.imul(h1, 0x01000193);
    h2 ^= code;
    h2 = Math.imul(h2, 0x01000193);
  }
  return `${(h1 >>> 0).toString(16).padStart(8, '0')}${(h2 >>> 0).toString(16).padStart(8, '0')}`;
}

export function emptyJournal(): CanvasJournal {
  return { version: 1, generation: 0, applied: [], head: -1, proposals: [] };
}

export function persistedPlan(journal: CanvasJournal): CanvasPlan | null {
  if (journal.head < 0) return null;
  return journal.applied[journal.head]?.plan ?? null;
}

function currentRevisionId(journal: CanvasJournal): string | null {
  if (journal.head < 0) return null;
  return journal.applied[journal.head]?.id ?? null;
}

function sortDays(days: CanvasDay[]): CanvasDay[] {
  return [...days].sort((a, b) => CANVAS_DAYS.indexOf(a.id) - CANVAS_DAYS.indexOf(b.id));
}

function allExercises(plan: CanvasPlan): CanvasExercise[] {
  return plan.days.flatMap((day) => day.sessions.flatMap((session) => session.exercises));
}

export function isUpperChestExercise(exercise: CanvasExercise): boolean {
  const variant = catalogVariantById(exercise.variantId);
  return variant?.primaryMuscle === 'chest' && (variant.benchAngleDeg ?? 0) >= 30;
}

function isLower(exercise: CanvasExercise): boolean {
  return LOWER_MUSCLES.has(exercise.primaryMuscle);
}

export function weeklyTotals(plan: CanvasPlan): Record<string, number> {
  const totals: Record<string, number> = Object.fromEntries(
    MUSCLE_GROUPS.map((muscle) => [muscle, 0]),
  );
  totals.upper_chest = 0;
  for (const exercise of allExercises(plan)) {
    for (const [muscle, fraction] of Object.entries(exercise.muscleContribution)) {
      totals[muscle] = (totals[muscle] ?? 0) + exercise.sets * Number(fraction);
    }
    if (isUpperChestExercise(exercise)) totals.upper_chest += exercise.sets;
  }
  for (const key of Object.keys(totals)) totals[key] = Math.round(totals[key] * 100) / 100;
  return totals;
}

function roleFor(
  exercises: CanvasExercise[],
  matches: (exercise: CanvasExercise) => boolean,
): CanvasPriority {
  const relevant = exercises.filter(matches);
  if (relevant.length === 0) return 'standard';
  if (relevant.every((exercise) => exercise.priority === 'maintenance')) return 'maintenance';
  if (relevant.some((exercise) => exercise.priority === 'priority')) return 'priority';
  return 'standard';
}

const GOAL_LABEL: Record<string, string> = {
  upper_chest: 'Upper chest',
  chest: 'Chest',
  back: 'Back',
  shoulders: 'Shoulders',
  biceps: 'Biceps',
  triceps: 'Triceps',
  quads: 'Quads',
  hamstrings: 'Hamstrings',
  glutes: 'Glutes',
  calves: 'Calves',
  core: 'Core',
};

function goalsFor(plan: CanvasPlan, totals: Record<string, number>): CanvasGoal[] {
  const exercises = allExercises(plan);
  const ids = ['upper_chest', ...MUSCLE_GROUPS];
  return ids
    .filter((id) => (totals[id] ?? 0) > 0)
    .map((id) => ({
      id,
      label: GOAL_LABEL[id] ?? id,
      role:
        id === 'upper_chest'
          ? roleFor(exercises, isUpperChestExercise)
          : roleFor(exercises, (exercise) => exercise.primaryMuscle === id),
      weeklySets: totals[id] ?? 0,
    }));
}

function finish(plan: CanvasPlan): CanvasPlan {
  const next: CanvasPlan = { ...plan, days: sortDays(plan.days), goals: [], weeklyTotals: {} };
  next.weeklyTotals = weeklyTotals(next);
  next.goals = goalsFor(next, next.weeklyTotals);
  return next;
}

function exerciseFromVariant(day: CanvasDayId, variantId: string, sets = 3): CanvasExercise {
  const variant = catalogVariantById(variantId);
  if (!variant) throw new Error(`missing_catalog_variant:${variantId}`);
  return {
    instanceId: `ex:${day}:${variantId}`,
    variantId: variant.id,
    name: variant.name,
    primaryMuscle: variant.primaryMuscle,
    muscleContribution: { ...variant.muscleContribution },
    sets,
    repRange: { min: 8, max: 12 },
    targetReps: 10,
    targetRir: 4,
    priority: 'standard',
    evidenceIds: ['k:81c218db'],
  };
}

function column(day: CanvasDayId, title: string, variants: string[]): CanvasDay {
  return {
    id: day,
    label: DAY_LABEL[day],
    sessions: [
      {
        id: `${day}:day`,
        period: 'day',
        title,
        exercises: variants.map((variantId) => exerciseFromVariant(day, variantId)),
      },
    ],
  };
}

/** One coach draft. Later utterances edit this plan; they do not invent a second program. */
export function coachDraftPlan(): CanvasPlan {
  return finish({
    version: 1,
    policyVersion: 'mesocycle-canvas-v1',
    weekCount: 4,
    currentWeek: 1,
    equipmentProfile: 'dumbbells',
    availableEquipment: ['dumbbells', 'bench', 'adjustable_bench', 'bodyweight'],
    goals: [],
    days: [
      column('mon', 'Lower body', ['goblet_squat', 'dumbbell_romanian_deadlift']),
      column('tue', 'Pull', ['one_arm_dumbbell_row', 'dumbbell_curl']),
      column('wed', 'Push', [
        INCLINE_DUMBBELL_PRESS_ID,
        'overhead_dumbbell_triceps_extension',
        'dumbbell_lateral_raise',
      ]),
      column('fri', 'Lower maintenance', ['dumbbell_hip_thrust', 'split_squat']),
    ],
    weeklyTotals: {},
  });
}

function fail(kind: CanvasFailure['kind'], extra?: Record<string, unknown>): OpFail {
  return { ok: false, result: { kind, ...extra } as CanvasFailure };
}

function mapExercises(
  plan: CanvasPlan,
  visit: (exercise: CanvasExercise, day: CanvasDay, session: CanvasSession) => CanvasExercise,
): CanvasPlan {
  return {
    ...plan,
    days: plan.days.map((day) => ({
      ...day,
      sessions: day.sessions.map((session) => ({
        ...session,
        exercises: session.exercises.map((exercise) => visit(exercise, day, session)),
      })),
    })),
  };
}

function applyDraft(plan: CanvasPlan | null): OpResult {
  if (plan) return fail('invalid_operation', { reason: 'already_drafted' });
  const draft = coachDraftPlan();
  return {
    ok: true,
    plan: draft,
    highlights: allExercises(draft).map((exercise) => ({
      instanceId: exercise.instanceId,
      change: 'added' as const,
      reason: 'Coach draft for a 4-week hypertrophy mesocycle',
    })),
  };
}

function applyPriority(plan: CanvasPlan, target: 'upper_chest' | 'triceps'): OpResult {
  const highlights: CanvasHighlight[] = [];
  let next = mapExercises(plan, (exercise) => {
    if (target === 'upper_chest' && isUpperChestExercise(exercise)) {
      highlights.push({
        instanceId: exercise.instanceId,
        change: 'updated',
        reason: 'Prioritize upper chest',
      });
      return { ...exercise, priority: 'priority', sets: Math.min(6, exercise.sets + 1) };
    }
    if (target === 'triceps' && exercise.primaryMuscle === 'triceps') {
      highlights.push({
        instanceId: exercise.instanceId,
        change: 'updated',
        reason: 'Prioritize triceps',
      });
      return { ...exercise, priority: 'priority', sets: Math.min(6, exercise.sets + 1) };
    }
    if (isLower(exercise) && exercise.priority !== 'maintenance') {
      highlights.push({
        instanceId: exercise.instanceId,
        change: 'kept',
        reason: 'Keep lower-body maintenance',
      });
      return { ...exercise, priority: 'maintenance' };
    }
    return exercise;
  });
  if (
    target === 'triceps' &&
    !allExercises(next).some((exercise) => exercise.primaryMuscle === 'triceps')
  ) {
    const variant = catalogVariantById('overhead_dumbbell_triceps_extension');
    if (!variant || missingEquipment(variant, new Set(next.availableEquipment)).length > 0) {
      return fail('unsupported_equipment', {
        missing: variant
          ? missingEquipment(variant, new Set(next.availableEquipment))
          : ['dumbbells'],
      });
    }
    const added = { ...exerciseFromVariant('wed', variant.id, 3), priority: 'priority' as const };
    next = {
      ...next,
      days: next.days.map((day) =>
        day.id === 'wed'
          ? {
              ...day,
              sessions: day.sessions.map((session, index) =>
                index === 0 ? { ...session, exercises: [...session.exercises, added] } : session,
              ),
            }
          : day,
      ),
    };
    highlights.push({
      instanceId: added.instanceId,
      change: 'added',
      reason: 'Add a triceps exercise so the priority is actually trained',
    });
  }
  return { ok: true, plan: finish(next), highlights };
}

function nonLowerCount(day: CanvasDay): number {
  return day.sessions.reduce(
    (count, session) => count + session.exercises.filter((exercise) => !isLower(exercise)).length,
    0,
  );
}

function takeLastMovable(days: CanvasDay[], target: CanvasDayId): CanvasExercise | null {
  const ranked = days
    .filter((day) => day.id !== target)
    .map((day) => {
      let found: { session: CanvasSession; index: number } | null = null;
      for (const session of [...day.sessions].reverse()) {
        for (let index = session.exercises.length - 1; index >= 0; index -= 1) {
          if (!isLower(session.exercises[index])) {
            found = { session, index };
            break;
          }
        }
        if (found) break;
      }
      return { day, found };
    })
    .filter((item): item is { day: CanvasDay; found: { session: CanvasSession; index: number } } =>
      Boolean(item.found),
    )
    .sort((a, b) => {
      const byCount = nonLowerCount(b.day) - nonLowerCount(a.day);
      if (byCount !== 0) return byCount;
      return CANVAS_DAYS.indexOf(a.day.id) - CANVAS_DAYS.indexOf(b.day.id);
    });
  const donor = ranked[0];
  if (!donor) return null;
  const dayCount = donor.day.sessions.reduce(
    (count, session) => count + session.exercises.length,
    0,
  );
  if (dayCount < 2) return null;
  const [exercise] = donor.found.session.exercises.splice(donor.found.index, 1);
  return exercise ?? null;
}

function applyFiveDays(plan: CanvasPlan): OpResult {
  let days = sortDays(clone(plan.days));
  for (const id of WEEKDAY) {
    if (!days.some((day) => day.id === id)) {
      days.push({
        id,
        label: DAY_LABEL[id],
        sessions: [{ id: `${id}:day`, period: 'day', title: DAY_LABEL[id], exercises: [] }],
      });
    }
  }
  days = sortDays(days);
  const highlights: CanvasHighlight[] = [];
  for (const day of days) {
    if (!WEEKDAY.includes(day.id)) continue;
    const count = day.sessions.reduce((sum, session) => sum + session.exercises.length, 0);
    if (count > 0) continue;
    const exercise = takeLastMovable(days, day.id);
    if (!exercise) return fail('invalid_operation', { reason: 'cannot_fill_day' });
    day.sessions[0]?.exercises.push(exercise);
    highlights.push({
      instanceId: exercise.instanceId,
      change: 'moved',
      reason: `Open ${day.label} so this mesocycle has five training days`,
    });
  }
  const trained = days.filter(
    (day) =>
      WEEKDAY.includes(day.id) && day.sessions.some((session) => session.exercises.length > 0),
  );
  if (trained.length < 5) return fail('invalid_operation', { reason: 'cannot_fill_day' });
  return { ok: true, plan: finish({ ...plan, days }), highlights };
}

function applySplitWednesday(plan: CanvasPlan): OpResult {
  const day = plan.days.find((item) => item.id === 'wed');
  if (!day) return fail('invalid_operation', { reason: 'missing_day' });
  if (day.sessions.length !== 1) return fail('invalid_operation', { reason: 'already_split' });
  const session = day.sessions[0];
  if (!session || session.exercises.length < 2)
    return fail('invalid_operation', { reason: 'nothing_to_split' });
  const mid = Math.ceil(session.exercises.length / 2);
  const amExercises = session.exercises.slice(0, mid);
  const pmExercises = session.exercises.slice(mid);
  const nextDays = plan.days.map((item) =>
    item.id !== 'wed'
      ? item
      : {
          ...item,
          sessions: [
            { id: 'wed:am', period: 'am' as const, title: 'Wednesday AM', exercises: amExercises },
            { id: 'wed:pm', period: 'pm' as const, title: 'Wednesday PM', exercises: pmExercises },
          ],
        },
  );
  const highlights: CanvasHighlight[] = [
    ...amExercises.map((exercise) => ({
      instanceId: exercise.instanceId,
      change: 'updated' as const,
      reason: 'Keep this exercise in the Wednesday AM session',
    })),
    ...pmExercises.map((exercise) => ({
      instanceId: exercise.instanceId,
      change: 'moved' as const,
      reason: 'Split Wednesday into stacked AM and PM sessions',
    })),
  ];
  return { ok: true, plan: finish({ ...plan, days: nextDays }), highlights };
}

function applySwap(plan: CanvasPlan, toVariantId: string): OpResult {
  if (toVariantId !== SMITH_INCLINE_VARIANT_ID) {
    return fail('invalid_operation', { reason: 'unknown_variant' });
  }
  const variant = catalogVariantById(toVariantId);
  if (!variant) return fail('invalid_operation', { reason: 'unknown_variant' });
  const missing = missingEquipment(variant, new Set(plan.availableEquipment));
  if (missing.length > 0) return fail('unsupported_equipment', { missing });
  let found = false;
  const highlights: CanvasHighlight[] = [];
  const next = mapExercises(plan, (exercise) => {
    if (exercise.variantId !== INCLINE_DUMBBELL_PRESS_ID) return exercise;
    found = true;
    highlights.push({
      instanceId: exercise.instanceId,
      change: 'replaced',
      reason: 'Swap incline dumbbell press for Smith machine incline press',
    });
    return {
      ...exercise,
      variantId: variant.id,
      name: variant.name,
      primaryMuscle: variant.primaryMuscle,
      muscleContribution: { ...variant.muscleContribution },
    };
  });
  if (!found) return fail('invalid_operation', { reason: 'missing_exercise' });
  return { ok: true, plan: finish(next), highlights };
}

function applyDeclare(plan: CanvasPlan, item: CatalogEquipment): OpResult {
  if (!(CATALOG_EQUIPMENT as readonly string[]).includes(item)) {
    return fail('invalid_operation', { reason: 'unknown_equipment' });
  }
  if (plan.availableEquipment.includes(item)) {
    return { ok: true, plan, highlights: [] };
  }
  return {
    ok: true,
    plan: finish({ ...plan, availableEquipment: [...plan.availableEquipment, item] }),
    highlights: [],
  };
}

function locate(plan: CanvasPlan, instanceId: string) {
  for (const day of plan.days) {
    for (const session of day.sessions) {
      const index = session.exercises.findIndex((exercise) => exercise.instanceId === instanceId);
      if (index >= 0) return { day, session, index, exercise: session.exercises[index] };
    }
  }
  return null;
}

function applyMove(plan: CanvasPlan, op: Extract<CanvasOp, { kind: 'move' }>): OpResult {
  const next = clone(plan);
  const from = locate(next, op.instanceId);
  if (!from?.exercise) return fail('invalid_operation', { reason: 'missing_exercise' });
  const targetDay = next.days.find((day) => day.id === op.toDay);
  const target = targetDay?.sessions.find((session) => session.id === op.toSessionId);
  if (!targetDay || !target) return fail('invalid_operation', { reason: 'bad_target' });
  if (from.session.id === target.id && from.index === op.toIndex) {
    return fail('invalid_operation', { reason: 'no_change' });
  }
  const [exercise] = from.session.exercises.splice(from.index, 1);
  if (!exercise) return fail('invalid_operation', { reason: 'missing_exercise' });
  const index = Math.max(0, Math.min(op.toIndex, target.exercises.length));
  target.exercises.splice(index, 0, exercise);
  return {
    ok: true,
    plan: finish(next),
    highlights: [
      {
        instanceId: exercise.instanceId,
        change: 'moved',
        reason: `Move ${exercise.name} to ${targetDay.label}`,
      },
    ],
  };
}

function applySetCount(plan: CanvasPlan, op: Extract<CanvasOp, { kind: 'set_sets' }>): OpResult {
  if (!Number.isInteger(op.sets) || op.sets < 1 || op.sets > 6) {
    return fail('invalid_operation', { reason: 'bad_sets' });
  }
  const current = locate(plan, op.instanceId);
  if (!current?.exercise) return fail('invalid_operation', { reason: 'missing_exercise' });
  if (current.exercise.sets === op.sets) return fail('invalid_operation', { reason: 'no_change' });
  const next = mapExercises(plan, (exercise) =>
    exercise.instanceId === op.instanceId ? { ...exercise, sets: op.sets } : exercise,
  );
  return {
    ok: true,
    plan: finish(next),
    highlights: [
      {
        instanceId: op.instanceId,
        change: 'updated',
        reason: `Set ${current.exercise.name} to ${op.sets} sets`,
      },
    ],
  };
}

export function applyCanvasOps(plan: CanvasPlan | null, ops: CanvasOp[]): OpResult {
  if (ops.length === 0) return fail('invalid_operation', { reason: 'empty_edit' });
  if (ops.some((op) => op.kind === 'undo' || op.kind === 'redo')) {
    return fail('invalid_operation', { reason: 'undo_is_separate' });
  }
  let current = plan;
  const highlights: CanvasHighlight[] = [];
  for (const op of ops) {
    let step: OpResult;
    if (op.kind === 'draft') step = applyDraft(current);
    else if (!current) step = fail('invalid_operation', { reason: 'no_plan' });
    else if (op.kind === 'prioritize') step = applyPriority(current, op.target);
    else if (op.kind === 'training_days') step = applyFiveDays(current);
    else if (op.kind === 'split_day') step = applySplitWednesday(current);
    else if (op.kind === 'swap_variant') step = applySwap(current, op.toVariantId);
    else if (op.kind === 'declare_equipment') step = applyDeclare(current, op.item);
    else if (op.kind === 'move') step = applyMove(current, op);
    else if (op.kind === 'set_sets') step = applySetCount(current, op);
    else step = fail('invalid_operation', { reason: 'unknown_operation' });
    if (!step.ok) return step;
    current = step.plan;
    highlights.push(...step.highlights);
  }
  if (!current) return fail('invalid_operation', { reason: 'no_plan' });
  return { ok: true, plan: current, highlights };
}

function normalizeUtterance(text: string): string {
  return text.trim().replace(/\s+/g, ' ').toLocaleLowerCase('en-US');
}

type UtteranceSlot = { ops: CanvasOp[] | null };

/** A partial category mention is a slot with no ops, so mixed commands fail closed. */
export function parseCanvasUtterance(
  text: string,
): { kind: 'ops'; ops: CanvasOp[] } | { kind: 'unsupported_command' } {
  const normalized = normalizeUtterance(text);
  if (!normalized) return { kind: 'unsupported_command' };
  const slots: UtteranceSlot[] = [];
  if (/\bundo\b/.test(normalized)) {
    slots.push({ ops: normalized === 'undo' ? [{ id: 'undo', kind: 'undo' }] : null });
  }
  if (/\bredo\b/.test(normalized)) {
    slots.push({ ops: normalized === 'redo' ? [{ id: 'redo', kind: 'redo' }] : null });
  }
  if (
    (/\b(build|draft|make|start)\b/.test(normalized) && /\b(plan|mesocycle)\b/.test(normalized)) ||
    /\bhypertrophy plan\b/.test(normalized)
  ) {
    slots.push({ ops: [{ id: 'draft', kind: 'draft' }] });
  }
  if (/\bprioriti[sz]e\b/.test(normalized) || /\bupper chest\b/.test(normalized)) {
    const complete =
      /\bprioriti[sz]e\b/.test(normalized) &&
      /\bupper chest\b/.test(normalized) &&
      /\btriceps\b/.test(normalized);
    slots.push({
      ops: complete
        ? [
            { id: 'priority-upper-chest', kind: 'prioritize', target: 'upper_chest' },
            { id: 'priority-triceps', kind: 'prioritize', target: 'triceps' },
          ]
        : null,
    });
  }
  if (/\btraining days\b/.test(normalized)) {
    slots.push({
      ops: /\b(5|five) training days\b/.test(normalized)
        ? [{ id: 'training-days-5', kind: 'training_days', count: 5 }]
        : null,
    });
  }
  const splitMentioned =
    /\bsplit\b/.test(normalized) ||
    (/\bwednesday\b/.test(normalized) && (/\bam\b/.test(normalized) || /\bpm\b/.test(normalized)));
  if (splitMentioned) {
    const complete =
      /\bsplit\b/.test(normalized) &&
      /\bwednesday\b/.test(normalized) &&
      (/\bam\s*\/\s*pm\b/.test(normalized) ||
        /\bam and pm\b/.test(normalized) ||
        /\bstacked\b/.test(normalized));
    slots.push({ ops: complete ? [{ id: 'split-wed', kind: 'split_day', day: 'wed' }] : null });
  }
  if (/\bswap\b/.test(normalized)) {
    const complete = /\bincline dumbbell press\b/.test(normalized) && /\bsmith\b/.test(normalized);
    slots.push({
      ops: complete
        ? [
            {
              id: 'swap-incline-smith',
              kind: 'swap_variant',
              toVariantId: SMITH_INCLINE_VARIANT_ID,
            },
          ]
        : null,
    });
  }
  if (/\bi have\b/.test(normalized)) {
    slots.push({
      ops: /\bsmith\b/.test(normalized)
        ? [{ id: 'declare-smith-machine', kind: 'declare_equipment', item: 'smith_machine' }]
        : null,
    });
  }
  const only = slots.length === 1 ? slots[0] : undefined;
  if (!only?.ops) return { kind: 'unsupported_command' };
  return { kind: 'ops', ops: only.ops };
}

export function narrate(highlights: CanvasHighlight[], plan: CanvasPlan | null): string {
  if (highlights.length === 0) return 'No exercises changed.';
  const names = new Map(
    allExercises(plan ?? coachDraftPlan()).map((exercise) => [exercise.instanceId, exercise.name]),
  );
  const sentences = highlights.map((highlight) => {
    const name = names.get(highlight.instanceId) ?? 'Exercise';
    return `${highlight.change === 'kept' ? 'Kept' : highlight.change[0].toUpperCase() + highlight.change.slice(1)} ${name}. ${highlight.reason}.`;
  });
  return [...new Set(sentences)].join(' ');
}

function toPrescription(exercise: CanvasExercise): Session['exercises'][number] {
  return {
    id: exercise.instanceId,
    name: exercise.name,
    primaryMuscle: exercise.primaryMuscle,
    muscleContribution: exercise.muscleContribution,
    sets: exercise.sets,
    repRange: exercise.repRange,
    targetReps: exercise.targetReps,
    targetRir: exercise.targetRir,
    targetLoadKg: null,
    loadInstruction: null,
    progression: 'hold',
    evidenceIds: exercise.evidenceIds,
  };
}

/** Sessions in week order. Workout execution reads this, not a second plan. */
export function executionQueue(plan: CanvasPlan): Session[] {
  return plan.days
    .flatMap((day) => day.sessions)
    .filter((session) => session.exercises.length > 0)
    .map((session, slot) => ({
      id: session.id,
      week: plan.currentWeek,
      slot,
      pattern: slot % 2 === 0 ? 'A' : 'B',
      title: session.title,
      exercises: session.exercises.map(toPrescription),
      safetyStop: false,
      explanation: null,
      evidenceIds: ['k:81c218db'],
    }));
}

export function canvasReadback(journal: CanvasJournal) {
  const plan = persistedPlan(journal);
  const pending = [...journal.proposals]
    .reverse()
    .find((proposal) => proposal.status === 'proposed');
  return {
    generation: journal.generation,
    revisionId: currentRevisionId(journal),
    plan,
    execution: plan ? executionQueue(plan) : [],
    undoAvailable: journal.head > 0,
    redoAvailable: journal.head >= 0 && journal.head < journal.applied.length - 1,
    pendingProposalId: pending?.id ?? null,
  };
}

function fingerprint(plan: CanvasPlan | null): string | null {
  return plan ? canvasRequestHash(plan) : null;
}

function lowerBodyIds(plan: CanvasPlan): string[] {
  return allExercises(plan)
    .filter(isLower)
    .map((exercise) => exercise.instanceId)
    .sort();
}

export function lowerBodyPreserved(before: CanvasPlan, after: CanvasPlan): boolean {
  const previous = new Map(
    allExercises(before)
      .filter(isLower)
      .map((exercise) => [exercise.instanceId, exercise.sets]),
  );
  const next = new Map(
    allExercises(after)
      .filter(isLower)
      .map((exercise) => [exercise.instanceId, exercise.sets]),
  );
  if (previous.size === 0) return false;
  for (const [id, sets] of previous) {
    if (next.get(id) === undefined || (next.get(id) ?? 0) < sets) return false;
  }
  return lowerBodyIds(before).every((id) => lowerBodyIds(after).includes(id));
}

type Reduced = { journal: CanvasJournal; result: CanvasResult; persist: boolean };

function proposedResult(proposal: CanvasProposal, replay: boolean): CanvasSuccess {
  return {
    kind: 'proposed',
    proposal,
    narration: narrate(proposal.highlights, proposal.preview),
    replay,
  };
}

function cloneJournal(journal: CanvasJournal): CanvasJournal {
  return clone(journal);
}

function reducePropose(journal: CanvasJournal, command: CanvasProposeCommand): Reduced {
  const requestHash = canvasRequestHash(command);
  const existing = journal.proposals.find((proposal) => proposal.requestId === command.requestId);
  if (existing) {
    return existing.requestHash === requestHash
      ? { journal, result: proposedResult(existing, true), persist: false }
      : { journal, result: { kind: 'request_conflict' }, persist: false };
  }
  if (
    command.expectedGeneration !== journal.generation ||
    command.baseRevisionId !== currentRevisionId(journal)
  ) {
    return { journal, result: { kind: 'stale_context' }, persist: false };
  }
  let ops: CanvasOp[];
  if (command.source === 'direct') {
    if (!command.ops || command.text) {
      return { journal, result: { kind: 'unsupported_command' }, persist: false };
    }
    ops = command.ops;
  } else {
    if (!command.text) return { journal, result: { kind: 'unsupported_command' }, persist: false };
    const parsed = parseCanvasUtterance(command.text);
    if (parsed.kind !== 'ops')
      return { journal, result: { kind: 'unsupported_command' }, persist: false };
    ops = parsed.ops;
  }
  const basePlan = persistedPlan(journal);
  let preview: CanvasPlan;
  let highlights: CanvasHighlight[];
  if (ops.length === 1 && ops[0]?.kind === 'undo') {
    if (journal.head <= 0) return { journal, result: { kind: 'nothing_to_undo' }, persist: false };
    preview = clone(journal.applied[journal.head - 1].plan);
    highlights = [{ instanceId: '*', change: 'updated', reason: 'Undo the last accepted edit' }];
  } else if (ops.length === 1 && ops[0]?.kind === 'redo') {
    if (journal.head < 0 || journal.head >= journal.applied.length - 1) {
      return { journal, result: { kind: 'nothing_to_redo' }, persist: false };
    }
    preview = clone(journal.applied[journal.head + 1].plan);
    highlights = [{ instanceId: '*', change: 'updated', reason: 'Redo the undone edit' }];
  } else {
    const applied = applyCanvasOps(basePlan ? clone(basePlan) : null, ops);
    if (!applied.ok) return { journal, result: applied.result, persist: false };
    preview = applied.plan;
    highlights = applied.highlights;
    if (
      basePlan &&
      ops.some((op) => GUARDED_KINDS.has(op.kind)) &&
      !lowerBodyPreserved(basePlan, preview)
    ) {
      return {
        journal,
        result: { kind: 'invalid_operation', reason: 'dropped_lower_body' },
        persist: false,
      };
    }
  }
  const proposal: CanvasProposal = {
    id: `proposal:${command.requestId}`,
    requestId: command.requestId,
    requestHash,
    generation: journal.generation,
    baseRevisionId: currentRevisionId(journal),
    source: command.source,
    utterance: command.text ?? null,
    ops,
    basePlan: basePlan ? clone(basePlan) : null,
    preview,
    highlights,
    status: 'proposed',
    decision: null,
  };
  const next = cloneJournal(journal);
  next.proposals.push(proposal);
  return { journal: next, result: proposedResult(proposal, false), persist: true };
}

function applySetEdits(
  plan: CanvasPlan,
  edits: Array<{ instanceId: string; sets: number }>,
): OpResult {
  let current = plan;
  const highlights: CanvasHighlight[] = [];
  for (const edit of edits) {
    const step = applySetCount(current, {
      id: `edit:${edit.instanceId}`,
      kind: 'set_sets',
      ...edit,
    });
    if (!step.ok) return step;
    current = step.plan;
    highlights.push(...step.highlights);
  }
  return { ok: true, plan: current, highlights };
}

function reduceDecide(journal: CanvasJournal, command: CanvasDecideCommand, now: string): Reduced {
  const proposal = journal.proposals.find((item) => item.id === command.proposalId);
  if (!proposal) return { journal, result: { kind: 'proposal_not_found' }, persist: false };
  const requestHash = canvasRequestHash(command);
  if (proposal.decision) {
    if (
      proposal.decision.requestId === command.requestId &&
      proposal.decision.requestHash === requestHash
    ) {
      return {
        journal,
        result: {
          kind: 'decided',
          receipt: proposal.decision.receipt,
          plan: persistedPlan(journal),
          narration: narrate(proposal.highlights, persistedPlan(journal)),
          replay: true,
        },
        persist: false,
      };
    }
    return {
      journal,
      result:
        proposal.decision.requestId === command.requestId
          ? { kind: 'request_conflict' }
          : { kind: 'already_decided' },
      persist: false,
    };
  }
  if (
    command.expectedGeneration !== journal.generation ||
    proposal.generation !== journal.generation ||
    proposal.baseRevisionId !== currentRevisionId(journal)
  ) {
    return { journal, result: { kind: 'stale_context' }, persist: false };
  }
  const next = cloneJournal(journal);
  const stored = next.proposals.find((item) => item.id === proposal.id);
  if (!stored) return { journal, result: { kind: 'proposal_not_found' }, persist: false };
  if (command.decision === 'reject') {
    const receipt: CanvasReceipt = {
      version: 1,
      proposalId: stored.id,
      requestId: command.requestId,
      decision: 'reject',
      status: 'rejected',
      revisionId: null,
      priorRevisionId: currentRevisionId(journal),
      planFingerprint: fingerprint(persistedPlan(journal)),
      decidedAt: now,
    };
    stored.status = 'rejected';
    stored.decision = { requestId: command.requestId, requestHash, receipt };
    return {
      journal: next,
      result: {
        kind: 'decided',
        receipt,
        plan: persistedPlan(next),
        narration: 'Rejected the preview. The saved plan is unchanged.',
        replay: false,
      },
      persist: true,
    };
  }
  const selected =
    command.acceptedOpIds === undefined
      ? stored.ops
      : stored.ops.filter((op) => command.acceptedOpIds?.includes(op.id));
  if (command.acceptedOpIds && selected.length !== command.acceptedOpIds.length) {
    return {
      journal,
      result: { kind: 'invalid_operation', reason: 'unknown_operation' },
      persist: false,
    };
  }
  if (selected.length === 0)
    return { journal, result: { kind: 'invalid_operation', reason: 'empty_edit' }, persist: false };
  const undo = selected.length === 1 && selected[0]?.kind === 'undo';
  const redo = selected.length === 1 && selected[0]?.kind === 'redo';
  if ((undo || redo) && (command.setEdits?.length || selected.length !== stored.ops.length)) {
    return {
      journal,
      result: { kind: 'invalid_operation', reason: 'undo_is_separate' },
      persist: false,
    };
  }
  let appliedPlan: CanvasPlan;
  let highlights = stored.highlights;
  if (undo) {
    if (next.head <= 0) return { journal, result: { kind: 'nothing_to_undo' }, persist: false };
    next.head -= 1;
    appliedPlan = next.applied[next.head].plan;
  } else if (redo) {
    if (next.head < 0 || next.head >= next.applied.length - 1) {
      return { journal, result: { kind: 'nothing_to_redo' }, persist: false };
    }
    next.head += 1;
    appliedPlan = next.applied[next.head].plan;
  } else {
    const recomputed = applyCanvasOps(stored.basePlan ? clone(stored.basePlan) : null, selected);
    if (!recomputed.ok) return { journal, result: recomputed.result, persist: false };
    let plan = recomputed.plan;
    highlights = recomputed.highlights;
    if (command.setEdits?.length) {
      const edited = applySetEdits(plan, command.setEdits);
      if (!edited.ok) return { journal, result: edited.result, persist: false };
      plan = edited.plan;
      highlights = [...highlights, ...edited.highlights];
    }
    if (
      stored.basePlan &&
      selected.some((op) => GUARDED_KINDS.has(op.kind)) &&
      !lowerBodyPreserved(stored.basePlan, plan)
    ) {
      return {
        journal,
        result: { kind: 'invalid_operation', reason: 'dropped_lower_body' },
        persist: false,
      };
    }
    const revision: CanvasRevision = {
      id: `revision:${command.requestId}`,
      proposalId: stored.id,
      plan,
    };
    next.applied = next.applied.slice(0, next.head + 1);
    next.applied.push(revision);
    next.head = next.applied.length - 1;
    appliedPlan = plan;
  }
  next.generation += 1;
  const receipt: CanvasReceipt = {
    version: 1,
    proposalId: stored.id,
    requestId: command.requestId,
    decision: 'apply',
    status: 'applied',
    revisionId: currentRevisionId(next),
    priorRevisionId: stored.baseRevisionId,
    planFingerprint: fingerprint(appliedPlan),
    decidedAt: now,
  };
  stored.status = 'applied';
  stored.highlights = highlights;
  stored.preview = appliedPlan;
  stored.decision = { requestId: command.requestId, requestHash, receipt };
  return {
    journal: next,
    result: {
      kind: 'decided',
      receipt,
      plan: appliedPlan,
      narration: narrate(highlights, appliedPlan),
      replay: false,
    },
    persist: true,
  };
}

/** Pure revision step. Chat, voice, and drag all enter here; nothing else writes a plan. */
export function reduceCanvas(journal: CanvasJournal, command: CanvasCommand, now: string): Reduced {
  if (!Number.isFinite(Date.parse(now))) {
    return { journal, result: { kind: 'invalid_operation', reason: 'bad_clock' }, persist: false };
  }
  return command.type === 'propose'
    ? reducePropose(journal, command)
    : reduceDecide(journal, command, now);
}

export async function reviseCanvas(
  port: CanvasPort,
  subject: string,
  command: CanvasCommand,
  now: string,
): Promise<CanvasResult> {
  const current = await port.read(subject);
  if (!current) return { kind: 'owner_missing' };
  const reduced = reduceCanvas(current, command, now);
  if (!reduced.persist) return reduced.result;
  const wrote = await port.write(subject, current.generation, reduced.journal);
  if (wrote === 'ok') return reduced.result;
  if (wrote === 'owner_missing') return { kind: 'owner_missing' };
  const again = await port.read(subject);
  if (!again) return { kind: 'owner_missing' };
  const replay = reduceCanvas(again, command, now);
  if (replay.result.kind === 'proposed' || replay.result.kind === 'decided') {
    if (replay.result.replay) return replay.result;
  }
  return { kind: 'stale_context' };
}

export function createMemoryCanvasPort(
  owners: ReadonlySet<string> | null = new Set(['owner']),
): CanvasPort & {
  exportJournal(subject: string): CanvasJournal | null;
  importJournal(subject: string, journal: CanvasJournal): void;
} {
  const journals = new Map<string, CanvasJournal>();
  const admitted = (subject: string) => owners === null || owners.has(subject);
  return {
    async read(subject) {
      if (!admitted(subject)) return null;
      return clone(journals.get(subject) ?? emptyJournal());
    },
    async write(subject, expectedGeneration, journal) {
      if (!admitted(subject)) return 'owner_missing';
      const current = journals.get(subject) ?? emptyJournal();
      if (current.generation !== expectedGeneration) return 'conflict';
      journals.set(subject, clone(journal));
      return 'ok';
    },
    exportJournal(subject) {
      const journal = journals.get(subject);
      return journal ? clone(journal) : null;
    },
    importJournal(subject, journal) {
      journals.set(subject, clone(journal));
    },
  };
}

export function parseJournal(value: unknown): CanvasJournal | null {
  if (!value || typeof value !== 'object') return null;
  const journal = value as Partial<CanvasJournal>;
  if (
    journal.version !== 1 ||
    typeof journal.generation !== 'number' ||
    !Array.isArray(journal.applied) ||
    !Array.isArray(journal.proposals)
  ) {
    return null;
  }
  if (
    typeof journal.head !== 'number' ||
    journal.head < -1 ||
    journal.head >= journal.applied.length
  )
    return null;
  const plan = persistedPlan(journal as CanvasJournal);
  if (journal.head >= 0 && (!plan || plan.policyVersion !== 'mesocycle-canvas-v1')) return null;
  return journal as CanvasJournal;
}
