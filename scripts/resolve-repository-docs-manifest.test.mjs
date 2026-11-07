import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { env, manifestRepo, resolver, sourceMapFixture } from './resolve-repository-docs.test.mjs';

function autoMergedManifests(t) {
  const fixture = manifestRepo(t);
  fixture.git('switch', '-qc', 'incoming');
  fixture.commit(
    'node --test shared.test.mjs',
    ['$TURBO_DEFAULT$', 'shared.mjs', 'theirs.mjs', 'workflow.yml', 'workflow.yml'],
    'incoming',
  );
  fixture.git('switch', '-q', 'feature');
  fixture.commit(
    'node --test shared.test.mjs',
    ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs'],
    'ours',
  );
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], {
    cwd: fixture.root, env, encoding: 'utf8',
  });
  assert.equal(merge.status, 1, merge.stderr);
  const unmerged = fixture.git('diff', '--name-only', '--diff-filter=U');
  assert.doesNotMatch(unmerged, /turbo\.json/);
  assert.match(unmerged, /REPOSITORY_SOURCES\.md/);
  const run = (flag = '--staged') => spawnSync('python3', [resolver, '--root', fixture.root, flag], {
    env, encoding: 'utf8',
  });
  return { ...fixture, run };
}

test('auto-merged manifest refuses a dropped parent turbo input', (t) => {
  const fixture = autoMergedManifests(t);
  const turbo = JSON.parse(readFileSync(join(fixture.root, fixture.turbo), 'utf8'));
  turbo.tasks.test.inputs = turbo.tasks.test.inputs.filter((item) => item !== 'theirs.mjs');
  writeFileSync(join(fixture.root, fixture.turbo), `${JSON.stringify(turbo, null, 2)}\n`);
  fixture.git('add', fixture.turbo);
  const before = readFileSync(join(fixture.root, fixture.output), 'utf8');
  const index = fixture.git('ls-files', '--stage');
  const result = fixture.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /additive manifest union keeps every parent test input/);
  assert.equal(readFileSync(join(fixture.root, fixture.output), 'utf8'), before);
  assert.equal(fixture.git('ls-files', '--stage'), index);
});

test('auto-merged manifest keeps both parent inputs and ignores dirty worktree bytes', (t) => {
  const fixture = autoMergedManifests(t);
  const merged = readFileSync(join(fixture.root, fixture.turbo), 'utf8');
  assert.match(merged, /theirs\.mjs/);
  assert.match(merged, /ours\.mjs/);
  writeFileSync(join(fixture.root, fixture.turbo), 'DIRTY\n');
  const result = fixture.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(join(fixture.root, fixture.turbo), 'utf8'), 'DIRTY\n');
  assert.match(fixture.git('show', `:${fixture.turbo}`), /theirs\.mjs/);
  assert.match(fixture.git('show', `:${fixture.turbo}`), /ours\.mjs/);
  const projection = fixture.git('show', `:${fixture.output}`);
  const turboDigest = createHash('sha256').update(fixture.git('show', `:${fixture.turbo}`)).digest('hex');
  assert.equal(projection.includes('<<<<<<<'), false);
  assert.match(projection, new RegExp(turboDigest));
  assert.equal(fixture.git('ls-files', '--unmerged'), '');
});

