import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { NativeAccountAdmissionError } from '@/lib/ports/native-account-admission';
import {
  admissionFailure,
  encodeWeightCursor,
  type CreateWeightCommand,
  type DeleteWeightCommand,
  type ListWeightQuery,
  type ListWeightResult,
  type MetricsGrant,
  type StoredWeightEntry,
  type WeightActionResult,
  type WeightFailureCode,
  type WeightLifecyclePort,
  type WeightReceipt,
} from '@/lib/metrics/weight-lifecycle';
import { executeNativeMutationQueries } from './native-account-admission';

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase(): NeonQueryFunction<false, false> {
  if (sql) return sql;
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for product persistence');
  sql = neon(connectionString);
  return sql;
}

const FAILURES = new Set<WeightFailureCode>([
  'invalid_input',
  'spoofed_subject',
  'gate_off',
  'revoked',
  'account_deleted',
  'account_not_found',
  'unconnected',
  'consent_required',
  'ineligible',
  'not_found',
  'idempotency_conflict',
  'stale_revision',
  'already_deleted',
  'record_conflict',
]);

type GrantRow = {
  owner_id: string | null;
  grant_subject: string | null;
  connected: boolean | null;
  consent_granted: boolean | null;
  entitled: boolean | null;
  revoked_at: string | Date | null;
  deleted_at: string | Date | null;
};

type ListedRow = {
  id: string;
  revision: number | string;
  weight: number | string | null;
  measured_at: string | Date;
  local_date: string | Date;
  deleted_at: string | Date | null;
  client_updated_at: string | Date;
  updated_at: string | Date;
  source_metadata: Record<string, unknown> | string | null;
  origin: string;
};

function missingAccount(subject: string): MetricsGrant {
  return {
    subject,
    ownerId: null,
    connected: true,
    consentGranted: true,
    entitled: true,
    revoked: false,
    accountDeleted: false,
  };
}

function asObject(value: ListedRow['source_metadata']): Record<string, unknown> {
  if (!value) return {};
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value) as unknown;
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
        ? (parsed as Record<string, unknown>)
        : {};
    } catch {
      return {};
    }
  }
  return value;
}

