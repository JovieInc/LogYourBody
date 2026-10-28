jest.mock('@neondatabase/serverless', () => ({
  neon: jest.fn(),
}));

import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonGymRegistry } from './gym-registry-adapter';

type Call = { sql: string; params: readonly unknown[] };

function database(rows: unknown[]) {
  const calls: Call[] = [];
  const query = (sql: string, params: readonly unknown[] = []) => {
    const promise = Promise.resolve(rows) as Promise<unknown> & { call: Call };
    promise.call = { sql: sql.replace(/\s+/g, ' ').trim(), params };
    return promise;
  };
  const fake = {
    query,
    transaction: (queries: Array<Promise<unknown> & { call: Call }>) => {
      queries.forEach((queryPromise) => calls.push(queryPromise.call));
      return Promise.all(queries);
    },
  };
  return { calls, fake: fake as unknown as NeonQueryFunction<false, false> };
}

const row = {
  id: '11111111-1111-4111-8111-111111111111',
  name: 'North',
  region: 'north',
  equipment: ['dumbbells'],
  preferred_machines: ['lat pulldown'],
  updated_at: '2026-10-25T12:00:00.000Z',
  deleted_at: null,
};

describe('gym registry sync', () => {
  it('sets the caller subject before listing gyms', async () => {
    const { calls, fake } = database([row]);
    const records = await createNeonGymRegistry(fake).list('user-a');

    expect(calls.map((call) => call.sql)).toEqual([
      "select set_config('app.current_user_subject', $1, true)",
      'select id, name, region, equipment, preferred_machines, updated_at, deleted_at from public.lyb_list_gyms()',
    ]);
    expect(calls[0]?.params).toEqual(['user-a']);
    expect(records).toEqual([
      {
        id: row.id,
        name: 'North',
        region: 'north',
        equipment: ['dumbbells'],
        preferredMachines: ['lat pulldown'],
        updatedAt: '2026-10-25T12:00:00.000Z',
        deletedAt: null,
      },
    ]);
  });

  it('upserts and deletes only through the subject-scoped functions', async () => {
    const { calls, fake } = database([row]);
    const registry = createNeonGymRegistry(fake);
    await registry.upsert('user-a', {
      id: row.id,
      name: 'North',
      region: 'north',
      equipment: ['dumbbells'],
      preferredMachines: ['lat pulldown'],
    });
    await registry.remove('user-a', row.id);

    expect(calls.map((call) => call.sql)).toEqual([
      "select set_config('app.current_user_subject', $1, true)",
      'select id, name, region, equipment, preferred_machines, updated_at, deleted_at from public.lyb_upsert_gym($1::uuid, $2, $3, $4::text[], $5::text[])',
      "select set_config('app.current_user_subject', $1, true)",
      'select id, name, region, equipment, preferred_machines, updated_at, deleted_at from public.lyb_delete_gym($1::uuid)',
    ]);
    expect(calls[0]?.params).toEqual(['user-a']);
    expect(calls[1]?.params).toEqual([row.id, 'North', 'north', ['dumbbells'], ['lat pulldown']]);
    expect(calls[3]?.params).toEqual([row.id]);
  });
});
