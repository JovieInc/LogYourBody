/** @jest-environment node */

import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonNativeProductRecords } from './native-product-records-adapter';
import { NATIVE_PRODUCT_RECORD_COLLECTIONS } from '@/lib/ports/native-product-records';

function databaseWith(query: jest.Mock) {
  return { query } as unknown as NeonQueryFunction<false, false>;
}

function normalized(statement: unknown) {
  return String(statement).replace(/\s+/g, ' ').trim();
}

const morningId = '11111111-1111-4111-8111-111111111111';
const eveningId = '22222222-2222-4222-8222-222222222222';

const morning = {
  id: morningId,
  date: '2026-08-13T12:15:00.000Z',
  steps: 8421,
  notes: 'morning walk',
  extra_native_field: { cadence: 118 },
};

function row(
  record: { id: string } & Record<string, unknown>,
  extra: Partial<Record<string, unknown>> = {},
) {
  return {
    id: record.id,
    payload: record,
    deleted_at: null,
    updated_at: '2026-08-13T12:16:00.000Z',
    ...extra,
  };
}

describe('createNeonNativeProductRecords', () => {
  it.each([
    { steps_present: true },
    { steps_present: true, steps: null },
    { steps_present: true, steps: Number.NaN },
    { steps_present: true, steps: Number.POSITIVE_INFINITY },
    { steps_present: true, steps: -1 },
    { steps_present: true, steps: 0.5 },
    { steps_present: true, steps: 2147483648 },
    { steps_present: false },
    { steps_present: false, steps: 0 },
    { steps_present: null, steps: 0 },
    { steps_present: 'true', steps: 0 },
    { steps_present: undefined, steps: 0 },
  ])(
    'rejects invalid daily presence from an internal caller without a write: %p',
    async (value) => {
      const query = jest.fn().mockResolvedValueOnce([row({ id: morningId, ...value })]);
      const store = createNeonNativeProductRecords(databaseWith(query));
      await expect(
        store.push('owner-subject', 'daily_metrics', [{ id: morningId, ...value }]),
      ).resolves.toEqual({ records: [], rejected_ids: [morningId] });
      expect(query).not.toHaveBeenCalled();
    },
  );

  it.each([
    {},
    { steps: null },
    { steps: 0 },
    { steps: 8421 },
    { steps: 0, steps_present: true },
    { steps: 2147483647, steps_present: true },
    { steps: null, steps_present: false },
  ])('keeps raw legacy and explicit daily presence payloads distinct: %p', async (value) => {
    const record = { id: morningId, date: morning.date, ...value };
    const query = jest.fn().mockResolvedValueOnce([row(record)]);
    const store = createNeonNativeProductRecords(databaseWith(query));
    const result = await store.push('owner-subject', 'daily_metrics', [record]);
    expect(result.rejected_ids).toEqual([]);
    expect(JSON.parse(String(query.mock.calls[0][1][3]))).toEqual(record);
    expect(result.records[0]).toMatchObject(record);
    if (!Object.hasOwn(value, 'steps_present')) {
      expect(result.records[0]).not.toHaveProperty('steps_present');
    }
  });

  it('upserts jsonb payloads by client id without dropping extra native fields', async () => {
    const query = jest.fn().mockResolvedValueOnce([row(morning)]);
    const store = createNeonNativeProductRecords(databaseWith(query));

    const result = await store.push('owner-subject', 'daily_metrics', [morning]);

    expect(result.rejected_ids).toEqual([]);
    expect(result.records[0]?.id).toBe(morningId);
    expect(result.records[0]?.user_id).toBe('owner-subject');
    expect(result.records[0]?.extra_native_field).toEqual({ cadence: 118 });
    expect(result.records[0]?.steps).toBe(8421);

    const sql = normalized(query.mock.calls[0]?.[0]);
    expect(sql).toContain('insert into public.native_records');
    expect(sql).toContain('on conflict (collection, id) do update');
    expect(sql).toContain('where public.native_records.user_subject = excluded.user_subject');
    expect(query.mock.calls[0]?.[1]?.[0]).toBe('daily_metrics');
    expect(query.mock.calls[0]?.[1]?.[1]).toBe(morningId);
    expect(query.mock.calls[0]?.[1]?.[2]).toBe('owner-subject');
    expect(JSON.parse(String(query.mock.calls[0]?.[1]?.[3]))).toMatchObject({
      id: morningId,
      extra_native_field: { cadence: 118 },
    });
  });

  it('rejects client ids owned by another subject instead of rewriting them', async () => {
    const query = jest.fn().mockResolvedValue([]);
    const store = createNeonNativeProductRecords(databaseWith(query));

    await expect(store.push('owner-subject', 'daily_metrics', [morning])).resolves.toEqual({
      records: [],
      rejected_ids: [morningId],
    });
  });

  it('inserts training sets once without accepting caller-owned metadata', async () => {
    const set = {
      id: morningId,
      record_type: 'set_log',
      sessionId: eveningId,
      exerciseId: 'goblet_squat',
      setNumber: 1,
      reps: 10,
      loadKg: 20,
      rir: 3,
      completedAt: '2026-08-13T12:15:00.000Z',
    };
    const query = jest.fn().mockResolvedValueOnce([row(set)]);
    const store = createNeonNativeProductRecords(databaseWith(query));
    await expect(
      store.insertTrainingSet!('owner-subject', {
        ...set,
        user_id: 'other-subject',
        deleted_at: '2026-01-01',
        server_updated_at: '2026-01-01',
      }),
    ).resolves.toMatchObject({ ...set, user_id: 'owner-subject', deleted_at: null });
    expect(query).toHaveBeenCalledTimes(1);
    expect(normalized(query.mock.calls[0][0])).toContain('on conflict (collection, id) do nothing');
    expect(normalized(query.mock.calls[0][0])).toContain(
      "values ('logged_sets', $1, $2, $3::jsonb",
    );
    expect(query.mock.calls[0][1]).toEqual([morningId, 'owner-subject', JSON.stringify(set)]);
  });

  it('reads the existing owned training set after an insert conflict without changing its payload', async () => {
    const original = { id: morningId, record_type: 'set_log', reps: 10, loadKg: 20 };
    const query = jest
      .fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([row(original)]);
    const store = createNeonNativeProductRecords(databaseWith(query));
    const result = await store.insertTrainingSet!('owner-subject', {
      ...original,
      reps: 8,
      loadKg: 25,
    });
    expect(result).toMatchObject({ ...original, server_updated_at: '2026-08-13T12:16:00.000Z' });
    expect(query).toHaveBeenCalledTimes(2);
    expect(normalized(query.mock.calls[0][0])).toContain('on conflict (collection, id) do nothing');
    expect(normalized(query.mock.calls[1][0])).toContain(
      "where collection = 'logged_sets' and id = $1 and user_subject = $2 and deleted_at is null",
    );
    expect(query.mock.calls[1][1]).toEqual([morningId, 'owner-subject']);
  });

  it('rejects training set conflicts with no owned active row instead of reviving or taking over a row', async () => {
    const query = jest.fn().mockResolvedValue([]);
    const store = createNeonNativeProductRecords(databaseWith(query));
    await expect(
      store.insertTrainingSet!('owner-subject', {
        id: morningId,
        record_type: 'set_log',
        reps: 10,
      }),
    ).resolves.toBeNull();
    expect(query).toHaveBeenCalledTimes(2);
    expect(normalized(query.mock.calls[1][0])).toContain(
      'user_subject = $2 and deleted_at is null',
    );
    expect(query.mock.calls[1][1]).toEqual([morningId, 'owner-subject']);
  });

  it('rejects an explicit null DEXA payload even for an internal caller', async () => {
    const query = jest.fn();
    const store = createNeonNativeProductRecords(databaseWith(query));
    await expect(
      store.push('owner-subject', 'dexa_results', [{ id: morningId, reported_measurements: null }]),
    ).resolves.toEqual({ records: [], rejected_ids: [morningId] });
    expect(query).not.toHaveBeenCalled();
  });

  it('retains an uninterpreted future envelope in both database parameters and returned records', async () => {
    const envelope = {
      schema_version: 2,
      items: [{ kind: 'future', payload: { observed: 'unknown' } }],
    };
    const input = { id: morningId, reported_measurements: envelope };
    const query = jest.fn().mockResolvedValue([row(input)]);
    const store = createNeonNativeProductRecords(databaseWith(query));
    const result = await store.push('owner-subject', 'dexa_results', [input]);
    expect(JSON.parse(String(query.mock.calls[0]?.[1]?.[3]))).toEqual(input);
    expect(result.records[0]?.reported_measurements).toEqual(envelope);
    expect(result.records[0]).not.toHaveProperty('muscle_mass');
  });

  it('pulls incrementally for the authenticated subject including tombstones', async () => {
    const query = jest
      .fn()
      .mockResolvedValue([
        row(morning),
        row({ id: eveningId }, { deleted_at: '2026-08-13T23:50:00.000Z' }),
      ]);
    const store = createNeonNativeProductRecords(databaseWith(query));

    const result = await store.pull('owner-subject', 'daily_metrics', {
      since: '2026-08-13T00:00:00.000Z',
      after_id: null,
      limit: 200,
    });

    expect(normalized(query.mock.calls[0]?.[0])).toContain(
      'where user_subject = $1 and collection = $2',
    );
    expect(query.mock.calls[0]?.[1]).toEqual([
      'owner-subject',
      'daily_metrics',
      '2026-08-13T00:00:00.000Z',
      200,
    ]);
    expect(result.deleted_ids).toEqual([eveningId]);
    expect(result.records[0]?.user_id).toBe('owner-subject');
  });

  it('tombstones deletes by owner subject and collection', async () => {
    const query = jest.fn().mockResolvedValue([{ id: morningId }]);
    const store = createNeonNativeProductRecords(databaseWith(query));

    await expect(store.remove('owner-subject', 'daily_metrics', [morningId])).resolves.toEqual({
      deleted_ids: [morningId],
    });
    expect(normalized(query.mock.calls[0]?.[0])).toContain(
      'where user_subject = $1 and collection = $2 and id = any($3::uuid[])',
    );
    expect(query.mock.calls[0]?.[1]).toEqual(['owner-subject', 'daily_metrics', [morningId]]);
  });

  it('ends active GLP-1 medications only for the authenticated subject', async () => {
    const query = jest.fn().mockResolvedValue([{ id: morningId }]);
    const store = createNeonNativeProductRecords(databaseWith(query));

    await expect(
      store.endActiveGlp1Medications('owner-subject', '2026-08-13T18:00:00.000Z'),
    ).resolves.toEqual({ updated: 1 });

    const sql = normalized(query.mock.calls[0]?.[0]);
    expect(sql).toContain("collection = 'glp1_medications'");
    expect(sql).toContain('where user_subject = $1');
    expect(query.mock.calls[0]?.[1]).toEqual(['owner-subject', '2026-08-13T18:00:00.000Z']);
  });

  it('deletes every native record for the subject during account deletion', async () => {
    const query = jest.fn().mockResolvedValue([]);
    const store = createNeonNativeProductRecords(databaseWith(query));

    await store.deleteAllForSubject('owner-subject');

    expect(normalized(query.mock.calls[0]?.[0])).toBe(
      'delete from public.native_records where user_subject = $1',
    );
    expect(query.mock.calls[0]?.[1]).toEqual(['owner-subject']);
  });

  it('exports all eight owned collections without a sync-page cap or opaque-payload loss', async () => {
    const rows = NATIVE_PRODUCT_RECORD_COLLECTIONS.flatMap((collection) =>
      Array.from({ length: 501 }, (_, index) => ({
        ...row({
          id: `${collection}-${index}`,
          future_field: { value: index, nested: [null, false, 0] },
          photo_url: 'https://example.com/photo.jpg',
          user_id: 'spoofed-owner',
        }),
        collection,
      })),
    );
    const query = jest.fn().mockResolvedValue(rows);
    const result = await createNeonNativeProductRecords(databaseWith(query)).listAll('owner-a');
    for (const collection of NATIVE_PRODUCT_RECORD_COLLECTIONS) {
      expect(result[collection]).toHaveLength(501);
      expect(result[collection][500]).toMatchObject({
        id: `${collection}-500`,
        user_id: 'owner-a',
        deleted_at: null,
        future_field: { value: 500, nested: [null, false, 0] },
        photo_url: 'https://example.com/photo.jpg',
      });
    }
    const sql = normalized(query.mock.calls[0][0]);
    expect(sql).toContain('where user_subject = $1 and deleted_at is null');
    expect(sql).not.toMatch(/\blimit\b/i);
    expect(query.mock.calls[0][1]).toEqual(['owner-a']);
    expect(query).toHaveBeenCalledTimes(1);
  });
});

