import { describe, expect, it } from '@jest/globals';
import { evaluateSpokenReply } from './spoken-reply-eval';

describe('spoken reply eval', () => {
  it('accepts the approved short command-line style', () => {
    expect(
      evaluateSpokenReply('Start the next set.', 'Stop here. Rack it. Two minutes.').passed,
    ).toBe(true);
  });

  it('fails an unasked-for reply over twelve words', () => {
    expect(
      evaluateSpokenReply(
        'I finished my set.',
        'You should rack the weight now and rest for two minutes before starting your next set.',
      ),
    ).toMatchObject({ passed: false, violations: ['word_limit'] });
  });

  it('fails more than two substantive sentence beats even below twelve words', () => {
    expect(
      evaluateSpokenReply(
        'I finished my set.',
        'Stop your set now. Put the weights down. Rest for two minutes.',
      ),
    ).toMatchObject({ passed: false, words: 12, sentences: 3, violations: ['sentence_limit'] });
  });

  it('allows a longer answer when the user asked a question', () => {
    expect(
      evaluateSpokenReply(
        'Why should I rest between sets?',
        'Rest between sets so your performance can recover. If you shorten the rest, your later sets may lose reps or load.',
      ),
    ).toMatchObject({ passed: true, questionException: true, violations: [] });
  });
});
