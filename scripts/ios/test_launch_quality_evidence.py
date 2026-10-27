"""Behavior tests for the exact validator called by the launch-quality gate."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('evidence', Path(__file__).with_name('launch-quality-evidence.py'))
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def test_fixed_diagnostic_selectors_have_native_test_implementations(self):
        root = Path(__file__).resolve().parents[2]
        source = (root / 'scripts/ios/launch-quality-audit.sh').read_text()
        block = source.split('DIAGNOSTIC_SEVEN_TESTS=(', 1)[1].split('\n)', 1)[0]
        selectors = re.findall(r'"(\w+/\w+)"', block)
        self.assertEqual(len(selectors), 7)
        self.assertEqual(len(set(selectors)), 7)
        for selector in selectors:
            suite, method = selector.split('/')
            with self.subTest(selector=selector):
                native_source = (root / f'apps/ios/LogYourBodyUITests/{suite}.swift').read_text()
                self.assertIsNotNone(
                    re.search(rf'\bfunc\s+{re.escape(method)}\s*\(\s*\)', native_source),
                    f'Missing native diagnostic implementation: {selector}',
                )

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / 'critical.xcresult'
        self.bundle.mkdir()
        self.bundle.with_suffix('.log').write_text('Running critical (attempt 1)\n')
        self.payload = {'testNodes': [{'nodeType': 'UI test bundle', 'children': [
            {'nodeType': 'Test Case', 'nodeIdentifier': identifier, 'result': 'Passed'}
            for identifier in evidence.REQUIRED_TESTS
        ]}], 'devices': [{'deviceId': 'simulator', 'osVersion': '26.5'}]}
        self.case = self.payload['testNodes'][0]['children'][0]
        # Expected ownership comes from the Swift capture sites, independently of the validator map.
        capture_groups = [
            (evidence.CRITICAL_TEST, ['launch-quality-chat-composer', 'launch-quality-chat-tab']),
            (evidence.ONBOARDING_TEST, ['launch-quality-onboarding-fixed-cta']),
            (evidence.FIRST_PHOTO_TEST, ['launch-quality-onboarding-first-photo']),
            (evidence.TIMELINE_TEST, ['launch-quality-home-timeline',
                                      'launch-quality-body-score-share', 'launch-quality-analytics']),
            (evidence.CANVAS_REDUCED_TEST, ['launch-quality-canvas-reduced-motion']),
            (evidence.CANVAS_REPLAY_TEST, ['launch-quality-canvas-replay-readback',
                                           'launch-quality-canvas-undo-readback']),
        ]
        self.manifest = [{'testIdentifier': identifier, 'attachments': []}
                         for identifier, _ in capture_groups]
        captures = [(group_index, name) for group_index, (_, names) in enumerate(capture_groups)
                    for name in names]
        for index, (group_index, name) in enumerate(captures):
            filename = f'{index}.png'
            (self.root / filename).write_bytes(b'\x89PNG\r\n\x1a\nfixture-payload')
            self.manifest[group_index]['attachments'].append({
                'exportedFileName': filename, 'suggestedHumanReadableName': name + '_0.png',
                'timestamp': 101, 'isAssociatedWithFailure': False,
                'deviceId': 'simulator', 'configurationName': 'Debug',
            })

    def validate(self):
        return evidence.validate_cases(self.payload, evidence.REQUIRED_TESTS)

    def captures(self):
        return evidence.validate_captures(self.manifest, self.root, 100)

    def test_native_function_coverage_rejects_missing_duplicate_unexecuted_partial_or_wrong_source(self):
        required = {'SettingsComponents.swift': ['SettingsRow.leadingContent.getter']}
        function = {'name': 'SettingsRow.leadingContent.getter', 'coveredLines': 35, 'executableLines': 35}
        source = {'name': 'SettingsComponents.swift', 'path': '/checkout/apps/ios/LogYourBody/SettingsComponents.swift',
                  'functions': [function]}
        payload = {'targets': [{'name': 'LogYourBody.app', 'files': [source]}]}
        self.assertEqual(evidence.validate_function_coverage(payload, required)[0]['coveredLines'], 35)
        variants = []
        for executed, total in [(0, 35), (34, 35), (0, 0), (None, 35), (35, None)]:
            item = copy.deepcopy(payload)
            item['targets'][0]['files'][0]['functions'][0].update(coveredLines=executed, executableLines=total)
            variants.append(item)
        missing = copy.deepcopy(payload)
        missing['targets'][0]['files'][0]['functions'] = []
        variants.append(missing)
        duplicate = copy.deepcopy(payload)
        duplicate['targets'][0]['files'][0]['functions'].append(copy.deepcopy(function))
        variants.append(duplicate)
        shadow = copy.deepcopy(payload)
        shadow['targets'][0]['files'][0]['path'] = '/tests/SettingsComponents.swift'
        variants.append(shadow)
        wrong_target = copy.deepcopy(payload)
        wrong_target['targets'][0]['name'] = 'LogYourBodyTests.xctest'
        variants.append(wrong_target)
        for item in variants:
            with self.subTest(item=item), self.assertRaises(ValueError):
                evidence.validate_function_coverage(item, required)

    def test_chaos_accounting_coverage_rejects_wrong_target_source_and_partial_execution(self):
        required = {'ChaosMonkeyUITests.swift': ['ChaosStepAccounting.record(_:)']}
        function = {'name': 'ChaosStepAccounting.record(_:)', 'coveredLines': 7, 'executableLines': 7}
        source = {'name': 'ChaosMonkeyUITests.swift',
                  'path': '/checkout/apps/ios/LogYourBodyUITests/ChaosMonkeyUITests.swift',
                  'functions': [function]}
        payload = {'targets': [{'name': 'LogYourBodyUITests.xctest', 'files': [source]}]}
        def validate(item):
            return evidence.validate_function_coverage(item, required,
                target_name='LogYourBodyUITests.xctest', source_root='LogYourBodyUITests')
        self.assertEqual(validate(payload)[0]['coveredLines'], 7)
        for mutation in ('partial', 'empty', 'wrong_target', 'wrong_source', 'duplicate'):
            item = copy.deepcopy(payload)
            target = item['targets'][0]
            file = target['files'][0]
            if mutation == 'partial':
                file['functions'][0]['coveredLines'] = 6
            elif mutation == 'empty':
                file['functions'][0].update(coveredLines=0, executableLines=0)
            elif mutation == 'wrong_target':
                target['name'] = 'LogYourBody.app'
            elif mutation == 'wrong_source':
                file['path'] = '/checkout/apps/ios/LogYourBody/ChaosMonkeyUITests.swift'
            else:
                file['functions'].append(copy.deepcopy(function))
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate(item)

    def test_passed_expected_case_and_all_seven_capture_hashes(self):
        self.assertEqual(self.validate()[0]['result'], 'Passed')
        captures = self.captures()
        self.assertEqual(len(captures), 10)
        self.assertEqual(captures[0]['sha256'], evidence.digest(self.root / '0.png'))

    def test_canvas_cases_must_both_pass(self):
        for identifier in (evidence.CANVAS_REDUCED_TEST, evidence.CANVAS_REPLAY_TEST):
            for result in ('Skipped', 'Failed', None):
                payload = copy.deepcopy(self.payload)
                case = next(item for item in payload['testNodes'][0]['children']
                            if item['nodeIdentifier'] == identifier)
                case['result'] = result
                with self.subTest(identifier=identifier, result=result), self.assertRaises(ValueError):
                    evidence.validate_cases(payload, evidence.REQUIRED_TESTS)

    def test_canvas_coverage_requires_the_actual_app_and_view_body(self):
        source = {'name': 'MesocycleCanvas.swift',
                  'path': '/checkout/apps/ios/LogYourBody/Views/MesocycleCanvas.swift',
                  'coveredLines': 600, 'executableLines': 1058,
                  'functions': [{'name': 'MesocycleCanvasContainer.body.getter',
                                 'coveredLines': 30, 'executableLines': 40}]}
        payload = {'targets': [{'name': 'LogYourBody.app', 'files': [source]}]}
        self.assertEqual(evidence.validate_canvas_coverage(payload)['coveredLines'], 600)
        for mutation in ('empty', 'model_only', 'missing_body', 'duplicate', 'wrong_target', 'wrong_path'):
            item = copy.deepcopy(payload)
            file = item['targets'][0]['files'][0]
            if mutation == 'empty':
                file['coveredLines'] = 0
            elif mutation == 'model_only':
                file['functions'][0]['coveredLines'] = 0
            elif mutation == 'missing_body':
                file['functions'] = []
            elif mutation == 'duplicate':
                item['targets'][0]['files'].append(copy.deepcopy(file))
            elif mutation == 'wrong_target':
                item['targets'][0]['name'] = 'LogYourBodyTests.xctest'
            else:
                file['path'] = '/tests/MesocycleCanvas.swift'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                evidence.validate_canvas_coverage(item)

    def test_canvas_cli_requires_executed_view_coverage_and_records_it(self):
        source = {'path': '/checkout/apps/ios/LogYourBody/Views/MesocycleCanvas.swift',
                  'coveredLines': 600, 'executableLines': 1058,
                  'functions': [{'name': 'MesocycleCanvasContainer.body.getter',
                                 'coveredLines': 30, 'executableLines': 40}]}
        coverage = {'targets': [{'name': 'LogYourBody.app', 'files': [source]}]}
        with patch.object(evidence, 'run_json', return_value=self.payload), \
             patch.object(evidence.subprocess, 'check_output', return_value=json.dumps(coverage)) as command:
            self.assertEqual(self.run_main(critical=False, canvas=True), 0)
        self.assertEqual(command.call_args.args[0],
                         ['xcrun', 'xccov', 'view', '--report', '--json', str(self.bundle)])
        receipt = json.loads(self.bundle.with_suffix('.evidence.json').read_text())
        self.assertEqual(receipt['canvasCoverage']['viewBody']['coveredLines'], 30)
        self.assertEqual(receipt['coverageSha256'], evidence.digest(self.bundle.with_suffix('.coverage.json')))
        source['functions'][0]['coveredLines'] = 0
        with patch.object(evidence, 'run_json', return_value=self.payload), \
             patch.object(evidence.subprocess, 'check_output', return_value=json.dumps(coverage)):
            self.assertEqual(self.run_main(critical=False, canvas=True), 65)
        self.assertFalse(self.bundle.with_suffix('.evidence.json').exists())

    def test_combined_runner_selects_and_validates_canvas_without_losing_inherited_cases(self):
        source = Path(__file__).with_name('launch-quality-audit.sh').read_text()
        selectors = source[source.index('LAUNCH_QUALITY_UI_TESTS=('):source.index('UI_RESULT_BUNDLE=')]
        command = 'set -euo pipefail\n' + selectors + '\nprintf "%s\\n" "${UI_SELECTORS[@]}" "${UI_EVIDENCE_ARGS[@]}"'
        output = subprocess.check_output(['bash', '-c', command], text=True).splitlines()
        # Preserve each inherited case, while allowing newly merged regressions.
        inherited_cases = (
            'LogYourBodyUITests/testLaunchQualityGateCapturesCriticalSurfaces',
            'LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFixedCTA',
            'LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFirstPhotoCTA',
            'LogYourBodyUITests/testLaunchQualityGateCapturesTimelineSurfaces',
            'LogYourBodyUITests/testProfileLogoutSignsOutFromPushedDetail',
            'OnboardingGoldenPathUITests/testBodyScoreOnboardingGoldenPathReachesReveal',
            'MesocycleCanvasUITests/testReducedMotionUsesStackedDayCards',
            'MesocycleCanvasUITests/testGoalThroughUndoKeepsTheCanvasAndReadbackTogether',
            'ChaosEdgeCaseUITests/testChaosLaunchForwardsActualXCTestConfiguration',
            'ChaosEdgeCaseUITests/testIntegrationDirectorySeparatesHealthAccessAndScanHistory',
            'ChaosEdgeCaseUITests/testAddEntryAccepts300CharacterNote',
            'ChaosEdgeCaseUITests/testAccessibilityXXXLHomeSettingsProfileHasNoLayoutAnomalies',
            'ChaosMonkeyUITests/testNativeScrollClippingRequiresActualScrollAncestor',
            'ChaosMonkeyUITests/testWeightEntryPhotoImportControlsAreExcludedFromMonkeyCandidates',
            'ChaosMonkeyUITests/testSystemAlertsRequireKnownDenyOnlyAction',
            'ChaosMonkeyUITests/testKeyboardDismissalPreservesDraftWithoutSending',
            'ChaosMonkeyUITests/testProfilePhotoImportIsExcludedFromMonkeyCandidates',
            'ChaosMonkeyUITests/testMissingActionTargetsDoNotCompleteMonkeySteps',
            'ChaosMonkeyUITests/testExecutedNativeActionsCompleteOnlyTheirOwnBudget',
            'ChaosMonkeyUITests/testFailedActionsExhaustAttemptsWithoutCompletion',
        )
        selected = [line.removeprefix('-only-testing:LogYourBodyUITests/')
                    for line in output if line.startswith('-only-testing:')]
        expected = [output[index + 1] for index, line in enumerate(output)
                    if line == '--expected-test']
        self.assertEqual(len(selected), len(set(selected)), 'A native case must be selected exactly once')
        self.assertCountEqual([identifier + '()' for identifier in selected], expected,
                              'Every selected native case must require its exact execution evidence')
        for identifier in inherited_cases:
            self.assertIn(identifier, selected)
        for identifier in evidence.REQUIRED_TESTS:
            self.assertIn('-only-testing:LogYourBodyUITests/' + identifier.removesuffix('()'), output)
            self.assertIn(identifier, output)
        self.assertIn('--require-canvas-coverage', source)
        swift = Path(__file__).resolve().parents[2] / 'apps/ios/LogYourBodyUITests/MesocycleCanvasUITests.swift'
        for name in evidence.REQUIRED_CAPTURES[-3:]:
            self.assertIn('attachScreenshot(named: "' + name + '"', swift.read_text())

    def test_zero_cases_and_all_skipped_rejected(self):
        for nodes in ([], [{'nodeType': 'Test Case', 'result': 'Skipped'}]):
            with self.subTest(nodes=nodes), self.assertRaises(ValueError):
                evidence.validate_cases({'testNodes': nodes}, [])

    def test_missing_wrong_or_duplicate_expected_identifier_rejected(self):
        for identifier in (None, 'AnotherSuite/testLaunchQualityGateCapturesCriticalSurfaces()'):
            self.case['nodeIdentifier'] = identifier
            with self.subTest(identifier=identifier), self.assertRaises(ValueError):
                self.validate()
        self.case['nodeIdentifier'] = evidence.CRITICAL_TEST
        self.payload['testNodes'].append(copy.deepcopy(self.case))
        with self.assertRaises(ValueError):
            self.validate()

    def test_failed_skipped_unknown_and_expected_failure_required_case_rejected(self):
        for result in ('Failed', 'Skipped', 'unknown', 'Expected Failure', None):
            self.case['result'] = result
            with self.subTest(result=result), self.assertRaises(ValueError):
                self.validate()

    def test_passing_parent_cannot_hide_nonpassing_repetition(self):
        for result in ('Failed', 'Skipped', 'unknown'):
            self.case['children'] = [{'nodeType': 'Test Case Run', 'result': result}]
            with self.subTest(result=result), self.assertRaises(ValueError):
                self.validate()

    def test_optional_unit_skips_remain_visible_without_counting_as_passes(self):
        self.payload['testNodes'].append({'nodeType': 'Test Case', 'result': 'Skipped',
                                         'nodeIdentifier': 'Optional/testKeychain()'})
        self.assertEqual([case['result'] for case in self.validate()], ['Passed'] * len(evidence.REQUIRED_TESTS) + ['Skipped'])

    def test_every_capture_is_required(self):
        for group_index, group in enumerate(self.manifest):
            for index in range(len(group['attachments'])):
                manifest = copy.deepcopy(self.manifest)
                del manifest[group_index]['attachments'][index]
                with self.subTest(group=group_index, index=index), self.assertRaises(ValueError):
                    evidence.validate_captures(manifest, self.root, 100)

    def test_duplicate_or_wrong_test_capture_manifest_rejected(self):
        for manifest in ([], self.manifest * 2, [{'testIdentifier': 'other', 'attachments': []}]):
            with self.subTest(manifest=manifest), self.assertRaises(ValueError):
                evidence.validate_captures(manifest, self.root, 100)

    def test_timeline_case_is_required_and_must_pass(self):
        cases = self.payload['testNodes'][0]['children']
        timeline = cases.pop()
        with self.assertRaises(ValueError):
            self.validate()
        cases.append(timeline)
        timeline['result'] = 'Skipped'
        with self.assertRaises(ValueError):
            self.validate()

    def test_capture_from_wrong_surface_test_cannot_satisfy_gate(self):
        self.manifest[0]['attachments'].append(self.manifest[1]['attachments'].pop())
        with self.assertRaises(ValueError):
            self.captures()

    def test_failed_stale_missing_and_ambiguous_capture_rejected(self):
        item = self.manifest[0]['attachments'][0]
        for key, value in (('isAssociatedWithFailure', True), ('isAssociatedWithFailure', None),
                           ('timestamp', None), ('timestamp', 99),
                           ('exportedFileName', '../outside.png'), ('exportedFileName', 'missing.png')):
            original = item[key]
            item[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.captures()
            item[key] = original
        self.manifest[0]['attachments'].append(copy.deepcopy(item))
        with self.assertRaises(ValueError):
            self.captures()

    def test_nonimage_cannot_count_as_screenshot(self):
        (self.root / '0.png').write_text('not an image')
        with self.assertRaises(ValueError):
            self.captures()

    def run_main(self, critical=True, expected=True, canvas=False):
        args = ['validator', '--bundle', str(self.bundle), '--started-at', '100']
        if expected:
            for identifier in evidence.REQUIRED_TESTS:
                args += ['--expected-test', identifier]
        if critical:
            args += ['--critical-captures']
        if canvas:
            args += ['--require-canvas-coverage']
        with patch.object(sys, 'argv', args):
            return evidence.main()

    def export(self, command, **kwargs):
        directory = Path(command[command.index('--output-path') + 1])
        (directory / 'manifest.json').write_text(json.dumps(self.manifest))
        for item in [item for group in self.manifest for item in group['attachments']]:
            filename = item['exportedFileName']
            (directory / filename).write_bytes((self.root / filename).read_bytes())
        return subprocess.CompletedProcess(command, 0)

    def test_cli_writes_fixture_only_receipt_with_live_verification_explicitly_missing(self):
        self.bundle.with_name('critical.attempt-1.xcresult').mkdir()
        (self.root / 'source-revision.txt').write_text('fixture-source-sha\n')
        (self.root / 'source-working-tree.patch').write_text('fixture-source-patch')
        with patch.object(evidence, 'run_json', return_value=self.payload), \
             patch.object(evidence.subprocess, 'run', side_effect=self.export):
            self.assertEqual(self.run_main(), 0)
        receipt = json.loads(self.bundle.with_suffix('.evidence.json').read_text())
        self.assertEqual(receipt['evidenceKind'], 'fixture_ui')
        self.assertTrue(receipt['recoveredAfterRetry'])
        self.assertEqual(receipt['sourceRevision'], 'fixture-source-sha')
        self.assertEqual(receipt['sourcePatchSha256'], evidence.digest(self.root / 'source-working-tree.patch'))
        self.assertEqual(receipt['exactDeployedBuild'], 'not_verified')
        self.assertEqual(set(receipt['liveVerification'].values()), {'not_verified'})
        self.assertEqual(len(receipt['captures']), 10)
        self.assertEqual(receipt['devices'], self.payload['devices'])

    def test_retry_without_first_result_bundle_still_reports_recovery(self):
        self.bundle.with_suffix('.log').write_text('Retrying critical after simulator launch failure\n')
        with patch.object(evidence, 'run_json', return_value=self.payload):
            self.assertEqual(self.run_main(critical=False), 0)
        receipt = json.loads(self.bundle.with_suffix('.evidence.json').read_text())
        self.assertTrue(receipt['recoveredAfterRetry'])
        self.assertIsNone(receipt['priorAttemptBundle'])

    def test_cli_rejects_partial_capture_and_removes_stale_pass(self):
        output = self.bundle.with_suffix('.evidence.json')
        output.write_text('{"status":"passed"}')
        self.manifest[0]['attachments'].pop()
        with patch.object(evidence, 'run_json', return_value=self.payload), \
             patch.object(evidence.subprocess, 'run', side_effect=self.export):
            self.assertEqual(self.run_main(), 65)
        self.assertFalse(output.exists())

    def test_cli_missing_bundle_unreadable_result_and_export_failure_rejected(self):
        for error in (ValueError('invalid JSON'), subprocess.CalledProcessError(1, 'xcrun')):
            with patch.object(evidence, 'run_json', side_effect=error):
                self.assertEqual(self.run_main(), 65)
        with patch.object(evidence, 'run_json', return_value=self.payload), \
             patch.object(evidence.subprocess, 'run', side_effect=OSError('export failed')):
            self.assertEqual(self.run_main(), 65)
        self.bundle.rmdir()
        self.assertEqual(self.run_main(), 65)

    def test_critical_captures_require_expected_identifier(self):
        with patch.object(evidence, 'run_json', return_value=self.payload):
            self.assertEqual(self.run_main(expected=False), 65)

    def test_unit_receipt_does_not_claim_ui_evidence(self):
        with patch.object(evidence, 'run_json', return_value=self.payload):
            self.assertEqual(self.run_main(critical=False), 0)
        receipt = json.loads(self.bundle.with_suffix('.evidence.json').read_text())
        self.assertEqual(receipt['evidenceKind'], 'unit_tests')
        self.assertFalse(receipt['recoveredAfterRetry'])
        self.bundle.with_suffix('.log').unlink()
        with patch.object(evidence, 'run_json', return_value=self.payload):
            self.assertEqual(self.run_main(critical=False), 0)
        receipt = json.loads(self.bundle.with_suffix('.evidence.json').read_text())
        self.assertEqual(receipt['recoveredAfterRetry'], 'unknown')

    def test_real_xcresult_invocation_uses_current_json_api(self):
        with patch.object(evidence.subprocess, 'check_output', return_value='{}') as command:
            self.assertEqual(evidence.run_json('get', 'test-results', 'tests'), {})
        self.assertEqual(command.call_args.args[0], ['xcrun', 'xcresulttool', 'get', 'test-results', 'tests'])

    def test_shell_rejects_nonempty_artifact_directory(self):
        script = Path(__file__).with_name('launch-quality-audit.sh')
        artifact = self.root / 'previous-proof'
        artifact.mkdir()
        prior = artifact / 'summary.md'
        prior.write_text('prior proof must survive')
        result = subprocess.run(['bash', str(script)], env={**os.environ, 'ARTIFACT_DIR': str(artifact)},
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 65)
        self.assertIn('Refusing to reuse', result.stderr)
        self.assertEqual(prior.read_text(), 'prior proof must survive')

    def test_shell_cold_build_budget_preserves_build_failures_and_timeout(self):
        source = Path(__file__).with_name('launch-quality-audit.sh').read_text()
        default = next(line for line in source.splitlines()
                       if line.startswith('BUILD_FOR_TESTING_TIMEOUT_SECONDS='))
        functions = source[source.index('build_for_testing_once() {'):
                           source.index('# A diagnostic subset never emits')]
        command = r"""
