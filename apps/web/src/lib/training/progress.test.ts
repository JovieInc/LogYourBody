import type { ControllerReceipt } from './controller';
import { readTrainingProgress, summarizeTrainingProgress } from './progress';
import type { TrainingRecordsSnapshot } from './service';
import { TRAINING_CONSENT_VERSION } from './types';

const now = new Date('2026-01-20T12:00:00.000Z');

const decision = (rationale: string, after = 'Plan unchanged.'): ControllerReceipt => ({
  decision: { kind: 'adjust_training', adjustment: 'load_correction' },
  actor: 'controller',
  rationale,
  signalFreshness: { training: 'fresh', recovery: 'fresh', trajectory: 'missing' },
  evidenceIds: [],
  before: '2 sessions/week',
  after,
  reviewPoint: 'Next session',
  nextAction: 'Keep the saved session.',
});

function snapshot(): TrainingRecordsSnapshot {
  return {
    setup: {
      id: 'setup-id',
      consentVersion: TRAINING_CONSENT_VERSION,
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment: 'dumbbells',
      startedAt: '2026-01-05T00:00:00.000Z',
    },
    swaps: [],
    sessions: [
      {
        id: 'session-1',
        deleted_at: null,
        server_updated_at: '2026-01-19T00:00:00.000Z',
        record_type: 'workout_session',
        programSetupId: 'setup-id',
        status: 'completed',
        startedAt: '2026-01-19T00:00:00.000Z',
        prescription: {
          id: 'prescription-1',
          week: 1,
          slot: 0,
          pattern: 'A',
          title: 'Full body A',
          exercises: [
            {
              id: 'goblet_squat',
              name: 'Goblet squat',
              sets: 2,
              progression: 'hold',
            },
          ],
          safetyStop: false,
          explanation: null,
          evidenceIds: [],
          executionRevision: 1,
          executionPaused: false,
          executionEvents: [
            {
              id: 'event-skip',
              kind: 'skipped',
              createdAt: '2026-01-19T00:10:00.000Z',
              exerciseId: 'one_arm_dumbbell_row',
            },
            {
              id: 'event-pain',
              kind: 'pain',
              createdAt: '2026-01-19T00:11:00.000Z',
              exerciseId: 'dumbbell_curl',
            },
          ],
        },
        initialPrescription: {
          exercises: [
            { id: 'goblet_squat', name: 'Goblet squat' },
            { id: 'one_arm_dumbbell_row', name: 'One-arm dumbbell row' },
          ],
        },
      },
    ],
    logs: [
      {
        id: 'set-1',
        sessionId: 'session-1',
        exerciseId: 'goblet_squat',
        setNumber: 1,
        reps: 9,
        loadKg: 20,
        rir: 2,
        completedAt: '2026-01-19T00:20:00.000Z',
        corrections: [
          {
            id: 'corr-1',
            correctedAt: '2026-01-19T00:21:00.000Z',
            previous: { reps: 10, loadKg: 20, rir: 2 },
          },
        ],
      },
      {
        id: 'set-curl',
        sessionId: 'session-1',
        exerciseId: 'dumbbell_curl',
        setNumber: 1,
        reps: 8,
        loadKg: 10,
        rir: 3,
        completedAt: '2026-01-19T00:12:00.000Z',
      },
    ],
    feedback: [
      {
        id: 'feedback-1',
        sessionId: 'session-1',
        source: 'voice',
        sourceObservationId: 'spoken-1',
        createdAt: '2026-01-19T00:30:00.000Z',
        pump: 9,
        trunkFatigue: 2,
        interpretations: [
          {
            claim: 'goal_preference',
            timeframe: 'historical',
            confidence: 'moderate',
            proposedExplanation: 'upper chest',
          },
          {
            claim: 'goal_preference',
            timeframe: 'current',
            confidence: 'moderate',
            proposedExplanation: 'triceps',
          },
          {
            claim: 'pump',
            timeframe: 'current',
            confidence: 'low',
            proposedExplanation: 'The pump felt strong.',
          },
        ],
      },
    ],
  };
}

describe('training progress read', () => {
  it('reuses the history summary and keeps set, session, and feedback identity', () => {
    const records = snapshot();
    const read = readTrainingProgress(records, now, {
      decision: decision('High soreness supports holding the load.', 'Load held.'),
      proposed: {
        pattern: 'A',
        exercises: [{ id: 'goblet_squat', name: 'Goblet squat', sets: 1, progression: 'add_reps' }],
      },
    });

    expect(read).toMatchObject(summarizeTrainingProgress(records, now));
    expect(read.completedSessions).toBe(1);
    expect(read.setsLast7Days).toBe(2);
    expect(read.evidence.sessions[0]).toMatchObject({
      sessionId: 'session-1',
      prescriptionId: 'prescription-1',
      status: 'completed',
    });
    expect(read.evidence.sessions[0]?.exercises).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          exerciseId: 'goblet_squat',
          variantId: 'goblet_squat',
          status: 'completed',
          sets: [
            expect.objectContaining({
              id: 'set-1',
              reps: 9,
              status: 'completed',
              corrections: [
                expect.objectContaining({
                  id: 'corr-1',
                  previous: expect.objectContaining({ reps: 10 }),
                }),
              ],
            }),
          ],
        }),
        expect.objectContaining({
          exerciseId: 'one_arm_dumbbell_row',
          variantId: 'one_arm_dumbbell_row',
          name: 'One-arm dumbbell row',
          status: 'skipped',
          sets: [],
        }),
      ]),
    );
    expect(read.evidence.feedback[0]).toMatchObject({
      id: 'feedback-1',
      source: 'voice',
      sourceObservationId: 'spoken-1',
    });
    expect(read.review.explanations).toEqual([
      'High soreness supports holding the load.',
      'Goblet squat: set count changed from 2 to 1.',
      'Goblet squat: logged sets support add a rep.',
    ]);
    expect(read.review.repeatBlock).toEqual({
      reuseVariantIds: ['goblet_squat'],
      expiredPriorities: ['upper chest'],
      renewedPriorities: ['triceps'],
    });
  });

  it('does not infer hypertrophy from a pump or lower reported back fatigue', () => {
    const records = snapshot();
    const read = readTrainingProgress(records, now, {
      decision: decision('The pump shows hypertrophy and lower back fatigue means the back grew.'),
      proposed: {
        pattern: 'A',
        exercises: [{ id: 'goblet_squat', name: 'Goblet squat', sets: 2, progression: 'hold' }],
      },
    });

    expect(read.review.explanations.join(' ')).not.toMatch(/hypertrophy|grew|muscle growth/i);
    expect(read.review.explanations).not.toEqual(
      expect.arrayContaining([expect.stringMatching(/pump|back fatigue|trunk fatigue/i)]),
    );
  });

  it('drops a growth claim when the only recorded signals are pump and trunk fatigue', () => {
    const records = snapshot();
    const read = readTrainingProgress(records, now, {
      decision: decision('This block produced hypertrophy.', 'Dose increased.'),
    });
    expect(read.review.explanations).not.toContain('This block produced hypertrophy.');
  });
});
