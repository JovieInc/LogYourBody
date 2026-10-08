import type { WaitlistEntryInput } from '@/lib/ports/waitlist-storage';
import { neonWaitlistStorage } from '@/lib/neon/waitlist-storage-adapter';

export async function acceptWaitlistEntry(
  entry: WaitlistEntryInput,
): Promise<{ created: boolean }> {
  return neonWaitlistStorage.accept(entry);
}

// Read-only aggregate for a future operator report. Historical registrations
// lack environment/QA classification; this cannot establish real-user growth.
export async function summarizeWaitlistRegistrations(window: { from: string; to: string }) {
  const zonedTimestamp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
  if (!zonedTimestamp.test(window.from) || !zonedTimestamp.test(window.to)) {
    throw new Error('INVALID_WAITLIST_WINDOW');
  }
  const from = new Date(window.from);
  const to = new Date(window.to);
  if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from >= to) {
    throw new Error('INVALID_WAITLIST_WINDOW');
  }
  const result = await neonWaitlistStorage.countRegistrations({
    from: from.toISOString(),
    to: to.toISOString(),
  });
  return {
    schema_version: 1,
    metric: 'unique_persisted_waitlist_registrations',
    environment: 'unclassified',
    window_start: from.toISOString(),
    window_end: to.toISOString(),
    observed_at: result.observedAt,
    count: result.count,
    qualified_real_users: null,
    exclusions_applied: [],
  } as const;
}
