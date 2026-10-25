import { z } from 'zod';

/**
 * Version 1 approved native training cards.
 *
 * json-render is not a supported consumer in this repository. There is no
 * runtime that evaluates generated component trees. These objects are a closed
 * schema. The iOS app maps each component onto an owned SwiftUI view. This is
 * not a Swift package of json-render and not a runtime migration.
 */
export const NATIVE_TRAINING_CARD_SCHEMA_VERSION = 1 as const;

export const NATIVE_TRAINING_CARD_RUNTIME = {
  consumer: 'owned-swiftui',
  jsonRender: 'unsupported',
} as const;

export const NATIVE_TRAINING_CARD_COMPONENTS = [
  'MesoPlanCard',
  'PlanChangeCard',
  'WorkoutSessionCard',
  'ExerciseSwapCard',
  'TrainingFeedbackCard',
  'ProgressReviewCard',
] as const;

export type NativeTrainingCardComponent = (typeof NATIVE_TRAINING_CARD_COMPONENTS)[number];

export const NATIVE_TRAINING_CARD_ACTIONS = {
  MesoPlanCard: ['apply_revision', 'adjust_revision', 'reject_revision', 'expand_program'],
  PlanChangeCard: ['apply_revision', 'adjust_revision', 'reject_revision'],
  WorkoutSessionCard: ['log_set', 'correct_set', 'navigate_exercise', 'expand_session'],
  ExerciseSwapCard: ['swap_exercise'],
  TrainingFeedbackCard: ['record_feedback'],
  ProgressReviewCard: ['propose_change'],
} as const satisfies Record<NativeTrainingCardComponent, readonly string[]>;

const uuid = z.string().uuid();
const catalogId = z.string().regex(/^[a-z0-9_]{1,64}$/);
const evidenceId = z.string().regex(/^k:[0-9a-f]{8}$/);
const shortText = (max: number) => z.string().trim().min(1).max(max);
const revisionId = uuid.nullable();

const programObjectSchema = z
  .object({
    kind: z.literal('program_revision'),
    id: uuid,
    revisionId: uuid,
    proposalId: uuid.nullable(),
  })
  .strict();
const proposalObjectSchema = z
  .object({ kind: z.literal('proposal'), id: uuid, revisionId })
  .strict();
const sessionObjectSchema = z.object({ kind: z.literal('session'), id: uuid, revisionId }).strict();
const swapObjectSchema = z
  .object({ kind: z.literal('exercise_swap'), id: uuid, revisionId })
  .strict();
const feedbackObjectSchema = z
  .object({ kind: z.literal('feedback'), id: uuid, revisionId })
  .strict();
const reviewObjectSchema = z
  .object({ kind: z.literal('progress_review'), id: uuid, revisionId })
  .strict();

const diffSchema = z
  .object({
    label: shortText(80),
    from: z.string().max(120),
    to: z.string().max(120),
  })
  .strict();
const evidenceSchema = z.array(evidenceId).max(12);
const reasonsSchema = z.array(shortText(160)).max(8);

const exerciseSchema = z
  .object({
    id: catalogId,
    name: shortText(80),
    setup: shortText(200),
    sets: z.number().int().min(1).max(10),
    repRange: z
      .object({ min: z.number().int().min(1).max(50), max: z.number().int().min(1).max(50) })
      .strict()
      .refine((range) => range.min <= range.max),
    targetReps: z.number().int().min(1).max(50),
    targetRir: z.number().int().min(0).max(6),
    targetLoadKg: z.number().finite().nonnegative().max(500).nullable(),
    completedSets: z.number().int().min(0).max(10),
  })
  .strict();

const previousSetSchema = z
  .object({
    exerciseId: catalogId,
    setNumber: z.number().int().min(1).max(20),
    reps: z.number().int().min(1).max(50),
    loadKg: z.number().finite().nonnegative().max(500).nullable(),
    rir: z.number().int().min(0).max(6),
    revision: z.number().int().nonnegative().nullable(),
  })
  .strict();

