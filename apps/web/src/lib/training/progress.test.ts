import { summarizeTrainingProgress } from './progress';
import type { TrainingRecordsSnapshot } from './service';
import type { Session, SetLog } from './types';

const now = new Date('2026-10-25T12:00:00.000Z');
const prescription = {
  id: 'session-a',
  exercises: [{ id: 'curl', name: 'Recorded curl variant', sets: 2 }],
  executionEvents: [{ id: 'skip-1', kind: 'skipped', exerciseId: 'press' }],
} as Session;
const corrected: SetLog = {
  id: 'set-a',
  sessionId: 'session-a',
  exerciseId: 'curl',
  setNumber: 1,
  reps: 8,
  loadKg: 12,
  rir: 2,
  completedAt: '2026-10-25T10:00:00.000Z',
  revision: 1,
  corrections: [
    {
      id: 'correction-a',
      correctedAt: now.toISOString(),
      previous: { reps: 10, loadKg: 120, rir: 3 },
    },
  ],
};

function snapshot(): TrainingRecordsSnapshot {
  return {
    setup: { id: 'setup-a' } as TrainingRecordsSnapshot['setup'],
    swaps: [],
    sessions: [
      {
        id: 'session-a',
        programSetupId: 'setup-a',
        blockId: 'block-a',
        programRevisionId: 'revision-a',
        status: 'completed',
        prescription,
        initialPrescription: {
          ...prescription,
          exercises: [...prescription.exercises, { id: 'press' }],
        },
        server_updated_at: now.toISOString(),
        deleted_at: null,
      },
    ],
    logs: [corrected],
    feedback: [
      {
        id: 'feedback-a',
        sessionId: 'session-a',
        pump: 9,
        trunkFatigue: 1,
        source: 'voice',
        sourceObservationId: 'voice-a',
        correctsObservationId: 'feedback-old',
        originalStatement: 'Less back fatigue today',
        createdAt: now.toISOString(),
      },
    ],
  };
}

describe('shared training progress read model', () => {
  it('retains exact variant, session, set and correction identities and feedback provenance', () => {
    const progress = summarizeTrainingProgress(snapshot(), now);
    expect(progress.exercises[0]).toMatchObject({
      exerciseId: 'curl',
      name: 'Recorded curl variant',
      lastSession: [corrected],
      heaviestSet: corrected,
    });
    expect(progress.sessions[0]).toMatchObject({
      sessionId: 'session-a',
      programSetupId: 'setup-a',
      programRevisionId: 'revision-a',
      blockId: 'block-a',
      status: 'completed',
      prescription,
      initialPrescription: { exercises: [{ id: 'curl' }, { id: 'press' }] },
      sets: [corrected],
      feedback: snapshot().feedback,
    });
    expect(progress.latestCheckIn).toEqual(snapshot().feedback[0]);
    // Pump and tolerability remain observations; the read model adds no growth claim or prescription.
    expect(progress).not.toHaveProperty('recommendation');
  });

  it('isolates the active enrollment and counts only valid sets within the last seven days', () => {
    const input = snapshot();
    input.sessions.push({ ...input.sessions[0]!, id: 'other', programSetupId: 'old-setup' });
    input.logs.push(
      { ...corrected, id: 'foreign', sessionId: 'other' },
      { ...corrected, id: 'future', completedAt: '2026-10-26T00:00:00.000Z' },
      { ...corrected, id: 'invalid', completedAt: 'invalid' },
      { ...corrected, id: 'old', completedAt: '2026-10-18T11:59:59.999Z' },
      { ...corrected, id: 'boundary', completedAt: '2026-10-18T12:00:00.000Z' },
    );
    const progress = summarizeTrainingProgress(input, now);
    expect(progress.completedSessions).toBe(1);
    expect(progress.setsLast7Days).toBe(2);
    expect(progress.exercises[0]?.totalSets).toBe(3);
    expect(progress.sessions).toHaveLength(1);
    expect(progress.sessions[0]?.sets.map((set) => set.id)).toContain('future');
    expect(progress.sessions[0]?.sets.map((set) => set.id)).not.toContain('foreign');
  });

  it('preserves an explicit skip even when there are no sets and never infers completion', () => {
    const input = snapshot();
    input.logs = [];
    input.sessions[0]!.status = 'paused';
    const progress = summarizeTrainingProgress(input, now);
    expect(progress.completedSessions).toBe(0);
    expect(progress.exercises).toEqual([]);
    expect(progress.sessions[0]).toMatchObject({
      status: 'paused',
      sets: [],
      prescription: { executionEvents: [{ kind: 'skipped', exerciseId: 'press' }] },
    });
  });

  it('keeps superseded feedback for audit but selects its correction for the latest check-in', () => {
    const input = snapshot();
    const correction = input.feedback[0]!;
    input.feedback.unshift({
      ...correction,
      id: 'feedback-old',
      correctsObservationId: undefined,
      pump: 2,
    });
    const progress = summarizeTrainingProgress(input, now);
    expect(progress.latestCheckIn).toEqual(correction);
    expect(progress.sessions[0]?.feedback).toHaveLength(2);
  });

  it('returns an empty history after enrollment is revoked', () => {
    expect(summarizeTrainingProgress({ ...snapshot(), setup: null }, now)).toEqual({
      enrolled: false,
      completedSessions: 0,
      setsLast7Days: 0,
      exercises: [],
      latestCheckIn: null,
      sessions: [],
    });
  });
});
