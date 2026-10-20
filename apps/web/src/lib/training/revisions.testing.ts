import type {
  TrainingRevisionsPort,
  TrainingRevisionContext,
} from '@/lib/ports/training-revisions';
import { MemoryTrainingRecords } from './memory-records.testing';
import { revisionReceiptSchema, type StoredTrainingProposal } from './revision-contract';

/** Domain/HTTP contract fake only. Real SQL races are tested by verify-training-revisions.py. */
export function revisionHarness() {
  const records = new MemoryTrainingRecords();
  const context: TrainingRevisionContext = {
    ownerId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    generation: 0,
    profileFingerprint: 'profile-v1',
    legacyFingerprint: 'empty',
    dateOfBirth: '1990-01-01',
    legacySetups: [],
    headRevision: null,
  };
  const proposals = new Map<string, StoredTrainingProposal>();
  const port: TrainingRevisionsPort = {
    readContext: jest.fn(async (subject) => (subject === 'owner' ? { ...context } : null)),
    readProposal: jest.fn(async (subject, id) =>
      subject === 'owner' ? (proposals.get(id) ?? null) : null,
    ),
    createProposal: jest.fn(async (input) => {
      const stored: StoredTrainingProposal = {
        proposal: input.proposal,
        requestHash: input.requestHash,
        status: 'proposed',
        receipt: null,
      };
      proposals.set(input.proposal.id, stored);
      return { kind: 'stored' as const, stored };
    }),
    decide: jest.fn(async (input) => {
      const stored = proposals.get(input.proposalId)!;
      if (stored.receipt)
        return stored.receipt.requestId === input.requestId &&
          stored.receipt.decision === input.decision
          ? { kind: 'decided' as const, receipt: stored.receipt }
          : { kind: 'already_decided' as const };
      const receipt = revisionReceiptSchema.parse({
        version: 1,
        proposalId: input.proposalId,
        requestId: input.requestId,
        decision: input.decision,
        status: input.decision === 'apply' ? 'applied' : 'rejected',
        actor: { kind: 'self', subject: input.subject },
        priorState: null,
        revisionId: input.decision === 'apply' ? input.revisionId : null,
        setup: input.decision === 'apply' ? input.setup : null,
        decidedAt: input.now,
      });
      if (input.decision === 'apply') {
        await records.push(input.subject, 'training_feedback', [
          { ...input.setup, record_type: 'program_setup' },
        ]);
        context.headRevision = input.revisionId;
      }
      stored.status = receipt.status;
      stored.receipt = receipt;
      return { kind: 'decided' as const, receipt };
    }),
    storeLegacySetup: jest.fn(async () => {}),
    revoke: jest.fn(async () => 0),
    exportForSubject: jest.fn(async () => ({ proposals: [...proposals.values()], revisions: [] })),
  };
  return { port, records, context, proposals };
}
export const proposalBody = {
  requestId: '11111111-1111-4111-8111-111111111111',
  expectedGeneration: 0,
  intent: {
    kind: 'initial_enrollment',
    adultConfirmed: true,
    safetyConfirmed: true,
    sessionsPerWeek: 2,
    equipment: 'dumbbells',
  },
  reason: 'Start the supported baseline after review',
};
export const decisionBody = (proposalId: string, decision: 'apply' | 'reject' = 'apply') => ({
  requestId: '22222222-2222-4222-8222-222222222222',
  proposalId,
  decision,
});