describe('admitted daily step deletion', () => {
  const admission = { subject: 'owner-a', ownerId: morningId };
  const deletion = {
    record: {
      ...morning,
      user_id: 'forged-owner',
      steps_deletion: { schema_version: 1, deleted_at: 'forged' },
    },
    day_start: '2026-08-13T00:00:00Z',
    day_end: '2026-08-14T00:00:00Z',
    time_zone: 'UTC',
  };
  function transactionStore(results: unknown[][]) {
    // Neon queries are lazy; record descriptors, then execute one transaction.
    const query = jest.fn((sql, values) => ({ sql, values }));
    const transaction = jest.fn().mockResolvedValue([[], ...results]);
    const database = { query, transaction } as unknown as NeonQueryFunction<false, false>;
    return { store: createNeonNativeProductRecords(database), query, transaction };
  }

  it('places account admission before both marker statements and preserves the original non-step snapshot', async () => {
    const persisted = {
      ...morning,
      steps: null,
      steps_present: false,
      steps_deletion: { schema_version: 1, day_start: deletion.day_start },
    };
    const { store, query, transaction } = transactionStore([[row(persisted)], []]);
    const result = await store.accountMutations!.deleteDailySteps!(admission, [deletion]);
    expect(transaction).toHaveBeenCalledTimes(1);
    const statements = transaction.mock.calls[0][0];
    expect(statements).toHaveLength(3);
    expect(normalized(statements[0].sql)).toBe(
      'select public.lyb_native_account_admit($1, $2::uuid)',
    );
    expect(statements[0].values).toEqual(['owner-a', morningId]);
    expect(normalized(statements[1].sql)).toContain("values ('daily_metrics'");
    expect(normalized(statements[2].sql)).toContain('update public.native_records target');
    const submitted = JSON.parse(statements[1].values[2]);
    expect(submitted).toEqual(morning);
    expect(statements[1].values[1]).toBe('owner-a');
    expect(result.records).toEqual([
      {
        ...persisted,
        user_id: 'owner-a',
        deleted_at: null,
        server_updated_at: '2026-08-13T12:16:00.000Z',
      },
    ]);
    expect(result.rejected_ids).toEqual([]);
    expect(query).toHaveBeenCalledTimes(3);
  });

  it('reports rejected anchors and returns other saved same-day rows without fabricated success', async () => {
    const { store } = transactionStore([
      [],
      [],
      [row({ ...morning, id: eveningId, steps: null })],
      [row({ ...morning, steps: null })],
    ]);
    const result = await store.accountMutations!.deleteDailySteps!(admission, [
      deletion,
      { ...deletion, record: { ...deletion.record, id: eveningId } },
    ]);
    expect(result.rejected_ids).toEqual([morningId]);
    expect(result.records.map((record) => record.id)).toEqual([eveningId, morningId]);
  });

  it.each([
    { deletions: [] },
    { deletions: [deletion, deletion] },
    { deletions: [{ ...deletion, day_end: '2027-08-13T00:00:00Z' }] },
    { deletions: [{ ...deletion, time_zone: 'Invalid/Zone' }] },
  ])(
    'rejects invalid internal typed calls before constructing mutations: %p',
    async ({ deletions }) => {
      const { store, query, transaction } = transactionStore([]);
      await expect(store.accountMutations!.deleteDailySteps!(admission, deletions)).rejects.toThrow(
        'invalid_steps_deletion',
      );
      expect(query).not.toHaveBeenCalled();
      expect(transaction).not.toHaveBeenCalled();
    },
  );

  it('propagates an owner replacement rejection and never retries an unadmitted write', async () => {
    const { store, transaction, query } = transactionStore([]);
    transaction.mockRejectedValue({ code: 'LYB01' });
    await expect(
      store.accountMutations!.deleteDailySteps!(admission, [deletion]),
    ).rejects.toMatchObject({ code: 'account_changed' });
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(query).toHaveBeenCalledTimes(3);
  });

  it('strips forged marker metadata before daily POST while retaining notes and unrelated fields', async () => {
    const { store, transaction } = transactionStore([[row(morning)]]);
    await store.accountMutations!.push(admission, 'daily_metrics', [deletion.record]);
    const statements = transaction.mock.calls[0][0];
    expect(normalized(statements[0].sql)).toBe(
      'select public.lyb_native_account_admit($1, $2::uuid)',
    );
    expect(JSON.parse(statements[1].values[3])).toEqual(morning);
    expect(statements).toHaveLength(2);
  });
});
