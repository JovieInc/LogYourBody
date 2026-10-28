import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { appendFileSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, posix, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { planCorrectionIssues } from './correction-recurrence.mjs';
import { classifyCorrection, LEVELS } from './correction-classification.mjs';

export const ROOT = fileURLToPath(new URL('../../..', import.meta.url));
export const LEDGER_PATH = 'packages/shared-lib/corrections.json';
export { LEVELS } from './correction-classification.mjs';

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

export function coverageReport(
  receipts,
  readGuard = readSource,
  { requireClassification = false } = {},
) {
  // Share the existing receipt contract and recurrence fingerprint identity.
  planCorrectionIssues(receipts);
  const rules = new Map();
  for (const receipt of receipts) {
    const fingerprint = receipt.fingerprint.trim().toLowerCase().replace(/\s+/g, '-');
    const classification = classifyCorrection(receipt, requireClassification);
    const { level } = classification;
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
      ...classification,
      guard: guard && { path: guard.path, anchor: guard.anchor, ratchet: guard.ratchet },
      proseOnlyReason: receipt.proseOnlyReason ?? null,
    });
    const previous = rules.get(fingerprint);
    assert.ok(
      !previous || previous.annotation === annotation,
      // Keep every conflicting source visible; divergent annotations still require review.
      `conflicting coverage annotations: ${fingerprint}; existing sources: ${previous ? [...previous.receipts.keys()].join(', ') : '(none)'}; incoming source: ${receipt.source}; existing guard: ${previous?.guard?.path ?? '(none)'}; incoming guard: ${guard?.path ?? '(none)'}`,
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
    const receipts = previous?.receipts ?? new Map();
    const source = new URL(receipt.source).href;
    receipts.set(source, {
      source,
      correction: receipt.correction.trim(),
      mechanization: receipt.mechanization.trim(),
    });
    rules.set(fingerprint, {
      fingerprint,
      ...classification,
      mechanized,
      annotation,
      guard,
      proseOnlyReason: receipt.proseOnlyReason ?? null,
      receipts,
    });
  }
  const entries = [...rules.values()]
    .sort((a, b) => a.fingerprint.localeCompare(b.fingerprint))
    .map(({ annotation: _annotation, receipts, ...rule }) => ({
      ...rule,
      receipts: [...receipts.values()].sort((a, b) => a.source.localeCompare(b.source)),
      recurrence: { receiptCount: receipts.size, repeatCount: receipts.size - 1 },
    }));
  const mechanized = entries.filter((rule) => rule.mechanized).length;
  return {
    schema: 'lyb.correction-coverage/v1',
    repository: 'JovieInc/LogYourBody',
    evidence: 'reviewed source anchors; not proof of guard execution',
    ...fraction(mechanized, entries.length),
    mechanizedShare: entries.length ? mechanized / entries.length : 0,
    levels: Object.fromEntries(
      LEVELS.map((level) => {
        const members = entries.filter((rule) => rule.level === level);
        return [level, fraction(members.filter((rule) => rule.mechanized).length, members.length)];
      }),
    ),
    rules: entries,
  };
}

export function guardCoverageReport(receipts, readGuard = readSource, options) {
  const report = coverageReport(receipts, readGuard, options);
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
    for (const receipt of before.receipts) {
      assert.ok(
        after.receipts.some(({ source }) => source === receipt.source),
        `correction ledger regression: removed receipt for ${before.fingerprint}`,
      );
    }
    if (before.mechanized)
      assert.ok(
        after.mechanized && LEVELS.indexOf(after.level) <= LEVELS.indexOf(before.level),
        `correction coverage regression: lost or downgraded guard for ${before.fingerprint}`,
      );
  }
}

