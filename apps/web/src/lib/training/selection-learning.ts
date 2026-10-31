import { hasRepeatedVariantResponse } from './alternatives';
import { effectiveTrainingFeedback } from './engine';
import { catalogVariantById, isEligibleVariant } from './catalog';
import type { NativeProductRecord } from '@/lib/ports/native-product-records';
import type { Session } from './types';
import type { TrainingRecordsSnapshot } from './service';

/** Persists one exercise substitution for the rest of a mesocycle block. The
 * original exercise keeps its history; the variant starts from its own. */
export type ExerciseSwapRecord = NativeProductRecord & {
  record_type: 'exercise_swap';
  programSetupId: string;
  blockId: string;
  sessionId: string;
  fromExerciseId: string;
  toVariantId: string;
};

/** Reuses block-swap application only after explicit approval and repeated usable response.
 * The approved event is stored atomically with the session; no second preference store.
 */
export function learnedExerciseSwaps(snapshot: TrainingRecordsSnapshot): ExerciseSwapRecord[] {
  const activeGym = effectiveTrainingFeedback(snapshot.feedback).find(
    (item) => item.context?.gymId,
  )?.context;
  const choices = new Map<
    string,
    { record: NativeProductRecord; event: Session['executionEvents'][number] }
  >();
  const events = snapshot.sessions
    .filter((record) => record.programSetupId === snapshot.setup?.id)
    .flatMap((record) =>
      ((record.prescription as Session | undefined)?.executionEvents ?? []).map((event) => ({
        record,
        event,
      })),
    )
    .sort(
      (a, b) =>
        a.event.createdAt.localeCompare(b.event.createdAt) || a.event.id.localeCompare(b.event.id),
    );
  for (const { record, event } of events) {
    if (event.kind === 'swap_restored') {
      for (const [key, choice] of choices)
        if (choice.event.id === event.restoresEventId) choices.delete(key);
    } else if (event.selectionContext && event.exerciseId && event.replacementExerciseId) {
      choices.set(`${record.blockId}:${event.exerciseId}`, { record, event });
    }
  }
  return [...choices.values()].flatMap(({ record, event }) => {
    const context = event.selectionContext!;
    const variant = catalogVariantById(event.replacementExerciseId!);
    if (
      !variant ||
      (activeGym?.gymId !== undefined && activeGym.gymId !== context.gymId) ||
      !hasRepeatedVariantResponse(snapshot.feedback, variant.id, context.gymId) ||
      !isEligibleVariant(variant, {
        available: new Set(activeGym?.availableEquipment ?? context.availableEquipment),
        excludedConcerns: context.excludedConcerns,
      })
    )
      return [];
    return [
      {
        id: event.id,
        record_type: 'exercise_swap' as const,
        programSetupId: String(record.programSetupId),
        blockId: String(record.blockId),
        sessionId: record.id,
        fromExerciseId: event.exerciseId!,
        toVariantId: variant.id,
        ...(record.programRevisionId ? { programRevisionId: record.programRevisionId } : {}),
        deleted_at: null,
        server_updated_at: event.createdAt,
      },
    ];
  });
}
