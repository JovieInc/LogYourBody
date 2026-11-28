import { execFile } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { describe, expect, it } from 'vitest';

const root = new URL('../../../', import.meta.url);
const webRequire = createRequire(new URL('apps/web/package.json', root));
const { load } = webRequire('js-yaml');
const config = load(readFileSync(new URL('.github/dependabot.yml', root), 'utf8'));
const manifest = JSON.parse(readFileSync(new URL('package.json', root), 'utf8'));
const run = promisify(execFile);

describe('Dependabot pnpm workspace updates (LYB-357)', () => {
  it('schedules the shared lockfile once from the workspace root', () => {
    const updates = config.updates.filter(
      (update: { 'package-ecosystem': string }) => update['package-ecosystem'] === 'npm',
    );
    expect(updates).toHaveLength(1);
    expect(updates[0].directory).toBe('/');
    expect(updates[0].directories).toBeUndefined();
    expect(updates[0].groups?.['react-runtime']).toEqual({ patterns: ['react', 'react-dom'] });
    expect(updates[0].schedule.interval).toBe('weekly');
    expect(updates[0]['open-pull-requests-limit']).toBeGreaterThan(0);
    expect(updates[0].cooldown).toEqual({
      'default-days': 3,
      'semver-major-days': 7,
      'semver-minor-days': 3,
      'semver-patch-days': 1,
    });
    expect(updates[0].ignore).toEqual(
      ['next', 'react', 'react-dom'].map((name) => ({
        'dependency-name': name,
        'update-types': ['version-update:semver-major'],
      })),
    );
    const workspace = load(readFileSync(new URL('pnpm-workspace.yaml', root), 'utf8'));
    expect(workspace.packages).toContain('apps/*');
    expect(workspace.minimumReleaseAgeExclude).toEqual(['next', '@ai-sdk/elevenlabs']);
  });

  it('updates a web dependency while keeping an immature Rollup peer out of the lockfile', async () => {
    const fixture = mkdtempSync(join(tmpdir(), 'lyb-dependabot-'));
    const mature = new Date(Date.now() - 30 * 86_400_000).toISOString();
    const fresh = new Date(Date.now() - 2 * 86_400_000).toISOString();
    const rollup = manifest.devDependencies.rollup as string;
    expect(rollup).toMatch(/^\^4\.\d+\.\d+$/);
    // Keep registry versions inside the real manifest's range after every bump.
    const matureRollup = rollup.slice(1);
    const freshRollup = matureRollup.replace(/\d+$/, (patch) => String(Number(patch) + 1));
    // Model Vite's dependency and Nitro's peer, with a recently locked Rollup.
    const packages: Record<string, Record<string, object>> = {
      leaf: { '1.0.0': {}, '1.1.0': {} },
      tool: { '1.0.0': { peerDependencies: { rollup: '^4.61.1' } } },
      bundler: { '1.0.0': { dependencies: { rollup: '^4.61.1' } } },
      rollup: { [matureRollup]: {}, [freshRollup]: {} },
    };
    let registry: string;
    const server = createServer((request, response) => {
      const name = decodeURIComponent(request.url!.slice(1));
      const versions = packages[name];
      if (!versions) {
        response.writeHead(404).end();
        return;
      }
      response.setHeader('content-type', 'application/json');
      response.end(
        JSON.stringify({
          name,
          'dist-tags': { latest: Object.keys(versions).at(-1) },
          time: Object.fromEntries(
            Object.keys(versions).map((version) => [
              version,
              name === 'rollup' && version === freshRollup ? fresh : mature,
            ]),
          ),
          versions: Object.fromEntries(
            Object.entries(versions).map(([version, content]) => [
              version,
              {
                name,
                version,
                ...content,
                dist: {
                  tarball: `${registry}${name}/-/${name}-${version}.tgz`,
                  shasum: 'a'.repeat(40),
                },
              },
            ]),
          ),
        }),
      );
    });
    try {
      await new Promise<void>((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', resolve);
      });
      const address = server.address();
      if (!address || typeof address === 'string') throw new Error('Missing registry port');
      registry = `http://127.0.0.1:${address.port}/`;
      const fixtureManifest = {
        name: 'fixture',
        private: true,
        packageManager: manifest.packageManager,
        dependencies: { tool: '1.0.0', bundler: '1.0.0' },
      };
      const writeManifest = (devDependencies: Record<string, string> = {}) =>
        writeFileSync(
          join(fixture, 'package.json'),
          JSON.stringify({ ...fixtureManifest, devDependencies }),
        );
      writeManifest();
      writeFileSync(join(fixture, 'pnpm-workspace.yaml'), 'packages: ["apps/*"]\n');
      mkdirSync(join(fixture, 'apps/web'), { recursive: true });
      writeFileSync(
        join(fixture, 'apps/web/package.json'),
        JSON.stringify({
          name: 'web',
          private: true,
          dependencies: { leaf: '1.0.0' },
        }),
      );
      const pnpm = (args: string[]) =>
        run(
          'corepack',
          [
            'pnpm',
            ...args,
            '--ignore-scripts',
            `--registry=${registry}`,
            `--store-dir=${join(fixture, 'store')}`,
            `--cache-dir=${join(fixture, 'cache')}`,
          ],
          { cwd: fixture, timeout: 15_000, env: { ...process.env, CI: 'true' } },
        );
      await pnpm(['install', '--lockfile-only']);
      const initial = readFileSync(join(fixture, 'pnpm-lock.yaml'), 'utf8');
      expect(initial).toContain(`rollup@${freshRollup}:`);
      const update = [
        'update',
        'leaf@1.1.0',
        '--lockfile-only',
        '--no-save',
        '-r',
        '--config.minimum-release-age=4320',
      ];
      // Negative control: the implicit peer is pinned to the immature locked version.
      await expect(pnpm(update)).rejects.toMatchObject({
        stdout: expect.stringContaining('ERR_PNPM_NO_MATURE_MATCHING_VERSION'),
      });
      expect(readFileSync(join(fixture, 'pnpm-lock.yaml'), 'utf8')).toBe(initial);
      writeManifest({ rollup });
      await pnpm(update);
      const lockfile = load(readFileSync(join(fixture, 'pnpm-lock.yaml'), 'utf8'));
      expect(lockfile.importers['apps/web'].dependencies.leaf.version).toBe('1.1.0');
      expect(lockfile.importers['.'].devDependencies.rollup.version).toBe(matureRollup);
      expect(lockfile.snapshots['bundler@1.0.0'].dependencies.rollup).toBe(matureRollup);
      expect(lockfile.packages[`rollup@${freshRollup}`]).toBeUndefined();
    } finally {
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
      rmSync(fixture, { recursive: true, force: true });
    }
  }, 30_000);
});
