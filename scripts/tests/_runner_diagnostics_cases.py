"""Focused-diagnostics test family (part 1): workflow step extraction and the
focused/full diagnostic dispatch scenarios. A leading-underscore module so pytest
never collects it directly; test_runner_routing.py imports it back so the family
stays in the CI collection of scripts/tests/test_runner_routing.py."""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import textwrap
from pathlib import Path
from typing import Any

import pytest

from test_runner_routing import _REPO_ROOT, _WORKFLOWS, _coverage_fds

# Focused diagnostics are deliberately separate from every qualification gate.
def _diagnostic_step(name: str) -> str:
    source = (_WORKFLOWS / 'ios-ui-diagnostics.yml').read_text()
    step = source.split('      - name: ' + name + '\n', 1)[1].split('\n      - ', 1)[0]
    return textwrap.dedent(step.split('        run: |\n', 1)[1])


def _diagnostic_python(marker: str, source: str) -> dict[str, Any]:
    body = source.split("<<'" + marker + "'\n", 1)[1].split('\n' + marker, 1)[0]
    namespace: dict[str, Any] = {'__name__': 'diagnostic_test'}
    exec(compile(body, '<actual-' + marker + '>', 'exec'), namespace)
    return namespace


def _diagnostic_receipt_module() -> dict[str, Any]:
    return _diagnostic_python('DIAGNOSTIC_RECEIPT_PY',
        (_REPO_ROOT / 'scripts/ios/launch-quality-audit.sh').read_text())


def _diagnostic_ids() -> list[str]:
    source = (_REPO_ROOT / 'scripts/ios/launch-quality-audit.sh').read_text()
    block = source.split('DIAGNOSTIC_SEVEN_TESTS=(\n', 1)[1].split('\n)', 1)[0]
    return [line.strip().strip('"') + '()' for line in block.splitlines()]


def _diagnostic_payload() -> tuple[dict[str, Any], str]:
    ids = _diagnostic_ids()
    payload = {'testNodes': [{'nodeType': 'UI test bundle', 'children': [
        {'nodeType': 'Test Case', 'nodeIdentifier': i, 'result': 'Passed'} for i in ids]}]}
    lines = []
    for identifier in ids:
        suite, method = identifier[:-2].split('/')
        lines += [f"Test Case '-[LogYourBodyUITests.{suite} {method}]' started.",
                  f"Test Case '-[LogYourBodyUITests.{suite} {method}]' passed (0.1 seconds)."]
    return payload, '\n'.join(lines) + '\n'


def test_focused_diagnostic_exact_catalogue_and_actual_events_reject_repetitions() -> None:
    import copy
    import pytest
    validate = _diagnostic_receipt_module()['strict_diagnostic_cases']
    payload, log = _diagnostic_payload()
    ids = _diagnostic_ids()
    assert len(validate(payload, ids, log)) == 7
    # One explicit native run leaf is valid; extra repetitions are not.
    one_run = copy.deepcopy(payload)
    one_run['testNodes'][0]['children'][0]['children'] = [{'nodeType': 'Test Case Run', 'result': 'Passed'}]
    assert len(validate(one_run, ids, log)) == 7
    mutations = []
    for result in ['Passed', 'Skipped', 'Failed', 'Not Run']:
        extra = copy.deepcopy(payload)
        extra['testNodes'][0]['children'].append({'nodeType': 'Test Case', 'nodeIdentifier': 'Extra/test()', 'result': result})
        mutations.append(extra)
    duplicate = copy.deepcopy(payload)
    duplicate['testNodes'][0]['children'].append(copy.deepcopy(duplicate['testNodes'][0]['children'][0]))
    mutations.append(duplicate)
    partial = copy.deepcopy(payload)
    partial['testNodes'][0]['children'].pop()
    mutations += [partial, {'testNodes': []}, {}, {'testNodes': None}]
    for result in ['Skipped', 'Failed', 'Not Run']:
        failed = copy.deepcopy(payload)
        failed['testNodes'][0]['children'][0]['result'] = result
        mutations.append(failed)
    for children in [[{'nodeType': 'Test Case Run', 'result': 'Passed'}] * 2,
                     [{'nodeType': 'Test Case Run', 'result': 'Skipped'}],
                     [{'nodeType': 'Unknown repetition', 'result': 'Passed'}]]:
        repeated = copy.deepcopy(payload)
        repeated['testNodes'][0]['children'][0]['children'] = children
        mutations.append(repeated)
    for mutation in mutations:
        with pytest.raises((ValueError, KeyError, TypeError)):
            validate(mutation, ids, log)
    lines = log.splitlines()
    for bad_log in ['', '\n'.join(lines[:-1]), log + '\n'.join(lines[:2]),
                    '\n'.join(lines[1:]), log.replace('passed', 'failed', 1),
                    log + "Test Case '-[OtherModule.Extra test]' passed (0.1 seconds).\n",
                    '\n'.join([lines[1], lines[0], *lines[2:]])]:
        with pytest.raises(ValueError):
            validate(payload, ids, bad_log)
    with pytest.raises(ValueError):
        validate(payload, ids[:-1], log)


