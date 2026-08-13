/** @jest-environment node */

import { NextRequest } from 'next/server';
import { createNativeProductRecordHandlers } from '../route-handlers';
import type {
  NativeProductRecord,
  NativeProductRecordCollection,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import type { JovieUserInfo } from '@/lib/auth/jovie-oauth';

const morningId = '11111111-1111-4111-8111-111111111111';
const eveningId = '22222222-2222-4222-8222-222222222222';

const morning = {
  id: morningId,
  date: '2026-08-13T12:15:00.000Z',
  steps: 8421,
  extra_native_field: { cadence: 118 },
};

class MemoryNativeRecords implements NativeProductRecordsPort {
  pushed: Array<{
    subject: string;
    collection: NativeProductRecordCollection;
    records: Array<Record<string, unknown>>;
  }> = [];
  pulled: Array<{ subject: string; collection: NativeProductRecordCollection; since: string }> = [];
  removed: Array<{ subject: string; collection: NativeProductRecordCollection; ids: string[] }> = [];
  ended: Array<{ subject: string; endedAt: string }> = [];

  async push(
    subject: string,
    collection: NativeProductRecordCollection,
    records: Array<Record<string, unknown>>,
  ) {
    this.pushed.push({ subject, collection, records });
    return {
      records: records.map(
        (record) =>
          ({
            ...record,
            id: String(record.id),
            deleted_at: null,
            server_updated_at: '2026-08-13T12:16:00.000Z',
          }) as NativeProductRecord,
      ),
      rejected_ids: [],
    };
  }

  async pull(subject: string, collection: NativeProductRecordCollection, input: { since: string }) {
    this.pulled.push({ subject, collection, since: input.since });
    return {
      records: [
        {
          ...morning,
          deleted_at: null,
          server_updated_at: '2026-08-13T12:16:00.000Z',
        } as NativeProductRecord,
      ],
      deleted_ids: [eveningId],
      next_cursor: null,
    };
  }

  async remove(subject: string, collection: NativeProductRecordCollection, ids: string[]) {
    this.removed.push({ subject, collection, ids });
    return { deleted_ids: ids };
  }

  async endActiveGlp1Medications(subject: string, endedAt: string) {
    this.ended.push({ subject, endedAt });
    return { updated: 1 };
  }

  async listAll() {
    return {
      daily_metrics: [],
      glp1_medications: [],
      glp1_dose_logs: [],
      dexa_results: [],
      progress_photos: [],
    };
  }

  async deleteAllForSubject() {}
}

function makeHarness(users: Record<string, string> = { 'access-a': 'owner-a', 'access-b': 'owner-b' }) {
  const records = new MemoryNativeRecords();
  const handlers = createNativeProductRecordHandlers({
    authenticate: async (request) => {
      const token = request.headers.get('authorization')?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
      const sub = token ? users[token] : undefined;
      return sub ? ({ sub } as JovieUserInfo) : null;
    },
    records,
  });
  return { handlers, records };
}

function request(
  method: 'GET' | 'POST' | 'DELETE',
  collection: string,
  token?: string,
  body?: unknown,
  query = '',
) {
  return new NextRequest(`http://localhost/api/auth/mobile/sync/v1/${collection}${query}`, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

describe('/api/auth/mobile/sync/v1/[collection]', () => {
  it('rejects missing bearer tokens before touching persistence', async () => {
    const { handlers, records } = makeHarness();
    expect((await handlers.GET(request('GET', 'daily-metrics'))).status).toBe(401);
    expect((await handlers.POST(request('POST', 'daily-metrics', undefined, [morning]))).status).toBe(
      401,
    );
    expect(
      (await handlers.DELETE(request('DELETE', 'daily-metrics', undefined, { ids: [morningId] }))).status,
    ).toBe(401);
    expect(records.pushed).toEqual([]);
    expect(records.pulled).toEqual([]);
    expect(records.removed).toEqual([]);
  });

  it('returns 404 for unknown collections', async () => {
    const { handlers, records } = makeHarness();
    expect((await handlers.GET(request('GET', 'food-logs', 'access-a'))).status).toBe(404);
    expect(records.pulled).toEqual([]);
  });

  it('pushes passthrough native fields scoped to the authenticated subject', async () => {
    const { handlers, records } = makeHarness();
    const response = await handlers.POST(
      request('POST', 'daily-metrics', 'access-a', {
        records: [{ ...morning, user_id: 'client-claimed-other-user' }],
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      version: 1,
      records: [{ id: morningId, extra_native_field: { cadence: 118 } }],
    });
    expect(records.pushed).toHaveLength(1);
    expect(records.pushed[0]?.subject).toBe('owner-a');
    expect(records.pushed[0]?.collection).toBe('daily_metrics');
    expect(records.pushed[0]?.records[0]?.extra_native_field).toEqual({ cadence: 118 });
  });

  it('accepts a raw array body from native clients', async () => {
    const { handlers, records } = makeHarness();
    const response = await handlers.POST(request('POST', 'dexa-results', 'access-a', [morning]));
    expect(response.status).toBe(200);
    expect(records.pushed[0]?.collection).toBe('dexa_results');
    expect(records.pushed[0]?.records).toHaveLength(1);
  });

  it('ends active GLP-1 medications for the authenticated subject', async () => {
    const { handlers, records } = makeHarness();
    const response = await handlers.POST(
      request('POST', 'glp1-medications', 'access-b', { ended_at: '2026-08-13T18:00:00.000Z' }),
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ version: 1, updated: 1 });
    expect(records.ended).toEqual([{ subject: 'owner-b', endedAt: '2026-08-13T18:00:00.000Z' }]);
    expect(records.pushed).toEqual([]);
  });

  it('pulls and deletes only for the authenticated subject', async () => {
    const { handlers, records } = makeHarness();

    const pull = await handlers.GET(
      request('GET', 'progress-photos', 'access-b', undefined, '?since=2026-08-13T00:00:00.000Z'),
    );
    expect(pull.status).toBe(200);
    expect(records.pulled).toEqual([
      { subject: 'owner-b', collection: 'progress_photos', since: '2026-08-13T00:00:00.000Z' },
    ]);

    const deleted = await handlers.DELETE(
      request('DELETE', 'progress-photos', 'access-b', { ids: [morningId] }),
    );
    expect(deleted.status).toBe(200);
    expect(records.removed).toEqual([
      { subject: 'owner-b', collection: 'progress_photos', ids: [morningId] },
    ]);
  });
});
