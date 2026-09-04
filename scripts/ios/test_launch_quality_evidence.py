"""Behavior tests for the exact validator called by the launch-quality gate."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('evidence', Path(__file__).with_name('launch-quality-evidence.py'))
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / 'critical.xcresult'
        self.bundle.mkdir()
        self.payload = {'testNodes': [{'nodeType': 'UI test bundle', 'children': [
            {'nodeType': 'Test Case', 'nodeIdentifier': evidence.CRITICAL_TEST, 'result': 'Passed'}
        ]}], 'devices': [{'deviceId': 'simulator', 'osVersion': '26.5'}]}
        self.case = self.payload['testNodes'][0]['children'][0]
        self.manifest = [{'testIdentifier': evidence.CRITICAL_TEST, 'attachments': []}]
        for index, name in enumerate(evidence.REQUIRED_CAPTURES):
            filename = f'{index}.png'
            (self.root / filename).write_bytes(b'\x89PNG\r\n\x1a\nfixture-payload')
            self.manifest[0]['attachments'].append({
                'exportedFileName': filename, 'suggestedHumanReadableName': name + '_0.png',
                'timestamp': 101, 'isAssociatedWithFailure': False,
                'deviceId': 'simulator', 'configurationName': 'Debug',
            })

    def validate(self):
        return evidence.validate_cases(self.payload, [evidence.CRITICAL_TEST])

    def captures(self):
        return evidence.validate_captures(self.manifest, self.root, 100)

    def test_passed_expected_case_and_all_seven_capture_hashes(self):
        self.assertEqual(self.validate()[0]['result'], 'Passed')
        captures = self.captures()
        self.assertEqual(len(captures), 7)
        self.assertEqual(captures[0]['sha256'], evidence.digest(self.root / '0.png'))

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
        self.assertEqual([case['result'] for case in self.validate()], ['Passed', 'Skipped'])

    def test_every_capture_is_required(self):
        for index in range(7):
            manifest = copy.deepcopy(self.manifest)
            del manifest[0]['attachments'][index]
            with self.subTest(index=index), self.assertRaises(ValueError):
                evidence.validate_captures(manifest, self.root, 100)

    def test_duplicate_or_wrong_test_capture_manifest_rejected(self):
        for manifest in ([], self.manifest * 2, [{'testIdentifier': 'other', 'attachments': []}]):
            with self.subTest(manifest=manifest), self.assertRaises(ValueError):
                evidence.validate_captures(manifest, self.root, 100)

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

    def run_main(self, critical=True, expected=True):
        args = ['validator', '--bundle', str(self.bundle), '--started-at', '100']
        if expected:
            args += ['--expected-test', evidence.CRITICAL_TEST]
        if critical:
            args += ['--critical-captures']
        with patch.object(sys, 'argv', args):
            return evidence.main()

    def export(self, command, **kwargs):
        directory = Path(command[command.index('--output-path') + 1])
        (directory / 'manifest.json').write_text(json.dumps(self.manifest))
        for item in self.manifest[0]['attachments']:
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
        self.assertEqual(len(receipt['captures']), 7)
        self.assertEqual(receipt['devices'], self.payload['devices'])

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
        self.assertEqual(json.loads(self.bundle.with_suffix('.evidence.json').read_text())['evidenceKind'],
                         'unit_tests')

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

    def test_shell_preserves_failed_attempt_and_stops_after_two(self):
        # Execute the real function definitions without running the product build.
        source = Path(__file__).with_name('launch-quality-audit.sh').read_text()
        functions = source[source.index('is_simulator_infra_failure() {'):source.index('assert_xcresult_evidence() {')]
        result_bundle = self.root / 'retry.xcresult'
        log = self.root / 'retry.log'
        command = r"""
set -euo pipefail
COMMON_XCODEBUILD_ARGS=(fixture)
XCODEBUILD_SETTINGS_ARRAY=(fixture)
XCODEBUILD_COMMAND_TIMEOUT_SECONDS=10
cleanup_booted_simulator_apps() { :; }
sleep() { :; }
run_with_timeout() {
  mkdir -p "$RESULT_BUNDLE"
  echo 'first attempt evidence' > "$RESULT_BUNDLE/receipt"
  echo 'Failed to install or launch the test runner'
  return 65
}
""" + functions + '\nrun_xcodebuild_test fixture "$RESULT_BUNDLE" "$RESULT_LOG"\n'
        result = subprocess.run(['bash', '-c', command], capture_output=True, text=True, timeout=10,
                                env={**os.environ, 'RESULT_BUNDLE': str(result_bundle), 'RESULT_LOG': str(log)})
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertTrue(result_bundle.with_name('retry.attempt-1.xcresult').is_dir())
        self.assertTrue(result_bundle.is_dir())
        self.assertEqual(log.read_text().count('Running fixture (attempt '), 2)
        self.assertIn('first attempt evidence', (result_bundle.with_name('retry.attempt-1.xcresult') / 'receipt').read_text())


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(EvidenceTests)
    result = unittest.TextTestRunner().run(suite)
    print(f'Evidence validator behavior tests executed: {result.testsRun}')
    if not result.wasSuccessful() or result.testsRun == 0:
        sys.exit(1)
