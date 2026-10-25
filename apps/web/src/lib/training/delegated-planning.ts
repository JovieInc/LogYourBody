import {
  EXERCISE_CATALOG,
  catalogVariantById,
  isEligibleVariant,
  resolveAvailableEquipment,
} from './catalog';
import {
  buildOperation,
  CANVAS_DAYS,
  canvasPlanSchema,
  interpretPlanUtterance,
} from './mesocycle-canvas';
import {
  delegatedProgramSchema,
  planningInputsSchema,
  type DelegatedProgram,
  type PlanningInputs,
  type SteeringIntent,
} from './delegation-contract';

export class PlanningQuestion extends Error {
  constructor(
    readonly field: string,
    readonly question: string,
  ) {
    super(question);
  }
}
const QUESTIONS: Record<keyof PlanningInputs, string> = {
  goal: 'What outcome would you like your training to support?',
  goalDate: 'Is there a date you are working toward?',
  experience: 'Are you new to training, returning, or training regularly?',
  sessionsPerWeek: 'How many days can you realistically train each week?',
  minutesPerSession: 'How many minutes can you realistically spend per session?',
  equipment: 'Will you train with dumbbells or at a full gym?',
  excludedVariantIds: 'Are there movements you want to exclude? You can say none.',
  limitations: 'Do you have known movement limitations? You can say none.',
  preferredVariantIds: 'Are there movements you want to keep? You can say none.',
};
export function resolvePlanningInputs(
  canonical: unknown,
  supplied: Partial<PlanningInputs>,
): PlanningInputs {
  const known = planningInputsSchema.partial().safeParse(canonical);
  const merged = { ...(known.success ? known.data : {}), ...supplied };
  // Date and positive preferences are optional; absence is never interpreted as no limitations.
  merged.preferredVariantIds ??= [];
  for (const field of [
    'goal',
    'experience',
    'sessionsPerWeek',
    'minutesPerSession',
    'equipment',
    'excludedVariantIds',
    'limitations',
  ] as const) {
    if (merged[field] === undefined) throw new PlanningQuestion(field, QUESTIONS[field]);
  }
  return planningInputsSchema.parse(merged);
}
export function eligibleForProgram(variantId: string, inputs: PlanningInputs): boolean {
  const variant = catalogVariantById(variantId);
  return Boolean(
    variant &&
    !inputs.excludedVariantIds.includes(variantId) &&
    isEligibleVariant(variant, {
      available: resolveAvailableEquipment({ profile: inputs.equipment }),
      excludedConcerns: inputs.limitations,
    }),
  );
}
function checkInputs(inputs: PlanningInputs) {
  const concerns = new Set(EXERCISE_CATALOG.flatMap((v) => v.exclusions));
  if (inputs.limitations.some((v) => !concerns.has(v)))
    throw new PlanningQuestion(
      'limitations',
      'This limitation needs qualified review before LYB can prescribe a plan. Which reviewed movement restriction applies?',
    );
  if (inputs.excludedVariantIds.some((id) => !catalogVariantById(id)))
    throw new PlanningQuestion(
      'excludedVariantIds',
      'Which exact catalog movement should LYB exclude?',
    );
  for (const id of inputs.preferredVariantIds) {
    if (!eligibleForProgram(id, inputs))
      throw new PlanningQuestion(
        'preferredVariantIds',
        'That movement conflicts with your equipment or a reviewed exclusion. Choose an eligible variant or review the constraint.',
      );
  }
}

/** Reuses LYB-119's reviewed draft and prescriptions. Redistributes its work to
 * the user's schedule; a time cap can reduce sets but never invent more work. */
