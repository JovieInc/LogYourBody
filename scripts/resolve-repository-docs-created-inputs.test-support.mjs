import assert from 'node:assert/strict';
import { readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

export function testCreatedDependencyInput(mode, fixture) {
  test(`dependency repair ${mode} refuses an untracked workspace manifest created during verification`, (t) => {
    const f = fixture(t, '.npmrc', 'staged');
    const index = f.git('ls-files', '--stage');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    const created = join(f.root, 'packages/shared-lib/package.json');
    writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
from pathlib import Path
marker = Path('created-once')
if not marker.exists():
    target = Path('packages/shared-lib/package.json')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('{"devDependencies":{"vitest":"9.9.9"}}\\n')
    marker.touch()
`, { mode: 0o755 });
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stderr, /untracked dependency inputs: packages\/shared-lib\/package\.json/);
    assert.equal(readFileSync(created, 'utf8'), '{"devDependencies":{"vitest":"9.9.9"}}\n');
    assert.equal(f.git('ls-files', '--stage'), index);
    assert.equal(f.git('show', ':SOURCES.md').includes('9.9.9'), false);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
    }
    unlinkSync(created);
    const retry = f.resolve(mode);
    assert.equal(retry.status, 0, retry.stderr);
    assert.equal(f.git('show', ':SOURCES.md').includes('9.9.9'), false);
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'repair stays idempotent after removing the untracked manifest');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
}
