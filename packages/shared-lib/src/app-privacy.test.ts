import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('runs App Store privacy drift regressions through the required test suite', () => {
  const output = execFileSync(
    process.execPath,
    ['--test', 'packages/shared-lib/scripts/app-privacy.behavior.mjs'],
    { cwd: fileURLToPath(new URL('../../..', import.meta.url)), encoding: 'utf8', timeout: 30_000 },
  );
  expect(output).toContain('# fail 0');
});