for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
  test(`dependency repair ${mode} fingerprints staged sources and preserves valid lockfile resolutions`, (t) => {
    const f = sourceMapFixture(t);
    writeFileSync(join(f.root, 'package.json'), JSON.stringify({ dependencies: { example: '1.0.0' } }));
    writeFileSync(join(f.root, 'pnpm-lock.yaml'), 'reviewed bot resolutions\n');
    const config = JSON.parse(readFileSync(join(f.root, 'repository-docs.json'), 'utf8'));
    config.sources.push({ path: 'package.json', purpose: 'Dependencies' });
    writeFileSync(join(f.root, 'repository-docs.json'), JSON.stringify(config));
    f.generate();
    f.commit();
    writeFileSync(join(f.root, 'package.json'), JSON.stringify({ dependencies: { example: '1.0.1' } }));
    f.git('add', 'package.json');
    writeFileSync(join(f.root, 'a.txt'), 'Unstaged source bytes\n');
    mkdirSync(join(f.root, 'bin'));
    writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
import sys
from pathlib import Path
assert sys.argv[1:] == ['pnpm', 'install', '--lockfile-only', '--ignore-scripts', '--frozen-lockfile', '--offline']
assert Path('pnpm-lock.yaml').read_text() == 'reviewed bot resolutions\\n'
`, { mode: 0o755 });
    const resolve = () => spawnSync('python3', [resolver, '--root', f.root, mode], {
      env: { ...env, PATH: `${join(f.root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
    });
    const result = resolve();
    assert.equal(result.status, 0, result.stderr);
    const projection = f.git('show', `:${f.output}`);
    const digest = (text) => createHash('sha256').update(text).digest('hex');
    assert.match(projection, new RegExp(digest('base-a\n')));
    assert.doesNotMatch(projection, new RegExp(digest('Unstaged source bytes\n')));
    assert.match(projection, /"example": "1\.0\.1"/);
    assert.equal(readFileSync(join(f.root, 'a.txt'), 'utf8'), 'Unstaged source bytes\n');
    assert.equal(f.git('show', ':a.txt'), 'base-a\n');
    assert.equal(readFileSync(join(f.root, 'pnpm-lock.yaml'), 'utf8'), 'reviewed bot resolutions\n');
    assert.deepEqual(f.git('diff', '--cached', '--name-only').trim().split('\n').sort(), [f.output, 'package.json'].sort());
    const index = f.git('ls-files', '--stage');
    assert.equal(resolve().status, 0, 'dependency repair is retryable with unstaged source edits');
    assert.equal(f.git('ls-files', '--stage'), index);
  });
}

