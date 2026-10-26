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
  it.each([
    ['fast-uri', '3.1.9'],
    ['undici', '8.12.2'],
  ])('%s has no vulnerable locked copies below %s', (dependency, minimum) => {
    const lockfile = readFileSync(new URL('pnpm-lock.yaml', root), 'utf8');
    const versions = [...lockfile.matchAll(new RegExp(`^ {2}${dependency}@([^:\\s]+):`, 'gm'))];

    expect(versions.length).toBeGreaterThan(0);
    for (const [, version] of versions) expectAtLeast(version, minimum);
  });

  it.each([
    ['fast-uri', '3.1.9'],
    ['undici', '8.12.2'],
  ])('%s keeps manifest, workspace and lockfile overrides consistent', (dependency, minimum) => {
    const manifest = JSON.parse(readFileSync(new URL('package.json', root), 'utf8'));
    const workspace = readFileSync(new URL('pnpm-workspace.yaml', root), 'utf8');
    const lockfile = readFileSync(new URL('pnpm-lock.yaml', root), 'utf8');
    const overridePattern = new RegExp(`^ {2}${dependency}: ["']?(\\^?[\\d.]+)`, 'm');
    const workspaceOverride = workspace.match(overridePattern)?.[1];

    expect(workspaceOverride).toBe(manifest.pnpm.overrides[dependency]);
    expect(lockfile.match(overridePattern)?.[1]).toBe(workspaceOverride);
    expectAtLeast(workspaceOverride!.replace(/^\^/, ''), minimum);
  });

  it.each([
    [
      'fast-uri',
      '3.1.9',
      ['@commitlint/cli', '@commitlint/load', '@commitlint/config-validator', 'ajv'],
    ],
    ['undici', '8.12.2', ['eve']],
  ])(
    '%s resolves to a patched version through its installed parent',
    (dependency, minimum, parents) => {
      let parentRequire = createRequire(new URL('package.json', root));
      for (const parent of parents) parentRequire = createRequire(parentRequire.resolve(parent));

      expectAtLeast(parentRequire(`${dependency}/package.json`).version, minimum);
    },
  );

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
