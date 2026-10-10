import 'server-only';
import { neon, type NeonQueryFunction } from '@neondatabase/serverless';
import { z } from 'zod';
import type { TrainingRevisionsPort, RevisionConflict } from '@/lib/ports/training-revisions';
import {
  revisionContextSchema,
  storedProposalSchema,
  revisionReceiptSchema,
} from '@/lib/training/revision-contract';

const contextSchema = revisionContextSchema.extend({
  ownerId: z.string().uuid(),
  dateOfBirth: z.unknown(),
  legacySetups: z.array(z.unknown()),
  headRevision: z.string().uuid().nullable(),
});
const conflictSchema = z.enum([
  'owner_missing',
  'stale_context',
  'revision_conflict',
  'request_conflict',
  'already_decided',
  'proposal_not_found',
  'program_already_enrolled',
]);
function ownedStored(value: unknown, subject: string) {
  const row = storedProposalSchema.parse(value);
  if (
    row.proposal.actor.subject !== subject ||
    (row.receipt && row.receipt.actor.subject !== subject)
  )
    throw new Error('training_revision_owner_mismatch');
  return row;
}
function database() {
  const url = process.env.DATABASE_URL || process.env.WAITLIST_DATABASE_URL;
  if (!url) throw new Error('Missing DATABASE_URL for training revisions');
  return neon(url);
}

export function createNeonTrainingRevisions(
  sql: NeonQueryFunction<false, false> = database(),
): TrainingRevisionsPort {
  async function command(
    subject: string,
    action: string,
    request: unknown,
  ): Promise<Record<string, unknown>> {
    const rows = (await sql.query(
      'select public.training_revision_command($1,$2,$3::jsonb) as result',
      [subject, action, JSON.stringify(request)],
    )) as Array<{ result: Record<string, unknown> }>;
    if (!rows[0]?.result) throw new Error('training_revision_unavailable');
    return rows[0].result;
  }
  function conflict(value: unknown): { kind: RevisionConflict } {
    return { kind: conflictSchema.parse(value) };
  }
  return {
    async readContext(subject) {
      const rows = (await sql.query('select public.training_revision_context($1) as context', [
        subject,
      ])) as Array<{ context: unknown }>;
      return rows[0]?.context ? contextSchema.parse(rows[0].context) : null;
    },
    async readProposal(subject, id) {
      const rows = (await sql.query(
        'select public.training_stored_proposal($1::uuid,$2) as stored',
        [id, subject],
      )) as Array<{ stored: unknown }>;
      return rows[0]?.stored ? ownedStored(rows[0].stored, subject) : null;
    },
    async createProposal(input) {
      const result = await command(input.subject, 'create', input);
      return result.kind === 'stored'
        ? { kind: 'stored', stored: ownedStored(result.stored, input.subject) }
        : conflict(result.kind);
    },
    async decide(input) {
      const result = await command(input.subject, input.decision, input);
      if (result.kind !== 'decided') return conflict(result.kind);
      const receipt = revisionReceiptSchema.parse(result.receipt);
      if (
        receipt.actor.subject !== input.subject ||
        receipt.proposalId !== input.proposalId ||
        receipt.requestId !== input.requestId ||
        receipt.decision !== input.decision
      )
        throw new Error('training_revision_receipt_mismatch');
      return { kind: 'decided', receipt };
    },
    async storeLegacySetup(subject, setup, context) {
      const result = await command(subject, 'legacy_enroll', { setup, context });
      if (result.kind !== 'enrolled') throw new Error('training_enrollment_not_committed');
    },
    async revoke(subject) {
      const result = await command(subject, 'revoke', {});
      if (result.kind === 'owner_missing') return 0;
      if (result.kind !== 'revoked') throw new Error('training_revocation_not_committed');
      return z.number().int().nonnegative().parse(result.deletedRecords);
    },
    async exportForSubject(subject) {
      const [proposals, revisions] = (await Promise.all([
        sql.query(
          'select public.training_stored_proposal(id,$1) as stored from public.training_revision_proposals where user_subject=$1 order by created_at,id',
          [subject],
        ),
        sql.query(
          'select payload from public.training_program_revisions where user_subject=$1 order by created_at,id',
          [subject],
        ),
      ])) as [Array<{ stored: unknown }>, Array<{ payload: unknown }>];
      return {
        proposals: proposals.map((row) => ownedStored(row.stored, subject)),
        revisions: revisions.map((row) => row.payload),
      };
    },
  };
}
export const neonTrainingRevisions: TrainingRevisionsPort = {
  readContext: (subject) => createNeonTrainingRevisions().readContext(subject),
  readProposal: (subject, id) => createNeonTrainingRevisions().readProposal(subject, id),
  createProposal: (input) => createNeonTrainingRevisions().createProposal(input),
  decide: (input) => createNeonTrainingRevisions().decide(input),
  storeLegacySetup: (subject, setup, context) =>
    createNeonTrainingRevisions().storeLegacySetup(subject, setup, context),
  revoke: (subject) => createNeonTrainingRevisions().revoke(subject),
  exportForSubject: (subject) => createNeonTrainingRevisions().exportForSubject(subject),
};