def _diagnostic_git(directory: Path, *args: str) -> str:
    return subprocess.check_output(['git', '-C', str(directory), *args], text=True).strip()


def _diagnostic_repository(tmp_path: Path) -> tuple[Path, str]:
    root = (tmp_path / 'repo').resolve()
    (root / 'scripts/ios').mkdir(parents=True)
    (root / 'apps/ios').mkdir(parents=True)
    (root / 'scripts/ios/launch-quality-audit.sh').write_bytes((_REPO_ROOT / 'scripts/ios/launch-quality-audit.sh').read_bytes())
    for name, code in {
        'bootstrap-local-config.sh': '#!/bin/bash\nprintf "bootstrap\\n" >> "$FAKE_CALLS"\n',
        'resolve-simulator-destination.sh': '#!/bin/bash\nprintf "destination\\n" >> "$FAKE_CALLS"\nprintf "platform=iOS Simulator,id=11111111-1111-1111-1111-111111111111\\n"\n',
        'test_launch_quality_evidence.py': (
            'import os, sys\n'
            'with open(os.environ["FAKE_CALLS"], "a") as calls:\n'
            '    calls.write("evidence-preflight\\n")\n'
            'sys.exit(int(os.environ.get("PREFLIGHT_EXIT", "0")))\n'
        ),
    }.items():
        (root / 'scripts/ios' / name).write_text(code)
    _diagnostic_git(root, 'init', '-q')
    _diagnostic_git(root, 'add', '.')
    _diagnostic_git(root, '-c', 'user.name=Diagnostic Test', '-c', 'user.email=diagnostic@example.invalid',
                    '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Isolated dispatcher fixture')
    return root, _diagnostic_git(root, 'rev-parse', 'HEAD')


