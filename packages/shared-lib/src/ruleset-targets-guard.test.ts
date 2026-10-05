import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('keeps the branch ruleset verifier regressions in the normal CI test suite', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  expect(() => {
    execFileSync(process.execPath, ['--test', '.github/scripts/verify-ruleset-targets.test.mjs'], {
      cwd: root,
      stdio: 'pipe',
      timeout: 10_000,
    });
  }).not.toThrow();
});
