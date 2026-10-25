import { catalogVariantById } from './catalog';
import { latestFeedbackPerSession } from './engine';
import type { TrainingRecordsSnapshot } from './service';
import type { Session, SetLog, TrainingFeedback } from './types';

export type ExerciseProgress = {
  exerciseId: string;
  name: string;
  lastPerformedAt: string;
  lastSession: SetLog[];
  heaviestSet: SetLog | null;
  totalSets: number;
};

/** Readback only: retain the saved variant and interruption decisions, including
 * skipped movements removed from the current prescription. Never rebuild history
 * from today's catalog or carry temporary priorities into a new block. */
export type TrainingProgressSession = {
  sessionId: string;
  programSetupId: string;
  programRevisionId: string | null;
  blockId: string | null;
  status: string;
  startedAt: string | null;
  completedAt: string | null;
  initialPrescription: Session | null;
  prescription: Session | null;
  sets: SetLog[];
  feedback: TrainingFeedback[];
};

export type TrainingProgress = {
  enrolled: boolean;
  completedSessions: number;
  setsLast7Days: number;
  exercises: ExerciseProgress[];
  latestCheckIn: TrainingFeedback | null;
  sessions: TrainingProgressSession[];
};

const DAY_MS = 24 * 60 * 60 * 1000;

function exerciseNames(sessions: TrainingRecordsSnapshot['sessions']): Map<string, string> {
  const names = new Map<string, string>();
  for (const record of sessions) {
    for (const field of ['initialPrescription', 'prescription'] as const) {
      const prescription = record[field] as Session | undefined;
      for (const exercise of prescription?.exercises ?? []) names.set(exercise.id, exercise.name);
    }
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
      sessions: [],
    };
  }
  const programSessions = snapshot.sessions.filter(
    (record) => (record as { programSetupId?: string }).programSetupId === setup.id,
  );
  const programSessionIds = new Set(programSessions.map((record) => record.id));
  const recordedLogs = snapshot.logs.filter((log) => programSessionIds.has(log.sessionId));
  const logs = recordedLogs.filter((log) => time(log.completedAt) <= now.getTime());
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
        .sort((a, b) => a.setNumber - b.setNumber);
      const heaviest = rows
        .filter((log) => log.loadKg !== null)
        .sort((a, b) => b.loadKg! - a.loadKg! || b.reps - a.reps)[0];
      return {
        exerciseId,
        name: names.get(exerciseId) ?? catalogVariantById(exerciseId)?.name ?? exerciseId,
        lastPerformedAt: latest.completedAt,
        lastSession,
        heaviestSet: heaviest ?? null,
        totalSets: rows.length,
      };
    })
    .sort((a, b) => time(b.lastPerformedAt) - time(a.lastPerformedAt));

  const feedback = snapshot.feedback.filter((item) => programSessionIds.has(item.sessionId));
  const latest = latestFeedbackPerSession(feedback)[0];

  return {
    enrolled: true,
    completedSessions: programSessions.filter(
      (record) => (record as { status?: string }).status === 'completed',
    ).length,
    setsLast7Days: logs.filter((log) => now.getTime() - time(log.completedAt) <= 7 * DAY_MS).length,
    exercises,
    latestCheckIn: latest ?? null,
    sessions: programSessions
      .map((record): TrainingProgressSession => ({
        sessionId: record.id,
        programSetupId: setup.id,
        programRevisionId:
          typeof record.programRevisionId === 'string' ? record.programRevisionId : null,
        blockId: typeof record.blockId === 'string' ? record.blockId : null,
        status: typeof record.status === 'string' ? record.status : 'unknown',
        startedAt: typeof record.startedAt === 'string' ? record.startedAt : null,
        completedAt: typeof record.completedAt === 'string' ? record.completedAt : null,
        initialPrescription: (record.initialPrescription as Session | undefined) ?? null,
        prescription: (record.prescription as Session | undefined) ?? null,
        sets: recordedLogs.filter((log) => log.sessionId === record.id),
        feedback: feedback.filter((item) => item.sessionId === record.id),
      }))
      .sort(
        (a, b) =>
          time(b.startedAt ?? b.completedAt ?? '') - time(a.startedAt ?? a.completedAt ?? ''),
      ),
  };
}
