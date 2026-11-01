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
  const loop = typing.split('for character in text {')[1] ?? '';
  const [focus, readback] = loop.split('field.typeText(String(character))');
  expect(focus).toMatch(
    /if !keyboard\.exists \{\s*field\.tap\(\)\s*guard keyboard\.waitForExistence\(timeout: 1\.5\) else \{ return false \}\s*\}/,
  );
  expect(focus.match(/waitForExistence/g)).toHaveLength(1);
  expect(readback).toMatch(
    /expected\.append\(character\)\s*if field\.value as\? String == expected \{ continue \}\s*let entered = XCTNSPredicateExpectation/,
  );
  expect(readback).toContain('attachDiagnostics(app: app, name: "incomplete-native-text-entry")');
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

it('checks Stats composition, card styling and provenance dismissal through the launch audit with executed coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const turbo = JSON.parse(readFileSync(new URL('../turbo.json', import.meta.url), 'utf8'));
  for (const input of [
    '$TURBO_ROOT$/scripts/ios/launch-ui-regression-audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_opacity_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch-ui-regression-report.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_timeline_day.py',
    '$TURBO_ROOT$/scripts/ios/test_launch_ui_regression_audit.py',
    '$TURBO_ROOT$/apps/ios/LogYourBodyWidget/**/*.swift',
    '$TURBO_ROOT$/apps/ios/LogYourBody/Components/FullMetricChartView+Part01.swift',
  ]) {
    expect(turbo.tasks.test.inputs).toContain(input);
  }
  const audit = readFileSync(
    new URL('../../../scripts/ios/launch-ui-regression-audit.py', import.meta.url),
    'utf8',
  );
  // launch audit keeps every size-ratchet sibling
  expect(audit).toContain('Cannot load launch UI audit sibling');
  expect(audit).toContain('_AUDIT_SIBLINGS');
  expect(audit).toContain('launch_ui_timeline_day.py');
  expect(audit).toContain('launch_ui_opacity_audit.py');
  expect(audit).toContain('launch-ui-regression-report.py');
  expect(audit).not.toMatch(/^def write_outputs\(/m);
  expect(audit).not.toMatch(/^def check_timeline_calendar_day\(/m);
  expect(audit).not.toMatch(/^def check_optional_cgfloat_opacity\(/m);
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
    const execution = output.match(/Launch UI audit behavior tests executed: (\d+)\/(\d+)/);
    expect(execution).not.toBeNull();
    expect(Number(execution?.[1])).toBeGreaterThan(0);
    expect(execution?.[1]).toBe(execution?.[2]);
    expect(output).toContain('launch-ui-regression-audit');
  } finally {
    rmSync(coverage, { recursive: true, force: true });
  }
}, 30_000);
