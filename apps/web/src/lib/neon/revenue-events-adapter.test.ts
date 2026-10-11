/** @jest-environment node */
import type { NeonQueryFunction } from '@neondatabase/serverless';
import { revenueCatEnvelopeSchema } from '@/lib/revenuecat/events';
import { createNeonRevenueEventStore } from './revenue-events-adapter';

jest.mock('server-only', () => ({}));
const envelope = revenueCatEnvelopeSchema.parse({
  api_version: '1.0',
  event: {
    id: 'event-fixture',
    app_id: 'app-fixture',
    type: 'TEST',
    event_timestamp_ms: 1,
  },
});
const fingerprint = 'a'.repeat(64);

describe('immutable RevenueCat event adapter', () => {
  it('inserts once using bound values and never overwrites a duplicate event', async () => {
    const query = jest.fn().mockResolvedValueOnce([{ event_id: envelope.event.id }]);
    const store = createNeonRevenueEventStore(query as unknown as NeonQueryFunction<false, false>);
    expect(await store.insert(envelope, fingerprint)).toBe('stored');
    expect(query).toHaveBeenCalledTimes(1);
    expect(query.mock.calls[0]![0].join(' ')).toMatch(
      /on conflict \(app_id, event_id\) do nothing/,
    );
    expect(query.mock.calls[0]!.slice(1)).toEqual([
      'app-fixture',
      'event-fixture',
      fingerprint,
      JSON.stringify(envelope),
    ]);
  });

  it.each([fingerprint, 'b'.repeat(64)])(
    'reads a competing insert in a fresh statement (%s)',
    async (saved) => {
      const query = jest
        .fn()
        .mockResolvedValueOnce([])
        .mockResolvedValueOnce([{ fingerprint: saved }]);
      const store = createNeonRevenueEventStore(
        query as unknown as NeonQueryFunction<false, false>,
      );
      expect(await store.insert(envelope, fingerprint)).toBe(
        saved === fingerprint ? 'duplicate' : 'conflict',
      );
      expect(query).toHaveBeenCalledTimes(2);
      expect(query.mock.calls[1]![0].join(' ')).toContain('select fingerprint');
      expect(query.mock.calls[1]!.slice(1)).toEqual(['app-fixture', 'event-fixture']);
    },
  );

  it('fails rather than acknowledging a missing conflicting row', async () => {
    const query = jest.fn().mockResolvedValue([]);
    const store = createNeonRevenueEventStore(query as unknown as NeonQueryFunction<false, false>);
    await expect(store.insert(envelope, fingerprint)).rejects.toThrow(
      'Revenue event persistence unavailable',
    );
  });
});
