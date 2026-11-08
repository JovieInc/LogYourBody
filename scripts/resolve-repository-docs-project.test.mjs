import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { env, resolver } from './resolve-repository-docs.test.mjs';
import { pinFixture, mergePinFixture } from './resolve-repository-docs-pin.test.mjs';

const PROJECT = 'apps/ios/LogYourBody.xcodeproj/project.pbxproj';
const WORKFLOW = '.github/workflows/ios-ui-diagnostics.yml';

for (const manualEdit of [false, true]) {
  test(`reviewed digest preserves incoming workflow additions; manual edit: ${manualEdit}`, (t) => {
    const f = pinFixture(t);
    f.writeProject('ours-project\n');
    f.generate();
    f.commit();
    f.git('switch', '-q', 'theirs');
    f.writeProject('theirs-project\n');
    const extra = `# retained incoming audit policy\n# spacing\n# spacing\n# spacing\n`;
    const workflowPath = join(f.root, WORKFLOW);
    writeFileSync(workflowPath, extra + readFileSync(workflowPath, 'utf8'));
    f.generate();
    f.commit();
    f.git('switch', '-q', 'ours');
    mergePinFixture(f);
    const merged = 'ours-project\ntheirs-project\n';
    writeFileSync(join(f.root, PROJECT), merged);
    f.git('add', '--', PROJECT);
    if (manualEdit) {
      writeFileSync(workflowPath, `# unreviewed edit\n${readFileSync(workflowPath, 'utf8')}`);
    }
    const index = f.git('ls-files', '--stage');
    const workflow = readFileSync(workflowPath);
    const projection = readFileSync(join(f.root, f.output));
    const digest = createHash('sha256').update(merged).digest('hex');
    const result = spawnSync('python3', [
      resolver, '--root', f.root, '--reviewed-project-sha256', digest,
    ], { env, encoding: 'utf8' });
    if (manualEdit) {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /conflict is not limited to the project pin/);
      assert.equal(f.git('ls-files', '--stage'), index);
      assert.deepEqual(readFileSync(workflowPath), workflow);
      assert.deepEqual(readFileSync(join(f.root, f.output)), projection);
    } else {
      assert.equal(result.status, 0, result.stderr);
      assert.match(f.git('show', `:${WORKFLOW}`), new RegExp(digest));
      assert.ok(f.git('show', `:${WORKFLOW}`).startsWith(extra));
      assert.equal(f.git('ls-files', '--unmerged'), '');
    }
  });
}

for (const variant of ['clean', 'dropped input', 'unstaged edit']) {
  test(`project union verifies an automatically merged project: ${variant}`, (t) => {
    const f = pinFixture(t);
    const base = 'base-project\nslot-a\ncontext-1\ncontext-2\ncontext-3\nslot-b\n';
    f.writeProject(base);
    f.generate();
    f.commit();
    f.git('branch', '-f', 'theirs', 'HEAD');
    f.writeProject(base.replace('slot-a\n', 'slot-a\nours-membership\n'));
    f.generate();
    f.commit();
    f.git('switch', '-q', 'theirs');
    f.writeProject(base.replace('slot-b\n', 'slot-b\ntheirs-membership\n'));
    f.generate();
    f.commit();
    f.git('switch', '-q', 'ours');
    mergePinFixture(f);
    assert.equal(f.git('ls-files', '--unmerged', '--', PROJECT), '');
    const path = join(f.root, PROJECT);
    if (variant === 'dropped input') {
      writeFileSync(path, readFileSync(path, 'utf8').replace('theirs-membership\n', ''));
      f.git('add', '--', PROJECT);
    } else if (variant === 'unstaged edit') {
      writeFileSync(path, `${readFileSync(path, 'utf8')}local edit\n`);
    }
    const index = f.git('ls-files', '--stage');
    const project = readFileSync(path);
    const workflow = readFileSync(join(f.root, WORKFLOW));
    const result = spawnSync('python3', [resolver, '--root', f.root, '--union-project'], {
      env, encoding: 'utf8',
    });
    if (variant === 'clean') {
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stdout, /verified additive project union/);
    } else {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /staged project differs from additive parent union|unstaged project edits/);
    }
    assert.equal(f.git('ls-files', '--stage'), index);
    assert.deepEqual(readFileSync(path), project);
    assert.deepEqual(readFileSync(join(f.root, WORKFLOW)), workflow);
  });
}

function projectPlacement(id, name, placed) {
  const reference = `\t\t${id} /* ${name} */ = {isa = PBXFileReference; path = ${name}; };\n`;
  return placed ? `${reference}\t\t\t\t${id} /* ${name} */,\n` : reference;
}

test('reviewed digest refuses a manually edited workflow', (t) => {
  const f = pinFixture(t);
  f.writeProject('ours-project\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject('theirs-project\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const merged = 'ours-project\ntheirs-project\n';
  writeFileSync(join(f.root, PROJECT), merged);
  f.git('add', '--', PROJECT);
  writeFileSync(join(f.root, WORKFLOW), 'manual resolution\n');
  const index = f.git('ls-files', '--stage');
  const result = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256',
    createHash('sha256').update(merged).digest('hex'),
  ], { env, encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /manually edited workflow/);
  assert.equal(f.git('ls-files', '--stage'), index);
  assert.equal(readFileSync(join(f.root, WORKFLOW), 'utf8'), 'manual resolution\n');
});

test('reviewed digest refuses a merged project that dropped a parent group entry', (t) => {
  const f = pinFixture(t);
  const oursId = 'A31203130100000000000001';
  const theirsId = 'B317A11A000000000000000D';
  f.writeProject(projectPlacement(oursId, 'ProgressPhotoAttachSheet+CheckIn.swift', true));
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  f.writeProject(projectPlacement(theirsId, 'ProgressPhotoAttachSheet+PersonalBody.swift', true));
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  mergePinFixture(f);
  const dropped = projectPlacement(oursId, 'ProgressPhotoAttachSheet+CheckIn.swift', true)
    + projectPlacement(theirsId, 'ProgressPhotoAttachSheet+PersonalBody.swift', false);
  writeFileSync(join(f.root, PROJECT), dropped);
  f.git('add', '--', PROJECT);
  const beforeWorkflow = readFileSync(join(f.root, WORKFLOW));
  const beforeMap = readFileSync(join(f.root, f.output));
  const index = f.git('ls-files', '--stage');
  const refused = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256',
    createHash('sha256').update(dropped).digest('hex'),
  ], { env, encoding: 'utf8' });
  assert.notEqual(refused.status, 0, refused.stderr);
  assert.match(refused.stderr, /merged project dropped a parent file: B317A11A000000000000000D/);
  assert.deepEqual(readFileSync(join(f.root, WORKFLOW)), beforeWorkflow);
  assert.deepEqual(readFileSync(join(f.root, f.output)), beforeMap);
  assert.equal(f.git('ls-files', '--stage'), index);
  const kept = projectPlacement(oursId, 'ProgressPhotoAttachSheet+CheckIn.swift', true)
    + projectPlacement(theirsId, 'ProgressPhotoAttachSheet+PersonalBody.swift', true);
  writeFileSync(join(f.root, PROJECT), kept);
  f.git('add', '--', PROJECT);
  const accepted = spawnSync('python3', [
    resolver, '--root', f.root, '--reviewed-project-sha256',
    createHash('sha256').update(kept).digest('hex'),
  ], { env, encoding: 'utf8' });
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.match(f.git('show', `:${WORKFLOW}`), new RegExp(createHash('sha256').update(kept).digest('hex')));
  assert.equal(f.git('diff', '--name-only', '--diff-filter=U'), '');
});

