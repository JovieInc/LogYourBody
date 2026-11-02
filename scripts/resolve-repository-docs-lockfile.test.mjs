import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { env, resolver } from './resolve-repository-docs.test.mjs';

function dependencyFixture(t, outdated) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-frozen-lockfile-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  git('init', '-q', '-b', 'dependency');
  git('config', 'core.hooksPath', '/dev/null');
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'package.json'), JSON.stringify({ dependencies: { example: '1.0.0' } }));
  writeFileSync(join(root, 'pnpm-lock.yaml'), outdated ? 'old lock\n' : 'resolved lock\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [{ path: 'package.json', purpose: 'Dependencies' }], imports: [], output: 'SOURCES.md',
  }));
  const generator = fileURLToPath(new URL('./repository_docs.py', import.meta.url));
  execFileSync('python3', [generator, '--root', root, '--write'], { env });
  git('add', '.');
  git('commit', '-qm', 'fixture');
  writeFileSync(join(root, 'package.json'), JSON.stringify({ dependencies: { example: '1.0.1' } }));
  git('add', 'package.json');
  writeFileSync(join(root, 'README.md'), 'Unstaged instructions\n');
  const bin = join(root, 'bin');
  mkdirSync(bin);
  writeFileSync(join(bin, 'corepack'), `#!/usr/bin/env python3
import os, sys
from pathlib import Path
lock = Path('pnpm-lock.yaml')
if '--no-frozen-lockfile' in sys.argv:
    lock.write_text('resolved lock\\n')
elif lock.read_text() != 'resolved lock\\n':
    print('ERR_PNPM_OUTDATED_LOCKFILE')
    sys.exit(1)
elif os.environ.get('MUTATE_FROZEN') == 'rewrite':
    lock.write_text('unexpected resolution\\n')
elif os.environ.get('MUTATE_FROZEN') == 'remove':
    lock.unlink()
`, { mode: 0o755 });
  const run = (mode, mutation) => spawnSync('python3', [resolver, '--root', root, mode], {
    env: { ...env, PATH: `${bin}:${env.PATH}`, MUTATE_FROZEN: mutation ?? '' }, encoding: 'utf8',
  });
  return { root, git, run, generator };
}

for (const [mode, outdated] of [
  ['--verify-lockfile', false],
  ['--refresh-lockfile', false],
  ['--refresh-lockfile', true],
]) {
  for (const mutation of ['rewrite', 'remove']) {
    test(`dependency ${mode} refuses a successful frozen ${mutation} (${outdated ? 'outdated' : 'valid'} lockfile)`, (t) => {
      const f = dependencyFixture(t, outdated);
      const lockfile = join(f.root, 'pnpm-lock.yaml');
      const projection = join(f.root, 'SOURCES.md');
      const lock = readFileSync(lockfile);
      const before = readFileSync(projection);
      const index = f.git('ls-files', '--stage');
      const refused = f.run(mode, mutation);
      assert.notEqual(refused.status, 0, 'frozen verification must reject lockfile mutation');
      assert.match(refused.stderr, /frozen verification changed pnpm-lock\.yaml/);
      assert.deepEqual(readFileSync(lockfile), lock, 'refusal restores the original resolutions');
      assert.deepEqual(readFileSync(projection), before);
      assert.equal(f.git('ls-files', '--stage'), index);
      assert.equal(readFileSync(join(f.root, 'README.md'), 'utf8'), 'Unstaged instructions\n');

      const retry = f.run(mode);
      assert.equal(retry.status, 0, retry.stderr);
      assert.equal(readFileSync(lockfile, 'utf8'), 'resolved lock\n');
      assert.match(f.git('show', ':SOURCES.md'), /"example": "1\.0\.1"/);
      assert.equal(f.git('show', ':pnpm-lock.yaml'), 'resolved lock\n');
      execFileSync('python3', [f.generator, '--root', f.root], { env });
      const repairedIndex = f.git('ls-files', '--stage');
      assert.equal(f.run(mode).status, 0, 'retry remains idempotent');
      assert.equal(f.git('ls-files', '--stage'), repairedIndex);
    });
  }
}
