import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));
const deployWorkflow = readFileSync(`${repoRoot}/.github/workflows/deploy.yml`, 'utf8');
const verifierSource = readFileSync(
  `${repoRoot}/.github/scripts/verify-vercel-chat-runtime-env.mjs`,
  'utf8',
);

function verifyStep(workflow: string): string {
  const match = workflow.match(
    /- name: Verify authenticated chat runtime configuration\n(?: {8}.+\n)+/,
  );

  if (!match) {
    throw new Error('deploy.yml is missing the authenticated chat runtime verification step');
  }

  return match[0];
}

describe('LogYourBody deploy verifies Vercel chat runtime env without ripgrep', () => {
  it('keeps the fail-closed production variable check', () => {
    expect(deployWorkflow).toContain('Verify authenticated chat runtime configuration');
    expect(verifierSource).toContain("'DATABASE_URL'");
    expect(verifierSource).toContain("'OPENAI_API_KEY'");
    expect(verifierSource).toContain("'CRON_SECRET'");
  });

  it('uses a portable Node checker instead of rg', () => {
    const step = verifyStep(deployWorkflow);
    const commands = step
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.length > 0 && !line.startsWith('#') && !line.startsWith('- name:'))
      .join('\n');

    expect(commands).toContain(
      'node --test .github/scripts/verify-vercel-chat-runtime-env.test.mjs',
    );
    expect(commands).toContain('node .github/scripts/verify-vercel-chat-runtime-env.mjs');
    expect(commands).toContain('.vercel/.env.production.local');
    expect(commands).not.toMatch(/(^|[^\w])rg([^\w]|$)/);
    expect(verifierSource).not.toMatch(/(^|[^\w])rg([^\w]|$)/);
  });

  it('proves the checker does not false-fail on a runner without rg', () => {
    const output = execFileSync(
      'node',
      ['--test', '.github/scripts/verify-vercel-chat-runtime-env.test.mjs'],
      {
        cwd: repoRoot,
        encoding: 'utf8',
      },
    );

    expect(output).toMatch(/# pass \d+/);
    expect(output).not.toMatch(/# fail [1-9]/);
  });
});
