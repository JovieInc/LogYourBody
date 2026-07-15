import type { WaitlistEntryInput } from '@/lib/ports/waitlist-storage';
import { supabaseWaitlistStorage } from '@/lib/supabase/waitlist-storage-adapter';

export async function acceptWaitlistEntry(entry: WaitlistEntryInput): Promise<void> {
  return supabaseWaitlistStorage.accept(entry);
}
