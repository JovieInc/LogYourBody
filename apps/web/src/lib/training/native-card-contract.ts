/**
 * Version 1 approved contract for native training cards.
 *
 * json-render is not a supported consumer: it has no SwiftUI runtime in this
 * app. Owned SwiftUI views render the same component names. This module does
 * not render a web workout surface and does not execute generated code.
 */

export const NATIVE_TRAINING_CARD_SCHEMA_VERSION = 1;

export const NATIVE_TRAINING_CARD_COMPONENTS = [
  'MesoPlanCard',
  'PlanChangeCard',
  'WorkoutSessionCard',
  'ExerciseSwapCard',
  'TrainingFeedbackCard',
  'ProgressReviewCard',
] as const;

export type NativeTrainingCardComponent = (typeof NATIVE_TRAINING_CARD_COMPONENTS)[number];

export const NATIVE_TRAINING_CARD_RENDER_TARGET = {
  jsonRenderSupported: false,
  consumer: 'swiftui-owned-views',
  reason:
    'json-render has no supported SwiftUI consumer. The catalog maps to owned views and is not a runtime migration.',
} as const;

const READ_ACTIONS: Record<NativeTrainingCardComponent, readonly string[]> = {
  MesoPlanCard: ['open_week'],
  PlanChangeCard: [],
  WorkoutSessionCard: ['open_session'],
  ExerciseSwapCard: [],
  TrainingFeedbackCard: [],
  ProgressReviewCard: ['refresh'],
};

const WRITE_ACTIONS: Record<NativeTrainingCardComponent, readonly string[]> = {
  MesoPlanCard: [],
  PlanChangeCard: ['apply_saved_revision', 'adjust_saved_revision', 'reject_saved_revision'],
  WorkoutSessionCard: ['log_set', 'correct_set'],
  ExerciseSwapCard: ['select_swap'],
  TrainingFeedbackCard: ['submit_feedback'],
  ProgressReviewCard: [],
};

const CODE_KEYS = new Set([
  'code',
  'script',
  'html',
  'javascript',
  'eval',
  'function',
  'generatedcode',
  'sourcecode',
]);

const SCORE_KEYS = new Set(['fatiguescore', 'readinessscore', 'recoveryscore']);

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CATALOG_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/;
const REVISION_PATTERN = /^(0|[1-9][0-9]{0,8})$/;
const OWNER_PATTERN = /^[A-Za-z0-9._:@+-]{1,200}$/;
const CODE_TEXT = /javascript:|<script|\beval\s*\(|\bfunction\s*\(/i;

export type NativeTrainingCardRejection =
  | 'unknown_component'
  | 'invalid_id'
  | 'unauthorized'
  | 'generated_code'
  | 'unsupported_action'
  | 'transcript_only'
  | 'invented_score'
  | 'invalid_schema';

export type ApprovedNativeTrainingAction = {
  kind: string;
  operation: 'saved_revision' | 'session_log' | 'exercise_swap' | 'session_feedback' | 'read';
  targetId: string;
};

export type ApprovedNativeTrainingCard = {
  schemaVersion: 1;
  component: NativeTrainingCardComponent;
  objectId: string;
  revision: string;
  ownerSubject: string;
  actions: ApprovedNativeTrainingAction[];
};

type Validation =
  | { ok: true; card: ApprovedNativeTrainingCard }
  | { ok: false; reason: NativeTrainingCardRejection };

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function scan(value: unknown): NativeTrainingCardRejection | null {
  if (typeof value === 'string') return CODE_TEXT.test(value) ? 'generated_code' : null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = scan(item);
      if (found) return found;
    }
    return null;
  }
  if (!isRecord(value)) return null;
  if ('root' in value && 'elements' in value) return 'generated_code';
  for (const [key, child] of Object.entries(value)) {
    const normalized = key.toLowerCase();
    if (key.startsWith('$')) return 'generated_code';
    if (SCORE_KEYS.has(normalized)) return 'invented_score';
    if (CODE_KEYS.has(normalized)) return 'generated_code';
    const found = scan(child);
    if (found) return found;
  }
  return null;
}

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

