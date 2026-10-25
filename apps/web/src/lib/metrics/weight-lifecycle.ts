import { createHash } from 'node:crypto';
import { z } from 'zod';

/** International avoirdupois pound. Native logging and this action use the same constant. */
export const POUNDS_TO_KILOGRAMS = '0.45359237';
const POUND_MICRO_KG = BigInt('45359237');
const ZERO = BigInt(0);
const TWO = BigInt(2);
const THOUSAND = BigInt(1000);
const HUNDRED_THOUSAND = BigInt(100000);
const MILLION = BigInt(1000000);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const WEIGHT_LIST_DEFAULT_LIMIT = 50;
export const WEIGHT_LIST_MAX_LIMIT = 100;

const KG_MIN_MILLI = BigInt(32000);
const KG_MAX_MILLI = BigInt(300000);
const LB_MIN_MILLI = BigInt(70000);
const LB_MAX_MILLI = BigInt(660000);

const measuredPattern =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-]\d{2}:\d{2})$/;

export type WeightUnit = 'kg' | 'lb';

export type WeightFailureCode =
  | 'invalid_input'
  | 'spoofed_subject'
  | 'gate_off'
  | 'revoked'
  | 'account_deleted'
  | 'account_not_found'
  | 'unconnected'
  | 'consent_required'
  | 'ineligible'
  | 'not_found'
  | 'idempotency_conflict'
  | 'stale_revision'
  | 'already_deleted'
  | 'record_conflict';

export type WeightFailure = { ok: false; code: WeightFailureCode; reason?: string };

export type MetricsGrant = {
  subject: string;
  ownerId: string | null;
  connected: boolean;
  consentGranted: boolean;
  entitled: boolean;
  revoked: boolean;
  accountDeleted: boolean;
};

export type WeightReceipt = {
  operation_id: string;
  action: 'create' | 'correct' | 'delete';
  record: {
    id: string;
    revision: number;
    weight_kg: string;
    input: { value: string; unit: WeightUnit };
    measured_at: string;
    utc_offset_minutes: number;
    local_date: string;
    iana_zone: string;
    deleted_at: string | null;
    provenance: {
      actor: 'agent' | 'device';
      conversion: 'identity' | 'lb*0.45359237';
      constant: typeof POUNDS_TO_KILOGRAMS;
      canonical_kg: string;
    };
  };
  cloud: { status: 'committed'; server_updated_at: string };
  device: { healthkit: 'not_claimed' };
};

export type WeightSuccess = { ok: true; replayed: boolean; receipt: WeightReceipt };
export type WeightActionResult = WeightSuccess | WeightFailure;

export type StoredWeightEntry = {
  id: string;
  subject: string;
  revision: number;
  weight_kg: string;
  input_value: string;
  input_unit: WeightUnit;
  measured_at: string;
  utc_offset_minutes: number;
  local_date: string;
  iana_zone: string;
  deleted_at: string | null;
  client_updated_at: string;
  server_updated_at: string;
  provenance: WeightReceipt['record']['provenance'];
};

export type StoredReceipt = {
  operation_id: string;
  request_hash: string;
  receipt: WeightReceipt;
};

export type CreateWeightCommand = {
  operation_id: string;
  record_id: string;
  request_hash: string;
  weight_kg: string;
  input_value: string;
  input_unit: WeightUnit;
  measured_at: string;
  utc_offset_minutes: number;
  local_date: string;
  iana_zone: string;
  provenance: WeightReceipt['record']['provenance'];
};

export type CorrectWeightCommand = CreateWeightCommand & { expected_revision: number };
export type DeleteWeightCommand = {
  operation_id: string;
  record_id: string;
  request_hash: string;
  expected_revision: number;
};

export type ListWeightQuery = {
  limit: number;
  cursor: { measured_at: string; id: string } | null;
  record_id: string | null;
};

export type ListWeightResult =
  | {
      ok: true;
      records: StoredWeightEntry[];
      next_cursor: string | null;
    }
  | WeightFailure;

