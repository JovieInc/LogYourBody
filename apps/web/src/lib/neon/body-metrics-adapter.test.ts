/** @jest-environment node */

import type { NeonQueryFunction } from '@neondatabase/serverless';
import {
  createNeonBodyMetricsExportReader,
  createNeonBodyMetricsStore,
} from './body-metrics-adapter';

function databaseWith(query: jest.Mock) {
  return { query } as unknown as NeonQueryFunction<false, false>;
}

function normalized(statement: unknown) {
  return String(statement).replace(/\s+/g, ' ').trim();
}

describe('createNeonBodyMetricsStore', () => {
  it('lists only live rows for the authenticated subject', async () => {
    const query = jest.fn().mockResolvedValue([]);
    const store = createNeonBodyMetricsStore(databaseWith(query));

    await store.list('owner-subject', 30);

    expect(normalized(query.mock.calls[0]?.[0])).toContain(
      'where user_subject = $1 and deleted_at is null',
    );
    expect(query.mock.calls[0]?.[1]).toEqual(['owner-subject', 30]);
  });

  it('upserts web daily rows without colliding with native same-day identity', async () => {
    const query = jest.fn().mockResolvedValue([{ id: 'web-row' }]);
    const store = createNeonBodyMetricsStore(databaseWith(query));

    await store.upsert('owner-subject', {
      date: '2026-08-13',
      weight: 80,
      weight_unit: 'kg',
      body_fat_percentage: null,
      body_fat_method: null,
      muscle_mass: null,
      waist: null,
      neck: null,
      hip: null,
      notes: null,
      photo_url: null,
      data_source: 'manual',
      source_metadata: {},
    });

    const sql = normalized(query.mock.calls[0]?.[0]);
    expect(sql).toContain('origin,');
    expect(sql).toContain("'web'");
    expect(sql).toContain(
      "on conflict (user_subject, date) where origin = 'web' and deleted_at is null",
    );
    expect(sql).not.toContain('on conflict (user_subject, date) do update');
    expect(query.mock.calls[0]?.[1]?.[0]).toBe('owner-subject');
  });
});

describe('createNeonBodyMetricsExportReader', () => {
  it('returns all projected rows with provenance, nulls and zero values intact', async () => {
    const rows = Array.from({ length: 137 }, (_, index) => ({
      id: `metric-${index}`,
      user_subject: 'owner-a',
      date: '2026-10-10',
      weight: index === 0 ? 0 : null,
      source_metadata: { reported: { value: index, unit: 'kg' } },
      photo_url: index === 0 ? 'https://example.com/photo.jpg' : null,
    }));
    const query = jest.fn().mockResolvedValue(rows);
    const result = await createNeonBodyMetricsExportReader(databaseWith(query)).listAll('owner-a');

    expect(result).toEqual(rows);
    expect(result).toHaveLength(137);
    expect(query.mock.calls[0][1]).toEqual(['owner-a']);
    const sql = normalized(query.mock.calls[0][0]);
    expect(sql).toContain('where user_subject = $1 and deleted_at is null');
    expect(sql).toContain('order by date desc, created_at desc, id desc');
    expect(sql).not.toMatch(/\blimit\b/i);

    const historyQuery = jest.fn().mockResolvedValue([]);
    await createNeonBodyMetricsStore(databaseWith(historyQuery)).list('owner-a', 500);
    const historySql = normalized(historyQuery.mock.calls[0][0]);
    expect(sql.split(' from public.body_metrics')[0]).toBe(
      historySql.split(' from public.body_metrics')[0],
    );
    expect(historyQuery.mock.calls[0][1]).toEqual(['owner-a', 100]);
  });
});
