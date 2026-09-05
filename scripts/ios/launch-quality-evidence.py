#!/usr/bin/env python3
"""Validate the launch gate's XCTest results and fixture screenshot evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

CRITICAL_TEST = 'LogYourBodyUITests/testLaunchQualityGateCapturesCriticalSurfaces()'
TIMELINE_TEST = 'LogYourBodyUITests/testLaunchQualityGateCapturesTimelineSurfaces()'
ONBOARDING_TEST = 'LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFixedCTA()'
FIRST_PHOTO_TEST = 'LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFirstPhotoCTA()'
REQUIRED_TESTS = (CRITICAL_TEST, ONBOARDING_TEST, FIRST_PHOTO_TEST, TIMELINE_TEST)
REQUIRED_CAPTURES = (
    'launch-quality-chat-composer',
    'launch-quality-chat-tab',
    'launch-quality-onboarding-fixed-cta',
    'launch-quality-onboarding-first-photo',
    'launch-quality-home-timeline',
    'launch-quality-body-score-share',
    'launch-quality-analytics',
)

CAPTURE_OWNERS = dict(zip(REQUIRED_CAPTURES, (
    CRITICAL_TEST, CRITICAL_TEST, ONBOARDING_TEST, FIRST_PHOTO_TEST,
    TIMELINE_TEST, TIMELINE_TEST, TIMELINE_TEST,
)))

def walk(nodes):
    for node in nodes:
        yield node
        yield from walk(node.get('children', []))


def validate_cases(payload, expected):
    cases = [node for node in walk(payload['testNodes']) if node['nodeType'] == 'Test Case']
    if not cases:
        raise ValueError('No XCTest cases executed')
    if not any(case.get('result') == 'Passed' for case in cases):
        raise ValueError('No XCTest cases passed (skipped cases are not execution proof)')
    for case in cases:
        if case.get('result') not in ('Passed', 'Skipped'):
            raise ValueError(f"Non-passing XCTest case: {case.get('nodeIdentifier')} ({case.get('result')})")
    for identifier in expected:
        matches = [case for case in cases if case.get('nodeIdentifier') == identifier]
        if len(matches) != 1 or matches[0].get('result') != 'Passed':
            raise ValueError(f'Required XCTest case missing, duplicated or not passed: {identifier}')
        # A parent Passed must not hide failed/skipped individual runs or repetitions.
        for node in walk([matches[0]]):
            if 'result' in node and node['result'] != 'Passed':
                raise ValueError(f'Required XCTest case has non-passing run: {identifier}')
    return [{'identifier': case.get('nodeIdentifier'), 'result': case['result']} for case in cases]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_captures(manifest, directory, started_at):
    groups = {}
    for identifier in REQUIRED_TESTS:
        matches = [item for item in manifest if item.get('testIdentifier') == identifier]
        if len(matches) != 1:
            raise ValueError(f'Missing or ambiguous required-test attachment manifest: {identifier}')
        groups[identifier] = matches[0]
    captures = []
    for name in REQUIRED_CAPTURES:
        matches = [item for item in groups[CAPTURE_OWNERS[name]]['attachments']
                   if item.get('suggestedHumanReadableName', '').startswith((name + '_', name + '.'))
                   or item.get('suggestedHumanReadableName') == name]
        if len(matches) != 1:
            raise ValueError(f'Missing or ambiguous required capture: {name}')
        item = matches[0]
        if item.get('isAssociatedWithFailure') is not False:
            raise ValueError(f'Capture associated with failure: {name}')
        timestamp = item.get('timestamp')
        if not isinstance(timestamp, (int, float)) or timestamp < started_at:
            raise ValueError(f'Missing or stale capture timestamp: {name}')
        path = (directory / item['exportedFileName']).resolve()
        if path.parent != directory.resolve() or not path.is_file():
            raise ValueError(f'Missing or unsafe exported capture: {name}')
        if not path.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError(f'Required capture is not a PNG screenshot: {name}')
        captures.append({'name': name, 'file': path.name, 'sha256': digest(path),
                         'capturedAt': timestamp, 'deviceId': item.get('deviceId'),
                         'configuration': item.get('configurationName')})
    return captures


def run_json(*args):
    return json.loads(subprocess.check_output(['xcrun', 'xcresulttool', *args], text=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--expected-test', action='append', default=[])
    parser.add_argument('--critical-captures', action='store_true')
    parser.add_argument('--started-at', type=float, required=True)
    args = parser.parse_args()
    output = args.bundle.with_suffix('.evidence.json')
    # Never leave a stale PASS next to a failed revalidation.
    output.unlink(missing_ok=True)
    try:
        if not args.bundle.is_dir():
            raise ValueError(f'Missing xcresult bundle: {args.bundle}')
        payload = run_json('get', 'test-results', 'tests', '--path', str(args.bundle))
        cases = validate_cases(payload, args.expected_test)
        prior_attempt = args.bundle.with_name(args.bundle.stem + '.attempt-1.xcresult')
        attempt_log = args.bundle.with_suffix('.log')
        retried = f'Retrying {args.bundle.stem} after simulator launch failure'
        recovered_after_retry = 'unknown'
        if prior_attempt.is_dir():
            recovered_after_retry = True
        elif attempt_log.is_file():
            log_text = attempt_log.read_text()
            if retried in log_text:
                recovered_after_retry = True
            elif f'Running {args.bundle.stem} (attempt 1)' in log_text:
                recovered_after_retry = False
        source_revision = args.bundle.parent / 'source-revision.txt'
        source_patch = args.bundle.parent / 'source-working-tree.patch'
        receipt = {
            'schemaVersion': 1,
            'evidenceKind': 'fixture_ui' if args.critical_captures else 'unit_tests',
            'status': 'passed',
            'generatedAt': datetime.now(timezone.utc).isoformat(),
            'startedAt': args.started_at,
            'resultBundle': str(args.bundle),
            'recoveredAfterRetry': recovered_after_retry,
            'priorAttemptBundle': str(prior_attempt) if prior_attempt.is_dir() else None,
            'sourceRevision': source_revision.read_text().strip() if source_revision.is_file() else 'unknown',
            'sourcePatchSha256': digest(source_patch) if source_patch.is_file() else 'unknown',
            'exactDeployedBuild': 'not_verified',
            'tests': cases,
            'devices': payload.get('devices', []),
            'configurations': payload.get('testPlanConfigurations', []),
            'validatorSha256': digest(Path(__file__)),
            'liveVerification': {'signInWithApple': 'not_verified',
                                 'purchase': 'not_verified', 'restore': 'not_verified'},
        }
        if args.critical_captures:
            if not set(REQUIRED_TESTS).issubset(args.expected_test):
                raise ValueError('Critical captures require all exact passing surface tests')
            directory = args.bundle.with_suffix('.attachments')
            # One immutable export per attempt; never combine old/new attachments.
            directory.mkdir(exist_ok=False)
            subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments',
                            '--path', str(args.bundle),
                            '--output-path', str(directory)], check=True)
            manifest_path = directory / 'manifest.json'
            receipt['captures'] = validate_captures(json.loads(manifest_path.read_text()),
                                                   directory, args.started_at)
            receipt['attachmentManifestSha256'] = digest(manifest_path)
        output.write_text(json.dumps(receipt, indent=2) + '\n')
        print(f"Verified {len(cases)} XCTest cases; evidence: {output}")
        return 0
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(f'Launch-quality evidence rejected: {error}', file=sys.stderr)
        return 65


if __name__ == '__main__':
    sys.exit(main())