def test_focused_diagnostic_actual_trusted_guard_rejects_old_wrong_dirty_or_unreviewed_source(tmp_path: Path) -> None:
    import hashlib
    import pytest
    body = _diagnostic_step('Validate reviewed composed tooling before candidate execution')
    module = _diagnostic_python('DIAGNOSTIC_TOOLING_PY', body)
    guard = module['validate_tooling']
    live_audit = (_REPO_ROOT / 'scripts/ios/launch-quality-audit.sh').read_bytes()
    assert module['REVIEWED_AUDIT_SHA256'] == hashlib.sha256(live_audit).hexdigest() == (
        'c4269ae0051375884a623b1b4d3eafd2afd93cc76f4fe1f61efb9fae23ec3928'
    )
    root, head = _diagnostic_repository(tmp_path)
    script = root / 'scripts/ios/launch-quality-audit.sh'
    expected = hashlib.sha256(script.read_bytes()).hexdigest()
    helper = root / 'scripts/ios/bootstrap-local-config.sh'
    dependencies = {'scripts/ios/bootstrap-local-config.sh': hashlib.sha256(helper.read_bytes()).hexdigest()}
    output = tmp_path / 'guard.json'
    guard(root, head, expected, dependencies, output)
    assert json.loads(output.read_text())['sourceRevision'] == head
    for reviewed in ['', 'marker-only', 'a' * 64, 'afa2a0a00fbe402626c9b07e3ad0c4b96cffe0b5a3a4943104f2001b6e3c7487']:
        with pytest.raises(ValueError):
            guard(root, head, reviewed, dependencies, output)
        assert not output.exists()
    with pytest.raises(ValueError):
        guard(root, head, expected, {'scripts/ios/bootstrap-local-config.sh': '0' * 64}, output)
    with pytest.raises(OSError):
        guard(root, head, expected, {'missing-reviewed-helper': '0' * 64}, output)
    for wrong_source in ['main', 'A' * 40, 'b' * 40]:
        with pytest.raises(ValueError):
            guard(root, wrong_source, expected, dependencies, output)
    helper.write_text('raise RuntimeError("must never execute")\n')
    with pytest.raises(ValueError):
        guard(root, head, expected, dependencies, output)
    _diagnostic_git(root, 'checkout', '--', 'scripts/ios/bootstrap-local-config.sh')
    (root / 'untracked-hook').write_text('must not execute')
    with pytest.raises(ValueError):
        guard(root, head, expected, dependencies, output)
    (root / 'untracked-hook').unlink()
    helper.unlink()
    helper.symlink_to(script)
    with pytest.raises(ValueError):
        guard(root, head, expected, dependencies, output)
    # The bound actual CLI refuses this synthetic/wrong audit before candidate execution.
    helper.unlink()
    _diagnostic_git(root, 'checkout', '--', 'scripts/ios/bootstrap-local-config.sh')
    env = {**os.environ, 'GITHUB_WORKSPACE': str(root), 'CHECKOUT_REF': head, 'RUNNER_TEMP': str(tmp_path)}
    result = subprocess.run(['bash', '-c', body], env=env, capture_output=True, text=True,
                            check=False, pass_fds=_coverage_fds())
    assert result.returncode != 0 and 'diagnostic-mode-unavailable' in result.stderr
    assert not (tmp_path / 'calls').exists()


def test_focused_diagnostic_actual_actor_guard_fails_before_checkout(tmp_path: Path) -> None:
    body = _diagnostic_step('Validate manual diagnostic source')
    fake = tmp_path / 'gh'
    fake.write_text('#!/bin/bash\nset -eu\nprintf "%s\\n" "$2" >> "$FAKE_CALLS"\n'
                    '[[ "${API_FAIL:-}" != true ]] || exit 1\n'
                    'case "$2" in\n*/permission) printf "%s\\n" "${PERMISSION:-write}";;\n'
                    '*/branches-where-head) printf "%s\\n" "${HEAD_PROVEN:-true}";;\n*) exit 1;;\nesac\n')
    fake.chmod(0o700)
    env = {**os.environ, 'PATH': f"{tmp_path}:{os.environ['PATH']}", 'FAKE_CALLS': str(tmp_path / 'calls'),
           'GITHUB_REPOSITORY': 'JovieInc/LogYourBody', 'GITHUB_REF': 'refs/heads/main',
           'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_SHA': 'b' * 40, 'GITHUB_WORKFLOW_SHA': 'b' * 40,
           'GITHUB_WORKFLOW_REF': 'JovieInc/LogYourBody/.github/workflows/ios-ui-diagnostics.yml@refs/heads/main',
           'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_ACTOR': 'writer', 'GITHUB_TRIGGERING_ACTOR': 'writer', 'CHECKOUT_REF': 'a' * 40}
    def run(overrides: dict[str, str]):
        return subprocess.run(['bash', '-c', body], env={**env, **overrides}, text=True,
                              capture_output=True, check=False, pass_fds=_coverage_fds())
    for permission in ['write', 'admin']:
        assert run({'PERMISSION': permission}).returncode == 0
    for overrides in [{'GITHUB_REPOSITORY': 'other/repo'}, {'GITHUB_REF': 'refs/heads/topic'},
                      {'GITHUB_EVENT_NAME': 'push'}, {'CHECKOUT_REF': ''}, {'CHECKOUT_REF': 'main'},
                      {'CHECKOUT_REF': 'A' * 40}, {'GITHUB_RUN_ATTEMPT': '2'},
                      {'GITHUB_WORKFLOW_SHA': 'c' * 40}, {'GITHUB_WORKFLOW_REF': 'candidate-workflow'},
                      {'PERMISSION': 'read'}, {'API_FAIL': 'true'}, {'HEAD_PROVEN': 'false'},
                      {'GITHUB_EVENT_NAME': 'pull_request'}, {'GITHUB_EVENT_NAME': 'workflow_call'}]:
        assert run(overrides).returncode != 0
    # Distinct triggering actor gets its own permission check.
    assert run({'GITHUB_TRIGGERING_ACTOR': 'second-writer'}).returncode == 0
    calls = (tmp_path / 'calls').read_text()
    assert '/collaborators/second-writer/permission' in calls
    # Push and schedule checkout github.sha only. A caller ref is refused, and gh is not consulted.
    for event in ('push', 'schedule'):
        assert run({'GITHUB_EVENT_NAME': event, 'CHECKOUT_REF': 'a' * 40}).returncode != 0
        before = (tmp_path / 'calls').read_text()
        result = run({'GITHUB_EVENT_NAME': event, 'CHECKOUT_REF': ''})
        assert result.returncode == 0, result.stderr
        assert (tmp_path / 'calls').read_text() == before
    for overrides in [{'GITHUB_EVENT_NAME': 'push', 'CHECKOUT_REF': '', 'GITHUB_REF': 'refs/heads/topic'},
                      {'GITHUB_EVENT_NAME': 'schedule', 'CHECKOUT_REF': '', 'GITHUB_WORKFLOW_SHA': 'c' * 40},
                      {'GITHUB_EVENT_NAME': 'push', 'CHECKOUT_REF': '', 'GITHUB_RUN_ATTEMPT': '2'},
                      {'GITHUB_EVENT_NAME': 'schedule', 'CHECKOUT_REF': '', 'GITHUB_SHA': 'main'},
                      {'GITHUB_EVENT_NAME': 'pull_request', 'CHECKOUT_REF': ''}]:
        assert run(overrides).returncode != 0


