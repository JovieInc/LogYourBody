import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync, realpathSync } from 'node:fs';
import { posix, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { planCorrectionIssues } from './correction-recurrence.mjs';

export const ROOT = fileURLToPath(new URL('../../..', import.meta.url));
export const LEDGER_PATH = 'packages/shared-lib/corrections.json';
export const LEVELS = ['codebase', 'static', 'prose', 'human', 'unclassified'];

export function readSource(path, { root = ROOT, ref } = {}) {
  assert.equal(typeof path, 'string', 'invalid guard path');
  assert.ok(
    path && posix.normalize(path) === path && !/^(?:\/|\.\.\/)|[\\:\x00-\x1f]/u.test(path),
    'nonlocal guard path',
  );
  if (ref) {
    assert.match(ref, /^(?:[a-f0-9]{40}|origin\/main)$/u, 'invalid baseline ref');
    return execFileSync('git', ['show', `${ref}:${path}`], {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  }
  const absolute = resolve(root, path);
  assert.equal(realpathSync(absolute), absolute, 'guard path traverses a symlink');
  return readFileSync(absolute, 'utf8');
}

function fraction(mechanized, total) {
  return { mechanized, total, percent: total ? (100 * mechanized) / total : null };
}

export function coverageReport(receipts, readGuard = readSource) {
  // Share the existing receipt contract and recurrence fingerprint identity.
  planCorrectionIssues(receipts);
  const rules = new Map();
  for (const receipt of receipts) {
    const fingerprint = receipt.fingerprint.trim().toLowerCase().replace(/\s+/g, '-');
    const level = receipt.level ?? 'unclassified';
    assert.ok(LEVELS.includes(level), 'invalid correction level');
    const guard = receipt.guard ?? null;
    if (guard) {
      assert.ok(
        ['codebase', 'static'].includes(level),
        'only codebase/static guards are mechanized',
      );
      assert.ok(
        typeof guard.anchor === 'string' && guard.anchor.trim().length >= 16,
        'specific guard anchor required',
      );
    }
    const annotation = JSON.stringify({
      level,
      guard: guard && { path: guard.path, anchor: guard.anchor },
      proseOnlyReason: receipt.proseOnlyReason ?? null,
    });
    const previous = rules.get(fingerprint);
    assert.ok(
      !previous || previous.annotation === annotation,
      `conflicting coverage annotations: ${fingerprint}`,
    );
    let mechanized = false;
    if (guard) {
      // A proposal or missing source anchor earns no mechanization credit.
      try {
        mechanized = readGuard(guard.path).includes(guard.anchor);
      } catch {
        mechanized = false;
      }
    }
    rules.set(fingerprint, { fingerprint, level, mechanized, annotation });
  }
  const entries = [...rules.values()].sort((a, b) => a.fingerprint.localeCompare(b.fingerprint));
  return {
    schema: 'lyb.correction-coverage/v1',
    repository: 'JovieInc/LogYourBody',
    evidence: 'reviewed source anchors; not proof of guard execution',
    ...fraction(entries.filter((rule) => rule.mechanized).length, entries.length),
    levels: Object.fromEntries(
      LEVELS.map((level) => {
        const members = entries.filter((rule) => rule.level === level);
        return [level, fraction(members.filter((rule) => rule.mechanized).length, members.length)];
      }),
    ),
    rules: entries.map(({ annotation: _annotation, ...rule }) => rule),
  };
}

export function guardCoverageReport(receipts, readGuard = readSource) {
  const report = coverageReport(receipts, readGuard);
  for (const receipt of receipts) {
    const fingerprint = receipt.fingerprint.trim().toLowerCase().replace(/\s+/g, '-');
    const rule = report.rules.find((entry) => entry.fingerprint === fingerprint);
    if (receipt.guard) {
      assert.ok(rule.mechanized, `guard coverage: missing guard anchor for ${fingerprint}`);
      assert.ok(
        receipt.proseOnlyReason == null,
        `guard coverage: guarded lesson cannot be prose-only: ${fingerprint}`,
      );
    } else {
      assert.ok(
        ['prose', 'human'].includes(rule.level) &&
          typeof receipt.proseOnlyReason === 'string' &&
          receipt.proseOnlyReason.trim(),
        `guard coverage: guard or prose-only reason required for ${fingerprint}`,
      );
    }
  }
  return report;
}

export function assertNoRegression(current, baseline) {
  for (const [name, before, after] of [
    ['overall', baseline, current],
    ...LEVELS.map((level) => [level, baseline.levels[level], current.levels[level]]),
  ]) {
    // Compare unrounded ratios; an empty baseline sets no percentage floor.
    assert.ok(
      !before.total ||
        !after.total ||
        after.mechanized * before.total >= before.mechanized * after.total,
      `correction coverage regression: ${name}`,
    );
  }
  for (const before of baseline.rules) {
    const after = current.rules.find((rule) => rule.fingerprint === before.fingerprint);
    assert.ok(after, `correction coverage regression: removed rule ${before.fingerprint}`);
    if (before.mechanized)
      assert.ok(
        after.mechanized && LEVELS.indexOf(after.level) <= LEVELS.indexOf(before.level),
        `correction coverage regression: lost or downgraded guard for ${before.fingerprint}`,
      );
  }
}

export function renderCoverage(report) {
  const row = (name, value) =>
    `| ${name} | ${value.mechanized}/${value.total} | ${value.percent === null ? 'N/A (no rules)' : `${value.percent.toFixed(2)}%`} |`;
  return [
    '## LYB owner loop — correction coverage',
    '',
    '| Level | Mechanized / rules | Coverage |',
    '| --- | --- | --- |',
    row('Overall', report),
    ...LEVELS.map((level) => row(level, report.levels[level])),
    '',
    'One rule per normalized correction fingerprint; repeated receipts count once.',
    'Only codebase/static rules with a retained source anchor count as mechanized.',
    'Source linkage is not proof of guard execution. An empty ledger is N/A.',
    '',
  ].join('\n');
}

export function runCoverage(argv, { root = ROOT, env = process.env } = {}) {
  assert.ok(
    argv.length === 0 || (argv.length === 2 && argv[0] === '--base-ref'),
    'usage: correction-coverage.mjs [--base-ref <sha|origin/main>]',
  );
  const current = guardCoverageReport(JSON.parse(readSource(LEDGER_PATH, { root })), (path) =>
    readSource(path, { root }),
  );
  if (argv.length) {
    const ref = argv[1];
    const baseline = coverageReport(JSON.parse(readSource(LEDGER_PATH, { root, ref })), (path) =>
      readSource(path, { root, ref }),
    );
    assertNoRegression(current, baseline);
  }
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, renderCoverage(current));
  return current;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    console.log(JSON.stringify(runCoverage(process.argv.slice(2)), null, 2));
  } catch (error) {
    console.error(`Correction coverage failed: ${error.message}`);
    process.exitCode = 1;
  }
}
