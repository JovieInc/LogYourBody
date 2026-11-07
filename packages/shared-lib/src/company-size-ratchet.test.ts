import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('rejects company size-500 growth through the required test suite', () => {
  const output = execFileSync(
    process.execPath,
    ['--test', 'packages/shared-lib/scripts/company-size-ratchet.behavior.mjs'],
    { cwd: fileURLToPath(new URL('../../..', import.meta.url)), encoding: 'utf8', timeout: 30_000 },
  );
  expect(output).toContain('# fail 0');
});