export function mergeCorrectionLedgers(base, ours, theirs, readGuard = readSource) {
  const reports = [base, ours, theirs].map((rows) => coverageReport(rows, readGuard));
  const [original, left, right] = [base, ours, theirs].map((rows) => {
    const indexed = new Map();
    for (const row of rows) {
      const key = JSON.stringify([
        row.fingerprint.trim().toLowerCase().replace(/\s+/g, '-'),
        new URL(row.source).href,
      ]);
      assert.ok(!indexed.has(key), `ledger merge: duplicate receipt ${key}`);
      indexed.set(key, row);
    }
    return indexed;
  });
  for (const key of original.keys()) {
    assert.ok(left.has(key) && right.has(key), `ledger merge: removed receipt ${key}`);
  }
  const merged = [...new Set([...left.keys(), ...right.keys()])].map((key) => {
    const a = left.get(key);
    const b = right.get(key);
    if (!a) return b;
    if (!b || isDeepStrictEqual(a, b)) return a;
    // Independent additions merge; concurrent receipt edits require explicit resolution.
    if (isDeepStrictEqual(a, original.get(key))) return b;
    assert.ok(
      isDeepStrictEqual(b, original.get(key)),
      `ledger merge: concurrent receipt edits ${key}`,
    );
    return a;
  });
  const report = guardCoverageReport(merged, readGuard, { requireClassification: true });
  for (const parent of reports) assertNoRegression(report, parent);
  return merged;
}

export function renderCoverage(report) {
  const cell = (value) =>
    value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('|', '&#124;')
      .replace(/\s+/g, ' ');
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
    '| Fingerprint | Route | Assessment in priority order | Guard or prose-only reason | Recurrence |',
    '| --- | --- | --- | --- | --- |',
    ...report.rules.map(
      (rule) =>
        `| ${rule.fingerprint} | ${rule.level} | ${cell(
          rule.considered.length
            ? rule.considered
                .map(
                  ({ level, feasible, rationale }) =>
                    `${level} (${feasible ? 'feasible' : 'not feasible'}): ${rationale}`,
                )
                .join('; ')
            : 'Historical annotation; no feasibility assessment.',
        )} | ${cell(rule.guard ? `${rule.guard.path}: ${rule.guard.anchor}` : (rule.proseOnlyReason ?? 'No retained guard.'))} | ${rule.recurrence.receiptCount} receipts; ${rule.recurrence.repeatCount} repeats |`,
    ),
    '',
    '| Fingerprint | Lesson | Source |',
    '| --- | --- | --- |',
    ...report.rules.flatMap((rule) =>
      rule.receipts.map(
        (receipt) =>
          `| ${rule.fingerprint} | ${cell(receipt.correction)} | ${cell(receipt.source)} |`,
      ),
    ),
    '',
  ].join('\n');
}

