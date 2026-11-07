import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
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
  it('does not let workspace overrides hide direct dependency bumps', () => {
    const rootRequire = createRequire(new URL('package.json', root));
    const webRequire = createRequire(new URL('apps/web/package.json', root));
    const { load } = webRequire('js-yaml');
    const { satisfies, validRange } = createRequire(rootRequire.resolve('eslint/package.json'))(
      'semver',
    );
    const { overrides } = load(readFileSync(new URL('pnpm-workspace.yaml', root), 'utf8'));
    const lockfile = load(readFileSync(new URL('pnpm-lock.yaml', root), 'utf8')) as {
      importers: Record<string, Record<string, Record<string, { version: string }>>>;
    };

    for (const [importer, locked] of Object.entries(lockfile.importers)) {
      const manifest: Record<string, Record<string, string>> = JSON.parse(
        readFileSync(new URL(`${importer}/package.json`, root), 'utf8'),
      );
      for (const section of ['dependencies', 'devDependencies', 'optionalDependencies']) {
        for (const [dependency, requested] of Object.entries(manifest[section] ?? {})) {
          if (!Object.hasOwn(overrides, dependency) || !validRange(requested)) continue;
          const resolved = locked[section]?.[dependency]?.version?.split('(')[0];
          const context = `${importer} ${dependency}: ${resolved} must satisfy ${requested}`;
          expect(resolved, context).toBeDefined();
          expect(satisfies(resolved, requested), context).toBe(true);
        }
      }
    }
  });

  it('keeps web React and React DOM dependency ranges in lockstep', () => {
    const manifest = JSON.parse(readFileSync(new URL('apps/web/package.json', root), 'utf8'));
    expect(manifest.dependencies.react).toBe(manifest.dependencies['react-dom']);
  });

  it('renders HTML with the installed web React and React DOM pair', () => {
    const webRequire = createRequire(new URL('apps/web/package.json', root));
    const react = webRequire('react');
    const { renderToString } = webRequire('react-dom/server');

    expect(renderToString(react.createElement('p', null, 'React dependency probe'))).toBe(
      '<p>React dependency probe</p>',
    );
  });

  it('shares the web React runtime with workspace UI components', () => {
    const webRequire = createRequire(new URL('apps/web/package.json', root));
    const uiRequire = createRequire(new URL('packages/jovie-ui/package.json', root));
    expect(uiRequire('react')).toBe(webRequire('react'));
  });

  it('keeps all locked PostCSS copies at the requested patch version', () => {
    const lockfile = readFileSync(new URL('pnpm-lock.yaml', root), 'utf8');
    const versions = [...lockfile.matchAll(/^ {2}postcss@([^:\s]+):/gm)];
    expect(versions.length).toBeGreaterThan(0);
    for (const [, version] of versions) expectAtLeast(version, '8.5.32');
  });

  it.each([
    ['fast-uri', '3.1.9'],
    ['glob', '14.0.2'],
    ['minimatch', '11.0.1'],
    ['undici', '8.12.2'],
  ])('%s has no vulnerable locked copies below %s', (dependency, minimum) => {
    const lockfile = readFileSync(new URL('pnpm-lock.yaml', root), 'utf8');
    const versions = [...lockfile.matchAll(new RegExp(`^ {2}${dependency}@([^:\\s]+):`, 'gm'))];

    expect(versions.length).toBeGreaterThan(0);
    // A patched copy is locked as name@version(patch_hash=...). Compare the semver.
    for (const [, version] of versions) expectAtLeast(version.split('(')[0], minimum);
  });

  it.each([
    ['fast-uri', '3.1.9'],
    ['glob', '14.0.2'],
    ['minimatch', '11.0.1'],
    ['postcss', '8.5.32'],
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
    ['glob', '14.0.2', ['apps/web/package.json']],
    ['minimatch', '11.0.1', ['eslint']],
    ['minimatch', '11.0.1', ['eslint-plugin-react']],
    ['postcss', '8.5.32', ['apps/web/package.json']],
    ['postcss', '8.5.32', ['apps/web/package.json', '@tailwindcss/postcss']],
    ['postcss', '8.5.32', ['apps/web/package.json', 'next']],
    ['undici', '8.12.2', ['eve']],
  ])(
    '%s resolves to a patched version through its installed parent',
    (dependency, minimum, parents) => {
      let parentRequire = createRequire(new URL('package.json', root));
      for (const parent of parents) {
        const parentUrl = parent.endsWith('/package.json')
          ? new URL(parent, root)
          : parentRequire.resolve(parent);
        parentRequire = createRequire(parentUrl);
      }

      expectAtLeast(parentRequire(`${dependency}/package.json`).version, minimum);
    },
  );

  it('keeps minimatch 11 callable for the ESLint 3.x parents', () => {
    const rootRequire = createRequire(new URL('package.json', root));
    const webRequire = createRequire(new URL('apps/web/package.json', root));
    const parents = [
      rootRequire.resolve('eslint-plugin-import'),
      rootRequire.resolve('eslint-plugin-react'),
      webRequire.resolve('eslint-plugin-jsx-a11y'),
    ];

    for (const parent of parents) {
      const parentRequire = createRequire(parent);
      const loaded = parentRequire('minimatch');
      // eslint-plugin-react calls the module itself. eslint-plugin-import and
      // eslint-plugin-jsx-a11y call the Babel __esModule default.
      const callable = loaded.__esModule ? loaded.default : loaded;
      expect(typeof loaded, parent).toBe('function');
      expect(callable, parent).toBe(loaded);
      expect(loaded('src/a.ts', 'src/**/*.ts')).toBe(true);
      expect(loaded.makeRe('*.jsx').test('Button.jsx')).toBe(true);
      expect(new loaded.Minimatch('src/**/*.ts', { dot: true }).match('src', true)).toBe(true);
      expectAtLeast(parentRequire('minimatch/package.json').version, '11.0.1');
    }

    const glob = webRequire('glob');
    const matches = glob.globSync('dependency-security.test.ts', {
      cwd: fileURLToPath(new URL('.', import.meta.url)),
      nodir: true,
    });
    expect(matches).toContain('dependency-security.test.ts');
  });

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