export interface WeightLifecyclePort {
  grant(subject: string): Promise<MetricsGrant | null>;
  create(
    subject: string,
    ownerId: string,
    command: CreateWeightCommand,
    now: Date,
  ): Promise<WeightActionResult>;
  correct(
    subject: string,
    ownerId: string,
    command: CorrectWeightCommand,
    now: Date,
  ): Promise<WeightActionResult>;
  remove(
    subject: string,
    ownerId: string,
    command: DeleteWeightCommand,
    now: Date,
  ): Promise<WeightActionResult>;
  list(subject: string, query: ListWeightQuery): Promise<ListWeightResult>;
}

const weightInputSchema = z
  .object({
    value: z.number(),
    unit: z.enum(['kg', 'lb']),
  })
  .strict();

const measurementSchema = z
  .object({
    measured_at: z.string(),
    utc_offset_minutes: z.number().int(),
    local_date: z.string(),
    iana_zone: z.string(),
  })
  .strict();

const identitySchema = z
  .object({
    operation_id: z.string(),
    record_id: z.string(),
    subject: z.string().optional(),
    user_id: z.string().optional(),
  })
  .strict();

export const createWeightBodySchema = identitySchema
  .merge(weightInputSchema)
  .merge(measurementSchema)
  .strict();
export const correctWeightBodySchema = createWeightBodySchema.extend({
  expected_revision: z.number().int(),
});
export const deleteWeightBodySchema = identitySchema.extend({
  expected_revision: z.number().int(),
});
export const listWeightQuerySchema = z
  .object({
    cursor: z.string().optional(),
    limit: z.number().int().optional(),
    record_id: z.string().optional(),
    subject: z.string().optional(),
    user_id: z.string().optional(),
  })
  .strict();

export function admissionFailure(
  gateEnabled: boolean,
  grant: MetricsGrant | null,
): WeightFailure | null {
  if (!gateEnabled) return { ok: false, code: 'gate_off' };
  if (!grant || !grant.connected) return { ok: false, code: 'unconnected' };
  if (grant.revoked) return { ok: false, code: 'revoked' };
  if (grant.accountDeleted) return { ok: false, code: 'account_deleted' };
  if (!grant.ownerId) return { ok: false, code: 'account_not_found' };
  if (!grant.consentGranted) return { ok: false, code: 'consent_required' };
  if (!grant.entitled) return { ok: false, code: 'ineligible' };
  return null;
}

export function weightMilli(value: number): bigint | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  const milli = Math.round(value * 1000);
  if (!Number.isSafeInteger(milli)) return null;
  if (Math.abs(milli / 1000 - value) > 1e-9) return null;
  return BigInt(milli);
}

export function formatMilli(milli: bigint): string {
  const negative = milli < ZERO;
  const abs = negative ? -milli : milli;
  const whole = abs / THOUSAND;
  const frac = (abs % THOUSAND).toString().padStart(3, '0').replace(/0+$/, '');
  const text = frac ? `${whole.toString()}.${frac}` : whole.toString();
  return negative ? `-${text}` : text;
}

export function formatMicro(micro: bigint): string {
  const negative = micro < ZERO;
  const abs = negative ? -micro : micro;
  const whole = abs / MILLION;
  const frac = (abs % MILLION).toString().padStart(6, '0');
  return `${negative ? '-' : ''}${whole.toString()}.${frac}`;
}

export function canonicalKgMicro(milli: bigint, unit: WeightUnit): bigint {
  if (unit === 'kg') return milli * THOUSAND;
  const numerator = milli * POUND_MICRO_KG;
  const denominator = HUNDRED_THOUSAND;
  const negative = numerator < ZERO;
  const abs = negative ? -numerator : numerator;
  const quotient = abs / denominator;
  const remainder = abs % denominator;
  const rounded = remainder * TWO >= denominator ? quotient + BigInt(1) : quotient;
  return negative ? -rounded : rounded;
}

