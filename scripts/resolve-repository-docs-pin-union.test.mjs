import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { env, resolver } from './resolve-repository-docs.test.mjs';
import {
  DIAGNOSTIC_PROJECT,
  DIAGNOSTIC_WORKFLOW,
  mergePinFixture,
  pinFixture,
  projectMember,
} from './resolve-repository-docs-pin.test.mjs';

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
  const run = (value) => spawnSync('python3', ['-c', 'from pathlib import Path; import sys; sys.path.insert(0, sys.argv[1]); from diagnostic_audit_pin import refresh_reviewed_audit; refresh_reviewed_audit(Path(sys.argv[2]), sys.argv[3])', dirname(resolver), f.root, value], { env, encoding: 'utf8' });
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


const BASE_AUDIT = '11'.repeat(32);
const OURS_AUDIT = '22'.repeat(32);
const THEIRS_AUDIT = '33'.repeat(32);
const TIMEOUT_PIN = `              'scripts/ios/xcodebuild-command-timeout.py': '${'a'.repeat(64)}',\n`;

function resolveProject(root, digest, audit) {
  const args = [resolver, '--root', root, '--reviewed-project-sha256', digest];
  if (audit) args.push('--reviewed-audit-sha256', audit);
  return spawnSync('python3', args, { env, encoding: 'utf8' });
}

for (const change of ['ours', 'theirs', 'divergent', 'removed', 'hand edited']) {
  test(`reviewed project repair preserves one-sided dependency updates: ${change}`, (t) => {
    const f = pinFixture(t, { baseAudit: BASE_AUDIT });
    const path = join(f.root, DIAGNOSTIC_WORKFLOW);
    const gap = '# context 1\n# context 2\n# context 3\n# context 4\n';
    const write = (project, pin, audit) => {
      f.writeProject(project, 'kept', audit);
      separateAudit(path);
      writeFileSync(path, pin + gap + readFileSync(path, 'utf8'));
    };
    write('base-project\n', TIMEOUT_PIN, BASE_AUDIT);
    f.generate();
    f.commit();
    f.git('branch', '-f', 'theirs');
    const oursPin = ['ours', 'divergent'].includes(change)
      ? TIMEOUT_PIN.replace('a'.repeat(64), 'b'.repeat(64)) : TIMEOUT_PIN;
    const theirsPin = change === 'removed' ? '' : change === 'ours' ? TIMEOUT_PIN
      : TIMEOUT_PIN.replace('a'.repeat(64), 'c'.repeat(64));
    write('ours-project\n', oursPin, BASE_AUDIT);
    f.generate();
    f.commit();
    f.git('switch', '-q', 'theirs');
    write('theirs-project\n', theirsPin, THEIRS_AUDIT);
    f.generate();
    f.commit();
    f.git('switch', '-q', 'ours');
    mergePinFixture(f);
    const project = 'ours-project\ntheirs-project\n';
    writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), project);
    f.git('add', '--', DIAGNOSTIC_PROJECT);
    if (change === 'hand edited') writeFileSync(path, readFileSync(path, 'utf8') + '# local edit\n');
    const index = f.git('ls-files', '--stage');
    const original = readFileSync(path);
    const projection = readFileSync(join(f.root, f.output));
    const digest = createHash('sha256').update(project).digest('hex');
    const result = resolveProject(f.root, digest);
    if (['ours', 'theirs'].includes(change)) {
      assert.equal(result.status, 0, result.stderr);
      const workflow = f.git('show', `:${DIAGNOSTIC_WORKFLOW}`);
      assert.ok(workflow.startsWith((change === 'ours' ? oursPin : theirsPin) + gap));
      assert.match(workflow, new RegExp(THEIRS_AUDIT));
      assert.match(workflow, new RegExp(digest));
      assert.equal(f.git('ls-files', '--unmerged'), '');
    } else {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /not limited to the project pin/);
      assert.equal(f.git('ls-files', '--stage'), index);
      assert.deepEqual(readFileSync(path), original);
      assert.deepEqual(readFileSync(join(f.root, f.output)), projection);
    }
  });
}

