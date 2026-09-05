import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));
const deployWorkflow = readFileSync(`${repoRoot}/.github/workflows/deploy.yml`, 'utf8');
const webReleaseLoop = readFileSync(`${repoRoot}/.github/workflows/web-release-loop.yml`, 'utf8');
const neonMigrateCliPath = join(repoRoot, 'apps/web/scripts/apply-neon-migrations.ts');

const serverOnlyImport =
  /(?:^|\n)\s*(?:import\s+['"]server-only['"]|import\s+[^;]*\sfrom\s+['"]server-only['"]|require\(\s*['"]server-only['"]\s*\))/;
const relativeSpecifier = /(?:from\s+|import\(\s*|require\(\s*)['"](\.\.?\/[^'"]+)['"]/g;

function resolveLocalModule(fromFile: string, specifier: string): string | undefined {
  const base = join(dirname(fromFile), specifier);
  const candidates = extname(base)
    ? [base]
    : [`${base}.ts`, `${base}.tsx`, `${base}.js`, `${base}.mjs`, join(base, 'index.ts')];

  return candidates.find((candidate) => existsSync(candidate));
}

function collectLocalModuleGraph(entryPath: string): string[] {
  const visited = new Set<string>();
  const queue = [entryPath];

  while (queue.length > 0) {
    const current = queue.pop();
    if (!current || visited.has(current)) continue;
    visited.add(current);

    const source = readFileSync(current, 'utf8');
    for (const match of source.matchAll(relativeSpecifier)) {
      const resolved = resolveLocalModule(current, match[1]);
      if (resolved) queue.push(resolved);
    }
  }

  return [...visited];
}

const requiredVariables = ['DATABASE_URL', 'OPENAI_API_KEY', 'CRON_SECRET'] as const;
const ripgrepInvocation = /(^|[\s;`])rg(\s|$)/m;
const vercelOrgId = 'team_bpNDbti6srVLYPKdmQLu4UgT';
const vercelProjectId = 'prj_6seYBdTtY3TuFqrJek1puaFG6Trj';

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

  it('targets the canonical Vercel team and project in noninteractive CI', () => {
    for (const workflow of [deployWorkflow, webReleaseLoop]) {
      expect(workflow).toContain(`VERCEL_ORG_ID: ${vercelOrgId}`);
      expect(workflow).toContain(`VERCEL_PROJECT_ID: ${vercelProjectId}`);
      expect(workflow).toContain('--scope="$VERCEL_ORG_ID" --project="$VERCEL_PROJECT_ID"');
      expect(workflow).not.toContain('--token="$VERCEL_TOKEN"');
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

describe('deploy neon migrate CLI stays runnable from GitHub Actions', () => {
  it('does not import server-only and stays fail-closed', () => {
    const graph = collectLocalModuleGraph(neonMigrateCliPath);
    expect(graph).toContain(neonMigrateCliPath);

    for (const modulePath of graph) {
      expect(readFileSync(modulePath, 'utf8')).not.toMatch(serverOnlyImport);
    }

    const migrateCli = readFileSync(neonMigrateCliPath, 'utf8');
    expect(migrateCli).toContain('process.env.DATABASE_URL');
    expect(migrateCli).toContain("throw new Error('Missing DATABASE_URL')");
    expect(migrateCli).toContain("await sql.query('begin')");
    expect(migrateCli).toContain("await sql.query('commit')");
    expect(migrateCli).toContain("await sql.query('rollback')");

    expect(deployWorkflow).toContain('Apply product database migrations');
    expect(deployWorkflow).toContain('test -n "$DATABASE_URL"');
    expect(deployWorkflow).toContain('pnpm --filter logyourbody db:apply:neon');
  });

  it('fails closed on missing DATABASE_URL instead of throwing server-only', () => {
    let stdout = '';
    let stderr = '';
    let status = 0;

    try {
      stdout = execFileSync('pnpm', ['exec', 'tsx', 'scripts/apply-neon-migrations.ts'], {
        cwd: join(repoRoot, 'apps/web'),
        env: {
          ...process.env,
          DATABASE_URL: '',
        },
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (error) {
      const failure = error as { status?: number; stdout?: string; stderr?: string };
      status = failure.status ?? 1;
      stdout = failure.stdout ?? '';
      stderr = failure.stderr ?? '';
    }

    const output = `${stdout}\n${stderr}`;
    expect(status).not.toBe(0);
    expect(output).toContain('Missing DATABASE_URL');
    expect(output).not.toContain('This module cannot be imported from a Client Component module');
  });
});
