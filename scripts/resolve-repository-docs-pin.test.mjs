import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { env, resolver } from './resolve-repository-docs.test.mjs';

const DIAGNOSTIC_PROJECT = 'apps/ios/LogYourBody.xcodeproj/project.pbxproj';
const DIAGNOSTIC_WORKFLOW = '.github/workflows/ios-ui-diagnostics.yml';

function pinWorkflow(digest, note = 'kept') {
  return `jobs:\n  pins:\n    run: echo ok\n    env:\n      # ${note}\n            '${DIAGNOSTIC_PROJECT}': '${digest}',\n`;
}

function pinFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-diagnostic-pin-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  const output = 'SOURCES.md';
  git('init', '-q', '-b', 'ours');
  git('config', 'core.hooksPath', '/dev/null');
  mkdirSync(join(root, 'apps/ios/LogYourBody.xcodeproj'), { recursive: true });
  mkdirSync(join(root, '.github/workflows'), { recursive: true });
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [
      { path: DIAGNOSTIC_PROJECT, purpose: 'Merged Xcode project' },
      { path: DIAGNOSTIC_WORKFLOW, purpose: 'Diagnostic project pin' },
      { path: 'a.txt', purpose: 'Branch fingerprint' },
    ],
    imports: [], output,
  }));
  const generate = () => execFileSync('python3', [
    fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
  ], { env });
  const commit = () => {
    git('add', '-A');
    git('commit', '-qm', 'fixture');
  };
  const writeProject = (body, note = 'kept') => {
    writeFileSync(join(root, DIAGNOSTIC_PROJECT), body);
    writeFileSync(join(root, DIAGNOSTIC_WORKFLOW), pinWorkflow(createHash('sha256').update(body).digest('hex'), note));
  };
  writeProject('base-project\n');
  writeFileSync(join(root, 'a.txt'), 'base-a\n');
  generate();
  commit();
  git('branch', 'theirs');
  return { root, git, output, generate, commit, writeProject };
}

function mergePinFixture(f) {
  const merge = spawnSync('git', ['merge', '--no-commit', 'theirs'], { cwd: f.root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
}

test('reviewed digest replaces a pin-only workflow conflict and rebuilds the source map from the index', (t) => {
  const f = pinFixture(t);
  f.writeProject('ours-project\n');
  writeFileSync(join(f.root, 'a.txt'), 'ours-a\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject('theirs-project\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const blocked = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256', 'ab'.repeat(32),
  ], { env, encoding: 'utf8' });
  assert.notEqual(blocked.status, 0);
  assert.match(blocked.stderr, /resolve source conflicts first: apps\/ios\/LogYourBody\.xcodeproj\/project\.pbxproj/);
  const merged = 'ours-project\ntheirs-project\n';
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), merged);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const digest = createHash('sha256').update(merged).digest('hex');
  const beforeWorkflow = readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW));
  const beforeMap = readFileSync(join(f.root, f.output));
  const index = f.git('ls-files', '--stage');
  const derived = spawnSync('python3', [resolver, '--root', f.root], { env, encoding: 'utf8' });
  assert.notEqual(derived.status, 0);
  assert.match(derived.stderr, /resolve source conflicts first: \.github\/workflows\/ios-ui-diagnostics\.yml/);
  const wrong = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256', '0'.repeat(64),
  ], { env, encoding: 'utf8' });
  assert.notEqual(wrong.status, 0);
  assert.match(wrong.stderr, /does not match merged source/);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  assert.deepEqual(readFileSync(join(f.root, f.output)), beforeMap);
  assert.equal(f.git('ls-files', '--stage'), index);
  writeFileSync(join(f.root, 'a.txt'), 'DIRTY\n');
  const result = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256', digest,
  ], { env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const workflow = f.git('show', `:${DIAGNOSTIC_WORKFLOW}`);
  const staged = f.git('show', `:${f.output}`);
  assert.match(workflow, new RegExp(digest));
  assert.doesNotMatch(workflow, new RegExp(createHash('sha256').update('ours-project\n').digest('hex')));
  assert.doesNotMatch(workflow, new RegExp(createHash('sha256').update('theirs-project\n').digest('hex')));
  assert.match(staged, new RegExp(digest));
  assert.match(staged, new RegExp(createHash('sha256').update(workflow).digest('hex')));
  assert.match(staged, new RegExp(createHash('sha256').update('ours-a\n').digest('hex')));
  assert.doesNotMatch(staged, new RegExp(createHash('sha256').update('DIRTY\n').digest('hex')));
  assert.equal(readFileSync(join(f.root, 'a.txt'), 'utf8'), 'DIRTY\n');
  assert.equal(f.git('diff', '--name-only', '--diff-filter=U'), '');
});

test('reviewed digest refuses a workflow conflict that changes more than the project pin', (t) => {
  const f = pinFixture(t);
  f.writeProject('ours-project\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject('theirs-project\n', 'moved');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const merged = 'ours-project\ntheirs-project\n';
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), merged);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const beforeWorkflow = readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW));
  const beforeMap = readFileSync(join(f.root, f.output));
  const index = f.git('ls-files', '--stage');
  const result = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256', createHash('sha256').update(merged).digest('hex'),
  ], { env, encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /not limited to the project pin/);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  assert.deepEqual(readFileSync(join(f.root, f.output)), beforeMap);
  assert.equal(f.git('ls-files', '--stage'), index);
});

function projectMember(id, name) {
  return `\t\t${id} /* ${name} */ = {isa = PBXFileReference; path = ${name}; };\n`;
}

test('reviewed digest refuses a merged project that dropped a parent file', (t) => {
  const f = pinFixture(t);
  const oursId = 'B317A11A0000000000000001';
  const theirsId = 'B313F11E0000000000000A01';
  f.writeProject(projectMember(oursId, 'PersonalBodyEstimate.swift'));
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject(projectMember(theirsId, 'BodyPhotoPresentation.swift'));
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const dropped = projectMember(oursId, 'PersonalBodyEstimate.swift');
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), dropped);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const beforeWorkflow = readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW));
  const beforeMap = readFileSync(join(f.root, f.output));
  const index = f.git('ls-files', '--stage');
  const refused = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256',
    createHash('sha256').update(dropped).digest('hex'),
  ], { env, encoding: 'utf8' });
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /merged project dropped a parent file: B313F11E0000000000000A01/);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  assert.deepEqual(readFileSync(join(f.root, f.output)), beforeMap);
  assert.equal(f.git('ls-files', '--stage'), index);
  const kept = dropped + projectMember(theirsId, 'BodyPhotoPresentation.swift');
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), kept);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const accepted = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256',
    createHash('sha256').update(kept).digest('hex'),
  ], { env, encoding: 'utf8' });
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.match(f.git('show', `:${DIAGNOSTIC_WORKFLOW}`), new RegExp(createHash('sha256').update(kept).digest('hex')));
  assert.equal(f.git('diff', '--name-only', '--diff-filter=U'), '');
});