export function recommendProgram(
  inputs: PlanningInputs,
  weekCount: 4 | 5 | 6,
  blockNumber = 1,
  authority: DelegatedProgram['authority'] = { trainerSubject: null, coachDelegated: false },
): DelegatedProgram {
  checkInputs(inputs);
  const draft = buildOperation(null, {
    kind: 'draft',
    goal: inputs.goal,
    equipment: inputs.equipment,
    weekCount,
  });
  if (!draft.ok)
    throw new PlanningQuestion(
      'goal',
      'LYB cannot safely draft this goal with the current reviewed policy. What training outcome should it support?',
    );
  const plan = draft.preview;
  let rows = plan.sessions.flatMap((s) => s.exercises);
  for (const row of rows) {
    if (eligibleForProgram(row.variantId, inputs)) continue;
    const replacement = EXERCISE_CATALOG.find(
      (v) =>
        v.substitutionEligible !== false &&
        v.primaryMuscle === row.primaryMuscle &&
        eligibleForProgram(v.id, inputs),
    );
    if (!replacement)
      throw new PlanningQuestion(
        'limitations',
        `No eligible ${row.primaryMuscle} movement remains. Which equipment or movement constraint can be reviewed?`,
      );
    Object.assign(row, { variantId: replacement.id, name: replacement.name });
  }
  // Eligibility can converge two slots onto the same variant. Combine their
  // existing work before distributing it so workout set identities stay unique.
  const unique = new Map<string, (typeof rows)[number]>();
  for (const row of rows) {
    const existing = unique.get(row.variantId);
    if (existing) existing.sets += row.sets;
    else unique.set(row.variantId, { ...row });
  }
  rows = [...unique.values()];
  for (const id of inputs.preferredVariantIds) {
    if (rows.some((r) => r.variantId === id)) continue;
    const variant = catalogVariantById(id)!;
    const row = rows.find(
      (r) =>
        r.primaryMuscle === variant.primaryMuscle &&
        !inputs.preferredVariantIds.includes(r.variantId),
    );
    if (!row)
      throw new PlanningQuestion(
        'preferredVariantIds',
        'The requested movements cannot all fit this reviewed draft. Which exact movement should be kept?',
      );
    Object.assign(row, { variantId: id, name: variant.name });
  }
  const days =
    inputs.sessionsPerWeek === 2
      ? (['monday', 'thursday'] as const)
      : inputs.sessionsPerWeek === 3
        ? (['monday', 'wednesday', 'friday'] as const)
        : CANVAS_DAYS.filter((d) => d !== 'sunday').slice(0, inputs.sessionsPerWeek);
  plan.sessions = days.map((day) => ({
    id: `session:${day}:single`,
    day,
    slot: 'single',
    title: day.charAt(0).toUpperCase() + day.slice(1),
    exercises: [],
  }));
  rows.forEach((row, index) => {
    // Preserve exact variant IDs; history is keyed by variant, never the label.
    const target = plan.sessions[index % plan.sessions.length]!;
    target.exercises.push({ ...row, instanceId: `${row.variantId}:${target.day}:single:${index}` });
  });
  for (const session of plan.sessions) {
    // Same conservative execution budget as workout mode's shortening policy.
    const budget = Math.floor(inputs.minutesPerSession / 3);
    while (session.exercises.reduce((sum, e) => sum + e.sets, 0) > budget) {
      const reducible = [...session.exercises].reverse().find((e) => e.sets > 1);
      if (!reducible)
        throw new PlanningQuestion(
          'minutesPerSession',
          'The eligible movements do not fit this time budget. Can you allow more time per session or another training day?',
        );
      reducible.sets -= 1;
    }
  }
  return delegatedProgramSchema.parse({
    inputs,
    plan,
    blockNumber,
    deloadWeek: weekCount,
    temporaryPriority: null,
    authority,
  });
}

export function validateProgram(program: DelegatedProgram): string | null {
  const parsed = delegatedProgramSchema.safeParse(program);
  if (!parsed.success) return 'invalid_plan';
  try {
    checkInputs(program.inputs);
  } catch {
    return 'reviewed_eligibility';
  }
  const { plan, inputs } = program;
  if (
    plan.sessions.length !== inputs.sessionsPerWeek ||
    plan.equipment !== inputs.equipment ||
    plan.weekCount !== program.deloadWeek
  )
    return 'schedule_or_lifecycle';
  if (
    program.temporaryPriority &&
    program.temporaryPriority.expiresAfterBlock !== program.blockNumber
  )
    return 'expired_priority';
  if (
    plan.sessions.some(
      (s) => new Set(s.exercises.map((e) => e.variantId)).size !== s.exercises.length,
    )
  )
    return 'duplicate_variant';
  if (
    plan.sessions.some(
      (s) => s.exercises.reduce((n, e) => n + e.sets, 0) * 3 > inputs.minutesPerSession,
    )
  )
    return 'time_budget';
  const rows = plan.sessions.flatMap((s) => s.exercises);
  if (
    rows.some(
      (r) =>
        !eligibleForProgram(r.variantId, inputs) ||
        catalogVariantById(r.variantId)?.name !== r.name ||
        catalogVariantById(r.variantId)?.primaryMuscle !== r.primaryMuscle,
    )
  )
    return 'reviewed_eligibility';
  if (inputs.preferredVariantIds.some((id) => !rows.some((r) => r.variantId === id)))
    return 'kept_variant_missing';
  return null;
}

