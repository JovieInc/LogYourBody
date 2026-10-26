import { expect, it } from 'vitest';
import { recordCorrection } from './correction-ledger';

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
