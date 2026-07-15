import 'server-only';

import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import type { UserDirectoryPort } from '@/lib/ports/user-directory';

let sql: NeonQueryFunction<false, false> | undefined;

function getDatabase(): NeonQueryFunction<false, false> {
  if (sql) return sql;
  const connectionString = process.env.DATABASE_URL || process.env.WAITLIST_DATABASE_URL;
  if (!connectionString) throw new Error('Missing DATABASE_URL for product persistence');
  sql = neon(connectionString);
  return sql;
}

export const neonUserDirectory: UserDirectoryPort = {
  async recordSignIn(identity) {
    await getDatabase()`
      insert into public.app_users (
        identity_provider,
        identity_subject,
        phone_e164,
        email,
        display_name,
        avatar_url,
        last_signed_in_at
      ) values (
        'jovie',
        ${identity.subject},
        ${identity.phoneNumber || null},
        ${identity.email || null},
        ${identity.displayName || null},
        ${identity.avatarUrl || null},
        now()
      )
      on conflict (identity_provider, identity_subject) do update set
        phone_e164 = coalesce(excluded.phone_e164, app_users.phone_e164),
        email = coalesce(excluded.email, app_users.email),
        display_name = coalesce(excluded.display_name, app_users.display_name),
        avatar_url = coalesce(excluded.avatar_url, app_users.avatar_url),
        last_signed_in_at = now(),
        updated_at = now()
    `;
  },
};
