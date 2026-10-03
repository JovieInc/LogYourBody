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
from unittest.mock import MagicMock, patch
from types import SimpleNamespace
import trace
import signal

spec = importlib.util.spec_from_file_location('evidence', Path(__file__).with_name('launch-quality-evidence.py'))
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)

# Trace the same CI entrypoint, including helper import AND meaningful behavior cases.
coverage_tracer = trace.Trace(count=True, trace=False, ignoredirs=[sys.base_prefix]) if __name__ == '__main__' else None
if coverage_tracer:
    sys.settrace(coverage_tracer.globaltrace)
observability_path = Path(__file__).with_name('launch-quality-observability.py').resolve()
obs_spec = importlib.util.spec_from_file_location('observability', observability_path)
observability = importlib.util.module_from_spec(obs_spec)
obs_spec.loader.exec_module(observability)


class EvidenceTests(unittest.TestCase):
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

    def run_main(self, critical=True, expected=True):
        args = ['validator', '--bundle', str(self.bundle), '--started-at', '100']
        if expected:
            for identifier in evidence.REQUIRED_TESTS:
                args += ['--expected-test', identifier]
        if critical:
            args += ['--critical-captures']
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
        self.assertEqual(len(receipt['captures']), 7)
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
start_launch_observer() { :; }
finish_launch_observer() { :; }
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


class ObservabilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / 'attempt-1'
        self.device = '2911FD29-A09E-4A81-BEA7-99A616FB7FC8'
        self.source = self.root / 'source'
        self.source.write_text('a' * 40 + '\n')
        self.patch = self.root / 'patch'
        self.patch.write_text('')
        self.destination = 'platform=iOS Simulator,id=' + self.device

    def initialize(self, directory=None, destination=None):
        observability.init(directory or self.directory, observability.STAGES[1], 1,
                           destination or self.destination, self.source, self.patch, 420)

    def event(self, message, process='installd', pid=42):
        return {'timestamp': '2026-10-01 07:07:36.449282+0000', 'processID': pid,
                'processImagePath': '/private/path/' + process, 'eventMessage': message,
                'secret': 'must-not-survive'}

    def test_init_binds_source_attempt_without_environment_payload(self):
        with patch.dict(os.environ, {'GITHUB_RUN_ID': '36827835458',
                                    'GITHUB_RUN_ATTEMPT': '1', 'AUTH_TOKEN': 'SECRET'}):
            self.initialize()
        context = json.loads((self.directory / 'context.json').read_text())
        self.assertEqual(context['github_run_id'], '36827835458')
        self.assertEqual(context['source_revision'], 'a' * 40)
        self.assertEqual(context['simulator_uuid'], self.device)
        self.assertNotIn('SECRET', json.dumps(context))
        self.assertNotIn('AUTH_TOKEN', json.dumps(context))
        with self.assertRaises(FileExistsError):
            self.initialize()
        for bad in [('other', 1, 420), (observability.STAGES[1], 3, 420),
                    (observability.STAGES[1], 1, 0)]:
            with self.assertRaises(ValueError):
                observability.init(self.root / 'bad', bad[0], bad[1], self.destination,
                                   self.source, self.patch, bad[2])
        self.source.write_text('not a revision')
        with self.assertRaises(ValueError):
            self.initialize(self.root / 'invalid-source')

    def test_unresolved_destination_remains_unknown_not_boot_ready(self):
        with patch.dict(os.environ, {'GITHUB_RUN_ID': 'SECRET\n123', 'GITHUB_RUN_ATTEMPT': ''}):
            self.initialize(destination='platform=iOS Simulator,name=iPhone 16')
        context = json.loads((self.directory / 'context.json').read_text())
        self.assertIsNone(context['simulator_uuid'])
        self.assertIsNone(context['github_run_id'])
        observability.collect(self.directory)
        state = json.loads((self.directory / 'collection-status.json').read_text())
        self.assertEqual(state['stop'], 'destination_unavailable')
        self.assertFalse((self.directory / 'host-service-events.ndjson').exists())

    def test_event_sanitizer_keeps_timing_codes_but_never_raw_payload(self):
        message = ('Install successful for Developer:com.logyourbody.app; Overall: 16.47s; '
                   'Waiting: 0.00s; pid = 27835; Error Domain=NSPOSIXErrorDomain Code=2; '
                   'arguments=TOKEN email=person@example.com /Users/person SECRET\npassword=SECRET')
        row = observability.sanitize_event(self.event(message), 'simulator', self.device)
        self.assertEqual(row['event'], 'install_complete')
        self.assertEqual(row['install_seconds'], {'Overall': 16.47, 'Waiting': 0.0})
        self.assertEqual(row['error_code'], 2)
        self.assertEqual(row['target_pid'], 27835)
        for private in ['SECRET', 'TOKEN', 'person', '/private', 'arguments', 'password']:
            self.assertNotIn(private, json.dumps(row))
        host = self.event(self.device + ' Launching app com.logyourbody.app', process='CoreSimulatorService')
        self.assertEqual(observability.sanitize_event(host, 'host', self.device)['event'], 'launch_start')
        wrong_host = self.event(self.device + ' Launching app com.logyourbody.app', process='installd')
        for payload, origin in [(wrong_host, 'host'), (host, 'other'), (self.event('Booted'), 'simulator'),
                                (self.event('com.logyourbody.app Booted'), 'simulator'),
                                (host, 'simulator'), (self.event(message, 'Safari'), 'simulator'),
                                (self.event(message, pid=True), 'simulator'),
                                (self.event(message, pid=-1), 'simulator'),
                                (self.event(message.replace('com.logyourbody.app', 'com.other.app')), 'simulator'),
                                (self.event(message.replace('com.logyourbody.app', 'com.logyourbody.app.evil')), 'simulator'),
                                (self.event(message), 'host'), ('SECRET', 'simulator')]:
            self.assertIsNone(observability.sanitize_event(payload, origin, self.device))
        for invalid in [None, 'bad', '2026-10-01T07:00:00',
                        '2026-10-01 07:07:36.449282+2400', '2026-10-01 07:07:36.449282+0060']:
            payload = self.event(message)
            payload['timestamp'] = invalid
            self.assertIsNone(observability.sanitize_event(payload, 'simulator', self.device))
        payload.pop('timestamp')
        self.assertIsNone(observability.sanitize_event(payload, 'simulator', self.device))
        self.assertIsNone(observability.sanitize_event(self.event(self.device + ' unknown message'), 'host', self.device))

    def test_malformed_context_is_unavailable_without_starting_any_stream(self):
        self.initialize()
        context_file = self.directory / 'context.json'
        original = json.loads(context_file.read_text())
        for key, value in [('simulator_uuid', '\" OR TRUE'), ('command_timeout_seconds', True),
                           ('audit_pid', -1), ('source_revision', 'missing'), ('attempt', 3)]:
            context_file.write_text(json.dumps({**original, key: value}))
            with patch.object(observability.subprocess, 'Popen') as spawn:
                self.assertEqual(observability.main(['collect', '--directory', str(self.directory)]), 1)
                spawn.assert_not_called()
            state = json.loads((self.directory / 'collection-status.json').read_text())
            self.assertEqual(state['command_end'], 'unknown')

    def test_all_allowlisted_events_are_fixed_classes(self):
        examples = ['Installing app', 'Launched app', 'Creating and launching job',
                    'running-active', 'process exited with status', 'getenv returned nil',
                    'has testmanagerd socket', 'Got reply to control session',
                    'Test runner is ready', 'connection failed']
        for text in examples:
            row = observability.sanitize_event(self.event('com.logyourbody.app ' + text), 'simulator', self.device)
            self.assertIsNotNone(row, text)
            self.assertNotIn('eventMessage', row)
        huge = self.event('com.logyourbody.app Install successful; Overall: ' + '9' * 400 + 's')
        self.assertNotIn('install_seconds', observability.sanitize_event(huge, 'simulator', self.device))

    def test_process_frames_require_audit_ancestry_or_event_bound_pid(self):
        text = '\n'.join(['10 1 S 0.0 0.1 00:01 /bin/bash',
                          '11 10 S 1.2 2.3 00:04 /usr/bin/xcodebuild',
                          '12 1 S 3.0 1.0 00:05 /Applications/LogYourBody',
                          '13 1 S 1.0 1.0 00:05 /usr/bin/xcodebuild',
                          '14 10 S 1.0 1.0 00:05 /private/person/Safari',
                          '15 1 S nan 1 00:00 /bin/installd', 'bad',
                          'bad 1 S 0 1 00:00 /bin/installd',
                          '-1 1 S 0 1 00:00 /bin/installd',
                          '16 1 SECRET 0 1 00:00 /bin/installd',
                          '17 1 S 0 1 SECRET /bin/installd',
                          '18 19 S 0 1 00:00 /bin/xcodebuild',
                          '19 18 S 0 1 00:00 /bin/bash'])
        rows = observability.process_rows(text, 10, {12})
        self.assertEqual([row['pid'] for row in rows], [11, 12])
        self.assertNotIn('person', json.dumps(rows))
        large = '\n'.join(f'{pid} 1 S 0 0 00:00 /bin/installd' for pid in range(100, 150))
        self.assertEqual(len(observability.process_rows(large, 10, set(range(100, 150)))), 32)

    def test_lifecycle_native_status_and_bytes_are_bounded(self):
        self.initialize()
        observability.mark(self.directory, 'command_start')
        observability.mark(self.directory, 'command_end', 124)
        events = [json.loads(line) for line in (self.directory / 'lifecycle.ndjson').read_text().splitlines()]
        self.assertEqual(events[-1]['command_status'], 124)
        self.assertNotIn('command_status', events[0])
        for event, status in [('ready', None), ('command_end', None), ('command_end', True), ('command_end', 256)]:
            with self.assertRaises(ValueError):
                observability.mark(self.directory, event, status)
        path = self.directory / 'bounded'
        self.assertFalse(observability.append_event(path, {'secret': 'x' * 200}, maximum=20))
        self.assertFalse(path.exists())
        self.assertTrue(observability.append_event(path, {'ok': 1}, maximum=20))
        self.assertTrue(observability.append_event(path, {'ok': 2}, maximum=20))
        self.assertEqual(path.stat().st_size, 20)
        self.assertFalse(observability.append_event(path, {'ok': 3}, maximum=20))
        below_boundary = self.directory / 'below-boundary'
        self.assertTrue(observability.append_event(below_boundary, {'ok': 1}, maximum=19))
        self.assertFalse(observability.append_event(below_boundary, {'ok': 2}, maximum=19))

    def collect_fixture(self, *, fail_spawn=False, fail_snapshot=False,
                        malformed=False, cancel=False, chunk_cap=False, truncate=False):
        self.initialize()
        mapping, chunks, children, handlers = {}, {}, [], {}
        selector = MagicMock()
        selector.get_map.side_effect = lambda: mapping
        selector.register.side_effect = lambda pipe, events, data: mapping.update({pipe: SimpleNamespace(fileobj=pipe, data=data)})
        selector.unregister.side_effect = lambda pipe: mapping.pop(pipe)
        def select(timeout):
            if cancel:
                handlers[signal.SIGTERM](signal.SIGTERM, None)
            return [(key, None) for key in list(mapping.values())]
        selector.select.side_effect = select
        def spawn(command, **kwargs):
            if fail_spawn:
                raise OSError('SECRET')
            child = MagicMock()
            child.pid = 1000 + len(children)
            child.stdout.fileno.return_value = child.pid
            child.returncode = 0 if ('simctl' not in command or chunk_cap) else 64
            child.poll.return_value = child.returncode
            child.wait.return_value = child.returncode
            children.append(child)
            message = self.device + ' Launching app com.logyourbody.app' if 'simctl' not in command else 'com.logyourbody.app Install successful'
            good = json.dumps(self.event(message)).encode() + b'\n'
            chunks[child.pid] = ([b'x' * (observability.MAX_BYTES + 1), b'bad\n"SECRET"\n', good] if malformed else [good]) + [b'']
            self.assertTrue(kwargs['start_new_session'])
            return child
        def install_handler(sig, handler):
            handlers[sig] = handler
            return signal.SIG_DFL
        original_append = observability.append_event
        def append(path, row, maximum=observability.MAX_BYTES):
            if truncate and path.name in ('process-state.ndjson', 'host-service-events.ndjson', 'simulator-service-events.ndjson'):
                return False
            return original_append(path, row, maximum)
        with patch.object(observability.selectors, 'DefaultSelector', return_value=selector), \
             patch.object(observability.subprocess, 'Popen', side_effect=spawn), \
             patch.object(observability.subprocess, 'check_output', side_effect=subprocess.SubprocessError('SECRET') if fail_snapshot else None,
                          return_value='10 1 S 0 0 00:00 /bin/xcodebuild'), \
             patch.object(observability.os, 'set_blocking'), \
             patch.object(observability.os, 'read', side_effect=lambda pid, maximum: chunks[pid].pop(0)), \
             patch.object(observability.time, 'monotonic', return_value=100), \
             patch.object(observability.signal, 'signal', side_effect=install_handler), \
             patch.object(observability, 'append_event', side_effect=append):
            observability.collect(self.directory)
        return json.loads((self.directory / 'collection-status.json').read_text())

    def test_mocked_collection_errors_chunks_and_caps_are_explicit(self):
        for options in [{}, {'fail_spawn': True}, {'fail_snapshot': True},
                        {'malformed': True}, {'truncate': True}, {'chunk_cap': True}, {'cancel': True}]:
            with self.subTest(options=options):
                self.directory = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                state = self.collect_fixture(**options)
                self.assertEqual(state['evidence_scope'], 'diagnostics_only')
                self.assertIn('UNVERIFIED', state['simulator_spawn_cleanup'])
                if options.get('fail_spawn'):
                    self.assertEqual(state['origin_status']['host'], 'unavailable')
                if options.get('fail_snapshot'):
                    self.assertEqual(state['process_snapshot'], 'unavailable')
                if options.get('malformed'):
                    self.assertGreater(state['malformed'], 0)
                if options.get('truncate'):
                    self.assertIn('process-state', state['truncated'])
                if options.get('chunk_cap'):
                    self.assertEqual(len(state['simulator_chunks']), 60)
                    self.assertIn('simulator_chunk_cap', state['truncated'])
                if options.get('cancel'):
                    self.assertEqual(state['stop'], 'signal')
                    lifecycle = (self.directory / 'lifecycle.ndjson').read_text()
                    self.assertNotIn('command_end', lifecycle)
                for file in self.directory.glob('*.json'):
                    self.assertNotIn('SECRET', file.read_text())

    def test_owned_host_group_cleanup_never_selects_process_names(self):
        child = MagicMock(pid=23456)
        child.poll.return_value = None
        child.wait.side_effect = [subprocess.TimeoutExpired('fixture', 0.2), 0]
        with patch.object(observability.os, 'killpg') as kill:
            self.assertTrue(observability.stop_children([child]))
        self.assertEqual([call.args for call in kill.call_args_list],
                         [(23456, signal.SIGTERM), (23456, signal.SIGKILL)])
        child.wait.side_effect = subprocess.TimeoutExpired('fixture', 0.2)
        with patch.object(observability.os, 'killpg', side_effect=ProcessLookupError):
            self.assertFalse(observability.stop_children([child]))

    def test_cli_error_paths_keep_fixed_stderr(self):
        self.initialize()
        self.assertEqual(observability.main(['mark', '--directory', str(self.directory), '--event', 'command_start']), 0)
        self.assertEqual(observability.main(['mark', '--directory', str(self.directory), '--event', 'command_end', '--status', '65']), 0)
        self.assertEqual(observability.main(['init', '--directory', str(self.root / 'cli'),
                         '--stage', observability.STAGES[1], '--attempt', '1', '--destination', self.destination,
                         '--source', str(self.source), '--patch', str(self.patch), '--timeout', '420']), 0)
        self.assertEqual(observability.main(['mark', '--directory', str(self.directory), '--event', 'SECRET']), 1)
        with patch.object(observability, 'collect') as collect:
            self.assertEqual(observability.main(['collect', '--directory', str(self.directory)]), 0)
            collect.assert_called_once_with(self.directory)
        for timeout in (1, 420, 600):
            commands = observability.commands(self.device, timeout)
            simulator = commands['simulator']
            self.assertEqual(simulator[3], self.device)
            self.assertEqual(int(simulator[simulator.index('--timeout') + 1]), min(timeout, 10))
            self.assertNotIn('bootstatus', json.dumps(commands))
            self.assertNotIn('boot', simulator)

    def test_real_bash_marks_preserve_0_65_124_143_and_two_attempts(self):
        # The candidate regression can target the preserved old audit for real-shell RED.
        audit = Path(os.environ.get('LYB_OBSERVABILITY_AUDIT_SOURCE',
                                    str(Path(__file__).with_name('launch-quality-audit.sh'))))
        source = audit.read_text()
        start = source.find('# Diagnostics are independent')
        start = start if start >= 0 else source.index('is_simulator_infra_failure() {')
        functions = source[start:source.index('run_ui_test_group() {')]
        fixture = r"""
set -euo pipefail
COMMON_XCODEBUILD_ARGS=(fixture)
XCODEBUILD_SETTINGS_ARRAY=(fixture)
XCODEBUILD_COMMAND_TIMEOUT_SECONDS=420
BUILD_FOR_TESTING_TIMEOUT_SECONDS=600
DESTINATION=fixture
cleanup_booted_simulator_apps() { :; }
sleep() { :; }
python3() {
  local mode="$2" directory="" event="" status=""
  shift 2
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --directory) directory="$2";;
      --event) event="$2";;
      --status) status="$2";;
    esac
    shift 2
  done
  case "$mode" in
    init) mkdir -p "$directory";;
    collect) return 99;;
    mark) echo "$event $status" >> "$directory/fixture-marks";;
  esac
}
run_with_timeout() {
  mkdir -p "$RESULT_BUNDLE"
  echo 'retained first attempt' > "$RESULT_BUNDLE/receipt"
  echo 'generic fixture result'
  return "$NATIVE_STATUS"
}
""" + functions
        for native in (0, 65, 124, 143):
            for label in ('launch-quality-unit-tests', 'launch-quality-build-for-testing'):
                directory = self.root / (label + '-' + str(native))
                directory.mkdir()
                call = '\nbuild_for_testing_once\n' if label.endswith('build-for-testing') else '\nrun_xcodebuild_test launch-quality-unit-tests "$RESULT_BUNDLE" "$RESULT_LOG"\n'
                result = subprocess.run(['bash', '-c', fixture + call], capture_output=True, text=True, timeout=10,
                    env={**os.environ, 'ROOT_DIR': str(Path(__file__).resolve().parents[2]),
                         'ARTIFACT_DIR': str(directory), 'NATIVE_STATUS': str(native),
                         'RESULT_BUNDLE': str(directory / 'fixture.xcresult'), 'RESULT_LOG': str(directory / 'fixture.log')})
                self.assertEqual(result.returncode, native, result.stderr)
                marks = list(directory.glob('observability/*/attempt-*/fixture-marks'))
                expected_attempts = 2 if native == 124 and label.endswith('unit-tests') else 1
                self.assertEqual(len(marks), expected_attempts, result.stdout)
                for mark in marks:
                    self.assertEqual(mark.read_text().splitlines(), ['command_start ', f'command_end {native}'])
                if expected_attempts == 2:
                    self.assertTrue((directory / 'fixture.attempt-1.xcresult/receipt').exists())


    def test_real_bash_cancellation_keeps_end_unknown_and_unrelated_child_alive(self):
        source = Path(__file__).with_name('launch-quality-audit.sh').read_text()
        functions = source[source.index('# Diagnostics are independent'):source.index('is_simulator_infra_failure() {')]
        fixture = r"""
set -euo pipefail
DESTINATION=fixture
python3() {
  local mode="$2" directory="" event=""
  shift 2
  while [[ "$#" -gt 0 ]]; do
    case "$1" in --directory) directory="$2";; --event) event="$2";; esac
    shift 2
  done
  case "$mode" in
    init) mkdir -p "$directory";;
    collect) trap 'exit 0' TERM; while :; do /bin/sleep 0.01; done;;
    mark) echo "$event" >> "$directory/fixture-marks";;
  esac
}
""" + functions + r"""
start_launch_observer launch-quality-unit-tests 1 420
kill -TERM "$$"
"""
        sentinel = subprocess.Popen(['/bin/sleep', '5'])
        try:
            result = subprocess.run(['bash', '-c', fixture], capture_output=True, text=True, timeout=3,
                                    env={**os.environ, 'ROOT_DIR': str(self.root), 'ARTIFACT_DIR': str(self.root)})
            self.assertEqual(result.returncode, 143, result.stderr)
            self.assertIsNone(sentinel.poll())
            mark = self.root / 'observability/launch-quality-unit-tests/attempt-1/fixture-marks'
            self.assertEqual(mark.read_text().splitlines(), ['command_start'])
        finally:
            sentinel.terminate()
            sentinel.wait(timeout=1)


