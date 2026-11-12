#!/usr/bin/env node
// Dependency-only bootstrap shared by local worktrees and Codex Cloud.
import { spawnSync } from 'node:child_process';
import { readFileSync, realpathSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function bootstrap(root, env = process.env) {
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
  const install = spawnSync('pnpm', ['install', '--frozen-lockfile', '--prefer-offline'], {
    ...options,
    env: { ...env, PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD: '1' },
    stdio: 'inherit',
  });
  if (install.error) throw install.error;
  if (install.status !== 0)
    throw new Error(`pnpm install failed (${install.status ?? install.signal}).`);
}

export const CORRECTION_LEDGER_MERGE_DRIVER =
  'node scripts/correction-classifier.mjs --merge-driver %O %A %B';

export function installCorrectionLedgerMergeDriver(root, env = process.env) {
  const options = { cwd: root, env, encoding: 'utf8' };
  const probe = spawnSync('git', ['rev-parse', '--git-dir'], options);
  if (probe.status !== 0) return false;
  const config = spawnSync(
    'git',
    ['config', '--local', 'merge.correction-ledger.driver', CORRECTION_LEDGER_MERGE_DRIVER],
    options,
  );
  if (config.error) throw config.error;
  if (config.status !== 0) {
    throw new Error(
      `correction ledger merge driver was not installed (${config.status ?? config.signal}).`,
    );
  }
  return true;
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  bootstrap(root);
  installCorrectionLedgerMergeDriver(root);
}
