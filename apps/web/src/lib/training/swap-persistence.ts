import { z } from 'zod';
import type {
  NativeProductRecord,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { CATALOG_EQUIPMENT, catalogVariantById, type CatalogEquipment } from './catalog';

/** User-submitted setup measures. A missing key is unknown and is never stored as 0. */
export const SETUP_DIMENSIONS = [
  'benchClearance',
  'floorClearance',
  'cableLine',
  'rangeOfMotion',
] as const;
export type SetupDimension = (typeof SETUP_DIMENSIONS)[number];

export type PersistedResponses = {
  jointDiscomfort?: number;
  trunkFatigue?: number;
  generalExhaustion?: number;
  stability?: 'stable' | 'unstable';
  targetMuscleQuality?: 'poor' | 'adequate' | 'good';
  romRestriction?: 'none' | 'limited' | 'blocked';
  tolerated?: boolean;
  beltRequested?: boolean;
  symptomsPersist?: boolean;
};

/** Facts from one approved swap for the active gym profile. */
export type PersistedSwapState = {
  version: 1;
  sessionId: string;
  gymId: string;
  approvedExerciseId: string;
  setupId: string;
  confirmedEquipment: CatalogEquipment[];
  dimensions: Partial<Record<SetupDimension, number>>;
  responses: PersistedResponses;
  previousExerciseId: string;
  rolledBack: boolean;
  updatedAt: string;
};

export type ApprovedSwapSubmission = {
  gymId: string;
  approvedExerciseId: string;
  setupId: string;
  previousExerciseId: string;
  confirmedEquipment: readonly string[];
  dimensions?: Partial<Record<SetupDimension, number | null>>;
  responses?: Record<string, unknown>;
};

const EPOCH = '1970-01-01T00:00:00.000Z';

const dimensionSchema = z
  .object({
    benchClearance: z.number().finite().min(0).max(1000).optional(),
    floorClearance: z.number().finite().min(0).max(1000).optional(),
    cableLine: z.number().finite().min(0).max(1000).optional(),
    rangeOfMotion: z.number().finite().min(0).max(1000).optional(),
  })
  .strict();

const responseSchema = z
  .object({
    jointDiscomfort: z.number().int().min(0).max(10).optional(),
    trunkFatigue: z.number().int().min(0).max(10).optional(),
    generalExhaustion: z.number().int().min(0).max(10).optional(),
    stability: z.enum(['stable', 'unstable']).optional(),
    targetMuscleQuality: z.enum(['poor', 'adequate', 'good']).optional(),
    romRestriction: z.enum(['none', 'limited', 'blocked']).optional(),
    tolerated: z.boolean().optional(),
    beltRequested: z.boolean().optional(),
    symptomsPersist: z.boolean().optional(),
  })
  .strict();

const persistedSwapSchema = z
  .object({
    version: z.literal(1),
    sessionId: z.string().trim().min(1).max(80),
    gymId: z.string().trim().min(1).max(80),
    approvedExerciseId: z.string().regex(/^[a-z][a-z0-9_]*$/),
    setupId: z.string().regex(/^[a-z][a-z0-9_]*$/),
    confirmedEquipment: z.array(z.enum(CATALOG_EQUIPMENT)).max(CATALOG_EQUIPMENT.length),
    dimensions: dimensionSchema,
    responses: responseSchema,
    previousExerciseId: z.string().regex(/^[a-z][a-z0-9_]*$/),
    rolledBack: z.boolean(),
    updatedAt: z.string().refine((value) => Number.isFinite(Date.parse(value))),
  })
  .strict();

function defined<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined)) as T;
}

function catalogId(value: unknown): string | null {
  return typeof value === 'string' && catalogVariantById(value) ? value : null;
}

function gymProfileId(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (trimmed.length < 1 || trimmed.length > 80 || /[\u0000-\u001f]/.test(trimmed)) return null;
  return trimmed;
}

function submittedNumber(value: unknown): number | undefined {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1000)
    return undefined;
  return value;
}

function submittedInteger(value: unknown): number | undefined {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value > 10)
    return undefined;
  return value;
}

function submittedChoice<const T extends string>(
  value: unknown,
  allowed: readonly T[],
): T | undefined {
  return typeof value === 'string' && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : undefined;
}

function submittedFlag(value: unknown): boolean | undefined {
  return typeof value === 'boolean' ? value : undefined;
}

