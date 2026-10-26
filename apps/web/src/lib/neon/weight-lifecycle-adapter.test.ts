/** @jest-environment node */

import type { NeonQueryFunction } from '@neondatabase/serverless';
import type { CreateWeightCommand } from '@/lib/metrics/weight-lifecycle';
import { createNeonWeightLifecycle } from './weight-lifecycle-adapter';

const SUBJECT = 'subject-a';
const OWNER = '11111111-1111-4111-8111-111111111111';
const RECORD = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const OP = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

function databaseWith(query: jest.Mock) {
  const database = {
    query,
    transaction: jest.fn(async (queries: Array<Promise<unknown>>) => {
      const results = [];
      for (const item of queries) results.push(await item);
      return results;
    }),
  };
  return database as unknown as NeonQueryFunction<false, false>;
}

const command: CreateWeightCommand = {
  operation_id: OP,
  record_id: RECORD,
  request_hash: 'hash',
  weight_kg: '81.646627',
  input_value: '180',
  input_unit: 'lb',
  measured_at: '2026-10-13T08:00:00-07:00',
  utc_offset_minutes: -420,
  local_date: '2026-10-13',
  iana_zone: 'America/Los_Angeles',
  provenance: {
    actor: 'agent',
    conversion: 'lb*0.45359237',
    constant: '0.45359237',
    canonical_kg: '81.646627',
  },
};

const receipt = {
  operation_id: OP,
  action: 'create',
  record: { id: RECORD, revision: 1 },
  cloud: { status: 'committed', server_updated_at: '2026-10-13T15:00:00.000Z' },
  device: { healthkit: 'not_claimed' },
};

describe('createNeonWeightLifecycle', () => {
  it('calls the lifecycle function and refuses a receipt that claims a HealthKit write', async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce([{ result: { outcome: 'committed', receipt } }])
      .mockResolvedValueOnce([]);
    const store = createNeonWeightLifecycle(databaseWith(query));

    await expect(
      store.create(SUBJECT, OWNER, command, new Date('2026-10-13T15:00:00.000Z')),
    ).resolves.toMatchObject({
      ok: true,
      replayed: false,
      receipt,
    });
    const statement = String(query.mock.calls[0]?.[0]);
    expect(statement).toContain('public.weight_lifecycle_command');
    expect(JSON.parse(String(query.mock.calls[0]?.[1]?.[2]))).toMatchObject({
      action: 'create',
      weight_kg: '81.646627',
      operation_id: OP,
    });

    query.mockReset();
    query
      .mockResolvedValueOnce([
        {
          result: {
            outcome: 'committed',
            receipt: { ...receipt, device: { healthkit: 'saved' } },
          },
        },
      ])
      .mockResolvedValueOnce([]);
    await expect(
      store.create(SUBJECT, OWNER, command, new Date('2026-10-13T15:00:00.000Z')),
    ).resolves.toMatchObject({ ok: false, reason: 'healthkit_not_claimed' });
  });

  it('reads a grant before listing live rows and can include one tombstone by id', async () => {
    const query = jest.fn().mockResolvedValueOnce([
      {
        owner_id: OWNER,
        grant_subject: SUBJECT,
        connected: true,
        consent_granted: true,
        entitled: true,
        revoked_at: null,
        deleted_at: null,
      },
    ]);
    query.mockResolvedValueOnce([]);
    query.mockResolvedValueOnce([]);
    const store = createNeonWeightLifecycle(databaseWith(query));

    await expect(
      store.list(SUBJECT, { limit: 50, cursor: null, record_id: null }),
    ).resolves.toMatchObject({ ok: true, records: [] });
    const listSql = String(query.mock.calls[1]?.[0]).replace(/\s+/g, ' ');
    expect(listSql).toContain('deleted_at is null');
    expect(listSql).toContain('order by measured_at desc, id desc');
    expect(String(query.mock.calls[0]?.[0])).toContain('metrics_agent_grants');
  });
});
