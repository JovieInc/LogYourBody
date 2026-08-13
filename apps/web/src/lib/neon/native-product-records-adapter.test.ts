/** @jest-environment node */

import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonNativeProductRecords } from './native-product-records-adapter';

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

  it('pulls incrementally for the authenticated subject including tombstones', async () => {
    const query = jest.fn().mockResolvedValue([
      row(morning),
      row({ id: eveningId }, { deleted_at: '2026-08-13T23:50:00.000Z' }),
    ]);
    const store = createNeonNativeProductRecords(databaseWith(query));

    const result = await store.pull('owner-subject', 'daily_metrics', {
      since: '2026-08-13T00:00:00.000Z',
      after_id: null,
      limit: 200,
    });

    expect(normalized(query.mock.calls[0]?.[0])).toContain('where user_subject = $1 and collection = $2');
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
});
