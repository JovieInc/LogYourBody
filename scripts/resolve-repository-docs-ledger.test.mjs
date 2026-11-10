import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { env, resolver, sourceMapFixture } from './resolve-repository-docs.test.mjs';

function ledgerMergeFixture(t, sourceConflict = false) {
  const f = sourceMapFixture(t);
  const ledger = 'packages/shared-lib/corrections.json';
  const template = JSON.parse(readFileSync(new URL('./fixtures/correction-classifier.json', import.meta.url)))[0];
  const receipt = (name) => ({ ...template, fingerprint: name,
    source: `https://example.com/corrections/${name}`, level: 'codebase', ruleId: 'type-or-schema' });
  const rows = [receipt('base')];
  const writeLedger = (name) => writeFileSync(join(f.root, ledger), `${JSON.stringify([...rows, receipt(name)], null, 2)}\n`);
  mkdirSync(join(f.root, 'packages/shared-lib'), { recursive: true });
  writeFileSync(join(f.root, 'model.ts'), `${template.guard.anchor}\n`);
  writeFileSync(join(f.root, ledger), `${JSON.stringify(rows, null, 2)}\n`);
  f.commit();
  f.git('branch', '-f', 'theirs');
  writeLedger('ours');
  writeFileSync(join(f.root, 'a.txt'), 'ours-a\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  writeLedger('theirs');
  writeFileSync(join(f.root, sourceConflict ? 'a.txt' : 'b.txt'), 'theirs-b\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  const merge = spawnSync('git', ['merge', '--no-commit', 'theirs'], { cwd: f.root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
  assert.match(f.git('ls-files', '--unmerged'), /corrections\.json/);
  const resolve = () => spawnSync('python3', [resolver, '--root', f.root, '--merge-ledger'], { env, encoding: 'utf8' });
  return { ...f, ledger, resolve, anchor: template.guard.anchor };
}

test('ledger repair refreshes staged fingerprints, preserves both parents and is retryable', (t) => {
  const f = ledgerMergeFixture(t);
  writeFileSync(join(f.root, 'a.txt'), 'unrelated unstaged source\n');
  const result = f.resolve();
  assert.equal(result.status, 0, result.stderr);
  const rows = JSON.parse(f.git('show', `:${f.ledger}`));
  assert.deepEqual(rows.map(({ fingerprint }) => fingerprint), ['base', 'theirs', 'ours']);
  assert.ok(rows.every(({ level, ruleId }) => level === 'codebase' && ruleId === 'type-or-schema'));
  const projection = f.git('show', `:${f.output}`);
  for (const source of ['ours-a\n', 'theirs-b\n']) {
    assert.match(projection, new RegExp(createHash('sha256').update(source).digest('hex')));
  }
  assert.equal(readFileSync(join(f.root, 'a.txt'), 'utf8'), 'unrelated unstaged source\n');
  assert.equal(f.git('ls-files', '--unmerged'), '');
  const index = f.git('ls-files', '--stage');
  assert.equal(f.resolve().status, 0, 'staged retries remain valid during the same merge');
  assert.equal(f.git('ls-files', '--stage'), index);
});

test('ledger repair preserves concurrent projection edits when rendering refuses a changed index', (t) => {
  const f = ledgerMergeFixture(t);
  const ledger = readFileSync(join(f.root, f.ledger));
  const ledgerIndex = f.git('ls-files', '--stage', '--', f.ledger);
  const gitBinary = execFileSync('which', ['git'], { env, encoding: 'utf8' }).trim();
  mkdirSync(join(f.root, 'bin'));
  writeFileSync(join(f.root, 'bin/git'), `#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
result = subprocess.run([${JSON.stringify(gitBinary)}, *sys.argv[1:]])
marker = Path('changed-once')
if sys.argv[1:] == ['show', ':a.txt'] and not marker.exists():
    Path('SOURCES.md').write_text('concurrent reviewed projection\\n')
    subprocess.run([${JSON.stringify(gitBinary)}, 'add', 'SOURCES.md'], check=True)
    marker.touch()
sys.exit(result.returncode)
`, { mode: 0o755 });
  const result = spawnSync('python3', [resolver, '--root', f.root, '--merge-ledger'], {
    env: { ...env, PATH: `${join(f.root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /source index changed during projection generation/);
  assert.equal(f.git('show', ':SOURCES.md'), 'concurrent reviewed projection\n');
  assert.equal(readFileSync(join(f.root, f.output), 'utf8'), 'concurrent reviewed projection\n');
  assert.deepEqual(readFileSync(join(f.root, f.ledger)), ledger);
  assert.equal(f.git('ls-files', '--stage', '--', f.ledger), ledgerIndex);
  assert.equal(f.resolve().status, 0, 'reviewed inputs can be regenerated on retry');
  assert.deepEqual(JSON.parse(f.git('show', `:${f.ledger}`)).map(({ fingerprint }) => fingerprint),
    ['base', 'theirs', 'ours']);
  const index = f.git('ls-files', '--stage');
  assert.equal(f.resolve().status, 0);
  assert.equal(f.git('ls-files', '--stage'), index);
});

for (const staged of [false, true]) {
  test(`ledger refusal preserves concurrent ${staged ? 'staged' : 'working'} projection edits after rendering`, (t) => {
    const f = ledgerMergeFixture(t);
    const ledger = readFileSync(join(f.root, f.ledger));
    const ledgerIndex = f.git('ls-files', '--stage', '--', f.ledger);
    const gitBinary = execFileSync('which', ['git'], { env, encoding: 'utf8' }).trim();
    mkdirSync(join(f.root, 'bin'));
    // The classifier starts after the resolver has rendered and staged the projection.
    writeFileSync(join(f.root, 'bin/node'), `#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
rendered = Path('SOURCES.md').read_bytes()
Path('rendered-projection').write_bytes(rendered)
Path('SOURCES.md').write_text('concurrent reviewed projection\\n')
if ${staged ? 'True' : 'False'}:
    subprocess.run([${JSON.stringify(gitBinary)}, 'add', 'SOURCES.md'], check=True)
    Path('SOURCES.md').write_bytes(rendered)
Path('reviewed-projection-index').write_bytes(subprocess.check_output([
    ${JSON.stringify(gitBinary)}, 'ls-files', '--stage', '--', 'SOURCES.md',
]))
sys.exit(1)
`, { mode: 0o755 });
    const result = spawnSync('python3', [resolver, '--root', f.root, '--merge-ledger'], {
      env: { ...env, PATH: `${join(f.root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
    });
    assert.notEqual(result.status, 0);
    assert.equal(readFileSync(join(f.root, f.output), 'utf8'), staged
      ? readFileSync(join(f.root, 'rendered-projection'), 'utf8')
      : 'concurrent reviewed projection\n');
    assert.equal(f.git('ls-files', '--stage', '--', f.output),
      readFileSync(join(f.root, 'reviewed-projection-index'), 'utf8'));
    assert.deepEqual(readFileSync(join(f.root, f.ledger)), ledger);
    assert.equal(f.git('ls-files', '--stage', '--', f.ledger), ledgerIndex);
    assert.match(result.stderr, /projection changed during ledger validation/);
    const retry = f.resolve();
    assert.equal(retry.status, 1, retry.stderr);
    assert.match(retry.stderr, /unstaged projection edits/);
    f.git('add', f.output);
    assert.equal(f.resolve().status, 0, 'staged reviewed inputs can be regenerated on retry');
    assert.deepEqual(JSON.parse(f.git('show', `:${f.ledger}`)).map(({ fingerprint }) => fingerprint),
      ['base', 'theirs', 'ours']);
  });
}

for (const problem of ['source conflict', 'missing guard', 'staged markers', 'no merge']) {
  test(`ledger repair refuses ${problem} without changing the projection, ledger or index`, (t) => {
    const f = ledgerMergeFixture(t, problem === 'source conflict');
    if (problem === 'missing guard' || problem === 'staged markers') {
      writeFileSync(join(f.root, 'model.ts'), problem === 'missing guard' ? 'guard removed\n' : `${f.anchor}\n<<<<<<< HEAD\n`);
      f.git('add', 'model.ts');
      writeFileSync(join(f.root, 'model.ts'), `${f.anchor}\n`);
    }
    if (problem === 'no merge') f.git('merge', '--abort');
    const before = [f.output, f.ledger].map((name) => readFileSync(join(f.root, name)));
    const index = f.git('ls-files', '--stage');
    const result = f.resolve();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, new RegExp({
      'source conflict': 'resolve source conflicts first: a.txt',
      'missing guard': 'missing guard anchor',
      'staged markers': 'staged conflict markers',
      'no merge': 'MERGE_HEAD',
    }[problem]));
    assert.equal(f.git('ls-files', '--stage'), index);
    assert.deepEqual([f.output, f.ledger].map((name) => readFileSync(join(f.root, name))), before);
    if (problem === 'no merge') return;
    if (problem === 'source conflict') {
      writeFileSync(join(f.root, 'a.txt'), 'reviewed source\n');
    }
    f.git('add', problem === 'source conflict' ? 'a.txt' : 'model.ts');
    const retry = f.resolve();
    assert.equal(retry.status, 0, retry.stderr);
  });
}
