import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const decision = JSON.parse(
  readFileSync(new URL('../correction-promotion-rule.json', import.meta.url), 'utf8'),
);

function assertSinglePromotionRule(rules: unknown[]) {
  assert.equal(rules.length, 1, 'LYB must have exactly one warn-to-ratchet promotion rule');
  assert.deepEqual(rules[0], {
    id: 'warn-to-ratchet',
    from: 'warn',
    to: 'blocking',
    repeatCountAtLeast: 2,
    excludedLevels: ['prose', 'human'],
  });
}

describe('warn-to-ratchet decision (LYB-361)', () => {
  it('records one promotion rule with the recommended threshold and exceptions', () => {
    expect(decision.schema).toBe('lyb.correction-promotion/v1');
    assertSinglePromotionRule(decision.rules);
  });

  it('keeps the recommendation inactive behind a default-off flag for future implementation', () => {
    expect(decision.status).toBe('recommended-default');
    expect(decision.activation).toEqual({
      featureGate: 'lyb_warn_to_ratchet_promotion',
      defaultEnabled: false,
      implemented: false,
    });
  });

  it('rejects a second conflicting promotion rule', () => {
    const conflictingRule = { ...decision.rules[0], repeatCountAtLeast: 1 };
    expect(() => assertSinglePromotionRule([...decision.rules, conflictingRule])).toThrow(
      'LYB must have exactly one warn-to-ratchet promotion rule',
    );
  });
});
