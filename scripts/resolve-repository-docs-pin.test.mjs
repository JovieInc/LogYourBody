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
const DIAGNOSTIC_AUDIT = 'scripts/ios/launch-quality-audit.sh';
const DIAGNOSTIC_TESTS = 'scripts/tests/test_runner_routing.py';

test('reviewed audit repair updates all pins together and rejects unreviewed inputs without writing', (t) => {
  const f = pinFixture(t);
  mkdirSync(join(f.root, 'scripts/ios'), { recursive: true });
  mkdirSync(join(f.root, 'scripts/tests'), { recursive: true });
  const previous = 'a'.repeat(64);
  const audit = '# reviewed selectors\n';
  const digest = createHash('sha256').update(audit).digest('hex');
  const workflow = `            REVIEWED_AUDIT_SHA256 = '${previous}'\n# keep workflow policy\n`;
  const tests = `    assert module['REVIEWED_AUDIT_SHA256'] == hashlib.sha256(live_audit).hexdigest() == (\n        '${previous}'\n    )\n    expected = '${previous}'\n    assert module['REVIEWED_AUDIT_SHA256'] == expected\n    assert \"REVIEWED_AUDIT_SHA256 = '${previous}'\" in source\n# keep refusal fixtures\n`;
  writeFileSync(join(f.root, DIAGNOSTIC_AUDIT), audit);
  writeFileSync(join(f.root, DIAGNOSTIC_WORKFLOW), workflow);
  writeFileSync(join(f.root, DIAGNOSTIC_TESTS), tests);
  f.git('add', '-A');
  const index = f.git('write-tree');
  const run = (value) => spawnSync('python3', [resolver, '--root', f.root, '--reviewed-audit-sha256', value], { env, encoding: 'utf8' });
  const unchanged = () => {
    assert.equal(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW), 'utf8'), workflow);
    assert.equal(f.git('write-tree'), index);
  };
  for (const value of ['marker-only', '0'.repeat(64)]) {
    const refused = run(value);
    assert.notEqual(refused.status, 0);
    assert.match(refused.stderr, /reviewed audit SHA-256/);
    unchanged();
  }
  writeFileSync(join(f.root, DIAGNOSTIC_AUDIT), `${audit}# unstaged\n`);
  const dirty = run(digest);
  assert.notEqual(dirty.status, 0);
  assert.match(dirty.stderr, /stage reviewed audit repair inputs first/);
  unchanged();
  writeFileSync(join(f.root, DIAGNOSTIC_AUDIT), audit);
  for (const bad of [tests.replace(previous, 'b'.repeat(64)), tests + tests]) {
    writeFileSync(join(f.root, DIAGNOSTIC_TESTS), bad);
    f.git('add', DIAGNOSTIC_TESTS);
    const refused = run(digest);
    assert.notEqual(refused.status, 0);
    assert.match(refused.stderr, /regression pins must agree/);
    assert.equal(readFileSync(join(f.root, DIAGNOSTIC_TESTS), 'utf8'), bad);
    assert.equal(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW), 'utf8'), workflow);
  }
  writeFileSync(join(f.root, DIAGNOSTIC_TESTS), tests);
  f.git('add', DIAGNOSTIC_TESTS);
  const accepted = run(digest);
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.equal(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW), 'utf8'), workflow.replace(previous, digest));
  assert.equal(readFileSync(join(f.root, DIAGNOSTIC_TESTS), 'utf8'), tests.replaceAll(previous, digest));
  assert.equal(f.git('write-tree'), index, 'review and staging stay explicit');
  f.git('add', '-A');
  assert.equal(run(digest).status, 0, 'reviewed retry is idempotent');
});

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

test('reviewed digest refuses a retained file declaration with a missing group reference', (t) => {
  const f = pinFixture(t);
  const oursId = 'B317A11A0000000000000001';
  const theirsId = 'B313F11E0000000000000A01';
  const member = (id, name) => projectMember(id, name) + `\t\t\t\t${id} /* ${name} */,\n`;
  const ours = member(oursId, 'HomeV2RecentReadings.swift');
  const theirs = member(theirsId, 'SubjectPlateView.swift');
  f.writeProject(ours);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject(theirs);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const dropped = ours + projectMember(theirsId, 'SubjectPlateView.swift');
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), dropped);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const beforeWorkflow = readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW));
  const beforeMap = readFileSync(join(f.root, f.output));
  const index = f.git('ls-files', '--stage');
  const resolve = (project) => spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256',
    createHash('sha256').update(project).digest('hex'),
  ], { env, encoding: 'utf8' });
  const refused = resolve(dropped);
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /merged project dropped a parent file reference: B313F11E0000000000000A01/);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  assert.deepEqual(readFileSync(join(f.root, f.output)), beforeMap);
  assert.equal(f.git('ls-files', '--stage'), index);
  const kept = ours + theirs;
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), kept);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const accepted = resolve(kept);
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.equal(f.git('show', `:${DIAGNOSTIC_PROJECT}`), kept);
  assert.match(f.git('show', `:${DIAGNOSTIC_WORKFLOW}`), new RegExp(createHash('sha256').update(kept).digest('hex')));
  assert.equal(f.git('ls-files', '--unmerged'), '');
});

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

for (const [name, marker] of [
  ['source', '<<<<<<< HEAD\n'],
  ['source', '||||||| base\n'],
  ['source', '=======\n'],
  ['source', '>>>>>>> main\n'],
  ['source', '|| base\r\n'],
  ['README.md', '<< HEAD\r\n'],
]) {
  test(`staged projection refuses ${name} marker ${JSON.stringify(marker)} and permits a clean retry`, (t) => {
    const root = mkdtempSync(join(tmpdir(), 'lyb-doc-source-markers-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
    git('init', '-q', '-b', 'repair');
    git('config', 'core.hooksPath', '/dev/null');
    writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
      schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
      sources: [{ path: 'source', purpose: 'Merged source' }], imports: [], output: 'SOURCES.md',
    }));
    for (const path of ['README.md', 'source']) writeFileSync(join(root, path), 'Clean input\n');
    git('add', '.');
    git('commit', '-qm', 'fixture');
    const resolve = () => spawnSync('python3', [resolver, '--root', root, '--staged'], {
      env, encoding: 'utf8',
    });
    assert.equal(resolve().status, 0);
    const before = readFileSync(join(root, 'SOURCES.md'), 'utf8');
    writeFileSync(join(root, name), `Staged resolution\n${marker}`);
    git('add', name);
    // A clean working copy must not hide unresolved markers in the staged source.
    writeFileSync(join(root, name), 'Clean input\n');
    const index = git('ls-files', '--stage');
    const refused = resolve();
    assert.notEqual(refused.status, 0, refused.stdout);
    assert.match(refused.stderr, /resolve staged conflict markers first:/);
    assert.equal(readFileSync(join(root, 'SOURCES.md'), 'utf8'), before);
    assert.equal(git('ls-files', '--stage'), index);
    git('add', name);
    // Conversely, unstaged markers must not invalidate the clean staged snapshot.
    writeFileSync(join(root, name), marker);
    const retry = resolve();
    assert.equal(retry.status, 0, retry.stderr);
    assert.equal(readFileSync(join(root, 'SOURCES.md'), 'utf8'), before);
    assert.equal(git('show', ':SOURCES.md'), before);
    assert.equal(readFileSync(join(root, name), 'utf8'), marker);
    assert.equal(resolve().status, 0, 'clean staged retry remains idempotent');
  });
}
