import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

it('captures chaos candidate attributes once per discovery without weakening photo-import safety', () => {
  const source = readFileSync(
    new URL('../../../apps/ios/LogYourBodyUITests/ChaosMonkeyUITests.swift', import.meta.url),
    'utf8',
  );
  const discovery =
    source.split('private func snapshotElements(')[1]?.split('/// `.isHittable`')[0] ?? '';
  // Native run 43355101470 resolved elements 736 and 571 times in the two
  // photo-import probes. Attribute reads during filtering must use one capture.
  expect(discovery).toContain('throws -> StepSnapshot');
  expect(discovery).toContain('let captured = try elements.map');
  expect(discovery).toContain('(element: element, attributes: try element.snapshot())');
  expect(discovery.match(/\.snapshot\(\)/g)).toHaveLength(1);
  const filters = discovery.split('let protectedFrames =')[1] ?? '';
  expect(filters).not.toMatch(/\belement\.(?:frame|identifier|label|elementType)\b/);
  expect(filters).not.toMatch(
    /(?:hasFiniteNonZeroFrame|isDenylisted)\((?:element|candidate\.element)\)/,
  );
  expect(filters).toContain('captured.compactMap');
  expect(filters).toContain('attributes.elementType == .button');
  expect(filters).toContain('isDenylisted(attributes), hasFiniteNonZeroFrame(attributes)');
  expect(filters).toContain('attributes.frame.intersects(windowFrame)');
  expect(filters).toContain('!isDenylisted(attributes), attributes.elementType != .key');
  expect(filters).toContain('attributes.elementType == .other || attributes.elementType == .cell');
  expect(filters).toContain('protectedFrames.contains(where: { $0.intersects(attributes.frame) })');
  expect(filters).toContain('return candidate.element.isHittable ? candidate.element : nil');
  expect(discovery).not.toMatch(/try[!?]|catch/);
  expect(source.match(/try snapshotElements\(in: app\)/g)).toHaveLength(4);
  expect(source).toContain('hasFiniteNonZeroFrame(_ element: XCUIElementAttributes)');
  expect(source).toContain('isDenylisted(_ element: XCUIElementAttributes)');
});

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
  expect(audit).toContain('uitest.progress_share_readiness');
  expect(audit).toContain('check_progress_share_readiness(root, violations, violation)');
  expect(audit).toContain('uitest.nested_launch_time_allowance');
  expect(audit).toContain('uitest.synthetic_chat_lifecycle_time_allowance');
  expect(audit).toContain('uitest.viewer_history_navigation');
  expect(audit).toContain('check_viewer_history_navigation(root, violations, violation)');
  expect(audit).toContain('check_character_type_keyboard_focus(root, violations, violation)');
  expect(audit).toContain('check_nested_launch_time_allowance(root, violations, violation)');
});

it('waits for exact metric text and Save readiness before testing Home check-in outcomes', () => {
  const source = readFileSync(
    new URL('../../../apps/ios/LogYourBodyUITests/HomeV2LayoutUITests.swift', import.meta.url),
    'utf8',
  );
  const method = (name: string) =>
    source.split(`func ${name}(`)[1]?.split(/\n {4}(?:private )?func /)[0] ?? '';
  // Run 42854027238: 17.0 was visible in the recording, but the immediate
  // enabled snapshot still saw Save disabled after the delete/type transaction.
  const readiness = method('assertSaveReady');
  expect(readiness).toContain('NSPredicate(format: "enabled == true AND hittable == true")');
  expect(readiness).toContain('evaluatedWith: save');
  expect(readiness).toContain('XCTWaiter.wait(for: [ready], timeout: 5), .completed');
  const replacement = method('replacePrefilledText');
  expect(replacement).toContain('XCTAssertTrue(isFieldCleared(field),');
  expect(replacement.indexOf('XCTAssertTrue(isFieldCleared(field),')).toBeLessThan(
    replacement.indexOf('field.typeText(replacement)'),
  );
  expect(replacement).toContain('NSPredicate(format: "value == %@", replacement)');
  expect(replacement).toContain('XCTWaiter.wait(for: [entered], timeout: 5), .completed');
  for (const name of [
    'testLogSheetEditsUnitsWithKeyboardAndCancelsWithoutChangingHome',
    'testBodyFatCheckInRefreshesDataHeroWithoutSavingWeight',
    'testBodyFatEditorAtLargestTextPreservesMethodUntilExplicitSelection',
  ]) {
    const body = method(name);
    expect(body).toContain('replacePrefilledText(');
    expect(body).toContain('assertSaveReady(save)');
    expect(body).not.toContain('field.typeText(');
    expect(body.indexOf('replacePrefilledText(')).toBeLessThan(
      body.indexOf('assertSaveReady(save)'),
    );
    if (body.includes('save.tap()')) {
      expect(body.indexOf('assertSaveReady(save)')).toBeLessThan(body.indexOf('save.tap()'));
    }
  }
});