set -euo pipefail
COMMON_XCODEBUILD_ARGS=(-project fixture.xcodeproj -enableCodeCoverage YES)
XCODEBUILD_SETTINGS_ARRAY=(CODE_SIGNING_REQUIRED=NO)
cleanup_booted_simulator_apps() { :; }
xcodebuild() {
  printf '%s\n' "$@" > "$ARTIFACT_DIR/build-arguments"
  echo 'compiler output'
  return "$COMPILER_STATUS"
}
run_with_timeout() {
  echo "$1" >> "$ARTIFACT_DIR/build-attempts"
  # A virtual elapsed clock exercises the real budget without a 15-minute sleep.
  if (( BUILD_DURATION > $1 )); then return 124; fi
  shift
  "$@"
}
""" + default + '\n' + functions + r"""
build_for_testing_once
echo 'ready for native tests'
"""
        cases = [
            ('cold', '', 650, 0, 0),
            ('hung', '', 901, 0, 124),
            ('compiler-error', '', 100, 65, 65),
            ('override-timeout', '20', 21, 0, 124),
            ('override-success', '20', 19, 0, 0),
        ]
        for name, override, duration, compiler_status, expected in cases:
            with self.subTest(name=name):
                artifact = self.root / name
                artifact.mkdir()
                result = subprocess.run(
                    ['bash', '-c', command], capture_output=True, text=True, timeout=10,
                    env={**os.environ, 'ARTIFACT_DIR': str(artifact),
                         'BUILD_FOR_TESTING_TIMEOUT_SECONDS': override,
                         'BUILD_DURATION': str(duration), 'COMPILER_STATUS': str(compiler_status)})
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual(len((artifact / 'build-attempts').read_text().splitlines()), 1)
                self.assertEqual('ready for native tests' in result.stdout, expected == 0)
                log = (artifact / 'launch-quality-build-for-testing.log').read_text()
                if expected == 124:
                    self.assertIn('build-for-testing timed out after', log)
                else:
                    self.assertIn('compiler output', log)
                    self.assertEqual((artifact / 'build-arguments').read_text().splitlines(), [
                        '-project', 'fixture.xcodeproj', '-enableCodeCoverage', 'YES',
                        'CODE_SIGNING_REQUIRED=NO', 'build-for-testing',
                    ])

    def test_shell_preserves_failed_attempt_and_stops_after_two(self):
        # Execute the real function definitions without running the product build.
        # The extracted range includes the diagnostic launch probe. Its simctl
        # calls can block longer than this timeout while CoreSimulatorService
        # is still cold (CI run 38551518501), and they are not the retry contract.
        source = Path(__file__).with_name('launch-quality-audit.sh').read_text()
        functions = source[source.index('is_simulator_infra_failure() {'):source.index('assert_xcresult_evidence() {')]
        result_bundle = self.root / 'retry.xcresult'
        log = self.root / 'retry.log'
        command = r"""
