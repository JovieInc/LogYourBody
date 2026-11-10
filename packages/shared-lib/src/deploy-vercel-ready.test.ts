import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it, vi } from 'vitest';
import { run } from '../../../.github/scripts/wait-vercel-deployment.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const workflow = readFileSync(join(root, '.github/workflows/deploy.yml'), 'utf8');
const deployScript = workflow
  .split('      - name: Deploy to Vercel\n')[1]
  .split('        run: |\n')[1]
  .split('\n\n')[0]
  .replace(/^ {10}/gm, '');

function runDeploy(state: string, cliStatus = 0) {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-vercel-ready-'));
  const outputPath = join(directory, 'output');
  const argsPath = join(directory, 'args');
  const preloadPath = join(directory, 'preload.mjs');
  try {
    writeFileSync(outputPath, '');
    writeFileSync(
      join(directory, 'pnpm'),
      '#!/bin/sh\nprintf "%s\\n" "$@" > "$CLI_ARGS"\necho "https://lyb-deployment.example.com"\nexit "$CLI_STATUS"\n',
      { mode: 0o755 },
    );
    writeFileSync(
      preloadPath,
      'globalThis.fetch = async () => ({ ok: true, json: async () => ({ readyState: process.env.TEST_READY_STATE }) });\n',
    );
    const result = spawnSync('bash', ['-e', '-o', 'pipefail', '-c', deployScript], {
      cwd: root,
      encoding: 'utf8',
      timeout: 10_000,
      env: {
        ...process.env,
        PATH: `${directory}:${process.env.PATH}`,
        NODE_OPTIONS: `--import=${preloadPath}`,
        VERCEL_TOKEN: 'fixture-token',
        VERCEL_ORG_ID: 'team_fixture',
        VERCEL_PROJECT_ID: 'prj_fixture',
        DEPLOYMENT_URL: '',
        GITHUB_OUTPUT: outputPath,
        CLI_ARGS: argsPath,
        CLI_STATUS: String(cliStatus),
        TEST_READY_STATE: state,
      },
    });
    return {
      status: result.status,
      logs: `${result.stdout}\n${result.stderr}`,
      output: readFileSync(outputPath, 'utf8'),
      args: readFileSync(argsPath, 'utf8').trim().split('\n'),
    };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

describe('Vercel production deployment readiness', () => {
  it('fails the actual deploy step on BLOCKED before publishing a success URL', () => {
    const result = runDeploy('BLOCKED');
    expect(result.status).toBe(1);
    expect(result.logs).toContain('::error::Vercel production deployment is BLOCKED');
    expect(result.logs).toContain('Tim must inspect https://vercel.com/jovie/log-your-body');
    expect(result.logs).not.toContain('fixture-token');
    expect(result.logs).not.toContain('Deployed to');
    expect(result.output).toBe('');
  });

  it('submits a scoped prebuilt production deploy without waiting, then publishes only READY', () => {
    const result = runDeploy('READY');
    expect(result.status).toBe(0);
    expect(result.logs).toContain('Vercel deployment is READY');
    expect(result.output).toBe(`url=${env.DEPLOYMENT_URL}\n`);
    expect(result.args).toEqual([
      'dlx',
      'vercel@latest',
      'deploy',
      '--prebuilt',
      '--prod',
      '--no-wait',
      '--scope=team_fixture',
      '--project=prj_fixture',
    ]);
  });

  it('preserves CLI upload failure without publishing a success URL', () => {
    const result = runDeploy('READY', 42);
    expect(result.status).toBe(42);
    expect(result.output).toBe('');
    expect(result.logs).not.toContain('Vercel deployment is READY');
    expect(result.logs).not.toContain('Deployed to');
  });

  it('includes the poller in deployment detection and the required shared-lib test cache', () => {
    const pollerPath = '.github/scripts/wait-vercel-deployment.mjs';
    expect(workflow.split('\n  web:\n')[0]).toContain(`- '${pollerPath}'`);
    expect(readFileSync(join(root, 'packages/shared-lib/turbo.json'), 'utf8')).toContain(
      `$TURBO_ROOT$/${pollerPath}`,
    );
  });
});

const env = {
  DEPLOYMENT_URL: 'https://lyb-deployment.example.com',
  VERCEL_TOKEN: 'fixture-token',
  VERCEL_ORG_ID: 'team_fixture',
};

function inspector(responses: unknown[]) {
  let elapsed = 0;
  const logs: string[] = [];
  const fetchImpl = vi.fn(async () => Response.json(responses.shift()));
  const sleep = vi.fn(async (ms: number) => {
    elapsed += ms;
  });
  return {
    logs,
    options: {
      env,
      fetchImpl,
      sleep,
      now: () => elapsed,
      timeoutMs: 12_000,
      pollIntervalMs: 5_000,
      log: {
        log: (message: string) => logs.push(message),
        error: (message: string) => logs.push(message),
      },
    },
  };
}

describe('Vercel deployment state inspection', () => {
  it.each(['BLOCKED', 'ERROR', 'CANCELED'])(
    'fails immediately on %s without another request or sleep',
    async (readyState) => {
      const fixture = inspector([{ readyState }, { readyState: 'READY' }]);
      expect(await run(fixture.options)).toBe(1);
      expect(fixture.options.fetchImpl).toHaveBeenCalledTimes(1);
      expect(fixture.options.sleep).not.toHaveBeenCalled();
      expect(fixture.logs.join('\n')).toContain(readyState);
      if (readyState === 'BLOCKED') {
        expect(fixture.logs.join('\n')).toContain(
          'Tim must inspect https://vercel.com/jovie/log-your-body',
        );
      }
    },
  );

  it('waits through pending states and succeeds only when that deployment is READY', async () => {
    const fixture = inspector(
      ['INITIALIZING', 'QUEUED', 'BUILDING', 'READY'].map((readyState) => ({ readyState })),
    );
    expect(await run({ ...fixture.options, timeoutMs: 30_000 })).toBe(0);
    expect(fixture.options.sleep.mock.calls).toEqual([[5_000], [5_000], [5_000]]);
    for (const [url, options] of fixture.options.fetchImpl.mock.calls as unknown as [
      URL,
      RequestInit,
    ][]) {
      expect(String(url)).toBe(
        'https://api.vercel.com/v13/deployments/lyb-deployment.example.com?teamId=team_fixture',
      );
      expect(options.headers).toEqual({ Authorization: 'Bearer fixture-token' });
      expect(options.redirect).toBe('error');
      expect(options.signal).toBeInstanceOf(AbortSignal);
    }
  });

  it('fails on a hold encountered after queuing', async () => {
    const fixture = inspector([{ readyState: 'QUEUED' }, { readyState: 'BLOCKED' }]);
    expect(await run(fixture.options)).toBe(1);
    expect(fixture.options.fetchImpl).toHaveBeenCalledTimes(2);
    expect(fixture.options.sleep).toHaveBeenCalledTimes(1);
  });

  it('bounds pending-state polling and fails before the job cancellation timeout', async () => {
    const fixture = inspector(Array(3).fill({ readyState: 'BUILDING' }));
    expect(await run(fixture.options)).toBe(1);
    expect(fixture.options.fetchImpl).toHaveBeenCalledTimes(3);
    expect(fixture.options.sleep.mock.calls).toEqual([[5_000], [5_000], [2_000]]);
    expect(fixture.logs.join('\n')).toContain('did not reach READY within 12s');
  });

  it.each([{}, { readyState: '' }, { readyState: 'UNKNOWN' }, { state: 'READY' }, null])(
    'fails closed on a malformed or unknown deployment response %j',
    async (response) => {
      const fixture = inspector([response]);
      expect(await run(fixture.options)).toBe(1);
      expect(fixture.options.sleep).not.toHaveBeenCalled();
      expect(fixture.logs.join('\n')).toContain('readiness is unverified');
    },
  );

  it.each([401, 403, 404, 429, 500])(
    'fails closed on HTTP %s without logging API bodies',
    async (status) => {
      const fixture = inspector([]);
      const fetchImpl = async () => new Response('fixture-token', { status });
      expect(await run({ ...fixture.options, fetchImpl })).toBe(1);
      expect(fixture.logs.join('\n')).toContain(`HTTP ${status}`);
      expect(fixture.logs.join('\n')).not.toContain('fixture-token');
    },
  );

  it('fails closed on invalid JSON', async () => {
    const fixture = inspector([]);
    expect(
      await run({ ...fixture.options, fetchImpl: async () => new Response('fixture-token') }),
    ).toBe(1);
    expect(fixture.logs.join('\n')).toContain('readiness is unverified');
    expect(fixture.logs.join('\n')).not.toContain('fixture-token');
  });

  it('aborts a stalled inspection request at the readiness deadline', async () => {
    const fixture = inspector([]);
    const fetchImpl = (_url: URL, { signal }: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        signal?.addEventListener('abort', () => reject(signal.reason), { once: true });
      });
    expect(await run({ ...fixture.options, now: Date.now, timeoutMs: 25, fetchImpl })).toBe(1);
    expect(fixture.logs.join('\n')).toContain('readiness is unverified');
    expect(fixture.options.sleep).not.toHaveBeenCalled();
  });

  it.each(['Error', 'TimeoutError'])(
    'fails closed on %s without logging exception details',
    async (name) => {
      const fixture = inspector([]);
      const fetchImpl = async () => {
        throw new DOMException('fixture-token', name);
      };
      expect(await run({ ...fixture.options, fetchImpl })).toBe(1);
      expect(fixture.logs.join('\n')).toContain('readiness is unverified');
      expect(fixture.logs.join('\n')).not.toContain('fixture-token');
    },
  );

  it.each(Object.keys(env))('requires %s before any request', async (key) => {
    const fixture = inspector([]);
    expect(await run({ ...fixture.options, env: { ...env, [key]: '' } })).toBe(1);
    expect(fixture.options.fetchImpl).not.toHaveBeenCalled();
  });

  it.each([
    'garbage',
    'http://lyb-deployment.example.com',
    'https://user:fixture-token@lyb-deployment.example.com',
    'https://lyb-deployment.example.com/path',
  ])('rejects an invalid CLI deployment origin %s', async (url) => {
    const fixture = inspector([]);
    expect(await run({ ...fixture.options, env: { ...env, DEPLOYMENT_URL: url } })).toBe(1);
    expect(fixture.options.fetchImpl).not.toHaveBeenCalled();
    expect(fixture.logs.join('\n')).not.toContain('fixture-token');
  });
});
