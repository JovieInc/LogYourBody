import { describe, expect, it, vi } from 'vitest';
import { recordCorrection, recordCorrectionReceipt } from './correction-ledger';

it('keeps the first record at recurrence 0 and increments it to 1 on the same rule id', () => {
  const first = recordCorrection([], {
    ruleId: 'ci-invariant',
    correction: 'Keep the required check enabled.',
  });
  expect(first).toEqual([
    {
      ruleId: 'ci-invariant',
      correction: 'Keep the required check enabled.',
      recurrence: 0,
    },
  ]);

  const second = recordCorrection(first, {
    ruleId: 'ci-invariant',
    correction: 'The same check failed again under new wording.',
  });
  expect(first[0].recurrence).toBe(0);
  expect(second).toEqual([
    {
      ruleId: 'ci-invariant',
      correction: 'Keep the required check enabled.',
      recurrence: 1,
    },
  ]);
});

it('leaves the first count unchanged when the rule id differs', () => {
  const first = recordCorrection([], {
    ruleId: 'ci-invariant',
    correction: 'Keep the required check enabled.',
  });
  const next = recordCorrection(first, {
    ruleId: 'prose-guidance',
    correction: 'Document the release step in the runbook.',
  });
  expect(next).toEqual([
    {
      ruleId: 'ci-invariant',
      correction: 'Keep the required check enabled.',
      recurrence: 0,
    },
    {
      ruleId: 'prose-guidance',
      correction: 'Document the release step in the runbook.',
      recurrence: 0,
    },
  ]);
});

describe('receipt recurrence and mechanization (LYB-362)', () => {
  const correction = {
    ruleId: 'ci-invariant',
    correction: 'Keep the required check enabled.',
    level: 'static' as const,
    source: 'first-receipt',
  };

  it('records a first-seen receipt without enqueueing mechanization', () => {
    const enqueueMechanize = vi.fn();
    const ledger = recordCorrectionReceipt([], correction, enqueueMechanize);

    expect(ledger).toEqual([{ ...correction, recurrence: 0, isRecurrence: false }]);
    expect(enqueueMechanize).not.toHaveBeenCalled();
    expect(correction).not.toHaveProperty('isRecurrence');
  });

  it.each([
    correction.correction,
    '  KEEP the\t required\ncheck enabled.  ',
    'Ｋeep the required check enabled.',
  ])('marks a second matching receipt and enqueues exactly one request: %s', (text) => {
    const enqueueMechanize = vi.fn();
    const first = recordCorrectionReceipt([], correction, enqueueMechanize);
    const repeat = { ...correction, correction: text, source: 'second-receipt' };
    const ledger = recordCorrectionReceipt(first, repeat, enqueueMechanize);

    expect(ledger).toEqual([first[0], { ...repeat, recurrence: 1, isRecurrence: true }]);
    expect(first).toEqual([{ ...correction, recurrence: 0, isRecurrence: false }]);
    expect(enqueueMechanize).toHaveBeenCalledExactlyOnceWith({
      type: 'mechanize',
      correction: ledger[1],
    });
  });

  it('does not enqueue different text at the same level and rule id', () => {
    const enqueueMechanize = vi.fn();
    const first = recordCorrectionReceipt([], correction, enqueueMechanize);
    const different = { ...correction, correction: 'Preserve deployment evidence.' };
    const ledger = recordCorrectionReceipt(first, different, enqueueMechanize);

    expect(ledger[1]).toEqual({ ...different, recurrence: 0, isRecurrence: false });
    expect(enqueueMechanize).not.toHaveBeenCalled();

    const repeated = recordCorrectionReceipt(ledger, different, enqueueMechanize);
    expect(repeated[2]).toEqual({ ...different, recurrence: 1, isRecurrence: true });
    expect(enqueueMechanize).toHaveBeenCalledTimes(1);
  });

  it('does not enqueue the same text at a different classifier level', () => {
    const enqueueMechanize = vi.fn();
    const first = recordCorrectionReceipt([], correction, enqueueMechanize);
    const different = { ...correction, ruleId: 'code-prevention', level: 'codebase' as const };
    const ledger = recordCorrectionReceipt(first, different, enqueueMechanize);

    expect(ledger[1]).toEqual({ ...different, recurrence: 0, isRecurrence: false });
    expect(enqueueMechanize).not.toHaveBeenCalled();
  });

  it('matches by normalized text and level even when the classifier rule id differs', () => {
    const enqueueMechanize = vi.fn();
    const first = recordCorrectionReceipt([], correction, enqueueMechanize);
    const repeat = { ...correction, ruleId: 'file-pattern-or-string' };
    const ledger = recordCorrectionReceipt(first, repeat, enqueueMechanize);

    expect(ledger[1]).toEqual({ ...repeat, recurrence: 1, isRecurrence: true });
    expect(enqueueMechanize).toHaveBeenCalledTimes(1);
  });

  it('enqueues once per new repeated receipt, without re-emitting older requests', () => {
    const enqueueMechanize = vi.fn();
    const first = recordCorrectionReceipt([], correction, enqueueMechanize);
    const second = recordCorrectionReceipt(first, correction, enqueueMechanize);
    const third = recordCorrectionReceipt(second, correction, enqueueMechanize);

    expect(third.map(({ recurrence }) => recurrence)).toEqual([0, 1, 2]);
    expect(enqueueMechanize.mock.calls).toEqual([
      [{ type: 'mechanize', correction: second[1] }],
      [{ type: 'mechanize', correction: third[2] }],
    ]);
  });

  it('detects recurrence against an existing classified ledger receipt', () => {
    const enqueueMechanize = vi.fn();
    const ledger = recordCorrectionReceipt([correction], correction, enqueueMechanize);

    expect(ledger[1]).toEqual({ ...correction, recurrence: 1, isRecurrence: true });
    expect(enqueueMechanize).toHaveBeenCalledTimes(1);
  });

  it('propagates queue failures without changing the prior ledger', () => {
    const enqueueMechanize = vi.fn(() => {
      throw new Error('queue unavailable');
    });
    const first = recordCorrectionReceipt([], correction, enqueueMechanize);

    expect(() => recordCorrectionReceipt(first, correction, enqueueMechanize)).toThrow(
      'queue unavailable',
    );
    expect(first).toEqual([{ ...correction, recurrence: 0, isRecurrence: false }]);
    expect(enqueueMechanize).toHaveBeenCalledTimes(1);
  });

  it.each([
    { ...correction, ruleId: ' ' },
    { ...correction, correction: ' \t\n' },
  ])('rejects blank identity fields without enqueueing: %j', (invalid) => {
    const enqueueMechanize = vi.fn();

    expect(() => recordCorrectionReceipt([], invalid, enqueueMechanize)).toThrow(/is required/);
    expect(enqueueMechanize).not.toHaveBeenCalled();
  });
});
