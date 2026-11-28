import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { fixture } from './resolve-repository-docs-dependency.test.mjs';

export function testFrozenLockfilePreservation(fixture) {
  for (const scenario of ['verify', 'current', 'refresh', 'failed-probe']) {
    for (const mutation of ['rewrite', 'delete']) {
      test(`dependency repair refuses frozen lockfile ${mutation} after ${scenario}`, (t) => {
        const f = fixture(t, '.pnpmfile.cjs', 'staged');
        const index = f.git('ls-files', '--stage');
        const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
        writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
import sys
from pathlib import Path
lock = Path('pnpm-lock.yaml')
if '--no-frozen-lockfile' in sys.argv:
    Path('regenerated').touch()
    lock.write_text('refreshed resolutions\\n')
elif ${scenario === 'refresh' ? 'True' : 'False'} and lock.read_text() == 'reviewed lockfile\\n':
    print('ERR_PNPM_OUTDATED_LOCKFILE')
    sys.exit(1)
elif ${mutation === 'delete' ? 'True' : 'False'}:
    lock.unlink()
else:
    lock.write_text('unexpected frozen resolutions\\n')
if ${scenario === 'failed-probe' ? 'True' : 'False'}:
    print('ERR_PNPM_OUTDATED_LOCKFILE')
    sys.exit(1)
`, { mode: 0o755 });
        const result = f.resolve(scenario === 'verify' ? '--verify-lockfile' : '--refresh-lockfile');
        assert.notEqual(result.status, 0, 'a frozen lockfile mutation must fail closed');
        assert.match(result.stderr, /frozen verification changed pnpm-lock\.yaml/);
        if (scenario === 'failed-probe') {
          assert.equal(existsSync(join(f.root, 'regenerated')), false, 'a mutated probe cannot authorize regeneration');
        }
        if (scenario === 'refresh') {
          assert.equal(existsSync(join(f.root, 'regenerated')), true, 'the final frozen step follows regeneration');
        }
        assert.equal(f.git('ls-files', '--stage'), index);
        for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
          assert.deepEqual(readFileSync(join(f.root, name)), outputs[i], 'failed repairs restore original artifacts');
        }
      });
    }
  }
}

testFrozenLockfilePreservation(fixture);
