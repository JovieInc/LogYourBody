import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const resolver = fileURLToPath(new URL('./resolve-repository-docs.py', import.meta.url));
const env = {
  ...Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_'))),
  GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null',
  GIT_AUTHOR_NAME: 'fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid',
  GIT_COMMITTER_NAME: 'fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid',
};

test('dependency PR body repair preserves prose, code meaning and existing Markdown without writing', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-dependency-body-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const input = join(directory, 'body.md');
  const original = 'Keep @unapproved and `@already`.\n```html\n<code>@example</code>\n```\n' +
    '<code>@source</code> <code>@scope</code> <code>@utility</code> <code>@property</code>\n' +
    '<code>a &lt; b &amp;&amp; c &gt; d</code>\n<code>  @scope  </code>\n';
  const expected = original.replace(/<code>(@(?:source|scope|utility|property))<\/code>/g, '`$1`')
    .replace('<code>a &lt; b &amp;&amp; c &gt; d</code>', '`a < b && c > d`')
    .replace('<code>  @scope  </code>', '`   @scope   `');
  writeFileSync(input, original);
  const index = execFileSync('git', ['ls-files', '--stage'], { encoding: 'utf8' });
  const run = (...args) => spawnSync('python3', [resolver, '--dependency-pr-body', input, ...args],
    { env, encoding: 'utf8' });
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, expected);
  assert.equal(readFileSync(input, 'utf8'), original);
  assert.equal(execFileSync('git', ['ls-files', '--stage'], { encoding: 'utf8' }), index);
  writeFileSync(input, expected);
  assert.equal(run().stdout, expected, 'repair is idempotent');
  assert.notEqual(run('--verify-lockfile').status, 0, 'metadata repair cannot mutate dependencies');
  assert.notEqual(run('--reviewed-project-sha256', 'a'.repeat(64)).status, 0);
  for (const bad of ['<code>@source\n@scope</code>', '<code>` @scope</code>',
    '<code>&#96; @scope</code>', '<code>&#10;@scope</code>', '<code><em>@scope</em></code>', '<code>@scope']) {
    writeFileSync(input, bad);
    const refused = run();
    assert.notEqual(refused.status, 0, bad);
    assert.equal(refused.stdout, '', 'refusal must not produce a partial body');
    assert.equal(readFileSync(input, 'utf8'), bad);
  }
});

