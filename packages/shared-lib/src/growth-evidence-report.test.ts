import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

// Existing pnpm test / CI discovery executes the real CLI behavior suite.
it('executes the private growth report with current production-code coverage', () => {
  const output = execFileSync(
    process.execPath,
    [
      '--test',
      '--experimental-test-coverage',
      '--test-coverage-include=packages/shared-lib/scripts/growth-report.mjs',
      '--test-coverage-lines=90',
      '--test-coverage-branches=85',
      '--test-coverage-functions=100',
      'packages/shared-lib/scripts/growth-report.behavior.mjs',
    ],
    { cwd: fileURLToPath(new URL('../../..', import.meta.url)), encoding: 'utf8', timeout: 30_000 },
  );
  expect(output).toContain('# fail 0');
  expect(output).toContain('growth-report.mjs');
  console.log(output.slice(output.indexOf('# start of coverage report')));
});
