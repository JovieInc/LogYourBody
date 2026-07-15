import type { WaitlistEntryInput } from '@/lib/ports/waitlist-storage';
import { neonWaitlistStorage } from '@/lib/neon/waitlist-storage-adapter';

export async function acceptWaitlistEntry(entry: WaitlistEntryInput): Promise<void> {
  return neonWaitlistStorage.accept(entry);
}
