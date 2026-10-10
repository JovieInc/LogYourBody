/** @jest-environment node */
import { createNeonTrainingRevisions } from './training-revisions-adapter';
import { revisionHarness, proposalBody, decisionBody } from '@/lib/training/revisions.testing';
import {
  createInitialTrainingProposal,
  decideInitialTrainingProposal,
} from '@/lib/training/revisions';
import type { NeonQueryFunction } from '@neondatabase/serverless';

async function fixture() {
  const h = revisionHarness();
  const input = {
    revisions: h.port,
    subject: 'owner',
    body: proposalBody,
    now: new Date('2026-10-10T12:00:00Z'),
  };
  const result = await createInitialTrainingProposal(input);
  if (result.kind !== 'stored') throw new Error(result.kind);
  const query = jest.fn();
  const adapter = createNeonTrainingRevisions({ query } as unknown as NeonQueryFunction<
    false,
    false
  >);
  return { ...h, input, query, adapter, stored: result.stored };
}
describe('Neon training revision runtime boundary', () => {
  it('uses owner parameters for pure context and proposal reads', async () => {
    const h = await fixture();
    h.query
      .mockResolvedValueOnce([{ context: h.context }])
      .mockResolvedValueOnce([{ stored: h.stored }]);
    expect(await h.adapter.readContext('owner')).toEqual(h.context);
    expect(await h.adapter.readProposal('owner', h.stored.proposal.id)).toEqual(h.stored);
    expect(h.query.mock.calls[0][1]).toEqual(['owner']);
    expect(h.query.mock.calls[1][1]).toEqual([h.stored.proposal.id, 'owner']);
    expect(h.query.mock.calls.every(([sql]) => sql.startsWith('select'))).toBe(true);
  });
  it.each(['foreign', 'malformed', 'mismatched receipt'])(
    'fails closed on %s stored payload',
    async (mode) => {
      const h = await fixture();
      const stored = JSON.parse(JSON.stringify(h.stored));
      if (mode === 'foreign') stored.proposal.actor.subject = 'another-owner';
      if (mode === 'malformed') stored.proposal.plan.sessions[0].exercises[0].sets = -2;
      if (mode === 'mismatched receipt') {
        stored.status = 'applied';
        stored.receipt = { status: 'applied' };
      }
      h.query.mockResolvedValue([{ stored }]);
      await expect(h.adapter.readProposal('owner', h.stored.proposal.id)).rejects.toThrow();
    },
  );
  it('rejects a decision receipt for another request instead of claiming success', async () => {
    const h = await fixture();
    const body = decisionBody(h.stored.proposal.id);
    await decideInitialTrainingProposal({ ...h.input, body });
    const call = jest.mocked(h.port.decide).mock.calls[0][0];
    h.query.mockResolvedValue([
      {
        result: {
          kind: 'decided',
          receipt: { ...h.stored.receipt, requestId: proposalBody.requestId },
        },
      },
    ]);
    await expect(h.adapter.decide(call)).rejects.toThrow('training_revision_receipt_mismatch');
  });
  it('uses exactly one command for durable decision, preserves original PG timestamp and typed conflicts', async () => {
    const h = await fixture();
    await decideInitialTrainingProposal({ ...h.input, body: decisionBody(h.stored.proposal.id) });
    const call = jest.mocked(h.port.decide).mock.calls[0][0];
    const receipt = { ...h.stored.receipt, decidedAt: '2026-10-10T12:00:00+00:00' };
    h.query
      .mockResolvedValueOnce([{ result: { kind: 'decided', receipt } }])
      .mockResolvedValueOnce([{ result: { kind: 'request_conflict' } }]);
    expect(await h.adapter.decide(call)).toEqual({ kind: 'decided', receipt });
    expect(await h.adapter.decide(call)).toEqual({ kind: 'request_conflict' });
    expect(h.query.mock.calls[0][1].slice(0, 2)).toEqual(['owner', 'apply']);
    expect(JSON.parse(h.query.mock.calls[0][1][2])).toEqual(call);
  });
  it('fails closed on missing migration or unknown command result without trying generic upsert', async () => {
    const h = await fixture();
    h.query.mockRejectedValueOnce(new Error('function missing'));
    await expect(h.adapter.revoke('owner')).rejects.toThrow('function missing');
    h.query.mockResolvedValueOnce([{ result: { kind: 'unknown' } }]);
    await expect(h.adapter.revoke('owner')).rejects.toThrow('training_revocation_not_committed');
    expect(h.query).toHaveBeenCalledTimes(2);
  });
  it('passes captured legacy context and fails if atomic admission refuses it', async () => {
    const h = await fixture();
    await decideInitialTrainingProposal({ ...h.input, body: decisionBody(h.stored.proposal.id) });
    const setup = h.stored.receipt!.setup!;
    h.query.mockResolvedValue([{ result: { kind: 'stale_context' } }]);
    await expect(h.adapter.storeLegacySetup('owner', setup, h.context)).rejects.toThrow(
      'training_enrollment_not_committed',
    );
    expect(JSON.parse(h.query.mock.calls[0][1][2])).toEqual({ setup, context: h.context });
  });
  it('exports only the authenticated owner through both ledger queries', async () => {
    const h = await fixture();
    h.query
      .mockResolvedValueOnce([{ stored: h.stored }])
      .mockResolvedValueOnce([{ payload: { id: 'owned-revision' } }]);
    expect(await h.adapter.exportForSubject('owner')).toEqual({
      proposals: [h.stored],
      revisions: [{ id: 'owned-revision' }],
    });
    h.query.mock.calls.forEach(([sql, values]) => {
      expect(sql).toContain('where user_subject=$1');
      expect(values).toEqual(['owner']);
    });
  });
});
