import type { NativeAccountAdmission } from '@/lib/ports/native-account-admission';
import {
  type NativeMutationQuery,
  captureNativeAccountAdmission,
  executeNativeMutationQueries,
} from './native-account-admission';
import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import type {
  NativeBodyMetricConflict,
  NativeBodyMetricPushInput,
  NativeBodyMetricSyncRecord,
  NativeBodyMetricsSyncPort,
} from '@/lib/ports/native-body-metrics-sync';

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase(): NeonQueryFunction<false, false> {
  if (sql) return sql;
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for product persistence');
  sql = neon(connectionString);
  return sql;
}

const columns = `
  id, date, local_date, measured_at, weight, weight_unit, waist, hip, waist_unit,
  body_fat_percentage, body_fat_method, muscle_mass, bone_mass, photo_url, notes,
  data_source, source_metadata, client_created_at, client_updated_at, deleted_at,
  updated_at
`;

type NativeBodyMetricRow = {
  id: string;
  date: string | Date;
  local_date: string | Date;
  measured_at: string | Date;
  weight: number | string | null;
  weight_unit: 'kg' | 'lbs';
  waist: number | string | null;
  hip: number | string | null;
  waist_unit: 'cm' | 'in';
  body_fat_percentage: number | string | null;
  body_fat_method: string | null;
  muscle_mass: number | string | null;
  bone_mass: number | string | null;
  photo_url: string | null;
  notes: string | null;
  data_source: string;
  source_metadata: Record<string, unknown> | string | null;
  client_created_at: string | Date;
  client_updated_at: string | Date;
  deleted_at: string | Date | null;
  updated_at: string | Date;
};

function iso(value: Date | string): string {
  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function optionalIso(value: Date | string | null): string | null {
  return value ? iso(value) : null;
}

function localDate(value: Date | string): string {
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}/.test(value)) {
    return value.slice(0, 10);
  }
  return iso(value).slice(0, 10);
}

