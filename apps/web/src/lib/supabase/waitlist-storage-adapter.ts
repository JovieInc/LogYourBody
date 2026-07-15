import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { WaitlistStoragePort } from '@/lib/ports/waitlist-storage';
import { normalizeWaitlistEmail } from '@/lib/waitlist/normalize-email';

function getServiceClient(): SupabaseClient {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error('Missing Supabase environment variables for waitlist storage');
  }

  return createClient(url, key, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

export const supabaseWaitlistStorage: WaitlistStoragePort = {
  async accept({ email, source }) {
    const normalized = normalizeWaitlistEmail(email);
    if (!normalized) {
      throw new Error('INVALID_EMAIL');
    }

    const { error } = await getServiceClient().from('waitlist_entries').insert({
      email: normalized,
      email_normalized: normalized,
      source,
    });

    // A duplicate means the address is already safely on the list. Keep the
    // public response identical so this endpoint cannot enumerate subscribers.
    if (error && error.code !== '23505') {
      throw error;
    }
  },
};
