import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { routeAuth } from 'eve/channels/auth';
import { eveRouteAuth } from '../../../agent/lib/channel-auth';
import {
  connectionInstruction,
  connectionStateFromAttributes,
} from '../../../agent/lib/account-connection';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));

function readRepoFile(repoRelativePath: string): string {
  return readFileSync(join(repoRoot, repoRelativePath), 'utf8');
}

describe('eve.dev core-chat boundary', () => {
  const agentSource = readRepoFile('agent/agent.ts');
  const channelSource = readRepoFile('agent/channels/eve.ts');
  const dynamicInstructions = readRepoFile('agent/instructions/account-connection.ts');
  const architecture = readRepoFile('docs/architecture/eve-core-chat-migration.md');
  const nativeChatService = readRepoFile('apps/ios/LogYourBody/Services/ChatService.swift');
  const mobileChatRoute = readRepoFile('apps/web/src/app/api/auth/mobile/chat/v1/route.ts');
  const packageJson = JSON.parse(readRepoFile('package.json')) as {
    scripts?: Record<string, string>;
    engines?: { node?: string };
    dependencies?: Record<string, string>;
    devDependencies?: Record<string, string>;
  };

  it('fails closed unless the server supplies the exact connected state', () => {
    expect(connectionStateFromAttributes(undefined)).toBe('unconnected');
    expect(connectionStateFromAttributes({})).toBe('unconnected');
    expect(connectionStateFromAttributes({ logYourBodyConnection: true })).toBe('unconnected');
    expect(connectionStateFromAttributes({ logYourBodyConnection: 'connected' })).toBe('connected');

    expect(connectionInstruction('unconnected')).toMatch(/Do not claim access to health data/);
    expect(connectionInstruction('connected')).toMatch(/does not grant health-data access/);
  });

  it('keeps production auth and product data unavailable in this slice', async () => {
    expect(channelSource).toMatch(/auth:\s*eveRouteAuth\(\)/);
    expect(channelSource).not.toMatch(/\bnone\(/);
    expect(channelSource).not.toMatch(/vercelOidc/);
    expect(dynamicInstructions).toMatch(/'turn\.started'/);
    expect(agentSource).toMatch(/external eve\.dev runtime/);

    for (const tool of [
      'agent',
      'bash',
      'glob',
      'grep',
      'read_file',
      'todo',
      'web_fetch',
      'web_search',
      'write_file',
    ]) {
      expect(readRepoFile(`agent/tools/${tool}.ts`)).toMatch(/disableTool/);
    }

    const defaultResponse = await routeAuth(
      new Request('https://localhost/api/eve'),
      eveRouteAuth({ LYB_EVE_ALLOW_LOCAL_DEV: undefined, VERCEL_ENV: undefined }),
    );
    expect(defaultResponse).toBeInstanceOf(Response);
    expect((defaultResponse as Response).status).toBe(401);

    const productionResponse = await routeAuth(
      new Request('https://localhost/api/eve'),
      eveRouteAuth({ LYB_EVE_ALLOW_LOCAL_DEV: '1', VERCEL_ENV: 'production' }),
    );
    expect(productionResponse).toBeInstanceOf(Response);
    expect((productionResponse as Response).status).toBe(401);

    const localSession = await routeAuth(
      new Request('http://localhost/api/eve'),
      eveRouteAuth({ LYB_EVE_ALLOW_LOCAL_DEV: '1', VERCEL_ENV: 'development' }),
    );
    expect(localSession).not.toBeInstanceOf(Response);
    expect(localSession).toMatchObject({ authenticator: 'local-dev', principalId: 'local-dev' });
  });

  it('preserves the native API and isolates Eve Node requirements', () => {
    expect(architecture).toMatch(/SwiftUI Chat -> LogYourBody first-party API -> eve runtime/);
    expect(architecture).toMatch(/existing first-party chat route and model adapter remain active/);
    expect(architecture).toMatch(/distinct from any internally named Jovie agent or product/);
    expect(nativeChatService).toMatch(/static let endpointPath = "\/api\/auth\/mobile\/chat\/v1"/);
    expect(mobileChatRoute).toMatch(/createModel: createChatModelPort/);
    expect(nativeChatService).not.toMatch(/\beve\b/i);
    expect(packageJson.engines?.node).toBe('20.x');
    expect(packageJson.scripts?.['eve:build']).toBe('bash scripts/eve/run-node24.sh build');
    expect(packageJson.scripts?.['eve:smoke']).toBe('bash scripts/eve/local-smoke.sh');
    expect(packageJson.dependencies?.eve).toBe('0.27.13');
  });

  it('contains no stale job-runner references in tracked files', () => {
    const trackedFiles = execFileSync('git', ['ls-files', '-z'], {
      cwd: repoRoot,
      encoding: 'utf8',
    })
      .split('\0')
      .filter(Boolean);
    const dottedName = new RegExp(['trigger', 'dev'].join('\\.'), 'i');
    const packageName = new RegExp(['trigger', 'dev'].join(''), 'i');

    const matches = trackedFiles.filter((file) => {
      const source = readFileSync(join(repoRoot, file)).toString('utf8');
      return dottedName.test(source) || packageName.test(source);
    });

    expect(matches).toEqual([]);
    const dependencyScope = `@${['trigger', 'dev'].join('.')}`;
    expect(Object.keys(packageJson.dependencies ?? {})).not.toContain(`${dependencyScope}/sdk`);
    expect(Object.keys(packageJson.devDependencies ?? {})).not.toContain(
      `${dependencyScope}/build`,
    );
  });
});
