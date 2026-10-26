import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('fails the CI check when launch xcresult coverage, fixture traces, or the installed build id is missing', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const output = execFileSync(
    process.execPath,
    [
      '--experimental-strip-types',
      '--experimental-vm-modules',
      '--test',
      'packages/shared-lib/scripts/installed-build-xcresult.behavior.mjs',
    ],
    { cwd: root, encoding: 'utf8', timeout: 30_000 },
  );
  expect(output).toContain('# tests 7');
  expect(output).toContain('# fail 0');
  expect(output).toContain('missing-xcresult-entry:');
  expect(output).toContain('fixture-substitute:');
  expect(output).toContain('installed-build-id-absent');
});
