/** @jest-environment node */

import { NextRequest } from 'next/server';
import { createNativeProductRecordHandlers } from '../route-handlers';
import type {
  NativeProductAccountMutationsPort,
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
  accountMutations: NativeProductAccountMutationsPort = {
    capture: async (subject) => ({ subject, ownerId: morningId }),
    push: (a, collection, records) => this.push(a.subject, collection, records),
    remove: (a, collection, ids) => this.remove(a.subject, collection, ids),
    endActiveGlp1Medications: (a, endedAt) => this.endActiveGlp1Medications(a.subject, endedAt),
  };

  pushed: Array<{
    subject: string;
    collection: NativeProductRecordCollection;
    records: Array<Record<string, unknown>>;
  }> = [];
  pulled: Array<{ subject: string; collection: NativeProductRecordCollection; since: string }> = [];
  removed: Array<{ subject: string; collection: NativeProductRecordCollection; ids: string[] }> =
    [];
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
      training_sessions: [],
      logged_sets: [],
      training_feedback: [],
    };
  }

  async deleteAllForSubject() {}
}

function makeHarness(
  users: Record<string, string> = { 'access-a': 'owner-a', 'access-b': 'owner-b' },
) {
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
    expect(
      (await handlers.POST(request('POST', 'daily-metrics', undefined, [morning]))).status,
    ).toBe(401);
    expect(
      (await handlers.DELETE(request('DELETE', 'daily-metrics', undefined, { ids: [morningId] })))
        .status,
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

  it('keeps training collections behind the consent-aware training API', async () => {
    const { handlers, records } = makeHarness();
    expect((await handlers.GET(request('GET', 'training-sessions', 'access-a'))).status).toBe(403);
    expect(
      (await handlers.POST(request('POST', 'logged-sets', 'access-a', [morning]))).status,
    ).toBe(403);
    expect(
      (
        await handlers.DELETE(
          request('DELETE', 'training-feedback', 'access-a', { ids: [morningId] }),
        )
      ).status,
    ).toBe(403);
    expect(records.pulled).toEqual([]);
    expect(records.pushed).toEqual([]);
    expect(records.removed).toEqual([]);
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

  const reportedMeasurements = {
    schema_version: 1,
    items: [
      {
        kind: 'lean_mass',
        value: 62,
        unit: 'kg',
        reported_label: 'Lean Mass',
        reported_unit: 'kg',
      },
    ],
  };

  it.each([
    ['known measurements', reportedMeasurements],
    [
      'unknown kind',
      {
        schema_version: 1,
        items: [{ kind: 'future_ratio', value: { numerator: 2, denominator: 3 } }],
      },
    ],
    [
      'future meaning for a known name',
      {
        schema_version: 2,
        items: [{ kind: 'lean_mass', value: { opaque: true }, unit: 'future' }],
      },
    ],
    [
      'future version',
      {
        schema_version: 2,
        items: [{ kind: 'future_ratio', value: 'uninterpreted', unit: { future: 'unit' } }],
      },
    ],
  ])('preserves bounded %s without converting them into a muscle scalar', async (_, envelope) => {
    const { handlers, records } = makeHarness();
    const response = await handlers.POST(
      request('POST', 'dexa-results', 'access-a', [
        { id: morningId, reported_measurements: envelope },
      ]),
    );
    expect(response.status).toBe(200);
    expect(records.pushed[0]?.records[0]).toEqual({
      id: morningId,
      reported_measurements: envelope,
    });
    expect(records.pushed[0]?.records[0]).not.toHaveProperty('muscle_mass');
  });

  it.each([
    ['null', null],
    ['array', []],
    ['missing version', { items: [] }],
    ['invalid version', { schema_version: 0, items: [] }],
    ['fractional version', { schema_version: 1.5, items: [] }],
    ['missing items', { schema_version: 1 }],
    ['nonobject item', { schema_version: 2, items: [3] }],
    ['missing kind', { schema_version: 2, items: [{}] }],
    [
      'too many items',
      { schema_version: 2, items: Array.from({ length: 65 }, () => ({ kind: 'future' })) },
    ],
    ['too many bytes', { schema_version: 2, items: [{ kind: 'future', data: '界'.repeat(6000) }] }],
    [
      'too many nodes',
      {
        schema_version: 2,
        items: Array.from({ length: 64 }, () => ({ kind: 'future', data: [1, 2, 3, 4, 5, 6, 7] })),
      },
    ],
    [
      'too deep',
      {
        schema_version: 2,
        items: [{ kind: 'future', data: { a: { b: { c: { d: { e: 1 } } } } } }],
      },
    ],
    [
      'invalid known value',
      { ...reportedMeasurements, items: [{ ...reportedMeasurements.items[0], value: -2 }] },
    ],
    [
      'non-number known value',
      { ...reportedMeasurements, items: [{ ...reportedMeasurements.items[0], value: '62' }] },
    ],
    [
      'unknown known-kind unit',
      { ...reportedMeasurements, items: [{ ...reportedMeasurements.items[0], unit: 'stone' }] },
    ],
    [
      'non-string known unit',
      { ...reportedMeasurements, items: [{ ...reportedMeasurements.items[0], unit: ['kg'] }] },
    ],
    [
      'unbounded label',
      {
        ...reportedMeasurements,
        items: [{ ...reportedMeasurements.items[0], reported_label: 'x'.repeat(161) }],
      },
    ],
  ])('rejects %s measurements before writing any record', async (_, envelope) => {
    const { handlers, records } = makeHarness();
    const response = await handlers.POST(
      request('POST', 'dexa-results', 'access-a', [
        { id: eveningId },
        { id: morningId, reported_measurements: envelope },
      ]),
    );
    expect(response.status).toBe(400);
    expect(records.pushed).toEqual([]);
  });

  it('keeps explicit unknown units and labels without inference', async () => {
    const { handlers, records } = makeHarness();
    const envelope = {
      schema_version: 1,
      items: [
        {
          kind: 'muscle_mass',
          value: 33,
          unit: null,
          reported_label: 'Muscle Mass',
          reported_unit: 'unidentified',
        },
      ],
    };
    expect(
      (
        await handlers.POST(
          request('POST', 'dexa-results', 'access-a', [
            { id: morningId, weight_unit: 'lbs', reported_measurements: envelope },
          ]),
        )
      ).status,
    ).toBe(200);
    expect(records.pushed[0]?.records[0]?.reported_measurements).toEqual(envelope);
  });

  it('does not change other collections containing a field with the same name', async () => {
    const { handlers, records } = makeHarness();
    expect(
      (
        await handlers.POST(
          request('POST', 'daily-metrics', 'access-a', [
            { ...morning, reported_measurements: null },
          ]),
        )
      ).status,
    ).toBe(200);
    expect(records.pushed[0]?.records[0]?.reported_measurements).toBeNull();
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

  it.each([2147483648, Number.MAX_SAFE_INTEGER, 1e100, -1, 1.5, '8421', true, [], {}])(
    'rejects an invalid daily step count (%j) before persistence',
    async (steps) => {
      const { handlers, records } = makeHarness();
      const response = await handlers.POST(
        request('POST', 'daily-metrics', 'access-a', [{ ...morning, steps }]),
      );

      expect(response.status).toBe(400);
      await expect(response.json()).resolves.toEqual({ version: 1, error: 'invalid_records' });
      expect(records.pushed).toEqual([]);
    },
  );

  it.each([0, 8421, 2147483647, null, undefined])(
    'preserves a valid or absent daily step count (%j) and other native fields',
    async (steps) => {
      const { handlers, records } = makeHarness();
      const record = JSON.parse(JSON.stringify({ ...morning, steps }));
      const response = await handlers.POST(
        request('POST', 'daily-metrics', 'access-b', { records: [record] }),
      );

      expect(response.status).toBe(200);
      expect(records.pushed).toEqual([
        { subject: 'owner-b', collection: 'daily_metrics', records: [record] },
      ]);
    },
  );

  it('rejects a mixed daily batch without partially persisting its valid record', async () => {
    const { handlers, records } = makeHarness();
    const response = await handlers.POST(
      request('POST', 'daily-metrics', 'access-a', {
        records: [morning, { ...morning, id: eveningId, steps: 2147483648 }],
      }),
    );

    expect(response.status).toBe(400);
    expect(records.pushed).toEqual([]);
  });

  it('keeps daily step validation scoped to daily metrics', async () => {
    const { handlers, records } = makeHarness();
    const record = { id: morningId, steps: 'an unrelated extension field' };
    const response = await handlers.POST(request('POST', 'dexa-results', 'access-a', [record]));

    expect(response.status).toBe(200);
    expect(records.pushed[0]?.records).toEqual([record]);
  });
});
