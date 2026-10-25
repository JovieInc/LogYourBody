import 'server-only';
import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { GymSchema, type GymRegistryPort } from '@/lib/ports/gym-registry';
import { executeNativeMutationQueries, type NativeMutationQuery } from './native-account-admission';
import type { NativeAccountAdmission } from '@/lib/ports/native-account-admission';

export function createNeonGymRegistry(database: NeonQueryFunction<false, false>): GymRegistryPort {
  // Transaction-local context never leaks between pooled connections. Explicit
  // owner predicates also protect deployments using a BYPASSRLS service role.
  const context = (subject: string) =>
    database.query("select set_config('app.user_subject', $1, true)", [subject]);
  async function mutate(admission: NativeAccountAdmission, query: NativeMutationQuery) {
    const results = await executeNativeMutationQueries(database, admission, [
      context(admission.subject),
      query,
    ]);
    return results[1];
  }
  return {
    async list(subject) {
      const results = await database.transaction([
        context(subject),
        database.query(
          `select id, payload from public.gyms
          where user_subject = $1 and deleted_at is null order by id`,
          [subject],
        ),
      ]);
      return results[1].map((row) => GymSchema.parse({ ...(row.payload as object), id: row.id }));
    },
    async save(admission, gym) {
      const value = GymSchema.parse(gym);
      const rows = await mutate(
        admission,
        database.query(
          `insert into public.gyms(id, owner_id, user_subject, payload)
         values ($1::uuid, $2::uuid, $3, $4::jsonb)
         on conflict (id) do update set payload = excluded.payload, updated_at = now()
         where public.gyms.user_subject = excluded.user_subject
           and public.gyms.owner_id = excluded.owner_id and public.gyms.deleted_at is null
         returning id`,
          [value.id, admission.ownerId, admission.subject, JSON.stringify(value)],
        ),
      );
      return rows.length === 1;
    },
    async remove(admission, id) {
      await mutate(
        admission,
        database.query(
          `update public.gyms set deleted_at = coalesce(deleted_at, now()), updated_at = now()
         where id = $1::uuid and user_subject = $2 and owner_id = $3::uuid`,
          [id, admission.subject, admission.ownerId],
        ),
      );
    },
  };
}

function registry() {
  if (!process.env.DATABASE_URL) throw new Error('Missing DATABASE_URL for gym persistence');
  return createNeonGymRegistry(neon(process.env.DATABASE_URL));
}

export const neonGymRegistry: GymRegistryPort = {
  list: (subject) => registry().list(subject),
  save: (admission, gym) => registry().save(admission, gym),
  remove: (admission, id) => registry().remove(admission, id),
};
