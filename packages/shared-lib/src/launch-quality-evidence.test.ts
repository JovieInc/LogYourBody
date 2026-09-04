import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('rejects incomplete XCTest proof through the launch gate validator with executed line coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const coverage = mkdtempSync(`${tmpdir()}/lyb-evidence-coverage-`);
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
        `${root}/scripts/ios/test_launch_quality_evidence.py`,
      ],
      { encoding: 'utf8', cwd: root, timeout: 30_000 },
    );
    console.log(
      output
        .split('\n')
        .filter((line) => /launch-quality-evidence|behavior tests executed/.test(line))
        .join('\n'),
    );
    expect(output).toContain('Evidence validator behavior tests executed: 18');
    expect(output).toContain('launch-quality-evidence');
  } finally {
    rmSync(coverage, { recursive: true, force: true });
  }
}, 30_000);
