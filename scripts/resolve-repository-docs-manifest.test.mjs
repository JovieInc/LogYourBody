import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { env, manifestRepo, resolver, sourceMapFixture } from './resolve-repository-docs.test.mjs';

function workflowBump(t) {
  const fixture = sourceMapFixture(t);
  const workflow = '.github/workflows/ci.yml';
  const original = 'jobs:\n  audit:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: swift-actions/setup-swift@7ca6abe6b3b0e8b5421b88be48feee39cbf52c6a # v2.4.0\n';
  const updated = original.replace(
    '7ca6abe6b3b0e8b5421b88be48feee39cbf52c6a # v2.4.0',
    '364295d9c23900ce04d4e5cc708387921b4e50f9 # v3',
  );
  mkdirSync(join(fixture.root, dirname(workflow)), { recursive: true });
  writeFileSync(join(fixture.root, workflow), original);
  const registry = JSON.parse(readFileSync(join(fixture.root, 'repository-docs.json'), 'utf8'));
  registry.sources = [{ path: workflow, purpose: 'CI dependencies' }];
  writeFileSync(join(fixture.root, 'repository-docs.json'), JSON.stringify(registry));
  fixture.generate();
  fixture.commit();
  // Dependabot commits the workflow outside local hooks, leaving a clean but stale map.
  writeFileSync(join(fixture.root, workflow), updated);
  fixture.git('add', workflow);
  fixture.git('commit', '-qm', 'ci(deps): bump setup-swift');
  const run = (script) => spawnSync('python3', [script, '--root', fixture.root], { env, encoding: 'utf8' });
  const check = () => run(join(dirname(resolver), 'repository_docs.py'));
  const stale = check();
  assert.equal(stale.status, 1, stale.stderr);
  assert.match(stale.stdout, /source projection stale: SOURCES\.md/);
  return { ...fixture, workflow, updated, check, repair: () => run(resolver) };
}

for (const dirty of [false, true]) {
  test(`workflow-only bot repair fingerprints indexed action pins (dirty workflow: ${dirty})`, (t) => {
    const f = workflowBump(t);
    const working = f.updated + (dirty ? '# Unstaged local workflow edit\n' : '');
    writeFileSync(join(f.root, f.workflow), working);
    const repaired = f.repair();
    assert.equal(repaired.status, 0, repaired.stderr);
    const projection = f.git('show', `:${f.output}`);
    const digest = createHash('sha256').update(f.updated).digest('hex');
    assert.match(projection, new RegExp(digest));
    assert.equal(f.git('show', `:${f.workflow}`), f.updated);
    assert.equal(readFileSync(join(f.root, f.workflow), 'utf8'), working);
    assert.equal(f.git('diff', '--cached', '--name-only').trim(), f.output);
    if (!dirty) assert.equal(f.check().status, 0);
    const index = f.git('ls-files', '--stage');
    assert.equal(f.repair().status, 0, 'repair remains idempotent');
    assert.equal(f.git('ls-files', '--stage'), index);
  });
}

test('workflow-only bot repair refuses unstaged projection edits without changing files or index', (t) => {
  const f = workflowBump(t);
  const local = 'Local projection edits\n';
  writeFileSync(join(f.root, f.output), local);
  const index = f.git('ls-files', '--stage');
  const result = f.repair();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unstaged projection edits/);
  assert.equal(readFileSync(join(f.root, f.output), 'utf8'), local);
  assert.equal(f.git('ls-files', '--stage'), index);
});

test('workflow-only bot repair restores the stale projection when staging fails', (t) => {
  const f = workflowBump(t);
  const projection = readFileSync(join(f.root, f.output), 'utf8');
  const index = f.git('ls-files', '--stage');
  const lock = join(f.root, f.git('rev-parse', '--git-path', 'index.lock').trim());
  writeFileSync(lock, 'another Git writer\n');
  const result = f.repair();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /index\.lock/);
  assert.equal(readFileSync(join(f.root, f.output), 'utf8'), projection);
  assert.equal(readFileSync(lock, 'utf8'), 'another Git writer\n');
  assert.equal(f.git('ls-files', '--stage'), index);
});

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
