import { catalogVariantById, isEligibleVariant, profileEquipment } from './catalog';
import { createMesoBlock, buildMicrocycle, progressionForExercise } from './engine';
import { stableTrainingUuid } from './service';
import type {
  Microcycle,
  Session,
  SetLog,
  TrainingProgramSetup,
} from './types';

/** The setup fields layout math actually needs; revision payloads persist
 * exactly this subset beside each canonical revision. */
export type PlanSetup = Pick<
  TrainingProgramSetup,
  'id' | 'sessionsPerWeek' | 'equipment' | 'startedAt'
>;
import {
  planLayoutSchema,
  type PlanEditOperation,
  type PlanLayout,
} from './revision-contract';

const PATTERNS = ['A', 'B'] as const;
type Pattern = (typeof PATTERNS)[number];

export type AppliedPlanEdit = {
  op: PlanEditOperation;
  change: string;
};
export type PlanEditResult =
  | { kind: 'applied'; layout: PlanLayout; diffs: AppliedPlanEdit[] }
  | { kind: 'edit_not_applicable' };

function exerciseName(exerciseId: string): string {
  return catalogVariantById(exerciseId)?.name ?? exerciseId;
}

/** Derives the canonical layout from a microcycle template. Sessions sharing a
 * pattern are identical by construction, so the first session of each pattern
 * defines that pattern's ordered list. */
export function layoutForPlan(plan: Microcycle): PlanLayout | null {
  const layout: Record<Pattern, { exerciseId: string; sets: number }[]> = { A: [], B: [] };
  const seen = new Set<Pattern>();
  for (const session of plan.sessions) {
    if (seen.has(session.pattern)) continue;
    seen.add(session.pattern);
    layout[session.pattern] = session.exercises.map((exercise) => ({
      exerciseId: exercise.id,
      sets: exercise.sets,
    }));
  }
  if (layout.A.length === 0 || layout.B.length === 0) return null;
  return layout;
}

function findIndex(entries: { exerciseId: string }[], exerciseId: string): number {
  return entries.findIndex((entry) => entry.exerciseId === exerciseId);
}

/** Applies typed canvas/chat operations to a layout. Every op is validated
 * against the reviewed catalog and the enrolled equipment profile; the whole
 * batch fails closed so a plan can never be left partially edited. */
export function applyPlanEditOps(input: {
  base: PlanLayout;
  operations: PlanEditOperation[];
  setup: PlanSetup;
}): PlanEditResult {
  const next: PlanLayout = {
    A: input.base.A.map((entry) => ({ ...entry })),
    B: input.base.B.map((entry) => ({ ...entry })),
  };
  const available = profileEquipment(input.setup.equipment);
  const diffs: AppliedPlanEdit[] = [];
  for (const op of input.operations) {
    switch (op.kind) {
      case 'move_exercise': {
        const source = next[op.fromPattern];
        const index = findIndex(source, op.exerciseId);
        if (index < 0) return { kind: 'edit_not_applicable' };
        const [entry] = source.splice(index, 1);
        const target = next[op.toPattern];
        if (op.toIndex > target.length) return { kind: 'edit_not_applicable' };
        if (
          op.fromPattern !== op.toPattern &&
          findIndex(target, entry.exerciseId) >= 0
        )
          return { kind: 'edit_not_applicable' };
        target.splice(op.toIndex, 0, entry);
        diffs.push({
          op,
          change:
            op.fromPattern === op.toPattern
              ? `Moved ${exerciseName(entry.exerciseId)} to position ${op.toIndex + 1} in day ${op.toPattern}`
              : `Moved ${exerciseName(entry.exerciseId)} from day ${op.fromPattern} to day ${op.toPattern}`,
        });
        break;
      }
      case 'reorder_exercise': {
        const entries = next[op.pattern];
        const index = findIndex(entries, op.exerciseId);
        if (index < 0 || op.toIndex >= entries.length) return { kind: 'edit_not_applicable' };
        const [entry] = entries.splice(index, 1);
        entries.splice(op.toIndex, 0, entry);
        diffs.push({
          op,
          change: `Moved ${exerciseName(entry.exerciseId)} to position ${op.toIndex + 1} in day ${op.pattern}`,
        });
        break;
      }
      case 'update_sets': {
        const entry = next[op.pattern][findIndex(next[op.pattern], op.exerciseId)];
        if (!entry) return { kind: 'edit_not_applicable' };
        const before = entry.sets;
        entry.sets = op.sets;
        diffs.push({
          op,
          change: `Sets for ${exerciseName(entry.exerciseId)}: ${before} -> ${op.sets}`,
        });
        break;
      }
      case 'swap_variant': {
        const entry = next[op.pattern][findIndex(next[op.pattern], op.exerciseId)];
        const variant = catalogVariantById(op.toVariantId);
        const current = entry ? catalogVariantById(entry.exerciseId) : undefined;
        if (!entry || !current || !variant) return { kind: 'edit_not_applicable' };
        if (variant.primaryMuscle !== current.primaryMuscle)
          return { kind: 'edit_not_applicable' };
        if (variant.id === current.id) return { kind: 'edit_not_applicable' };
        if (!isEligibleVariant(variant, { available }))
          return { kind: 'edit_not_applicable' };
        entry.exerciseId = variant.id;
        diffs.push({
          op,
          change: `Swapped ${current.name} for ${variant.name} on day ${op.pattern}`,
        });
        break;
      }
      case 'remove_exercise': {
        const entries = next[op.pattern];
        const index = findIndex(entries, op.exerciseId);
        // A pattern must keep at least one movement; a plan never silently
        // drops a day.
        if (index < 0 || entries.length <= 1) return { kind: 'edit_not_applicable' };
        const [entry] = entries.splice(index, 1);
        diffs.push({
          op,
          change: `Removed ${exerciseName(entry.exerciseId)} from day ${op.pattern}`,
        });
        break;
      }
    }
  }
  const layout = planLayoutSchema.parse(next);
  return { kind: 'applied', layout, diffs };
}

