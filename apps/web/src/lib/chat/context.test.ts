import { buildChatModelMessages } from './context';

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
      'cite only opaque evidence IDs supplied with that output',
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
});
