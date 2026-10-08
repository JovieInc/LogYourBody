import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import type { WaitlistStoragePort } from '@/lib/ports/waitlist-storage';
import { normalizeWaitlistEmail } from '@/lib/waitlist/normalize-email';

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase(): NeonQueryFunction<false, false> {
  if (sql) return sql;

  const connectionString = process.env.WAITLIST_DATABASE_URL;
  if (!connectionString) {
    throw new Error('Missing WAITLIST_DATABASE_URL for waitlist storage');
  }

  sql = neon(connectionString);
  return sql;
}

export const neonWaitlistStorage: WaitlistStoragePort = {
  async accept({ email, source }) {
    const normalized = normalizeWaitlistEmail(email);
    if (!normalized) {
      throw new Error('INVALID_EMAIL');
    }

    const rows = await getDatabase()`
      insert into public.waitlist_entries (email, email_normalized, source)
      values (${normalized}, ${normalized}, ${source})
      on conflict (email_normalized) do nothing
      returning true as created
    `;
    return { created: rows.length === 1 };
  },

  async countRegistrations({ from, to }) {
    const rows = await getDatabase()`
      select count(*)::text as count, now() as observed_at
      from public.waitlist_entries
      where created_at >= ${from}::timestamptz
        and created_at < ${to}::timestamptz
    `;
    const count = Number(rows[0]?.count);
    const observedAt = new Date(rows[0]?.observed_at).toISOString();
    if (!Number.isSafeInteger(count) || count < 0) throw new Error('INVALID_WAITLIST_COUNT');
    return { count, observedAt };
  },
};
