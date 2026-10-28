import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('requires verified native text entry before testing draft preservation', () => {
  const source = readFileSync(
    new URL('../../../apps/ios/LogYourBodyUITests/ChaosMonkeyUITests.swift', import.meta.url),
    'utf8',
  );
  const typing =
    source.split('private func typeVerifiedText(')[1]?.split('private func performType(')[0] ?? '';
  expect(typing).toContain('NSPredicate(format: "value == %@", expected)');
  expect(typing).toContain('guard XCTWaiter.wait(for: [entered], timeout: 2) == .completed else');
  expect(typing).not.toMatch(/XCUIKeyboardKey.delete|UIPasteboard/);
  const turbo = JSON.parse(readFileSync(new URL('../turbo.json', import.meta.url), 'utf8'));
  expect(turbo.tasks.test.inputs).toContain('$TURBO_ROOT$/apps/ios/LogYourBodyUITests/**/*.swift');

  const probe = source
    .split('func testKeyboardDismissalPreservesDraftWithoutSending()')[1]
    .split('func testSystemAlertsRequireKnownDenyOnlyAction()')[0];
  const [setup, dismissal] = probe.split('dismissKeyboardForStep(');
  expect(setup).toContain('XCTAssertTrue(typeVerifiedText(draft, into: composer, app: app))');
  expect(setup).toContain('XCTAssertEqual(composer.value as? String, draft');
  expect(dismissal).toContain('XCTAssertEqual(composer.value as? String, draft');
  expect(dismissal).toContain('XCTAssertFalse(app.staticTexts[draft].exists');

  const action = source
    .split('private func performType(')[1]
    .split('private func performDismiss(')[0];
  expect(action).toContain(
    'guard typeVerifiedText(String(edge.prefix(24)), into: field, app: app) else',
  );
  expect(action).not.toContain('field.typeText(');
});

it('checks Stats composition and real card styling through the launch audit with executed coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const turbo = JSON.parse(readFileSync(new URL('../turbo.json', import.meta.url), 'utf8'));
  for (const input of [
    '$TURBO_ROOT$/scripts/ios/launch-ui-regression-audit.py',
    '$TURBO_ROOT$/scripts/ios/test_launch_ui_regression_audit.py',
    '$TURBO_ROOT$/apps/ios/LogYourBody/Components/FullMetricChartView+Part01.swift',
  ]) {
    expect(turbo.tasks.test.inputs).toContain(input);
  }
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
    expect(output).toContain('Launch UI audit behavior tests executed: 15');
    expect(output).toContain('launch-ui-regression-audit');
  } finally {
    rmSync(coverage, { recursive: true, force: true });
  }
}, 30_000);