export function resolveWeight(
  value: number,
  unit: WeightUnit,
):
  | {
      ok: true;
      milli: bigint;
      input: string;
      weight_kg: string;
      provenance: WeightReceipt['record']['provenance'];
    }
  | WeightFailure {
  const milli = weightMilli(value);
  if (milli === null) return { ok: false, code: 'invalid_input', reason: 'ambiguous_weight' };
  const min = unit === 'kg' ? KG_MIN_MILLI : LB_MIN_MILLI;
  const max = unit === 'kg' ? KG_MAX_MILLI : LB_MAX_MILLI;
  if (milli < min || milli > max)
    return { ok: false, code: 'invalid_input', reason: 'out_of_range' };
  const weightKg = formatMicro(canonicalKgMicro(milli, unit));
  return {
    ok: true,
    milli,
    input: formatMilli(milli),
    weight_kg: weightKg,
    provenance: {
      actor: 'agent',
      conversion: unit === 'lb' ? 'lb*0.45359237' : 'identity',
      constant: POUNDS_TO_KILOGRAMS,
      canonical_kg: weightKg,
    },
  };
}

export function resolveMeasurement(input: {
  measured_at: string;
  utc_offset_minutes: number;
  local_date: string;
  iana_zone: string;
}): { ok: true; measured_at: string } | WeightFailure {
  const match = measuredPattern.exec(input.measured_at);
  if (!match) return { ok: false, code: 'invalid_input', reason: 'ambiguous_timestamp' };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.local_date)) {
    return { ok: false, code: 'invalid_input', reason: 'ambiguous_local_date' };
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const calendar = new Date(Date.UTC(year, month - 1, day));
  if (
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    calendar.getUTCFullYear() !== year ||
    calendar.getUTCMonth() !== month - 1 ||
    calendar.getUTCDate() !== day
  ) {
    return { ok: false, code: 'invalid_input', reason: 'ambiguous_timestamp' };
  }
  const offsetToken = match[8] ?? '';
  const offsetMinutes = offsetToken === 'Z' ? 0 : signedOffset(offsetToken);
  if (offsetMinutes === null || offsetMinutes !== input.utc_offset_minutes) {
    return { ok: false, code: 'invalid_input', reason: 'offset_mismatch' };
  }
  const fraction = match[7] ? `.${match[7].padEnd(3, '0').slice(0, 3)}` : '';
  const measuredAt = `${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}${fraction}${offsetToken}`;
  const instant = Date.parse(measuredAt);
  if (!Number.isFinite(instant)) {
    return { ok: false, code: 'invalid_input', reason: 'ambiguous_timestamp' };
  }
  const zone = zoneParts(new Date(instant), input.iana_zone);
  if (!zone) return { ok: false, code: 'invalid_input', reason: 'invalid_zone' };
  if (zone.offsetMinutes !== input.utc_offset_minutes) {
    return { ok: false, code: 'invalid_input', reason: 'offset_zone_mismatch' };
  }
  if (zone.localDate !== input.local_date) {
    return { ok: false, code: 'invalid_input', reason: 'local_date_mismatch' };
  }
  return { ok: true, measured_at: measuredAt };
}

function signedOffset(token: string): number | null {
  const match = /^([+-])(\d{2}):(\d{2})$/.exec(token);
  if (!match) return null;
  const minutes = Number(match[2]) * 60 + Number(match[3]);
  if (Number(match[3]) > 59 || Number(match[2]) > 23) return null;
  return match[1] === '-' ? -minutes : minutes;
}