function isCatalogId(value: unknown): value is string {
  return typeof value === 'string' && (UUID_PATTERN.test(value) || CATALOG_ID_PATTERN.test(value));
}

function isRevision(value: unknown): value is string {
  return typeof value === 'string' && (UUID_PATTERN.test(value) || REVISION_PATTERN.test(value));
}

function stringList(value: unknown): string[] | null {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) return null;
  return value as string[];
}

function componentOf(value: unknown): NativeTrainingCardComponent | null {
  return NATIVE_TRAINING_CARD_COMPONENTS.find((component) => component === value) ?? null;
}

function actorMatches(record: Record<string, unknown>, ownerSubject: string): boolean {
  for (const key of ['ownerSubject', 'actorSubject', 'subject', 'actor']) {
    const value = record[key];
    if (typeof value === 'string' && value !== ownerSubject) return false;
  }
  return true;
}

function actionRecord(value: unknown, ownerSubject: string): Record<string, unknown> | null {
  if (!isRecord(value) || !actorMatches(value, ownerSubject)) return null;
  return value;
}

function pushAction(
  actions: ApprovedNativeTrainingAction[],
  kind: string,
  operation: ApprovedNativeTrainingAction['operation'],
  targetId: string,
): void {
  actions.push({ kind, operation, targetId });
}

function validateAction(
  component: NativeTrainingCardComponent,
  objectId: string,
  revision: string,
  props: Record<string, unknown>,
  action: Record<string, unknown>,
  actions: ApprovedNativeTrainingAction[],
): NativeTrainingCardRejection | null {
  const kind = action.kind;
  if (typeof kind !== 'string') return 'unsupported_action';
  if (READ_ACTIONS[component].includes(kind)) {
    if (action.operation !== undefined && action.operation !== 'read') return 'unsupported_action';
    pushAction(actions, kind, 'read', objectId);
    return null;
  }
  if (!WRITE_ACTIONS[component].includes(kind)) return 'unsupported_action';
  if (component === 'PlanChangeCard') {
    if (action.operation !== 'saved_revision') return 'unsupported_action';
    if (action.proposalId !== objectId || action.expectedRevision !== revision)
      return 'unauthorized';
    if (kind === 'adjust_saved_revision' && action.utterance !== undefined) {
      const utterance = action.utterance;
      if (
        typeof utterance !== 'string' ||
        utterance.trim().length === 0 ||
        utterance.length > 240
      ) {
        return 'invalid_schema';
      }
    }
    pushAction(actions, kind, 'saved_revision', objectId);
    return null;
  }
  if (component === 'WorkoutSessionCard') {
    if (action.operation !== 'session_log' || action.sessionId !== objectId) return 'unauthorized';
    const exercises = Array.isArray(props.exercises) ? props.exercises : [];
    const known = exercises.some((item) => isRecord(item) && item.id === action.exerciseId);
    if (!known || !isCatalogId(action.exerciseId)) return 'invalid_id';
    if (typeof action.setNumber !== 'number' || action.setNumber < 1) return 'invalid_schema';
    pushAction(actions, kind, 'session_log', objectId);
    return null;
  }
  if (component === 'ExerciseSwapCard') {
    if (action.operation !== 'exercise_swap' || action.sessionId !== props.sessionId) {
      return 'unauthorized';
    }
    const alternatives = Array.isArray(props.alternatives) ? props.alternatives : [];
    const eligible = alternatives.some((item) => isRecord(item) && item.id === action.toVariantId);
    if (!eligible || !isCatalogId(action.toVariantId)) return 'invalid_id';
    pushAction(actions, kind, 'exercise_swap', String(props.sessionId));
    return null;
  }
  if (action.operation !== 'session_feedback' || action.sessionId !== props.sessionId) {
    return 'unauthorized';
  }
  if (
    action.performance !== undefined &&
    !['up', 'stable', 'down'].includes(String(action.performance))
  ) {
    return 'invalid_schema';
  }
  pushAction(actions, kind, 'session_feedback', String(props.sessionId));
  return null;
}

