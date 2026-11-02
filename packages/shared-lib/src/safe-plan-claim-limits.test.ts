import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

type DateRule = {
  fixtureInput: string;
  recoveryState: string;
  contractPath: string;
  basis: string;
  exposedClaimIds: string[];
};

type ClaimTable = {
  id: string;
  parent: string;
  status: string;
  approvalBasis: string;
  appliesTo: string[];
  decision: string;
  source: { sha: string; schema: string; fixture: string };
  inputs: Record<string, { required?: unknown; labeled?: unknown }>;
  allowedClaimIds: string[];
  forbiddenClaimIds: string[];
  dates: DateRule[];
};

type LaunchContract = {
  schema?: string;
  sourceIssue?: string;
  promise?: { optionalInputs?: string[]; requiredInputs?: string[] };
  requiredPaths?: { id?: string }[];
};

// Package-local decisions are Turbo inputs, so editing the table invalidates
// the existing shared-lib CI test cache without a workflow change.
const table: ClaimTable = JSON.parse(
  readFileSync(new URL('../decisions/safe-plan-claim-limits.json', import.meta.url), 'utf8'),
);
const contract: LaunchContract = JSON.parse(
  readFileSync(
    new URL('../../../scripts/fixtures/lyb-launch-contract.json', import.meta.url),
    'utf8',
  ),
);

const forbiddenClaimIds = [
  'appearance_goal_assigned',
  'body_score_clinical_accuracy',
  'body_score_efficacy',
  'body_score_safety',
  'coach_dexa_clinical_accuracy',
  'coach_dexa_efficacy',
  'coach_efficacy',
  'coach_glp1_direction',
  'coach_glp1_efficacy',
  'coach_glp1_safety',
  'coach_result_guarantee',
  'coach_safety',
  'date_guarantees_result',
  'dexa_clinical_accuracy',
  'dexa_efficacy',
  'dexa_required',
  'dexa_safety',
  'expired_date_silent_extension',
  'glp1_efficacy',
  'glp1_medication_direction',
  'glp1_required',
  'glp1_safety',
  'impossible_date_feasible',
  'invented_body_score',
  'invented_trend',
  'maintenance_efficacy',
  'maintenance_safety',
  'observed_uplift',
  'plan_efficacy',
  'plan_safety',
  'safe_plan',
  'unsafe_date_acceptable',
];

const dateRules = [
  {
    fixtureInput: 'unsafe',
    recoveryState: 'defer_or_revise_constraint',
    contractPath: 'launch.safety',
    basis: 'Impossible dates and unsafe targets defer or suggest revising the constraint.',
  },
  {
    fixtureInput: 'impossible',
    recoveryState: 'defer_or_revise_constraint',
    contractPath: 'launch.safety',
    basis: 'Impossible dates and unsafe targets defer or suggest revising the constraint.',
  },
  {
    fixtureInput: 'expired',
    recoveryState: 'offer_review_maintenance_or_new_date',
    contractPath: 'launch.return',
    basis:
      'A completed/expired date offers review, maintenance, or a new date without silently extending it.',
  },
  {
    fixtureInput: 'maintenance',
    recoveryState: 'keep_maintenance_interval',
    contractPath: 'launch.deadline',
    basis:
      'Saves an outcome, date, and constraints such as travel, availability, or a maintenance interval.',
  },
];

const optionalInputs = ['dexa', 'glp1Disclosure'] as const;

function claimReferences(value: ClaimTable): string[] {
  return [
    ...value.allowedClaimIds,
    ...value.dates.flatMap((date) => [...date.exposedClaimIds, date.recoveryState]),
  ];
}

