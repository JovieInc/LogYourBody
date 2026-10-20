import type { TrainingRecordsSnapshot } from './service';
import type { Session, SetLog } from './types';

type LoggedSet = Pick<SetLog, 'setNumber' | 'reps' | 'loadKg' | 'rir'>;

export type ExerciseProgress = {
  exerciseId: string;
  name: string;
  lastPerformedAt: string;
  lastSession: LoggedSet[];
  heaviestSet: (LoggedSet & { completedAt: string }) | null;
  totalSets: number;
};

export type TrainingProgress = {
  enrolled: boolean;
  completedSessions: number;
  setsLast7Days: number;
  exercises: ExerciseProgress[];
  latestCheckIn: {
    soreness: number;
    pump: number;
    performance: 'up' | 'stable' | 'down';
    jointPain: number;
    createdAt: string;
  } | null;
};

const DAY_MS = 24 * 60 * 60 * 1000;

function exerciseNames(sessions: TrainingRecordsSnapshot['sessions']): Map<string, string> {
  const names = new Map<string, string>();
  for (const record of sessions) {
    const prescription = (record as { prescription?: Session }).prescription;
    for (const exercise of prescription?.exercises ?? []) names.set(exercise.id, exercise.name);
  }
  return names;
}

const time = (value: string) => Date.parse(value);

/** Reports what the user actually logged. It never prescribes. */
export function summarizeTrainingProgress(
  snapshot: TrainingRecordsSnapshot,
  now: Date,
): TrainingProgress {
  const setup = snapshot.setup;
  if (!setup) {
    return {
      enrolled: false,
      completedSessions: 0,
      setsLast7Days: 0,
      exercises: [],
      latestCheckIn: null,
    };
  }
  const programSessions = snapshot.sessions.filter(
    (record) => (record as { programSetupId?: string }).programSetupId === setup.id,
  );
  const programSessionIds = new Set(programSessions.map((record) => record.id));
  const logs = snapshot.logs.filter((log) => programSessionIds.has(log.sessionId));
  const names = exerciseNames(programSessions);

  const byExercise = new Map<string, SetLog[]>();
  for (const log of logs) {
    byExercise.set(log.exerciseId, [...(byExercise.get(log.exerciseId) ?? []), log]);
  }

  const exercises = [...byExercise.entries()]
    .map(([exerciseId, rows]): ExerciseProgress => {
      const ordered = [...rows].sort((a, b) => time(b.completedAt) - time(a.completedAt));
      const latest = ordered[0]!;
      const lastSession = ordered
        .filter((log) => log.sessionId === latest.sessionId)
        .sort((a, b) => a.setNumber - b.setNumber)
        .map(({ setNumber, reps, loadKg, rir }) => ({ setNumber, reps, loadKg, rir }));
      const heaviest = rows
        .filter((log) => log.loadKg !== null)
        .sort((a, b) => b.loadKg! - a.loadKg! || b.reps - a.reps)[0];
      return {
        exerciseId,
        name: names.get(exerciseId) ?? exerciseId,
        lastPerformedAt: latest.completedAt,
        lastSession,
        heaviestSet: heaviest
          ? {
              setNumber: heaviest.setNumber,
              reps: heaviest.reps,
              loadKg: heaviest.loadKg,
              rir: heaviest.rir,
              completedAt: heaviest.completedAt,
            }
          : null,
        totalSets: rows.length,
      };
    })
    .sort((a, b) => time(b.lastPerformedAt) - time(a.lastPerformedAt));

  const latest = snapshot.feedback
    .filter((item) => programSessionIds.has(item.sessionId))
    .sort((a, b) => time(b.createdAt) - time(a.createdAt))[0];

  return {
    enrolled: true,
    completedSessions: programSessions.filter(
      (record) => (record as { status?: string }).status === 'completed',
    ).length,
    setsLast7Days: logs.filter((log) => now.getTime() - time(log.completedAt) <= 7 * DAY_MS).length,
    exercises,
    latestCheckIn: latest
      ? {
          soreness: latest.soreness,
          pump: latest.pump,
          performance: latest.performance,
          jointPain: latest.jointPain,
          createdAt: latest.createdAt,
        }
      : null,
  };
}