export function steerProgram(prior: DelegatedProgram, intent: SteeringIntent): DelegatedProgram {
  const next = delegatedProgramSchema.parse(JSON.parse(JSON.stringify(prior)));
  if (intent.kind === 'keep' || intent.kind === 'exclude') {
    const key = intent.kind === 'keep' ? 'preferredVariantIds' : 'excludedVariantIds';
    next.inputs[key] = [...new Set([...next.inputs[key], intent.variantId])];
  } else if (intent.kind === 'schedule') next.inputs.sessionsPerWeek = intent.count;
  else if (intent.kind === 'authorize_trainer')
    next.authority.trainerSubject = intent.trainerSubject;
  else if (intent.kind === 'delegate_coach') next.authority.coachDelegated = intent.enabled;
  if (['keep', 'exclude', 'schedule', 'next_block'].includes(intent.kind)) {
    const rebuilt = recommendProgram(
      next.inputs,
      next.plan.weekCount,
      next.blockNumber + (intent.kind === 'next_block' ? 1 : 0),
      next.authority,
    );
    // Priorities are block-scoped. They only survive steering inside this block.
    if (intent.kind !== 'next_block') rebuilt.temporaryPriority = next.temporaryPriority;
    Object.assign(next, rebuilt);
    if (intent.kind !== 'next_block') next.completedWeeks = { ...prior.completedWeeks };
  }
  if (intent.kind === 'prioritize')
    next.temporaryPriority = {
      muscles: intent.muscles,
      upperChest: intent.upperChest,
      expiresAfterBlock: next.blockNumber,
    };
  if (
    next.temporaryPriority &&
    ['keep', 'exclude', 'schedule', 'prioritize'].includes(intent.kind)
  ) {
    // Rebuild first so repeating/renewing a priority cannot accumulate set additions.
    const baseline = recommendProgram(
      next.inputs,
      next.plan.weekCount,
      next.blockNumber,
      next.authority,
    );
    const built = buildOperation(baseline.plan, {
      kind: 'prioritize',
      muscles: next.temporaryPriority.muscles,
      upperChest: next.temporaryPriority.upperChest,
    });
    if (!built.ok)
      throw new PlanningQuestion(
        'priority',
        'This priority needs review before it can fit the plan.',
      );
    next.plan = canvasPlanSchema.parse(built.preview);
  }
  const invalid = validateProgram(next);
  if (invalid)
    throw new PlanningQuestion(
      invalid,
      'This change exceeds the reviewed plan or time budget. Review the constraint before applying it.',
    );
  return next;
}

export function interpretSteering(utterance: string): SteeringIntent | null {
  const text = utterance
    .trim()
    .toLowerCase()
    .replace(/[.!?]+$/, '');
  if (/^(prepare|review|start) (?:the )?next block$/.test(text)) return { kind: 'next_block' };
  const match = text.match(/^(keep|i hate|exclude) (.+)$/);
  if (match) {
    const name = match[2]!.replace(/s$/, '');
    const variant = EXERCISE_CATALOG.find((v) => v.name.toLowerCase().replace(/s$/, '') === name);
    if (!variant) return null;
    return match[1] === 'keep'
      ? { kind: 'keep', variantId: variant.id, scope: 'durable' }
      : { kind: 'exclude', variantId: variant.id, scope: 'durable' };
  }
  const schedule = text.match(/^(?:i (?:only )?train|train) (two|three|four|five|six|[2-6]) days$/);
  if (schedule) {
    const count = ({ two: 2, three: 3, four: 4, five: 5, six: 6 }[schedule[1]!] ??
      Number(schedule[1])) as PlanningInputs['sessionsPerWeek'];
    return { kind: 'schedule', count, scope: 'durable' };
  }
  const existing = interpretPlanUtterance(text);
  return existing?.kind === 'prioritize'
    ? {
        kind: 'prioritize',
        muscles: existing.muscles,
        upperChest: existing.upperChest,
        scope: 'this_block',
      }
    : null;
}

export function priorityLabels(
  priority: Pick<NonNullable<DelegatedProgram['temporaryPriority']>, 'muscles' | 'upperChest'>,
): string[] {
  return [
    ...(priority.upperChest ? ['upper chest'] : []),
    ...priority.muscles.filter((m) => !(priority.upperChest && m === 'chest')),
  ];
}
