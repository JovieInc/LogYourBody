import { expect, it } from 'vitest';
import { classifyCorrectionRecords, recordCorrection } from './correction-ledger';

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
