import type { TrainingProgramSetup } from '@/lib/training/types';
import type {
  PlanLayout,
  RevisionContextToken,
  StoredTrainingProposal,
  StoredTrainingRevision,
  TrainingProposal,
  TrainingRevisionReceipt,
} from '@/lib/training/revision-contract';

export type TrainingRevisionContext = RevisionContextToken & {
  dateOfBirth: unknown;
  legacySetups: unknown[];
  headRevision: string | null;
};
export type RevisionConflict =
  | 'owner_missing'
  | 'stale_context'
  | 'revision_conflict'
  | 'request_conflict'
  | 'already_decided'
  | 'proposal_not_found'
  | 'program_already_enrolled'
  | 'program_not_enrolled';
export type ProposalWriteResult =
  { kind: 'stored'; stored: StoredTrainingProposal } | { kind: RevisionConflict };
export type RevisionDecisionResult =
  { kind: 'decided'; receipt: TrainingRevisionReceipt } | { kind: RevisionConflict };

/** Atomic canonical enrollment and plan-edit decisions. Never substitute
 * generic records.push. */
export interface TrainingRevisionsPort {
  readContext(subject: string): Promise<TrainingRevisionContext | null>;
  readProposal(subject: string, id: string): Promise<StoredTrainingProposal | null>;
  /** The immutable payload of the current head revision, or null before
   * enrollment. Plan edits build on this, never on a client-supplied plan. */
  readHeadRevision(subject: string): Promise<StoredTrainingRevision | null>;
  createProposal(input: {
    subject: string;
    requestId: string;
    requestHash: string;
    proposal: TrainingProposal;
  }): Promise<ProposalWriteResult>;
  decide(input: {
    subject: string;
    proposalId: string;
    requestId: string;
    requestHash: string;
    decision: 'apply' | 'reject';
    context: RevisionContextToken;
    now: string;
    revisionId: string;
    /** null on an applied plan edit (the head it replaces). */
    baseRevision: string | null;
    /** Enrolled setup for initial revisions; null for plan edits. */
    setup: (TrainingProgramSetup & { programRevisionId: string }) | null;
    /** Canonical layout a plan edit installs; null for initial enrollment. */
    layout: PlanLayout | null;
  }): Promise<RevisionDecisionResult>;
  storeLegacySetup(
    subject: string,
    setup: TrainingProgramSetup,
    context: RevisionContextToken,
  ): Promise<void>;
  revoke(subject: string): Promise<number>;
  exportForSubject(
    subject: string,
  ): Promise<{ proposals: StoredTrainingProposal[]; revisions: unknown[] }>;
}

