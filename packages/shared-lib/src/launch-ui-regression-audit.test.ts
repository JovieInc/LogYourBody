import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('checks Stats composition and real card styling through the launch audit with executed coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const coverage = mkdtempSync(`${tmpdir()}/lyb-ui-audit-coverage-`);
  try {
    const pythonLibrary = execFileSync('python3', ['-c', 'import sys; print(sys.prefix)'], {
      encoding: 'utf8',
    }).trim();
    const output = execFileSync(
      'python3',
      [
        '-c',
        `import runpy, sys, trace
test, library, coverage = sys.argv[1:]
runner = trace.Trace(count=True, trace=False, ignoredirs=[library])
status = 0
sys.argv = [test]
try:
    runner.runctx("runpy.run_path(test, run_name='__main__')", {"runpy": runpy, "test": test}, {})
except SystemExit as error:
    status = error.code
finally:
    runner.results().write_results(show_missing=True, summary=True, coverdir=coverage)
sys.exit(status)
`,
        `${root}/scripts/ios/test_launch_ui_regression_audit.py`,
        pythonLibrary,
        coverage,
      ],
      { encoding: 'utf8', cwd: root, timeout: 30_000 },
    );
    console.log(
      output
        .split('\n')
        .filter((line) => /launch-ui-regression-audit|behavior tests executed/.test(line))
        .join('\n'),
    );
    expect(output).toContain('Launch UI audit behavior tests executed: 12');
    expect(output).toContain('launch-ui-regression-audit');
  } finally {
    rmSync(coverage, { recursive: true, force: true });
  }
}, 30_000);
