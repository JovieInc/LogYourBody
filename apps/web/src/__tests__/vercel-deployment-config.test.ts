import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const repositoryRoot = resolve(__dirname, '../../../..');

describe('Vercel Git deployment configuration', () => {
  it.each([
    ['repository root', resolve(repositoryRoot, 'vercel.json')],
    ['web project root', resolve(repositoryRoot, 'apps/web/vercel.json')],
  ])('%s keeps Production on Actions and allows Preview deployments', (_scope, configPath) => {
    const config = JSON.parse(readFileSync(configPath, 'utf8'));

    expect(config.git.deploymentEnabled).toEqual({ main: false });
    expect(config.github.silent).toBe(true);
  });
});