def _run_diagnostic_dispatch(tmp_path: Path, *, mode: str = '--diagnostic-seven', **overrides: str):
    import sys
    root, head = _diagnostic_repository(tmp_path)
    binary = tmp_path / 'bin'
    binary.mkdir()
    payload, _ = _diagnostic_payload()
    fixture = tmp_path / 'catalogue.json'
    fixture.write_text(json.dumps(payload))
    fake = '''import json, os, pathlib, subprocess, sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['FAKE_CALLS'],'a') as f:f.write(json.dumps([name,*args])+'\\n')
if name=='fake-timeout':
    if ('build-for-testing' in args
            and int(args[1].removesuffix('s')) < int(os.environ.get('BUILD_DURATION_SECONDS','0'))):
        sys.exit(124)
    sys.exit(subprocess.call(args[2:]))
if name=='xcrun':
    if args[:3]==['xcresulttool','get','test-results']:
        if os.environ.get('CATALOGUE_EXIT'):sys.exit(int(os.environ['CATALOGUE_EXIT']))
        print(pathlib.Path(os.environ['FAKE_CATALOGUE']).read_text())
    sys.exit(0)
if 'build-for-testing' in args:sys.exit(int(os.environ.get('BUILD_EXIT','0')))
if '-only-testing:LogYourBodyTests' in args:sys.exit(88)
count=pathlib.Path(os.environ['FAKE_COUNT'])
n=int(count.read_text()) if count.exists() else 0
count.write_text(str(n+1))
if os.environ.get('INFRA_FIRST')=='true' and n==0:
    print('Failed to install or launch the test runner')
    sys.exit(70)
pathlib.Path(args[args.index('-resultBundlePath')+1]).mkdir()
for selector in args:
    if selector.startswith('-only-testing:LogYourBodyUITests/'):
        _,suite,method=selector.split('/')
        print("Test Case '-[LogYourBodyUITests.%s %s]' started."%(suite,method))
        print("Test Case '-[LogYourBodyUITests.%s %s]' passed (0.1 seconds)."%(suite,method))
if os.environ.get('POST_TEST_INFRA')=='true':print('Failed to install or launch the test runner')
sys.exit(int(os.environ.get('UI_EXIT','0')))
'''
    for name in ['xcodebuild', 'xcrun', 'fake-timeout']:
        p = binary / name
        p.write_text('#!' + sys.executable + '\n' + fake)
        p.chmod(0o700)
    sleep = binary / 'sleep'
    sleep.write_text('#!/bin/bash\nexit 0\n')
    sleep.chmod(0o700)
    env = {**os.environ, 'PATH': f"{binary}:{os.environ['PATH']}", 'FAKE_CALLS': str(tmp_path / 'calls'),
           'FAKE_COUNT': str(tmp_path / 'count'), 'FAKE_CATALOGUE': str(fixture),
           'DIAGNOSTIC_EXPECTED_SOURCE_SHA': head, 'ARTIFACT_DIR': str(tmp_path / 'artifacts'),
           'LQ_LAUNCH_PROBE': 'false', 'TIMEOUT_BIN': str(binary / 'fake-timeout'),
           'RUN_SWIFTLINT': 'false', 'RUN_STATIC_UI_REGRESSION_AUDIT': 'false',
           'RUN_OPTICAL_GRID_AUDIT': 'false', **overrides}
    args = [] if not mode else [mode]
    result = subprocess.run(['bash', str(root / 'scripts/ios/launch-quality-audit.sh'), *args],
                            cwd=root, env=env, text=True, capture_output=True, check=False, pass_fds=_coverage_fds())
    calls = (tmp_path / 'calls').read_text().splitlines() if (tmp_path / 'calls').exists() else []
    receipt = tmp_path / 'artifacts/diagnostic-receipt.json'
    return result, calls, json.loads(receipt.read_text()) if receipt.exists() else None


