import { optimizeMesocycle, type OptimizerInput } from './optimizer';
import { certifyOptimization } from './optimizer-certification';
import type { RollingScheduleContext } from './rolling-schedule';
import { RECOVERY_POLICY } from './recovery';
import type { RecoveryTrial } from './recovery-contract';

export function source(): OptimizerInput {
  return {
    sessions: [
      {
        id: 'A',
        day: 'monday',
        part: 'am',
        exercises: [
          {
            id: 'dumbbell_lateral_raise',
            name: 'Lateral raise',
            primaryMuscle: 'shoulders',
            sets: 2,
          },
        ],
      },
      {
        id: 'B',
        day: 'tuesday',
        part: 'pm',
        exercises: [{ id: 'dumbbell_curl', name: 'Curl', primaryMuscle: 'biceps', sets: 2 }],
      },
      {
        id: 'C',
        day: 'wednesday',
        part: 'any',
        exercises: [{ id: 'goblet_squat', name: 'Squat', primaryMuscle: 'quads', sets: 2 }],
      },
    ],
    equipmentProfile: 'dumbbells',
    locationId: null,
    locationPermission: 'unknown',
    stationGeography: 'unknown',
    rollingSchedule: {
      rotationId: 'rotation-1',
      programSetupId: 'setup',
      blockId: 'block-1',
      asOf: '2026-10-26T07:00:00Z',
      attendanceSince: '2026-10-01T00:00:00Z',
      requestedVisitsPerWeek: 5,
      slots: [
        slot('am', '2026-10-26T08:00:00Z'),
        slot('pm', '2026-10-26T20:00:00Z'),
        slot('later', '2026-10-28T08:00:00Z'),
      ],
      history: [],
      observations: [],
      trials: [],
      timing: { warmUpSeconds: 300, setSeconds: 60, restSeconds: 120, transitionSeconds: 60 },
    },
  };
}

export function slot(id: string, scheduledAt: string): RollingScheduleContext['slots'][number] {
  return {
    id,
    scheduledAt,
    timeZone: 'UTC',
    locationId: 'gym',
    groupId: id,
    visitId: id,
    kind: 'visit' as const,
    availableEquipment: ['dumbbells' as const, 'bench' as const],
    priorityTargets: [],
  };
}

export function review(input = source()) {
  const result = optimizeMesocycle(input);
  if (result.kind !== 'proposal') throw new Error('Expected proposal');
  expect(certifyOptimization(input, result.proposal)).toEqual({ ok: true });
  expect(result.proposal.rollingSchedule).toBeDefined();
  return result.proposal.rollingSchedule!;
}

export function history(
  input: OptimizerInput,
  templateId = 'A',
  completedSets = 1,
  at = '2026-10-25T08:00:00Z',
) {
  const template = input.sessions.find((row) => row.id === templateId)!;
  const context = input.rollingSchedule!;
  const id = `history-${context.history.length}`;
  context.history.push({
    id,
    templateId,
    rotationId: context.rotationId,
    groupId: id,
    visitId: id,
    startedAt: at,
    endedAt: at,
    outcome: completedSets ? 'partial' : 'empty',
    exercises: template.exercises.map((exercise) => ({
      id: exercise.id,
      primaryMuscle: exercise.primaryMuscle,
      sets: exercise.sets,
      muscleContribution: { [exercise.primaryMuscle]: 1 },
      targetRir: 2,
    })),
  });
  input.logs ??= [];
  for (let n = 1; n <= completedSets; n++)
    input.logs.push({
      id: `${id}-${n}`,
      sessionId: id,
      exerciseId: template.exercises[0]!.id,
      setNumber: n,
      reps: 10,
      loadKg: 10,
      rir: 2,
      completedAt: at,
    });
  return context.history.at(-1)!;
}

export function reduction(): RecoveryTrial {
  const outcome = {
    decision: 'pending' as const,
    observationIds: [],
    completedSetIds: [],
    rationale: 'Awaiting review.',
  };
  return {
    id: '11111111-1111-4111-8111-111111111111',
    record_type: 'recovery_trial',
    version: 1,
    revision: 1,
    policyVersion: RECOVERY_POLICY.version,
    programSetupId: 'setup',
    programRevisionId: null,
    blockId: 'block-1',
    muscle: 'shoulders',
    exerciseId: 'dumbbell_lateral_raise',
    goal: 'emphasize',
    sourceFingerprint: 'source',
    requestHash: 'request',
    baseline: [],
    inference: {
      action: 'reduce',
      rationale: 'Reviewed decline.',
      uncertainty: 'high',
      evidenceIds: [],
      observationIds: [],
      completedSetIds: [],
      comparableSessionIds: [],
      change: { kind: 'sets', from: 2, to: 1 },
      parameterProposal: null,
    },
    hypothesis: 'A reduced dose may improve tolerance.',
    reviewPoint: 'next_comparable_completed_exposure',
    holdConditions: [],
    revertConditions: [],
    state: 'applied',
    outcome,
    history: [{ revision: 1, state: 'applied', at: '2026-10-25T09:00:00Z', outcome }],
    createdAt: '2026-10-25T09:00:00Z',
    updatedAt: '2026-10-25T09:00:00Z',
    appliedAt: '2026-10-25T09:00:00Z',
  };
}