/** Rebuilds one session's exercises from the canonical layout. Rep range, RIR,
 * progression and load guidance stay engine-owned and recompute from logged
 * history, exactly like the baseline builder and exercise swaps. Returns the
 * session unchanged when the layout cannot fully resolve. */
export function sessionWithLayout(
  session: Session,
  layout: PlanLayout,
  logs: SetLog[],
): Session {
  if (session.safetyStop) return session;
  const entries = layout[session.pattern];
  const targetRir = session.exercises[0]?.targetRir ?? 3;
  const exercises = [];
  for (const entry of entries) {
    const variant = catalogVariantById(entry.exerciseId);
    if (!variant) return session;
    const progression = progressionForExercise(variant.id, logs, targetRir);
    exercises.push({
      id: variant.id,
      name: variant.name,
      primaryMuscle: variant.primaryMuscle,
      muscleContribution: variant.muscleContribution,
      sets: entry.sets,
      repRange: session.exercises[0]?.repRange ?? { min: 8, max: 12 },
      targetReps: progression.targetReps,
      targetRir,
      targetLoadKg: progression.targetLoadKg,
      loadInstruction: progression.loadInstruction,
      progression: progression.action,
      evidenceIds: session.exercises[0]?.evidenceIds ?? [],
    });
  }
  if (exercises.length === 0) return session;
  return { ...session, exercises };
}

/** Deterministic week-1 template preview for a proposed layout, built exactly
 * like the reviewed baseline so create-time and decide-time recomputation
 * agree regardless of when the decision lands. */
export function planForLayout(
  subject: string,
  setup: PlanSetup,
  layout: PlanLayout,
): Microcycle {
  const block = createMesoBlock(setup.startedAt, setup.startedAt);
  const plan = buildMicrocycle({
    // buildMicrocycle only reads sessionsPerWeek/equipment/startedAt.
    setup: setup as TrainingProgramSetup,
    block,
    logs: [],
    feedback: [],
    sessionIds: Array.from({ length: setup.sessionsPerWeek }, (_, slot) =>
      stableTrainingUuid(subject, setup.id, block.id, '1', String(slot)),
    ),
  });
  const sessions = plan.sessions.map((session) => sessionWithLayout(session, layout, []));
  const plannedFractionalVolume = sessions.reduce(
    (volume, session) => {
      for (const exercise of session.exercises) {
        for (const [muscle, fraction] of Object.entries(exercise.muscleContribution)) {
          volume[muscle] = (volume[muscle] ?? 0) + exercise.sets * Number(fraction);
        }
      }
      return volume;
    },
    {} as Record<string, number>,
  );
  return { ...plan, sessions, plannedFractionalVolume };
}
