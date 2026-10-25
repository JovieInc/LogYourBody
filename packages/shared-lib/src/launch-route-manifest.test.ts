import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('validates launch manifests against the pinned Jovie oracle and rejects unclassified screens', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const output = execFileSync(
    process.execPath,
    ['--experimental-vm-modules', '--test', 'scripts/lyb-launch-manifest.test.mjs'],
    { cwd: root, encoding: 'utf8', timeout: 30_000 },
  );
  expect(output).toContain('# fail 0');
  expect(output).toContain('# tests 11');
});
