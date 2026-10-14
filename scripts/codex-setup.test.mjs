import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import test from 'node:test';
import { bootstrap } from './codex-setup.mjs';

function fixture(t, behavior = '') {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'jovie-codex-')));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, 'bin'));
  writeFileSync(join(root, '.nvmrc'), process.versions.node);
  writeFileSync(join(root, 'package.json'), JSON.stringify({ packageManager: 'pnpm@9.15.9' }));
  writeFileSync(join(root, 'pnpm-lock.yaml'), 'preserve lock');
  writeFileSync(join(root, '.env.local'), 'preserve environment');
  writeFileSync(
    join(root, 'bin/pnpm'),
    `#!/bin/bash
set -eu
if [[ "$*" == '--version' ]]; then
  ${behavior || "echo '9.15.9'"}
  exit 0
fi
printf '%s\\n' "$PWD" "$*" "$PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD" "\${ONNXRUNTIME_NODE_INSTALL:-unset}" > "$PWD/install-receipt"
exit "\${INSTALL_STATUS:-0}"
`,
    { mode: 0o755 },
  );
  return { root, env: { PATH: `${join(root, 'bin')}:/usr/bin:/bin` } };
}

test('installs frozen dependencies in the repository without touching environment or lockfiles', (t) => {
  const { root, env } = fixture(t);
  bootstrap(root, env);
  assert.equal(
    readFileSync(join(root, 'install-receipt'), 'utf8'),
    `${root}\ninstall --frozen-lockfile --prefer-offline\n1\nunset\n`,
  );
  assert.equal(readFileSync(join(root, '.env.local'), 'utf8'), 'preserve environment');
  assert.equal(readFileSync(join(root, 'pnpm-lock.yaml'), 'utf8'), 'preserve lock');
});

test('rejects a runtime mismatch before running the installer', (t) => {
  const { root, env } = fixture(t);
  writeFileSync(join(root, '.nvmrc'), '0.0.0');
  assert.throws(() => bootstrap(root, env), /Expected Node/);
});

test('requires an exact pnpm pin', (t) => {
  const { root, env } = fixture(t);
  for (const packageManager of [undefined, 'npm@10.0.0', 'pnpm@latest']) {
    writeFileSync(join(root, 'package.json'), JSON.stringify({ packageManager }));
    assert.throws(() => bootstrap(root, env), /exact pnpm/);
  }
});

test('fails closed on missing pnpm, wrong package manager, and failed version probe', (t) => {
  for (const behavior of ["echo '10.0.0'", 'exit 7']) {
    const { root, env } = fixture(t, behavior);
    assert.throws(() => bootstrap(root, env), /pnpm must resolve/);
  }
  const { root } = fixture(t);
  assert.throws(() => bootstrap(root, { PATH: join(root, 'missing') }), /ENOENT/);
});

test('propagates installer failures and signals', (t) => {
  const { root, env } = fixture(t);
  assert.throws(() => bootstrap(root, { ...env, INSTALL_STATUS: '42' }), /failed \(42\)/);
  writeFileSync(
    join(root, 'bin/pnpm'),
    '#!/bin/bash\nif [[ "$*" == "--version" ]]; then echo 9.15.9; else kill -TERM $$; fi\n',
    { mode: 0o755 },
  );
  assert.throws(() => bootstrap(root, env), /SIGTERM/);
});

test('reports executable disappearance between probe and install', (t) => {
  const { root, env } = fixture(t, 'echo 9.15.9; rm -- "$0"');
  assert.throws(() => bootstrap(root, env), /ENOENT/);
});

test('secret-free SessionStart uses the dependency lane and emits valid hook JSON from any cwd', (t) => {
  const { root, env } = fixture(t);
  mkdirSync(join(root, 'scripts'));
  mkdirSync(join(root, 'nested'));
  for (const name of ['codex-setup.sh', 'codex-setup.mjs'])
    copyFileSync(resolve('scripts', name), join(root, 'scripts', name));

  const result = spawnSync('bash', [join(root, 'scripts/codex-setup.sh'), '--codex-hook'], {
    cwd: join(root, 'nested'),
    encoding: 'utf8',
    input: '{}',
    env: { ...env, PATH: `${env.PATH}:${process.env.PATH}`, NVM_DIR: join(root, 'missing') },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).hookSpecificOutput.hookEventName, 'SessionStart');
  assert.match(JSON.parse(result.stdout).hookSpecificOutput.additionalContext, /secret-free/);
});

test('the CLI exits nonzero when the frozen dependency installation fails', (t) => {
  const { root, env } = fixture(t);
  mkdirSync(join(root, 'scripts'));
  copyFileSync(resolve('scripts/codex-setup.mjs'), join(root, 'scripts/codex-setup.mjs'));
  symlinkSync(root, join(root, 'linked-root'));
  const result = spawnSync(process.execPath, [join(root, 'linked-root/scripts/codex-setup.mjs')], {
    encoding: 'utf8',
    env: { ...env, INSTALL_STATUS: '42' },
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /pnpm install failed/);
});

test('desktop actions select the repository and forward arguments without reinstalling', (t) => {
  const { root, env } = fixture(t);
  mkdirSync(join(root, 'scripts'));
  mkdirSync(join(root, 'nested'));
  copyFileSync(resolve('scripts/codex-setup.sh'), join(root, 'scripts/codex-setup.sh'));
  writeFileSync(join(root, 'bin/pnpm'), '#!/bin/bash\nprintf "%s\\n" "$PWD" "$*"\n', {
    mode: 0o755,
  });
  const options = {
    cwd: join(root, 'nested'),
    encoding: 'utf8',
    env: { ...env, NVM_DIR: join(root, 'missing') },
  };
  const result = spawnSync(
    'bash',
    [join(root, 'scripts/codex-setup.sh'), '--run', 'test', '--bail'],
    options,
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `${root}\ntest --bail\n`);
  const invalid = spawnSync('bash', [join(root, 'scripts/codex-setup.sh'), '--run'], options);
  assert.equal(invalid.status, 2);
});

test('cleanup preserves dirty source, caches and Git metadata and rejects apply', (t) => {
  const { root, env } = fixture(t);
  const script = resolve('scripts/codex-cleanup.sh');
  const sentinels = ['source.txt', 'git-metadata', 'cached-build'];
  for (const name of sentinels) writeFileSync(join(root, name), 'preserve');
  for (const args of [[], ['--dry-run'], ['--codex-hook']]) {
    const result = spawnSync('bash', [script, ...args], {
      cwd: root,
      env,
      input: '{}',
      encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    if (args.includes('--codex-hook'))
      assert.deepEqual(JSON.parse(result.stdout), { continue: true });
    for (const name of sentinels) assert.equal(readFileSync(join(root, name), 'utf8'), 'preserve');
  }
  assert.equal(spawnSync('bash', [script, '--apply'], { env }).status, 2);
});
