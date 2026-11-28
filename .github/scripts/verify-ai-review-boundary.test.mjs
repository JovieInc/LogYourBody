#!/usr/bin/env node

// Tests for the AI review boundary guard (.github/scripts/verify-ai-review-boundary.mjs).
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { scanFile } from './verify-ai-review-boundary.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const scanner = resolve(here, 'verify-ai-review-boundary.mjs');
const repoRoot = resolve(here, '..', '..');

const CLEAN_ADVISORY = `# Advisory AI review - comments only, never blocks a merge.
name: Advisory AI Review
on:
  pull_request:
jobs:
  review:
    steps:
      - run: node .github/scripts/advisory-ai-review.mjs
`;

const WARDEN_BLOCKING = `name: Warden
on: [pull_request]
permissions:
  pull-requests: write
jobs:
  review:
    steps:
      - run: gh pr review $PR --request-changes --body "$VERDICT"
      - run: warden --fail-on findings "$PR"
`;

const SEER_FAILCHECK = `name: Sentry Seer code review
on: [pull_request]
jobs:
  review:
    steps:
      - run: exit 1 # failCheck on findings
`;

let base;

function rootWith(name, content) {
  const root = mkdtempSync(join(tmpdir(), 'ai-review-boundary-'));
  mkdirSync(join(root, '.github', 'workflows'), { recursive: true });
  writeFileSync(join(root, '.github', 'workflows', name), content);
  return root;
}

function runScanner(root) {
  return execFileSync('node', [scanner, '--root', root], { encoding: 'utf8' });
}

before(() => {
  base = mkdtempSync(join(tmpdir(), 'ai-review-boundary-suite-'));
});

after(() => {
  rmSync(base, { recursive: true, force: true });
});

describe('verify-ai-review-boundary', () => {
  it('passes an advisory, comment-only AI reviewer', () => {
    assert.match(runScanner(rootWith('advisory.yml', CLEAN_ADVISORY)), /ok/);
  });

  it('fails a Warden-style review that requests changes', () => {
    assert.throws(
      () => runScanner(rootWith('warden.yml', WARDEN_BLOCKING)),
      (error) => {
        assert.match(error.stderr, /warden\.yml/);
        assert.match(error.stderr, /request-changes/);
        return true;
      }
    );
  });

  it('fails a Seer-style review that fails a check', () => {
    assert.throws(
      () => runScanner(rootWith('seer.yml', SEER_FAILCHECK)),
      (error) => {
        assert.match(error.stderr, /seer\.yml/);
        assert.match(error.stderr, /failCheck/);
        return true;
      }
    );
  });

  it('ignores non-AI files that merely mention the signals', () => {
    const root = rootWith(
      'pr-labels.yml',
      '# a maintainer may request changes; see CONTRIBUTING\n'
    );
    assert.match(runScanner(root), /ok/);
  });

  it('does not flag the guards that enforce it', () => {
    assert.equal(
      scanFile('.github/scripts/verify-ai-review-boundary.test.mjs', 'failCheck'),
      null
    );
    assert.equal(
      scanFile('.github/scripts/verify-workflow-concurrency.mjs', 'failCheck'),
      null
    );
  });

  it('leaves the checked-in .github tree clean', () => {
    assert.match(runScanner(repoRoot), /ok/);
  });

  it('stays wired into the workflow concurrency verifier', () => {
    const verifier = readFileSync(
      resolve(repoRoot, '.github/scripts/verify-workflow-concurrency.mjs'),
      'utf8'
    );
    assert.match(verifier, /verify-ai-review-boundary\.mjs/);
  });
});
