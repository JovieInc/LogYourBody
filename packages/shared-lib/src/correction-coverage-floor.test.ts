import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const decision = JSON.parse(
  readFileSync(new URL('../correction-coverage-floor.json', import.meta.url), 'utf8'),
);

function assertSingleCoverageFloor(rules: unknown[]) {
  assert.equal(rules.length, 1, 'LYB must have exactly one correction-pyramid coverage floor');
  assert.deepEqual(rules[0], {
    id: 'mechanized-share-nonregression',
    metric: 'correctionPyramidCoverage.mechanizedShare',
    baseline: 'last-recorded',
    failWhen: 'current-less-than-baseline',
    absoluteFloor: null,
  });
}

describe('correction-pyramid coverage floor decision (LYB-364)', () => {
  it('records one baseline nonregression rule with no absolute percentage floor', () => {
    expect(decision.schema).toBe('lyb.correction-coverage-floor/v1');
    expect(decision.decision).toBe('LYB-364');
    assertSingleCoverageFloor(decision.rules);
  });

  it('keeps the recommendation inactive behind a default-off flag for future implementation', () => {
    expect(decision.status).toBe('recommended-default');
    expect(decision.activation).toEqual({
      featureGate: 'lyb_correction_pyramid_coverage_floor',
      defaultEnabled: false,
      implemented: false,
    });
  });

  it('rejects a second conflicting coverage floor', () => {
    const conflictingFloor = { ...decision.rules[0], absoluteFloor: 0.8 };
    expect(() => assertSingleCoverageFloor([...decision.rules, conflictingFloor])).toThrow(
      'LYB must have exactly one correction-pyramid coverage floor',
    );
  });
});
