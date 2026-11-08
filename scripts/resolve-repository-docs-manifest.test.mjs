import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { env, manifestRepo, resolver, sourceMapFixture } from './resolve-repository-docs.test.mjs';

function conflictingManifests(t, theirsTest, theirsInputs, oursTest = 'node --test shared.test.mjs ours.test.mjs', oursInputs = ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs']) {
  const fixture = manifestRepo(t);
  fixture.git('switch', '-qc', 'incoming');
  fixture.commit(theirsTest, theirsInputs, 'incoming');
  fixture.git('switch', '-q', 'feature');
  fixture.commit(oursTest, oursInputs, 'ours');
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: fixture.root, env });
  assert.equal(merge.status, 1, 'fixture must contain a real merge conflict');
  const run = (flag) => spawnSync('python3', [resolver, '--root', fixture.root, flag], { env, encoding: 'utf8' });
  return { ...fixture, run };
}

test('manifest union keeps both parents test inputs and inline turbo arrays', (t) => {
  const fixture = conflictingManifests(
    t,
    'node --test shared.test.mjs theirs.test.mjs',
    ['$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml'],
  );
  writeFileSync(join(fixture.root, 'NOTES.md'), 'Unstaged note\n');
  assert.notEqual(fixture.run('--staged').status, 0);
  const refused = spawnSync('python3', [resolver, '--root', fixture.root], { env, encoding: 'utf8' });
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /resolve source conflicts first/);
  const result = fixture.run('--union-manifests');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(
    JSON.parse(readFileSync(join(fixture.root, fixture.pkg), 'utf8')).scripts.test,
    'node --test shared.test.mjs theirs.test.mjs ours.test.mjs',
  );
  const turbo = readFileSync(join(fixture.root, fixture.turbo), 'utf8');
  assert.match(turbo, /"extends": \["\/\/"\]/);
  assert.match(turbo, /"outputs": \["\$TURBO_EXTENDS\$"\]/);
  assert.deepEqual(JSON.parse(turbo).tasks.test.inputs, [
    '$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs',
  ]);
  assert.equal(fixture.git('ls-files', '-u'), '');
  const projection = fixture.git('show', `:${fixture.output}`);
  assert.match(projection, /theirs\.test\.mjs/);
  assert.match(projection, /ours\.test\.mjs/);
  assert.equal(readFileSync(join(fixture.root, 'NOTES.md'), 'utf8'), 'Unstaged note\n');
  const index = fixture.git('ls-files', '--stage');
  assert.equal(fixture.run('--union-manifests').status, 0, 'resolved manifests stay idempotent');
  assert.equal(fixture.git('ls-files', '--stage'), index);
});

for (const [name, testScript, inputs] of [
  ['deleted test', 'node --test', ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml']],
  ['reordered input', 'node --test shared.test.mjs extra.test.mjs', ['shared.mjs', '$TURBO_DEFAULT$', 'workflow.yml', 'workflow.yml', 'theirs.mjs']],
  ['replaced script', 'node --test other.test.mjs', ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'extra.mjs']],
  ['dropped repeated input', 'node --test shared.test.mjs extra.test.mjs', ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml']],
]) {
  test(`manifest union refuses ${name} without staging`, (t) => {
    const fixture = conflictingManifests(t, testScript, inputs);
    const before = readFileSync(join(fixture.root, fixture.pkg), 'utf8');
    const index = fixture.git('ls-files', '--stage');
    const result = fixture.run('--union-manifests');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /additive manifest union keeps every parent test input/);
    assert.equal(readFileSync(join(fixture.root, fixture.pkg), 'utf8'), before);
    assert.equal(fixture.git('ls-files', '--stage'), index);
  });
}

