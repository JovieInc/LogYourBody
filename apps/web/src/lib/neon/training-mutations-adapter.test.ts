/** @jest-environment node */
import type { NeonQueryFunction } from '@neondatabase/serverless';
import { createNeonTrainingMutations } from './training-mutations-adapter';
const ownerId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const setupId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const recordId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const admission = { ownerId, generation: 3, setupId, revisionId: null };
function fixture() {
  const query = jest.fn();
  const port = createNeonTrainingMutations({ query } as unknown as NeonQueryFunction<false, false>);
  return { query, port };
}
describe('training mutation database boundary', () => {
  it('captures owner incarnation and the canonical supported setup without writing', async () => {
    const { query, port } = fixture();
    query.mockResolvedValue([
      {
        context: {
          ownerId,
          generation: 3,
          headRevision: null,
          legacySetups: [
            {
              id: setupId,
              consentVersion: 'hypertrophy-coach-v1',
              adultConfirmed: true,
              safetyConfirmed: true,
              sessionsPerWeek: 2,
              equipment: 'dumbbells',
              startedAt: '2026-01-01T00:00:00Z',
            },
          ],
        },
      },
    ]);
    expect(await port.captureAdmission('owner')).toEqual(admission);
    expect(query.mock.calls).toEqual([
      ['select public.training_revision_context($1) as context', ['owner']],
    ]);
  });
  it('fails closed when the deployed context lacks incarnation', async () => {
    const { query, port } = fixture();
    query.mockResolvedValue([{ context: { generation: 0, headRevision: null, legacySetups: [] } }]);
    await expect(port.captureAdmission('owner')).rejects.toThrow();
  });
  it.each(['owner_missing', 'stale_admission', 'session_conflict', 'record_conflict'])(
    'returns %s without a generic writer fallback',
    async (kind) => {
      const { query, port } = fixture();
      query.mockResolvedValue([{ result: { kind } }]);
      expect(
        await port.commit({
          subject: 'owner',
          admission,
          action: 'set_insert',
          record: { id: recordId },
        }),
      ).toEqual({ kind });
      expect(query).toHaveBeenCalledTimes(1);
      expect(query.mock.calls[0][0]).toContain('training_mutation_command');
      expect(JSON.parse(query.mock.calls[0][1][2])).toEqual(admission);
    },
  );
  it.each(['wrong owner', 'wrong record', 'tombstone'])(
    'rejects a saved response with %s',
    async (mode) => {
      const { query, port } = fixture();
      query.mockResolvedValue([
        {
          result: {
            kind: 'saved',
            record: {
              id: mode === 'wrong record' ? setupId : recordId,
              user_id: mode === 'wrong owner' ? 'other' : 'owner',
              deleted_at: mode === 'tombstone' ? '2026-01-01' : null,
              server_updated_at: '2026-01-01T00:00:00Z',
            },
          },
        },
      ]);
      await expect(
        port.commit({
          subject: 'owner',
          admission,
          action: 'set_insert',
          record: { id: recordId },
        }),
      ).rejects.toThrow();
    },
  );
});