function gitText(root, args) {
  return execFileSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function ledgerAtRevision(root, revision) {
  return JSON.parse(gitText(root, ['show', `${revision}:${LEDGER_PATH}`]));
}

function readGuardFromRevisions(root, revisions) {
  return (path) => {
    const chunks = [];
    for (const revision of revisions) {
      try {
        chunks.push(gitText(root, ['show', `${revision}:${path}`]));
      } catch {
        // A one-sided guard does not exist in every ancestor revision.
      }
    }
    return chunks.join('\n');
  };
}

// A recursive merge can leave conflict markers in the ancestor stage. Rebuild that
// stage from the two real merge bases so the outer union still has a JSON ancestor.
export function readGitMergeLedgers(root) {
  const ours = JSON.parse(gitText(root, ['show', `:2:${LEDGER_PATH}`]));
  const theirs = JSON.parse(gitText(root, ['show', `:3:${LEDGER_PATH}`]));
  const baseText = gitText(root, ['show', `:1:${LEDGER_PATH}`]);
  try {
    return [JSON.parse(baseText), ours, theirs];
  } catch (error) {
    if (!/^<{2,} /m.test(baseText)) throw error;
    const bases = gitText(root, ['merge-base', '--all', 'HEAD', 'MERGE_HEAD'])
      .trim()
      .split('\n')
      .filter(Boolean);
    assert.equal(
      bases.length,
      2,
      'ledger merge: conflicted ancestor needs two recursive merge bases',
    );
    const parents = gitText(root, ['merge-base', '--all', bases[0], bases[1]])
      .trim()
      .split('\n')
      .filter(Boolean);
    assert.equal(
      parents.length,
      1,
      'ledger merge: recursive merge bases need one shared ancestor',
    );
    const revisions = [parents[0], bases[0], bases[1]];
    const base = mergeCorrectionLedgers(
      ledgerAtRevision(root, parents[0]),
      ledgerAtRevision(root, bases[0]),
      ledgerAtRevision(root, bases[1]),
      readGuardFromRevisions(root, revisions),
    );
    return [base, ours, theirs];
  }
}

export function assertLedgerMergeReady(root) {
  const otherConflicts = execFileSync('git', ['diff', '--name-only', '--diff-filter=U', '-z'], {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
    .split('\0')
    .filter((path) => path && path !== LEDGER_PATH);
  assert.equal(
    otherConflicts.length,
    0,
    `ledger merge: resolve other conflicts first: ${otherConflicts.join(', ')}`,
  );
  const staged = execFileSync(
    'git',
    [
      'diff',
      '--cached',
      '--no-ext-diff',
      '--no-textconv',
      '--text',
      '--no-color',
      '--unified=0',
      '--',
      '.',
      `:!${LEDGER_PATH}`,
    ],
    { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  );
  // Staging a file does not prove its conflict markers were resolved.
  // Inspect raw staged bytes; Git attributes must not hide unresolved markers.
  // conflict-marker-size can emit markers shorter than the default seven characters.
  assert.doesNotMatch(
    staged,
    /^\+(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |$)/m,
    'ledger merge: resolve staged conflict markers first',
  );
  // Git honors per-path conflict-marker-size, including size 1. A global
  // single-character regex would also reject ordinary Markdown blockquotes.
  let checked;
  try {
    checked = execFileSync(
      'git',
      [
        'diff',
        '--cached',
        '--no-ext-diff',
        '--no-textconv',
        '--text',
        '--no-color',
        '--check',
        '--',
        '.',
        `:!${LEDGER_PATH}`,
      ],
      {
        cwd: root,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, LC_ALL: 'C' },
      },
    );
  } catch (error) {
    if (error.status !== 2) throw error;
    checked = error.stdout;
  }
  assert.doesNotMatch(
    checked,
    /: leftover conflict marker$/m,
    'ledger merge: resolve staged conflict markers first',
  );
}

export function runCoverage(argv, { root = ROOT, env = process.env } = {}) {
  if (argv.length === 1 && argv[0] === '--merge-ledger') {
    assertLedgerMergeReady(root);
    const stages = readGitMergeLedgers(root);
    const merged = mergeCorrectionLedgers(stages[0], stages[2], stages[1], (path) =>
      readSource(path, { root }),
    );
    readSource(LEDGER_PATH, { root }); // Refuse symlinked output before writing.
    writeFileSync(resolve(root, LEDGER_PATH), `${JSON.stringify(merged, null, 2)}\n`);
    argv = [];
  }
  const usage =
    'usage: correction-coverage.mjs [--base-ref <sha|origin/main>]... [--output <path>] | --merge-ledger';
  const baseRefs = [];
  let output;
  assert.equal(argv.length % 2, 0, usage);
  for (let index = 0; index < argv.length; index += 2) {
    const option = argv[index];
    const value = argv[index + 1];
    assert.ok(
      ['--base-ref', '--output'].includes(option) && value?.trim() && !value.startsWith('--'),
      usage,
    );
    if (option === '--output') {
      assert.equal(output, undefined, usage);
      output = value;
    } else baseRefs.push(value);
  }
  const current = guardCoverageReport(
    JSON.parse(readSource(LEDGER_PATH, { root })),
    (path) => readSource(path, { root }),
    { requireClassification: true },
  );
  for (const ref of baseRefs) {
    const baseline = coverageReport(JSON.parse(readSource(LEDGER_PATH, { root, ref })), (path) =>
      readSource(path, { root, ref }),
    );
    assertNoRegression(current, baseline);
  }
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, renderCoverage(current));
  current.commitSha = execFileSync('git', ['rev-parse', 'HEAD'], {
    cwd: root,
    encoding: 'utf8',
  }).trim();
  current.timestamp = new Date().toISOString();
  if (output) {
    const outputPath = resolve(root, output);
    mkdirSync(dirname(outputPath), { recursive: true });
    writeFileSync(outputPath, `${JSON.stringify(current, null, 2)}\n`);
  }
  return current;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const report = runCoverage(process.argv.slice(2));
    console.log(
      process.argv.includes('--output')
        ? `Correction coverage: ${report.mechanized}/${report.total} mechanized (${(100 * report.mechanizedShare).toFixed(2)}%); ${LEVELS.map((level) => `${level}=${report.levels[level].total}`).join(', ')}`
        : JSON.stringify(report, null, 2),
    );
  } catch (error) {
    console.error(`Correction coverage failed: ${error.message}`);
    process.exitCode = 1;
  }
}
