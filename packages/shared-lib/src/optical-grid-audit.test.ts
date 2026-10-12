import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('enforces optical-grid regression and shrink-only baseline behavior with executed coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const coverage = mkdtempSync(`${tmpdir()}/lyb-grid-coverage-`);
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
        `${root}/scripts/ios/test_optical_grid_audit.py`,
      ],
      { encoding: 'utf8', cwd: root, timeout: 30_000 },
    );
    console.log(
      output
        .split('\n')
        .filter((line) => /optical-grid-audit|behavior tests executed/.test(line))
        .join('\n'),
    );
    expect(output).toContain('Optical grid behavior tests executed: 7');
    expect(output).toContain('optical-grid-audit');
  } finally {
    rmSync(coverage, { recursive: true, force: true });
  }
}, 30_000);
