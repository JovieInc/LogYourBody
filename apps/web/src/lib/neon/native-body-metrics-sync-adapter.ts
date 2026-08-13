import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import type {
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
  return {
    async push(subject, records) {
      const accepted: NativeBodyMetricSyncRecord[] = [];
      const rejectedIds: string[] = [];

      for (const record of records) {
        const rows = (await database.query(
          `insert into public.body_metrics (
             id, user_subject, date, measured_at, local_date, origin,
             weight, weight_unit, body_fat_percentage, body_fat_method,
             muscle_mass, bone_mass, waist, hip, waist_unit, notes, photo_url,
             data_source, source_metadata, client_created_at, client_updated_at,
             deleted_at
           ) values (
             $1, $2, $3::date, $4::timestamptz, $3::date, 'native',
             $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
             $16, $17::jsonb, $18::timestamptz, $19::timestamptz, null
           )
           on conflict (id) do update set
             date = excluded.date,
             measured_at = excluded.measured_at,
             local_date = excluded.local_date,
             origin = 'native',
             weight = excluded.weight,
             weight_unit = excluded.weight_unit,
             body_fat_percentage = excluded.body_fat_percentage,
             body_fat_method = excluded.body_fat_method,
             muscle_mass = excluded.muscle_mass,
             bone_mass = excluded.bone_mass,
             waist = excluded.waist,
             hip = excluded.hip,
             waist_unit = excluded.waist_unit,
             notes = excluded.notes,
             photo_url = excluded.photo_url,
             data_source = excluded.data_source,
             source_metadata = excluded.source_metadata,
             client_updated_at = excluded.client_updated_at,
             deleted_at = null,
             updated_at = now()
           where public.body_metrics.user_subject = excluded.user_subject
           returning ${columns}`,
          pushParams(subject, record),
        )) as NativeBodyMetricRow[];

        if (rows[0]) accepted.push(mapRecord(rows[0]));
        else rejectedIds.push(record.id);
      }

      return { records: accepted, rejected_ids: rejectedIds };
    },

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

    async remove(subject, ids) {
      if (ids.length === 0) return { deleted_ids: [] };
      const rows = (await database.query(
        `update public.body_metrics
         set deleted_at = coalesce(deleted_at, now()),
             updated_at = now()
         where user_subject = $1 and id = any($2::uuid[])
         returning id`,
        [subject, ids],
      )) as Array<{ id: string }>;
      return { deleted_ids: rows.map((row) => row.id) };
    },
  };
}

export const neonNativeBodyMetricsSync: NativeBodyMetricsSyncPort = {
  push: (subject, records) => createNeonNativeBodyMetricsSync().push(subject, records),
  pull: (subject, input) => createNeonNativeBodyMetricsSync().pull(subject, input),
  remove: (subject, ids) => createNeonNativeBodyMetricsSync().remove(subject, ids),
};
