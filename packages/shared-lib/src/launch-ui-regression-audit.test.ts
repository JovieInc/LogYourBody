import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('keeps voice hardware dormant during ordinary chat construction and dismissal', () => {
  const source = readFileSync(
    new URL('../../../apps/ios/LogYourBody/Services/VoiceCaptureService.swift', import.meta.url),
    'utf8',
  );
  const capture =
    source.split('final class VoiceCaptureService {')[1]?.split('enum VoiceCoachPolicy')[0] ?? '';
  expect(capture).toMatch(/@ObservationIgnored\s+private lazy var audioEngine/);
  expect(capture.split('func start()')[0]).not.toMatch(
    /(?:let|var) recognizer[^\n]*=\s*SFSpeechRecognizer/,
  );
  const start = capture.split('func start()')[1]?.split('func finish()')[0] ?? '';
  expect(start.indexOf('try await requestPermissions()')).toBeGreaterThan(-1);
  expect(start.indexOf('SFSpeechRecognizer(locale:')).toBeGreaterThan(
    start.indexOf('try await requestPermissions()'),
  );
  const cancel =
    capture.split('func cancel()')[1]?.split('private func requestPermissions()')[0] ?? '';
  expect(cancel).toMatch(
    /if request != nil \{\s*audioEngine\.stop\(\)\s*audioEngine\.inputNode\.removeTap\(onBus: 0\)\s*try\? AVAudioSession\.sharedInstance\(\)\.setActive\(false, options: \.notifyOthersOnDeactivation\)\s*\}/,
  );
  expect(cancel.match(/audioEngine/g)).toHaveLength(2);
  expect(cancel.match(/AVAudioSession/g)).toHaveLength(1);
  const playback = readFileSync(
    new URL('../../../apps/ios/LogYourBody/Services/VoicePlaybackService.swift', import.meta.url),
    'utf8',
  );
  expect(playback).toMatch(/private lazy var synthesizer/);
  expect(playback).not.toMatch(/(?:let|var) synthesizer[^\n]*=\s*AVSpeechSynthesizer\(\)/);
  const turbo = JSON.parse(readFileSync(new URL('../turbo.json', import.meta.url), 'utf8'));
  for (const file of ['VoiceCaptureService.swift', 'VoicePlaybackService.swift']) {
    expect(turbo.tasks.test.inputs).toContain(`$TURBO_ROOT$/apps/ios/LogYourBody/Services/${file}`);
  }
});

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
    /if !focused\.exists \{\s*field\.tap\(\)\s*guard focused\.waitForExistence\(timeout: 1\.5\) else \{ return false \}\s*\}/,
  );
  expect(focus.match(/waitForExistence/g)).toHaveLength(1);
  expect(readback).toMatch(
    /expected\.append\(character\)\s*if field\.value as\? String == expected \{ continue \}\s*let entered = XCTNSPredicateExpectation/,
  );
  expect(readback).toContain('attachDiagnostics(app: app, name: "incomplete-native-text-entry")');
  expect(typing).toContain('.matching(NSPredicate(format: "hasKeyboardFocus == true"))');
  expect(typing).not.toContain('if !keyboard.exists');
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

it('keeps paced chat typing focused and gives nested launch scenarios the audit time cap', () => {
  const tests = readFileSync(
    new URL('../../../apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift', import.meta.url),
    'utf8',
  );
  const typing =
    tests
      .split('for character in addition {')[1]
      ?.split('composer.typeText(String(character))')[0] ?? '';
  expect(typing).toContain('hasKeyboardFocus == true');
  expect(typing).toContain('if !focused.exists');
  expect(typing).toContain('guard focused.waitForExistence(timeout: 2) else { break }');
  const timeline =
    tests
      .split('func testLaunchQualityGateCapturesTimelineSurfaces()')[1]
      ?.split('try testDatedTimelineManualBaselineAndInterruptedPhotoReturn()')[0] ?? '';
  expect(timeline).toContain('executionTimeAllowance = 180');
  const audit = readFileSync(
    new URL('../../../scripts/ios/launch_ui_home_interaction_audit.py', import.meta.url),
    'utf8',
  );
  expect(audit).toContain('uitest.character_type_keyboard_focus');
  expect(audit).toContain('uitest.nested_launch_time_allowance');
  expect(audit).toContain('uitest.viewer_history_navigation');
  expect(audit).toContain('check_viewer_history_navigation(root, violations, violation)');
  expect(audit).toContain('check_character_type_keyboard_focus(root, violations, violation)');
  expect(audit).toContain('check_nested_launch_time_allowance(root, violations, violation)');
});

it('checks Stats composition, card styling and provenance dismissal through the launch audit with executed coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const turbo = JSON.parse(readFileSync(new URL('../turbo.json', import.meta.url), 'utf8'));
  for (const input of [
    '$TURBO_ROOT$/scripts/ios/launch-ui-regression-audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_opacity_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_timeline_gesture_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_home_interaction_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_dated_stats_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch-ui-regression-report.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_timeline_day.py',
    '$TURBO_ROOT$/scripts/ios/test_launch_ui_regression_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_audit_test_support.py',
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
  expect(audit).toContain('launch_ui_timeline_gesture_audit.py');
  expect(audit).toContain('launch_ui_dated_stats_audit.py');
  expect(audit).toContain('launch-ui-regression-report.py');
  expect(audit).not.toMatch(/^def write_outputs\(/m);
  expect(audit).not.toMatch(/^def check_timeline_calendar_day\(/m);
  expect(audit).not.toMatch(/^def check_optional_cgfloat_opacity\(/m);
  expect(audit).not.toMatch(/^def check_timeline_gestures\(/m);
  expect(audit).not.toMatch(/^def check_dated_stats_fixture\(/m);
  // The parent audit stays within the company 500-line ratchet.
  const parentLines = audit.endsWith('\n') ? audit.slice(0, -1).split('\n') : audit.split('\n');
  expect(parentLines.length).toBeLessThanOrEqual(500);
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