set -euo pipefail
COMMON_XCODEBUILD_ARGS=(fixture)
XCODEBUILD_SETTINGS_ARRAY=(fixture)
XCODEBUILD_COMMAND_TIMEOUT_SECONDS=10
LQ_LAUNCH_PROBE=false
cleanup_booted_simulator_apps() { :; }
sleep() { :; }
run_with_timeout() {
  mkdir -p "$RESULT_BUNDLE"
  echo 'first attempt evidence' > "$RESULT_BUNDLE/receipt"
  echo 'Failed to install or launch the test runner'
  return 65
}
""" + functions + r"""
start_launch_probe() { :; }
stop_launch_probe() { :; }
run_xcodebuild_test fixture "$RESULT_BUNDLE" "$RESULT_LOG"
"""
        result = subprocess.run(['bash', '-c', command], capture_output=True, text=True, timeout=10,
                                env={**os.environ, 'RESULT_BUNDLE': str(result_bundle), 'RESULT_LOG': str(log)})
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertTrue(result_bundle.with_name('retry.attempt-1.xcresult').is_dir())
        self.assertTrue(result_bundle.is_dir())
        self.assertEqual(log.read_text().count('Running fixture (attempt '), 2)
        self.assertIn('first attempt evidence', (result_bundle.with_name('retry.attempt-1.xcresult') / 'receipt').read_text())

    def test_shell_does_not_retry_timeouts_or_started_tests(self):
        # Same probe stub as the retry test: simctl is outside this contract.
        source = Path(__file__).with_name('launch-quality-audit.sh').read_text()
        functions = source[source.index('is_simulator_infra_failure() {'):source.index('assert_xcresult_evidence() {')]
        result_bundle = self.root / 'timeout.xcresult'
        log = self.root / 'timeout.log'
        command = r"""