/** Copies only keys the caller actually set. Null and omitted measures stay absent. */
function pickDimensions(
  input: ApprovedSwapSubmission['dimensions'],
): Partial<Record<SetupDimension, number>> {
  if (!input) return {};
  const dimensions: Partial<Record<SetupDimension, number>> = {};
  for (const key of SETUP_DIMENSIONS) {
    if (!Object.hasOwn(input, key)) continue;
    const value = submittedNumber(input[key]);
    if (value !== undefined) dimensions[key] = value;
  }
  return dimensions;
}

function pickResponses(input: ApprovedSwapSubmission['responses']): PersistedResponses {
  if (!input) return {};
  const responses: PersistedResponses = {};
  const jointDiscomfort = submittedInteger(input.jointDiscomfort);
  const trunkFatigue = submittedInteger(input.trunkFatigue);
  const generalExhaustion = submittedInteger(input.generalExhaustion);
  const stability = submittedChoice(input.stability, ['stable', 'unstable'] as const);
  const targetMuscleQuality = submittedChoice(input.targetMuscleQuality, [
    'poor',
    'adequate',
    'good',
  ] as const);
  const romRestriction = submittedChoice(input.romRestriction, [
    'none',
    'limited',
    'blocked',
  ] as const);
  const tolerated = submittedFlag(input.tolerated);
  const beltRequested = submittedFlag(input.beltRequested);
  const symptomsPersist = submittedFlag(input.symptomsPersist);
  if (Object.hasOwn(input, 'jointDiscomfort') && jointDiscomfort !== undefined)
    responses.jointDiscomfort = jointDiscomfort;
  if (Object.hasOwn(input, 'trunkFatigue') && trunkFatigue !== undefined)
    responses.trunkFatigue = trunkFatigue;
  if (Object.hasOwn(input, 'generalExhaustion') && generalExhaustion !== undefined)
    responses.generalExhaustion = generalExhaustion;
  if (Object.hasOwn(input, 'stability') && stability) responses.stability = stability;
  if (Object.hasOwn(input, 'targetMuscleQuality') && targetMuscleQuality)
    responses.targetMuscleQuality = targetMuscleQuality;
  if (Object.hasOwn(input, 'romRestriction') && romRestriction)
    responses.romRestriction = romRestriction;
  if (Object.hasOwn(input, 'tolerated') && tolerated !== undefined) responses.tolerated = tolerated;
  if (Object.hasOwn(input, 'beltRequested') && beltRequested !== undefined)
    responses.beltRequested = beltRequested;
  if (Object.hasOwn(input, 'symptomsPersist') && symptomsPersist !== undefined)
    responses.symptomsPersist = symptomsPersist;
  return responses;
}

function confirmedEquipment(values: readonly string[]): CatalogEquipment[] | null {
  const equipment: CatalogEquipment[] = [];
  for (const value of values) {
    if (!(CATALOG_EQUIPMENT as readonly string[]).includes(value)) return null;
    const item = value as CatalogEquipment;
    if (!equipment.includes(item)) equipment.push(item);
  }
  return equipment;
}

/** Builds the stored record from an explicit submission. Unknown keys are ignored. */
export function storeApprovedSwap(
  submission: ApprovedSwapSubmission,
  context: { sessionId: string; updatedAt: string },
): PersistedSwapState | null {
  const gymId = gymProfileId(submission.gymId);
  const approvedExerciseId = catalogId(submission.approvedExerciseId);
  const setupId = catalogId(submission.setupId);
  const previousExerciseId = catalogId(submission.previousExerciseId);
  const equipment = confirmedEquipment(submission.confirmedEquipment ?? []);
  const sessionId = gymProfileId(context.sessionId);
  if (
    !gymId ||
    !approvedExerciseId ||
    !setupId ||
    !previousExerciseId ||
    !equipment ||
    !sessionId ||
    approvedExerciseId === previousExerciseId ||
    !Number.isFinite(Date.parse(context.updatedAt))
  )
    return null;
  return {
    version: 1,
    sessionId,
    gymId,
    approvedExerciseId,
    setupId,
    confirmedEquipment: equipment,
    dimensions: pickDimensions(submission.dimensions),
    responses: pickResponses(submission.responses),
    previousExerciseId,
    rolledBack: false,
    updatedAt: context.updatedAt,
  };
}

/** Reads a previously stored record. A malformed or extended payload is ignored. */
export function reloadApprovedSwap(raw: unknown): PersistedSwapState | null {
  const parsed = persistedSwapSchema.safeParse(raw);
  if (!parsed.success) return null;
  if (
    !catalogVariantById(parsed.data.approvedExerciseId) ||
    !catalogVariantById(parsed.data.setupId) ||
    !catalogVariantById(parsed.data.previousExerciseId)
  )
    return null;
  return {
    ...parsed.data,
    dimensions: defined(parsed.data.dimensions),
    responses: defined(parsed.data.responses),
  };
}