const weekSchema = z
  .object({
    week: z.number().int().min(1).max(8),
    sessions: z
      .array(
        z
          .object({
            id: uuid,
            title: shortText(80),
            slot: z.number().int().min(0).max(6),
          })
          .strict(),
      )
      .min(1)
      .max(6),
  })
  .strict();

const alternativeSchema = z
  .object({
    id: catalogId,
    name: shortText(80),
    tradeoff: shortText(160),
  })
  .strict();

const reviewIntentSchema = z.enum(['keep', 'exclude', 'prioritize', 'schedule', 'next_block']);

export const nativeTrainingCardSchema = z.discriminatedUnion('component', [
  z
    .object({
      schemaVersion: z.literal(NATIVE_TRAINING_CARD_SCHEMA_VERSION),
      component: z.literal('MesoPlanCard'),
      object: programObjectSchema,
      properties: z
        .object({
          title: shortText(80),
          weekCount: z.number().int().min(1).max(8),
          compact: z.literal(true),
          weeks: z.array(weekSchema).min(1).max(8),
          diff: z.array(diffSchema).max(12),
          reasons: reasonsSchema,
          evidenceIds: evidenceSchema,
        })
        .strict()
        .refine((properties) => properties.weekCount === properties.weeks.length),
    })
    .strict(),
  z
    .object({
      schemaVersion: z.literal(NATIVE_TRAINING_CARD_SCHEMA_VERSION),
      component: z.literal('PlanChangeCard'),
      object: proposalObjectSchema,
      properties: z
        .object({
          reason: shortText(500),
          diff: z.array(diffSchema).max(12),
          reasons: reasonsSchema,
          evidenceIds: evidenceSchema,
          status: z.enum(['pending', 'applied', 'rejected']),
        })
        .strict(),
    })
    .strict(),
  z
    .object({
      schemaVersion: z.literal(NATIVE_TRAINING_CARD_SCHEMA_VERSION),
      component: z.literal('WorkoutSessionCard'),
      object: sessionObjectSchema,
      properties: z
        .object({
          title: shortText(80),
          week: z.number().int().min(1).max(52),
          slot: z.number().int().min(0).max(6),
          exercises: z.array(exerciseSchema).min(1).max(12),
          previous: z.array(previousSetSchema).max(12),
        })
        .strict(),
    })
    .strict(),
  z
    .object({
      schemaVersion: z.literal(NATIVE_TRAINING_CARD_SCHEMA_VERSION),
      component: z.literal('ExerciseSwapCard'),
      object: swapObjectSchema,
      properties: z
        .object({
          sessionId: uuid,
          exerciseId: catalogId,
          alternatives: z.array(alternativeSchema).min(1).max(6),
        })
        .strict(),
    })
    .strict(),
  z
    .object({
      schemaVersion: z.literal(NATIVE_TRAINING_CARD_SCHEMA_VERSION),
      component: z.literal('TrainingFeedbackCard'),
      object: feedbackObjectSchema,
      properties: z
        .object({
          sessionId: uuid,
          prompt: shortText(120),
        })
        .strict(),
    })
    .strict(),
  z
    .object({
      schemaVersion: z.literal(NATIVE_TRAINING_CARD_SCHEMA_VERSION),
      component: z.literal('ProgressReviewCard'),
      object: reviewObjectSchema,
      properties: z
        .object({
          recordedResultIds: z.array(uuid).min(1).max(12),
          citations: z
            .array(
              z
                .object({
                  resultId: uuid,
                  statement: shortText(200),
                })
                .strict(),
            )
            .min(1)
            .max(8),
          proposedChange: z
            .object({
              intent: reviewIntentSchema,
              evidenceIds: z.array(evidenceId).min(1).max(12),
            })
            .strict()
            .nullable(),
        })
        .strict()
        .refine((properties) =>
          properties.citations.every((citation) =>
            properties.recordedResultIds.includes(citation.resultId),
          ),
        ),
    })
    .strict(),
]);

