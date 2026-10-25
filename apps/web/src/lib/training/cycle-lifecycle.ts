import { catalogVariantById } from './catalog';
import type { NativeProductRecord } from '@/lib/ports/native-product-records';
import {
  completedTrainingSession,
  configuredMesoBlock,
  createProgramBlock,
  evaluateDeload,
} from './engine';
import type {
  CyclePhase,
  MesoBlock,
  Session,
  SetLog,
  TrainingFeedback,
  TrainingProgramSetup,
} from './types';

export function completedCycleSessions(
  setup: TrainingProgramSetup,
  sessions: NativeProductRecord[],
  logs: SetLog[],
) {
  return sessions.filter(
    (row) =>
      row.programSetupId === setup.id &&
      (!setup.cycle || row.blockId === (setup.cycle.blockId ?? 'block-1')) &&
      row.status === 'completed' &&
      row.prescription &&
      completedTrainingSession(row.prescription as Session, logs),
  );
}

/** Calendar passage is not evidence of completed training. Configured blocks
 * stop at review until the next block is explicitly accepted. */
export function cycleBlock(
  setup: TrainingProgramSetup,
  sessions: NativeProductRecord[],
  logs: SetLog[],
  now: Date,
): MesoBlock {
  return setup.cycle
    ? {
        ...configuredMesoBlock(
          setup.startedAt,
          setup.cycle.weekCount,
          completedCycleSessions(setup, sessions, logs).length,
          setup.sessionsPerWeek,
        ),
        id: setup.cycle.blockId ?? 'block-1',
      }
    : createProgramBlock(setup, now.toISOString());
}

export function cyclePhase(block: MesoBlock, feedback: TrainingFeedback[]): CyclePhase | undefined {
  if (!block.phase) return undefined;
  if (block.phase === 'review') return 'review';
  return evaluateDeload(feedback).action !== 'none' ? 'reactive_deload' : block.phase;
}

export function cycleReuseOptions(snapshot: {
  setup: TrainingProgramSetup | null;
  sessions: NativeProductRecord[];
  swaps: Array<{ programSetupId: string; fromExerciseId: string; toVariantId: string }>;
}) {
  const ids = new Set(
    snapshot.sessions
      .filter((row) => row.programSetupId === snapshot.setup?.id)
      .flatMap((row) => ((row.prescription as Session)?.exercises ?? []).map((item) => item.id)),
  );
  const swaps = new Map(
    snapshot.swaps
      .filter((swap) => swap.programSetupId === snapshot.setup?.id)
      .map((swap) => [swap.toVariantId, swap.fromExerciseId]),
  );
  return [...ids].sort().map((id) => {
    const retained = snapshot.setup?.cycle?.retainedVariants.find(
      (item) => item.toVariantId === id,
    );
    let source = retained?.fromExerciseId ?? id;
    const seen = new Set<string>();
    while (swaps.has(source) && !seen.has(source)) {
      seen.add(source);
      source = swaps.get(source)!;
    }
    return {
      fromExerciseId: source,
      toVariantId: id,
      name: catalogVariantById(id)?.name ?? id,
      reason: retained?.reason ?? 'Keep the exercise that worked in the last block.',
    };
  });
}
