import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { normalizeWaitlistEmail } from '@/lib/waitlist/normalize-email';

export type WaitlistInsertResult =
  | { status: 'created'; id: string }
  | { status: 'existing'; id: string };

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

export async function upsertWaitlistEntry(params: {
  email: string;
  source?: string;
}): Promise<WaitlistInsertResult> {
  const normalized = normalizeWaitlistEmail(params.email);
  if (!normalized) {
    throw new Error('INVALID_EMAIL');
  }

  const supabase = getServiceClient();
  const source = params.source ?? 'landing';

  const { data: existing, error: lookupError } = await supabase
    .from('waitlist_entries')
    .select('id')
    .eq('email_normalized', normalized)
    .maybeSingle();

  if (lookupError) {
    throw lookupError;
  }

  if (existing?.id) {
    return { status: 'existing', id: existing.id };
  }

  const { data: created, error: insertError } = await supabase
    .from('waitlist_entries')
    .insert({
      email: normalized,
      email_normalized: normalized,
      source,
    })
    .select('id')
    .single();

  if (insertError) {
    if (insertError.code === '23505') {
      const { data: raced } = await supabase
        .from('waitlist_entries')
        .select('id')
        .eq('email_normalized', normalized)
        .maybeSingle();

      if (raced?.id) {
        return { status: 'existing', id: raced.id };
      }
    }
    throw insertError;
  }

  return { status: 'created', id: created.id };
}
