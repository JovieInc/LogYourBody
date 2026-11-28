import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { fixture } from './resolve-repository-docs-dependency.test.mjs';

const mismatch = (setting) =>
  `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH Cannot proceed with the frozen installation. The current "${setting}" configuration doesn't match the value found in the lockfile`;

for (const [name, diagnostic, canRefresh] of [
  ['outdated manifest', 'ERR_PNPM_OUTDATED_LOCKFILE', true],
  ['override mismatch', mismatch('overrides'), true],
  ['catalog mismatch', mismatch('catalogs'), false],
  ['patch mismatch', mismatch('patchedDependencies'), false],
  ['unqualified mismatch', 'ERR_PNPM_LOCKFILE_CONFIG_MISMATCH', false],
  ['authentication failure', 'ERR_PNPM_FETCH_401', false],
  ['registry failure', 'ERR_PNPM_FETCH_503', false],
  ['corrupt lockfile', 'ERR_PNPM_BROKEN_LOCKFILE', false],
  ['multiple errors', `ERR_PNPM_FETCH_401\n${mismatch('overrides')}`, false],
]) {
  for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
    test(`dependency repair ${mode} handles ${name} without relaxing frozen verification`, (t) => {
      const f = fixture(t, '.pnpmfile.cjs', 'staged');
      writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
import json
import sys
from pathlib import Path
lock = Path('pnpm-lock.yaml')
with Path('pnpm-calls').open('a') as calls:
    calls.write(json.dumps(sys.argv[1:]) + '\\n')
if '--no-frozen-lockfile' in sys.argv:
    lock.write_text('resolved lockfile\\n')
elif lock.read_text() != 'resolved lockfile\\n':
    print(${JSON.stringify(diagnostic)})
    sys.exit(1)
`, { mode: 0o755 });
      const index = f.git('ls-files', '--stage');
      const artifacts = ['pnpm-lock.yaml', 'SOURCES.md'];
      const outputs = artifacts.map((name) => readFileSync(join(f.root, name)));
      const result = f.resolve(mode);
      const calls = readFileSync(join(f.root, 'pnpm-calls'), 'utf8')
        .trim().split('\n').map((line) => JSON.parse(line));
      const frozen = ['--frozen-lockfile', '--offline'];
      if (mode === '--refresh-lockfile' && canRefresh) {
        assert.equal(result.status, 0, result.stderr);
        assert.deepEqual(calls.map((args) => args.slice(4)), [
          frozen, ['--no-frozen-lockfile'], frozen,
        ]);
        assert.equal(f.git('show', ':pnpm-lock.yaml'), 'resolved lockfile\n');
        assert.equal(f.git('show', ':SOURCES.md'), readFileSync(join(f.root, 'SOURCES.md'), 'utf8'));
      } else {
        assert.notEqual(result.status, 0, result.stdout);
        assert.deepEqual(calls.map((args) => args.slice(4)), [frozen]);
        assert.equal(f.git('ls-files', '--stage'), index);
        for (const [i, name] of artifacts.entries()) {
          assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
          assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
        }
      }
      for (const args of calls) {
        assert.deepEqual(args.slice(0, 4), ['pnpm', 'install', '--lockfile-only', '--ignore-scripts']);
      }
    });
  }
}
