/** @jest-environment node */

import { NextRequest } from 'next/server';
import { createNativeBodyMetricsSyncHandlers } from '../route-handlers';
import type {
  NativeBodyMetricPushInput,
  NativeBodyMetricSyncRecord,
  NativeBodyMetricsSyncPort,
} from '@/lib/ports/native-body-metrics-sync';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';

const morningId = '11111111-1111-4111-8111-111111111111';
const eveningId = '22222222-2222-4222-8222-222222222222';

const morningInput: NativeBodyMetricPushInput = {
  id: morningId,
  date: '2026-08-13T12:15:00.000Z',
  local_date: '2026-08-13',
  weight: 80.4,
  weight_unit: 'kg',
  waist_circumference: 81,
  hip_circumference: 96,
  waist_unit: 'cm',
  body_fat_percentage: 18.2,
  body_fat_method: 'dexa',
  muscle_mass: 62.1,
  bone_mass: 3.11,
  photo_url: null,
  notes: 'morning',
  data_source: 'bodyspec_dexa',
  source_metadata: { vendor: 'bodyspec' },
  created_at: '2026-08-13T12:15:00.000Z',
  updated_at: '2026-08-13T12:15:00.000Z',
};

function asRecord(input: NativeBodyMetricPushInput): NativeBodyMetricSyncRecord {
  return {
    ...input,
    deleted_at: null,
    server_updated_at: '2026-08-13T12:16:00.000Z',
  };
}

class MemoryNativeSync implements NativeBodyMetricsSyncPort {
  pushed: Array<{ subject: string; records: NativeBodyMetricPushInput[] }> = [];
  pulled: Array<{ subject: string; since: string; after_id: string | null; limit?: number }> = [];
  removed: Array<{ subject: string; ids: string[] }> = [];

  async push(subject: string, records: NativeBodyMetricPushInput[]) {
    this.pushed.push({ subject, records });
    return { records: records.map(asRecord), rejected_ids: [] };
  }

  async pull(
    subject: string,
    input: { since: string; after_id: string | null; limit?: number },
  ) {
    this.pulled.push({ subject, ...input });
    return {
      records: [asRecord(morningInput)],
      deleted_ids: [eveningId],
      next_cursor: null,
    };
  }

  async remove(subject: string, ids: string[]) {
    this.removed.push({ subject, ids });
    return { deleted_ids: ids };
  }
}

function makeHarness(users: Record<string, string> = { 'access-a': 'owner-a', 'access-b': 'owner-b' }) {
  const sync = new MemoryNativeSync();
  const handlers = createNativeBodyMetricsSyncHandlers({
    authenticate: async (request) => {
      const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
      const sub = token ? users[token] : undefined;
      return sub ? ({ sub } as JovieUserInfo) : null;
    },
    sync,
  });
  return { handlers, sync };
}

function request(
  method: 'GET' | 'POST' | 'DELETE',
  token?: string,
  body?: unknown,
  query = '',
) {
  return new NextRequest(`http://localhost/api/auth/mobile/sync/v1/body-metrics${query}`, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

describe('/api/auth/mobile/sync/v1/body-metrics', () => {
  it('rejects missing bearer tokens before touching persistence', async () => {
    const { handlers, sync } = makeHarness();
    expect((await handlers.GET(request('GET'))).status).toBe(401);
    expect((await handlers.POST(request('POST', undefined, { records: [morningInput] }))).status).toBe(
      401,
    );
    expect((await handlers.DELETE(request('DELETE', undefined, { ids: [morningId] }))).status).toBe(
      401,
    );
    expect(sync.pushed).toEqual([]);
    expect(sync.pulled).toEqual([]);
    expect(sync.removed).toEqual([]);
  });

  it('pushes native records scoped to the authenticated subject and keeps same-day identity', async () => {
    const { handlers, sync } = makeHarness();
    const evening = {
      ...morningInput,
      id: eveningId,
      date: '2026-08-13T23:40:00.000Z',
      notes: 'evening',
      data_source: 'manual' as const,
      source_metadata: {},
      created_at: '2026-08-13T23:40:00.000Z',
      updated_at: '2026-08-13T23:40:00.000Z',
    };

    const response = await handlers.POST(
      request('POST', 'access-a', {
        records: [
          { ...morningInput, user_id: 'client-claimed-other-user' },
          evening,
        ],
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      version: 1,
      records: [{ id: morningId, bone_mass: 3.11 }, { id: eveningId }],
    });
    expect(sync.pushed).toHaveLength(1);
    expect(sync.pushed[0]?.subject).toBe('owner-a');
    expect(sync.pushed[0]?.records).toHaveLength(2);
    expect(sync.pushed[0]?.records.map((record) => record.id)).toEqual([morningId, eveningId]);
    expect(sync.pushed[0]?.records[0]).not.toHaveProperty('user_id');
    expect(sync.pushed[0]?.records[0]?.bone_mass).toBe(3.11);
  });

  it('fails closed when a native field would be silently dropped', async () => {
    const { handlers, sync } = makeHarness();
    const truncated: Record<string, unknown> = { ...morningInput };
    delete truncated.bone_mass;
    const response = await handlers.POST(request('POST', 'access-a', { records: [truncated] }));
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({ version: 1, error: 'invalid_records' });
    expect(sync.pushed).toEqual([]);
  });

  it('pulls and deletes only for the authenticated subject', async () => {
    const { handlers, sync } = makeHarness();

    const pull = await handlers.GET(
      request('GET', 'access-b', undefined, '?since=2026-08-13T00:00:00.000Z&limit=50'),
    );
    expect(pull.status).toBe(200);
    await expect(pull.json()).resolves.toMatchObject({
      version: 1,
      deleted_ids: [eveningId],
      records: [{ id: morningId, user_id: 'owner-b' }],
    });
    expect(sync.pulled).toEqual([
      {
        subject: 'owner-b',
        since: '2026-08-13T00:00:00.000Z',
        after_id: null,
        limit: 50,
      },
    ]);

    const deleted = await handlers.DELETE(request('DELETE', 'access-b', { ids: [morningId] }));
    expect(deleted.status).toBe(200);
    await expect(deleted.json()).resolves.toEqual({
      version: 1,
      deleted_ids: [morningId],
    });
    expect(sync.removed).toEqual([{ subject: 'owner-b', ids: [morningId] }]);
  });
});
