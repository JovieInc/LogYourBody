import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { env, resolver } from './resolve-repository-docs.test.mjs';

export const DIAGNOSTIC_PROJECT = 'apps/ios/LogYourBody.xcodeproj/project.pbxproj';
export const DIAGNOSTIC_WORKFLOW = '.github/workflows/ios-ui-diagnostics.yml';

function pinWorkflow(digest, note = 'kept', auditDigest = undefined) {
  const audit = auditDigest === undefined
    ? ''
    : `          REVIEWED_AUDIT_SHA256 = '${auditDigest}'\n`;
  return `jobs:\n  pins:\n    run: echo ok\n    env:\n      # ${note}\n${audit}            '${DIAGNOSTIC_PROJECT}': '${digest}',\n`;
}

export function pinFixture(t, { baseAudit } = {}) {
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
  const writeProject = (body, note = 'kept', auditDigest = baseAudit) => {
    writeFileSync(join(root, DIAGNOSTIC_PROJECT), body);
    writeFileSync(join(root, DIAGNOSTIC_WORKFLOW), pinWorkflow(
      createHash('sha256').update(body).digest('hex'), note, auditDigest,
    ));
  };
  writeProject('base-project\n');
  writeFileSync(join(root, 'a.txt'), 'base-a\n');
  generate();
  commit();
  git('branch', 'theirs');
  return { root, git, output, generate, commit, writeProject };
}

export function mergePinFixture(f) {
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

const BASE_AUDIT = '11'.repeat(32);
const OURS_AUDIT = '22'.repeat(32);
const THEIRS_AUDIT = '33'.repeat(32);

function mergedAuditPin(t, oursAudit, theirsAudit, theirsNote = 'kept') {
  const f = pinFixture(t, { baseAudit: BASE_AUDIT });
  f.writeProject('ours-project\n', 'kept', oursAudit);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject('theirs-project\n', theirsNote, theirsAudit);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const merged = 'ours-project\ntheirs-project\n';
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), merged);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  return { f, digest: createHash('sha256').update(merged).digest('hex') };
}

function resolveProjectPin(f, digest) {
  return spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256', digest,
  ], { env, encoding: 'utf8' });
}

test('reviewed project digest keeps a one-sided reviewed audit pin from either parent', (t) => {
  const branch = mergedAuditPin(t, OURS_AUDIT, BASE_AUDIT);
  const branchResult = resolveProjectPin(branch.f, branch.digest);
  assert.equal(branchResult.status, 0, branchResult.stderr);
  const branchWorkflow = branch.f.git('show', `:${DIAGNOSTIC_WORKFLOW}`);
  assert.match(branchWorkflow, new RegExp(OURS_AUDIT));
  assert.doesNotMatch(branchWorkflow, new RegExp(BASE_AUDIT));
  assert.match(branchWorkflow, new RegExp(branch.digest));

  const incoming = mergedAuditPin(t, BASE_AUDIT, THEIRS_AUDIT);
  const incomingResult = resolveProjectPin(incoming.f, incoming.digest);
  assert.equal(incomingResult.status, 0, incomingResult.stderr);
  const incomingWorkflow = incoming.f.git('show', `:${DIAGNOSTIC_WORKFLOW}`);
  assert.match(incomingWorkflow, new RegExp(THEIRS_AUDIT));
  assert.doesNotMatch(incomingWorkflow, new RegExp(BASE_AUDIT));
  assert.match(incomingWorkflow, new RegExp(incoming.digest));
  assert.equal(incoming.f.git('diff', '--name-only', '--diff-filter=U'), '');
});

