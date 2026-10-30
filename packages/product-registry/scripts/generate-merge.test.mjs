import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  cpSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = 'apps/web/src/lib/generated/endpoints.generated.ts';
const registry = 'packages/product-registry/src/products/logyourbody.mjs';

function fixture(run) {
  const root = mkdtempSync(join(tmpdir(), 'product-merge-'));
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });
  const generate = (...args) =>
    spawnSync(process.execPath, ['packages/product-registry/scripts/generate.mjs', ...args], {
      cwd: root,
      encoding: 'utf8',
    });
  const write = (path, content) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), content);
  };
  try {
    cpSync(join(packageRoot, 'src'), join(root, 'packages/product-registry/src'), {
      recursive: true,
    });
    write(
      'packages/product-registry/scripts/generate.mjs',
      readFileSync(join(packageRoot, 'scripts/generate.mjs')),
    );
    symlinkSync(
      join(packageRoot, 'node_modules'),
      join(root, 'packages/product-registry/node_modules'),
    );
    git('init', '-b', 'base');
    git('config', 'user.name', 'Merge fixture');
    git('config', 'user.email', 'fixture@example.invalid');
    git('config', 'core.hooksPath', '/dev/null');
    assert.equal(generate().status, 0);
    git('add', '.');
    git('commit', '-m', 'base');
    run({ root, git, generate, write });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function conflict({ git, write }, paths) {
  const files = [paths].flat();
  git('switch', '-c', 'incoming');
  for (const path of files) write(path, 'incoming\n');
  git('add', '--', ...files);
  git('commit', '-m', 'incoming');
  git('switch', 'base');
  for (const path of files) write(path, 'branch\n');
  git('add', '--', ...files);
  git('commit', '-m', 'branch');
  assert.throws(() => git('merge', '--no-commit', 'incoming'));
}

test('merge repair regenerates and stages conflicted output from merged sources only', () =>
  fixture((f) => {
    conflict(f, output);
    const source = readFileSync(join(f.root, registry), 'utf8');
    f.write(
      registry,
      source.replace(
        'allowlist: [',
        'allowlist: [\n      { value: "fixture-parent-a", reason: "parent A" },\n      { value: "fixture-parent-b", reason: "parent B" },',
      ),
    );
    f.git('add', registry);
    const unrelated = 'docs/product/product-registry.generated.md';
    const stagedUnrelated = f.git('show', `:${unrelated}`);
    f.write(unrelated, 'preserve unstaged edits\n');
    f.write('notes.txt', 'preserve staged edits\n');
    f.git('add', 'notes.txt');
    const result = f.generate('--resolve-merge');
    assert.equal(result.status, 0, result.stderr);
    assert.equal(f.git('diff', '--name-only', '--diff-filter=U'), '');
    const staged = f.git('show', `:${output}`);
    assert.match(staged, /fixture-parent-a/);
    assert.match(staged, /fixture-parent-b/);
    assert.doesNotMatch(staged, /<<<<<<<|=======|>>>>>>>/);
    assert.equal(readFileSync(join(f.root, unrelated), 'utf8'), 'preserve unstaged edits\n');
    assert.equal(f.git('show', `:${unrelated}`), stagedUnrelated);
    assert.equal(f.git('show', ':notes.txt'), 'preserve staged edits\n');
    const index = f.git('write-tree');
    assert.equal(f.generate('--resolve-merge').status, 0);
    assert.equal(f.git('write-tree'), index);
  }));

test('merge repair refuses unresolved sources before writing any output', () =>
  fixture((f) => {
    conflict(f, 'unresolved.txt');
    f.write(output, 'preserve output on refusal\n');
    const before = readFileSync(join(f.root, output), 'utf8');
    const index = f.git('ls-files', '--stage');
    const result = f.generate('--resolve-merge');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /resolve source conflicts first/);
    assert.equal(readFileSync(join(f.root, output), 'utf8'), before);
    assert.equal(f.git('ls-files', '--stage'), index);
    assert.equal(f.git('diff', '--name-only', '--diff-filter=U').trim(), 'unresolved.txt');
  }));

test('merge repair resolves generated outputs before an independent correction ledger conflict', () =>
  fixture((f) => {
    const ledger = 'packages/shared-lib/corrections.json';
    conflict(f, [output, ledger]);
    const originalLedger = readFileSync(join(f.root, ledger), 'utf8');
    const ledgerStages = f.git('ls-files', '--stage', '--', ledger);
    const expectedOutput = f.git('show', `incoming~1:${output}`);
    const result = f.generate('--resolve-merge');
    assert.equal(result.status, 0, result.stderr);
    assert.equal(f.git('diff', '--name-only', '--diff-filter=U').trim(), ledger);
    assert.equal(f.git('show', `:${output}`), expectedOutput);
    assert.equal(f.git('ls-files', '--stage', '--', ledger), ledgerStages);
    assert.equal(readFileSync(join(f.root, ledger), 'utf8'), originalLedger);
    const index = f.git('ls-files', '--stage');
    assert.equal(f.generate('--resolve-merge').status, 0);
    assert.equal(f.git('ls-files', '--stage'), index, 'retry must leave the ledger unresolved');
    assert.equal(readFileSync(join(f.root, ledger), 'utf8'), originalLedger);
    f.write(ledger, '[]\n');
    f.git('add', ledger);
    assert.equal(f.generate('--check').status, 0);
  }));

test('merge repair requires an active merge and rejects check mode', () =>
  fixture((f) => {
    assert.notEqual(f.generate('--resolve-merge').status, 0);
    assert.notEqual(f.generate('--resolve-merge', '--check').status, 0);
  }));