it('waits for a stable hittable sidebar before each single dismissal tap', () => {
  const source = readFileSync(
    new URL(
      '../../../apps/ios/LogYourBodyUITests/HomeV2TimelineIntegrationUITests.swift',
      import.meta.url,
    ),
    'utf8',
  );
  const helper =
    source.split('private func dismissSidebar(')[1]?.split('\n    private func ')[0] ?? '';
  expect(helper).toContain('guard scrim.exists, scrim.isHittable else { return false }');
  expect(helper).toContain('var previousFrame = CGRect.null');
  expect(helper).toContain('let frame = scrim.frame');
  expect(helper).toContain('defer { previousFrame = frame }');
  expect(helper).toContain(
    '!frame.isEmpty && window.frame.contains(frame) && frame == previousFrame',
  );
  expect(helper).toContain('XCTWaiter.wait(for: [ready], timeout: 5), .completed');
  expect(helper).toContain(
    'window.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()',
  );
  expect(helper.match(/\.tap\(\)/g)).toHaveLength(1);
  expect(helper.indexOf('XCTWaiter.wait(')).toBeLessThan(helper.indexOf('.tap()'));
  expect(helper).toContain('XCTAssertTrue(scrim.waitForNonExistence(timeout: 5))');
  expect(helper.indexOf('.tap()')).toBeLessThan(helper.indexOf('scrim.waitForNonExistence('));
  const journey = source
    .split('func testPhotoScrubResetsWhenNavigatingToTheMenuAndBack()')[1]
    .split('\n    func ')[0];
  expect(journey).toContain('for _ in 0..<3 {');
  expect(journey.match(/dismissSidebar\(scrim, in: app\)/g)).toHaveLength(2);
  expect(journey).not.toContain('scrim.coordinate(');
  expect(journey).toContain('"Header swipes must still open the sidebar"');
  expect(journey).toContain('app.buttons["home_v2_viewer_close"].waitForExistence(timeout: 5)');
});

it('checks Stats composition, card styling and provenance dismissal through the launch audit with executed coverage', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const turbo = JSON.parse(readFileSync(new URL('../turbo.json', import.meta.url), 'utf8'));
  for (const input of [
    '$TURBO_ROOT$/scripts/ios/launch-ui-regression-audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_*.py',
    '$TURBO_ROOT$/packages/shared-lib/scripts/company-size-ratchet.mjs',
    '$TURBO_ROOT$/packages/shared-lib/scripts/company-size-ratchet.behavior.mjs',
    '$TURBO_ROOT$/.company-guards/size-baseline.json',
    '$TURBO_ROOT$/scripts/ios/launch_ui_opacity_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_timeline_gesture_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_home_interaction_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_offline_pin_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch_ui_dated_stats_audit.py',
    '$TURBO_ROOT$/scripts/ios/launch-ui-regression-report.py',
    '$TURBO_ROOT$/scripts/ios/test_launch_ui_regression_audit.py',
    '$TURBO_ROOT$/scripts/ios/test_launch_ui_audit_support.py',
    '$TURBO_ROOT$/scripts/ios/test_launch_ui_home_interaction.py',
    '$TURBO_ROOT$/apps/ios/LogYourBodyWidget/**/*.swift',
    '$TURBO_ROOT$/apps/ios/LogYourBody/Components/FullMetricChartView+Part01.swift',
  ]) {
    expect(turbo.tasks.test.inputs).toContain(input);
  }
  const audit = readFileSync(
    new URL('../../../scripts/ios/launch-ui-regression-audit.py', import.meta.url),
    'utf8',
  );
  // launch audit loads every size-ratchet check sibling
  expect(audit).toContain('Cannot load launch UI audit sibling');
  expect(audit).toContain('launch_ui_*.py');
  expect(audit).toContain('def load_check_siblings');
  expect(audit).toContain('_AUDIT_SIBLINGS');
  expect(audit).toContain('launch_ui_timeline_day.py');
  expect(audit).toContain('launch_ui_opacity_audit.py');
  expect(audit).toContain('launch_ui_timeline_gesture_audit.py');
  expect(audit).toContain('launch_ui_offline_pin_audit.py');
  expect(audit).toContain('check_ui_test_offline_pin');
  expect(audit).toContain('launch_ui_dated_stats_audit.py');
  expect(audit).toContain('launch-ui-regression-report.py');
  expect(audit).not.toMatch(/^def write_outputs\(/m);
  expect(audit).not.toMatch(/^def check_timeline_calendar_day\(/m);
  expect(audit).not.toMatch(/^def check_home_interaction\(/m);
  expect(audit).not.toMatch(/^def check_optional_cgfloat_opacity\(/m);
  expect(audit).not.toMatch(/^def check_timeline_gestures\(/m);
  readFileSync(
    new URL('../../../scripts/ios/launch_ui_home_interaction_audit.py', import.meta.url),
  );
  readFileSync(new URL('../../../scripts/ios/launch_ui_timeline_day.py', import.meta.url));
  const opacity = readFileSync(
    new URL('../../../scripts/ios/launch_ui_opacity_audit.py', import.meta.url),
    'utf8',
  );
  expect(opacity).toContain('def contribute');
  const gesture = readFileSync(
    new URL('../../../scripts/ios/launch_ui_timeline_gesture_audit.py', import.meta.url),
    'utf8',
  );
  expect(gesture).toContain('def contribute');
  expect(audit).not.toMatch(/^def check_ui_test_offline_pin\(/m);
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

it('repairs additive audit and manifest conflicts while rejecting lost parent checks', () => {
  const output = execFileSync(
    process.execPath,
    [
      '--test',
      'scripts/resolve-repository-docs-manifest.test.mjs',
      'scripts/resolve-repository-docs-json.test.mjs',
    ],
    { cwd: fileURLToPath(new URL('../../..', import.meta.url)), encoding: 'utf8', timeout: 30_000 },
  );
  expect(output).toContain('# fail 0');
  expect(output).toContain('manifest union keeps both launch-audit sibling registrations');
  expect(output).toContain(
    'manifest union refuses a non-additive launch-audit conflict without staging',
  );
}, 30_000);