function zoneParts(
  instant: Date,
  timeZone: string,
): { offsetMinutes: number; localDate: string } | null {
  const namedUtc = timeZone === 'UTC' || timeZone === 'Etc/UTC' || timeZone === 'GMT';
  if (
    !timeZone ||
    timeZone.length > 80 ||
    (!namedUtc && !/^[A-Za-z]+(?:\/[A-Za-z0-9_+-]+)+$/.test(timeZone))
  ) {
    return null;
  }
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      timeZoneName: 'longOffset',
    }).formatToParts(instant);
    const read = (type: Intl.DateTimeFormatPartTypes) =>
      parts.find((part) => part.type === type)?.value ?? '';
    const name = read('timeZoneName');
    let offsetMinutes = 0;
    if (name !== 'GMT' && name !== 'UTC') {
      const match = /^GMT([+-])(\d{2}):(\d{2})$/.exec(name);
      if (!match) return null;
      offsetMinutes = (match[1] === '-' ? -1 : 1) * (Number(match[2]) * 60 + Number(match[3]));
    }
    return {
      offsetMinutes,
      localDate: `${read('year')}-${read('month')}-${read('day')}`,
    };
  } catch {
    return null;
  }
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map((item) => canonicalJson(item)).join(',')}]`;
  if (value && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>).sort(([a], [b]) =>
      a < b ? -1 : a > b ? 1 : 0,
    );
    return `{${entries
      .map(([key, item]) => `${JSON.stringify(key)}:${canonicalJson(item)}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

export function requestHash(payload: unknown): string {
  return createHash('sha256').update(canonicalJson(payload)).digest('hex');
}

function spoofed(subject: string, claimed: { subject?: string; user_id?: string }): boolean {
  return [claimed.subject, claimed.user_id].some(
    (value) => value !== undefined && value !== subject,
  );
}

function uuid(value: string): boolean {
  return UUID.test(value);
}

type PreparedCreate = { command: CreateWeightCommand } | WeightFailure;

function prepareCreate(
  subject: string,
  body: z.infer<typeof createWeightBodySchema>,
): PreparedCreate {
  if (!uuid(body.operation_id) || !uuid(body.record_id)) {
    return { ok: false, code: 'invalid_input', reason: 'invalid_id' };
  }
  if (spoofed(subject, body)) return { ok: false, code: 'spoofed_subject' };
  const weight = resolveWeight(body.value, body.unit);
  if (!weight.ok) return weight;
  const measured = resolveMeasurement(body);
  if (!measured.ok) return measured;
  const command: CreateWeightCommand = {
    operation_id: body.operation_id.toLowerCase(),
    record_id: body.record_id.toLowerCase(),
    request_hash: '',
    weight_kg: weight.weight_kg,
    input_value: weight.input,
    input_unit: body.unit,
    measured_at: measured.measured_at,
    utc_offset_minutes: body.utc_offset_minutes,
    local_date: body.local_date,
    iana_zone: body.iana_zone,
    provenance: weight.provenance,
  };
  command.request_hash = requestHash({
    action: 'create',
    record_id: command.record_id,
    weight_kg: command.weight_kg,
    input_value: command.input_value,
    input_unit: command.input_unit,
    measured_at: command.measured_at,
    utc_offset_minutes: command.utc_offset_minutes,
    local_date: command.local_date,
    iana_zone: command.iana_zone,
  });
  return { command };
}

export function receiptFor(
  action: WeightReceipt['action'],
  entry: StoredWeightEntry,
  operationId: string,
): WeightReceipt {
  return {
    operation_id: operationId,
    action,
    record: {
      id: entry.id,
      revision: entry.revision,
      weight_kg: entry.weight_kg,
      input: { value: entry.input_value, unit: entry.input_unit },
      measured_at: entry.measured_at,
      utc_offset_minutes: entry.utc_offset_minutes,
      local_date: entry.local_date,
      iana_zone: entry.iana_zone,
      deleted_at: entry.deleted_at,
      provenance: entry.provenance,
    },
    cloud: { status: 'committed', server_updated_at: entry.server_updated_at },
    device: { healthkit: 'not_claimed' },
  };
}

async function admitted(
  subject: string,
  store: WeightLifecyclePort,
): Promise<{ grant: MetricsGrant & { ownerId: string } } | WeightFailure> {
  const grant = await store.grant(subject);
  const failure = admissionFailure(true, grant);
  if (failure || !grant?.ownerId) return failure ?? { ok: false, code: 'account_not_found' };
  return { grant: { ...grant, ownerId: grant.ownerId } };
}

export async function createWeightEntry(input: {
  gateEnabled: boolean;
  subject: string;
  body: unknown;
  store: WeightLifecyclePort;
  now: Date;
}): Promise<WeightActionResult> {
  if (!input.gateEnabled) return { ok: false, code: 'gate_off' };
  const parsed = createWeightBodySchema.safeParse(input.body);
  if (!parsed.success) return { ok: false, code: 'invalid_input', reason: 'rejected_shape' };
  const prepared = prepareCreate(input.subject, parsed.data);
  if (!('command' in prepared)) return prepared;
  const admission = await admitted(input.subject, input.store);
  if (!('grant' in admission)) return admission;
  return input.store.create(input.subject, admission.grant.ownerId, prepared.command, input.now);
}

export async function correctWeightEntry(input: {
  gateEnabled: boolean;
  subject: string;
  body: unknown;
  store: WeightLifecyclePort;
  now: Date;
}): Promise<WeightActionResult> {
  if (!input.gateEnabled) return { ok: false, code: 'gate_off' };
  const parsed = correctWeightBodySchema.safeParse(input.body);
  if (!parsed.success) return { ok: false, code: 'invalid_input', reason: 'rejected_shape' };
  if (!Number.isInteger(parsed.data.expected_revision) || parsed.data.expected_revision < 1) {
    return { ok: false, code: 'invalid_input', reason: 'expected_revision' };
  }
  const prepared = prepareCreate(input.subject, parsed.data);
  if (!('command' in prepared)) return prepared;
  const admission = await admitted(input.subject, input.store);
  if (!('grant' in admission)) return admission;
  return input.store.correct(
    input.subject,
    admission.grant.ownerId,
    {
      ...prepared.command,
      expected_revision: parsed.data.expected_revision,
      request_hash: requestHash({
        action: 'correct',
        record_id: prepared.command.record_id,
        expected_revision: parsed.data.expected_revision,
        weight_kg: prepared.command.weight_kg,
        input_value: prepared.command.input_value,
        input_unit: prepared.command.input_unit,
        measured_at: prepared.command.measured_at,
        utc_offset_minutes: prepared.command.utc_offset_minutes,
        local_date: prepared.command.local_date,
        iana_zone: prepared.command.iana_zone,
      }),
    },
    input.now,
  );
}

export async function deleteWeightEntry(input: {
  gateEnabled: boolean;
  subject: string;
  body: unknown;
  store: WeightLifecyclePort;
  now: Date;
}): Promise<WeightActionResult> {
  if (!input.gateEnabled) return { ok: false, code: 'gate_off' };
  const parsed = deleteWeightBodySchema.safeParse(input.body);
  if (!parsed.success) return { ok: false, code: 'invalid_input', reason: 'rejected_shape' };
  if (!uuid(parsed.data.operation_id) || !uuid(parsed.data.record_id)) {
    return { ok: false, code: 'invalid_input', reason: 'invalid_id' };
  }
  if (spoofed(input.subject, parsed.data)) return { ok: false, code: 'spoofed_subject' };
  if (!Number.isInteger(parsed.data.expected_revision) || parsed.data.expected_revision < 1) {
    return { ok: false, code: 'invalid_input', reason: 'expected_revision' };
  }
  const command: DeleteWeightCommand = {
    operation_id: parsed.data.operation_id.toLowerCase(),
    record_id: parsed.data.record_id.toLowerCase(),
    expected_revision: parsed.data.expected_revision,
    request_hash: requestHash({
      action: 'delete',
      record_id: parsed.data.record_id.toLowerCase(),
      expected_revision: parsed.data.expected_revision,
    }),
  };
  const admission = await admitted(input.subject, input.store);
  if (!('grant' in admission)) return admission;
  return input.store.remove(input.subject, admission.grant.ownerId, command, input.now);
}

export function encodeWeightCursor(cursor: { measured_at: string; id: string }): string {
  return Buffer.from(JSON.stringify(cursor)).toString('base64url');
}

export function decodeWeightCursor(
  value: string,
): { measured_at: string; id: string } | WeightFailure {
  try {
    const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8')) as {
      measured_at?: unknown;
      id?: unknown;
    };
    if (
      typeof parsed.measured_at !== 'string' ||
      typeof parsed.id !== 'string' ||
      !uuid(parsed.id)
    ) {
      return { ok: false, code: 'invalid_input', reason: 'invalid_cursor' };
    }
    return { measured_at: parsed.measured_at, id: parsed.id.toLowerCase() };
  } catch {
    return { ok: false, code: 'invalid_input', reason: 'invalid_cursor' };
  }
}

export async function listWeightEntries(input: {
  gateEnabled: boolean;
  subject: string;
  query: unknown;
  store: WeightLifecyclePort;
}): Promise<ListWeightResult> {
  if (!input.gateEnabled) return { ok: false, code: 'gate_off' };
  const parsed = listWeightQuerySchema.safeParse(input.query);
  if (!parsed.success) return { ok: false, code: 'invalid_input', reason: 'rejected_shape' };
  if (spoofed(input.subject, parsed.data)) return { ok: false, code: 'spoofed_subject' };
  if (parsed.data.record_id && !uuid(parsed.data.record_id)) {
    return { ok: false, code: 'invalid_input', reason: 'invalid_id' };
  }
  if (
    parsed.data.limit !== undefined &&
    (parsed.data.limit < 1 || parsed.data.limit > WEIGHT_LIST_MAX_LIMIT)
  ) {
    return { ok: false, code: 'invalid_input', reason: 'invalid_limit' };
  }
  const cursor = parsed.data.cursor ? decodeWeightCursor(parsed.data.cursor) : null;
  if (cursor && 'ok' in cursor && cursor.ok === false) return cursor;
  const admission = await admitted(input.subject, input.store);
  if (!('grant' in admission)) return admission;
  const recordId = parsed.data.record_id?.toLowerCase() ?? null;
  const listed = await input.store.list(input.subject, {
    limit: parsed.data.limit ?? WEIGHT_LIST_DEFAULT_LIMIT,
    cursor: cursor && !('ok' in cursor) ? cursor : null,
    record_id: recordId,
  });
  if (listed.ok && recordId && listed.records.length === 0) {
    return { ok: false, code: 'not_found' };
  }
  return listed;
}

export type NativePushExisting = {
  user_subject: string;
  deleted_at: string | null;
  client_updated_at: string;
  weight: number | null;
  weight_unit: string;
  measured_at: string;
  local_date: string;
};

export type NativePushDecision =
  | { kind: 'insert' }
  | { kind: 'accept'; replay: boolean }
  | { kind: 'foreign' }
  | { kind: 'conflict'; code: 'tombstone' | 'stale_write' | 'payload_conflict' };

function sameNativePayload(existing: NativePushExisting, incoming: NativePushExisting): boolean {
  return (
    existing.weight === incoming.weight &&
    existing.weight_unit === incoming.weight_unit &&
    existing.measured_at === incoming.measured_at &&
    existing.local_date === incoming.local_date
  );
}

/** Delayed native pushes must not resurrect a tombstone or overwrite a newer correction.
 * A strictly newer live payload is an offline edit and is kept. A different stale payload
 * is a conflict so the device still has the edit. */
export function decideNativePush(
  existing: NativePushExisting | null,
  incoming: NativePushExisting,
): NativePushDecision {
  if (!existing) return { kind: 'insert' };
  if (existing.user_subject !== incoming.user_subject) return { kind: 'foreign' };
  if (existing.deleted_at) return { kind: 'conflict', code: 'tombstone' };
  const existingTime = Date.parse(existing.client_updated_at);
  const incomingTime = Date.parse(incoming.client_updated_at);
  if (incomingTime > existingTime) return { kind: 'accept', replay: false };
  if (sameNativePayload(existing, incoming)) return { kind: 'accept', replay: true };
  if (incomingTime < existingTime) return { kind: 'conflict', code: 'stale_write' };
  return { kind: 'conflict', code: 'payload_conflict' };
}
