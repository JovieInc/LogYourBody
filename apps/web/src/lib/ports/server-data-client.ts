import { createClerkSupabaseClient } from '@/lib/supabase/clerk-client';

export async function createAuthenticatedDataClient(getToken: () => Promise<string | null>) {
  return createClerkSupabaseClient(getToken);
}
