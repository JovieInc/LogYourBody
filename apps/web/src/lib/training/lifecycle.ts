import { createMesoBlock, evaluateDeload } from './engine';
import type { NativeProductRecord } from '@/lib/ports/native-product-records';
import {
  MUSCLE_GROUPS,
  type CyclePhase,
  type Session,
  type TrainingFeedback,
  type TrainingProgramSetup,
} from './types';

/** Terminal skips/early ends occupy an attempt, never a completed training slot. */
export function completedTraining(record: NativeProductRecord): boolean {
  const prescription = record.prescription as Session | undefined;
  return (
    record.status === 'completed' &&
    !prescription?.executionEvents?.some((event) => event.kind === 'ended') &&
    (prescription?.exercises.length ?? 0) > 0
  );
}

/** Reduced planned-deload work is retained as history, not overload evidence. */
export function progressionTraining(record: NativeProductRecord): boolean {
  return completedTraining(record) && record.cyclePhase !== 'planned_deload';
}

export function cycleBlock(
  setup: TrainingProgramSetup,
  sessions: NativeProductRecord[],
  now: Date,
) {
  if (!setup.cycle) return createMesoBlock(setup.startedAt, now.toISOString());
  const blockId = `block-${setup.cycle.number}`;
  // Count distinct completed slots in consecutive weeks. Calendar time never fills gaps.
  let completedWeeks = 0;
  for (let week = 1; week <= setup.cycle.weekCount; week++) {
    const slots = new Set(
      sessions
        .filter(
          (record) =>
            record.programSetupId === setup.id &&
            record.blockId === blockId &&
            record.weekNumber === week &&
            typeof record.slot === 'number' &&
            Number.isInteger(record.slot) &&
            record.slot >= 0 &&
            record.slot < setup.sessionsPerWeek &&
            completedTraining(record),
        )
        .map((record) => record.slot),
    );
    if (slots.size < setup.sessionsPerWeek) break;
    completedWeeks++;
  }
  return createMesoBlock(setup.startedAt, now.toISOString(), { ...setup.cycle, completedWeeks });
}

export function cycleLifecycle(
  setup: TrainingProgramSetup,
  sessions: NativeProductRecord[],
  feedback: TrainingFeedback[],
  now: Date,
) {
  if (!setup.cycle) return undefined;
  const block = cycleBlock(setup, sessions, now);
  const recovery = evaluateDeload(feedback);
  const phase: CyclePhase =
    block.phase === 'review'
      ? 'review'
      : recovery.action !== 'none' ||
          MUSCLE_GROUPS.some((muscle) => evaluateDeload(feedback, muscle).action !== 'none')
        ? 'reactive_deload'
        : block.phase!;
  return {
    phase,
    blockId: block.id,
    week: block.currentWeek,
    weekCount: block.weekCount,
    nextPhase: phase === 'review' ? 'next_block' : 'adjustment',
    priorities: block.phase === 'review' ? [] : setup.cycle.priorities,
    constraints: block.phase === 'review' ? [] : setup.cycle.constraints,
  };
}
