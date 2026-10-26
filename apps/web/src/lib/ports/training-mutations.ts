import type { NativeProductRecord } from './native-product-records';

export type TrainingMutationAdmission = Readonly<{
  ownerId: string;
  generation: number;
  setupId: string;
  revisionId: string | null;
}>;
export type TrainingMutationAction =
  | 'session_insert'
  | 'session_update'
  | 'set_insert'
  | 'set_correct'
  | 'feedback_insert'
  | 'swap_insert';
export type TrainingMutationConflict =
  'owner_missing' | 'stale_admission' | 'session_conflict' | 'record_conflict';
export type TrainingMutationResult =
  { kind: 'saved'; record: NativeProductRecord } | { kind: TrainingMutationConflict };

/** Canonical training writes serialize with consent revocation and account deletion. */
export interface TrainingMutationsPort {
  /** Atomic recovery-trial CAS, serialized with consent/account mutation and
   * checked against the exact training rows used to construct the proposal. */
  commitRecoveryTrial?(input: {
    subject: string;
    admission: TrainingMutationAdmission;
    expectedRecords: Record<string, unknown>;
    expectedRevision: number | null;
    record: Record<string, unknown>;
  }): Promise<TrainingMutationResult>;
  captureAdmission(subject: string): Promise<TrainingMutationAdmission | null>;
  commit(input: {
    subject: string;
    admission: TrainingMutationAdmission;
    action: TrainingMutationAction;
    record: Record<string, unknown>;
  }): Promise<TrainingMutationResult>;
}
