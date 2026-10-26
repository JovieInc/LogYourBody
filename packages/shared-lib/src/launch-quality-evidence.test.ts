import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

// The trace CLI swallows SystemExit. Keep coverage while propagating suite failures.
const driver = `
import runpy, sys, trace
test_path, coverage_dir = sys.argv[1:]
sys.argv = [test_path]
tracer = trace.Trace(count=True, trace=False, ignoredirs=[sys.prefix])
status = 0
try:
    tracer.runctx("runpy.run_path(test_path, run_name='__main__')",
                  {"runpy": runpy, "test_path": test_path}, {})
except SystemExit as error:
    status = error.code
finally:
    tracer.results().write_results(show_missing=True, summary=True, coverdir=coverage_dir)
sys.exit(status)
`;

function checkedTrace(test: string, coverage: string, root: string) {
  return execFileSync('python3', ['-c', driver, test, coverage], {
    encoding: 'utf8',
    cwd: root,
    timeout: 30_000,
  });
}

it('keeps replay and onboarding state fixtures free of UIKit and SwiftUI animation waits in DEBUG only', () => {
  const source = readFileSync(
    new URL('../../../apps/ios/LogYourBody/LogYourBodyApp.swift', import.meta.url),
    'utf8',
  );
  const debugBlocks = [...source.matchAll(/^[ \t]*#if DEBUG\n(.*?)^[ \t]*#endif/gms)]
    .map((match) => match[1])
    .join('\n');
  const policy = debugBlocks.match(
    /static func usesDeterministicUITestAnimations\(arguments: \[String\]\) -> Bool \{(.*?)\n {4}\}/s,
  )?.[1];
  expect(policy, 'a single DEBUG policy must cover both state fixtures').toBeDefined();
  for (const flag of ['-lybUITestChatReplayFixture', '-lybUITestBodyScoreOnboardingFixture']) {
    expect(policy).toContain(`arguments.contains("${flag}")`);
  }
  const condition = String.raw`if Self\.usesDeterministicUITestAnimations\(arguments: ProcessInfo\.processInfo\.arguments\) \{`;
  expect(debugBlocks).toMatch(
    new RegExp(`${condition}\\s*UIView\\.setAnimationsEnabled\\(false\\)`),
  );
  expect(debugBlocks).toMatch(
    new RegExp(
      `${condition}\\s*transaction\\.animation = nil\\s*transaction\\.disablesAnimations = true`,
    ),
  );
  expect(source.replace(/^[ \t]*#if DEBUG\n.*?^[ \t]*#endif/gms, '')).not.toContain(
    'usesDeterministicUITestAnimations',
  );
});

it('rejects incomplete XCTest proof through the launch gate validator with executed line coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const coverage = mkdtempSync(`${tmpdir()}/lyb-evidence-coverage-`);
  try {
    const output = checkedTrace(
      `${root}/scripts/ios/test_launch_quality_evidence.py`,
      coverage,
      root,
    );
    console.log(
      output
        .split('\n')
        .filter((line) => /launch-quality-evidence|behavior tests executed/.test(line))
        .join('\n'),
    );
    expect(output).toContain('Evidence validator behavior tests executed: 29');
    expect(output).toContain('launch-quality-evidence');
  } finally {
    rmSync(coverage, { recursive: true, force: true });
  }
}, 30_000);

it('propagates evidence assertion failures and nonzero exits despite passing suite markers', () => {
  const directory = mkdtempSync(`${tmpdir()}/lyb-evidence-failure-`);
  try {
    const test = `${directory}/failed.py`;
    writeFileSync(
      test,
      'import sys, unittest\n' +
        'class Failure(unittest.TestCase):\n' +
        '    def test_missing_canvas_execution(self):\n' +
        '        self.assertEqual(0, 1)\n' +
        'result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Failure))\n' +
        'print("Evidence validator behavior tests executed: 29")\n' +
        'sys.exit(0 if result.wasSuccessful() else 1)\n',
    );
    expect(() => checkedTrace(test, directory, directory)).toThrow(/AssertionError: 0 != 1/);
    writeFileSync(test, 'import sys\nsys.exit(7)\n');
    expect(() => checkedTrace(test, directory, directory)).toThrow(/Command failed/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
