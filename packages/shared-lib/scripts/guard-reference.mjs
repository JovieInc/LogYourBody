// LYB-254: a claimed guard path must exist. Entries with no guard warn on a shrink-only baseline.
import assert from 'node:assert/strict';
import { appendFileSync, lstatSync, realpathSync } from 'node:fs';
import { posix, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { LEDGER_PATH, readSource, ROOT } from './correction-coverage.mjs';
import { planCorrectionIssues } from './correction-recurrence.mjs';

export const BASELINE_PATH = 'packages/shared-lib/guard-reference-baseline.json';
export const SCHEMA = 'lyb.guard-reference/v1';

const ENTRY_ID = /^[a-z0-9][a-z0-9._:-]{0,159}$/u;

function entryId(fingerprint) {
  const id =
    typeof fingerprint === 'string' ? fingerprint.trim().toLowerCase().replace(/\s+/g, '-') : '';
  assert.match(id, ENTRY_ID, 'invalid guard reference entry id');
  return id;
}

function referenceStatus(path, root) {
  if (
    typeof path !== 'string' ||
    !path ||
    posix.normalize(path) !== path ||
    /^(?:\/|\.\.\/)|[\\:\x00-\x1f]/u.test(path)
  ) {
    return 'invalid';
  }
  const absolute = resolve(root, path);
  let stat;
  try {
    stat = lstatSync(absolute);
  } catch (error) {
    if (error.code === 'ENOENT' || error.code === 'ENOTDIR') return 'missing';
    throw error;
  }
  if (!stat.isFile() || stat.isSymbolicLink() || realpathSync(absolute) !== absolute) {
    return 'missing';
  }
  return 'ok';
}

export function ledgerGuardReferences(receipts) {
  planCorrectionIssues(receipts);
  const rules = new Map();
  for (const receipt of receipts) {
    const id = entryId(receipt.fingerprint);
    const claimed = receipt.guard != null;
    const path = claimed && typeof receipt.guard.path === 'string' ? receipt.guard.path : null;
    const reference = { id, claimed, path: claimed ? path : null };
    const previous = rules.get(id);
    assert.ok(
      !previous || (previous.claimed === reference.claimed && previous.path === reference.path),
      `conflicting guard reference: ${id}`,
    );
    rules.set(id, reference);
  }
  return [...rules.values()].sort((a, b) => a.id.localeCompare(b.id));
}

function missingFromRevision(error) {
  const detail = `${error.stderr ?? ''}\n${error.message ?? ''}`;
  return (
    /fatal: path .+ does not exist in /u.test(detail) ||
    /fatal: path .+ exists on disk, but not in /u.test(detail)
  );
}

function parseBaseline(text) {
  const value = JSON.parse(text);
  assert.ok(
    value &&
      typeof value === 'object' &&
      !Array.isArray(value) &&
      Object.keys(value).sort().join(',') === 'schema,unguarded',
    'invalid guard reference baseline schema',
  );
  assert.equal(value.schema, SCHEMA, 'invalid guard reference baseline schema');
  assert.ok(Array.isArray(value.unguarded), 'guard reference baseline unguarded must be an array');
  const ids = value.unguarded.map((id) => {
    assert.equal(typeof id, 'string', 'invalid guard reference baseline id');
    assert.match(id, ENTRY_ID, `invalid guard reference baseline id: ${id}`);
    return id;
  });
  assert.deepEqual(
    ids,
    [...ids].sort((a, b) => a.localeCompare(b)),
    'guard reference baseline must be sorted',
  );
  assert.equal(new Set(ids).size, ids.length, 'duplicate guard reference baseline id');
  return ids;
}

function readBaseline({ root, ref }) {
  try {
    return parseBaseline(readSource(BASELINE_PATH, { root, ref }));
  } catch (error) {
    if (ref && missingFromRevision(error)) return [];
    throw error;
  }
}

function assertSubset(current, allowed, reason) {
  for (const id of current) assert.ok(allowed.includes(id), `${reason}: ${id}`);
}

export function runGuardReferences(
  argv,
  { root = ROOT, env = process.env, warn = console.warn } = {},
) {
  assert.ok(
    argv.length === 0 || (argv.length === 2 && argv[0] === '--base-ref'),
    'usage: guard-reference.mjs [--base-ref <sha|origin/main>]',
  );
  const rules = ledgerGuardReferences(JSON.parse(readSource(LEDGER_PATH, { root })));
  const problems = [];
  for (const rule of rules) {
    if (!rule.claimed) continue;
    const named = typeof rule.path === 'string' && rule.path.trim() ? rule.path : '(no path)';
    const status = named === '(no path)' ? 'missing' : referenceStatus(rule.path, root);
    if (status === 'ok') continue;
    const reason = status === 'invalid' ? 'nonlocal guard path' : 'guard reference missing';
    problems.push(`${reason}: ${rule.id} ${named}`);
  }
  if (problems.length) throw new Error(problems.join('\n'));
  const unguarded = rules.filter((rule) => !rule.claimed).map((rule) => rule.id);
  const baseline = readBaseline({ root });
  if (argv.length) {
    assertSubset(baseline, readBaseline({ root, ref: argv[1] }), 'guard reference baseline growth');
  }
  assertSubset(unguarded, baseline, 'unguarded ledger entry has no baseline allowance');
  assertSubset(baseline, unguarded, 'stale guard reference baseline');
  for (const id of unguarded) {
    warn(`::warning::LYB guard reference ${id}: no guard reference; baseline can only shrink.`);
  }
  if (env.GITHUB_STEP_SUMMARY) {
    appendFileSync(
      env.GITHUB_STEP_SUMMARY,
      [
        '## LYB guard references',
        '',
        `Claimed guard paths checked: ${rules.length - unguarded.length}.`,
        unguarded.length
          ? `Unguarded entries (baseline can only shrink): ${unguarded.join(', ')}.`
          : 'Unguarded entries (baseline can only shrink): none.',
        '',
      ].join('\n'),
    );
  }
  return { schema: SCHEMA, checked: rules.length - unguarded.length, unguarded };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    console.log(JSON.stringify(runGuardReferences(process.argv.slice(2)), null, 2));
  } catch (error) {
    console.error(`Guard reference check failed: ${error.message}`);
    process.exitCode = 1;
  }
}
