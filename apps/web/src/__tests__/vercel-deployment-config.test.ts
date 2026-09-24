import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repositoryRoot = resolve(__dirname, '../../../..');

describe('Vercel Git deployment configuration', () => {
  it.each([
    ['repository root', resolve(repositoryRoot, 'vercel.json')],
    ['web project root', resolve(repositoryRoot, 'apps/web/vercel.json')],
  ])(
    '%s keeps Production on Actions and builds the web workspace with its dependencies',
    (scope, configPath) => {
      const config = JSON.parse(readFileSync(configPath, 'utf8'));
      const isWebProjectRoot = scope === 'web project root';
      const installCommand = isWebProjectRoot
        ? 'cd ../.. && pnpm install --frozen-lockfile && cd apps/web'
        : 'pnpm install --frozen-lockfile';
      const buildCommand = isWebProjectRoot
        ? 'cd ../.. && pnpm turbo run build --filter=logyourbody...'
        : 'pnpm turbo run build --filter=logyourbody...';

      expect(config.git.deploymentEnabled).toEqual({ main: false });
      expect(config.github.silent).toBe(true);
      expect(config.installCommand).toContain(installCommand);
      expect(config.buildCommand).toBe(buildCommand);
    },
  );
});
