import {
  CONCERNING_PAIN_MESSAGE,
  evaluateMovementPain,
  type MovementPainFeedback,
} from './pain-policy';

describe('concerning-pain movement policy (LYB-298)', () => {
  it.each<{ name: string; feedback: MovementPainFeedback }>([
    { name: 'persistent pain', feedback: { persistentPain: true } },
    { name: 'worsening pain', feedback: { worseningPain: true } },
    {
      name: 'neurologic symptoms without reported pain',
      feedback: { symptomFlags: ['neurologic'] },
    },
    {
      name: 'concerning pain alongside trunk fatigue',
      feedback: { persistentPain: true, worseningPain: true, trunkFatigue: 10 },
    },
    {
      name: 'all concerning flags',
      feedback: { persistentPain: true, worseningPain: true, symptomFlags: ['neurologic'] },
    },
  ])('pauses for $name with no swap or continued coaching', ({ feedback }) => {
    expect(evaluateMovementPain(feedback)).toEqual({
      action: 'pause_movement',
      swapAllowed: false,
      coachingAllowed: false,
      explanation: CONCERNING_PAIN_MESSAGE,
    });
  });

  it.each<{ name: string; feedback?: MovementPainFeedback }>([
    { name: 'missing feedback' },
    { name: 'unreported fields', feedback: {} },
    { name: 'trunk fatigue alone', feedback: { trunkFatigue: 10 } },
    { name: 'joint pain without concerning flags', feedback: { jointPain: 2 } },
    { name: 'a high pain score alone', feedback: { jointPain: 10 } },
    { name: 'a pain flag alone', feedback: { symptomFlags: ['pain'] } },
    {
      name: 'explicitly absent concerning flags',
      feedback: { persistentPain: false, worseningPain: false, symptomFlags: [], jointPain: 2 },
    },
  ])('leaves $name to the existing swap eligibility checks', ({ feedback }) => {
    expect(evaluateMovementPain(feedback)).toEqual({
      action: 'continue_to_swap',
      swapAllowed: true,
      explanation: null,
    });
  });

  it('locks the sole pause message without injury-prevention, load or continued-coaching assurances', () => {
    expect(CONCERNING_PAIN_MESSAGE).toBe(
      'Stop this movement. If pain is persistent, worsening, or includes numbness, weakness, or other neurologic symptoms, seek evaluation from a qualified clinician.',
    );
    expect(CONCERNING_PAIN_MESSAGE).not.toMatch(
      /injury[- ]prevention|prevent\w*.{0,30}injur|(?:zero|no|without) spinal load|safe/i,
    );
  });
});
