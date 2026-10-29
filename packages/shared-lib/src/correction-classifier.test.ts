import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('runs correction classifier fixtures and CLI behavior through the normal script test runner', () => {
  const output = execFileSync(
    process.execPath,
    [
      '--test',
      '--experimental-test-coverage',
      '--test-coverage-include=scripts/correction-classifier.mjs',
      '--test-coverage-lines=100',
      '--test-coverage-branches=100',
      '--test-coverage-functions=100',
      'scripts/correction-classifier.test.mjs',
    ],
    {
      cwd: fileURLToPath(new URL('../../..', import.meta.url)),
      encoding: 'utf8',
      // The expanded Git matrix covers dozens of isolated merge scenarios. Keep child
      // CLI/Git deadlines and full coverage, with room for hosted runner load.
      timeout: 120_000,
      env: { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' },
    },
  );
  expect(output).toContain('# fail 0');
  console.log(output.slice(output.indexOf('# start of coverage report')));
}, 125_000);
