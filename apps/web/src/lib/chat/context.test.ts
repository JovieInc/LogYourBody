import { buildChatModelMessages, isTrainingQuestion } from './context';
import type { NextWorkoutResult } from '@/lib/training/service';

describe('buildChatModelMessages', () => {
  it('limits training guidance to authorized engine output and supplied evidence IDs', () => {
    const [systemMessage] = buildChatModelMessages({
      user: null,
      metrics: [],
      conversationMessages: [],
    });

    expect(systemMessage.role).toBe('system');
    expect(systemMessage.content).toContain(
      'narrate only recommendations returned by the deterministic programming engine',
    );
    expect(systemMessage.content).toContain(
      'cite each supporting evidence ID in its exact [k:id] form',
    );
    expect(systemMessage.content).toContain('Never invent, calculate, select, or adjust exercises');
    expect(systemMessage.content).toContain('no authorized training guidance is available');
  });

  it('retains body-image safety and server-scoped context boundaries', () => {
    const [systemMessage] = buildChatModelMessages({
      user: null,
      metrics: [],
      conversationMessages: [],
    });

    expect(systemMessage.content).toContain(
      'Use only the authorized context below and the conversation',
    );
    expect(systemMessage.content).toContain(
      'Do not provide prescriptive aesthetic coaching for minors',
    );
    expect(systemMessage.content).toContain('Never infer goals from immutable traits or gender');
    expect(systemMessage.content).toContain('Authorized body context (server-scoped to this user)');
  });

  it('passes only the approved profile and metric fields to the model', () => {
    const [systemMessage, userMessage] = buildChatModelMessages({
      user: {
        subject: 'test-user',
        email: 'not-forwarded@example.test',
        profileData: {
          height: 170,
          height_unit: 'cm',
          goal_weight: 72,
          goal_weight_unit: 'kg',
          privateNote: 'not forwarded',
        },
      },
      metrics: [
        {
          id: 'test-metric',
          user_subject: 'test-user',
          date: '2026-09-25',
          weight: 72,
          weight_unit: 'kg',
          body_fat_percentage: 20,
          body_fat_method: 'test',
          muscle_mass: 55,
          waist: null,
          neck: null,
          hip: null,
          notes: 'not forwarded',
          photo_url: 'not-forwarded',
          data_source: 'test',
          source_metadata: {},
          created_at: '2026-09-25T00:00:00Z',
          updated_at: '2026-09-25T00:00:00Z',
        },
      ],
      conversationMessages: [
        {
          id: 'test-message',
          role: 'user',
          content: 'Summarize the available data.',
          clientMessageId: null,
          createdAt: '2026-09-25T00:00:00Z',
        },
      ],
    });

    expect(systemMessage.content).toContain(
      '"height":170,"heightUnit":"cm","goalWeight":72,"goalWeightUnit":"kg"',
    );
    expect(systemMessage.content).toContain('"bodyFatPercentage":20,"muscleMass":55');
    expect(systemMessage.content).not.toContain('not-forwarded');
    expect(systemMessage.content).not.toContain('privateNote');
    expect(userMessage).toEqual({ role: 'user', content: 'Summarize the available data.' });
  });

  it('passes prescription numbers and citations only from a returned engine session', () => {
    const trainingOutput: NextWorkoutResult = {
      kind: 'workout',
      week: 2,
      weekCount: 2,
      weeklyFractionalVolume: { chest: 4 },
      session: {
        id: 'engine-session',
        week: 2,
        slot: 0,
        pattern: 'A',
        title: 'Full body A',
        safetyStop: false,
        explanation: null,
        evidenceIds: ['k:81c218db'],
        exercises: [
          {
            id: 'goblet_squat',
            name: 'Goblet squat',
            primaryMuscle: 'quads',
            muscleContribution: { quads: 1 },
            sets: 2,
            repRange: { min: 8, max: 12 },
            targetReps: 9,
            targetRir: 3,
            targetLoadKg: null,
            loadInstruction: null,
            progression: 'add_reps',
            evidenceIds: ['k:1795aef0'],
          },
        ],
      },
    };
    const [systemMessage] = buildChatModelMessages({
      user: null,
      metrics: [],
      conversationMessages: [],
      trainingOutput,
    });
    expect(systemMessage.content).toContain('"targetReps":9');
    expect(systemMessage.content).toContain('"sets":2');
    expect(systemMessage.content).toContain('"evidenceIds":["[k:1795aef0]"]');
    expect(systemMessage.content).toContain('"targetLoadKg":null');
    expect(systemMessage.content).not.toContain('targetLoadKg":15');
  });
});

describe('isTrainingQuestion', () => {
  it('recognizes lifting load requests without misclassifying ordinary body-weight questions', () => {
    expect(isTrainingQuestion('What weight should I use?')).toBe(true);
    expect(isTrainingQuestion('How much load should I add?')).toBe(true);
    expect(isTrainingQuestion('Summarize my body weight trend.')).toBe(false);
  });
});

describe('voice reply mode', () => {
  it('adds brief spoken-reply rules only to turns marked for speech', () => {
    const base = {
      user: null,
      metrics: [],
      conversationMessages: [],
    };
    const [normalSystemMessage] = buildChatModelMessages(base);
    const [voiceSystemMessage] = buildChatModelMessages({ ...base, voiceMode: true });

    expect(normalSystemMessage.content).not.toContain('Voice reply mode is active');
    expect(voiceSystemMessage.content).toContain('one brief, direct imperative line');
    expect(voiceSystemMessage.content).toContain('about 12 words');
    expect(voiceSystemMessage.content).toContain('If the user explicitly asks a question');
  });
});
