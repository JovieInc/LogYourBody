import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { posix, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { classifyLedger } from '../../../scripts/correction-classifier.mjs';
import { coverageReport, readSource } from './correction-coverage.mjs';

export function emitCorrectionChecks(receipts) {
  const classified = classifyLedger(receipts);
  classified.forEach((row, index) => {
    assert.ok(
      receipts[index].level === row.level && receipts[index].ruleId === row.ruleId,
      `run correction-classifier first: entry ${index + 1}`,
    );
  });
  const report = coverageReport(classified, () => '', { requireClassification: true });
  return report.rules
    .filter(({ level }) => level === 'static')
    .map((rule) => {
      assert.ok(rule.guard, `static check requires a scanner guard: ${rule.fingerprint}`);
      // Existing hard gates and finding-baseline ratchets keep their own runners.
      assert.ok(!rule.guard.ratchet, `use the existing baseline ratchet: ${rule.fingerprint}`);
      assert.ok(rule.guard.path.endsWith('.mjs'), 'correction check guard must be an mjs scanner');
      return {
        fingerprint: rule.fingerprint,
        ruleId: classified.find(
          ({ fingerprint }) =>
            fingerprint.trim().toLowerCase().replace(/\s+/g, '-') === rule.fingerprint,
        ).ruleId,
        guard: { ...rule.guard },
        recurrence: rule.recurrence.repeatCount,
        severity: rule.recurrence.repeatCount === 0 ? 'warning' : 'error',
      };
    });
}

function findingsFrom(value) {
  assert.ok(Array.isArray(value), 'correction findings must be an array');
  for (const finding of value) {
    assert.ok(
      finding &&
        Object.keys(finding).sort().join(',') === 'key,path' &&
        typeof finding.path === 'string' &&
        typeof finding.key === 'string' &&
        finding.key.trim(),
      'invalid correction finding',
    );
    assert.ok(
      finding.path &&
        posix.normalize(finding.path) === finding.path &&
        !/^(?:\/|\.\.\/)|[\\:\x00-\x1f]/u.test(finding.path),
      'nonlocal correction finding path',
    );
  }
  return value;
}

export async function runCorrectionChecks(
  receipts,
  { root = process.cwd(), report = console.error } = {},
) {
  const checks = emitCorrectionChecks(receipts);
  if (!checks.length) return { checks: [], exitCode: 0 };
  const files = execFileSync(
    'git',
    ['ls-files', '--cached', '--others', '--exclude-standard', '--deduplicate', '-z'],
    { cwd: root, encoding: 'utf8' },
  )
    .split('\0')
    .filter((path) => path && existsSync(resolve(root, path)))
    .sort();
  const snapshot = Object.freeze({
    files: Object.freeze(files),
    readSource: (path) => readSource(path, { root }),
  });
  const results = [];
  for (const check of checks) {
    const source = readSource(check.guard.path, { root });
    assert.ok(source.includes(check.guard.anchor), `missing guard anchor: ${check.fingerprint}`);
    const { scan } = await import(pathToFileURL(resolve(root, check.guard.path)).href);
    assert.equal(typeof scan, 'function', 'correction check guard must export scan');
    const findings = findingsFrom(await scan(snapshot));
    for (const finding of findings) {
      const message = `${check.fingerprint}: ${finding.path}: ${finding.key}`
        .replaceAll('%', '%25')
        .replaceAll('\r', '%0D')
        .replaceAll('\n', '%0A');
      report(`::${check.severity}::${message}`);
    }
    results.push({ ...check, findings });
  }
  return {
    checks: results,
    exitCode: results.some(({ severity, findings }) => severity === 'error' && findings.length)
      ? 1
      : 0,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const args = process.argv.slice(2);
    assert.ok(
      args.length === 1 && !args[0].startsWith('-'),
      'usage: correction-checks.mjs <classified-ledger.json> (run from the source repository)',
    );
    const result = await runCorrectionChecks(JSON.parse(readFileSync(args[0], 'utf8')));
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = result.exitCode;
  } catch (error) {
    console.error(`Correction checks failed: ${error.message}`);
    process.exitCode = 1;
  }
}