function mergedDependencyProjection(t) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-merged-dependency-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  const output = 'SOURCES.md';
  const manifest = (left, right) => `${JSON.stringify({
    dependencies: {
      left, s1: 'keep', s2: 'keep', s3: 'keep', s4: 'keep', s5: 'keep', right,
    },
  }, null, 2)}\n`;
  const lock = (left, right) => `left: ${left}\ns1: keep\ns2: keep\ns3: keep\ns4: keep\ns5: keep\nright: ${right}\n`;
  git('init', '-q', '-b', 'ours');
  git('config', 'core.hooksPath', '/dev/null');
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1,
    repository: 'example/app',
    entrypoints: ['README.md'],
    sources: [
      { path: 'package.json', purpose: 'Dependencies' },
      { path: 'a.txt', purpose: 'First fingerprint' },
      { path: 'b.txt', purpose: 'Second fingerprint' },
    ],
    imports: [],
    output,
  }));
  writeFileSync(join(root, 'package.json'), manifest('1', '1'));
  writeFileSync(join(root, 'pnpm-lock.yaml'), lock('1', '1'));
  writeFileSync(join(root, 'a.txt'), 'base-a\n');
  writeFileSync(join(root, 'b.txt'), 'base-b\n');
  const generate = () => execFileSync('python3', [
    fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
  ], { env });
  const commit = () => {
    git('add', '-A');
    git('commit', '-qm', 'fixture');
  };
  generate();
  commit();
  git('branch', 'theirs');
  git('switch', '-q', 'theirs');
  writeFileSync(join(root, 'package.json'), manifest('1', '3'));
  writeFileSync(join(root, 'pnpm-lock.yaml'), lock('1', '3'));
  writeFileSync(join(root, 'b.txt'), 'theirs-b\n');
  generate();
  commit();
  git('switch', '-q', 'ours');
  writeFileSync(join(root, 'package.json'), manifest('2', '1'));
  writeFileSync(join(root, 'pnpm-lock.yaml'), lock('2', '1'));
  writeFileSync(join(root, 'a.txt'), 'ours-a\n');
  generate();
  commit();
  const merge = spawnSync('git', ['merge', '--no-commit', 'theirs'], { cwd: root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
  assert.equal(git('diff', '--name-only', '--diff-filter=U').trim(), output);
  assert.equal(readFileSync(join(root, 'package.json'), 'utf8'), manifest('2', '3'));
  assert.equal(readFileSync(join(root, 'pnpm-lock.yaml'), 'utf8'), lock('2', '3'));
  writeFileSync(join(root, 'a.txt'), 'DIRTY\n');
  writeFileSync(join(root, 'notes.txt'), 'unrelated local notes\n');
  mkdirSync(join(root, 'bin'));
  writeFileSync(join(root, 'bin/corepack'), `#!/usr/bin/env python3
import sys
from pathlib import Path
Path('pnpm-calls').open('a').write(' '.join(sys.argv[1:]) + '\\n')
text = Path('pnpm-lock.yaml').read_text()
if '<<<<<<' in text:
    print('ERR_PNPM_LOCKFILE_CONFLICT_MARKERS')
    sys.exit(1)
if text != 'left: 2\\ns1: keep\\ns2: keep\\ns3: keep\\ns4: keep\\ns5: keep\\nright: 3\\n':
    print('ERR_PNPM_OUTDATED_LOCKFILE')
    sys.exit(1)
if '--no-frozen-lockfile' in sys.argv:
    Path('pnpm-lock.yaml').write_text('rewritten lock\\n')
`, { mode: 0o755 });
  const resolve = (mode) => spawnSync('python3', [resolver, '--root', root, mode], {
    env: { ...env, PATH: `${join(root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
  });
  return { root, git, output, resolve, lock: lock('2', '3') };
}

for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
  test(`dependency repair ${mode} rebuilds an unmerged projection without rewriting a merged lockfile`, (t) => {
    const f = mergedDependencyProjection(t);
    const result = f.resolve(mode);
    assert.equal(result.status, 0, result.stderr);
    const projection = f.git('show', `:${f.output}`);
    const digest = (text) => createHash('sha256').update(text).digest('hex');
    assert.equal(projection.includes('<<<<<<<'), false);
    assert.match(projection, /"left": "2"/);
    assert.match(projection, /"right": "3"/);
    assert.match(projection, new RegExp(digest('ours-a\n')));
    assert.match(projection, new RegExp(digest('theirs-b\n')));
    assert.doesNotMatch(projection, new RegExp(digest('DIRTY\n')));
    assert.equal(readFileSync(join(f.root, 'a.txt'), 'utf8'), 'DIRTY\n');
    assert.equal(f.git('show', ':a.txt'), 'ours-a\n');
    assert.equal(readFileSync(join(f.root, 'pnpm-lock.yaml'), 'utf8'), f.lock);
    assert.equal(f.git('show', ':pnpm-lock.yaml'), f.lock);
    assert.equal(readFileSync(join(f.root, 'notes.txt'), 'utf8'), 'unrelated local notes\n');
    assert.equal(f.git('ls-files', '--unmerged'), '');
    assert.match(readFileSync(join(f.root, 'pnpm-calls'), 'utf8'), /--frozen-lockfile --offline/);
    assert.doesNotMatch(readFileSync(join(f.root, 'pnpm-calls'), 'utf8'), /--no-frozen-lockfile/);
    const index = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'merged dependency repair stays idempotent');
    assert.equal(f.git('ls-files', '--stage'), index);
  });
}

test('dependency repair still refuses a resolved unstaged projection edit', (t) => {
  const f = sourceMapFixture(t);
  writeFileSync(join(f.root, 'package.json'), '{"dependencies":{"example":"1.0.0"}}\n');
  writeFileSync(join(f.root, 'pnpm-lock.yaml'), 'reviewed lock\n');
  const config = JSON.parse(readFileSync(join(f.root, 'repository-docs.json'), 'utf8'));
  config.sources.push({ path: 'package.json', purpose: 'Dependencies' });
  writeFileSync(join(f.root, 'repository-docs.json'), JSON.stringify(config));
  f.generate();
  f.commit();
  writeFileSync(join(f.root, f.output), 'local projection edit\n');
  mkdirSync(join(f.root, 'bin'));
  writeFileSync(join(f.root, 'bin/corepack'), '#!/bin/sh\necho "$*" >> pnpm-calls\n', { mode: 0o755 });
  const index = f.git('ls-files', '--stage');
  const result = spawnSync('python3', [resolver, '--root', f.root, '--verify-lockfile'], {
    env: { ...env, PATH: `${join(f.root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unstaged dependency edits: SOURCES\.md/);
  assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
  assert.equal(readFileSync(join(f.root, f.output), 'utf8'), 'local projection edit\n');
  assert.equal(f.git('ls-files', '--stage'), index);
});
