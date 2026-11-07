import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Package-local decisions are Turbo inputs, so editing this record invalidates
// the existing shared-lib CI test cache without a workflow change.
const record = JSON.parse(
  readFileSync(new URL('../decisions/exercise-safety-bounds.json', import.meta.url), 'utf8'),
);

const REQUIRED_KEYS = [
  'deload_deferral',
  'plan_edit_limit',
  'minimum_days_between_dexa_suggestions',
  'diagnosis_allowed',
  'silent_consequential_plan_change',
] as const;

const IN_BOUND_LIMIT = 'in_bound_training_plan_adjustments_only';
const MINIMUM_DEXA_SUGGESTION_DAYS = 30;

type BoundsRecord = {
  id?: unknown;
  parent?: unknown;
  status?: unknown;
  deload_deferral?: {
    limit?: unknown;
    max_unreviewed_bound_crossings?: unknown;
    override_requires_visible_review_checkpoint?: unknown;
    retains_current_plan_when_check_ins_do_not_support_deload?: unknown;
    pain_pause_remains_authoritative?: unknown;
    planned_deload_remains_authoritative?: unknown;
  } | null;
  plan_edit_limit?: {
    limit?: unknown;
    max_unreviewed_consequential_edits?: unknown;
    unsupported_edits_allowed?: unknown;
    consequential_override_requires_visible_review_checkpoint?: unknown;
  } | null;
  minimum_days_between_dexa_suggestions?: unknown;
  dexa_suggestion?: {
    insist?: unknown;
    only_when_goal_needs_measurement?: unknown;
  } | null;
  diagnosis_allowed?: unknown;
  silent_consequential_plan_change?: unknown;
};

function assertFalseFlag(value: unknown, key: string) {
  assert.equal(value, false, `${key} must be false`);
}

function assertZero(value: unknown, key: string) {
  assert.equal(value, 0, `${key} must be 0`);
}

function validateBounds(value: BoundsRecord) {
  for (const key of REQUIRED_KEYS) {
    assert(Object.prototype.hasOwnProperty.call(value, key), `missing required key: ${key}`);
  }

  const deload = value.deload_deferral;
  assert(deload && typeof deload === 'object', 'deload_deferral must be an object');
  assert.equal(deload.limit, IN_BOUND_LIMIT, 'deload_deferral.limit is outside the accepted bound');
  assertZero(
    deload.max_unreviewed_bound_crossings,
    'deload_deferral.max_unreviewed_bound_crossings',
  );
  assert.equal(
    deload.override_requires_visible_review_checkpoint,
    true,
    'deload_deferral.override_requires_visible_review_checkpoint must be true',
  );
  assert.equal(
    deload.retains_current_plan_when_check_ins_do_not_support_deload,
    true,
    'deload_deferral.retains_current_plan_when_check_ins_do_not_support_deload must be true',
  );
  assert.equal(
    deload.pain_pause_remains_authoritative,
    true,
    'deload_deferral.pain_pause_remains_authoritative must be true',
  );
  assert.equal(
    deload.planned_deload_remains_authoritative,
    true,
    'deload_deferral.planned_deload_remains_authoritative must be true',
  );

  const planEdit = value.plan_edit_limit;
  assert(planEdit && typeof planEdit === 'object', 'plan_edit_limit must be an object');
  assert.equal(
    planEdit.limit,
    IN_BOUND_LIMIT,
    'plan_edit_limit.limit is outside the accepted bound',
  );
  assertZero(
    planEdit.max_unreviewed_consequential_edits,
    'plan_edit_limit.max_unreviewed_consequential_edits',
  );
  assertFalseFlag(planEdit.unsupported_edits_allowed, 'plan_edit_limit.unsupported_edits_allowed');
  assert.equal(
    planEdit.consequential_override_requires_visible_review_checkpoint,
    true,
    'plan_edit_limit.consequential_override_requires_visible_review_checkpoint must be true',
  );

  const dexaDays = value.minimum_days_between_dexa_suggestions;
  assert(
    typeof dexaDays === 'number' && Number.isFinite(dexaDays) && Number.isInteger(dexaDays),
    'minimum_days_between_dexa_suggestions must be a finite integer',
  );
  assert(
    dexaDays >= MINIMUM_DEXA_SUGGESTION_DAYS,
    'minimum_days_between_dexa_suggestions must be at least 30 days',
  );

  const dexa = value.dexa_suggestion;
  assert(dexa && typeof dexa === 'object', 'dexa_suggestion must be an object');
  assertFalseFlag(dexa.insist, 'dexa_suggestion.insist');
  assert.equal(
    dexa.only_when_goal_needs_measurement,
    true,
    'dexa_suggestion.only_when_goal_needs_measurement must be true',
  );

  assertFalseFlag(value.diagnosis_allowed, 'diagnosis_allowed');
  assertFalseFlag(value.silent_consequential_plan_change, 'silent_consequential_plan_change');
}

function withoutKey(key: string): BoundsRecord {
  const candidate = JSON.parse(JSON.stringify(record)) as BoundsRecord;
  delete candidate[key as keyof BoundsRecord];
  return candidate;
}

describe('LYB-303 exercise safety bounds', () => {
  it('loads the required keys, a numeric DEXA interval, and diagnosis_allowed false', () => {
    validateBounds(record);
    expect(record).toMatchObject({
      id: 'LYB-303',
      parent: 'LYB-173',
      status: 'accepted',
      diagnosis_allowed: false,
      silent_consequential_plan_change: false,
    });
    expect(record.minimum_days_between_dexa_suggestions).toBeTypeOf('number');
    expect(record.minimum_days_between_dexa_suggestions).toBe(MINIMUM_DEXA_SUGGESTION_DAYS);
    expect(record.diagnosis_allowed).toBe(false);
  });

  it.each(REQUIRED_KEYS)('fails when %s is missing', (key) => {
    expect(() => validateBounds(withoutKey(key))).toThrow(
      new RegExp(`missing required key: ${key}`),
    );
  });

  it.each([true, 'false', 0, null, undefined])('rejects diagnosis_allowed = %j', (value) => {
    expect(() => validateBounds({ ...record, diagnosis_allowed: value })).toThrow(
      /diagnosis_allowed/,
    );
  });

  it.each([true, 'false', 0, null, undefined])(
    'rejects silent_consequential_plan_change = %j',
    (value) => {
      expect(() => validateBounds({ ...record, silent_consequential_plan_change: value })).toThrow(
        /silent_consequential_plan_change/,
      );
    },
  );

  it.each([undefined, null, '30', true, Number.NaN, Number.POSITIVE_INFINITY, 0, -1, 29, 29.5])(
    'rejects a non-numeric or too-short DEXA interval: %j',
    (value) => {
      expect(() =>
        validateBounds({ ...record, minimum_days_between_dexa_suggestions: value }),
      ).toThrow(/minimum_days_between_dexa_suggestions/);
    },
  );

  it('rejects an empty deload deferral or plan-edit limit', () => {
    expect(() => validateBounds({ ...record, deload_deferral: {} })).toThrow(/deload_deferral/);
    expect(() => validateBounds({ ...record, plan_edit_limit: {} })).toThrow(/plan_edit_limit/);
    expect(() => validateBounds({ ...record, deload_deferral: null })).toThrow(/deload_deferral/);
    expect(() => validateBounds({ ...record, plan_edit_limit: null })).toThrow(/plan_edit_limit/);
  });
});