function iso(value: Date | string): string {
  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function text(value: unknown, fallback: string): string {
  return typeof value === 'string' && value ? value : fallback;
}

function mapEntry(subject: string, row: ListedRow): StoredWeightEntry {
  const metadata = asObject(row.source_metadata);
  const provenance = metadata.provenance;
  const weight =
    typeof metadata.weight_kg === 'string'
      ? metadata.weight_kg
      : row.weight == null
        ? '0.000000'
        : Number(row.weight).toFixed(6);
  const actor = row.origin === 'agent' ? 'agent' : 'device';
  return {
    id: row.id,
    subject,
    revision: Number(row.revision),
    weight_kg: weight,
    input_value: text(metadata.input_value, weight),
    input_unit: metadata.input_unit === 'lb' ? 'lb' : 'kg',
    measured_at: text(metadata.measured_at, iso(row.measured_at)),
    utc_offset_minutes:
      typeof metadata.utc_offset_minutes === 'number' ? metadata.utc_offset_minutes : 0,
    local_date: text(metadata.local_date, String(row.local_date).slice(0, 10)),
    iana_zone: text(metadata.iana_zone, 'UTC'),
    deleted_at: row.deleted_at ? iso(row.deleted_at) : null,
    client_updated_at: iso(row.client_updated_at),
    server_updated_at: iso(row.updated_at),
    provenance:
      provenance && typeof provenance === 'object' && !Array.isArray(provenance)
        ? (provenance as StoredWeightEntry['provenance'])
        : {
            actor,
            conversion: 'identity',
            constant: '0.45359237',
            canonical_kg: weight,
          },
  };
}

function receiptFrom(value: unknown): WeightReceipt | null {
  if (!value || typeof value !== 'object') return null;
  const receipt = value as WeightReceipt;
  if (receipt.device?.healthkit !== 'not_claimed') return null;
  if (receipt.cloud?.status !== 'committed') return null;
  if (!receipt.operation_id || !receipt.record?.id) return null;
  return receipt;
}

function payload(
  action: 'create' | 'correct' | 'delete',
  command: CreateWeightCommand | DeleteWeightCommand,
  now: Date,
) {
  const base = {
    action,
    operation_id: command.operation_id,
    record_id: command.record_id,
    request_hash: command.request_hash,
    now: now.toISOString(),
  };
  if (!('weight_kg' in command)) {
    return { ...base, expected_revision: command.expected_revision };
  }
  return {
    ...base,
    weight_kg: command.weight_kg,
    input_value: command.input_value,
    input_unit: command.input_unit,
    measured_at: command.measured_at,
    utc_offset_minutes: command.utc_offset_minutes,
    local_date: command.local_date,
    iana_zone: command.iana_zone,
    provenance: command.provenance,
    ...('expected_revision' in command ? { expected_revision: command.expected_revision } : {}),
  };
}

export function createNeonWeightLifecycle(
  database: NeonQueryFunction<false, false> = getDatabase(),
): WeightLifecyclePort {
  async function loadGrant(subject: string): Promise<MetricsGrant | null> {
    const rows = (await database.query(
      `select u.id as owner_id,
              g.user_subject as grant_subject,
              g.connected,
              g.consent_granted,
              g.entitled,
              g.revoked_at,
              g.deleted_at
       from public.app_users u
       left join public.metrics_agent_grants g on g.user_subject = u.identity_subject
       where u.identity_provider = 'jovie' and u.identity_subject = $1`,
      [subject],
    )) as GrantRow[];
    const row = rows[0];
    if (!row) return missingAccount(subject);
    if (!row.grant_subject) {
      return {
        subject,
        ownerId: row.owner_id,
        connected: false,
        consentGranted: false,
        entitled: false,
        revoked: false,
        accountDeleted: false,
      };
    }
    return {
      subject,
      ownerId: row.owner_id,
      connected: row.connected === true,
      consentGranted: row.consent_granted === true,
      entitled: row.entitled === true,
      revoked: row.revoked_at != null,
      accountDeleted: row.deleted_at != null,
    };
  }

  async function mutate(
    subject: string,
    ownerId: string,
    action: 'create' | 'correct' | 'delete',
    command: CreateWeightCommand | DeleteWeightCommand,
    now: Date,
  ): Promise<WeightActionResult> {
    try {
      const [rows] = (await executeNativeMutationQueries(database, { subject, ownerId }, [
        database.query(
          'select public.weight_lifecycle_command($1, $2::uuid, $3::jsonb) as result',
          [subject, ownerId, JSON.stringify(payload(action, command, now))],
        ),
      ])) as Array<Array<{ result: unknown }>>;
      const raw = rows?.[0]?.result;
      const result =
        typeof raw === 'string'
          ? (JSON.parse(raw) as { outcome?: string; receipt?: unknown; reason?: string })
          : (raw as { outcome?: string; receipt?: unknown; reason?: string } | undefined);
      const outcome = result?.outcome;
      if (outcome === 'committed' || outcome === 'replayed') {
        const receipt = receiptFrom(result?.receipt);
        if (!receipt) return { ok: false, code: 'invalid_input', reason: 'healthkit_not_claimed' };
        return { ok: true, replayed: outcome === 'replayed', receipt };
      }
      if (outcome && FAILURES.has(outcome as WeightFailureCode)) {
        return {
          ok: false,
          code: outcome as WeightFailureCode,
          ...(result?.reason ? { reason: result.reason } : {}),
        };
      }
      return { ok: false, code: 'invalid_input', reason: 'rejected_shape' };
    } catch (error) {
      if (error instanceof NativeAccountAdmissionError) {
        return { ok: false, code: 'account_not_found' };
      }
      throw error;
    }
  }

  return {
    grant: loadGrant,
    create: (subject, ownerId, command, now) => mutate(subject, ownerId, 'create', command, now),
    correct: (subject, ownerId, command, now) => mutate(subject, ownerId, 'correct', command, now),
    remove: (subject, ownerId, command, now) => mutate(subject, ownerId, 'delete', command, now),
    async list(subject, query: ListWeightQuery): Promise<ListWeightResult> {
      const grant = await loadGrant(subject);
      const failure = admissionFailure(true, grant);
      if (failure || !grant?.ownerId) return failure ?? { ok: false, code: 'account_not_found' };
      const cursor = query.cursor;
      const params = [
        subject,
        query.record_id,
        cursor?.measured_at ?? null,
        cursor?.id ?? null,
        query.limit + 1,
      ];
      try {
        const [rows] = (await executeNativeMutationQueries(
          database,
          { subject, ownerId: grant.ownerId },
          [
            database.query(
              `select id, revision, weight, measured_at, local_date, deleted_at,
                      client_updated_at, updated_at, source_metadata, origin
               from public.body_metrics
               where user_subject = $1
                 and weight is not null
                 and ($2::uuid is not null or deleted_at is null)
                 and ($2::uuid is null or id = $2::uuid)
                 and (
                   $3::timestamptz is null
                   or measured_at < $3::timestamptz
                   or (measured_at = $3::timestamptz and id < $4::uuid)
                 )
               order by measured_at desc, id desc
               limit $5`,
              params,
            ),
          ],
        )) as Array<ListedRow[]>;
        const page = (rows ?? []).slice(0, query.limit).map((row) => mapEntry(subject, row));
        const last = page.at(-1);
        return {
          ok: true,
          records: page,
          next_cursor:
            (rows ?? []).length > query.limit && last
              ? encodeWeightCursor({ measured_at: last.measured_at, id: last.id })
              : null,
        };
      } catch (error) {
        if (error instanceof NativeAccountAdmissionError) {
          return { ok: false, code: 'account_not_found' };
        }
        throw error;
      }
    },
  };
}

export const neonWeightLifecycle: WeightLifecyclePort = {
  grant: (subject) => createNeonWeightLifecycle().grant(subject),
  create: (subject, ownerId, command, now) =>
    createNeonWeightLifecycle().create(subject, ownerId, command, now),
  correct: (subject, ownerId, command, now) =>
    createNeonWeightLifecycle().correct(subject, ownerId, command, now),
  remove: (subject, ownerId, command, now) =>
    createNeonWeightLifecycle().remove(subject, ownerId, command, now),
  list: (subject, query) => createNeonWeightLifecycle().list(subject, query),
};
