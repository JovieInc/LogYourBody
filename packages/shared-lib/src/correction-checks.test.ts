import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('runs emitted correction checks and their exit behavior through the normal CI suite', () => {
  const output = execFileSync(
    process.execPath,
    [
      '--test',
      '--experimental-test-coverage',
      '--test-coverage-include=packages/shared-lib/scripts/correction-checks.mjs',
      '--test-coverage-lines=100',
      '--test-coverage-branches=100',
      '--test-coverage-functions=100',
      'packages/shared-lib/scripts/correction-checks.behavior.mjs',
    ],
    { cwd: fileURLToPath(new URL('../../..', import.meta.url)), encoding: 'utf8', timeout: 30_000 },
  );
  expect(output).toContain('# fail 0');
  console.log(output.slice(output.indexOf('# start of coverage report')));
});
