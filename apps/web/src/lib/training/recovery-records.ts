import type {
  NativeProductRecordsPort,
  NativeProductRecord,
} from '@/lib/ports/native-product-records';
import {
  captureTrainingAdmission,
  requireAdmittedSetup,
  TrainingMutationError,
} from './mutation-admission';
import { createMesoBlock } from './engine';
import { loadTrainingRecords, type TrainingRecordsSnapshot } from './service';
import { trainingRequestHash } from './revisions';
import { evaluateRecovery, RECOVERY_POLICY, type RecoveryExposure } from './recovery';
import { readRecoveryTrials, recoveryTrialSchema, type RecoveryTrial } from './recovery-contract';
import type { MuscleGroup, Session } from './types';

export type RecoveryTarget = {
  muscle: MuscleGroup;
  exerciseId: string;
  goal: 'emphasize' | 'grow' | 'maintain';
};
export class RecoveryConflict extends Error {}

export function recoveryRecordBasis(rows: NativeProductRecord[]): Record<string, unknown> {
  return Object.fromEntries(
    rows.map((row) => {
      const {
        collection,
        user_id: _owner,
        deleted_at: _deleted,
        server_updated_at: _updated,
        ...payload
      } = row;
      return [`${collection}/${row.id}`, payload];
    }),
  );
}

function fingerprint(snapshot: TrainingRecordsSnapshot) {
  return trainingRequestHash(
    recoveryRecordBasis(
      snapshot.sourceRecords.filter((row) => row.record_type !== 'recovery_trial'),
    ),
  );
}

function response(input: { snapshot: TrainingRecordsSnapshot; target: RecoveryTarget; now: Date }) {
  const setup = input.snapshot.setup;
  if (!setup) throw new RecoveryConflict('program_not_enrolled');
  const block = createMesoBlock(setup.startedAt, input.now.toISOString());
  const exposures: RecoveryExposure[] = input.snapshot.sessions
    .filter(
      (row) =>
        row.programSetupId === setup.id && row.blockId === block.id && row.status === 'completed',
    )
    .flatMap((row) => {
      const session = row.prescription as Session | undefined;
      const exercise = session?.exercises?.find(
        (item) => item.id === input.target.exerciseId && item.primaryMuscle === input.target.muscle,
      );
      if (!exercise) return [];
      return [
        {
          sessionId: row.id,
          prescription: exercise,
          completed: input.snapshot.logs.filter(
            (log) => log.sessionId === row.id && log.exerciseId === exercise.id,
          ),
        },
      ];
    });
  return {
    block,
    exposures,
    evaluation: evaluateRecovery({
      ...input.target,
      exposures,
      feedback: input.snapshot.feedback,
      now: input.now,
      deload: block.currentWeek === block.weekCount,
    }),
  };
}

export async function readRecovery(input: {
  records: NativeProductRecordsPort;
  subject: string;
  target: RecoveryTarget;
  now: Date;
}) {
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  return {
    ...response({ ...input, snapshot }),
    trials: readRecoveryTrials(snapshot.sourceRecords),
  };
}

/** Proposal construction writes only the trial. Plan reads and evaluation are pure. */
export async function createRecoveryTrial(input: {
  records: NativeProductRecordsPort;
  subject: string;
  target: RecoveryTarget;
  requestId: string;
  now: Date;
}) {
  const admission = await captureTrainingAdmission(input.records, input.subject);
  if (!admission) throw new RecoveryConflict('program_not_enrolled');
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  if (!snapshot.setup) throw new RecoveryConflict('program_not_enrolled');
  requireAdmittedSetup(admission, snapshot.setup);
  const requestHash = trainingRequestHash(input.target);
  const existing = readRecoveryTrials(snapshot.sourceRecords).find(
    (trial) => trial.id === input.requestId,
  );
  if (existing) {
    if (existing.programSetupId !== snapshot.setup.id)
      throw new RecoveryConflict('trial_context_changed');
    if (existing.requestHash !== requestHash) throw new RecoveryConflict('request_conflict');
    return existing;
  }
  const { block, exposures, evaluation } = response({ ...input, snapshot });
  const timestamp = input.now.toISOString();
  const outcome: RecoveryTrial['outcome'] = {
    decision: 'pending',
    observationIds: [],
    completedSetIds: [],
    rationale: 'Awaiting a reviewed intervention and comparable response.',
  };
  const trial = recoveryTrialSchema.parse({
    id: input.requestId,
    record_type: 'recovery_trial',
    version: 1,
    revision: 0,
    policyVersion: RECOVERY_POLICY.version,
    programSetupId: snapshot.setup.id,
    programRevisionId: snapshot.setup.programRevisionId ?? null,
    blockId: block.id,
    ...input.target,
    sourceFingerprint: fingerprint(snapshot),
    requestHash,
    baseline: exposures,
    inference: evaluation,
    hypothesis: evaluation.change
      ? 'A smaller dose may improve tolerance at the next comparable exposure; the cause of decline remains uncertain.'
      : 'Observe the next comparable response before testing an unreviewed material change.',
    reviewPoint: 'next_comparable_completed_exposure',
    holdConditions: [
      'No comparable response',
      'Missing or conflicting readiness',
      'Changed setup, effort or rest',
      'Unreviewed increase bounds',
    ],
    revertConditions: [
      'Continued adverse response requires recovery review',
      'User rejects the intervention',
      'Deload or next block requires a new baseline',
    ],
    state: 'proposed',
    outcome,
    history: [{ revision: 0, state: 'proposed', at: timestamp, outcome }],
    createdAt: timestamp,
    updatedAt: timestamp,
    appliedAt: null,
  });
  if (!input.records.trainingMutations?.commitRecoveryTrial)
    throw new TrainingMutationError('training_mutations_unavailable');
  const saved = await input.records.trainingMutations.commitRecoveryTrial({
    subject: input.subject,
    admission,
    expectedRecords: recoveryRecordBasis(snapshot.sourceRecords),
    expectedRevision: null,
    record: trial,
  });
  if (saved.kind !== 'saved') throw new RecoveryConflict(saved.kind);
  return recoveryTrialSchema.parse(saved.record);
}

