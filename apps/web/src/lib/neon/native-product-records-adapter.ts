import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import type {
  NativeProductRecord,
  NativeProductRecordCollection,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { NATIVE_PRODUCT_RECORD_COLLECTIONS } from '@/lib/ports/native-product-records';

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase(): NeonQueryFunction<false, false> {
  if (sql) return sql;
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for product persistence');
  sql = neon(connectionString);
  return sql;
}

type NativeRecordRow = {
  id: string;
  payload: Record<string, unknown> | string;
  deleted_at: string | Date | null;
  updated_at: string | Date;
};

function iso(value: Date | string): string {
  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function optionalIso(value: Date | string | null): string | null {
  return value ? iso(value) : null;
}

function asPayload(value: NativeRecordRow['payload']): Record<string, unknown> {
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
  return value || {};
}

function mapRecord(subject: string, row: NativeRecordRow): NativeProductRecord {
  const payload = asPayload(row.payload);
  return {
    ...payload,
    id: row.id,
    user_id: subject,
    deleted_at: optionalIso(row.deleted_at),
    server_updated_at: iso(row.updated_at),
  };
}

function recordId(record: Record<string, unknown>): string | null {
  return typeof record.id === 'string' && record.id ? record.id : null;
}

function payloadForInsert(record: Record<string, unknown>): Record<string, unknown> {
  const payload = { ...record };
  delete payload.user_id;
  delete payload.deleted_at;
  delete payload.server_updated_at;
  return payload;
}

export function createNeonNativeProductRecords(
  database: NeonQueryFunction<false, false> = getDatabase(),
): NativeProductRecordsPort {
  return {
    async push(subject, collection, records) {
      const accepted: NativeProductRecord[] = [];
      const rejectedIds: string[] = [];

      for (const record of records) {
        const id = recordId(record);
        if (!id) continue;
        const rows = (await database.query(
          `insert into public.native_records (
             collection, id, user_subject, payload, deleted_at, updated_at
           ) values ($1, $2, $3, $4::jsonb, null, now())
           on conflict (collection, id) do update set
             payload = excluded.payload,
             deleted_at = null,
             updated_at = now()
           where public.native_records.user_subject = excluded.user_subject
           returning id, payload, deleted_at, updated_at`,
          [collection, id, subject, JSON.stringify(payloadForInsert(record))],
        )) as NativeRecordRow[];
        if (rows[0]) accepted.push(mapRecord(subject, rows[0]));
        else rejectedIds.push(id);
      }

      return { records: accepted, rejected_ids: rejectedIds };
    },

    async pull(subject, collection, input) {
      const limit = Math.min(Math.max(input.limit ?? 200, 1), 500);
      const afterId = input.after_id;
      const rows = (await database.query(
        afterId
          ? `select id, payload, deleted_at, updated_at from public.native_records
             where user_subject = $1 and collection = $2
               and (
                 updated_at > $3::timestamptz
                 or (updated_at = $3::timestamptz and id > $4::uuid)
               )
             order by updated_at asc, id asc
             limit $5`
          : `select id, payload, deleted_at, updated_at from public.native_records
             where user_subject = $1 and collection = $2
               and updated_at >= $3::timestamptz
             order by updated_at asc, id asc
             limit $4`,
        afterId
          ? [subject, collection, input.since, afterId, limit]
          : [subject, collection, input.since, limit],
      )) as NativeRecordRow[];
      const records = rows.map((row) => mapRecord(subject, row));
      const last = records.at(-1);
      return {
        records,
        deleted_ids: records.filter((record) => record.deleted_at).map((record) => record.id),
        next_cursor:
          records.length === limit && last
            ? { since: String(last.server_updated_at), after_id: last.id }
            : null,
      };
    },

    async remove(subject, collection, ids) {
      if (ids.length === 0) return { deleted_ids: [] };
      const rows = (await database.query(
        `update public.native_records
         set deleted_at = coalesce(deleted_at, now()),
             updated_at = now()
         where user_subject = $1 and collection = $2 and id = any($3::uuid[])
         returning id`,
        [subject, collection, ids],
      )) as Array<{ id: string }>;
      return { deleted_ids: rows.map((row) => row.id) };
    },

    async endActiveGlp1Medications(subject, endedAt) {
      const rows = (await database.query(
        `update public.native_records
         set payload = payload || jsonb_build_object('ended_at', $2::text),
             updated_at = now()
         where user_subject = $1
           and collection = 'glp1_medications'
           and deleted_at is null
           and (
             payload->>'ended_at' is null
             or payload->>'ended_at' = ''
             or payload->>'ended_at' = 'null'
           )
         returning id`,
        [subject, endedAt],
      )) as Array<{ id: string }>;
      return { updated: rows.length };
    },

    async listAll(subject) {
      const rows = (await database.query(
        `select collection, id, payload, deleted_at, updated_at
         from public.native_records
         where user_subject = $1 and deleted_at is null
         order by collection, updated_at desc, id desc`,
        [subject],
      )) as Array<NativeRecordRow & { collection: NativeProductRecordCollection }>;
      const grouped = Object.fromEntries(
        NATIVE_PRODUCT_RECORD_COLLECTIONS.map((collection) => [
          collection,
          [] as NativeProductRecord[],
        ]),
      ) as Record<NativeProductRecordCollection, NativeProductRecord[]>;
      for (const row of rows) {
        grouped[row.collection].push(mapRecord(subject, row));
      }
      return grouped;
    },

    async deleteAllForSubject(subject) {
      await database.query(`delete from public.native_records where user_subject = $1`, [subject]);
    },
  };
}

export const neonNativeProductRecords: NativeProductRecordsPort = {
  push: (subject, collection, records) =>
    createNeonNativeProductRecords().push(subject, collection, records),
  pull: (subject, collection, input) =>
    createNeonNativeProductRecords().pull(subject, collection, input),
  remove: (subject, collection, ids) =>
    createNeonNativeProductRecords().remove(subject, collection, ids),
  endActiveGlp1Medications: (subject, endedAt) =>
    createNeonNativeProductRecords().endActiveGlp1Medications(subject, endedAt),
  listAll: (subject) => createNeonNativeProductRecords().listAll(subject),
  deleteAllForSubject: (subject) => createNeonNativeProductRecords().deleteAllForSubject(subject),
};
