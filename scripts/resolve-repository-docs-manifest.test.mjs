import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { env, manifestRepo, resolver } from './resolve-repository-docs.test.mjs';

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