test('manifest union leaves a conflicted correction ledger for its resolver', (t) => {
  const fixture = manifestRepo(t);
  const ledger = 'packages/shared-lib/corrections.json';
  const writeLedger = (body) => {
    mkdirSync(dirname(join(fixture.root, ledger)), { recursive: true });
    writeFileSync(join(fixture.root, ledger), body);
  };
  writeLedger('[]\n');
  fixture.git('add', ledger);
  fixture.git('commit', '-qm', 'ledger base');
  fixture.git('switch', '-qc', 'incoming');
  writeLedger('[{"fingerprint":"theirs"}]\n');
  fixture.commit(
    'node --test shared.test.mjs theirs.test.mjs',
    ['$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml'],
    'incoming',
  );
  fixture.git('switch', '-q', 'feature');
  writeLedger('[{"fingerprint":"ours"}]\n');
  fixture.commit(
    'node --test shared.test.mjs ours.test.mjs',
    ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs'],
    'ours',
  );
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: fixture.root, env });
  assert.equal(merge.status, 1, merge.stderr?.toString());
  const beforeLedger = readFileSync(join(fixture.root, ledger), 'utf8');
  const result = spawnSync('python3', [resolver, '--root', fixture.root, '--union-manifests'], {
    env, encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fixture.git('diff', '--name-only', '--diff-filter=U').trim(), ledger);
  assert.equal(readFileSync(join(fixture.root, ledger), 'utf8'), beforeLedger);
  assert.match(beforeLedger, /^<<<<<<< /m);
  const testScript = JSON.parse(readFileSync(join(fixture.root, fixture.pkg), 'utf8')).scripts.test;
  assert.match(testScript, /ours\.test\.mjs/);
  assert.match(testScript, /theirs\.test\.mjs/);
  assert.equal(fixture.git('ls-files', '-u', '--', fixture.output).trim(), '');
});

test('manifest union refuses an unrelated conflict without staging', (t) => {
  const fixture = manifestRepo(t);
  fixture.git('switch', '-qc', 'incoming');
  writeFileSync(join(fixture.root, 'NOTES.md'), 'Incoming note\n');
  fixture.commit(
    'node --test shared.test.mjs theirs.test.mjs',
    ['$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml'],
    'incoming',
  );
  fixture.git('switch', '-q', 'feature');
  writeFileSync(join(fixture.root, 'NOTES.md'), 'Branch note\n');
  fixture.commit(
    'node --test shared.test.mjs ours.test.mjs',
    ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs'],
    'ours',
  );
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: fixture.root, env });
  assert.equal(merge.status, 1);
  const before = readFileSync(join(fixture.root, fixture.pkg), 'utf8');
  const index = fixture.git('ls-files', '--stage');
  const result = spawnSync('python3', [resolver, '--root', fixture.root, '--union-manifests'], {
    env, encoding: 'utf8',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unrelated conflicts/);
  assert.equal(readFileSync(join(fixture.root, fixture.pkg), 'utf8'), before);
  assert.equal(fixture.git('ls-files', '--stage'), index);
});

test('manifest union refuses a symlink stage and a commit that is not a merge', (t) => {
  const fixture = conflictingManifests(
    t,
    'node --test shared.test.mjs theirs.test.mjs',
    ['$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml'],
  );
  const blob = fixture.git('rev-parse', `:3:${fixture.pkg}`).trim();
  const before = readFileSync(join(fixture.root, fixture.pkg), 'utf8');
  execFileSync('git', ['update-index', '--index-info'], {
    cwd: fixture.root,
    env,
    input: `120000 ${blob} 3\t${fixture.pkg}\n`,
  });
  const index = fixture.git('ls-files', '--stage');
  const symlink = fixture.run('--union-manifests');
  assert.notEqual(symlink.status, 0);
  assert.match(symlink.stderr, /regular files/);
  assert.equal(readFileSync(join(fixture.root, fixture.pkg), 'utf8'), before);
  assert.equal(fixture.git('ls-files', '--stage'), index);
  fixture.git('merge', '--abort');
  const absent = fixture.run('--union-manifests');
  assert.notEqual(absent.status, 0);
  assert.match(absent.stderr, /repository-docs:/);
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
