import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { appendFileSync, existsSync, lstatSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, posix, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { guardCoverageReport, LEDGER_PATH, readSource, ROOT } from './correction-coverage.mjs';

const SCHEMA = 'lyb.correction-ratchet/v1';

function localPath(path) {
  assert.ok(
    typeof path === 'string' &&
      path &&
      posix.normalize(path) === path &&
      !/^(?:\/|\.\.\/)|[\\:\x00-\x1f]/u.test(path),
    'nonlocal ratchet path',
  );
  return path;
}

function normalizeFindings(findings) {
  assert.ok(Array.isArray(findings), 'ratchet findings must be an array');
  return findings
    .map((finding) => {
      assert.ok(
        finding &&
          Object.keys(finding).sort().join(',') === 'key,path' &&
          typeof finding.key === 'string' &&
          finding.key.trim(),
        'ratchet finding requires only a local path and a nonblank key',
      );
      return { path: localPath(finding.path), key: finding.key };
    })
    .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
}

function assertSubset(current, baseline, reason) {
  const available = new Map();
  for (const finding of baseline) {
    const key = JSON.stringify(finding);
    available.set(key, (available.get(key) ?? 0) + 1);
  }
  for (const finding of current) {
    const key = JSON.stringify(finding);
    assert.ok(available.get(key) > 0, `${reason}: ${finding.path}`);
    available.set(key, available.get(key) - 1);
  }
}

function ratchets(receipts) {
  const rules = new Map();
  const paths = new Map();
  for (const receipt of receipts) {
    const config = receipt.guard?.ratchet;
    if (config === undefined) continue;
    assert.ok(config && Object.keys(config).join(',') === 'baseline', 'invalid guard ratchet');
    const baseline = localPath(config.baseline);
    const fingerprint = receipt.fingerprint.trim().toLowerCase().replace(/\s+/g, '-');
    assert.ok(
      !paths.has(baseline) || paths.get(baseline) === fingerprint,
      'shared ratchet baseline',
    );
    assert.ok(receipt.guard.path.endsWith('.mjs'), 'ratchet guard must be an mjs scanner');
    paths.set(baseline, fingerprint);
    rules.set(fingerprint, { fingerprint, path: receipt.guard.path, baseline });
  }
  return rules;
}

function readBaseline(path, options) {
  const value = JSON.parse(readSource(path, options));
  assert.equal(value.schema, SCHEMA, 'invalid ratchet baseline schema');
  return normalizeFindings(value.findings);
}

function snapshot(root, ref) {
  const output = execFileSync(
    'git',
    ref
      ? ['ls-tree', '-r', '-z', ref]
      : ['ls-files', '--cached', '--others', '--exclude-standard', '--deduplicate', '-z'],
    { cwd: root, encoding: 'utf8' },
  );
  const files = output
    .split('\0')
    .filter(Boolean)
    .flatMap((entry) => {
      if (ref)
        return /^100(?:644|755) blob /.test(entry) ? [entry.slice(entry.indexOf('\t') + 1)] : [];
      return existsSync(resolve(root, entry)) ? [entry] : [];
    });
  return Object.freeze({
    files: Object.freeze(files.sort()),
    readSource: (path) => readSource(path, { root, ref }),
  });
}

export async function runRatchets(
  argv,
  { root = ROOT, env = process.env, warn = console.warn } = {},
) {
  let ref;
  let update = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--base-ref' && !ref && argv[i + 1]) ref = argv[++i];
    else if (argv[i] === '--update-baselines' && !update) update = true;
    else
      throw new Error(
        'usage: correction-ratchet.mjs [--base-ref <sha|origin/main>] [--update-baselines]',
      );
  }
  assert.ok(!update || ref, '--update-baselines requires --base-ref');
  const receipts = JSON.parse(readSource(LEDGER_PATH, { root }));
  guardCoverageReport(receipts, (path) => readSource(path, { root }), {
    requireClassification: true,
  });
  const current = ratchets(receipts);
  const previous = ref ? ratchets(JSON.parse(readSource(LEDGER_PATH, { root, ref }))) : new Map();
  for (const fingerprint of previous.keys()) {
    assert.ok(current.has(fingerprint), `removed correction ratchet: ${fingerprint}`);
  }
  const report = [];
  const writes = [];
  // Validate every rule before an update can change any baseline.
  for (const rule of current.values()) {
    const { fingerprint, path, baseline } = rule;
    readSource(path, { root }); // Reject symlinks before importing executable guard code.
    const { scan } = await import(pathToFileURL(resolve(root, path)).href);
    assert.equal(typeof scan, 'function', `ratchet guard must export scan: ${fingerprint}`);
    const before = previous.get(fingerprint);
    const limit = before
      ? readBaseline(before.baseline, { root, ref })
      : ref
        ? normalizeFindings(await scan(snapshot(root, ref)))
        : undefined;
    let allowed;
    try {
      allowed = readBaseline(baseline, { root });
    } catch (error) {
      // Seeding is explicit, checked against the immutable base, and never hides malformed data.
      if (error.code !== 'ENOENT' || !update || before) throw error;
      allowed = limit;
    }
    if (limit) assertSubset(allowed, limit, `baseline growth: ${fingerprint}`);
    const findings = normalizeFindings(await scan(snapshot(root)));
    assertSubset(findings, allowed, `new correction violation: ${fingerprint}`);
    if (update) {
      const target = resolve(root, baseline);
      assert.equal(
        realpathSync(dirname(target)),
        dirname(target),
        'baseline parent traverses a symlink',
      );
      assert.ok(
        !lstatSync(target, { throwIfNoEntry: false })?.isSymbolicLink(),
        'baseline is a symlink',
      );
      writes.push([baseline, `${JSON.stringify({ schema: SCHEMA, findings }, null, 2)}\n`]);
    } else
      assert.deepEqual(
        allowed,
        findings,
        `stale correction baseline: ${fingerprint}; run --update-baselines --base-ref origin/main`,
      );
    if (findings.length)
      warn(
        `::warning::LYB correction ${fingerprint}: ${findings.length} existing finding(s); baseline can only shrink.`,
      );
    report.push({ fingerprint, baseline, findings: findings.length });
  }
  for (const [path, contents] of writes) writeFileSync(resolve(root, path), contents);
  if (env.GITHUB_STEP_SUMMARY) {
    appendFileSync(
      env.GITHUB_STEP_SUMMARY,
      [
        '## LYB correction violation ratchets',
        '',
        ...report.map(
          (rule) => `- ${rule.fingerprint}: ${rule.findings} accepted existing finding(s).`,
        ),
        '',
      ].join('\n'),
    );
  }
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    console.log(JSON.stringify(await runRatchets(process.argv.slice(2)), null, 2));
  } catch (error) {
    console.error(`Correction ratchet failed: ${error.message}`);
    process.exitCode = 1;
  }
}
