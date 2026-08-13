import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));
const deployWorkflow = readFileSync(`${repoRoot}/.github/workflows/deploy.yml`, 'utf8');

describe('LogYourBody deploy no longer depends on Supabase management tokens', () => {
  it('does not run supabase secrets list or function deploy', () => {
    expect(deployWorkflow).not.toContain('supabase secrets');
    expect(deployWorkflow).not.toContain('SUPABASE_ACCESS_TOKEN');
    expect(deployWorkflow).not.toContain('account-deletion-backend');
    expect(deployWorkflow).not.toContain('supabase functions');
  });
});