/** One action: the next prescription read returns the exercise from before the swap. */
export function rollbackApprovedSwap(
  state: PersistedSwapState,
  updatedAt: string,
): PersistedSwapState | null {
  if (!Number.isFinite(Date.parse(updatedAt))) return null;
  return { ...state, rolledBack: true, updatedAt };
}

/**
 * Exercise the next prescription should use. One tolerated response does not
 * change this rule and does not exclude other exercises.
 */
export function readNextPrescriptionExercise(
  plannedExerciseId: string,
  state: PersistedSwapState | null,
): string {
  if (!state) return plannedExerciseId;
  if (state.rolledBack)
    return plannedExerciseId === state.approvedExerciseId
      ? state.previousExerciseId
      : plannedExerciseId;
  return plannedExerciseId === state.previousExerciseId
    ? state.approvedExerciseId
    : plannedExerciseId;
}

/** A stored response never marks other exercises ineligible. */
export function ineligibleAlternatives(_state: PersistedSwapState): readonly string[] {
  return [];
}

export function latestSwapState(
  records: readonly {
    programSetupId?: unknown;
    deleted_at?: unknown;
    swapPersistence?: unknown;
  }[],
  setupId: string,
): PersistedSwapState | null {
  const states = records.flatMap((record) => {
    if (record.deleted_at || record.programSetupId !== setupId) return [];
    const state = reloadApprovedSwap(record.swapPersistence);
    return state ? [state] : [];
  });
  states.sort(
    (a, b) => a.updatedAt.localeCompare(b.updatedAt) || a.sessionId.localeCompare(b.sessionId),
  );
  return states.at(-1) ?? null;
}

async function pullCollection(
  records: NativeProductRecordsPort,
  subject: string,
  collection: 'training_sessions' | 'logged_sets',
): Promise<NativeProductRecord[]> {
  const all: NativeProductRecord[] = [];
  const visited = new Set<string>();
  let cursor: { since: string; after_id: string | null } = { since: EPOCH, after_id: null };
  for (;;) {
    const page = await records.pull(subject, collection, { ...cursor, limit: 500 });
    all.push(...page.records);
    if (!page.next_cursor) return all;
    const key = `${page.next_cursor.since}\0${page.next_cursor.after_id ?? ''}`;
    if (visited.has(key)) throw new Error('training_records_pagination_stalled');
    visited.add(key);
    cursor = page.next_cursor;
  }
}

async function writeSwap(
  records: NativeProductRecordsPort,
  subject: string,
  sessionId: string,
  state: PersistedSwapState,
): Promise<boolean> {
  if (!records.updateTrainingSession) return false;
  const [sessions, sets] = await Promise.all([
    pullCollection(records, subject, 'training_sessions'),
    pullCollection(records, subject, 'logged_sets'),
  ]);
  const record = sessions.find((item) => item.id === sessionId && item.deleted_at === null);
  if (!record || record.record_type !== 'workout_session') return false;
  const prescription = record.prescription as { executionRevision?: number } | undefined;
  const logged = sets.filter(
    (item) => item.deleted_at === null && item.sessionId === sessionId,
  ).length;
  const saved = await records.updateTrainingSession(
    subject,
    sessionId,
    Number(prescription?.executionRevision ?? 0),
    logged,
    { ...record, swapPersistence: state },
  );
  return saved !== null;
}

export async function saveApprovedSwap(input: {
  records: NativeProductRecordsPort;
  subject: string;
  sessionId: string;
  now: Date;
  submission: ApprovedSwapSubmission;
}): Promise<PersistedSwapState | null> {
  const state = storeApprovedSwap(input.submission, {
    sessionId: input.sessionId,
    updatedAt: input.now.toISOString(),
  });
  if (!state) return null;
  return (await writeSwap(input.records, input.subject, input.sessionId, state)) ? state : null;
}

export async function rollbackSavedSwap(input: {
  records: NativeProductRecordsPort;
  subject: string;
  sessionId: string;
  now: Date;
}): Promise<PersistedSwapState | null> {
  const sessions = await pullCollection(input.records, input.subject, 'training_sessions');
  const record = sessions.find((item) => item.id === input.sessionId && item.deleted_at === null);
  const current = reloadApprovedSwap(record?.swapPersistence);
  if (!current) return null;
  const rolled = rollbackApprovedSwap(current, input.now.toISOString());
  if (!rolled) return null;
  return (await writeSwap(input.records, input.subject, input.sessionId, rolled)) ? rolled : null;
}