def test_focused_diagnostic_real_dispatcher_builds_once_selects_only_seven_and_never_qualifies(tmp_path: Path) -> None:
    result, calls, receipt = _run_diagnostic_dispatch(tmp_path, BUILD_FOR_TESTING_TIMEOUT_SECONDS='1',
        DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE='999', UI_XCODEBUILD_COMMAND_TIMEOUT_SECONDS='1')
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'evidence-preflight' not in calls
    commands = [json.loads(c) for c in calls if c.startswith('["xcodebuild"')]
    assert len(commands) == 2
    assert 'build-for-testing' in commands[0] and 'test-without-building' in commands[1]
    selectors = [arg for arg in commands[1] if arg.startswith('-only-testing:')]
    assert selectors == ['-only-testing:LogYourBodyUITests/' + i[:-2] for i in _diagnostic_ids()]
    assert 'LogYourBodyTests' not in ' '.join(selectors)
    assert '-parallel-testing-enabled' in commands[1]
    assert commands[1][commands[1].index('-default-test-execution-time-allowance') + 1] == '90'
    assert commands[1][commands[1].index('-maximum-test-execution-time-allowance') + 1] == '180'
    timed = [json.loads(c) for c in calls if c.startswith('["fake-timeout"')]
    assert timed[0][2] == '600s' and timed[1][2] == '1500s'
    assert receipt['status'] == 'passed' and receipt['evidenceKind'] == 'diagnostic_ui_subset'
    assert receipt['qualifying'] is False and receipt['nativeQualification'] is False
    assert len(receipt['tests']) == 7 and receipt['uiCommandAttempts'] == 1
    assert receipt['unitWitnessCoverageRatchetPerformanceProtectedSignedPhysical'] == 'NOT_EXECUTED_OR_QUALIFIED'
    artifacts = tmp_path / 'artifacts'
    assert not list(artifacts.glob('*.evidence.json')) and not list(artifacts.glob('*.coverage.json'))


