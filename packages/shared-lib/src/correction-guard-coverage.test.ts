import { expect, it } from 'vitest';
import { correctionGuardCoverage } from './correction-guard-coverage';

const guardedLint = {
  level: 'static',
  guard: {
    path: 'packages/shared-lib/scripts/correction-ratchet.mjs',
    anchor: 'reject the new lint violation',
  },
};

const unguardedLint = { level: 'static' };

it('returns covered 0 and total 0 when the denominator is empty', () => {
  expect(correctionGuardCoverage([])).toEqual({ covered: 0, total: 0, ratio: null });
  expect(correctionGuardCoverage([{ level: 'human' }, { level: 'human-review' }])).toEqual({
    covered: 0,
    total: 0,
    ratio: null,
  });
});

it('counts one guarded and one unguarded lint correction as covered 1 of total 2', () => {
  const metric = correctionGuardCoverage([guardedLint, unguardedLint]);
  expect(metric.covered).toBe(1);
  expect(metric.total).toBe(2);
  expect(metric.ratio).toBe(0.5);
});

it('does not change the total when a prose correction is included', () => {
  const before = correctionGuardCoverage([guardedLint, unguardedLint]);
  const after = correctionGuardCoverage([
    guardedLint,
    unguardedLint,
    { level: 'prose', proseOnlyReason: 'Copy tone requires editorial judgment.' },
  ]);
  expect(after.total).toBe(before.total);
  expect(after).toEqual(before);
});

it('leaves a lint correction uncovered when its mechanized check is absent', () => {
  const metric = correctionGuardCoverage([
    { ...guardedLint, mechanized: false },
    { level: 'lint', mechanized: true },
  ]);
  expect(metric.covered).toBe(1);
  expect(metric.total).toBe(2);
  expect(metric.ratio).toBe(0.5);
});

it('counts a codebase correction as guarded without a mechanized check', () => {
  expect(correctionGuardCoverage([{ level: 'codebase' }])).toEqual({
    covered: 1,
    total: 1,
    ratio: 1,
  });
});

it('counts repeated receipts of one lint rule once', () => {
  const metric = correctionGuardCoverage([
    { ...guardedLint, fingerprint: 'lint rule' },
    { ...guardedLint, fingerprint: 'Lint-Rule', source: 'https://example.com/replay' },
    { ...unguardedLint, fingerprint: 'other-lint' },
  ]);
  expect(metric.covered).toBe(1);
  expect(metric.total).toBe(2);
});
