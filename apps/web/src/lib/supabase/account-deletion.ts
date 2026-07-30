import 'server-only';

import { createClient } from '@supabase/supabase-js';

/**
 * Every table in the Supabase health-data schema that is owned by one account.
 * Keep this list in dependency-safe order and update the migration guard test
 * whenever a new user-owned table is added.
 */
export const accountDeletionTargets = [
  { table: 'data_exports', column: 'user_id' },
  { table: 'progress_photos', column: 'user_id' },
  { table: 'dexa_results', column: 'user_id' },
  { table: 'glp1_dose_logs', column: 'user_id' },
  { table: 'glp1_medications', column: 'user_id' },
  { table: 'daily_metrics', column: 'user_id' },
  { table: 'body_metrics', column: 'user_id' },
  { table: 'email_subscriptions', column: 'user_id' },
  { table: 'profiles', column: 'id' },
] as const;

export async function deleteUserHealthData(userId: string): Promise<void> {
  if (!userId.trim()) throw new Error('Cannot delete health data without a user id');

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) {
    throw new Error('Supabase account-deletion service is not configured');
  }

  // This module is server-only. The service role is used only for this
  // authenticated, exact-user deletion chain; clients never receive it.
  const supabase = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  for (const target of accountDeletionTargets) {
    const { error } = await supabase.from(target.table).delete().eq(target.column, userId);
    if (error) {
      throw new Error(`Failed to delete ${target.table}: ${error.message}`);
    }
  }
}
