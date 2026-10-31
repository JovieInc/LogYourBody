import { z } from 'zod';
import { CATALOG_EQUIPMENT, EXERCISE_CATALOG } from './catalog';
import { eligibleForProgram } from './delegated-planning';
import { effectiveTrainingFeedback } from './engine';
import { hasSelectionSymptoms, suggestAlternatives } from './alternatives';
import type { TrainingRecordsSnapshot } from './service';
import type { ExerciseSelectionContext, Session } from './types';

export const selectionContextSchema = z
  .object({
    gymId: z.string().trim().min(1).max(80),
    availableEquipment: z.array(z.enum(CATALOG_EQUIPMENT)).max(CATALOG_EQUIPMENT.length),
    excludedConcerns: z.array(z.string().trim().min(1).max(80)).max(16),
    setupNote: z.string().trim().min(1).max(160).optional(),
  })
  .strict();

export function exerciseSelectionEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return (
    env.LYB_HYPERTROPHY_COACH_API_ENABLED === 'true' &&
    env.LYB_EXERCISE_SELECTION_ENABLED === 'true'
  );
}

/** A read-only proposal. Inventory is explicit for this visit, never inferred from a gym name. */
export function reviewExerciseSelection(
  snapshot: TrainingRecordsSnapshot,
  session: Session,
  exerciseId: string,
  context: ExerciseSelectionContext,
) {
  const setup = snapshot.setup;
  const exercise = session.exercises.find((item) => item.id === exerciseId);
  if (!setup || !exercise) return null;
  const feedback = effectiveTrainingFeedback(snapshot.feedback);
  const currentFeedback = feedback.filter((item) => item.sessionId === session.id);
  const paused =
    session.safetyStop || session.executionPaused || currentFeedback.some(hasSelectionSymptoms);
  const library = EXERCISE_CATALOG.filter(
    (variant) =>
      variant.id === exerciseId ||
      (!setup.excludedVariantIds?.includes(variant.id) &&
        !session.exercises.some((item) => item.id === variant.id) &&
        (!setup.delegated || eligibleForProgram(variant.id, setup.delegated.inputs))),
  );
  const previousSwaps = [
    ...snapshot.swaps,
    ...snapshot.sessions.flatMap((record) => {
      if (record.programSetupId !== setup.id) return [];
      const events = (record.prescription as Session | undefined)?.executionEvents ?? [];
      const restored = new Set(events.map((event) => event.restoresEventId));
      return events
        .filter(
          (event) =>
            event.selectionContext &&
            !restored.has(event.id) &&
            event.exerciseId &&
            event.replacementExerciseId,
        )
        .map((event) => ({
          fromExerciseId: event.exerciseId!,
          toVariantId: event.replacementExerciseId!,
        }));
    }),
  ];
  const suggestions = paused
    ? { status: 'symptom_safety' as const, differentExercise: null, sameExerciseSetup: null }
    : suggestAlternatives(
        {
          exerciseId,
          feedback: snapshot.feedback,
          previousSwaps,
          allowTrials: true,
          gymId: context.gymId,
          excludedConcerns: [
            ...context.excludedConcerns,
            ...(setup.delegated?.inputs.limitations ?? []),
          ],
        },
        library,
        new Set(context.availableEquipment),
      );
  const options = [suggestions.differentExercise, suggestions.sameExerciseSetup].flatMap(
    (option) => {
      if (!option) return [];
      const variant = library.find((item) => item.id === option.variantId)!;
      return [{ ...option, name: variant.name, setup: variant }];
    },
  );
  const preferredContext = snapshot.sessions
    .flatMap((record) =>
      record.programSetupId === setup.id
        ? ((record.prescription as Session | undefined)?.executionEvents ?? [])
        : [],
    )
    .filter((event) => event.selectionContext)
    .sort(
      (a, b) => b.createdAt.localeCompare(a.createdAt) || b.id.localeCompare(a.id),
    )[0]?.selectionContext;
  return {
    sessionId: session.id,
    exerciseId,
    revision: session.executionRevision ?? 0,
    status: suggestions.status,
    context,
    options,
    preferredContext,
    message:
      suggestions.status === 'symptom_safety'
        ? 'Pause this movement. Do not train through pain. Seek medical evaluation for persistent, worsening or neurologic symptoms.'
        : 'Supported options may reduce trunk demands; individual response is unknown. Check clearance, cable line and comfortable ROM. A belt does not establish tolerance. Approval tries this setup today; repeated positive feedback can retain it in this block.',
  };
}
