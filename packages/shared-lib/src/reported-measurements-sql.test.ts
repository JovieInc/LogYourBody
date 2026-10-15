import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url)).replace(/\/$/, '');
// trace's CLI can swallow SystemExit; preserve the real unittest exit status.
const driver = `
import runpy, sys, trace
tracer = trace.Trace(count=True, trace=False, ignoredirs=[sys.prefix])
status = 0
test_path, coverage_dir = sys.argv[1:]
sys.argv = [test_path]
try:
    tracer.runctx("runpy.run_path(test_path, run_name='__main__')",
                  {"runpy": runpy, "test_path": test_path}, {})
except SystemExit as error:
    status = error.code
finally:
    tracer.results().write_results(show_missing=True, summary=True, coverdir=coverage_dir)
sys.exit(status)
`;

function checkedTrace(
  test: string,
  directory: string,
  production = root + '/scripts/neon/test-reported-measurements.py',
) {
  const output = execFileSync('python3', ['-c', driver, test, directory], {
    encoding: 'utf8',
    cwd: root,
    timeout: 30_000,
  });
  expect(output).toContain('Reported measurements harness behavior tests executed: 8');
  const measured = output
    .split('\n')
    .map((line) => line.match(/^\s*\d+\s+(\d+)%\s+\S+\s+\((.+)\)$/))
    .find((row) => row?.[2] === production);
  expect(measured, 'The production harness must execute under trace').toBeDefined();
  expect(Number(measured?.[1])).toBeGreaterThanOrEqual(90);
  return output;
}

it('executes reported SQL harness process and failure paths with at least 90% production line coverage', () => {
  const directory = mkdtempSync(tmpdir() + '/lyb-reported-sql-coverage-');
  try {
    const output = checkedTrace(
      root + '/scripts/neon/test_reported_measurements_harness.py',
      directory,
    );
    console.log(
      output
        .split('\n')
        .filter((line) => /test-reported-measurements|behavior tests executed/.test(line))
        .join('\n'),
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}, 30_000);

it('fails the CI wrapper on an actual Python assertion failure and nonzero exit', () => {
  const directory = mkdtempSync(tmpdir() + '/lyb-reported-sql-failure-');
  try {
    const test = directory + '/failed.py';
    writeFileSync(
      test,
      'import unittest\nclass Failure(unittest.TestCase):\n    def test_real_failure(self):\n        self.assertEqual(1, 2)\nunittest.main()\n',
    );
    expect(() => checkedTrace(test, directory)).toThrow(/AssertionError: 1 != 2/);
    writeFileSync(test, 'import sys; sys.exit(7)\n');
    expect(() => checkedTrace(test, directory)).toThrow(/Command failed/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

it('fails the CI wrapper when a passing suite inadequately executes the production harness', () => {
  const directory = mkdtempSync(tmpdir() + '/lyb-reported-sql-undercoverage-');
  try {
    const production = directory + '/test-reported-measurements.py';
    writeFileSync(
      production,
      'def unexecuted():\n    value = 1\n    value += 2\n    return value\nloaded = True\n',
    );
    const test = directory + '/passed.py';
    writeFileSync(
      test,
      'import runpy\nrunpy.run_path(' +
        JSON.stringify(production) +
        ')\nprint("Reported measurements harness behavior tests executed: 8")\n',
    );
    expect(() => checkedTrace(test, directory, production)).toThrow(/greater than or equal to 90/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
