import 'server-only';
import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { datedOutcomePlanInputs, type DatedOutcomePort } from '@/lib/ports/dated-outcome';
import {
  captureNativeAccountAdmission,
  executeNativeMutationQueries,
} from './native-account-admission';

export function createNeonDatedOutcomes(
  database: NeonQueryFunction<false, false>,
): DatedOutcomePort & { exportForSubject(subject: string): Promise<unknown[]> } {
  return {
    capture: (subject) => captureNativeAccountAdmission(database, subject),
    async read(subject) {
      const rows = await database.query(
        `select dated_outcome as value, dated_outcome_revision as revision
         from public.app_users where identity_provider = 'jovie' and identity_subject = $1
         and dated_outcome_revision is not null`,
        [subject],
      );
      return (rows[0] as Awaited<ReturnType<DatedOutcomePort['read']>>) ?? null;
    },
    async save(admission, edit) {
      const [rows] = await executeNativeMutationQueries(database, admission, [
        database.query(
          'select public.lyb_save_dated_outcome($1::uuid, $2::jsonb, $3::jsonb) as result',
          [
            admission.ownerId,
            JSON.stringify(edit),
            JSON.stringify(datedOutcomePlanInputs(edit.value)),
          ],
        ),
      ]);
      return rows[0].result as Awaited<ReturnType<DatedOutcomePort['save']>>;
    },
    async exportForSubject(subject) {
      return database.query(
        `select r.request_id, r.edit, r.plan_inputs, r.created_at
         from public.dated_outcome_recompute_requests r join public.app_users u on u.id = r.owner_id
         where u.identity_provider = 'jovie' and u.identity_subject = $1 order by r.created_at, r.request_id`,
        [subject],
      );
    },
  };
}

let instance: ReturnType<typeof createNeonDatedOutcomes> | undefined;
export function neonDatedOutcomes(): ReturnType<typeof createNeonDatedOutcomes> {
  if (!instance) {
    if (!process.env.DATABASE_URL) throw new Error('Missing DATABASE_URL for product persistence');
    instance = createNeonDatedOutcomes(neon(process.env.DATABASE_URL));
  }
  return instance;
}
