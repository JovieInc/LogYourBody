import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import type { RevenueEventStore } from '@/lib/ports/revenue-events';

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase() {
  if (sql) return sql;
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for revenue persistence');
  sql = neon(connectionString);
  return sql;
}

export function createNeonRevenueEventStore(
  database: NeonQueryFunction<false, false> = getDatabase(),
): RevenueEventStore {
  return {
    async insert(envelope, fingerprint) {
      const { app_id: appId, id } = envelope.event;
      const inserted = await database`
        insert into public.revenuecat_events (app_id, event_id, fingerprint, payload)
        values (${appId}, ${id}, ${fingerprint}, ${JSON.stringify(envelope)}::jsonb)
        on conflict (app_id, event_id) do nothing
        returning event_id
      `;
      if (inserted.length === 1) return 'stored';
      // A new statement sees a competing insert after ON CONFLICT waits for it.
      const existing = await database`
        select fingerprint from public.revenuecat_events
        where app_id = ${appId} and event_id = ${id}
      `;
      if (existing.length !== 1) throw new Error('Revenue event persistence unavailable');
      return existing[0]?.fingerprint === fingerprint ? 'duplicate' : 'conflict';
    },
  };
}

export const neonRevenueEvents: RevenueEventStore = {
  insert: (envelope, fingerprint) => createNeonRevenueEventStore().insert(envelope, fingerprint),
};