def test_launch_quality_validator_preflight_finishes_before_simulator_boot_and_failure_stops_native_work(tmp_path: Path) -> None:
    # Exercise the real dispatcher: a booted simulator must not compete with the
    # validator's bounded shell fixtures, and failed preflight must stay fatal.
    for status in (0, 65, 124):
        result, calls, receipt = _run_diagnostic_dispatch(
            tmp_path / str(status), mode='', DESTINATION='auto', PREFLIGHT_EXIT=str(status))
        assert receipt is None
        if status == 0:
            assert result.returncode == 88, result.stdout + result.stderr
            assert calls[:3] == ['evidence-preflight', 'bootstrap', 'destination']
            assert calls.count('evidence-preflight') == 1
            assert any('build-for-testing' in call for call in calls)
            assert any('-only-testing:LogYourBodyTests' in call for call in calls)
        else:
            assert result.returncode == status, result.stdout + result.stderr
            assert calls == ['evidence-preflight']


def test_focused_diagnostic_dispatch_failure_timeout_and_missing_catalogue_never_pass_or_retry_after_tests(tmp_path: Path) -> None:
    for index, overrides in enumerate([{'BUILD_EXIT': '70'}, {'BUILD_EXIT': '124'}, {'UI_EXIT': '124'},
                                       {'UI_EXIT': '70', 'POST_TEST_INFRA': 'true'}, {'CATALOGUE_EXIT': '1'},
                                       {'DIAGNOSTIC_EXPECTED_SOURCE_SHA': 'b' * 40}]):
        result, calls, receipt = _run_diagnostic_dispatch(tmp_path / str(index), **overrides)
        assert result.returncode != 0 and receipt['status'] == 'failed', (result.stdout, result.stderr)
        assert receipt['qualifying'] is False and receipt['nativeQualification'] is False
        commands = [json.loads(c) for c in calls if c.startswith('["xcodebuild"')]
        assert sum('test-without-building' in c for c in commands) <= 1
        if 'BUILD_EXIT' in overrides or 'DIAGNOSTIC_EXPECTED_SOURCE_SHA' in overrides:
            assert not any('test-without-building' in c for c in commands)
        if overrides.get('UI_EXIT') == '124':
            assert 'timeout' in receipt['errors']
        if 'DIAGNOSTIC_EXPECTED_SOURCE_SHA' in overrides:
            assert not calls and 'sourceMismatch' in receipt['errors']


def test_focused_diagnostic_one_ui_command_even_for_infrastructure_failure_and_default_full_are_preserved(tmp_path: Path) -> None:
    result, calls, receipt = _run_diagnostic_dispatch(tmp_path / 'infra', INFRA_FIRST='true')
    assert result.returncode == 70, result.stdout + result.stderr
    assert receipt['uiCommandAttempts'] == 1 and receipt['status'] == 'failed'
    assert sum('test-without-building' in c for c in calls) == 2  # command and timeout wrapper, no second attempt
    assert sum('build-for-testing' in c for c in calls) == 2  # native command and timeout wrapper
    result, calls, receipt = _run_diagnostic_dispatch(tmp_path / 'default', mode='')
    assert result.returncode == 88 and receipt is None, result.stdout + result.stderr
    assert any('-only-testing:LogYourBodyTests' in c for c in calls)
    assert not any('diagnostic-seven.xcresult' in c for c in calls)
    result, calls, receipt = _run_diagnostic_dispatch(tmp_path / 'unknown', mode='--diagnostic-typo')
    assert result.returncode == 64 and not calls and receipt is None


def test_full_launch_cold_build_budget_reaches_the_complete_unit_target(tmp_path: Path) -> None:
    for name, overrides, expected in [
            ('default', {'BUILD_DURATION_SECONDS': '750'}, '900s'),
            ('override', {'BUILD_FOR_TESTING_TIMEOUT_SECONDS': '37', 'BUILD_DURATION_SECONDS': '25'}, '37s')]:
        result, calls, receipt = _run_diagnostic_dispatch(tmp_path / name, mode='', **overrides)
        assert result.returncode == 88 and receipt is None, result.stdout + result.stderr
        timed = [json.loads(c) for c in calls if c.startswith('["fake-timeout"')]
        assert len(timed) == 2
        assert timed[0][2] == expected and 'build-for-testing' in timed[0]
        assert timed[1][2] == '1020s' and '-only-testing:LogYourBodyTests' in timed[1]
        assert '-enableCodeCoverage' in timed[0]
        assert timed[0][timed[0].index('-enableCodeCoverage') + 1] == 'YES'
        assert timed[1][timed[1].index('-default-test-execution-time-allowance') + 1] == '90'
        assert timed[1][timed[1].index('-maximum-test-execution-time-allowance') + 1] == '180'