export async function decideRecoveryTrial(input: {
  records: NativeProductRecordsPort;
  subject: string;
  trialId: string;
  expectedRevision: number;
  decision: 'apply' | 'reject' | 'revert' | 'review';
  now: Date;
}) {
  const admission = await captureTrainingAdmission(input.records, input.subject);
  if (!admission) throw new RecoveryConflict('program_not_enrolled');
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  if (!snapshot.setup) throw new RecoveryConflict('program_not_enrolled');
  requireAdmittedSetup(admission, snapshot.setup);
  const trials = readRecoveryTrials(snapshot.sourceRecords);
  const trial = trials.find((item) => item.id === input.trialId);
  if (!trial) throw new RecoveryConflict('trial_not_found');
  if (trial.revision !== input.expectedRevision || trial.programSetupId !== snapshot.setup.id)
    throw new RecoveryConflict('trial_revision_conflict');
  let state = trial.state;
  let outcome = trial.outcome;
  let appliedAt = trial.appliedAt;
  const current = response({ ...input, snapshot, target: trial });
  if (input.decision === 'apply') {
    if (state !== 'proposed' || !trial.inference.change || trial.inference.action !== 'reduce')
      throw new RecoveryConflict('no_executable_change');
    if (
      trial.sourceFingerprint !== fingerprint(snapshot) ||
      current.block.id !== trial.blockId ||
      current.block.currentWeek === current.block.weekCount
    )
      throw new RecoveryConflict('trial_context_changed');
    if (
      trials.some(
        (other) =>
          other.id !== trial.id &&
          other.state === 'applied' &&
          other.blockId === trial.blockId &&
          other.exerciseId === trial.exerciseId,
      )
    )
      throw new RecoveryConflict('trial_already_active');
    state = 'applied';
    appliedAt = input.now.toISOString();
  } else if (input.decision === 'reject') {
    if (state !== 'proposed') throw new RecoveryConflict('trial_already_decided');
    state = 'rejected';
  } else if (input.decision === 'revert') {
    if (state !== 'applied') throw new RecoveryConflict('trial_not_applied');
    state = 'reverted';
  } else {
    if (state !== 'applied' || !appliedAt) throw new RecoveryConflict('trial_not_applied');
    const following = current.exposures.filter(
      (exposure) =>
        exposure.completed.some((log) => Date.parse(log.completedAt) > Date.parse(appliedAt!)) &&
        !trial.baseline.some((baseline) => baseline.sessionId === exposure.sessionId),
    );
    const comparable =
      following.some((exposure) =>
        current.evaluation.comparableSessionIds.includes(exposure.sessionId),
      ) &&
      trial.baseline.some((baseline) =>
        current.evaluation.comparableSessionIds.includes(baseline.sessionId),
      );
    const adverse = ['reduce', 'respace', 'substitute', 'recovery_review'].includes(
      current.evaluation.action,
    );
    outcome = {
      decision:
        following.length && comparable
          ? adverse
            ? 'revert'
            : current.evaluation.action === 'hold'
              ? 'retain'
              : 'inconclusive'
          : 'inconclusive',
      observationIds: current.evaluation.observationIds,
      completedSetIds: current.evaluation.completedSetIds,
      rationale: current.evaluation.rationale,
    };
  }
  const revision = trial.revision + 1;
  const timestamp = input.now.toISOString();
  const updated: RecoveryTrial = {
    ...trial,
    revision,
    state,
    outcome,
    appliedAt,
    updatedAt: timestamp,
    history: [...trial.history, { revision, state, at: timestamp, outcome }],
  };
  if (!input.records.trainingMutations?.commitRecoveryTrial)
    throw new TrainingMutationError('training_mutations_unavailable');
  const saved = await input.records.trainingMutations.commitRecoveryTrial({
    subject: input.subject,
    admission,
    expectedRecords: recoveryRecordBasis(snapshot.sourceRecords),
    expectedRevision: trial.revision,
    record: updated,
  });
  if (saved.kind !== 'saved') throw new RecoveryConflict(saved.kind);
  return recoveryTrialSchema.parse(saved.record);
}
