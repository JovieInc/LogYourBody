import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { fixture } from './resolve-repository-docs-dependency.test.mjs';

function manifest(spec, script = 'base', extra = {}) {
  return JSON.stringify({
    name: 'fixture', scripts: { test: script }, devDependencies: { turbo: spec, typescript: '^5.9.3', ...extra },
  }, null, 2) + '\n';
}

function conflict(t, ours, theirs, base = manifest('^2.11.9'), otherConflict = false, nested = false) {
  const f = fixture(t, '.npmrc', 'staged');
  const file = (name) => join(f.root, name);
  writeFileSync(file('package.json'), base);
  if (nested) {
    mkdirSync(file('packages/ui'), { recursive: true });
    writeFileSync(file('packages/ui/package.json'), manifest('^1.0.0'));
    f.git('add', 'packages/ui/package.json');
  }
  f.git('add', 'package.json');
  f.git('commit', '-qm', 'base manifest');
  f.git('branch', 'theirs');
  writeFileSync(file('package.json'), ours);
  if (nested) writeFileSync(file('packages/ui/package.json'), manifest('^1.0.1'));
  if (otherConflict) writeFileSync(file('README.md'), 'Ours\n');
  f.git('commit', '-qam', 'ours');
  f.git('switch', '-q', 'theirs');
  writeFileSync(file('package.json'), theirs);
  if (nested) writeFileSync(file('packages/ui/package.json'), manifest('^1.0.2'));
  if (otherConflict) writeFileSync(file('README.md'), 'Theirs\n');
  f.git('commit', '-qam', 'theirs');
  f.git('switch', '-q', 'dependency');
  assert.throws(() => f.git('merge', '--no-commit', 'theirs'), { status: 1 });
  assert.match(f.git('ls-files', '-u'), /package\.json/);
  assert.equal(f.git('show', 'AUTO_MERGE:package.json'), readFileSync(file('package.json'), 'utf8'));
  writeFileSync(file('bin/corepack'), `#!/usr/bin/env python3
import sys
from pathlib import Path
with Path('pnpm-calls').open('a') as log:
    log.write(' '.join(sys.argv[1:]) + '\\n')
lock = Path('pnpm-lock.yaml')
if '--no-frozen-lockfile' in sys.argv:
    lock.write_text('resolved lock\\n')
elif lock.read_text() != 'resolved lock\\n':
    print('ERR_PNPM_OUTDATED_LOCKFILE')
    sys.exit(1)
elif Path('fail-final').exists():
    print('final frozen verification failed', file=sys.stderr)
    sys.exit(17)
elif Path('concurrent-edit').exists():
    target = Path('concurrent-path')
    Path(target.read_text() if target.exists() else 'package.json').write_text(Path('concurrent-edit').read_text())
`, { mode: 0o755 });
  const state = () => ({
    index: f.git('ls-files', '--stage'),
    manifest: readFileSync(file('package.json'), 'utf8'),
    lock: readFileSync(file('pnpm-lock.yaml'), 'utf8'),
    projection: readFileSync(file('SOURCES.md'), 'utf8'),
  });
  return { ...f, file, state };
}

function positiveFixture(t) {
  return conflict(
    t,
    manifest('^2.11.10'),
    manifest('^2.11.9', 'main', { rollup: '^4.65.0' }),
  );
}

test('dependency manifest merge keeps an adjacent addition and a one-sided change', (t) => {
  const f = positiveFixture(t);
  writeFileSync(f.file('notes.txt'), 'unrelated local notes\n');
  const result = f.resolve('--refresh-lockfile');
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const staged = JSON.parse(f.git('show', ':package.json'));
  assert.equal(staged.scripts.test, 'main');
  assert.deepEqual(staged.devDependencies, { rollup: '^4.65.0', turbo: '^2.11.10', typescript: '^5.9.3' });
  assert.match(readFileSync(f.file('package.json'), 'utf8'), /"rollup": "\^4\.65\.0",\n {4}"turbo"/);
  assert.equal(f.git('show', ':pnpm-lock.yaml'), 'resolved lock\n');
  assert.equal(f.git('ls-files', '--unmerged'), '');
  assert.match(f.git('show', ':SOURCES.md'), /"turbo": "\^2\.11\.10"/);
  assert.equal(readFileSync(f.file('notes.txt'), 'utf8'), 'unrelated local notes\n');
  assert.match(readFileSync(f.file('pnpm-calls'), 'utf8'), /--no-frozen-lockfile/);
  const repaired = f.state();
  assert.equal(f.resolve('--refresh-lockfile').status, 0, 'retry is idempotent');
  assert.deepEqual(f.state(), repaired);
});

