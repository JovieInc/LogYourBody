import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { fixture as dependencyFixture } from './resolve-repository-docs-dependency.test.mjs';

for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
  for (const bit of ['assume-unchanged', 'skip-worktree']) {
    test(`dependency repair ${mode} refuses ${bit} lockfile rewrites`, (t) => {
      const f = dependencyFixture(t, '.npmrc', 'staged');
      const index = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      f.git('update-index', `--${bit}`, 'pnpm-lock.yaml');
      writeFileSync(join(f.root, 'pnpm-lock.yaml'), 'unverified resolution\n');
      assert.equal(f.git('diff', '--name-only', '--', 'pnpm-lock.yaml'), '', 'the bit hides the rewrite from git diff');
      writeFileSync(join(f.root, 'pnpm-lock.yaml'), outputs[0]);
      writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
from pathlib import Path
marker = Path('changed-once')
if not marker.exists():
    Path('pnpm-lock.yaml').write_text('unverified resolution\\n')
    marker.touch()
`, { mode: 0o755 });
      const result = f.resolve(mode);
      assert.notEqual(result.status, 0, 'hidden lockfile bytes cannot pass frozen verification');
      assert.match(result.stderr, /dependency inputs changed during verification/);
      assert.equal(f.git('ls-files', '--stage'), index);
      for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
        assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
        assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
      }
      f.git('update-index', `--no-${bit}`, 'pnpm-lock.yaml');
      const retry = f.resolve(mode);
      assert.equal(retry.status, 0, retry.stderr);
      assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), outputs[0]);
      const repairedIndex = f.git('ls-files', '--stage');
      assert.equal(f.resolve(mode).status, 0, 'reviewed frozen verification remains idempotent');
      assert.equal(f.git('ls-files', '--stage'), repairedIndex);
    });
  }
}