test('reviewed digest keeps branch workflow edits when incoming changes only the project pin', (t) => {
  const f = pinFixture(t);
  f.writeProject('ours-project\n');
  const workflowPath = join(f.root, DIAGNOSTIC_WORKFLOW);
  // Keep the extra pin away from the project pin so Git conflicts only that line.
  writeFileSync(workflowPath, TIMEOUT_PIN + readFileSync(workflowPath, 'utf8'));
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject('theirs-project\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const merged = 'ours-project\ntheirs-project\n';
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), merged);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const digest = createHash('sha256').update(merged).digest('hex');
  const conflicted = readFileSync(workflowPath);
  const beforeMap = readFileSync(join(f.root, f.output));
  const index = f.git('ls-files', '--stage');
  writeFileSync(workflowPath, Buffer.concat([conflicted, Buffer.from('hand edit\n')]));
  const dirty = resolveProject(f.root, digest);
  assert.notEqual(dirty.status, 0);
  assert.match(dirty.stderr, /not limited to the project pin/);
  assert.deepEqual(readFileSync(workflowPath), Buffer.concat([conflicted, Buffer.from('hand edit\n')]));
  assert.deepEqual(readFileSync(join(f.root, f.output)), beforeMap);
  assert.equal(f.git('ls-files', '--stage'), index);
  writeFileSync(workflowPath, conflicted);
  const result = resolveProject(f.root, digest);
  assert.equal(result.status, 0, result.stderr);
  const staged = f.git('show', `:${DIAGNOSTIC_WORKFLOW}`);
  assert.match(staged, new RegExp(digest));
  assert.match(staged, /xcodebuild-command-timeout\.py/);
  assert.doesNotMatch(staged, new RegExp(createHash('sha256').update('ours-project\n').digest('hex')));
  assert.doesNotMatch(staged, new RegExp(createHash('sha256').update('theirs-project\n').digest('hex')));
  assert.equal(f.git('diff', '--name-only', '--diff-filter=U'), '');
});

test('additive project union keeps both parent file memberships', (t) => {
  const f = pinFixture(t);
  const oursId = 'B318A11A0000000000000001';
  const theirsId = 'B317A11A0000000000000001';
  f.writeProject(`base-project\n${projectMember(oursId, 'BodyShapeCalibration.swift')}`);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject(`base-project\n${projectMember(theirsId, 'PersonalBodyEstimate.swift')}`);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const beforeWorkflow = readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW));
  const union = spawnSync('python3', [resolver, '--root', f.root, '--union-project'], {
    env, encoding: 'utf8',
  });
  assert.equal(union.status, 0, union.stderr);
  const staged = f.git('show', `:${DIAGNOSTIC_PROJECT}`);
  assert.match(staged, new RegExp(oursId));
  assert.match(staged, new RegExp(theirsId));
  assert.equal(f.git('diff', '--name-only', '--diff-filter=U', '--', DIAGNOSTIC_PROJECT), '');
  assert.match(f.git('diff', '--name-only', '--diff-filter=U'), /ios-ui-diagnostics/);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_WORKFLOW)), beforeWorkflow);
  writeFileSync(join(f.root, 'a.txt'), 'DIRTY\n');
  const bytes = execFileSync('git', ['show', `:${DIAGNOSTIC_PROJECT}`], { cwd: f.root });
  const digest = createHash('sha256').update(bytes).digest('hex');
  const pinned = resolveProject(f.root, digest);
  assert.equal(pinned.status, 0, pinned.stderr);
  assert.match(f.git('show', `:${DIAGNOSTIC_WORKFLOW}`), new RegExp(digest));
  assert.doesNotMatch(f.git('show', `:${f.output}`), new RegExp(createHash('sha256').update('DIRTY\n').digest('hex')));
  assert.equal(readFileSync(join(f.root, 'a.txt'), 'utf8'), 'DIRTY\n');
  assert.equal(f.git('diff', '--name-only', '--diff-filter=U'), '');
});

test('project union refuses a parent that edits an existing project line', (t) => {
  const f = pinFixture(t);
  f.writeProject(`base-project\n${projectMember('B318A11A0000000000000001', 'BodyShapeCalibration.swift')}`);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject(`changed-project\n${projectMember('B317A11A0000000000000001', 'PersonalBodyEstimate.swift')}`);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const beforeProject = readFileSync(join(f.root, DIAGNOSTIC_PROJECT));
  const index = f.git('ls-files', '--stage', '--', DIAGNOSTIC_PROJECT);
  const refused = spawnSync('python3', [resolver, '--root', f.root, '--union-project'], {
    env, encoding: 'utf8',
  });
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /parent changed an existing project line/);
  assert.deepEqual(readFileSync(join(f.root, DIAGNOSTIC_PROJECT)), beforeProject);
  assert.equal(f.git('ls-files', '--stage', '--', DIAGNOSTIC_PROJECT), index);
});

