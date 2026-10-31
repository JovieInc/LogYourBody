import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

type WinDecision = {
  allowed_win_kinds?: unknown;
  vanity_counters_allowed?: unknown;
  fabricated_impact_allowed?: unknown;
};

// Package-local decisions are Turbo inputs, so editing the record invalidates
// the existing shared-lib CI test cache without changing workflow configuration.
const record: WinDecision = JSON.parse(
  readFileSync(new URL('../decisions/earned-win-eligibility.json', import.meta.url), 'utf8'),
);
const allowedWinKinds = new Set([
  'goal_relative_gain',
  'first_ever_milestone',
  'measured_time_saved',
]);

function validateRecord(value: WinDecision) {
  assert(Array.isArray(value.allowed_win_kinds), 'allowed_win_kinds must be an array');
  assert(value.allowed_win_kinds.length > 0, 'allowed_win_kinds must be non-empty');
  for (const kind of value.allowed_win_kinds) {
    assert(allowedWinKinds.has(kind), 'Unknown celebration win kind');
  }
  assert.equal(value.vanity_counters_allowed, false, 'Vanity counters must be disabled');
  assert.equal(value.fabricated_impact_allowed, false, 'Fabricated impact must be disabled');
}

describe('LYB-305 earned-win eligibility decision', () => {
  it('loads a non-empty allowed subset and explicitly disables vanity and fabricated impact', () => {
    validateRecord(record);
  });

  it.each([...allowedWinKinds])('accepts the permitted singleton subset: %s', (kind) => {
    validateRecord({ ...record, allowed_win_kinds: [kind] });
  });

  it.each(['daily_streak', 'app_opens', '', null, 42, {}])(
    'rejects an unknown win kind even alongside permitted kinds: %j',
    (kind) => {
      expect(() =>
        validateRecord({ ...record, allowed_win_kinds: [...allowedWinKinds, kind] }),
      ).toThrow(/Unknown celebration win kind/);
    },
  );

  it.each([undefined, null, [], '', 'goal_relative_gain', {}])(
    'rejects missing, empty or malformed allowed_win_kinds: %j',
    (kinds) => {
      expect(() => validateRecord({ ...record, allowed_win_kinds: kinds })).toThrow(
        /allowed_win_kinds/,
      );
    },
  );

  for (const flag of ['vanity_counters_allowed', 'fabricated_impact_allowed'] as const) {
    it.each([true, undefined, null, 0, 'false'])(`rejects ${flag} = %j`, (value) => {
      expect(() => validateRecord({ ...record, [flag]: value })).toThrow(/must be disabled/);
    });
  }
});