export type NativeTrainingCard = z.infer<typeof nativeTrainingCardSchema>;

export type NativeTrainingCardRejection =
  | 'unknown_component'
  | 'invalid_id'
  | 'unknown_field'
  | 'forbidden_field'
  | 'generated_code'
  | 'invalid_card'
  | 'unknown_action'
  | 'unauthorized'
  | 'object_mismatch'
  | 'invalid_payload';

const FORBIDDEN_KEY =
  /^(code|script|eval|javascript|html|function|generatedcode|swiftsource|fatiguescore|readinessscore)$/i;
const GENERATED_CODE =
  /(?:function\s*\(|<script|javascript:|eval\s*\(|<\/|import\s+|export\s+|=>\s*\{|```)/i;

export type AdmittedNativeTrainingAction =
  | {
      operation: 'saved_revision';
      method: 'decide';
      decision: 'apply' | 'reject';
      proposalId: string;
    }
  | {
      operation: 'saved_revision';
      method: 'propose';
      decision: 'adjust';
      baseProposalId: string;
      utterance: string;
    }
  | {
      operation: 'saved_revision';
      method: 'propose';
      decision: 'propose_change';
      intent: z.infer<typeof reviewIntentSchema>;
      evidenceIds: string[];
      recordedResultIds: string[];
      utterance: string;
    }
  | {
      operation: 'log_set';
      sessionId: string;
      exerciseId: string;
      setNumber: number;
      reps: number;
      loadKg: number | null;
      rir: number;
    }
  | {
      operation: 'correct_set';
      sessionId: string;
      exerciseId: string;
      setNumber: number;
      reps: number;
      loadKg: number | null;
      rir: number;
      correctionId: string;
      expectedRevision: number;
    }
  | {
      operation: 'swap_exercise';
      sessionId: string;
      exerciseId: string;
      toVariantId: string;
    }
  | {
      operation: 'record_feedback';
      sessionId: string;
      feedbackId: string;
      statement: string;
    }
  | { operation: 'local'; kind: 'expand_program'; programId: string }
  | { operation: 'local'; kind: 'expand_session'; sessionId: string }
  | { operation: 'local'; kind: 'navigate_exercise'; sessionId: string; exerciseIndex: number };

export type ChatTurnSession = {
  id: string;
  revisionId?: string | null;
  title: string;
  week: number;
  slot: number;
  exercises: Array<{
    id: string;
    name: string;
    sets: number;
    repRange: { min: number; max: number };
    targetReps: number;
    targetRir: number;
    targetLoadKg: number | null;
    loadInstruction?: string | null;
  }>;
  loggedSets?: Array<{
    exerciseId: string;
    setNumber: number;
    reps: number;
    loadKg: number | null;
    rir: number;
    revision?: number;
  }>;
};

export type DurableTrainingCardSource = {
  proposal?: {
    id: string;
    revisionId?: string | null;
    reason?: string;
    diff?: Array<{ label: string; from: string; to: string }>;
    reasons?: string[];
    evidenceIds?: string[];
    status?: 'pending' | 'applied' | 'rejected';
  } | null;
  program?: {
    id: string;
    revisionId: string;
    proposalId?: string | null;
    title: string;
    weeks: Array<{ week: number; sessions: Array<{ id: string; title: string; slot: number }> }>;
    diff?: Array<{ label: string; from: string; to: string }>;
    reasons?: string[];
    evidenceIds?: string[];
  } | null;
  session?: ChatTurnSession | null;
  swap?: {
    id: string;
    revisionId?: string | null;
    sessionId: string;
    exerciseId: string;
    alternatives: Array<{ id: string; name: string; tradeoff: string }>;
  } | null;
  feedback?: {
    id: string;
    revisionId?: string | null;
    sessionId: string;
    prompt: string;
  } | null;
  review?: {
    id: string;
    revisionId?: string | null;
    recordedResultIds: string[];
    citations: Array<{ resultId: string; statement: string }>;
    proposedChange?: { intent: z.infer<typeof reviewIntentSchema>; evidenceIds: string[] } | null;
  } | null;
};

function walk(value: unknown): NativeTrainingCardRejection | null {
  if (typeof value === 'string') return GENERATED_CODE.test(value) ? 'generated_code' : null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = walk(item);
      if (found) return found;
    }
    return null;
  }
  if (!value || typeof value !== 'object') return null;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_KEY.test(key)) return 'forbidden_field';
    const found = walk(child);
    if (found) return found;
  }
  return null;
}

function componentOf(value: unknown): string | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const component = (value as { component?: unknown }).component;
  return typeof component === 'string' ? component : null;
}

function rejectionFromZod(error: z.ZodError, fallback: NativeTrainingCardRejection) {
  const issue = error.issues[0];
  if (!issue) return fallback;
  if (issue.code === 'unrecognized_keys') return 'unknown_field';
  if (issue.code === 'invalid_value' && issue.path.at(-1) === 'component')
    return 'unknown_component';
  const invalidString = issue.code === 'invalid_format';
  if (invalidString && String(issue.message).toLowerCase().includes('uuid')) return 'invalid_id';
  if (
    issue.path.includes('id') ||
    issue.path.includes('proposalId') ||
    issue.path.includes('revisionId')
  ) {
    return 'invalid_id';
  }
  return fallback;
}

export function parseNativeTrainingCards(
  input: unknown,
): { ok: true; cards: NativeTrainingCard[] } | { ok: false; reason: NativeTrainingCardRejection } {
  if (typeof input === 'string') {
    return { ok: false, reason: GENERATED_CODE.test(input) ? 'generated_code' : 'invalid_card' };
  }
  const items = Array.isArray(input) ? input : [input];
  if (items.length === 0) return { ok: true, cards: [] };
  const cards: NativeTrainingCard[] = [];
  for (const item of items) {
    const forbidden = walk(item);
    if (forbidden) return { ok: false, reason: forbidden };
    const component = componentOf(item);
    if (
      !component ||
      !NATIVE_TRAINING_CARD_COMPONENTS.includes(component as NativeTrainingCardComponent)
    ) {
      return { ok: false, reason: component ? 'unknown_component' : 'invalid_card' };
    }
    const parsed = nativeTrainingCardSchema.safeParse(item);
    if (!parsed.success)
      return { ok: false, reason: rejectionFromZod(parsed.error, 'invalid_card') };
    cards.push(parsed.data);
  }
  return { ok: true, cards };
}

function sameObject(left: NativeTrainingCard['object'], right: NativeTrainingCard['object']) {
  return JSON.stringify(left) === JSON.stringify(right);
}

const emptyPayload = z.object({}).strict();
const logPayload = z
  .object({
    exerciseId: catalogId,
    setNumber: z.number().int().min(1).max(20),
    reps: z.number().int().min(1).max(50),
    loadKg: z.number().finite().nonnegative().max(500).nullable(),
    rir: z.number().int().min(0).max(6),
  })
  .strict();

function actionPayload(action: string) {
  switch (action) {
    case 'adjust_revision':
      return z.object({ utterance: shortText(500) }).strict();
    case 'navigate_exercise':
      return z.object({ exerciseIndex: z.number().int().min(0).max(11) }).strict();
    case 'log_set':
      return logPayload;
    case 'correct_set':
      return logPayload.extend({
        correctionId: uuid,
        expectedRevision: z.number().int().nonnegative(),
      });
    case 'swap_exercise':
      return z.object({ toVariantId: catalogId }).strict();
    case 'record_feedback':
      return z.object({ statement: shortText(280) }).strict();
    default:
      return emptyPayload;
  }
}

function proposalIdFor(card: NativeTrainingCard): string | null {
  if (card.component === 'PlanChangeCard')
    return card.properties.status === 'pending' ? card.object.id : null;
  if (card.component === 'MesoPlanCard') return card.object.proposalId;
  return null;
}

export function admitNativeTrainingCardAction(input: {
  card: NativeTrainingCard;
  request: unknown;
  ownerSubject: string;
}):
  | { ok: true; action: AdmittedNativeTrainingAction }
  | { ok: false; reason: NativeTrainingCardRejection } {
  const forbidden = walk(input.request);
  if (forbidden) return { ok: false, reason: forbidden };
  if (!input.request || typeof input.request !== 'object' || Array.isArray(input.request)) {
    return { ok: false, reason: 'invalid_payload' };
  }
  const raw = input.request as Record<string, unknown>;
  const allowed = NATIVE_TRAINING_CARD_ACTIONS[input.card.component] as readonly string[];
  if (typeof raw.action === 'string' && !allowed.includes(raw.action)) {
    return { ok: false, reason: 'unknown_action' };
  }
  if (raw.component !== input.card.component) return { ok: false, reason: 'object_mismatch' };
  const payloadSchema = actionPayload(typeof raw.action === 'string' ? raw.action : '');
  const parsed = z
    .object({
      schemaVersion: z.literal(NATIVE_TRAINING_CARD_SCHEMA_VERSION),
      action: z.string(),
      component: z.literal(input.card.component),
      object: z.unknown(),
      actorSubject: z.string().trim().min(1).max(200),
      payload: payloadSchema,
    })
    .strict()
    .safeParse(raw);
  if (!parsed.success)
    return { ok: false, reason: rejectionFromZod(parsed.error, 'invalid_payload') };
  if (!input.ownerSubject || parsed.data.actorSubject !== input.ownerSubject) {
    return { ok: false, reason: 'unauthorized' };
  }
  const object = nativeTrainingCardSchema.safeParse({
    schemaVersion: NATIVE_TRAINING_CARD_SCHEMA_VERSION,
    component: input.card.component,
    object: parsed.data.object,
    properties: input.card.properties,
  });
  if (!object.success || !sameObject(object.data.object, input.card.object)) {
    return { ok: false, reason: 'object_mismatch' };
  }
  const action = parsed.data.action;
  const payload = parsed.data.payload as Record<string, unknown>;
  if (action === 'apply_revision' || action === 'reject_revision') {
    const proposalId = proposalIdFor(input.card);
    if (!proposalId) return { ok: false, reason: 'invalid_payload' };
    return {
      ok: true,
      action: {
        operation: 'saved_revision',
        method: 'decide',
        decision: action === 'apply_revision' ? 'apply' : 'reject',
        proposalId,
      },
    };
  }
  if (action === 'adjust_revision') {
    const proposalId = proposalIdFor(input.card);
    if (!proposalId) return { ok: false, reason: 'invalid_payload' };
    return {
      ok: true,
      action: {
        operation: 'saved_revision',
        method: 'propose',
        decision: 'adjust',
        baseProposalId: proposalId,
        utterance: String(payload.utterance),
      },
    };
  }
  if (action === 'expand_program' && input.card.component === 'MesoPlanCard') {
    return {
      ok: true,
      action: { operation: 'local', kind: 'expand_program', programId: input.card.object.id },
    };
  }
  if (input.card.component === 'WorkoutSessionCard') {
    if (action === 'expand_session') {
      return {
        ok: true,
        action: { operation: 'local', kind: 'expand_session', sessionId: input.card.object.id },
      };
    }
    if (action === 'navigate_exercise') {
      const exerciseIndex = Number(payload.exerciseIndex);
      if (exerciseIndex >= input.card.properties.exercises.length) {
        return { ok: false, reason: 'invalid_payload' };
      }
      return {
        ok: true,
        action: {
          operation: 'local',
          kind: 'navigate_exercise',
          sessionId: input.card.object.id,
          exerciseIndex,
        },
      };
    }
    const exercise = input.card.properties.exercises.find((item) => item.id === payload.exerciseId);
    if (!exercise) return { ok: false, reason: 'invalid_payload' };
    if (action === 'log_set') {
      if (
        payload.setNumber !== exercise.completedSets + 1 ||
        Number(payload.setNumber) > exercise.sets
      ) {
        return { ok: false, reason: 'invalid_payload' };
      }
      return {
        ok: true,
        action: {
          operation: 'log_set',
          sessionId: input.card.object.id,
          exerciseId: exercise.id,
          setNumber: Number(payload.setNumber),
          reps: Number(payload.reps),
          loadKg: payload.loadKg as number | null,
          rir: Number(payload.rir),
        },
      };
    }
    if (action === 'correct_set') {
      const previous = input.card.properties.previous.find(
        (item) => item.exerciseId === exercise.id,
      );
      if (
        !previous ||
        previous.revision === null ||
        previous.setNumber !== payload.setNumber ||
        previous.revision !== payload.expectedRevision
      ) {
        return { ok: false, reason: 'invalid_payload' };
      }
      return {
        ok: true,
        action: {
          operation: 'correct_set',
          sessionId: input.card.object.id,
          exerciseId: exercise.id,
          setNumber: previous.setNumber,
          reps: Number(payload.reps),
          loadKg: payload.loadKg as number | null,
          rir: Number(payload.rir),
          correctionId: String(payload.correctionId),
          expectedRevision: previous.revision,
        },
      };
    }
  }
  if (action === 'swap_exercise' && input.card.component === 'ExerciseSwapCard') {
    const toVariantId = String(payload.toVariantId);
    if (!input.card.properties.alternatives.some((item) => item.id === toVariantId)) {
      return { ok: false, reason: 'invalid_payload' };
    }
    return {
      ok: true,
      action: {
        operation: 'swap_exercise',
        sessionId: input.card.properties.sessionId,
        exerciseId: input.card.properties.exerciseId,
        toVariantId,
      },
    };
  }
  if (action === 'record_feedback' && input.card.component === 'TrainingFeedbackCard') {
    return {
      ok: true,
      action: {
        operation: 'record_feedback',
        sessionId: input.card.properties.sessionId,
        feedbackId: input.card.object.id,
        statement: String(payload.statement),
      },
    };
  }
  if (action === 'propose_change' && input.card.component === 'ProgressReviewCard') {
    const change = input.card.properties.proposedChange;
    if (!change) return { ok: false, reason: 'invalid_payload' };
    return {
      ok: true,
      action: {
        operation: 'saved_revision',
        method: 'propose',
        decision: 'propose_change',
        intent: change.intent,
        evidenceIds: change.evidenceIds,
        recordedResultIds: input.card.properties.recordedResultIds,
        utterance: change.intent,
      },
    };
  }
  return { ok: false, reason: 'unknown_action' };
}

function keepEvidence(ids: string[] | undefined) {
  return (ids ?? []).filter((id) => evidenceId.safeParse(id).success);
}

function keepDiff(diff: Array<{ label: string; from: string; to: string }> | undefined) {
  return (diff ?? []).filter((item) => diffSchema.safeParse(item).success);
}

export function nativeCardsForChatTurn(source: DurableTrainingCardSource): NativeTrainingCard[] {
  const candidates: unknown[] = [];
  if (source.program) {
    candidates.push({
      schemaVersion: NATIVE_TRAINING_CARD_SCHEMA_VERSION,
      component: 'MesoPlanCard',
      object: {
        kind: 'program_revision',
        id: source.program.id,
        revisionId: source.program.revisionId,
        proposalId: source.program.proposalId ?? null,
      },
      properties: {
        title: source.program.title,
        weekCount: source.program.weeks.length,
        compact: true,
        weeks: source.program.weeks,
        diff: keepDiff(source.program.diff),
        reasons: (source.program.reasons ?? []).filter(
          (reason) => shortText(160).safeParse(reason).success,
        ),
        evidenceIds: keepEvidence(source.program.evidenceIds),
      },
    });
  }
  if (source.proposal?.id) {
    candidates.push({
      schemaVersion: NATIVE_TRAINING_CARD_SCHEMA_VERSION,
      component: 'PlanChangeCard',
      object: {
        kind: 'proposal',
        id: source.proposal.id,
        revisionId: source.proposal.revisionId ?? null,
      },
      properties: {
        reason: source.proposal.reason?.trim() || 'Review this saved change before it starts.',
        diff: keepDiff(source.proposal.diff),
        reasons: (source.proposal.reasons ?? []).filter(
          (reason) => shortText(160).safeParse(reason).success,
        ),
        evidenceIds: keepEvidence(source.proposal.evidenceIds),
        status: source.proposal.status ?? 'pending',
      },
    });
  }
  if (source.session) {
    const logs = source.session.loggedSets ?? [];
    candidates.push({
      schemaVersion: NATIVE_TRAINING_CARD_SCHEMA_VERSION,
      component: 'WorkoutSessionCard',
      object: {
        kind: 'session',
        id: source.session.id,
        revisionId: source.session.revisionId ?? null,
      },
      properties: {
        title: source.session.title,
        week: source.session.week,
        slot: source.session.slot,
        exercises: source.session.exercises.map((exercise) => {
          const completed = logs.filter((log) => log.exerciseId === exercise.id).length;
          return {
            id: exercise.id,
            name: exercise.name,
            setup:
              exercise.loadInstruction?.trim() || `Use the prescribed setup for ${exercise.name}.`,
            sets: exercise.sets,
            repRange: exercise.repRange,
            targetReps: exercise.targetReps,
            targetRir: exercise.targetRir,
            targetLoadKg: exercise.targetLoadKg,
            completedSets: Math.min(completed, exercise.sets),
          };
        }),
        previous: source.session.exercises.flatMap((exercise) => {
          const latest = logs
            .filter((log) => log.exerciseId === exercise.id)
            .sort((left, right) => right.setNumber - left.setNumber)[0];
          if (!latest) return [];
          return [
            {
              exerciseId: exercise.id,
              setNumber: latest.setNumber,
              reps: latest.reps,
              loadKg: latest.loadKg,
              rir: latest.rir,
              revision: latest.revision ?? null,
            },
          ];
        }),
      },
    });
  }
  if (source.swap && source.swap.alternatives.length > 0) {
    candidates.push({
      schemaVersion: NATIVE_TRAINING_CARD_SCHEMA_VERSION,
      component: 'ExerciseSwapCard',
      object: {
        kind: 'exercise_swap',
        id: source.swap.id,
        revisionId: source.swap.revisionId ?? null,
      },
      properties: {
        sessionId: source.swap.sessionId,
        exerciseId: source.swap.exerciseId,
        alternatives: source.swap.alternatives,
      },
    });
  }
  if (source.feedback) {
    candidates.push({
      schemaVersion: NATIVE_TRAINING_CARD_SCHEMA_VERSION,
      component: 'TrainingFeedbackCard',
      object: {
        kind: 'feedback',
        id: source.feedback.id,
        revisionId: source.feedback.revisionId ?? null,
      },
      properties: {
        sessionId: source.feedback.sessionId,
        prompt: source.feedback.prompt,
      },
    });
  }
  if (
    source.review &&
    source.review.citations.length > 0 &&
    source.review.recordedResultIds.length > 0
  ) {
    const proposed = source.review.proposedChange;
    candidates.push({
      schemaVersion: NATIVE_TRAINING_CARD_SCHEMA_VERSION,
      component: 'ProgressReviewCard',
      object: {
        kind: 'progress_review',
        id: source.review.id,
        revisionId: source.review.revisionId ?? null,
      },
      properties: {
        recordedResultIds: source.review.recordedResultIds,
        citations: source.review.citations,
        proposedChange:
          proposed && proposed.evidenceIds.length > 0
            ? { intent: proposed.intent, evidenceIds: keepEvidence(proposed.evidenceIds) }
            : null,
      },
    });
  }
  const cards: NativeTrainingCard[] = [];
  for (const candidate of candidates) {
    const parsed = parseNativeTrainingCards(candidate);
    if (parsed.ok && parsed.cards[0]) cards.push(parsed.cards[0]);
  }
  return cards;
}