test('reviewed project digest refuses divergent reviewed audit pins', (t) => {
  const f = mergedAuditPin(t, OURS_AUDIT, THEIRS_AUDIT);
  const beforeWorkflow = readFileSync(join(f.f.root, DIAGNOSTIC_WORKFLOW));
  const beforeMap = readFileSync(join(f.f.root, f.f.output));
  const index = f.f.git('ls-files', '--stage');
  const result = resolveProjectPin(f.f, f.digest);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /divergent reviewed audit pins/);
  assert.deepEqual(readFileSync(join(f.f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  assert.deepEqual(readFileSync(join(f.f.root, f.f.output)), beforeMap);
  assert.equal(f.f.git('ls-files', '--stage'), index);
});

test('reviewed project digest still refuses non-pin edits when the audit pin matches', (t) => {
  const f = mergedAuditPin(t, BASE_AUDIT, BASE_AUDIT, 'moved');
  const beforeWorkflow = readFileSync(join(f.f.root, DIAGNOSTIC_WORKFLOW));
  const index = f.f.git('ls-files', '--stage');
  const result = resolveProjectPin(f.f, f.digest);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /not limited to the project pin/);
  assert.deepEqual(readFileSync(join(f.f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  assert.equal(f.f.git('ls-files', '--stage'), index);
});

export function projectMember(id, name) {
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

const DIAGNOSTIC_AUDIT = 'scripts/ios/launch-quality-audit.sh';
const ROUTING_TESTS = 'scripts/tests/test_runner_routing.py';
const HISTORICAL_AUDIT = 'ab'.repeat(32);

function auditFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-audit-pin-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  mkdirSync(join(root, 'scripts/ios'), { recursive: true });
  mkdirSync(join(root, 'scripts/tests'), { recursive: true });
  mkdirSync(join(root, '.github/workflows'), { recursive: true });
  const output = 'SOURCES.md';
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [
      { path: DIAGNOSTIC_AUDIT, purpose: 'Reviewed launch audit' },
      { path: 'a.txt', purpose: 'Unrelated source' },
    ],
    imports: [], output,
  }));
  writeFileSync(join(root, 'a.txt'), 'kept-source\n');
  const audit = 'audit-v1\n';
  const digest = createHash('sha256').update(audit).digest('hex');
  writeFileSync(join(root, DIAGNOSTIC_AUDIT), audit);
  writeFileSync(join(root, DIAGNOSTIC_WORKFLOW), [
    'jobs:',
    '  pins:',
    '    run: |',
    `          REVIEWED_AUDIT_SHA256 = '${digest}'`,
    '',
  ].join('\n'));
  writeFileSync(join(root, ROUTING_TESTS), [
    `expected = '${digest}'`,
    `assert module['REVIEWED_AUDIT_SHA256'] == '${digest}'`,
    `assert "REVIEWED_AUDIT_SHA256 = '${digest}'" in source`,
    `historical = '${HISTORICAL_AUDIT}'`,
    '',
  ].join('\n'));
  execFileSync('python3', [
    fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
  ], { env });
  git('init', '-q', '-b', 'main');
  git('config', 'core.hooksPath', '/dev/null');
  git('add', '-A');
  git('commit', '-qm', 'fixture');
  return { root, git, output, digest };
}

test('reviewed audit digest updates every current pin and ignores unstaged source bytes', (t) => {
  const f = auditFixture(t);
  const next = 'audit-v2\n';
  const digest = createHash('sha256').update(next).digest('hex');
  writeFileSync(join(f.root, DIAGNOSTIC_AUDIT), next);
  f.git('add', '--', DIAGNOSTIC_AUDIT);
  const beforeWorkflow = readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW));
  const beforeTests = readFileSync(join(f.root, ROUTING_TESTS));
  const beforeMap = readFileSync(join(f.root, f.output));
  const index = f.git('ls-files', '--stage');
  const wrong = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-audit-sha256', '0'.repeat(64),
  ], { env, encoding: 'utf8' });
  assert.notEqual(wrong.status, 0);
  assert.match(wrong.stderr, /does not match merged source/);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  assert.deepEqual(readFileSync(join(f.root, ROUTING_TESTS)), beforeTests);
  assert.deepEqual(readFileSync(join(f.root, f.output)), beforeMap);
  assert.equal(f.git('ls-files', '--stage'), index);
  writeFileSync(join(f.root, DIAGNOSTIC_AUDIT), `${next}unstaged\n`);
  const dirty = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-audit-sha256', digest,
  ], { env, encoding: 'utf8' });
  assert.notEqual(dirty.status, 0);
  assert.match(dirty.stderr, /stage reviewed audit and pin edits first/);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  assert.equal(f.git('ls-files', '--stage'), index);
  writeFileSync(join(f.root, DIAGNOSTIC_AUDIT), next);
  writeFileSync(join(f.root, 'a.txt'), 'DIRTY\n');
  const result = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-audit-sha256', digest,
  ], { env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const workflow = f.git('show', `:${DIAGNOSTIC_WORKFLOW}`);
  const tests = f.git('show', `:${ROUTING_TESTS}`);
  const staged = f.git('show', `:${f.output}`);
  assert.match(workflow, new RegExp(digest));
  assert.doesNotMatch(workflow, new RegExp(f.digest));
  assert.equal(tests.split(digest).length - 1, 3);
  assert.doesNotMatch(tests, new RegExp(f.digest));
  assert.match(tests, new RegExp(HISTORICAL_AUDIT));
  assert.match(staged, new RegExp(digest));
  assert.match(staged, new RegExp(createHash('sha256').update('kept-source\n').digest('hex')));
  assert.doesNotMatch(staged, new RegExp(createHash('sha256').update('DIRTY\n').digest('hex')));
  assert.equal(readFileSync(join(f.root, 'a.txt'), 'utf8'), 'DIRTY\n');
  const again = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-audit-sha256', digest,
  ], { env, encoding: 'utf8' });
  assert.equal(again.status, 0, again.stderr);
  assert.equal(f.git('show', `:${DIAGNOSTIC_WORKFLOW}`), workflow);
  assert.equal(f.git('show', `:${ROUTING_TESTS}`), tests);
});

