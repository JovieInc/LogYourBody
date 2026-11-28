import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { draftTestFlightNotes } from './draft-testflight-notes.mjs';

const entrypoint = fileURLToPath(new URL('./draft-testflight-notes.mjs', import.meta.url));

function fixture(t) {
  const cwd = mkdtempSync(join(tmpdir(), 'testflight-note-fixture-'));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  const git = (...args) => execFileSync(
    'git',
    ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgSign=false', '-c', 'core.hooksPath=/dev/null', ...args],
    { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  ).trim();
  const commit = (message) => {
    git('commit', '--allow-empty', '-m', message);
    return git('rev-parse', 'HEAD');
  };
  git('init', '-b', 'trunk');
  const lastDistributed = commit('Old example release');
  const first = commit('Internal draft title must not leak');
  git('switch', '-c', 'side', lastDistributed);
  const side = commit('Side example title must not leak');
  git('switch', 'trunk');
  git('merge', '--no-ff', '-m', 'Build tooling title must not leak', 'side');
  const merged = git('rev-parse', 'HEAD');
  const candidate = commit('Candidate ticket title must not leak');
  return { cwd, first, merged, side, input: { lastDistributed, candidate, entries: [] } };
}

const approval = (sha, note, overrides = {}) => ({
  sha, note, audience: 'customer', approval: 'approved', category: 'fix', ...overrides,
});
const run = (cwd, input) => spawnSync(process.execPath, [entrypoint], {
  cwd, input: JSON.stringify(input), encoding: 'utf8',
});

test('CLI prints only eligible approved metadata, in first-parent release order without repeats', (t) => {
  const { cwd, first, merged, input } = fixture(t);
  input.entries = [
    approval(input.candidate, 'Restore the selected view when reopened.'),
    approval(merged, 'Restore the selected view when reopened.'),
    approval(merged, 'Hide an example dependency title.', { category: 'dependency' }),
    approval(input.candidate, 'Hide an example security ticket.', { category: 'security' }),
    approval(first, 'Hide internal notes.', { audience: 'internal' }),
    approval(merged, 'Hide unapproved copy.', { approval: 'pending' }),
    approval(first, 'Keep the selected unit while editing.'),
  ];
  const result = run(cwd, input);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.equal(result.stdout, '- Keep the selected unit while editing.\n- Restore the selected view when reopened.\n');
});

test('rejects absent, abbreviated, unknown, or off-line distribution boundaries', (t) => {
  const { cwd, side, input } = fixture(t);
  for (const lastDistributed of [undefined, input.lastDistributed.slice(0, 8), 'f'.repeat(40), side]) {
    const result = run(cwd, { ...input, lastDistributed });
    assert.equal(result.status, 2, result.stderr);
    assert.equal(result.stdout, '');
  }
});

test('rejects approved notes outside the open/closed range, including second-parent commits', (t) => {
  const { cwd, side, input } = fixture(t);
  for (const sha of [input.lastDistributed, side, undefined]) {
    const result = run(cwd, { ...input, entries: [approval(sha, 'Example change.')] });
    assert.equal(result.status, 2);
    assert.equal(result.stdout, '');
  }
});

test('distinguishes a valid empty range from invalid input without substituting raw titles', (t) => {
  const { cwd, input } = fixture(t);
  for (const fields of [{}, { candidate: input.lastDistributed }]) {
    const result = run(cwd, { ...input, ...fields });
    assert.equal(result.status, 3, result.stderr);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /No approved customer notes/);
  }
});

test('rejects multiline, tracker-link, ticket, and oversized note copy with no partial draft', (t) => {
  const { cwd, first, input } = fixture(t);
  for (const note of ['Test\nsecond line', 'See https://example.invalid/ticket', 'Fix DEMO-123', 'x'.repeat(1000)]) {
    input.entries = [approval(first, 'Valid public copy.'), approval(input.candidate, note)];
    assert.throws(() => draftTestFlightNotes(input, { cwd }), /single-line|review budget/);
    const result = run(cwd, input);
    assert.equal(result.status, 2);
    assert.equal(result.stdout, '');
  }
});