for (const [description, base, ours, theirs, winner] of [
  ['caret patch ranges', '^2.11.9', '^2.11.10', '^2.11.11', '^2.11.11'],
  ['caret minor ranges', '^2.11.9', '^2.13.0', '^2.12.0', '^2.13.0'],
  ['zero-major caret patch ranges', '^0.11.9', '^0.11.10', '^0.11.11', '^0.11.11'],
  ['tilde patch ranges', '~2.11.9', '~2.11.10', '~2.11.11', '~2.11.11'],
  ['different caret majors', '^2.11.9', '^2.11.10', '^3.0.0'],
  ['disjoint zero-major caret ranges', '^0.11.9', '^0.11.10', '^0.12.0'],
  ['disjoint zero-minor caret patches', '^0.0.1', '^0.0.2', '^0.0.3'],
  ['disjoint tilde minor ranges', '~2.11.9', '~2.11.10', '~2.12.0'],
  ['distinct exact pins', '2.11.9', '2.11.10', '2.11.11'],
  ['different operators', '^2.11.9', '^2.11.10', '~2.11.11'],
  ['prerelease ambiguity', '^2.11.9', '^2.11.10-rc.1', '^2.11.10'],
  ['opposite upgrade directions', '^2.11.9', '^2.11.8', '^2.11.10'],
]) {
  test(`dependency manifest merge handles ${description}`, (t) => {
    const f = conflict(t, manifest(ours), manifest(theirs), manifest(base));
    const before = f.state();
    const result = f.resolve('--refresh-lockfile');
    if (winner) {
      assert.equal(result.status, 0, result.stdout + result.stderr);
      assert.equal(JSON.parse(f.git('show', ':package.json')).devDependencies.turbo, winner);
    } else {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /incompatible devDependencies\.turbo/);
      assert.equal(existsSync(f.file('pnpm-calls')), false);
      assert.deepEqual(f.state(), before);
    }
  });
}

test('dependency manifest merge keeps conflicts in verify mode', (t) => {
  const f = positiveFixture(t);
  const before = f.state();
  const result = f.resolve('--verify-lockfile');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /resolve source conflicts first: package\.json/);
  assert.equal(existsSync(f.file('pnpm-calls')), false);
  assert.deepEqual(f.state(), before);
});

test('dependency manifest merge preserves edited conflict bytes before invoking pnpm', (t) => {
  const f = positiveFixture(t);
  writeFileSync(f.file('package.json'), f.state().manifest + '\n');
  const before = f.state();
  const result = f.resolve('--refresh-lockfile');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /refuses worktree edits: package\.json/);
  assert.equal(existsSync(f.file('pnpm-calls')), false);
  assert.deepEqual(f.state(), before);
});

test('dependency manifest merge refuses unrelated source conflicts before invoking pnpm', (t) => {
  const f = conflict(t, manifest('^2.11.10'), manifest('^2.11.9', 'main', { rollup: '^4.65.0' }),
    manifest('^2.11.9'), true);
  const before = f.state();
  const result = f.resolve('--refresh-lockfile');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /resolve source conflicts first: README\.md, package\.json/);
  assert.equal(existsSync(f.file('pnpm-calls')), false);
  assert.deepEqual(f.state(), before);
});

test('dependency manifest merge restores the conflict and artifacts when frozen verification fails', (t) => {
  const f = positiveFixture(t);
  writeFileSync(f.file('fail-final'), '');
  const before = f.state();
  const result = f.resolve('--refresh-lockfile');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /final frozen verification failed/);
  assert.deepEqual(f.state(), before);
  unlinkSync(f.file('fail-final'));
  assert.equal(f.resolve('--refresh-lockfile').status, 0, 'the restored merge remains retryable');
});

