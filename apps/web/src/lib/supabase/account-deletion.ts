import 'server-only';

/**
 * Supabase edge-function account deletion is retired. Product rows live in
 * Neon and are erased by `neonUserDirectory.deleteUser`. Empty Neon state is
 * an acceptable hard-cut outcome.
 */
export async function deleteUserHealthData(userId: string): Promise<void> {
  void userId;
  throw new Error('Supabase account-deletion service retired. Use neonUserDirectory.deleteUser.');
}
