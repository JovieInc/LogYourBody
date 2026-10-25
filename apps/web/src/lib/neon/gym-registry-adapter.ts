import 'server-only';
import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { gymChangesSchema, gymRecordSchema, type GymRegistryPort } from '@/lib/ports/gym-registry';
import { NativeAccountAdmissionError } from '@/lib/ports/native-account-admission';
import {
  captureNativeAccountAdmission,
  executeNativeMutationQueries,
} from './native-account-admission';

export function createNeonGymRegistry(database: NeonQueryFunction<false, false>): GymRegistryPort {
  return {
    async sync(subject, changes = []) {
      if (changes.length) changes = gymChangesSchema.parse({ changes }).changes;
      const admission = await captureNativeAccountAdmission(database, subject);
      if (!admission) throw new NativeAccountAdmissionError('account_changed');
      const queries = [
        database.query("select set_config('lyb.gym_owner_id', $1, true)", [admission.ownerId]),
      ];
      for (const { gym, deleted } of changes) {
        queries.push(
          database.query(
            `insert into public.gyms (id, owner_id, name, coarse_region, equipment, preferred_machines, deleted)
           values ($1::uuid, $2::uuid, $3, $4, $5::text[], $6::text[], $7::boolean)
           on conflict (id) do update set name = excluded.name, coarse_region = excluded.coarse_region,
             equipment = excluded.equipment, preferred_machines = excluded.preferred_machines,
             deleted = excluded.deleted, updated_at = now()
           where public.gyms.owner_id = excluded.owner_id and not public.gyms.deleted`,
            [
              gym.id,
              admission.ownerId,
              gym.name,
              gym.coarseRegion,
              gym.equipment,
              gym.preferredMachines,
              deleted,
            ],
          ),
        );
      }
      queries.push(
        database.query(
          `select jsonb_build_object('gym', jsonb_build_object('id', id, 'name', name,
          'coarseRegion', coarse_region, 'equipment', equipment, 'preferredMachines', preferred_machines),
          'deleted', deleted) as record
         from public.gyms where owner_id = $1::uuid order by id`,
          [admission.ownerId],
        ),
      );
      const results = await executeNativeMutationQueries(database, admission, queries);
      return results.at(-1)!.map((row) => gymRecordSchema.parse(row.record));
    },
  };
}

export const neonGymRegistry: GymRegistryPort = {
  sync(subject, changes) {
    if (!process.env.DATABASE_URL) throw new Error('Missing DATABASE_URL for gym persistence');
    return createNeonGymRegistry(neon(process.env.DATABASE_URL)).sync(subject, changes);
  },
};
