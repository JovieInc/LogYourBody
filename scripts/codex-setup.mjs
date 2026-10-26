#!/usr/bin/env node
// Dependency-only bootstrap shared by local worktrees and Codex Cloud.
import { spawnSync } from 'node:child_process';
import { readFileSync, realpathSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function bootstrap(root, env = process.env, { repairGenerated = false } = {}) {
  const pin = readFileSync(resolve(root, '.nvmrc'), 'utf8').trim();
  const pkg = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
  if (process.version !== `v${pin}`) {
    throw new Error(
      `Expected Node ${pin}; got ${process.version}. Activate the pinned runtime first.`,
    );
  }
  if (!/^pnpm@\d+\.\d+\.\d+$/u.test(pkg.packageManager ?? '')) {
    throw new Error('Expected an exact pnpm version in package.json packageManager.');
  }
  const options = { cwd: root, env, encoding: 'utf8' };
  const version = spawnSync('pnpm', ['--version'], options);
  if (version.error) throw version.error;
  if (version.status !== 0 || version.stdout.trim() !== pkg.packageManager.slice(5)) {
    throw new Error(
      `pnpm must resolve ${pkg.packageManager}; dependency install was not attempted.`,
    );
  }
  const steps = [];
  if (repairGenerated) {
    // Repair bot-generated dependency artifacts, then retain the frozen install gate.
    steps.push([
      'pnpm',
      [
        'install',
        '--lockfile-only',
        '--no-frozen-lockfile',
        '--ignore-scripts',
        '--prefer-offline',
      ],
    ]);
    steps.push(['python3', ['scripts/repository_docs.py', '--write']]);
  }
  steps.push(['pnpm', ['install', '--frozen-lockfile', '--prefer-offline']]);
  for (const [command, args] of steps) {
    const result = spawnSync(command, args, {
      ...options,
      env: { ...env, PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD: '1' },
      stdio: 'inherit',
    });
    if (result.error) throw result.error;
    if (result.status !== 0)
      throw new Error(`${command} ${args[0]} failed (${result.status ?? result.signal}).`);
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 1 || args[0] !== '--repair-generated'))
    throw new Error('Usage: codex-setup.mjs [--repair-generated]');
  bootstrap(resolve(dirname(fileURLToPath(import.meta.url)), '..'), process.env, {
    repairGenerated: args[0] === '--repair-generated',
  });
}
