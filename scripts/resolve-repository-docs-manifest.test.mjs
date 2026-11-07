import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
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

for (const mode of ['--staged', null]) {
  for (const input of ['repository-docs.json', 'README.md', 'packages/shared-lib/turbo.json']) {
    test(`source-map repair ${mode ?? 'default'} refuses indexed symlink ${input}`, (t) => {
      const f = autoMergedManifests(t);
      const blob = f.git('rev-parse', `:${input}`).trim();
      // Keep regular worktree bytes: the index mode must determine admission.
      f.git('update-index', '--cacheinfo', `120000,${blob},${input}`);
      const before = readFileSync(join(f.root, f.output));
      const index = f.git('ls-files', '--stage');
      const result = spawnSync('python3', [resolver, '--root', f.root, ...(mode ? [mode] : [])], {
        env, encoding: 'utf8',
      });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /source input must be a regular indexed file/);
      assert.deepEqual(readFileSync(join(f.root, f.output)), before);
      assert.equal(f.git('ls-files', '--stage'), index);
    });
  }

  test(`source-map repair ${mode ?? 'default'} accepts executable indexed sources`, (t) => {
    const f = autoMergedManifests(t);
    f.git('update-index', '--chmod=+x', 'README.md');
    const result = spawnSync('python3', [resolver, '--root', f.root, ...(mode ? [mode] : [])], {
      env, encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(f.git('ls-files', '--stage', '--', 'README.md'), /^100755 /);
    assert.equal(f.git('ls-files', '--unmerged'), '');
  });
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

test('auto-merged manifest accepts a new glob that covers replaced inputs', (t) => {
  const fixture = manifestRepo(t);
  const named = ['scripts/ios/launch_ui_timeline_day.py', 'scripts/ios/launch_ui_opacity_audit.py'];
  fixture.commit('node --test shared.test.mjs', ['$TURBO_DEFAULT$', ...named, 'workflow.yml'], 'narrow');
  fixture.git('branch', 'incoming');
  fixture.commit(
    'node --test shared.test.mjs',
    ['$TURBO_DEFAULT$', 'scripts/ios/launch_ui_*.py', 'workflow.yml', 'company.mjs'],
    'glob',
  );
  fixture.git('switch', '-q', 'incoming');
  fixture.commit(
    'node --test shared.test.mjs',
    ['$TURBO_DEFAULT$', ...named, 'workflow.yml', 'personal.ts'],
    'personal',
  );
  fixture.git('switch', '-q', 'feature');
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], {
    cwd: fixture.root, env, encoding: 'utf8',
  });
  assert.equal(merge.status, 1, merge.stderr);
  const kept = {
    extends: ['//'],
    tasks: {
      test: {
        outputs: ['$TURBO_EXTENDS$'],
        inputs: ['$TURBO_DEFAULT$', 'scripts/ios/launch_ui_*.py', 'workflow.yml', 'company.mjs', 'personal.ts'],
      },
      'test:mutation': { cache: false },
    },
  };
  writeFileSync(join(fixture.root, fixture.turbo), `${JSON.stringify(kept, null, 2)}\n`);
  fixture.git('add', fixture.turbo);
  const accepted = spawnSync('python3', [resolver, '--root', fixture.root, '--staged'], {
    env, encoding: 'utf8',
  });
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.match(fixture.git('show', `:${fixture.turbo}`), /launch_ui_\*\.py/);
  assert.match(fixture.git('show', `:${fixture.turbo}`), /personal\.ts/);
  const dropped = structuredClone(kept);
  dropped.tasks.test.inputs = dropped.tasks.test.inputs.filter((item) => item !== 'personal.ts');
  writeFileSync(join(fixture.root, fixture.turbo), `${JSON.stringify(dropped, null, 2)}\n`);
  fixture.git('add', fixture.turbo);
  const refused = spawnSync('python3', [resolver, '--root', fixture.root, '--staged'], {
    env, encoding: 'utf8',
  });
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /additive manifest union keeps every parent test input/);
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
