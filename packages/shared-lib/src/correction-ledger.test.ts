import { describe, expect, it, vi } from 'vitest';
import {
  classifyCorrectionRecords,
  correctionPyramidCoverage,
  recordCorrection,
  recordCorrectionReceipt,
} from './correction-ledger';

const feasible = { feasible: true, rationale: 'This mechanism enforces the full invariant.' };
const infeasible = {
  feasible: false,
  rationale: 'This mechanism cannot enforce the full invariant.',
};
const classificationFixtures = [
  {
    ruleId: 'typed-state',
    correction: 'Prevent invalid state through the type.',
    expected: 'codebase',
    classification: { human: feasible, prose: feasible, static: feasible, codebase: feasible },
  },
  {
    ruleId: 'ci-invariant',
    correction: 'Compare coverage with the immutable Git base in CI.',
    expected: 'static',
    classification: { codebase: infeasible, static: feasible, prose: feasible, human: feasible },
  },
  {
    ruleId: 'prose-guidance',
    correction: 'Describe the purpose of a manual investigation in the runbook.',
    expected: 'prose',
    classification: { codebase: infeasible, static: infeasible, prose: feasible, human: feasible },
  },
  {
    ruleId: 'human-judgment',
    correction: 'An account owner must decide whether to accept external terms.',
    expected: 'human',
    classification: {
      codebase: infeasible,
      static: infeasible,
      prose: infeasible,
      human: feasible,
    },
  },
] as const;

it.each(classificationFixtures)(
  'assigns exactly $expected to $ruleId',
  ({ expected, ...correction }) => {
    const ledger = recordCorrection([], correction);
    const result = classifyCorrectionRecords(ledger);
    expect(result).toEqual([{ ...ledger[0], level: expected }]);
    expect(ledger[0]).not.toHaveProperty('level');
    expect(classifyCorrectionRecords(result)).toEqual(result);
  },
);

it.each(classificationFixtures.slice(0, 2))(
  'replaces a human-review mislabel with $expected for $ruleId',
  ({ expected, ...correction }) => {
    const ledger = recordCorrection([], { ...correction, level: 'human' as const });
    const repeated = recordCorrection(ledger, { ...correction, level: 'human' as const });
    const result = classifyCorrectionRecords(
      Object.freeze(repeated.map((record) => Object.freeze(record))),
    );
    expect(result).toEqual([{ ...repeated[0], level: expected }]);
    expect(result[0].recurrence).toBe(1);
    expect(repeated[0].level).toBe('human');
  },
);

it('classifies every record in a mixed ledger without dropping or reordering corrections', () => {
  const ledger = classificationFixtures.map((fixture, recurrence) => ({
    ruleId: fixture.ruleId,
    correction: fixture.correction,
    classification: fixture.classification,
    recurrence,
  }));
  expect(classifyCorrectionRecords(ledger)).toEqual(
    ledger.map((record, index) => ({ ...record, level: classificationFixtures[index].expected })),
  );
});

it('returns an empty ledger when there are no corrections', () => {
  expect(classifyCorrectionRecords([])).toEqual([]);
});

describe('pyramid coverage (LYB-363)', () => {
  it('counts classified ledger records by level and reports the mechanized share', () => {
    const records = [0, 0, 1, 1, 1, 2, 3].map((fixtureIndex, index) => {
      const { ruleId, correction, classification } = classificationFixtures[fixtureIndex];
      return { ruleId: `${ruleId}-${index}`, correction, classification, recurrence: index * 10 };
    });
    const ledger = Object.freeze(
      classifyCorrectionRecords(records).map((record) => Object.freeze(record)),
    );

    expect(correctionPyramidCoverage(ledger)).toEqual({
      levels: { codebase: 2, static: 3, prose: 1, human: 1 },
      total: 7,
      mechanized: 5,
      mechanizedShare: 5 / 7,
    });
  });

  it('returns defined zero counts and share for an empty ledger', () => {
    expect(correctionPyramidCoverage([])).toEqual({
      levels: { codebase: 0, static: 0, prose: 0, human: 0 },
      total: 0,
      mechanized: 0,
      mechanizedShare: 0,
    });
  });

  it.each([
    { level: 'codebase', mechanized: 1 },
    { level: 'static', mechanized: 1 },
    { level: 'prose', mechanized: 0 },
    { level: 'human', mechanized: 0 },
  ] as const)('reports a share of $mechanized for a $level correction', ({ level, mechanized }) => {
    expect(correctionPyramidCoverage([{ level }])).toEqual({
      levels: { codebase: 0, static: 0, prose: 0, human: 0, [level]: 1 },
      total: 1,
      mechanized,
      mechanizedShare: mechanized,
    });
  });
});

it.each([{}, { codebase: infeasible, static: infeasible, prose: infeasible, human: infeasible }])(
  'refuses incomplete or unenforceable assessments instead of defaulting to human',
  (classification) => {
    const ledger = recordCorrection([], { ruleId: 'unreviewed', classification });
    expect(() => classifyCorrectionRecords(ledger)).toThrow(/assessment required|no enforceable/);
    expect(ledger[0]).not.toHaveProperty('level');
  },
);

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