function propsValid(
  component: NativeTrainingCardComponent,
  props: Record<string, unknown>,
  objectId: string,
): NativeTrainingCardRejection | null {
  if (component === 'PlanChangeCard' && props.proposalId !== objectId) return 'invalid_id';
  if (component === 'ExerciseSwapCard' && props.sessionId !== objectId) return 'invalid_id';
  if (component === 'WorkoutSessionCard' && props.sessionId !== objectId) return 'invalid_id';
  if (component === 'TrainingFeedbackCard' && props.sessionId !== objectId) return 'invalid_id';
  if (component === 'ProgressReviewCard') {
    const cited = stringList(props.citedResultIds);
    if (!cited || cited.some((id) => !isUuid(id))) return 'invalid_id';
    if (props.proposal != null && cited.length === 0) return 'invalid_schema';
    if (isRecord(props.proposal) && props.proposal.before === props.proposal.after)
      return 'invalid_schema';
  }
  if (component === 'MesoPlanCard' && !Array.isArray(props.sessions)) return 'invalid_schema';
  return null;
}

export function validateNativeTrainingCard(input: unknown, ownerSubject: string): Validation {
  const scanned = scan(input);
  if (scanned) return { ok: false, reason: scanned };
  if (!OWNER_PATTERN.test(ownerSubject) || !isRecord(input))
    return { ok: false, reason: 'invalid_schema' };
  if (input.schemaVersion !== NATIVE_TRAINING_CARD_SCHEMA_VERSION)
    return { ok: false, reason: 'invalid_schema' };
  const component = componentOf(input.component);
  if (!component) return { ok: false, reason: 'unknown_component' };
  if (!isUuid(input.objectId) || !isRevision(input.revision))
    return { ok: false, reason: 'invalid_id' };
  if (input.ownerSubject !== ownerSubject || !actorMatches(input, ownerSubject)) {
    return { ok: false, reason: 'unauthorized' };
  }
  if (!isRecord(input.props)) return { ok: false, reason: 'invalid_schema' };
  const propsProblem = propsValid(component, input.props, input.objectId);
  if (propsProblem) return { ok: false, reason: propsProblem };
  if (!Array.isArray(input.actions)) return { ok: false, reason: 'invalid_schema' };
  const actions: ApprovedNativeTrainingAction[] = [];
  for (const value of input.actions) {
    const action = actionRecord(value, ownerSubject);
    if (!action) return { ok: false, reason: 'unauthorized' };
    const problem = validateAction(
      component,
      input.objectId,
      input.revision,
      input.props,
      action,
      actions,
    );
    if (problem) return { ok: false, reason: problem };
  }
  return {
    ok: true,
    card: {
      schemaVersion: 1,
      component,
      objectId: input.objectId,
      revision: input.revision,
      ownerSubject,
      actions,
    },
  };
}

export function approveTranscriptCard(
  input: unknown,
  ownerSubject: string,
  durableCards: ApprovedNativeTrainingCard[],
): Validation {
  const validated = validateNativeTrainingCard(input, ownerSubject);
  if (!validated.ok) return validated;
  const durable = durableCards.find(
    (card) =>
      card.component === validated.card.component &&
      card.objectId === validated.card.objectId &&
      card.revision === validated.card.revision &&
      card.ownerSubject === ownerSubject,
  );
  if (!durable) return { ok: false, reason: 'transcript_only' };
  const durableKinds = new Set(durable.actions.map((action) => action.kind));
  if (validated.card.actions.some((action) => !durableKinds.has(action.kind))) {
    return { ok: false, reason: 'unauthorized' };
  }
  return { ok: true, card: durable };
}

export function savedRevisionDecision(kind: string): 'apply' | 'reject' | 'adjust' | null {
  if (kind === 'apply_saved_revision') return 'apply';
  if (kind === 'reject_saved_revision') return 'reject';
  if (kind === 'adjust_saved_revision') return 'adjust';
  return null;
}

/** User text for an adjust action. The card grants the capability; this checks the note. */
export function adjustmentUtteranceIsValid(utterance: string): boolean {
  const scanned = scan(utterance);
  return scanned == null && utterance.trim().length > 0 && utterance.length <= 240;
}
