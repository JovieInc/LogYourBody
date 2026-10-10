import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import type {
  TrainingMutationAdmission,
  TrainingMutationAction,
} from '@/lib/ports/training-mutations';
import type { TrainingProgramSetup } from './types';

export class TrainingMutationError extends Error {
  constructor(readonly code: 'training_context_changed' | 'training_mutations_unavailable') {
    super(code);
  }
}
export async function captureTrainingAdmission(records: NativeProductRecordsPort, subject: string) {
  if (!records.trainingMutations) throw new TrainingMutationError('training_mutations_unavailable');
  return records.trainingMutations.captureAdmission(subject);
}
export function requireAdmittedSetup(
  admission: TrainingMutationAdmission,
  setup: TrainingProgramSetup,
) {
  if (admission.setupId !== setup.id || admission.revisionId !== (setup.programRevisionId ?? null))
    throw new TrainingMutationError('training_context_changed');
}
export async function commitTrainingMutation(
  records: NativeProductRecordsPort,
  subject: string,
  admission: TrainingMutationAdmission,
  action: TrainingMutationAction,
  record: Record<string, unknown>,
) {
  if (!records.trainingMutations) throw new TrainingMutationError('training_mutations_unavailable');
  const result = await records.trainingMutations.commit({ subject, admission, action, record });
  if (result.kind !== 'saved')
    throw new TrainingMutationError(
      result.kind === 'record_conflict'
        ? 'training_mutations_unavailable'
        : 'training_context_changed',
    );
  return result.record;
}