if __name__ == '__main__':
    suite = unittest.TestSuite([unittest.defaultTestLoader.loadTestsFromTestCase(EvidenceTests),
                                unittest.defaultTestLoader.loadTestsFromTestCase(ObservabilityTests)])
    result = unittest.TextTestRunner().run(suite)
    sys.settrace(None)
    counts = coverage_tracer.results().counts
    helper_counts = {key: count for key, count in counts.items()
                     if Path(key[0]).resolve() == observability_path}
    executable = trace._find_executable_linenos(str(observability_path))
    covered = {line for (filename, line), count in helper_counts.items() if count > 0}
    percentage = 100 * len(covered & set(executable)) / len(executable) if executable else 0
    coverage_dir = (Path(os.environ['ARTIFACT_DIR']) / 'observability/test-coverage'
                    if os.environ.get('ARTIFACT_DIR') else Path(tempfile.mkdtemp(prefix='lyb-observability-coverage-')))
    coverage_dir.mkdir(parents=True, exist_ok=True)
    trace.CoverageResults(counts=helper_counts).write_results(show_missing=True, summary=True, coverdir=str(coverage_dir))
    (coverage_dir / 'helper-line-coverage.json').write_text(json.dumps({
        'source': str(observability_path), 'source_sha256': observability.hashlib.sha256(observability_path.read_bytes()).hexdigest(),
        'covered_lines': sorted(covered & set(executable)), 'executable_lines': sorted(executable),
        'line_percent': percentage, 'required_line_percent': 90, 'executed_tests': result.testsRun,
        'test_selector': 'existing entrypoint: EvidenceTests + ObservabilityTests'}) + '\n')
    print(f'Observability helper executed line coverage: {percentage:.2f}% (required >=90%)')
    if not helper_counts or percentage < 90:
        print('Missing or insufficient executed observability helper coverage', file=sys.stderr)
        sys.exit(1)
    print(f'Evidence validator behavior tests executed: {result.testsRun}')
    if not result.wasSuccessful() or result.testsRun == 0:
        sys.exit(1)