set -euo pipefail
COMMON_XCODEBUILD_ARGS=(fixture)
XCODEBUILD_SETTINGS_ARRAY=(fixture)
XCODEBUILD_COMMAND_TIMEOUT_SECONDS=10
LQ_LAUNCH_PROBE=false
cleanup_booted_simulator_apps() { :; }
sleep() { :; }
run_with_timeout() {
  mkdir -p "$RESULT_BUNDLE"
  printf '%s\n' "$FAILURE_LOG"
  return "$FAILURE_STATUS"
}
""" + functions + r"""
start_launch_probe() { :; }
stop_launch_probe() { :; }
run_xcodebuild_test fixture "$RESULT_BUNDLE" "$RESULT_LOG"
"""
        failures = [
            (124, 'xcodebuild command timed out after 720s'),
            (124, 'Failed to launch app\nxcodebuild command timed out after 720s'),
            (65, "Test Case '-[ChatTests testRetry]' exceeded execution time allowance of 3 minutes.\n"
                 'Restarting after unexpected exit, crash, or test timeout'),
            (65, "Test Case '-[ChatTests testRetry]' started.\nFailed to launch app"),
            (65, "Test Suite 'Selected tests' started at 2026-10-26.\nEarly unexpected exit"),
            (65, 'Restarting after unexpected exit, crash, or test timeout'),
        ]
        for index, (status, failure_log) in enumerate(failures):
            with self.subTest(status=status, failure_log=failure_log):
                directory = self.root / str(index)
                directory.mkdir()
                result_bundle = directory / 'timeout.xcresult'
                log = directory / 'timeout.log'
                result = subprocess.run(
                    ['bash', '-c', command], capture_output=True, text=True, timeout=10,
                    env={**os.environ, 'RESULT_BUNDLE': str(result_bundle), 'RESULT_LOG': str(log),
                         'FAILURE_STATUS': str(status), 'FAILURE_LOG': failure_log})
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertFalse(result_bundle.with_name('timeout.attempt-1.xcresult').exists())
                self.assertEqual(log.read_text().count('Running fixture (attempt '), 1)
                self.assertNotIn('Retrying fixture', log.read_text())


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(EvidenceTests)
    result = unittest.TextTestRunner().run(suite)
    print(f'Evidence validator behavior tests executed: {result.testsRun}')
    if not result.wasSuccessful() or result.testsRun == 0:
        sys.exit(1)
