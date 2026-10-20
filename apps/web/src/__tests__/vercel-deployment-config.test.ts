import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repositoryRoot = resolve(__dirname, '../../../..');

describe('Vercel Git deployment configuration', () => {
  it.each([
    ['repository root', resolve(repositoryRoot, 'vercel.json')],
    ['web project root', resolve(repositoryRoot, 'apps/web/vercel.json')],
  ])(
    '%s keeps Production on Actions, skips bot-only refs, and builds the web workspace with its dependencies',
    (scope, configPath) => {
      const config = JSON.parse(readFileSync(configPath, 'utf8'));
      const isWebProjectRoot = scope === 'web project root';
      const installCommand = isWebProjectRoot
        ? 'cd ../.. && corepack pnpm install --frozen-lockfile && cd apps/web'
        : 'corepack pnpm install --frozen-lockfile';
      const buildCommand = isWebProjectRoot
        ? 'cd ../.. && corepack pnpm turbo run build --filter=logyourbody...'
        : 'corepack pnpm turbo run build --filter=logyourbody...';

      // main ships through deploy.yml; bot-only refs never queue preview builds
      // (.github/scripts/verify-vercel-branch-exclusions.test.mjs, 2026-10-20).
      expect(config.git.deploymentEnabled).toEqual({
        main: false,
        'backup/**': false,
        'archive/**': false,
        'stash/**': false,
        'gh-readonly-queue/**': false,
      });
      expect(config.github.silent).toBe(true);
      expect(config.installCommand).toContain(installCommand);
      expect(config.buildCommand).toBe(buildCommand);
    },
  );
});
