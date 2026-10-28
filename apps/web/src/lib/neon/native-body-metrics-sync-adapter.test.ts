/** @jest-environment node */

import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonNativeBodyMetricsSync } from './native-body-metrics-sync-adapter';
import type { NativeBodyMetricPushInput } from '@/lib/ports/native-body-metrics-sync';

function databaseWith(query: jest.Mock) {
  return { query } as unknown as NeonQueryFunction<false, false>;
}

function normalized(statement: unknown) {
  return String(statement).replace(/\s+/g, ' ').trim();
}

const morning: NativeBodyMetricPushInput = {
  id: '11111111-1111-4111-8111-111111111111',
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

const evening: NativeBodyMetricPushInput = {
  ...morning,
  id: '22222222-2222-4222-8222-222222222222',
  date: '2026-08-13T23:40:00.000Z',
  weight: 80.1,
  bone_mass: 3.11,
  notes: 'evening',
  data_source: 'manual',
  source_metadata: {},
  created_at: '2026-08-13T23:40:00.000Z',
  updated_at: '2026-08-13T23:40:00.000Z',
};

function row(record: NativeBodyMetricPushInput, extra: Partial<Record<string, unknown>> = {}) {
  return {
    id: record.id,
    date: record.local_date,
    local_date: record.local_date,
    measured_at: record.date,
    weight: record.weight,
    weight_unit: record.weight_unit,
    waist: record.waist_circumference,
    hip: record.hip_circumference,
    waist_unit: record.waist_unit,
    body_fat_percentage: record.body_fat_percentage,
    body_fat_method: record.body_fat_method,
    muscle_mass: record.muscle_mass,
    bone_mass: record.bone_mass,
    photo_url: record.photo_url,
    notes: record.notes,
    data_source: record.data_source,
    source_metadata: record.source_metadata,
    client_created_at: record.created_at,
    client_updated_at: record.updated_at,
    deleted_at: null,
    updated_at: '2026-08-13T23:41:00.000Z',
    ...extra,
  };
}

describe('createNeonNativeBodyMetricsSync', () => {
  it('upserts same-day native records by client id and stores bone mass plus timestamps', async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce([row(morning)])
      .mockResolvedValueOnce([row(evening)]);
    const store = createNeonNativeBodyMetricsSync(databaseWith(query));

    const result = await store.push('owner-subject', [morning, evening]);

    expect(result.rejected_ids).toEqual([]);
    expect(result.records).toHaveLength(2);
    expect(result.records[0]?.bone_mass).toBe(3.11);
    expect(result.records[0]?.date).toBe(morning.date);
    expect(result.records[0]?.local_date).toBe('2026-08-13');
    expect(result.records[1]?.id).toBe(evening.id);

    const firstSql = normalized(query.mock.calls[0]?.[0]);
    expect(firstSql).toContain('on conflict (id) do update');
    expect(firstSql).toContain('bone_mass');
    expect(firstSql).toContain('measured_at');
    expect(firstSql).toContain('local_date');
    expect(firstSql).toContain('client_created_at');
    expect(firstSql).toContain('where public.body_metrics.user_subject = excluded.user_subject');
    expect(firstSql).not.toContain('on conflict (user_subject, date)');
    expect(query.mock.calls[0]?.[1]?.[0]).toBe(morning.id);
    expect(query.mock.calls[0]?.[1]?.[1]).toBe('owner-subject');
    expect(query.mock.calls[0]?.[1]?.[9]).toBe(3.11);
    expect(query.mock.calls[1]?.[1]?.[0]).toBe(evening.id);
  });

  it('rejects client ids owned by another subject instead of rewriting them', async () => {
    const query = jest.fn().mockResolvedValue([]);
    const store = createNeonNativeBodyMetricsSync(databaseWith(query));

    await expect(store.push('owner-subject', [morning])).resolves.toEqual({
      records: [],
      rejected_ids: [morning.id],
    });
  });

  it('pulls incrementally for the authenticated subject including tombstones', async () => {
    const query = jest.fn().mockResolvedValue([
      row(morning),
      row(evening, { deleted_at: '2026-08-13T23:50:00.000Z' }),
    ]);
    const store = createNeonNativeBodyMetricsSync(databaseWith(query));

    const result = await store.pull('owner-subject', {
      since: '2026-08-13T00:00:00.000Z',
      after_id: null,
      limit: 200,
    });

    expect(normalized(query.mock.calls[0]?.[0])).toContain('where user_subject = $1');
    expect(normalized(query.mock.calls[0]?.[0])).toContain('updated_at >= $2::timestamptz');
    expect(query.mock.calls[0]?.[1]).toEqual(['owner-subject', '2026-08-13T00:00:00.000Z', 200]);
    expect(result.deleted_ids).toEqual([evening.id]);
    expect(result.records[1]?.deleted_at).toBe('2026-08-13T23:50:00.000Z');
  });

  it('tombstones deletes by owner subject and is idempotent', async () => {
    const query = jest.fn().mockResolvedValue([{ id: morning.id }]);
    const store = createNeonNativeBodyMetricsSync(databaseWith(query));

    await expect(store.remove('owner-subject', [morning.id])).resolves.toEqual({
      deleted_ids: [morning.id],
    });
    expect(normalized(query.mock.calls[0]?.[0])).toContain(
      'set deleted_at = coalesce(deleted_at, now())',
    );
    expect(normalized(query.mock.calls[0]?.[0])).toContain(
      'where user_subject = $1 and id = any($2::uuid[])',
    );
    expect(query.mock.calls[0]?.[1]).toEqual(['owner-subject', [morning.id]]);
  });
});