test('project union refuses duplicate file membership ids', (t) => {
  const f = pinFixture(t);
  const shared = 'B318A11A0000000000000001';
  f.writeProject(`base-project\n${projectMember(shared, 'BodyShapeCalibration.swift')}`);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject(`base-project\n${projectMember(shared, 'PersonalBodyEstimate.swift')}`);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const index = f.git('ls-files', '--stage', '--', DIAGNOSTIC_PROJECT);
  const refused = spawnSync('python3', [resolver, '--root', f.root, '--union-project'], {
    env, encoding: 'utf8',
  });
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, new RegExp(`duplicate file membership ${shared}`));
  assert.equal(f.git('ls-files', '--stage', '--', DIAGNOSTIC_PROJECT), index);
});

function separateAudit(path) {
  const text = readFileSync(path, 'utf8');
  if (text.includes('# shared 0\n')) return;
  // Four unchanged lines keep the audit pin and project pin in separate hunks.
  const gap = [0, 1, 2, 3].map((index) => `          # shared ${index}\n`).join('');
  writeFileSync(path, text.replace(
    /(REVIEWED_AUDIT_SHA256 = '[0-9a-f]+'\n)/,
    `$1${gap}`,
  ));
}

test('divergent audit pins keep a one-sided dependency only with an explicit digest', (t) => {
  const f = pinFixture(t, { baseAudit: BASE_AUDIT });
  const workflowPath = join(f.root, DIAGNOSTIC_WORKFLOW);
  const routing = join(f.root, 'scripts/tests/test_runner_routing.py');
  const audit = join(f.root, 'scripts/ios/launch-quality-audit.sh');
  mkdirSync(join(f.root, 'scripts/tests'), { recursive: true });
  mkdirSync(join(f.root, 'scripts/ios'), { recursive: true });
  separateAudit(workflowPath);
  writeFileSync(routing, `expected = '${BASE_AUDIT}'\n`);
  writeFileSync(audit, 'base-audit\n');
  f.git('add', '-A');
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.git('merge', '--ff-only', 'ours');
  f.git('switch', '-q', 'ours');
  f.writeProject('ours-project\n', 'kept', OURS_AUDIT);
  separateAudit(workflowPath);
  writeFileSync(routing, `expected = '${OURS_AUDIT}'\n`);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject('theirs-project\n', 'kept', THEIRS_AUDIT);
  separateAudit(workflowPath);
  writeFileSync(workflowPath, TIMEOUT_PIN + readFileSync(workflowPath, 'utf8'));
  writeFileSync(routing, `expected = '${THEIRS_AUDIT}'\n`);
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const merged = 'ours-project\ntheirs-project\n';
  writeFileSync(join(f.root, DIAGNOSTIC_PROJECT), merged);
  f.git('add', '--', DIAGNOSTIC_PROJECT);
  const digest = createHash('sha256').update(merged).digest('hex');
  const before = readFileSync(workflowPath);
  const blocked = resolveProject(f.root, digest);
  assert.notEqual(blocked.status, 0);
  assert.match(blocked.stderr, /divergent reviewed audit pins/);
  assert.deepEqual(readFileSync(workflowPath), before);
  const auditBody = 'merged-audit\n';
  const auditDigest = createHash('sha256').update(auditBody).digest('hex');
  writeFileSync(audit, auditBody);
  f.git('add', '--', 'scripts/ios/launch-quality-audit.sh');
  const result = resolveProject(f.root, digest, auditDigest);
  assert.equal(result.status, 0, result.stderr);
  const staged = f.git('show', `:${DIAGNOSTIC_WORKFLOW}`);
  assert.match(staged, new RegExp(digest));
  assert.match(staged, new RegExp(auditDigest));
  assert.match(staged, /xcodebuild-command-timeout\.py/);
  assert.doesNotMatch(staged, /<<<<<<<</);
  const tests = f.git('show', ':scripts/tests/test_runner_routing.py');
  assert.match(tests, new RegExp(auditDigest));
  assert.doesNotMatch(tests, /<<<<<<<</);
  assert.equal(f.git('diff', '--name-only', '--diff-filter=U'), '');
});
