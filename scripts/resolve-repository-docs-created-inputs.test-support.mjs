import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
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

export function testLateDependencyInputs(mode, fixture, env) {
  const dependencyInputs = [
    '.pnpmfile.cjs',
    'apps/web/.npmrc',
    'patches/example.patch',
    'apps/local/package.json',
  ];
  const cases = ['untracked', 'ignored'].flatMap((state) =>
    dependencyInputs.map((input) => [state, input]));
  cases.push(['ignored', 'pnpm-workspace.yaml']);

  for (const phase of ['verification', 'rendering']) {
    for (const [state, input] of cases) {
      test(`dependency repair ${mode} refuses new ${state} ${input} inputs during ${phase}`, (t) => {
        const f = fixture(t, '.npmrc', 'staged');
        if (state === 'ignored') {
          writeFileSync(join(f.root, '.gitignore'), `${input}\n`);
          f.git('add', '.gitignore');
        }
        writeFileSync(join(f.root, 'package.json'), '{"dependencies":{"example":"2.0.0"}}\n');
        f.git('add', 'package.json');
        const index = f.git('ls-files', '--stage');
        const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
        const gitBinary = execFileSync('which', ['git'], { env, encoding: 'utf8' }).trim();
        writeFileSync(join(f.root, 'bin', phase === 'verification' ? 'corepack' : 'git'), `#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
result = ${phase === 'rendering' ? `subprocess.run([${JSON.stringify(gitBinary)}, *sys.argv[1:]]).returncode` : '0'}
marker = Path('changed-once')
if not marker.exists() and ${phase === 'rendering' ? "sys.argv[1:] == ['show', ':package.json']" : 'True'}:
    target = Path(${JSON.stringify(input)})
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('unreviewed resolver input\\n')
    marker.touch()
sys.exit(result)
`, { mode: 0o755 });
        const result = f.resolve(mode);
        assert.notEqual(result.status, 0, 'new local resolver inputs must invalidate dependency verification');
        assert.ok(result.stderr.includes(`${state} dependency inputs: ${input}`), result.stderr);
        assert.equal(f.git('ls-files', '--stage'), index);
        assert.equal(readFileSync(join(f.root, input), 'utf8'), 'unreviewed resolver input\n');
        for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
          assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
          assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
        }
        unlinkSync(join(f.root, input));
        const retry = f.resolve(mode);
        assert.equal(retry.status, 0, retry.stderr);
        assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), outputs[0]);
        assert.match(f.git('show', ':SOURCES.md'), /"example": "2\.0\.0"/);
        const repairedIndex = f.git('ls-files', '--stage');
        assert.equal(f.resolve(mode).status, 0, 'the reviewed dependency repair remains idempotent');
        assert.equal(f.git('ls-files', '--stage'), repairedIndex);
      });
    }
  }
}
