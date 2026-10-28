import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const reporter = fileURLToPath(new URL('./reporter.mjs', import.meta.url));
const hash = (value) => createHash('sha256').update(value).digest('hex');

function requireValid(condition, message) {
  if (!condition) throw new Error(message);
}

function relativeFile(path) {
  requireValid(
    typeof path === 'string' &&
      path.length > 0 &&
      !isAbsolute(path) &&
      !path.split(/[\\/]/).some((part) => !part || part === '.' || part === '..'),
    'Invalid target path',
  );
}

export function validateManifest(manifest) {
  requireValid(
    manifest?.schemaVersion === 1 && Array.isArray(manifest.targets) && manifest.targets.length > 0,
    'A nonempty v1 mutation manifest is required',
  );
  const ids = new Set();
  for (const target of manifest.targets) {
    requireValid(
      typeof target.id === 'string' && !ids.has(target.id),
      'Duplicate or invalid target ID',
    );
    ids.add(target.id);
    for (const path of [target.source, target.test]) relativeFile(path);
    requireValid(
      target.source.endsWith('.mjs') &&
        target.test.endsWith('.mjs') &&
        target.source !== target.test,
      'Targets require separate JavaScript source and tests',
    );
    requireValid(
      Number.isSafeInteger(target.timeoutMs) && target.timeoutMs > 0 && target.timeoutMs <= 60_000,
      'Invalid test timeout',
    );
    requireValid(
      Number.isSafeInteger(target.minimumTests) && target.minimumTests > 0,
      'A positive test count is required',
    );
    for (const key of ['lines', 'branches', 'functions']) {
      requireValid(
        Number.isFinite(target.coverage?.[key]) &&
          target.coverage[key] > 0 &&
          target.coverage[key] <= 100,
        'Positive baseline coverage floors are required',
      );
    }
    requireValid(
      target.testNamePattern === undefined || typeof target.testNamePattern === 'string',
      'Invalid test selector',
    );
    requireValid(
      Array.isArray(target.mutations) && target.mutations.length > 0,
      'Empty mutation target',
    );
    const mutations = new Set();
    for (const mutation of target.mutations) {
      requireValid(
        typeof mutation.id === 'string' && !mutations.has(mutation.id),
        'Duplicate mutation ID',
      );
      mutations.add(mutation.id);
      requireValid(
        typeof mutation.find === 'string' &&
          mutation.find.length > 0 &&
          typeof mutation.replace === 'string' &&
          mutation.find !== mutation.replace,
        'Mutation must change a nonempty source anchor',
      );
    }
  }
  return manifest;
}

export function replaceOnce(source, mutation) {
  requireValid(
    source.split(mutation.find).length === 2,
    'Mutation source anchor must match exactly once',
  );
  return source.replace(mutation.find, () => mutation.replace);
}

export function classifyExecution(result, minimumTests, expectedTests) {
  if (result.error || result.signal) {
    return {
      status: result.error?.code === 'ETIMEDOUT' ? 'timeout' : 'error',
      reason: result.error?.code ?? result.signal,
    };
  }
  let events;
  try {
    events = result.stdout
      .trim()
      .split('\n')
      .map((line) => JSON.parse(line));
  } catch {
    return { status: 'error', reason: 'Missing structured test output' };
  }
  const summary = events.findLast((event) => event.type === 'summary' && !event.file);
  const counts = summary?.counts;
  if (
    !counts ||
    counts.tests < minimumTests ||
    (expectedTests !== undefined && counts.tests !== expectedTests) ||
    counts.cancelled ||
    counts.skipped ||
    counts.todo ||
    counts.passed + counts.failed !== counts.tests
  ) {
    return { status: 'error', reason: 'Incomplete test execution', counts };
  }
  const failures = events.filter((event) => event.type === 'failure');
  if (result.status === 0 && summary.success && counts.failed === 0) {
    const coverage = events.find((event) => event.type === 'coverage')?.summary;
    return {
      status: 'passed',
      counts,
      coverage: coverage?.totals,
      coverageFiles: coverage?.files,
    };
  }
  const assertion = (event) =>
    event.code === 'ERR_ASSERTION' || event.causeCode === 'ERR_ASSERTION';
  if (
    result.status === 1 &&
    counts.failed > 0 &&
    failures.some(assertion) &&
    failures.every((event) => assertion(event) || event.failureType === 'subtestsFailed')
  ) {
    return {
      status: 'killed',
      counts,
      failingTests: failures.filter(assertion).map((event) => event.name),
    };
  }
  return { status: 'error', reason: 'Non-assertion test or process failure', counts };
}

function coveredSource(files, path, floors) {
  const source = files?.find((file) => file.path === path);
  if (!source || source.totalLineCount <= 0 || source.coveredLineCount <= 0) return null;
  const metrics = [
    ['Line', 'lines'],
    ['Branch', 'branches'],
    ['Function', 'functions'],
  ];
  for (const [metric, floor] of metrics) {
    const total = source[`total${metric}Count`];
    const covered = source[`covered${metric}Count`];
    const percent = source[`covered${metric}Percent`];
    if (
      !Number.isSafeInteger(total) ||
      !Number.isSafeInteger(covered) ||
      covered < 0 ||
      covered > total ||
      !Number.isFinite(percent) ||
      percent < floors[floor] ||
      percent > 100
    )
      return null;
  }
  const {
    path: _path,
    lines: _lines,
    branches: _branches,
    functions: _functions,
    ...summary
  } = source;
  return summary;
}

