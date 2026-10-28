import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url));

it('runs mutation harness failure paths with measured coverage', () => {
  const output = execFileSync(
    process.execPath,
    [
      '--test',
      '--experimental-test-coverage',
      '--test-coverage-include=scripts/mutation/run.mjs',
      '--test-coverage-lines=90',
      '--test-coverage-branches=95',
      '--test-coverage-functions=100',
      'scripts/mutation/run.test.mjs',
    ],
    { cwd: root, encoding: 'utf8', timeout: 30_000 },
  );
  expect(output).toContain('# fail 0');
  expect(output).toContain('run.mjs');
}, 30_000);

it('requires every curated launch mutant to be killed by actual assertions', () => {
  execFileSync(process.execPath, ['scripts/mutation/run.mjs'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 60_000,
  });
  const report = JSON.parse(readFileSync(root + '/coverage/mutation/report.json', 'utf8'));
  expect(report.status).toBe('passed');
  expect(report.planned).toBeGreaterThan(0);
  expect(report.executed).toBe(report.planned);
  expect(report.killed).toBe(report.planned);
}, 60_000);