function asNumber(value: number | string | null): number | null {
  if (value == null || value === '') return null;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function asMetadata(value: NativeBodyMetricRow['source_metadata']): Record<string, unknown> {
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

function mapRecord(row: NativeBodyMetricRow): NativeBodyMetricSyncRecord {
  return {
    id: row.id,
    date: iso(row.measured_at),
    local_date: localDate(row.local_date),
    weight: asNumber(row.weight),
    weight_unit: row.weight_unit,
    waist_circumference: asNumber(row.waist),
    hip_circumference: asNumber(row.hip),
    waist_unit: row.waist_unit,
    body_fat_percentage: asNumber(row.body_fat_percentage),
    body_fat_method: row.body_fat_method,
    muscle_mass: asNumber(row.muscle_mass),
    bone_mass: asNumber(row.bone_mass),
    photo_url: row.photo_url,
    notes: row.notes,
    data_source: row.data_source,
    source_metadata: asMetadata(row.source_metadata),
    created_at: iso(row.client_created_at),
    updated_at: iso(row.client_updated_at),
    deleted_at: optionalIso(row.deleted_at),
    server_updated_at: iso(row.updated_at),
  };
}

function pushParams(subject: string, record: NativeBodyMetricPushInput) {
  return [
    record.id,
    subject,
    record.local_date,
    record.date,
    record.weight,
    record.weight_unit,
    record.body_fat_percentage,
    record.body_fat_method,
    record.muscle_mass,
    record.bone_mass,
    record.waist_circumference,
    record.hip_circumference,
    record.waist_unit,
    record.notes,
    record.photo_url,
    record.data_source,
    JSON.stringify(record.source_metadata),
    record.created_at,
    record.updated_at,
  ];
}

export function createNeonNativeBodyMetricsSync(
  database: NeonQueryFunction<false, false> = getDatabase(),
): NativeBodyMetricsSyncPort {
  async function remove(subject: string, ids: string[], admission?: NativeAccountAdmission) {
    const [rows] = (await executeNativeMutationQueries(database, admission, [
      database.query(
        `update public.body_metrics
         set deleted_at = coalesce(deleted_at, now()),
             updated_at = now()
         where user_subject = $1 and id = any($2::uuid[])
         returning id`,
        [subject, ids],
      ),
    ])) as Array<Array<{ id: string }>>;
    return { deleted_ids: (rows ?? []).map((row) => row.id) };
  }

  async function push(
    subject: string,
    records: NativeBodyMetricPushInput[],
    admission?: NativeAccountAdmission,
  ) {
    const accepted: NativeBodyMetricSyncRecord[] = [];
    const rejectedIds: string[] = [];
    const conflicts: NativeBodyMetricConflict[] = [];
    const queries: NativeMutationQuery[] = [];
    const submittedIds: string[] = [];

    for (const record of records) {
      queries.push(
        database.query(
          `with incoming as (
             select
               $1::uuid as id,
               $2::text as user_subject,
               $3::date as local_date,
               $4::timestamptz as measured_at,
               $5::numeric as weight,
               $6::text as weight_unit,
               $7::numeric as body_fat_percentage,
               $8::text as body_fat_method,
               $9::numeric as muscle_mass,
               $10::numeric as bone_mass,
               $11::numeric as waist,
               $12::numeric as hip,
               $13::text as waist_unit,
               $14::text as notes,
               $15::text as photo_url,
               $16::text as data_source,
               $17::jsonb as source_metadata,
               $18::timestamptz as client_created_at,
               $19::timestamptz as client_updated_at
           ),
           current_row as (
             select user_subject, ${columns}
             from public.body_metrics
             where id = (select id from incoming)
           ),
           decision as (
             select case
               when current_row.id is null then 'insert'
               when current_row.user_subject is distinct from incoming.user_subject then 'foreign'
               when current_row.deleted_at is not null then 'tombstone'
               when incoming.client_updated_at > current_row.client_updated_at then 'accept'
               when current_row.weight is not distinct from incoming.weight
                 and current_row.weight_unit is not distinct from incoming.weight_unit
                 and current_row.measured_at is not distinct from incoming.measured_at
                 and current_row.local_date is not distinct from incoming.local_date then 'replay'
               when current_row.client_updated_at > incoming.client_updated_at then 'stale_write'
               else 'payload_conflict'
             end as outcome
             from incoming
             left join current_row on true
           ),
           upserted as (
             insert into public.body_metrics (
               id, user_subject, date, measured_at, local_date, origin,
               weight, weight_unit, body_fat_percentage, body_fat_method,
               muscle_mass, bone_mass, waist, hip, waist_unit, notes, photo_url,
               data_source, source_metadata, client_created_at, client_updated_at,
               deleted_at
             )
             select
               incoming.id, incoming.user_subject, incoming.local_date, incoming.measured_at,
               incoming.local_date, 'native',
               incoming.weight, incoming.weight_unit, incoming.body_fat_percentage, incoming.body_fat_method,
               incoming.muscle_mass, incoming.bone_mass, incoming.waist, incoming.hip, incoming.waist_unit,
               incoming.notes, incoming.photo_url, incoming.data_source, incoming.source_metadata,
               incoming.client_created_at, incoming.client_updated_at, null
             from incoming
             where (select outcome from decision) in ('insert', 'accept', 'replay')
             on conflict (id) do update set
               date = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.date else public.body_metrics.date end,
               measured_at = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.measured_at else public.body_metrics.measured_at end,
               local_date = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.local_date else public.body_metrics.local_date end,
               origin = case when excluded.client_updated_at > public.body_metrics.client_updated_at then 'native' else public.body_metrics.origin end,
               weight = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.weight else public.body_metrics.weight end,
               weight_unit = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.weight_unit else public.body_metrics.weight_unit end,
               body_fat_percentage = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.body_fat_percentage else public.body_metrics.body_fat_percentage end,
               body_fat_method = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.body_fat_method else public.body_metrics.body_fat_method end,
               muscle_mass = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.muscle_mass else public.body_metrics.muscle_mass end,
               bone_mass = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.bone_mass else public.body_metrics.bone_mass end,
               waist = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.waist else public.body_metrics.waist end,
               hip = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.hip else public.body_metrics.hip end,
               waist_unit = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.waist_unit else public.body_metrics.waist_unit end,
               notes = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.notes else public.body_metrics.notes end,
               photo_url = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.photo_url else public.body_metrics.photo_url end,
               data_source = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.data_source else public.body_metrics.data_source end,
               source_metadata = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.source_metadata else public.body_metrics.source_metadata end,
               client_updated_at = case when excluded.client_updated_at > public.body_metrics.client_updated_at then excluded.client_updated_at else public.body_metrics.client_updated_at end,
               updated_at = case when excluded.client_updated_at > public.body_metrics.client_updated_at then now() else public.body_metrics.updated_at end,
               revision = case
                 when excluded.client_updated_at > public.body_metrics.client_updated_at
                   and (
                     public.body_metrics.weight is distinct from excluded.weight
                     or public.body_metrics.weight_unit is distinct from excluded.weight_unit
                     or public.body_metrics.measured_at is distinct from excluded.measured_at
                     or public.body_metrics.local_date is distinct from excluded.local_date
                   )
                 then public.body_metrics.revision + 1
                 else public.body_metrics.revision
               end
             where public.body_metrics.user_subject = excluded.user_subject
               and public.body_metrics.deleted_at is null
               and (
                 excluded.client_updated_at > public.body_metrics.client_updated_at
                 or (
                   public.body_metrics.weight is not distinct from excluded.weight
                   and public.body_metrics.weight_unit is not distinct from excluded.weight_unit
                   and public.body_metrics.measured_at is not distinct from excluded.measured_at
                   and public.body_metrics.local_date is not distinct from excluded.local_date
                 )
               )
             returning ${columns}
           )
           select upserted.*, (select outcome from decision) as push_outcome
           from upserted
           union all
           select ${columns}, (select outcome from decision) as push_outcome
           from current_row
           where (select outcome from decision) in ('tombstone', 'stale_write', 'payload_conflict')
             and not exists (select 1 from upserted)`,
          pushParams(subject, record),
        ),
      );
      submittedIds.push(record.id);
    }
    const results = await executeNativeMutationQueries(database, admission, queries);
    for (const [index, result] of results.entries()) {
      const rows = result as Array<NativeBodyMetricRow & { push_outcome?: string }>;
      const row = rows[0];
      const id = submittedIds[index]!;
      if (!row) {
        rejectedIds.push(id);
        continue;
      }
      const outcome = row.push_outcome ?? 'accept';
      if (outcome === 'insert' || outcome === 'accept' || outcome === 'replay') {
        accepted.push(mapRecord(row));
      } else if (
        outcome === 'tombstone' ||
        outcome === 'stale_write' ||
        outcome === 'payload_conflict'
      ) {
        conflicts.push({ id: row.id, code: outcome, record: mapRecord(row) });
      } else {
        rejectedIds.push(id);
      }
    }

    return { records: accepted, rejected_ids: rejectedIds, conflicts };
  }

  return {
    accountMutations: {
      capture: (subject) => captureNativeAccountAdmission(database, subject),
      push: (admission, records) => push(admission.subject, records, admission),
      remove: (admission, ids) => remove(admission.subject, ids, admission),
    },
    push,

    async pull(subject, input) {
      const limit = Math.min(Math.max(input.limit ?? 200, 1), 500);
      const afterId = input.after_id;
      const rows = (await database.query(
        afterId
          ? `select ${columns} from public.body_metrics
             where user_subject = $1
               and (
                 updated_at > $2::timestamptz
                 or (updated_at = $2::timestamptz and id > $3::uuid)
               )
             order by updated_at asc, id asc
             limit $4`
          : `select ${columns} from public.body_metrics
             where user_subject = $1
               and updated_at >= $2::timestamptz
             order by updated_at asc, id asc
             limit $3`,
        afterId ? [subject, input.since, afterId, limit] : [subject, input.since, limit],
      )) as NativeBodyMetricRow[];

      const records = rows.map(mapRecord);
      const last = records.at(-1);
      return {
        records,
        deleted_ids: records.filter((record) => record.deleted_at).map((record) => record.id),
        next_cursor:
          records.length === limit && last
            ? { since: last.server_updated_at, after_id: last.id }
            : null,
      };
    },

    remove,
  };
}

export const neonNativeBodyMetricsSync: NativeBodyMetricsSyncPort = {
  accountMutations: {
    capture: (subject) => captureNativeAccountAdmission(getDatabase(), subject),
    push: (admission, records) =>
      createNeonNativeBodyMetricsSync().accountMutations!.push(admission, records),
    remove: (admission, ids) =>
      createNeonNativeBodyMetricsSync().accountMutations!.remove(admission, ids),
  },
  push: (subject, records) => createNeonNativeBodyMetricsSync().push(subject, records),
  pull: (subject, input) => createNeonNativeBodyMetricsSync().pull(subject, input),
  remove: (subject, ids) => createNeonNativeBodyMetricsSync().remove(subject, ids),
};
