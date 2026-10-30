import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import { cycleBlock } from './cycle-lifecycle';
import { buildMicrocycle, effectiveTrainingFeedback } from './engine';
import { loadTrainingRecords, applyConfiguredVariants, applyExerciseSwaps } from './service';
import { readRecoveryTrials } from './recovery-contract';
import { recoveryRecordBasis } from './recovery-records';
import { trainingRequestHash } from './revisions';
import { optimizerInputSchema } from './optimizer';
import { CONTROLLER_POLICY } from './controller';
import type { RollingScheduleContext } from './rolling-schedule';
import type { Session } from './types';

/** HTTP inputs offer opportunities, not evidence or approval. Rebuild the work,
 * completed history and applied decisions from the authenticated owner's records
 * on both propose and accept. This endpoint remains proposal-only. */
export async function ownedRollingScheduleSource(input: {
  source: unknown;
  records: NativeProductRecordsPort;
  subject: string;
  recoveryEnabled: boolean;
}) {
  const parsed = optimizerInputSchema.safeParse(input.source);
  if (!parsed.success || !parsed.data.rollingSchedule) return null;
  const context = parsed.data.rollingSchedule;
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  const setup = snapshot.setup;
  if (!setup) return null;
  const block = cycleBlock(setup, snapshot.sessions, snapshot.logs, new Date(context.asOf));
  const programIds = new Set([setup.id, ...(setup.cycle?.historyProgramIds ?? [])]);
  const rows = snapshot.sessions.filter((row) => programIds.has(String(row.programSetupId)));
  const rowIds = new Set(rows.map((row) => row.id));
  const logs = snapshot.logs.filter((log) => rowIds.has(log.sessionId));
  const feedback = effectiveTrainingFeedback(
    snapshot.feedback.filter((row) => rowIds.has(row.sessionId)),
  );
  const completedIds = new Set(
    rows.filter((row) => row.status === 'completed').map((row) => row.id),
  );
  const completedLogs = logs.filter((log) => completedIds.has(log.sessionId));
  const templateId = (slot: number) => String.fromCharCode(65 + slot);
  const microcycle = buildMicrocycle({
    setup,
    block,
    sessionIds: Array.from({ length: setup.sessionsPerWeek }, (_, slot) => templateId(slot)),
    logs: completedLogs,
    feedback,
  });
  const rotationId = `${setup.id}:${block.id}:${block.currentWeek}`;
  const sessions = microcycle.sessions.map((session, index) => {
    const effective = rows
      .filter(
        (row) =>
          row.programSetupId === setup.id &&
          row.blockId === block.id &&
          row.weekNumber === block.currentWeek &&
          row.slot === index &&
          (row.prescription as Session)?.executionRevision > 0,
      )
      .sort((a, b) => Date.parse(String(b.startedAt)) - Date.parse(String(a.startedAt)))[0];
    const prescribed = effective
      ? (effective.prescription as Session)
      : applyConfiguredVariants(
          applyExerciseSwaps(
            session,
            snapshot.swaps.filter(
              (swap) => swap.programSetupId === setup.id && swap.blockId === block.id,
            ),
            completedLogs,
          ),
          setup,
          completedLogs,
        );
    return {
      id: session.id,
      day: (['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const)[index]!,
      part: 'any' as const,
      exercises: prescribed.exercises.map((exercise) => ({
        id: exercise.id,
        name: exercise.name,
        primaryMuscle: exercise.primaryMuscle,
        muscleContribution: exercise.muscleContribution,
        sets: exercise.sets,
        targetRir: exercise.targetRir,
        ...(effective ? { userEdited: true } : {}),
      })),
    };
  });
  // The ordinary engine owns a safety pause. Do not turn its empty prescription
  // into a different muscle's workout through scheduling.
  if (microcycle.sessions.some((session) => session.safetyStop)) return null;
  if (
    rows.some(
      (row) =>
        row.programSetupId === setup.id &&
        row.blockId === block.id &&
        row.weekNumber === block.currentWeek &&
        ((row.prescription as Session)?.safetyStop ||
          (row.prescription as Session)?.executionPaused),
    )
  )
    return null;
  const observations: RollingScheduleContext['observations'] = [];
  for (const row of feedback) {
    const at = row.observedAt ?? row.createdAt;
    const add = (
      scope: RollingScheduleContext['observations'][number]['scope'],
      state: 'ready' | 'limited' | 'unknown',
      extra: object = {},
    ) =>
      observations.push({
        id: `${row.id}:${observations.length}`,
        sourceObservationId: row.id,
        at,
        scope,
        state,
        ...extra,
      });
    if (row.generalReadiness) add('whole_body', row.generalReadiness);
    if (row.targetMuscle && row.targetMuscleReadiness)
      add('muscle', row.targetMuscleReadiness, { muscle: row.targetMuscle });
    for (const [muscle, signal] of Object.entries(row.muscles ?? {})) {
      if (signal.recovery) add('muscle', signal.recovery, { muscle });
      if ((signal.soreness ?? 0) >= CONTROLLER_POLICY.deloadSorenessThreshold)
        add('muscle', 'limited', { muscle });
    }
    for (const scope of ['grip', 'trunk'] as const) {
      const state = row.supportingReadiness?.[scope];
      if (state) add(scope, state);
    }
    for (const [muscle, state] of Object.entries(row.supportingReadiness?.muscles ?? {}))
      if (state) add('muscle', state, { muscle });
    if ((row.jointPain ?? 0) > 0 || row.symptomFlags?.length)
      add(row.context?.exerciseId ? 'exercise' : 'whole_body', 'limited', {
        ...(row.context?.exerciseId ? { exerciseId: row.context.exerciseId } : {}),
        symptom: true,
      });
  }
  const history: RollingScheduleContext['history'] = rows.map((row) => {
    const prescription = row.prescription as Session;
    const endedAt =
      typeof row.completedAt === 'string'
        ? row.completedAt
        : (prescription.executionEvents?.findLast((event) => event.kind === 'ended')?.createdAt ??
          null);
    return {
      id: row.id,
      templateId: templateId(Number(row.slot)),
      rotationId: `${row.programSetupId}:${row.blockId}:${row.weekNumber}`,
      groupId: typeof row.sessionGroupId === 'string' ? row.sessionGroupId : row.id,
      visitId: typeof row.visitId === 'string' ? row.visitId : row.id,
      startedAt: String(row.startedAt),
      endedAt,
      outcome: logs.some((log) => log.sessionId === row.id)
        ? row.status === 'completed'
          ? 'completed'
          : 'partial'
        : row.status === 'ended'
          ? 'empty'
          : 'unknown',
      exercises: prescription.exercises.map((exercise) => ({
        id: exercise.id,
        primaryMuscle: exercise.primaryMuscle,
        muscleContribution: exercise.muscleContribution,
        sets: exercise.sets,
        targetRir: exercise.targetRir,
      })),
    };
  });
  const source = {
    ...parsed.data,
    sessions,
    logs: logs.map(({ id, sessionId, exerciseId, setNumber, reps, loadKg, rir, completedAt }) => ({
      id,
      sessionId,
      exerciseId,
      setNumber,
      reps,
      loadKg,
      rir,
      completedAt,
    })),
    targetRir: block.targetRir,
    equipmentProfile: setup.equipment,
    sequencingContext: {
      ...parsed.data.sequencingContext,
      blockId: block.id,
      asOf: context.asOf,
      intents: parsed.data.sequencingContext?.intents ?? [],
      excludedExerciseIds: [
        ...new Set([
          ...(parsed.data.sequencingContext?.excludedExerciseIds ?? []),
          ...(setup.excludedVariantIds ?? []),
          ...(setup.delegated?.inputs.excludedVariantIds ?? []),
        ]),
      ],
      excludedConcerns: [
        ...new Set([
          ...(parsed.data.sequencingContext?.excludedConcerns ?? []),
          ...(setup.delegated?.inputs.limitations ?? []),
        ]),
      ],
    },
    rollingSchedule: {
      ...context,
      programSetupId: setup.id,
      blockId: block.id,
      rotationId,
      attendanceSince: setup.startedAt,
      requestedVisitsPerWeek: setup.sessionsPerWeek,
      sourceFingerprint: trainingRequestHash(recoveryRecordBasis(snapshot.sourceRecords)),
      history,
      observations,
      trials: input.recoveryEnabled ? readRecoveryTrials(snapshot.sourceRecords) : [],
    },
  };
  const validated = optimizerInputSchema.safeParse(source);
  return validated.success ? validated.data : null;
}
