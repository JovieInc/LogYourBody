import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const workflow = readFileSync(join(root, '.github/workflows/ios-release-loop.yml'), 'utf8');
const job = workflow.split('\n  create-release:\n')[1];
const publication = job.split('      - name: Create GitHub release\n')[1];
const builtCommit = '8f05c37800efd9aa595421f340f2e8bbfd6e45f4';
const appToken = 'fixture-repository-app-token';

function publish({ prerelease = true, existing = false, denied = false } = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-ios-release-'));
  const calls = join(directory, 'calls.jsonl');
  const tag = prerelease ? 'ios-v1.2.0-testflight.20261017004754' : 'ios-v1.2.0';
  const expressions: Record<string, string> = {
    'steps.release_metadata.outputs.tag': tag,
    'steps.release_metadata.outputs.version': 'ios-v1.2.0',
    'steps.release_metadata.outputs.deployment_type': prerelease ? 'testflight' : 'app_store',
    'steps.release_metadata.outputs.prerelease': String(prerelease),
    'needs.validate-release.outputs.build_number': '20261017004754',
    'github.sha': builtCommit,
    'github.actor': 'github-merge-queue[bot]',
    'github.server_url': new URL('https://github.com/JovieInc/LogYourBody').origin,
    'github.repository': 'JovieInc/LogYourBody',
    'github.run_id': '38986790647',
    'steps.release-token.outputs.token': appToken,
    'secrets.GITHUB_TOKEN': 'fixture-actions-token',
  };
  const render = (source: string) =>
    source.replace(/\$\{\{\s*([^}]+?)\s*\}\}/g, (_, key: string) => {
      if (!(key in expressions)) throw new Error(`Unexpected workflow expression: ${key}`);
      return expressions[key];
    });
  const script = publication
    .split('        run: |\n')[1]
    .split('\n')
    .map((line) => line.replace(/^ {10}/, ''))
    .join('\n');
  const tokenExpression = publication.match(/GH_TOKEN: (.+)/)?.[1];
  expect(tokenExpression).toBeDefined();

  try {
    // Reproduce GitHub's workflow-scope denial for an older built commit:
    // the Actions token cannot publish it after main's workflows change.
    writeFileSync(
      join(directory, 'gh'),
      `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.RELEASE_CALLS, JSON.stringify(args) + '\\n');
if (args[0] === 'release' && args[1] === 'view') {
  process.exit(process.env.RELEASE_EXISTS === 'true' ? 0 : 1);
}
if (args[0] !== 'release' || args[1] !== 'create') process.exit(99);
if (process.env.GH_TOKEN !== '${appToken}' || process.env.RELEASE_DENIED === 'true') {
  console.error('HTTP 403: Resource not accessible by integration');
  process.exit(1);
}
`,
      { mode: 0o755 },
    );
    const result = spawnSync('bash', ['-e', '-o', 'pipefail', '-c', render(script)], {
      encoding: 'utf8',
      timeout: 10_000,
      env: {
        PATH: `${directory}:${process.env.PATH}`,
        GH_TOKEN: render(tokenExpression!),
        GITHUB_SHA: builtCommit,
        RELEASE_CALLS: calls,
        RELEASE_EXISTS: String(existing),
        RELEASE_DENIED: String(denied),
      },
    });
    return {
      ...result,
      tag,
      calls: readFileSync(calls, 'utf8')
        .trim()
        .split('\n')
        .map((line) => JSON.parse(line) as string[]),
    };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

describe('iOS release publication', () => {
  it('mints a short-lived token scoped to this repository with the required workflow permission', () => {
    const tokenStep = job.match(/ {6}- name: Mint release token\n([\s\S]*?)(?=\n {6}- name:)/)?.[1];
    expect(tokenStep).toBeDefined();
    expect(tokenStep).toMatch(/actions\/create-github-app-token@[a-f0-9]{40}/);
    expect(tokenStep).toContain('app-id: ${{ vars.JOVIE_BOT_APP_ID }}');
    expect(tokenStep).toContain('private-key: ${{ secrets.JOVIE_BOT_PRIVATE_KEY }}');
    expect(tokenStep).toContain('owner: ${{ github.repository_owner }}');
    expect(tokenStep).toContain('repositories: ${{ github.event.repository.name }}');
    expect(tokenStep).toContain('permission-contents: write');
    expect(tokenStep).toContain('permission-workflows: write');
    expect(tokenStep).not.toContain('skip-token-revoke:');
    expect(publication).toContain('GH_TOKEN: ${{ steps.release-token.outputs.token }}');
    expect(job).toMatch(/permissions:\n {6}contents: read/);
  });

  it.each([true, false])(
    'publishes prerelease=%s at the built SHA after main advances',
    (prerelease) => {
      const result = publish({ prerelease });
      expect(result.status, result.stderr).toBe(0);
      expect(result.calls).toHaveLength(2);
      const args = result.calls[1];
      expect(args.slice(0, 3)).toEqual(['release', 'create', result.tag]);
      expect(args[args.indexOf('--target') + 1]).toBe(builtCommit);
      expect(args.includes('--prerelease')).toBe(prerelease);
      const notes = args[args.indexOf('--notes') + 1];
      expect(notes).toContain(`**Commit**: ${builtCommit}`);
      expect(notes).toContain('**Build Number**: 20261017004754');
    },
  );

  it('does not republish an existing release on retry', () => {
    const result = publish({ existing: true });
    expect(result.status, result.stderr).toBe(0);
    expect(result.calls).toEqual([['release', 'view', result.tag]]);
  });

  it('still fails when GitHub denies publication', () => {
    const result = publish({ denied: true });
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('HTTP 403: Resource not accessible by integration');
  });
});
