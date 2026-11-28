import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { fixture } from './resolve-repository-docs-dependency.test.mjs';

for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
  for (const [scenario, quote, react, extra, refusal] of [
    ['unquoted mismatch', '', '19.3.0', '', /react-dom@19\.3\.1 requires matching react, got 19\.3\.0/],
    ['single-quoted mismatch', "'", '19.3.0', '', /react-dom@19\.3\.1 requires matching react, got 19\.3\.0/],
    ['double-quoted mismatch', '"', '19.3.0', '', /react-dom@19\.3\.1 requires matching react, got 19\.3\.0/],
    ['matching versions', '', '19.3.1', '', null],
    ['mixed runtimes', '', '19.3.1', '  react-dom@19.3.0(react@19.3.0): {}\n',
      /multiple React runtime versions: 19\.3\.0, 19\.3\.1/],
  ]) {
    test(`dependency repair ${mode} checks React renderer snapshots (${scenario})`, (t) => {
      const f = fixture(t, '.npmrc', 'staged');
      const lockfile = join(f.root, 'pnpm-lock.yaml');
      const output = join(f.root, 'SOURCES.md');
      const resolved = `snapshots:\n  ${quote}react-dom@19.3.1(react@${react})${quote}:\n    dependencies:\n      react: ${react}\n${extra}`;
      writeFileSync(join(f.root, 'package.json'), '{"dependencies":{"example":"2.0.0"}}\n');
      writeFileSync(join(f.root, 'resolved-lockfile'), resolved);
      if (mode === '--verify-lockfile') writeFileSync(lockfile, resolved);
      f.git('add', 'package.json', 'pnpm-lock.yaml');
      writeFileSync(join(f.root, 'bin/corepack'), `#!/bin/sh
echo "$*" >> pnpm-calls
case " $* " in
  *" --no-frozen-lockfile "*) cp resolved-lockfile pnpm-lock.yaml ;;
  *) cmp -s resolved-lockfile pnpm-lock.yaml || { echo ERR_PNPM_OUTDATED_LOCKFILE; exit 1; } ;;
esac
`, { mode: 0o755 });
      const index = f.git('ls-files', '--stage');
      const beforeLock = readFileSync(lockfile);
      const beforeProjection = readFileSync(output);
      const result = f.resolve(mode);
      assert.match(readFileSync(join(f.root, 'pnpm-calls'), 'utf8').trim().split('\n').at(-1),
        /--frozen-lockfile --offline$/);
      if (refusal) {
        assert.notEqual(result.status, 0, result.stdout);
        assert.match(result.stderr, refusal);
        assert.equal(f.git('ls-files', '--stage'), index);
        assert.deepEqual(readFileSync(lockfile), beforeLock);
        assert.deepEqual(readFileSync(output), beforeProjection);
      } else {
        assert.equal(result.status, 0, result.stderr);
        assert.equal(f.git('show', ':pnpm-lock.yaml'), resolved);
        assert.match(f.git('show', ':SOURCES.md'), /"example": "2\.0\.0"/);
      }
    });
  }
}