def test_full_launch_build_failure_or_timeout_stops_without_retry_or_qualification(tmp_path: Path) -> None:
    for name, overrides, status in [
            ('compiler-error', {'BUILD_EXIT': '65'}, 65),
            ('timeout-exit', {'BUILD_EXIT': '124'}, 124),
            ('elapsed-timeout', {'BUILD_DURATION_SECONDS': '901'}, 124)]:
        result, calls, receipt = _run_diagnostic_dispatch(tmp_path / name, mode='', **overrides)
        assert result.returncode == status and receipt is None, result.stdout + result.stderr
        timed = [json.loads(c) for c in calls if c.startswith('["fake-timeout"')]
        assert len(timed) == 1 and 'build-for-testing' in timed[0]
        commands = [json.loads(c) for c in calls if c.startswith('["xcodebuild"')]
        if name == 'elapsed-timeout':
            assert not commands  # The virtual clock expires inside the timeout fixture.
        else:
            assert len(commands) == 1 and 'build-for-testing' in commands[0]
        artifacts = tmp_path / name / 'artifacts'
        log = (artifacts / 'launch-quality-build-for-testing.log').read_text()
        if status == 124:
            assert 'build-for-testing timed out after 900s' in log
        assert not list(artifacts.glob('*.xcresult'))
        assert not list(artifacts.glob('*.evidence.json'))
        assert not list(artifacts.glob('*.coverage.json'))
        assert not (artifacts / 'summary.md').exists()


def test_focused_diagnostic_workflow_has_fixed_nonqualifying_trust_order_and_preserves_pending_runs() -> None:
    source = (_WORKFLOWS / 'ios-ui-diagnostics.yml').read_text()
    assert '  queue: max\n' in source and '  cancel-in-progress: false\n' in source
    assert source.count('concurrency:') == 1 and source.count('  group: lyb-ui-diagnostics-seven\n') == 1
    assert source.index('concurrency:') < source.index('jobs:')
    assert source.count('      checkout-ref:\n') == 1
    for forbidden in ['  pull_request:', '  pull_request_target:', '  workflow_call:', '  workflow_run:', 'uses: ./', 'mac-lane', 'secrets.']:
        assert forbidden not in source
    assert '  push:\n    branches: [main]\n    paths:\n      - .github/workflows/ios-ui-diagnostics.yml\n      - scripts/ios/launch-quality-audit.sh\n      - apps/ios/LogYourBodyUITests/HomeV2LayoutUITests.swift\n' in source
    assert "  schedule:\n    - cron: '0 16 * * *'\n" in source
    assert source.count("github.event_name == 'workflow_dispatch' && inputs.checkout-ref || github.sha") == 1
    assert 'push and schedule refuse a caller checkout ref.' in source
    assert "REVIEWED_AUDIT_SHA256 = 'c4269ae0051375884a623b1b4d3eafd2afd93cc76f4fe1f61efb9fae23ec3928'" in source
    assert source.index('Validate manual diagnostic source') < source.index('- uses: actions/checkout@')
    assert source.index('Validate reviewed composed tooling') < source.index('Select hosted Xcode') < source.index('Run fixed seven-case diagnostic')
    assert 'persist-credentials: false' in source and 'python3 -I -' in source
    assert 'run: bash scripts/ios/launch-quality-audit.sh --diagnostic-seven' in source
    assert 'ios-ui-diagnostic-seven-${{ github.run_id }}-${{ github.run_attempt }}' in source
    assert 'retention-days: 14' in source and 'name: Focused UI Diagnostics (NONQUALIFYING)' in source
    import re
    uses = re.findall(r'uses: ([^\s]+)', source)
    assert len(uses) == 3 and all(re.fullmatch(r'[\w-]+/[\w-]+@[0-9a-f]{40}', value) for value in uses)
