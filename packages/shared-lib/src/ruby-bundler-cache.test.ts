import { spawnSync, execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

type Step = { name: string; if?: string; run?: string; uses?: string };
const actionPath = fileURLToPath(
  new URL('../../../.github/actions/setup-ruby-bundler/action.yml', import.meta.url),
);
const steps: Step[] = JSON.parse(
  execFileSync(
    'ruby',
    [
      '-ryaml',
      '-rjson',
      '-e',
      'puts JSON.generate(YAML.load_file(ARGV[0])["runs"]["steps"])',
      actionPath,
    ],
    { encoding: 'utf8' },
  ),
);

// Execute the action's real shell steps; only the cache service and bundle CLI are fixtures.
function runSetup(
  environment: string,
  cacheHit: boolean,
  staleBundle: boolean,
  installFails = false,
) {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-ruby-cache-'));
  const bundleDirectory = join(directory, 'vendor/bundle');
  const staleExtension = join(bundleDirectory, 'date_core.bundle');
  const commands = join(directory, 'commands');
  mkdirSync(bundleDirectory, { recursive: true });
  mkdirSync(join(directory, 'vendor/JovieKit'));
  writeFileSync(join(directory, 'vendor/JovieKit/Package.swift'), 'retained package');
  writeFileSync(commands, '');
  if (staleBundle) writeFileSync(staleExtension, 'incompatible Ruby extension');
  mkdirSync(join(directory, 'bin'));
  writeFileSync(
    join(directory, 'bin/bundle'),
    `#!/bin/bash
set -eu
echo "$*" >> "$COMMANDS"
if [[ -f vendor/bundle/date_core.bundle ]]; then
  echo 'LoadError: date_core.bundle: Symbol not found: _rb_cFalseClass' >&2
  exit 1
fi
if [[ "$1" == install && "$INSTALL_FAILS" == true ]]; then exit 2; fi
`,
    { mode: 0o755 },
  );
  let restored = false;
  let status = 0;
  let error = '';
  try {
    for (const step of steps) {
      if (
        ![
          'Reset native gems on self-hosted Macs',
          'Cache Ruby dependencies',
          'Install dependencies',
          'Update bundle if cache hit',
        ].includes(step.name)
      )
        continue;
      const condition = step.if;
      const enabled =
        condition === undefined ||
        {
          "runner.environment == 'self-hosted'": environment === 'self-hosted',
          "runner.environment == 'github-hosted'": environment === 'github-hosted',
          "steps.bundler-cache.outputs.cache-hit != 'true'": !restored,
          "steps.bundler-cache.outputs.cache-hit == 'true'": restored,
        }[condition];
      if (enabled === undefined) throw new Error(`Unhandled action condition: ${condition}`);
      if (!enabled) continue;
      if (step.uses?.startsWith('actions/cache@')) {
        restored = cacheHit;
        if (restored && environment === 'self-hosted') {
          mkdirSync(bundleDirectory, { recursive: true });
          writeFileSync(staleExtension, 'incompatible cached extension');
        }
      } else {
        const result = spawnSync('bash', ['-e', '-o', 'pipefail', '-c', step.run!], {
          cwd: directory,
          encoding: 'utf8',
          env: {
            ...process.env,
            PATH: `${join(directory, 'bin')}:${process.env.PATH}`,
            COMMANDS: commands,
            INSTALL_FAILS: String(installFails),
          },
        });
        status = result.status ?? 1;
        error += result.stderr;
        if (status !== 0) break;
      }
    }
    return {
      status,
      error,
      restored,
      commands: readFileSync(commands, 'utf8').trim().split('\n'),
      staleExtension: existsSync(staleExtension),
      packageSource: readFileSync(join(directory, 'vendor/JovieKit/Package.swift'), 'utf8'),
    };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

it.each([false, true])(
  'rebuilds self-hosted native gems without restoring incompatible cache (stale workspace: %s)',
  (stale) => {
    const result = runSetup('self-hosted', true, stale);
    expect(result.status, result.error).toBe(0);
    expect(result.restored).toBe(false);
    expect(result.staleExtension).toBe(false);
    expect(result.commands).toEqual(['install']);
    expect(result.packageSource).toBe('retained package');
  },
);

it('retains hosted cache hits and verifies the bundle', () => {
  const result = runSetup('github-hosted', true, false);
  expect(result.status).toBe(0);
  expect(result.restored).toBe(true);
  expect(result.commands).toEqual(['check']);
});

it('installs dependencies on a hosted cache miss', () => {
  const result = runSetup('github-hosted', false, false);
  expect(result.status).toBe(0);
  expect(result.commands).toEqual(['install']);
});

it('propagates dependency installation failures on self-hosted Macs', () => {
  expect(runSetup('self-hosted', true, true, true).status).toBe(2);
});
