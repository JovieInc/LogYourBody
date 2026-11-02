import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Decisions and fixtures live in this package so changes invalidate Turbo's
// existing CI test cache without changing workflows or task configuration.
const policyPath = 'program-revision-rationale-wording.json';
const decisionsDirectory = new URL('../decisions/', import.meta.url);
const records = readdirSync(decisionsDirectory, { recursive: true })
  .filter((path) => path.endsWith('.json'))
  .map((path) => ({
    path,
    value: JSON.parse(readFileSync(new URL(path, decisionsDirectory), 'utf8')),
  }));
const fixture = JSON.parse(
  readFileSync(new URL('../fixtures/program-revision-rationale.json', import.meta.url), 'utf8'),
);
const defaultRule = {
  source: 'user_utterance',
  transformation: 'verbatim',
  generatedCoachSentence: false,
  templateName: false,
  trademark: false,
};

function validatePolicy(candidates: typeof records) {
  const policies = candidates.filter(
    ({ path, value }) =>
      path === policyPath ||
      value?.id === 'LYB-277' ||
      value?.kind === 'program_revision_rationale_wording',
  );
  assert.equal(policies.length, 1, 'Exactly one revision rationale wording policy is required');
  const policy = policies[0];
  assert.equal(policy.path, policyPath);
  assert.equal(policy.value.id, 'LYB-277');
  assert.equal(policy.value.parent, 'LYB-107');
  assert.equal(policy.value.kind, 'program_revision_rationale_wording');
  assert.equal(policy.value.status, 'accepted');
  assert.deepEqual(policy.value.default, defaultRule);
  return policy.value;
}

function validateRevision(policy: ReturnType<typeof validatePolicy>, revision: unknown) {
  assert.deepEqual(policy.default, defaultRule);
  assert(typeof fixture.userUtterance === 'string' && fixture.userUtterance.trim());
  assert.deepEqual(revision, { rationale: fixture.userUtterance });
}

describe('program revision rationale wording policy (LYB-277)', () => {
  it('reads exactly one accepted policy and preserves the supplied user utterance verbatim', () => {
    validateRevision(validatePolicy(records), fixture.revision);
  });

  it('rejects a missing or duplicated policy, including a renamed copy', () => {
    const policy = { path: policyPath, value: validatePolicy(records) };
    expect(() => validatePolicy([])).toThrow(/Exactly one/);
    expect(() => validatePolicy([policy, policy])).toThrow(/Exactly one/);
    expect(() => validatePolicy([policy, { ...policy, path: 'copy.json' }])).toThrow(/Exactly one/);
    expect(() => validatePolicy([{ ...policy, path: 'copy.json' }])).toThrow();
  });

  it('rejects alternate sources, transformations and generated wording permissions', () => {
    const policy = validatePolicy(records);
    for (const key of Object.keys(defaultRule)) {
      const candidate = { ...policy, default: { ...policy.default, [key]: true } };
      expect(() => validatePolicy([{ path: policyPath, value: candidate }])).toThrow();
    }
    expect(() =>
      validatePolicy([{ path: policyPath, value: { ...policy, default: {} } }]),
    ).toThrow();
  });

  it('rejects any rationale other than the supplied utterance without introducing alternative copy', () => {
    const policy = validatePolicy(records);
    const utterance: string = fixture.userUtterance;
    for (const rationale of [
      undefined,
      null,
      42,
      '',
      utterance.trim(),
      utterance.toUpperCase(),
      utterance.replace(/\n/g, ' '),
      `${utterance}.`,
      `[${utterance}]`,
    ]) {
      expect(() => validateRevision(policy, { rationale })).toThrow();
    }
    for (const field of ['generatedCoachSentence', 'templateName', 'trademark']) {
      expect(() => validateRevision(policy, { ...fixture.revision, [field]: utterance })).toThrow();
    }
  });
});
