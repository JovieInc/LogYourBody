import type { TrainingProgramSetup } from '@/lib/training/types';
import type {
  InitialTrainingProposal,
  RevisionContextToken,
  StoredTrainingProposal,
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
  | 'program_already_enrolled';
export type ProposalWriteResult =
  { kind: 'stored'; stored: StoredTrainingProposal } | { kind: RevisionConflict };
export type RevisionDecisionResult =
  { kind: 'decided'; receipt: TrainingRevisionReceipt } | { kind: RevisionConflict };

/** Atomic canonical enrollment decisions. Never substitute generic records.push. */
export interface TrainingRevisionsPort {
  readContext(subject: string): Promise<TrainingRevisionContext | null>;
  readProposal(subject: string, id: string): Promise<StoredTrainingProposal | null>;
  createProposal(input: {
    subject: string;
    requestId: string;
    requestHash: string;
    proposal: InitialTrainingProposal;
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
    setup: TrainingProgramSetup & { programRevisionId: string };
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
