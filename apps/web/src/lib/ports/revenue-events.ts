import type { RevenueCatEnvelope } from '@/lib/revenuecat/events';

/** Immutable provider events; this port is never exposed through native record sync. */
export interface RevenueEventStore {
  insert(
    envelope: RevenueCatEnvelope,
    fingerprint: string,
  ): Promise<'stored' | 'duplicate' | 'conflict'>;
}