function fixture(t, input, state) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-dependency-inputs-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  git('init', '-q', '-b', 'dependency');
  git('config', 'core.hooksPath', '/dev/null');
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'package.json'), '{"dependencies":{"example":"1.0.0"}}\n');
  writeFileSync(join(root, 'pnpm-lock.yaml'), 'reviewed lockfile\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [{ path: 'package.json', purpose: 'Dependencies' }], imports: [], output: 'SOURCES.md',
  }));
  execFileSync('python3', [fileURLToPath(new URL('./repository_docs.py', import.meta.url)),
    '--root', root, '--write'], { env });
  const path = join(root, input);
  mkdirSync(dirname(path), { recursive: true });
  if (state !== 'untracked') writeFileSync(path, 'reviewed input\n');
  git('add', '.');
  git('commit', '-qm', 'fixture');
  writeFileSync(path, 'local input\n');
  if (state === 'staged') git('add', input);
  mkdirSync(join(root, 'bin'));
  writeFileSync(join(root, 'bin/corepack'), '#!/bin/sh\necho "$*" >> pnpm-calls\n', { mode: 0o755 });
  const resolve = (mode) => spawnSync('python3', [resolver, '--root', root, mode], {
    env: { ...env, PATH: `${join(root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
  });
  return { root, git, path, resolve };
}

function conflictedProjection(t, sourceConflict = false) {
  const f = fixture(t, '.npmrc', 'staged');
  const generate = () => execFileSync('python3', [
    fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', f.root, '--write',
  ], { env });
  const config = JSON.parse(readFileSync(join(f.root, 'repository-docs.json'), 'utf8'));
  config.sources.unshift({ path: 'README.md', purpose: 'Reviewed instructions' });
  writeFileSync(join(f.root, 'repository-docs.json'), JSON.stringify(config));
  generate();
  f.git('add', 'repository-docs.json', 'SOURCES.md');
  f.git('commit', '-qm', 'review dependency configuration');
  f.git('branch', 'incoming');
  writeFileSync(join(f.root, 'package.json'), '{"dependencies":{"example":"2.0.0"}}\n');
  writeFileSync(join(f.root, 'pnpm-lock.yaml'), 'reviewed dependency bump\n');
  if (sourceConflict) writeFileSync(join(f.root, 'README.md'), 'Branch instructions\n');
  generate();
  f.git('add', 'package.json', 'pnpm-lock.yaml', 'README.md', 'SOURCES.md');
  f.git('commit', '-qm', 'bump dependency');
  f.git('switch', '-q', 'incoming');
  writeFileSync(join(f.root, 'README.md'), 'Incoming reviewed instructions\n');
  generate();
  f.git('add', 'README.md', 'SOURCES.md');
  f.git('commit', '-qm', 'update instructions');
  f.git('switch', '-q', 'dependency');
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: f.root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
  assert.match(f.git('ls-files', '--unmerged'), /SOURCES\.md/);
  return f;
}

for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
  for (const phase of ['verification', 'rendering']) {
    for (const [state, input] of [['untracked', '.pnpmfile.cjs'], ['ignored', 'apps/web/.npmrc']]) {
      test(`dependency repair ${mode} refuses new ${state} inputs during ${phase}`, (t) => {
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
  test(`dependency repair ${mode} rebuilds a conflicted projection after frozen verification`, (t) => {
    const f = conflictedProjection(t);
    const lockfile = readFileSync(join(f.root, 'pnpm-lock.yaml'));
    writeFileSync(join(f.root, 'README.md'), 'Unstaged instructions must survive\n');
    const result = f.resolve(mode);
    assert.equal(result.status, 0, result.stderr);
    const projection = f.git('show', ':SOURCES.md');
    const incomingHash = createHash('sha256').update('Incoming reviewed instructions\n').digest('hex');
    assert.match(projection, /"example": "2\.0\.0"/);
    assert.ok(projection.includes(incomingHash), 'projection must retain incoming staged instructions');
    assert.doesNotMatch(projection, /<<<<<<<|=======|>>>>>>>/);
    assert.equal(f.git('ls-files', '--unmerged'), '');
    assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), lockfile);
    assert.equal(readFileSync(join(f.root, 'SOURCES.md'), 'utf8'), projection);
    assert.equal(readFileSync(join(f.root, 'README.md'), 'utf8'), 'Unstaged instructions must survive\n');
    assert.match(readFileSync(join(f.root, 'pnpm-calls'), 'utf8'), /--frozen-lockfile --offline/);
    const index = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'dependency repair must be retryable after a merge');
    assert.equal(f.git('ls-files', '--stage'), index);
  });
  test(`dependency repair ${mode} retains projection conflict stages when frozen verification fails`, (t) => {
    const f = conflictedProjection(t);
    writeFileSync(join(f.root, 'bin/corepack'), '#!/bin/sh\necho frozen-check-failed >&2\nexit 17\n', { mode: 0o755 });
    const index = f.git('ls-files', '--stage');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr + result.stdout, /frozen-check-failed/);
    assert.equal(f.git('ls-files', '--stage'), index);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
    }
    writeFileSync(join(f.root, 'bin/corepack'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    assert.equal(f.resolve(mode).status, 0, 'retry must use the retained conflict and reviewed lockfile');
  });
  test(`dependency repair ${mode} refuses source conflicts before invoking pnpm`, (t) => {
    const f = conflictedProjection(t, true);
    const index = f.git('ls-files', '--stage');
    const projection = readFileSync(join(f.root, 'SOURCES.md'));
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /resolve source conflicts first: README\.md/);
    assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
    assert.equal(f.git('ls-files', '--stage'), index);
    assert.deepEqual(readFileSync(join(f.root, 'SOURCES.md')), projection);
  });
  for (const input of ['package.json', '.npmrc']) {
    test(`dependency repair ${mode} refuses unstaged ${input} changes while rendering source parity`, (t) => {
      const f = fixture(t, '.npmrc', 'staged');
      const gitBinary = execFileSync('which', ['git'], { env, encoding: 'utf8' }).trim();
      const index = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      const edited = input === 'package.json' ? '{"dependencies":{"example":"3.0.0"}}\n' : 'strict-peer-dependencies=true\n';
      writeFileSync(join(f.root, 'bin/git'), `#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
result = subprocess.run([${JSON.stringify(gitBinary)}, *sys.argv[1:]])
marker = Path('changed-once')
if sys.argv[1:] == ['show', ':package.json'] and not marker.exists():
    Path(${JSON.stringify(input)}).write_text(${JSON.stringify(edited)})
    marker.touch()
sys.exit(result.returncode)
`, { mode: 0o755 });
      const result = f.resolve(mode);
      assert.notEqual(result.status, 0, 'rendering must not authorize dependency inputs changed after verification');
      assert.match(result.stderr, /dependency inputs changed during projection generation/);
      assert.equal(f.git('ls-files', '--stage'), index);
      assert.equal(readFileSync(join(f.root, input), 'utf8'), edited);
      for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
        assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
        assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
      }
      f.git('add', input);
      const retry = f.resolve(mode);
      assert.equal(retry.status, 0, retry.stderr);
      assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), outputs[0]);
      if (input === 'package.json') assert.match(f.git('show', ':SOURCES.md'), /"example": "3\.0\.0"/);
      const repairedIndex = f.git('ls-files', '--stage');
      assert.equal(f.resolve(mode).status, 0, 'repair stays idempotent after reviewing the changed inputs');
      assert.equal(f.git('ls-files', '--stage'), repairedIndex);
    });
  }
  test(`dependency repair ${mode} refuses lockfile changes while rendering source parity`, (t) => {
    const f = fixture(t, '.npmrc', 'staged');
    const gitBinary = execFileSync('which', ['git'], { env, encoding: 'utf8' }).trim();
    const index = f.git('ls-files', '--stage');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    writeFileSync(join(f.root, 'bin/git'), `#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
result = subprocess.run([${JSON.stringify(gitBinary)}, *sys.argv[1:]])
marker = Path('changed-once')
if sys.argv[1:] == ['show', ':package.json'] and not marker.exists():
    Path('pnpm-lock.yaml').write_text('unverified resolution\\n')
    marker.touch()
sys.exit(result.returncode)
`, { mode: 0o755 });
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0, 'rendering must not authorize an unverified lockfile');
    assert.match(result.stderr, /lockfile changed during projection generation/);
    assert.equal(f.git('ls-files', '--stage'), index);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
    }
    const retry = f.resolve(mode);
    assert.equal(retry.status, 0, retry.stderr);
    assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), outputs[0]);
    assert.equal(f.git('show', ':SOURCES.md'), readFileSync(join(f.root, 'SOURCES.md'), 'utf8'));
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'repair stays idempotent after restoring the verified lockfile');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
  test(`dependency repair ${mode} refuses index changes while rendering source parity`, (t) => {
    const f = fixture(t, '.npmrc', 'staged');
    const gitBinary = execFileSync('which', ['git'], { env, encoding: 'utf8' }).trim();
    const index = f.git('ls-files', '--stage', '--', ':(exclude)package.json');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    writeFileSync(join(f.root, 'bin/git'), `#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
result = subprocess.run([${JSON.stringify(gitBinary)}, *sys.argv[1:]])
marker = Path('changed-once')
if sys.argv[1:] == ['show', ':package.json'] and not marker.exists():
    Path('package.json').write_text('{"dependencies":{"example":"3.0.0"}}\\n')
    subprocess.run([${JSON.stringify(gitBinary)}, 'add', 'package.json'], check=True)
    marker.touch()
sys.exit(result.returncode)
`, { mode: 0o755 });
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0, 'a projection must not describe an index replaced during rendering');
    assert.match(result.stderr, /source index changed during projection generation/);
    assert.equal(f.git('show', ':package.json'), '{"dependencies":{"example":"3.0.0"}}\n');
    assert.equal(f.git('ls-files', '--stage', '--', ':(exclude)package.json'), index);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
    }
    const retry = f.resolve(mode);
    assert.equal(retry.status, 0, retry.stderr);
    assert.match(f.git('show', ':SOURCES.md'), /"example": "3\.0\.0"/);
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'repair stays idempotent after rendering the reviewed index');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
  test(`dependency repair ${mode} refuses lockfile drift during frozen verification`, (t) => {
    const f = fixture(t, '.npmrc', 'staged');
    const index = f.git('ls-files', '--stage');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
from pathlib import Path
marker = Path('changed-once')
if not marker.exists():
    Path('pnpm-lock.yaml').write_text('unverified resolution\\n')
    marker.touch()
`, { mode: 0o755 });
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0, 'a successful verifier cannot authorize changed lockfile bytes');
    assert.match(result.stderr, /dependency inputs changed during verification/);
    assert.equal(f.git('ls-files', '--stage'), index);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
    }
    const retry = f.resolve(mode);
    assert.equal(retry.status, 0, retry.stderr);
    assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), outputs[0]);
    assert.equal(f.git('show', ':SOURCES.md'), readFileSync(join(f.root, 'SOURCES.md'), 'utf8'));
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'reviewed frozen verification remains idempotent');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
  for (const state of ['staged', 'unstaged']) {
    test(`dependency repair ${mode} refuses ${state} manifest changes during verification`, (t) => {
      const f = fixture(t, '.npmrc', 'staged');
      const beforeIndex = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
import subprocess
from pathlib import Path
marker = Path('changed-once')
if not marker.exists():
    Path('package.json').write_text('{"dependencies":{"example":"2.0.0"}}\\n')
    ${state === 'staged' ? "subprocess.run(['git', 'add', 'package.json'], check=True)" : '# Leave the concurrent edit unstaged.'}
    marker.touch()
`, { mode: 0o755 });
      const result = f.resolve(mode);
      assert.notEqual(result.status, 0, result.stdout);
      assert.match(result.stderr, /dependency inputs changed during verification/);
      assert.equal(readFileSync(join(f.root, 'package.json'), 'utf8'), '{"dependencies":{"example":"2.0.0"}}\n');
      assert.equal(f.git('show', ':package.json'), state === 'staged'
        ? '{"dependencies":{"example":"2.0.0"}}\n'
        : '{"dependencies":{"example":"1.0.0"}}\n');
      assert.equal(f.git('show', ':.npmrc'), 'local input\n');
      if (state === 'unstaged') assert.equal(f.git('ls-files', '--stage'), beforeIndex);
      for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
        assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
        assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
      }
      f.git('add', 'package.json');
      const retry = f.resolve(mode);
      assert.equal(retry.status, 0, retry.stderr);
      assert.match(f.git('show', ':SOURCES.md'), /"example": "2\.0\.0"/);
      const repairedIndex = f.git('ls-files', '--stage');
      assert.equal(f.resolve(mode).status, 0, 'repair remains idempotent after reviewing the concurrent change');
      assert.equal(f.git('ls-files', '--stage'), repairedIndex);
    });
  }
  for (const input of ['.pnpmfile.cjs', 'apps/web/.npmrc', 'patches/example.patch', 'apps/local-only/package.json']) {
    test(`dependency repair ${mode} refuses ignored ${input} before invoking pnpm`, (t) => {
      const f = fixture(t, input, 'untracked');
      writeFileSync(join(f.root, '.gitignore'), `${input}\nnode_modules/\n.next/\n`);
      f.git('add', '.gitignore');
      for (const generated of ['apps/web/.next/package.json', 'apps/web/.next/types/package.json']) {
        mkdirSync(dirname(join(f.root, generated)), { recursive: true });
        writeFileSync(join(f.root, generated), '{"type":"commonjs"}\n');
      }
      mkdirSync(join(f.root, 'node_modules/example'), { recursive: true });
      writeFileSync(join(f.root, 'node_modules/example/.npmrc'), 'vendor config\n');
      writeFileSync(join(f.root, 'node_modules/example/package.json'), '{"name":"vendor"}\n');
      const index = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      const result = f.resolve(mode);
      assert.notEqual(result.status, 0, result.stdout);
      assert.match(result.stderr, /ignored dependency inputs:/);
      assert.ok(result.stderr.includes(input), result.stderr);
      assert.equal(result.stderr.includes('node_modules/'), false, result.stderr);
      assert.equal(result.stderr.includes('.next/'), false, result.stderr);
      assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
      assert.equal(f.git('ls-files', '--stage'), index);
      assert.equal(readFileSync(f.path, 'utf8'), 'local input\n');
      for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
        assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      }
      unlinkSync(f.path);
      const retry = f.resolve(mode);
      assert.equal(retry.status, 0, retry.stderr);
      const repairedIndex = f.git('ls-files', '--stage');
      assert.equal(f.resolve(mode).status, 0, 'repair stays idempotent with ignored vendor config');
      assert.equal(f.git('ls-files', '--stage'), repairedIndex);
      assert.equal(readFileSync(join(f.root, 'apps/web/.next/package.json'), 'utf8'), '{"type":"commonjs"}\n');
    });
  }
  test(`dependency repair ${mode} requires staged projection configuration before invoking pnpm`, (t) => {
    const f = fixture(t, '.npmrc', 'staged');
    const configPath = join(f.root, 'repository-docs.json');
    const config = JSON.parse(readFileSync(configPath, 'utf8'));
    config.repository = 'reviewed/dependency-update';
    writeFileSync(configPath, JSON.stringify(config));
    const index = f.git('ls-files', '--stage');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, /unstaged dependency edits: repository-docs\.json/);
    assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
    assert.equal(f.git('ls-files', '--stage'), index);
    assert.deepEqual(JSON.parse(readFileSync(configPath, 'utf8')), config);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
    }
    f.git('add', 'repository-docs.json');
    const retry = f.resolve(mode);
    assert.equal(retry.status, 0, retry.stderr);
    assert.match(f.git('show', ':SOURCES.md'), /Repository: `reviewed\/dependency-update`/);
    assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), outputs[0]);
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'repair with reviewed configuration stays idempotent');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
  for (const input of ['.pnpmfile.cjs', 'apps/web/.npmrc', 'patches/example.patch']) {
    test(`dependency repair ${mode} refuses indexed symlink ${input} before invoking pnpm`, (t) => {
      const f = fixture(t, input, 'staged');
      const external = mkdtempSync(join(tmpdir(), 'lyb-external-dependency-'));
      t.after(() => rmSync(external, { recursive: true, force: true }));
      const target = join(external, 'input');
      writeFileSync(target, 'unreviewed external input\n');
      unlinkSync(f.path);
      symlinkSync(target, f.path);
      f.git('add', input);
      const index = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      const result = f.resolve(mode);
      assert.notEqual(result.status, 0, result.stdout);
      assert.match(result.stderr, /dependency input must be a regular indexed file:/);
      assert.ok(result.stderr.includes(input), result.stderr);
      assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
      assert.equal(f.git('ls-files', '--stage'), index);
      assert.equal(readFileSync(target, 'utf8'), 'unreviewed external input\n');
      for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
        assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      }
    });
  }
  test(`dependency repair ${mode} accepts an executable indexed hook`, (t) => {
    const f = fixture(t, '.pnpmfile.cjs', 'staged');
    chmodSync(f.path, 0o755);
    f.git('add', '.pnpmfile.cjs');
    const result = f.resolve(mode);
    assert.equal(result.status, 0, result.stderr);
    assert.match(f.git('ls-files', '--stage', '.pnpmfile.cjs'), /^100755 /);
    assert.match(readFileSync(join(f.root, 'pnpm-calls'), 'utf8'), /--frozen-lockfile --offline/);
  });
  for (const input of ['.pnpmfile.cjs', 'apps/web/.npmrc', 'patches/example.patch']) {
    for (const state of ['untracked', 'unstaged']) {
      test(`dependency repair ${mode} refuses ${state} ${input} before invoking pnpm`, (t) => {
        const f = fixture(t, input, state);
        const index = f.git('ls-files', '--stage');
        const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
        const result = f.resolve(mode);
        assert.notEqual(result.status, 0, result.stdout);
        assert.match(result.stderr, new RegExp(`${state} dependency (?:inputs|edits):`));
        assert.ok(result.stderr.includes(input), result.stderr);
        assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
        assert.equal(f.git('ls-files', '--stage'), index);
        assert.equal(readFileSync(f.path, 'utf8'), 'local input\n');
        for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
          assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
        }
      });
    }
    test(`dependency repair ${mode} accepts staged ${input} and preserves unrelated edits`, (t) => {
      const f = fixture(t, input, 'staged');
      writeFileSync(join(f.root, 'notes.txt'), 'unrelated local notes\n');
      const result = f.resolve(mode);
      assert.equal(result.status, 0, result.stderr);
      assert.match(readFileSync(join(f.root, 'pnpm-calls'), 'utf8'), /pnpm install .*--frozen-lockfile --offline/);
      assert.equal(f.git('show', `:${input}`), 'local input\n');
      assert.equal(readFileSync(join(f.root, 'notes.txt'), 'utf8'), 'unrelated local notes\n');
      assert.equal(f.git('show', ':SOURCES.md'), readFileSync(join(f.root, 'SOURCES.md'), 'utf8'));
    });
  }
}