function execute(args, cwd, timeoutMs) {
  // A campaign may itself run inside node:test. Start an independent reporter
  // rather than inheriting its private child-process serialization protocol.
  const env = { ...process.env };
  delete env.NODE_TEST_CONTEXT;
  return spawnSync(process.execPath, args, {
    cwd,
    encoding: 'utf8',
    timeout: timeoutMs,
    env,
    maxBuffer: 4 * 1024 * 1024,
    killSignal: 'SIGKILL',
  });
}

export function runCampaign(root, manifest) {
  validateManifest(manifest);
  const results = [];
  for (const target of manifest.targets) {
    const directory = mkdtempSync(join(tmpdir(), 'lyb-mutation-'));
    const result = {
      id: target.id,
      source: target.source,
      test: target.test,
      selector: target.testNamePattern ?? null,
      hashes: {},
      mutations: [],
    };
    results.push(result);
    try {
      for (const path of [target.source, target.test]) {
        const contents = readFileSync(join(root, path));
        result.hashes[path] = hash(contents);
        mkdirSync(dirname(join(directory, path)), { recursive: true });
        writeFileSync(join(directory, path), contents);
      }
      const source = readFileSync(join(directory, target.source), 'utf8');
      // Each invocation already has its own process and filesystem snapshot.
      // Avoid a second test child that could survive the outer timeout.
      const args = ['--test', '--experimental-test-isolation=none', `--test-reporter=${reporter}`];
      if (target.testNamePattern) args.push(`--test-name-pattern=${target.testNamePattern}`);
      const baselineArgs = [
        ...args,
        '--experimental-test-coverage',
        `--test-coverage-include=${target.source}`,
        `--test-coverage-lines=${target.coverage.lines}`,
        `--test-coverage-branches=${target.coverage.branches}`,
        `--test-coverage-functions=${target.coverage.functions}`,
        target.test,
      ];
      result.baseline = classifyExecution(
        execute(baselineArgs, directory, target.timeoutMs),
        target.minimumTests,
      );
      result.baseline.coverage = coveredSource(
        result.baseline.coverageFiles,
        join(directory, target.source),
        target.coverage,
      );
      delete result.baseline.coverageFiles;
      if (result.baseline.status !== 'passed' || !result.baseline.coverage) {
        result.status = 'baseline_failed';
        continue;
      }
      for (const mutation of target.mutations) {
        const outcome = { id: mutation.id };
        result.mutations.push(outcome);
        try {
          const mutated = replaceOnce(source, mutation);
          outcome.sha256 = hash(mutated);
          writeFileSync(join(directory, target.source), mutated);
          const syntax = execute(['--check', target.source], directory, target.timeoutMs);
          if (syntax.error || syntax.signal || syntax.status !== 0) {
            Object.assign(outcome, {
              status: 'invalid',
              reason: 'Mutant did not pass syntax validation',
            });
            continue;
          }
          Object.assign(
            outcome,
            classifyExecution(
              execute([...args, target.test], directory, target.timeoutMs),
              target.minimumTests,
              result.baseline.counts.tests,
            ),
          );
          if (outcome.status === 'passed') outcome.status = 'survived';
        } catch (error) {
          Object.assign(outcome, { status: 'invalid', reason: error.message });
        } finally {
          writeFileSync(join(directory, target.source), source);
        }
      }
      result.status = result.mutations.every((mutation) => mutation.status === 'killed')
        ? 'passed'
        : 'failed';
    } catch (error) {
      Object.assign(result, { status: 'error', reason: error.message });
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }
  const mutations = results.flatMap((target) => target.mutations);
  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    manifestSha256: hash(JSON.stringify(manifest)),
    scope:
      'Curated semantic mutants for the listed JavaScript policy files; not whole-app or Swift mutation coverage.',
    status: results.every((target) => target.status === 'passed') ? 'passed' : 'failed',
    planned: manifest.targets.reduce((count, target) => count + target.mutations.length, 0),
    executed: mutations.length,
    killed: mutations.filter((mutation) => mutation.status === 'killed').length,
    targets: results,
  };
}

export function runCLI(args, root = repository) {
  let result;
  try {
    requireValid(args.length === 0, 'Mutation command accepts no overrides');
    const manifest = JSON.parse(readFileSync(join(root, 'scripts/mutation/targets.json'), 'utf8'));
    result = runCampaign(root, manifest);
  } catch (error) {
    result = { schemaVersion: 1, status: 'failed', reason: error.message };
  }
  const reportPath = join(root, 'coverage/mutation/report.json');
  mkdirSync(dirname(reportPath), { recursive: true });
  const temporary = `${reportPath}.${process.pid}.tmp`;
  writeFileSync(temporary, JSON.stringify(result, null, 2) + '\n');
  renameSync(temporary, reportPath);
  console.log(
    `Mutation ${result.status}: ${result.killed ?? 0}/${result.planned ?? 0} killed; report: coverage/mutation/report.json`,
  );
  return result.status === 'passed' ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = runCLI(process.argv.slice(2));
}