test('dependency manifest merge preserves an existing index lock if staging fails', (t) => {
  const f = positiveFixture(t);
  const before = f.state();
  writeFileSync(f.file('.git/index.lock'), 'another writer\n');
  assert.notEqual(f.resolve('--refresh-lockfile').status, 0);
  assert.equal(readFileSync(f.file('.git/index.lock'), 'utf8'), 'another writer\n');
  assert.equal(existsSync(f.file('pnpm-calls')), false);
  assert.deepEqual(f.state(), before);
});

test('dependency manifest merge preserves a concurrent edit during verification', (t) => {
  const f = positiveFixture(t);
  const concurrent = manifest('^2.11.12');
  writeFileSync(f.file('concurrent-edit'), concurrent);
  const before = f.state();
  const result = f.resolve('--refresh-lockfile');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /changed during repair; review and retry/);
  assert.equal(f.state().manifest, concurrent);
  assert.equal(f.state().lock, before.lock);
  assert.equal(f.state().projection, before.projection);
  assert.equal(JSON.parse(f.git('show', ':package.json')).devDependencies.turbo, '^2.11.10');
});

for (const [phase, request] of [['staging', 1], ['rollback', 2]]) {
  test(`dependency manifest merge preserves an index-only edit before ${phase}`, (t) => {
    const f = positiveFixture(t);
    const before = f.state();
    const reviewed = manifest('^2.11.12');
    writeFileSync(f.file('stage-only.json'), reviewed);
    const staged = f.git('hash-object', '-w', 'stage-only.json').trim();
    if (phase === 'rollback') writeFileSync(f.file('fail-final'), '');
    const realGit = execFileSync('which', ['git'], { encoding: 'utf8' }).trim();
    writeFileSync(f.file('bin/git'), `#!/usr/bin/env python3
import os, subprocess, sys
from pathlib import Path
git = ${JSON.stringify(realGit)}
args = sys.argv[1:]
if args == ['rev-parse', '--path-format=absolute', '--git-path', 'index']:
    count = Path('index-probes')
    request = int(count.read_text()) + 1 if count.exists() else 1
    count.write_text(str(request))
    if request == ${request}:
        oid = ${JSON.stringify(staged)}
        edit = f"0 {'0' * len(oid)}\\tpackage.json\\0" + f"100644 {oid}\\tpackage.json\\0"
        subprocess.run([git, 'update-index', '-z', '--index-info'], input=edit.encode(), check=True)
os.execv(git, [git, *args])
`, { mode: 0o755 });
    const result = f.resolve('--refresh-lockfile');
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, /index changed; review and retry/);
    assert.equal(f.git('show', ':package.json'), reviewed);
    assert.equal(f.state().manifest, before.manifest);
    assert.equal(f.state().lock, before.lock);
    assert.equal(f.state().projection, before.projection);
    assert.equal(existsSync(f.file('.git/index.lock')), false);
  });
}

for (const changed of ['package.json', 'packages/ui/package.json']) {
  test(`dependency manifest merge restores unaffected packages when ${changed} is edited`, (t) => {
    const f = conflict(t, manifest('^2.11.10'), manifest('^2.11.9', 'main', { rollup: '^4.65.0' }),
      manifest('^2.11.9'), false, true);
    const unchanged = changed === 'package.json' ? 'packages/ui/package.json' : 'package.json';
    const initialStages = f.git('ls-files', '--stage', '--', unchanged);
    const initial = readFileSync(f.file(unchanged), 'utf8');
    const before = f.state();
    const concurrent = manifest('^2.11.12');
    writeFileSync(f.file('concurrent-path'), changed);
    writeFileSync(f.file('concurrent-edit'), concurrent);
    const result = f.resolve('--refresh-lockfile');
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, /changed during repair; review and retry/);
    assert.equal(readFileSync(f.file(changed), 'utf8'), concurrent);
    assert.equal(readFileSync(f.file(unchanged), 'utf8'), initial);
    assert.equal(f.git('ls-files', '--stage', '--', unchanged), initialStages);
    assert.equal(f.state().lock, before.lock);
    assert.equal(f.state().projection, before.projection);
  });
}
