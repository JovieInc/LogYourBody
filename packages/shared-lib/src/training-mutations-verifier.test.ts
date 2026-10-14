import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('executes training verifier safety and failure contracts with coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const coverage = mkdtempSync(`${tmpdir()}/lyb-training-verifier-coverage-`);
  try {
    const pythonLibrary = execFileSync('python3', ['-c', 'import sys; print(sys.prefix)'], {
      encoding: 'utf8',
    }).trim();
    const output = execFileSync(
      'python3',
      [
        '-m',
        'trace',
        '--count',
        '--summary',
        '--missing',
        '--ignore-dir',
        pythonLibrary,
        '--coverdir',
        coverage,
        `${root}/apps/web/db/tests/test_verify_training_mutations.py`,
      ],
      { encoding: 'utf8', cwd: root, timeout: 30_000 },
    );
    console.log(
      output
        .split('\n')
        .filter((line) => /verify-training-mutations|behavior tests executed/.test(line))
        .join('\n'),
    );
    expect(output).toContain('Training verifier behavior tests executed: 7');
    expect(output).toContain('verify-training-mutations');
  } finally {
    rmSync(coverage, { recursive: true, force: true });
  }
}, 30_000);