test('reviewed audit digest refuses to move the workflow pin without the routing tests', (t) => {
  const f = auditFixture(t);
  const next = 'audit-v2\n';
  const digest = createHash('sha256').update(next).digest('hex');
  writeFileSync(join(f.root, DIAGNOSTIC_AUDIT), next);
  writeFileSync(join(f.root, ROUTING_TESTS), `historical = '${HISTORICAL_AUDIT}'\n`);
  f.git('add', '--', DIAGNOSTIC_AUDIT, ROUTING_TESTS);
  const beforeWorkflow = readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW));
  const index = f.git('ls-files', '--stage');
  const refused = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-audit-sha256', digest,
  ], { env, encoding: 'utf8' });
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /absent from the routing tests/);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  assert.equal(f.git('ls-files', '--stage'), index);
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

// Token counts alone must not certify swapped PBXBuildFile -> fileRef edges.
test('reviewed project merge refuses rewired parent build-file mappings', (t) => {
  const f = pinFixture(t);
  const member = (build, file, name) =>
    projectMember(file, name) + `\t\t${build} /* ${name} in Sources */ = {isa = PBXBuildFile; fileRef = ${file} /* ${name} */; };\n`;
  const ours = member('BUILD1', 'FILE1', 'DatedOutcomeStats.swift');
  const theirs = member('BUILD2', 'FILE2', 'HealthSyncPresentationStore.swift');
  f.writeProject(ours); f.generate(); f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject(theirs); f.generate(); f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const kept = ours + theirs;
  const swapped = kept.replace('fileRef = FILE1', 'fileRef = TEMP')
    .replace('fileRef = FILE2', 'fileRef = FILE1').replace('fileRef = TEMP', 'fileRef = FILE2');
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), swapped);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const index = f.git('ls-files', '--stage');
  const workflow = readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW));
  const output = readFileSync(join(f.root, f.output));
  const resolve = (source) => resolveProjectPin(f, createHash('sha256').update(source).digest('hex'));
  assert.notEqual(resolve(swapped).status, 0, 'swapped mappings must fail with identical identifier counts');
  assert.match(resolve(swapped).stderr, /merged project changed a parent build-file mapping/);
  assert.equal(f.git('ls-files', '--stage'), index);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW)), workflow);
  assert.deepEqual(readFileSync(join(f.root, f.output)), output);
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), kept);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const accepted = resolve(kept);
  assert.equal(accepted.status, 0, accepted.stderr);
});
