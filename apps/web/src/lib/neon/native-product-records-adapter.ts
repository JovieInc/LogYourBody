import {
  isValidDailyStepDeletion,
  type DailyStepDeletionInput,
} from '@/lib/ports/daily-step-deletions';
import type { NativeAccountAdmission } from '@/lib/ports/native-account-admission';
import {
  type NativeMutationQuery,
  captureNativeAccountAdmission,
  executeNativeMutationQueries,
} from './native-account-admission';
import { createNeonTrainingMutations } from './training-mutations-adapter';
import 'server-only';

import { hasSafeReportedMeasurements } from '@/lib/ports/reported-measurements';
import { hasSafeDailyStepMeasurement } from '@/lib/ports/daily-metric-steps';

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

function payloadForInsert(
  record: Record<string, unknown>,
  collection?: NativeProductRecordCollection,
): Record<string, unknown> {
  const payload = { ...record };
  delete payload.user_id;
  delete payload.deleted_at;
  delete payload.server_updated_at;
  if (collection === 'daily_metrics') delete payload.steps_deletion;
  return payload;
}

export function createNeonNativeProductRecords(
  database: NeonQueryFunction<false, false> = getDatabase(),
): NativeProductRecordsPort {
  async function remove(
    subject: string,
    collection: NativeProductRecordCollection,
    ids: string[],
    admission?: NativeAccountAdmission,
  ) {
    const [rows] = (await executeNativeMutationQueries(database, admission, [
      database.query(
        `update public.native_records
         set deleted_at = coalesce(deleted_at, now()),
             updated_at = now()
         where user_subject = $1 and collection = $2 and id = any($3::uuid[])
         returning id`,
        [subject, collection, ids],
      ),
    ])) as Array<Array<{ id: string }>>;
    return { deleted_ids: (rows ?? []).map((row) => row.id) };
  }

  async function deleteDailySteps(
    admission: NativeAccountAdmission,
    deletions: DailyStepDeletionInput[],
  ): Promise<{ records: NativeProductRecord[]; rejected_ids: string[] }> {
    if (
      !deletions.length ||
      deletions.length > 100 ||
      !deletions.every(isValidDailyStepDeletion) ||
      new Set(deletions.map((item) => item.record.id.toLowerCase())).size !== deletions.length
    ) {
      throw new TypeError('invalid_steps_deletion');
    }
    const queries: NativeMutationQuery[] = [];
    for (const deletion of deletions) {
      const record = payloadForInsert(deletion.record, 'daily_metrics');
      queries.push(
        database.query(
          `insert into public.native_records (
           collection, id, user_subject, payload, deleted_at, updated_at
         ) values ('daily_metrics', $1::uuid, $2,
           $3::jsonb || jsonb_build_object(
             'steps', null, 'steps_present', false,
             'steps_deletion', jsonb_build_object(
               'schema_version', 1, 'deleted_at', now(),
               'day_start', $4::text, 'day_end', $5::text, 'time_zone', $6::text
             )
           ), null, now()
         )
         on conflict (collection, id) do update set
           payload = public.native_records.payload || jsonb_build_object(
             'steps', null, 'steps_present', false,
             'steps_deletion', case
               when public.native_records.payload#>>'{steps_deletion,schema_version}' = '1'
               then public.native_records.payload->'steps_deletion'
               else excluded.payload->'steps_deletion' end
           ), updated_at = now()
         where public.native_records.user_subject = excluded.user_subject
           and case when pg_input_is_valid(public.native_records.payload->>'date', 'timestamptz')
             then (public.native_records.payload->>'date')::timestamptz >= $4::timestamptz
               and (public.native_records.payload->>'date')::timestamptz < $5::timestamptz
             else false end
           and (
             public.native_records.payload#>>'{steps_deletion,schema_version}' is distinct from '1'
             or (
               case when pg_input_is_valid(public.native_records.payload#>>'{steps_deletion,day_start}', 'timestamptz')
                 and pg_input_is_valid(public.native_records.payload#>>'{steps_deletion,day_end}', 'timestamptz')
               then (public.native_records.payload#>>'{steps_deletion,day_start}')::timestamptz = $4::timestamptz
                 and (public.native_records.payload#>>'{steps_deletion,day_end}')::timestamptz = $5::timestamptz
               else false end
             )
           )
         returning id, payload, deleted_at, updated_at`,
          [
            record.id,
            admission.subject,
            JSON.stringify(record),
            deletion.day_start,
            deletion.day_end,
            deletion.time_zone,
          ],
        ),
      );
      // A later statement sees the marker after the owner guard; a rejected
      // foreign anchor cannot authorize changes to another daily row.
      queries.push(
        database.query(
          `update public.native_records target
         set payload = target.payload || jsonb_build_object(
           'steps', null, 'steps_present', false,
           'steps_deletion', marker.payload->'steps_deletion'
         ), updated_at = now()
         from public.native_records marker
         where marker.collection = 'daily_metrics' and marker.id = $1::uuid
           and marker.user_subject = $2
           and marker.payload#>>'{steps_deletion,schema_version}' = '1'
           and case when pg_input_is_valid(marker.payload#>>'{steps_deletion,day_start}', 'timestamptz')
             and pg_input_is_valid(marker.payload#>>'{steps_deletion,day_end}', 'timestamptz')
           then (marker.payload#>>'{steps_deletion,day_start}')::timestamptz = $3::timestamptz
             and (marker.payload#>>'{steps_deletion,day_end}')::timestamptz = $4::timestamptz
           else false end
           and target.collection = 'daily_metrics' and target.user_subject = $2
           and target.id <> marker.id
           and target.payload#>>'{steps_deletion,schema_version}' is distinct from '1'
           and case when pg_input_is_valid(target.payload->>'date', 'timestamptz')
             then (target.payload->>'date')::timestamptz >= $3::timestamptz
               and (target.payload->>'date')::timestamptz < $4::timestamptz
             else false end
         returning target.id, target.payload, target.deleted_at, target.updated_at`,
          [record.id, admission.subject, deletion.day_start, deletion.day_end],
        ),
      );
    }
    // Account admission locks app_users FOR UPDATE before these statements.
    // Admitted daily POST uses the same lock, including different record IDs.
    const results = await executeNativeMutationQueries(database, admission, queries);
    const accepted = new Map<string, NativeProductRecord>();
    const rejected: string[] = [];
    for (const [index, deletion] of deletions.entries()) {
      const anchor = results[index * 2] as NativeRecordRow[];
      if (!anchor.length) rejected.push(deletion.record.id);
      for (const row of [...anchor, ...(results[index * 2 + 1] as NativeRecordRow[])]) {
        accepted.set(row.id, mapRecord(admission.subject, row));
      }
    }
    return { records: [...accepted.values()], rejected_ids: rejected };
  }

  async function endActiveGlp1Medications(
    subject: string,
    endedAt: string,
    admission?: NativeAccountAdmission,
  ) {
    const [rows] = (await executeNativeMutationQueries(database, admission, [
      database.query(
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
      ),
    ])) as Array<Array<{ id: string }>>;
    return { updated: (rows ?? []).length };
  }

  async function push(
    subject: string,
    collection: NativeProductRecordCollection,
    records: Array<Record<string, unknown>>,
    admission?: NativeAccountAdmission,
  ) {
    const accepted: NativeProductRecord[] = [];
    const rejectedIds: string[] = [];
    const queries: NativeMutationQuery[] = [];
    const submittedIds: string[] = [];

    for (const record of records) {
      const id = recordId(record);
      if (!id) continue;
      if (collection === 'daily_metrics' && !hasSafeDailyStepMeasurement(record)) {
        rejectedIds.push(id);
        continue;
      }
      if (collection === 'dexa_results' && !hasSafeReportedMeasurements(record)) {
        rejectedIds.push(id);
        continue;
      }
      queries.push(
        database.query(
          `insert into public.native_records (
             collection, id, user_subject, payload, deleted_at, updated_at
           ) values ($1, $2, $3,
              $4::jsonb || coalesce((
                select jsonb_build_object('steps', null, 'steps_present', false,
                  'steps_deletion', marker.payload->'steps_deletion')
                from public.native_records marker
                where $1 = 'daily_metrics' and marker.collection = 'daily_metrics'
                  and marker.user_subject = $3
                  and jsonb_typeof(marker.payload->'steps_deletion') = 'object'
                  and marker.payload#>>'{steps_deletion,schema_version}' = '1'
                  and (marker.id = $2::uuid or case
                    when pg_input_is_valid($4::jsonb->>'date', 'timestamptz')
                      and pg_input_is_valid(marker.payload#>>'{steps_deletion,day_start}', 'timestamptz')
                      and pg_input_is_valid(marker.payload#>>'{steps_deletion,day_end}', 'timestamptz')
                    then ($4::jsonb->>'date')::timestamptz
                      >= (marker.payload#>>'{steps_deletion,day_start}')::timestamptz
                      and ($4::jsonb->>'date')::timestamptz
                      < (marker.payload#>>'{steps_deletion,day_end}')::timestamptz
                    else false end)
                order by marker.updated_at desc, marker.id limit 1
              ), '{}'::jsonb), null, now())
           on conflict (collection, id) do update set
             payload = case
               when excluded.collection = 'daily_metrics'
                 and (
                   public.native_records.payload#>>'{steps_deletion,schema_version}' = '1'
                   or excluded.payload#>>'{steps_deletion,schema_version}' = '1'
                 )
               then public.native_records.payload || excluded.payload || jsonb_build_object(
                 'steps', null, 'steps_present', false,
                 'steps_deletion', case
                   when public.native_records.payload#>>'{steps_deletion,schema_version}' = '1'
                   then public.native_records.payload->'steps_deletion'
                   else excluded.payload->'steps_deletion' end,
                 'date', case
                   when public.native_records.payload#>>'{steps_deletion,schema_version}' = '1'
                   then public.native_records.payload->'date'
                   else excluded.payload->'date' end
               )
               when excluded.collection = 'daily_metrics'
                 and not (excluded.payload ? 'steps_present')
                 and public.native_records.payload->'steps_present' = 'true'::jsonb
                 and jsonb_typeof(excluded.payload->'steps') = 'number'
                 and public.native_records.payload->'steps' = excluded.payload->'steps'
                 and jsonb_typeof(excluded.payload->'date') = 'string'
                 and public.native_records.payload->'date' = excluded.payload->'date'
               then excluded.payload || jsonb_build_object('steps_present', true)
               when excluded.collection = 'dexa_results'
                 and not (excluded.payload ? 'reported_measurements')
                 and public.native_records.payload ? 'reported_measurements'
               then excluded.payload || jsonb_build_object(
                 'reported_measurements', public.native_records.payload->'reported_measurements'
               )
               else excluded.payload
             end,
             deleted_at = null,
             updated_at = now()
           where public.native_records.user_subject = excluded.user_subject
           returning id, payload, deleted_at, updated_at`,
          [collection, id, subject, JSON.stringify(payloadForInsert(record, collection))],
        ),
      );
      submittedIds.push(id);
    }
    const results = await executeNativeMutationQueries(database, admission, queries);
    for (const [index, result] of results.entries()) {
      const rows = result as NativeRecordRow[];
      if (rows[0]) accepted.push(mapRecord(subject, rows[0]));
      else rejectedIds.push(submittedIds[index]!);
    }

    return { records: accepted, rejected_ids: rejectedIds };
  }

  return {
    accountMutations: {
      capture: (subject) => captureNativeAccountAdmission(database, subject),
      deleteDailySteps,
      push: (admission, collection, records) =>
        push(admission.subject, collection, records, admission),
      remove: (admission, collection, ids) => remove(admission.subject, collection, ids, admission),
      endActiveGlp1Medications: (admission, endedAt) =>
        endActiveGlp1Medications(admission.subject, endedAt, admission),
    },
    trainingMutations: createNeonTrainingMutations(database),
    async insertTrainingSet(subject, record) {
      const id = recordId(record);
      if (!id) return null;
      const inserted = (await database.query(
        `insert into public.native_records (
           collection, id, user_subject, payload, deleted_at, updated_at
         ) values ('logged_sets', $1, $2, $3::jsonb, null, now())
         on conflict (collection, id) do nothing
         returning id, payload, deleted_at, updated_at`,
        [id, subject, JSON.stringify(payloadForInsert(record))],
      )) as NativeRecordRow[];
      if (inserted[0]) return mapRecord(subject, inserted[0]);

      // A conflicting insert waits for the winner. Read it in a fresh statement
      // so its committed row is visible; never update or revive an existing set.
      const existing = (await database.query(
        `select id, payload, deleted_at, updated_at from public.native_records
         where collection = 'logged_sets' and id = $1
           and user_subject = $2 and deleted_at is null`,
        [id, subject],
      )) as NativeRecordRow[];
      return existing[0] ? mapRecord(subject, existing[0]) : null;
    },

    async correctTrainingSet(subject, id, expectedRevision, record) {
      const mutations = createNeonTrainingMutations(database);
      const admission = await mutations.captureAdmission(subject);
      if (!admission) return null;
      const result = await mutations.commit({
        subject,
        admission,
        action: 'set_correct',
        record: { ...record, id, expectedRevision },
      });
      return result.kind === 'saved' ? result.record : null;
    },

    async updateTrainingSession(subject, id, expectedRevision, expectedLoggedSetCount, record) {
      const mutations = createNeonTrainingMutations(database);
      const admission = await mutations.captureAdmission(subject);
      if (!admission) return null;
      const result = await mutations.commit({
        subject,
        admission,
        action: 'session_update',
        record: { ...record, expectedExecutionRevision: expectedRevision, expectedLoggedSetCount },
      });
      return result.kind === 'saved' ? result.record : null;
    },

    push,

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

    remove,

    endActiveGlp1Medications,

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
  accountMutations: {
    capture: (subject) => captureNativeAccountAdmission(getDatabase(), subject),
    deleteDailySteps: (admission, deletions) =>
      createNeonNativeProductRecords().accountMutations!.deleteDailySteps!(admission, deletions),
    push: (admission, collection, records) =>
      createNeonNativeProductRecords().accountMutations!.push(admission, collection, records),
    remove: (admission, collection, ids) =>
      createNeonNativeProductRecords().accountMutations!.remove(admission, collection, ids),
    endActiveGlp1Medications: (admission, endedAt) =>
      createNeonNativeProductRecords().accountMutations!.endActiveGlp1Medications(
        admission,
        endedAt,
      ),
  },
  trainingMutations: {
    commitRecoveryTrial: (input) =>
      createNeonTrainingMutations(getDatabase()).commitRecoveryTrial!(input),
    captureAdmission: (subject) =>
      createNeonTrainingMutations(getDatabase()).captureAdmission(subject),
    commit: (input) => createNeonTrainingMutations(getDatabase()).commit(input),
  },
  insertTrainingSet: (subject, record) =>
    createNeonNativeProductRecords().insertTrainingSet!(subject, record),
  correctTrainingSet: (subject, id, expectedRevision, record) =>
    createNeonNativeProductRecords().correctTrainingSet!(subject, id, expectedRevision, record),
  updateTrainingSession: (subject, id, expectedRevision, expectedLoggedSetCount, record) =>
    createNeonNativeProductRecords().updateTrainingSession!(
      subject,
      id,
      expectedRevision,
      expectedLoggedSetCount,
      record,
    ),
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
