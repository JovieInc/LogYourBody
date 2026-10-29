import 'server-only';
import { neon, type NeonQueryFunction, type NeonQueryPromise } from '@neondatabase/serverless';

export type GymSyncRecord = {
  id: string;
  name: string;
  region: string | null;
  equipment: string[];
  preferredMachines: string[];
  updatedAt: string;
  deletedAt: string | null;
};

type GymRow = {
  id: string;
  name: string;
  region: string | null;
  equipment: string[] | null;
  preferred_machines: string[] | null;
  updated_at: string | Date;
  deleted_at: string | Date | null;
};

const listColumns = 'id, name, region, equipment, preferred_machines, updated_at, deleted_at';

// `query()` infers its boolean flags as `boolean` unless the call is pinned.
// `transaction()` only accepts the `false, false` client used everywhere else.
type GymQuery = NeonQueryPromise<false, false>;

let cached: NeonQueryFunction<false, false> | undefined;

function defaultDatabase(): NeonQueryFunction<false, false> {
  if (cached) return cached;
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for product persistence');
  cached = neon(connectionString);
  return cached;
}

function timestamp(value: string | Date): string {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function mapGym(row: GymRow): GymSyncRecord {
  return {
    id: row.id,
    name: row.name,
    region: row.region,
    equipment: row.equipment ?? [],
    preferredMachines: row.preferred_machines ?? [],
    updatedAt: timestamp(row.updated_at),
    deletedAt: row.deleted_at ? timestamp(row.deleted_at) : null,
  };
}

async function withSubject(
  database: NeonQueryFunction<false, false>,
  subject: string,
  statement: GymQuery,
): Promise<GymRow[]> {
  const results = await database.transaction([
    database.query<false, false>(`select set_config('app.current_user_subject', $1, true)`, [
      subject,
    ]),
    statement,
  ]);
  return (results[1] ?? []) as GymRow[];
}

export function createNeonGymRegistry(
  database: NeonQueryFunction<false, false> = defaultDatabase(),
) {
  return {
    async list(subject: string): Promise<GymSyncRecord[]> {
      const rows = await withSubject(
        database,
        subject,
        database.query<false, false>(`select ${listColumns} from public.lyb_list_gyms()`, []),
      );
      return rows.map(mapGym);
    },

    async upsert(
      subject: string,
      gym: {
        id: string;
        name: string;
        region: string | null;
        equipment: string[];
        preferredMachines: string[];
      },
    ): Promise<GymSyncRecord> {
      const rows = await withSubject(
        database,
        subject,
        database.query<false, false>(
          `select ${listColumns} from public.lyb_upsert_gym($1::uuid, $2, $3, $4::text[], $5::text[])`,
          [gym.id, gym.name, gym.region, gym.equipment, gym.preferredMachines],
        ),
      );
      const row = rows[0];
      if (!row) throw new Error('gym_not_saved');
      return mapGym(row);
    },

    async remove(subject: string, id: string): Promise<GymSyncRecord> {
      const rows = await withSubject(
        database,
        subject,
        database.query<false, false>(`select ${listColumns} from public.lyb_delete_gym($1::uuid)`, [
          id,
        ]),
      );
      const row = rows[0];
      if (!row) throw new Error('gym_not_owned');
      return mapGym(row);
    },
  };
}
