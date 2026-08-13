import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));
const deployWorkflow = readFileSync(`${repoRoot}/.github/workflows/deploy.yml`, 'utf8');
const webReleaseLoop = readFileSync(`${repoRoot}/.github/workflows/web-release-loop.yml`, 'utf8');

const requiredVariables = ['DATABASE_URL', 'OPENAI_API_KEY', 'CRON_SECRET'] as const;
const ripgrepInvocation = /(^|[\s;`])rg(\s|$)/m;

function hasRequiredVariable(envFile: string, requiredVariable: string): boolean {
  try {
    execFileSync('grep', ['-qE', `^${requiredVariable}=`, envFile], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return true;
  } catch {
    return false;
  }
}

describe('deploy Vercel env verify uses POSIX grep', () => {
  const tempDirs: string[] = [];

  afterEach(() => {
    for (const dir of tempDirs.splice(0)) {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('replaces rg with quiet grep and keeps the same required keys', () => {
    expect(deployWorkflow).toContain('Verify authenticated chat runtime configuration');
    expect(deployWorkflow).toContain('grep -qE');
    expect(deployWorkflow).not.toContain('rg --quiet');
    expect(deployWorkflow).not.toMatch(ripgrepInvocation);
    expect(webReleaseLoop).not.toMatch(ripgrepInvocation);

    expect(deployWorkflow).toContain(`for required_variable in ${requiredVariables.join(' ')}`);
    for (const requiredVariable of requiredVariables) {
      expect(deployWorkflow).toContain(requiredVariable);
    }
  });

  it('detects required keys without printing env values', () => {
    const dir = mkdtempSync(join(tmpdir(), 'deploy-vercel-env-verify-'));
    tempDirs.push(dir);
    const envFile = join(dir, '.env.production.local');
    writeFileSync(
      envFile,
      [
        'DATABASE_URL=postgres://example.invalid/db',
        'OPENAI_API_KEY=sk-test-do-not-print',
        'CRON_SECRET=cron-test-do-not-print',
      ].join('\n'),
    );

    for (const requiredVariable of requiredVariables) {
      expect(hasRequiredVariable(envFile, requiredVariable)).toBe(true);
    }

    const listed = execFileSync(
      'grep',
      ['-E', '^(DATABASE_URL|OPENAI_API_KEY|CRON_SECRET)=', envFile],
      { encoding: 'utf8' },
    );
    const quiet = execFileSync(
      'grep',
      ['-qE', '^(DATABASE_URL|OPENAI_API_KEY|CRON_SECRET)=', envFile],
      { encoding: 'utf8' },
    );

    expect(listed).toContain('sk-test-do-not-print');
    expect(quiet).toBe('');
    expect(hasRequiredVariable(envFile, 'MISSING_KEY')).toBe(false);
  });
});
