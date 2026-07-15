import { createClient } from '@/lib/supabase/server';

export async function createAuthenticatedDataClient(getToken: () => Promise<string | null>) {
  void getToken;
  return createClient();
}
