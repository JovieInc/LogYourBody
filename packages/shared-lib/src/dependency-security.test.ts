import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { describe, expect, it } from 'vitest';

const root = new URL('../../../', import.meta.url);

function expectAtLeast(version: string, minimum: string) {
  expect(version).toMatch(/^\d+\.\d+\.\d+$/);
  const actual = version.split('.').map(Number);
  const floor = minimum.split('.').map(Number);
  const difference = actual.findIndex((part, index) => part !== floor[index]);
  expect(
    difference === -1 || actual[difference] > floor[difference],
    `${version} must be at least ${minimum}`,
  ).toBe(true);
}

describe('Dependabot security update resolution', () => {
  describe.each(['package.json', 'packages/shared-lib/package.json'])(
    '%s installed dependencies',
    (manifest) => {
      const workspaceRequire = createRequire(new URL(manifest, root));
      const vitestRequire = createRequire(workspaceRequire.resolve('vitest/package.json'));

      it.each([
        ['vite', '7.3.7'],
        ['@vitest/mocker', '5.0.3'],
      ])('%s meets the security floor %s', (dependency, minimum) => {
        expectAtLeast(vitestRequire(`${dependency}/package.json`).version, minimum);
      });
    },
  );

  it('keeps both Vite override declarations consistent with the patched lockfile', () => {
    const manifest = JSON.parse(readFileSync(new URL('package.json', root), 'utf8'));
    const workspace = readFileSync(new URL('pnpm-workspace.yaml', root), 'utf8');
    const lockfile = readFileSync(new URL('pnpm-lock.yaml', root), 'utf8');
    const workspaceVite = workspace.match(/^ {2}vite: ["']?([\d.]+)/m)?.[1];
    const lockedVite = lockfile.match(/^ {2}vite: ([\d.]+)/m)?.[1];

    expect(workspaceVite).toBe(manifest.pnpm.overrides.vite);
    expect(lockedVite).toBe(workspaceVite);
    expectAtLeast(workspaceVite!, '7.3.7');
  });
});