function validateTable(value: ClaimTable) {
  assert.equal(value.id, 'LYB-287');
  assert.equal(value.parent, 'LYB-183');
  assert.equal(value.status, 'accepted');
  assert.equal(value.approvalBasis, 'ships-if-unanswered');
  assert.deepEqual(value.appliesTo, ['product', 'coach']);
  assert.match(value.decision, /no efficacy or safety claim/);
  assert.match(value.decision, /recovery next action/);
  assert.deepEqual(value.forbiddenClaimIds, forbiddenClaimIds);
  assert.equal(new Set(value.forbiddenClaimIds).size, value.forbiddenClaimIds.length);

  const forbidden = new Set(value.forbiddenClaimIds);
  for (const id of claimReferences(value)) {
    assert(!forbidden.has(id), `forbidden claim id: ${id}`);
  }
  assert.deepEqual(value.allowedClaimIds, [], 'allowed claims must be empty');
  assert.deepEqual(
    value.dates.map(({ fixtureInput, recoveryState, contractPath, basis }) => ({
      fixtureInput,
      recoveryState,
      contractPath,
      basis,
    })),
    dateRules,
  );
  for (const date of value.dates) {
    assert.deepEqual(date.exposedClaimIds, [], `${date.fixtureInput} exposes a claim`);
  }
  for (const key of optionalInputs) {
    assert.equal(value.inputs[key]?.required, false, `${key} must stay optional`);
    assert.equal(value.inputs[key]?.labeled, false, `${key} must stay unlabeled`);
  }
}

function validateContract(value: LaunchContract) {
  assert.equal(value.schema, 'lyb-launch-contract/v1');
  assert.equal(value.sourceIssue, 'JOV-6013');
  const optional = new Set(value.promise?.optionalInputs ?? []);
  const required = new Set(value.promise?.requiredInputs ?? []);
  for (const key of optionalInputs) {
    assert(optional.has(key), `${key} must stay optional in the launch contract`);
    assert(!required.has(key), `${key} must stay optional in the launch contract`);
  }
  const paths = new Set((value.requiredPaths ?? []).map((path) => path.id));
  for (const date of dateRules) assert(paths.has(date.contractPath), date.contractPath);
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function recoveryState(value: ClaimTable, fixtureInput: string): string {
  validateTable(value);
  const matches = value.dates.filter((date) => date.fixtureInput === fixtureInput);
  assert.equal(matches.length, 1, `fixture input: ${fixtureInput}`);
  return matches[0].recoveryState;
}

describe('safe-plan claim limits (LYB-287)', () => {
  it('loads the rule table and keeps GLP-1 and DEXA optional in the contract', () => {
    validateTable(table);
    validateContract(contract);
    expect(table.source).toMatchObject({
      sha: '197a96ff21c53cb4ccd8f6c1e3d733058b8c1cf7',
      schema: 'lyb-launch-contract/v1',
      fixture: 'scripts/fixtures/lyb-launch-contract.json',
    });
  });

  it.each(dateRules)(
    'maps $fixtureInput to $recoveryState',
    ({ fixtureInput, recoveryState: state }) => {
      expect(recoveryState(table, fixtureInput)).toBe(state);
    },
  );

  it.each(optionalInputs)('fails when %s is marked required', (key) => {
    const candidate = clone(table);
    candidate.inputs[key].required = true;
    expect(() => validateTable(candidate)).toThrow(`${key} must stay optional`);
  });

  it.each(optionalInputs)('fails when the launch contract marks %s required', (key) => {
    const candidate = clone(contract);
    candidate.promise = {
      optionalInputs: (candidate.promise?.optionalInputs ?? []).filter((input) => input !== key),
      requiredInputs: [...(candidate.promise?.requiredInputs ?? []), key],
    };
    expect(() => validateContract(candidate)).toThrow(`${key} must stay optional`);
  });

  it.each(['plan_efficacy', 'glp1_required', 'dexa_required', 'safe_plan'] as const)(
    'fails when the table references forbidden claim id %s',
    (claimId) => {
      const allowed = clone(table);
      allowed.allowedClaimIds = [claimId];
      expect(() => validateTable(allowed)).toThrow(`forbidden claim id: ${claimId}`);

      const exposed = clone(table);
      exposed.dates[0].exposedClaimIds = [claimId];
      expect(() => validateTable(exposed)).toThrow(`forbidden claim id: ${claimId}`);

      const state = clone(table);
      state.dates[0].recoveryState = claimId;
      expect(() => recoveryState(state, 'unsafe')).toThrow(`forbidden claim id: ${claimId}`);
    },
  );
});
