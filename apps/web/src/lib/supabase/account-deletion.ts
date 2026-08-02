import 'server-only';

/**
 * Delete the authenticated user's Supabase rows and photo assets through the
 * canonical edge-function boundary. The first-party web runtime validates the
 * Jovie session, then uses its server-only service credential to request
 * deletion for that exact subject. Jovie credentials never leave LYB.
 */
export async function deleteUserHealthData(userId: string): Promise<void> {
  if (!userId.trim()) throw new Error('Cannot delete account data without a user id');

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) {
    throw new Error('Supabase account-deletion service is not configured');
  }

  const response = await fetch(`${url.replace(/\/$/, '')}/functions/v1/delete-user-assets`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${serviceRoleKey}`,
      apikey: serviceRoleKey,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ userId }),
    cache: 'no-store',
  });

  if (!response.ok) {
    throw new Error(`Account data deletion failed with status ${response.status}`);
  }
}
