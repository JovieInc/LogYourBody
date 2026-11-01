import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import test from 'node:test';
import { classifyLedger, runClassifier } from './correction-classifier.mjs';

const commands = [['--resolve-merge'], ['--resolve-merge', '--stage'], ['--check-merge']];
for (const [args, target] of commands.flatMap((args) =>
  ['index', 'HEAD', 'MERGE_HEAD', 'ledger'].map((target) => [args, target]),
)) {
  test(`${args.join(' ')} refuses a changed ${target} and safely retries`, (t) => {
    const root = mkdtempSync(join(tmpdir(), 'lyb-classifier-concurrency-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const options = {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 5_000,
      env: { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' },
    };
    const git = (...args) => execFileSync('git', args, options);
    const ledger = join(root, 'packages/shared-lib/corrections.json');
    mkdirSync(join(root, 'packages/shared-lib'), { recursive: true });
    const rows = classifyLedger(
      JSON.parse(
        readFileSync(new URL('./fixtures/correction-classifier.json', import.meta.url)),
      ).slice(0, 3),
    );
    const writeLedger = (rows) => writeFileSync(ledger, `${JSON.stringify(rows, null, 2)}\n`);
    for (const { guard } of rows) writeFileSync(join(root, guard.path), guard.anchor);
    git('init', '--initial-branch=left');
    git('config', 'user.name', 'Ledger fixture');
    git('config', 'user.email', 'fixture@example.test');
    writeLedger([rows[0]]);
    git('add', '.');
    git('commit', '-m', 'test: base receipt');
    git('branch', 'right');
    writeLedger([rows[1], rows[0]]);
    git('commit', '-am', 'test: branch receipt');
    git('switch', 'right');
    writeLedger([rows[2], rows[0]]);
    git('commit', '-am', 'test: main receipt');
    git('switch', 'left');
    assert.equal(spawnSync('git', ['merge', '--no-commit', 'right'], options).status, 1);
    const quiet = { log() {}, error: (message) => assert.fail(message) };
    if (args[0] === '--check-merge') {
      assert.equal(runClassifier(['--resolve-merge', root, '--stage'], quiet), 0);
    }
    const original = readFileSync(ledger, 'utf8');
    const parent = ['index', 'ledger'].includes(target) ? null : git('rev-parse', target).trim();
    const replacement = parent && git('rev-parse', `${parent}^`).trim();
    const setParent = (value) => {
      if (target === 'MERGE_HEAD') {
        // MERGE_HEAD is a pseudoref; recent Git refuses update-ref writes to it.
        writeFileSync(resolve(root, git('rev-parse', '--git-path', target).trim()), `${value}\n`);
      } else {
        git('update-ref', target, value);
      }
      assert.equal(git('rev-parse', target).trim(), value, 'the parent mutation must take effect');
    };
    let changedIndex;
    let indexReads = 0;
    let diagnostic = '';
    const concurrentLedger = `${original}\nconcurrent ledger edit\n`;
    const command = [args[0], root, ...args.slice(1)];
    const status = runClassifier(
      command,
      {
        log() {},
        error: (message) => {
          diagnostic = message;
        },
      },
      (program, argv, options) => {
        const output = execFileSync(program, argv, options);
        if (argv.includes('ls-files')) indexReads += 1;
        if (
          argv.includes('ls-files') &&
          changedIndex === undefined &&
          (target !== 'ledger' || indexReads === 2)
        ) {
          if (target === 'index') {
            writeFileSync(join(root, 'concurrent.txt'), 'another writer\n');
            git('add', 'concurrent.txt');
          } else if (target === 'ledger') {
            // Edit after the last index read, without changing either staged bytes or parents.
            writeFileSync(ledger, concurrentLedger);
          } else {
            // Parent refs can change without changing a single indexed byte.
            setParent(replacement);
          }
          changedIndex = git('ls-files', '--stage', '-z');
        }
        return output;
      },
    );
    assert.notEqual(changedIndex, undefined, `the negative control must run: ${diagnostic}`);
    assert.equal(status, 1, 'changed merge evidence cannot receive a successful verdict');
    assert.match(
      diagnostic,
      target === 'index'
        ? /merge index changed during validation/
        : target === 'ledger'
          ? /merge ledger changed during validation/
          : /merge parents changed during validation/,
    );
    assert.equal(
      readFileSync(ledger, 'utf8'),
      target === 'ledger' ? concurrentLedger : original,
      'refusal preserves the ledger, including another writer’s edits',
    );
    assert.equal(
      git('ls-files', '--stage', '-z'),
      changedIndex,
      'refusal preserves the other writer',
    );
    if (parent) {
      assert.equal(git('rev-parse', target).trim(), replacement, 'refusal preserves the writer');
      setParent(parent);
    }
    if (target === 'ledger') writeFileSync(ledger, original);
    assert.equal(runClassifier(command, quiet), 0, 'retry validates current merge evidence');
    assert.deepEqual(JSON.parse(readFileSync(ledger, 'utf8')), [rows[2], rows[0], rows[1]]);
    if (target === 'index') assert.equal(git('show', ':0:concurrent.txt'), 'another writer\n');
  });
}
