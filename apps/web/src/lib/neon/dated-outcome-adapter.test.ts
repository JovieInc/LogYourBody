/** @jest-environment node */
import { createNeonDatedOutcomes } from './dated-outcome-adapter';
import type { NeonQueryFunction } from '@neondatabase/serverless';

describe('Neon dated outcome admission', () => {
  it('guards the outcome and recompute write in the same transaction', async () => {
    const query = jest.fn().mockImplementation((sql, params) => ({ sql, params }));
    const transaction = jest.fn().mockResolvedValue([[], [{ result: { kind: 'saved' } }]]);
    const adapter = createNeonDatedOutcomes({ query, transaction } as unknown as NeonQueryFunction<
      false,
      false
    >);
    const admission = { subject: 'owner', ownerId: '26800000-0000-4000-8000-000000000002' };
    await adapter.save(admission, {
      requestId: '26800000-0000-4000-8000-000000000001',
      previousRevision: null,
      value: {
        outcome: { metric: 'weight_kg', targetValue: 80 },
        outcomeDate: '2027-04-01',
        constraints: { availability: {}, travel: [], maintenance: [] },
      },
    });
    const [queries] = transaction.mock.calls[0];
    expect(queries[0].sql).toContain('lyb_native_account_admit');
    expect(queries[0].params).toEqual(['owner', admission.ownerId]);
    expect(queries[1].sql).toContain('lyb_save_dated_outcome');
    expect(JSON.parse(queries[1].params[2])).toEqual({
      goal: 'weight_kg: 80',
      goalDate: '2027-04-01T00:00:00Z',
    });
  });
  it('uses subject-scoped reads and never creates an empty outcome', async () => {
    const query = jest.fn().mockResolvedValue([]);
    const adapter = createNeonDatedOutcomes({ query } as unknown as NeonQueryFunction<
      false,
      false
    >);
    expect(await adapter.read('owner')).toBeNull();
    expect(query.mock.calls[0][0]).toContain('identity_subject = $1');
    expect(query.mock.calls[0][1]).toEqual(['owner']);
  });
});
