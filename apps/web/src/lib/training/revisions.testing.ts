import type {
  TrainingRevisionsPort,
  TrainingRevisionContext,
} from '@/lib/ports/training-revisions';
import { MemoryTrainingRecords } from './memory-records.testing';
import {
  revisionReceiptSchema,
  storedTrainingRevisionSchema,
  type StoredTrainingProposal,
  type StoredTrainingRevision,
} from './revision-contract';

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
  const revisions = new Map<string, StoredTrainingRevision>();
  const port: TrainingRevisionsPort = {
    readContext: jest.fn(async (subject) => (subject === 'owner' ? { ...context } : null)),
    readProposal: jest.fn(async (subject, id) =>
      subject === 'owner' ? (proposals.get(id) ?? null) : null,
    ),
    readHeadRevision: jest.fn(async (subject) =>
      subject === 'owner' && context.headRevision
        ? (revisions.get(context.headRevision) ?? null)
        : null,
    ),
    createProposal: jest.fn(async (input) => {
      // Mirrors the production function: an edit may only build on the live head.
      const baseRevision = input.proposal.baseRevision;
      if (baseRevision === null) {
        if (context.headRevision) return { kind: 'program_already_enrolled' as const };
      } else {
        if (!context.headRevision) return { kind: 'program_not_enrolled' as const };
        if (context.headRevision !== baseRevision)
          return { kind: 'revision_conflict' as const };
      }
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
      const priorState = context.headRevision;
      if (input.decision === 'apply') {
        if (input.baseRevision === null) {
          if (priorState) return { kind: 'revision_conflict' as const };
        } else if (priorState !== input.baseRevision) {
          return { kind: 'revision_conflict' as const };
        }
      }
      const receipt = revisionReceiptSchema.parse({
        version: 1,
        proposalId: input.proposalId,
        requestId: input.requestId,
        decision: input.decision,
        status: input.decision === 'apply' ? 'applied' : 'rejected',
        actor: { kind: 'self', subject: input.subject },
        priorState: input.decision === 'apply' ? priorState : null,
        revisionId: input.decision === 'apply' ? input.revisionId : null,
        setup: input.decision === 'apply' ? input.setup : null,
        decidedAt: input.now,
      });
      if (input.decision === 'apply') {
        const revision = storedTrainingRevisionSchema.parse({
          version: 1,
          id: input.revisionId,
          proposal: stored.proposal,
          baseRevision: input.baseRevision,
          layout: input.layout,
          setup:
            input.setup ??
            (revisions.get(input.baseRevision ?? '')?.setup as unknown),
          activatedAt: input.now,
        });
        revisions.set(revision.id, revision);
        if (input.setup) {
          await records.push(input.subject, 'training_feedback', [
            { ...input.setup, record_type: 'program_setup' },
          ]);
        }
        if (input.layout) {
          // Rebind the enrolled setup to the new head revision, mirroring the
          // production command's in-transaction programRevisionId update.
          const feedback = await records.pull(input.subject, 'training_feedback');
          const enrolled = feedback.records.find(
            (row) =>
              row.record_type === 'program_setup' &&
              row.id === revision.setup.id &&
              row.deleted_at === null,
          );
          if (enrolled)
            await records.push(input.subject, 'training_feedback', [
              { ...enrolled, programRevisionId: revision.id },
            ]);
          const existing = await records.pull(input.subject, 'training_sessions');
          const stale = existing.records
            .filter(
              (row) =>
                row.record_type === 'plan_layout' &&
                (row as { programSetupId?: string }).programSetupId === revision.setup.id &&
                row.deleted_at === null,
            )
            .map((row) => row.id);
          if (stale.length)
            await records.remove(input.subject, 'training_sessions', stale);
          await records.push(input.subject, 'training_sessions', [
            {
              id: revision.id,
              record_type: 'plan_layout',
              programSetupId: revision.setup.id,
              programRevisionId: revision.id,
              layout: input.layout,
              createdAt: input.now,
            },
          ]);
        }
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
  return { port, records, context, proposals, revisions };
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
export const planEditBody = (
  operations: unknown[],
  requestId = '33333333-3333-4333-8333-333333333333',
) => ({
  requestId,
  expectedGeneration: 0,
  intent: { kind: 'plan_edit', operations },
  reason: 'Adjust the reviewed plan through typed operations',
});
export const decisionBody = (proposalId: string, decision: 'apply' | 'reject' = 'apply') => ({
  requestId: '22222222-2222-4222-8222-222222222222',
  proposalId,
  decision,
});
