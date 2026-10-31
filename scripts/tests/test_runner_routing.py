"""Regression tests for exact, conservative per-run CI runner routing."""

from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import textwrap
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

import pytest

from diagnostic_fixtures import reviewed_diagnostic_candidate_bytes as _reviewed_diagnostic_candidate_bytes

_REPO_ROOT = Path(__file__).resolve().parents[2]
_WORKFLOWS = _REPO_ROOT / ".github" / "workflows"
_QUERY_SCRIPT = _REPO_ROOT / ".github" / "scripts" / "query-runner-heartbeat.sh"
_AWAIT_SCRIPT = _REPO_ROOT / ".github" / "scripts" / "await-runner-heartbeat.sh"
# Materialize the actual pre-checkout workflow body so Bashcov measures it too.
_DISPATCH_GUARD_SCRIPT = _REPO_ROOT / "coverage/mac-runner-routing/ios-quality-dispatch-guard.sh"
_FIXTURE_GH = (
    _REPO_ROOT / "scripts" / "tests" / "fixtures" / "runner-heartbeat-gh" / "gh"
)


def _coverage_fds() -> tuple[int, ...]:
    # Bashcov traces child Bash processes through this inherited descriptor.
    descriptor = os.environ.get("BASH_XTRACEFD", "")
    return (int(descriptor),) if descriptor.isdigit() else ()


def _job_block(workflow: str, job_name: str) -> str:
    content = (_WORKFLOWS / workflow).read_text(encoding="utf-8")
    marker = f"  {job_name}:\n"
    assert marker in content
    remainder = content.split(marker, 1)[1]
    lines: list[str] = []
    for line in remainder.splitlines():
        if line.startswith("  ") and not line.startswith("    "):
            break
        lines.append(line)
    return "\n".join(lines)


def _fake_gh(tmp_path: Path) -> Path:
    fake = tmp_path / "gh"
    fake.write_text(
        textwrap.dedent(
            """\
            #!/usr/bin/env bash
            set -euo pipefail
            endpoint=''
            for argument in "$@"; do
              if [[ "$argument" == repos/* ]]; then
                endpoint="$argument"
              fi
            done
            if [[ -n "${FAKE_GH_SLEEP_SECONDS:-}" ]]; then
              sleep "$FAKE_GH_SLEEP_SECONDS"
            fi
            if [[ -n "${FAKE_GH_INVOCATION_MARKER:-}" ]]; then
              printf 'invoked\n' >> "$FAKE_GH_INVOCATION_MARKER"
            fi
            if [[ -n "${FAKE_GH_ERROR:-}" ]]; then
              echo "$FAKE_GH_ERROR" >&2
              exit 1
            fi
            if [[ "$endpoint" == *'/jobs?per_page=100' ]]; then
              printf '%s\n' "${FAKE_JOBS_JSON:?}"
            else
              printf '%s\n' "${FAKE_RUNS_JSON:?}"
            fi
            """
        ),
        encoding="utf-8",
    )
    fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
    return fake


def _exact_evidence(
    *,
    observed_at: Optional[str] = None,
    run_updates: Optional[dict[str, Any]] = None,
    job_updates: Optional[dict[str, Any]] = None,
) -> tuple[str, str]:
    if observed_at is None:
        observed_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    head_sha = "a" * 40
    run: dict[str, Any] = {
        "id": 29672288797,
        "run_attempt": 1,
        "name": "Mac Runner Heartbeat",
        "path": ".github/workflows/mac-runner-heartbeat.yml",
        "head_branch": "main",
        "head_sha": head_sha,
        "head_repository": {"full_name": "JovieInc/LogYourBody"},
        "event": "schedule",
        "status": "completed",
        "conclusion": "success",
        "updated_at": observed_at,
        "html_url": "https://github.com/JovieInc/LogYourBody/actions/runs/29672288797",
    }
    if run_updates:
        run.update(run_updates)
    job: dict[str, Any] = {
        "id": 843137,
        "run_id": run["id"],
        "run_attempt": run["run_attempt"],
        "head_sha": run.get("head_sha", head_sha),
        "name": "Self-hosted Mac runner heartbeat",
        "status": "completed",
        "conclusion": "success",
        "runner_id": 55,
        "runner_name": "tw-mac-001",
        # Live API proof returns requested job labels, not all registration labels.
        "labels": ["jovie-mac"],
    }
    if job_updates:
        job.update(job_updates)
    return json.dumps({"workflow_runs": [run]}), json.dumps([{"jobs": [job]}])


def _run_query(
    tmp_path: Path,
    *,
    runs_json: Optional[str] = None,
    jobs_json: Optional[str] = None,
    api_error: str = "",
    sleep_seconds: str = "",
    timeout_seconds: str = "20",
    expected_event: str = "",
    expected_sha: str = "",
    github_actions_context: bool = False,
    invocation_marker: Optional[Path] = None,
) -> tuple[subprocess.CompletedProcess[str], dict[str, str]]:
    tmp_path.mkdir(parents=True, exist_ok=True)
    fake_gh = _fake_gh(tmp_path)
    if runs_json is None or jobs_json is None:
        exact_runs, exact_jobs = _exact_evidence()
        runs_json = exact_runs if runs_json is None else runs_json
        jobs_json = exact_jobs if jobs_json is None else jobs_json
    output = tmp_path / "github-output"
    env = os.environ.copy()
    # Fixture injection is deliberately unavailable to production Actions
    # invocations. The test subprocess opts out of that parent context and
    # passes the exact helper path instead of relying on PATH resolution.
    env.pop("GITHUB_ACTIONS", None)
    env.update(
        {
            "GH_REPO": "JovieInc/LogYourBody",
            "HEARTBEAT_WORKFLOW": "mac-runner-heartbeat.yml",
            "GITHUB_OUTPUT": str(output),
            "HEARTBEAT_GH_TEST_HELPER": str(fake_gh),
            "HEARTBEAT_GH_TEST_MODE": "1",
            "HEARTBEAT_MAX_AGE_SECONDS": "900",
            "HEARTBEAT_API_TIMEOUT_SECONDS": timeout_seconds,
            "HEARTBEAT_EXPECTED_EVENT": expected_event,
            "HEARTBEAT_EXPECTED_SHA": expected_sha,
            "FAKE_RUNS_JSON": runs_json,
            "FAKE_JOBS_JSON": jobs_json,
            "FAKE_GH_ERROR": api_error,
            "FAKE_GH_SLEEP_SECONDS": sleep_seconds,
            "FAKE_GH_INVOCATION_MARKER": (
                str(invocation_marker) if invocation_marker is not None else ""
            ),
        }
    )
    if github_actions_context:
        env["GITHUB_ACTIONS"] = "true"
    result = subprocess.run(
        ["bash", str(_QUERY_SCRIPT)],
        cwd=_REPO_ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False, pass_fds=_coverage_fds(),
    )
    outputs: dict[str, str] = {}
    if output.exists():
        for line in output.read_text(encoding="utf-8").splitlines():
            key, value = line.split("=", 1)
            outputs[key] = value
    return result, outputs


def _run_fixture_query(
    tmp_path: Path,
    scenario: str,
    *,
    attempts: int = 3,
) -> tuple[subprocess.CompletedProcess[str], dict[str, str], int]:
    tmp_path.mkdir(parents=True, exist_ok=True)
    state_dir = tmp_path / "fixture-state"
    output = tmp_path / "github-output"
    fake_sleep = tmp_path / "sleep"
    fake_sleep.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    fake_sleep.chmod(fake_sleep.stat().st_mode | stat.S_IXUSR)
    env = os.environ.copy()
    env.pop("GITHUB_ACTIONS", None)
    env.update(
        {
            "PATH": f"{tmp_path}:{env['PATH']}",
            "GH_REPO": "JovieInc/LogYourBody",
            "HEARTBEAT_WORKFLOW": "mac-runner-heartbeat.yml",
            "GITHUB_OUTPUT": str(output),
            "HEARTBEAT_GH_TEST_HELPER": str(_FIXTURE_GH),
            "HEARTBEAT_GH_TEST_MODE": "1",
            "HEARTBEAT_MAX_AGE_SECONDS": "900",
            "HEARTBEAT_API_TIMEOUT_SECONDS": "5",
            "HEARTBEAT_JOB_POLL_ATTEMPTS": str(attempts),
            "HEARTBEAT_JOB_POLL_INTERVAL_SECONDS": "1",
            "HEARTBEAT_FIXTURE_SCENARIO": scenario,
            "HEARTBEAT_FIXTURE_STATE_DIR": str(state_dir),
        }
    )
    result = subprocess.run(
        ["bash", str(_QUERY_SCRIPT)],
        cwd=_REPO_ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False, pass_fds=_coverage_fds(),
    )
    outputs: dict[str, str] = {}
    if output.exists():
        for line in output.read_text(encoding="utf-8").splitlines():
            key, value = line.split("=", 1)
            outputs[key] = value
    jobs_count_file = state_dir / "jobs-count"
    jobs_count = int(jobs_count_file.read_text(encoding="utf-8"))
    return result, outputs, jobs_count


def _run_await(
    tmp_path: Path,
    states: list[tuple[str, str, str]],
    *,
    attempts: int,
) -> tuple[subprocess.CompletedProcess[str], dict[str, str], int]:
    tmp_path.mkdir(parents=True, exist_ok=True)
    state_file = tmp_path / "states"
    state_file.write_text(
        "\n".join("|".join(state) for state in states) + "\n", encoding="utf-8"
    )
    count_file = tmp_path / "count"
    query = tmp_path / "query"
    query.write_text(
        textwrap.dedent(
            """\
            #!/usr/bin/env bash
            set -euo pipefail
            count=0
            [[ ! -f "$FAKE_QUERY_COUNT" ]] || count="$(cat "$FAKE_QUERY_COUNT")"
            count=$((count + 1))
            echo "$count" > "$FAKE_QUERY_COUNT"
            record="$(sed -n "${count}p" "$FAKE_QUERY_STATES")"
            if [[ -z "$record" ]]; then
              record="$(tail -n 1 "$FAKE_QUERY_STATES")"
            fi
            IFS='|' read -r health probe_state evidence <<< "$record"
            {
              echo "health=$health"
              echo "probe_state=$probe_state"
              echo "evidence=$evidence"
            } >> "$GITHUB_OUTPUT"
            """
        ),
        encoding="utf-8",
    )
    query.chmod(query.stat().st_mode | stat.S_IXUSR)
    fake_sleep = tmp_path / "sleep"
    fake_sleep.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    fake_sleep.chmod(fake_sleep.stat().st_mode | stat.S_IXUSR)
    output = tmp_path / "github-output"
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{tmp_path}:{env['PATH']}",
            "GITHUB_OUTPUT": str(output),
            "RUNNER_HEARTBEAT_QUERY_HELPER": str(query),
            "HEARTBEAT_POLL_ATTEMPTS": str(attempts),
            "HEARTBEAT_POLL_INTERVAL_SECONDS": "1",
            "FAKE_QUERY_COUNT": str(count_file),
            "FAKE_QUERY_STATES": str(state_file),
        }
    )
    result = subprocess.run(
        ["bash", str(_AWAIT_SCRIPT)],
        cwd=_REPO_ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False, pass_fds=_coverage_fds(),
    )
    outputs: dict[str, str] = {}
    if output.exists():
        for line in output.read_text(encoding="utf-8").splitlines():
            key, value = line.split("=", 1)
            outputs[key] = value
    count = int(count_file.read_text(encoding="utf-8")) if count_file.exists() else 0
    return result, outputs, count


def test_exact_fresh_run_and_job_prove_fixed_runner_health(tmp_path: Path) -> None:
    result, outputs = _run_query(tmp_path)

    assert result.returncode == 0, result.stderr
    assert outputs["health"] == "up", outputs
    assert outputs["probe_state"] == "healthy"
    assert "run 29672288797 attempt 1" in outputs["evidence"]


def test_terminal_run_with_lagging_job_polls_same_attempt_to_settled_success(
    tmp_path: Path,
) -> None:
    result, outputs, jobs_count = _run_fixture_query(
        tmp_path, "lagging-then-settled"
    )

    assert result.returncode == 0, result.stderr
    assert jobs_count == 2
    assert outputs["health"] == "up", outputs
    assert outputs["probe_state"] == "healthy"
    assert "run 29989764821 attempt 1" in outputs["evidence"]


def test_persistent_lag_times_out_fail_closed_after_bounded_job_polls(
    tmp_path: Path,
) -> None:
    result, outputs, jobs_count = _run_fixture_query(
        tmp_path, "persistent-lag", attempts=3
    )

    assert result.returncode == 0, result.stderr
    assert jobs_count == 3
    assert outputs["health"] == "down"
    assert outputs["probe_state"] == "unhealthy"
    assert "remained unsettled after 3 observations" in outputs["evidence"]


def test_job_identity_drift_missing_label_and_non_success_fail_closed(
    tmp_path: Path,
) -> None:
    cases = (
        ("wrong-identity", "uncertain"),
        ("changed-evidence", "uncertain"),
        ("missing-label", "uncertain"),
        ("failed", "unhealthy"),
    )

    for scenario, expected_state in cases:
        result, outputs, _ = _run_fixture_query(tmp_path / scenario, scenario)

        assert result.returncode == 0, result.stderr
        assert outputs["health"] == "down"
        assert outputs["probe_state"] == expected_state, outputs


def test_production_actions_context_cannot_authorize_test_gh_helper(
    tmp_path: Path,
) -> None:
    marker = tmp_path / "fake-gh-invoked"
    result, outputs = _run_query(
        tmp_path,
        github_actions_context=True,
        invocation_marker=marker,
    )

    assert result.returncode == 0, result.stderr
    assert outputs == {
        "health": "down",
        "probe_state": "uncertain",
        "evidence": "heartbeat gh test helper is not authorized",
    }
    assert not marker.exists()


def test_current_exact_queued_or_in_progress_probe_is_the_only_retryable_state(
    tmp_path: Path,
) -> None:
    head_sha = "a" * 40
    for status in ("queued", "in_progress"):
        runs_json, jobs_json = _exact_evidence(
            run_updates={
                "event": "push",
                "status": status,
                "conclusion": None,
            }
        )
        result, outputs = _run_query(
            tmp_path / status,
            runs_json=runs_json,
            jobs_json=jobs_json,
            expected_event="push",
            expected_sha=head_sha,
        )

        assert result.returncode == 0, result.stderr
        assert outputs["health"] == "down"
        assert outputs["probe_state"] == "pending", outputs
        assert f"status={status}" in outputs["evidence"]


def test_current_merge_group_probe_requires_exact_queue_ref_and_sha(
    tmp_path: Path,
) -> None:
    head_sha = "a" * 40
    exact_runs, exact_jobs = _exact_evidence(
        run_updates={
            "event": "merge_group",
            "head_branch": "gh-readonly-queue/main/pr-14469-c3d181de6800",
        }
    )
    accepted, accepted_outputs = _run_query(
        tmp_path / "accepted",
        runs_json=exact_runs,
        jobs_json=exact_jobs,
        expected_event="merge_group",
        expected_sha=head_sha,
    )
    wrong_sha, wrong_sha_outputs = _run_query(
        tmp_path / "wrong-sha",
        runs_json=exact_runs,
        jobs_json=exact_jobs,
        expected_event="merge_group",
        expected_sha="b" * 40,
    )

    assert accepted.returncode == 0, accepted.stderr
    assert accepted_outputs["health"] == "up", accepted_outputs
    assert accepted_outputs["probe_state"] == "healthy"
    assert wrong_sha.returncode == 0, wrong_sha.stderr
    assert wrong_sha_outputs["health"] == "down"
    assert wrong_sha_outputs["probe_state"] == "uncertain"


def test_stale_success_failed_probe_and_api_uncertainty_never_poll(
    tmp_path: Path,
) -> None:
    head_sha = "a" * 40
    stale_at = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat().replace(
        "+00:00", "Z"
    )
    stale_runs, stale_jobs = _exact_evidence(
        observed_at=stale_at,
        run_updates={"event": "push"},
    )
    failed_runs, failed_jobs = _exact_evidence(
        run_updates={"event": "push", "conclusion": "failure"}
    )
    cases = (
        (stale_runs, stale_jobs, "", "unhealthy"),
        (failed_runs, failed_jobs, "", "unhealthy"),
        (None, None, "HTTP 503: unavailable", "uncertain"),
    )

    for index, (runs_json, jobs_json, api_error, expected_state) in enumerate(cases):
        case_dir = tmp_path / str(index)
        case_dir.mkdir()
        result, outputs = _run_query(
            case_dir,
            runs_json=runs_json,
            jobs_json=jobs_json,
            api_error=api_error,
            expected_event="push",
            expected_sha=head_sha,
        )
        assert result.returncode == 0, result.stderr
        assert outputs["health"] == "down"
        assert outputs["probe_state"] == expected_state, outputs


def test_bounded_observer_polls_pending_then_accepts_exact_success(
    tmp_path: Path,
) -> None:
    result, outputs, count = _run_await(
        tmp_path,
        [
            ("down", "pending", "current exact heartbeat is status=in_progress"),
            ("up", "healthy", "current exact heartbeat succeeded"),
        ],
        attempts=3,
    )

    assert result.returncode == 0, result.stderr
    assert count == 2
    assert outputs["health"] == "up"
    assert outputs["probe_state"] == "healthy"


def test_offline_pending_probe_falls_back_after_exact_observation_bound(
    tmp_path: Path,
) -> None:
    result, outputs, count = _run_await(
        tmp_path,
        [("down", "pending", "current exact heartbeat is status=queued")],
        attempts=3,
    )

    assert result.returncode == 0, result.stderr
    assert count == 3
    assert outputs["health"] == "down"
    assert outputs["probe_state"] == "unhealthy"
    assert "remained pending after 3 observations" in outputs["evidence"]


def test_uncertain_or_failed_probe_selects_hosted_without_retry(
    tmp_path: Path,
) -> None:
    for index, state in enumerate(("uncertain", "unhealthy")):
        result, outputs, count = _run_await(
            tmp_path / str(index),
            [("down", state, f"{state} evidence")],
            attempts=10,
        )
        assert result.returncode == 0, result.stderr
        assert count == 1
        assert outputs["health"] == "down"
        assert outputs["probe_state"] == state
        assert "using hosted capacity" in outputs["evidence"]


def test_missing_stale_or_incomplete_evidence_degrades_to_hosted(
    tmp_path: Path,
) -> None:
    stale_at = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat().replace(
        "+00:00", "Z"
    )
    stale_runs, stale_jobs = _exact_evidence(observed_at=stale_at)
    queued_runs, queued_jobs = _exact_evidence(
        run_updates={"status": "queued", "conclusion": None}
    )
    cases = (
        (json.dumps({"workflow_runs": []}), json.dumps([])),
        (stale_runs, stale_jobs),
        (queued_runs, queued_jobs),
    )

    for index, (runs_json, jobs_json) in enumerate(cases):
        case_dir = tmp_path / str(index)
        case_dir.mkdir()
        result, outputs = _run_query(
            case_dir,
            runs_json=runs_json,
            jobs_json=jobs_json,
        )
        assert result.returncode == 0, result.stderr
        assert outputs["health"] == "down"


def test_api_error_timeout_and_malformed_schema_degrade_without_raw_leak(
    tmp_path: Path,
) -> None:
    cases = (
        {"api_error": "HTTP 403: secret diagnostic"},
        {"sleep_seconds": "2", "timeout_seconds": "1"},
        {"runs_json": json.dumps({"workflow_runs": "not-an-array"})},
    )

    for index, case in enumerate(cases):
        case_dir = tmp_path / str(index)
        case_dir.mkdir()
        result, outputs = _run_query(case_dir, **case)
        assert result.returncode == 0, result.stderr
        assert outputs["health"] == "down"
        assert "secret diagnostic" not in result.stdout
        assert "secret diagnostic" not in result.stderr


def test_wrong_run_identity_or_job_attestation_degrades_to_hosted(
    tmp_path: Path,
) -> None:
    wrong_repo = _exact_evidence(
        run_updates={"head_repository": {"full_name": "attacker/fork"}}
    )
    wrong_run_id = _exact_evidence(job_updates={"run_id": 42})
    wrong_head = _exact_evidence(job_updates={"head_sha": "b" * 40})
    missing_label = _exact_evidence(job_updates={"labels": ["ubuntu-latest"]})
    missing_runner = _exact_evidence(job_updates={"runner_id": 0, "runner_name": ""})

    for index, (runs_json, jobs_json) in enumerate(
        (wrong_repo, wrong_run_id, wrong_head, missing_label, missing_runner)
    ):
        case_dir = tmp_path / str(index)
        case_dir.mkdir()
        result, outputs = _run_query(
            case_dir,
            runs_json=runs_json,
            jobs_json=jobs_json,
        )
        assert result.returncode == 0, result.stderr
        assert outputs["health"] == "down"


def _ruby_setup_step(name: str) -> str:
    action = (_REPO_ROOT / '.github/actions/setup-ruby-bundler/action.yml').read_text()
    return action.split(f'    - name: {name}\n', 1)[1].split('\n    - name:', 1)[0]


def _ruby_setup_body(name: str) -> str:
    body = _ruby_setup_step(name).split('      run: ', 1)[1]
    return textwrap.dedent(body[2:]) if body.startswith('|\n') else body


def test_ruby_bundle_cache_separates_runtime_builds_and_runner_platforms(tmp_path: Path) -> None:
    import re

    # Execute the action's real Ruby identity calculation, including two Ruby
    # builds with the same version but different native extension configuration.
    def identity(label: str, config_change: str = '') -> dict[str, str]:
        output = tmp_path / f'{label}.output'
        preload = tmp_path / f'{label}.rb'
        preload.write_text('require "rbconfig"\n' + config_change)
        result = subprocess.run(
            ['bash', '-e', '-o', 'pipefail', '-c', _ruby_setup_body('Get Ruby version')],
            env={**os.environ, 'GITHUB_OUTPUT': str(output), 'RUBYOPT': f'-r{preload}'},
            text=True, capture_output=True, check=False, pass_fds=_coverage_fds(),
        )
        assert result.returncode == 0, result.stderr
        return dict(line.split('=', 1) for line in output.read_text().splitlines())

    current = identity('current')
    assert current == identity('repeat')
    assert re.fullmatch('[0-9a-f]{64}', current['abi'])
    for index, setting in enumerate(['arch', 'configure_args']):
        changed = identity(str(index), f'RbConfig::CONFIG["{setting}"] += "-other-build"\n')
        assert current['version'] == changed['version']
        assert current['abi'] != changed['abi']

    cache = _ruby_setup_step('Cache Ruby dependencies')
    key = cache.split('        key: ', 1)[1].splitlines()[0]
    restore = cache.split('        restore-keys: |\n', 1)[1].strip().splitlines()
    values = {
        'runner.os': 'macOS', 'runner.arch': 'ARM64', 'runner.environment': 'self-hosted',
        'inputs.cache-key-prefix': 'ios-gems', 'steps.ruby-version.outputs.version': current['version'],
        'steps.ruby-version.outputs.abi': current['abi'], 'steps.gemfile-hash.outputs.hash': 'lock-a',
    }

    def render(template: str, overrides: dict[str, str]) -> str:
        context = {**values, **overrides}
        return re.sub(r'\$\{\{\s*(.*?)\s*\}\}', lambda match: context[match[1]], template)

    current_key = render(key, {})
    prefixes = [render(template, {}) for template in restore]
    assert prefixes and all(current_key.startswith(prefix) for prefix in prefixes)
    for field, other in [
        ('runner.os', 'Linux'), ('runner.arch', 'X64'), ('runner.environment', 'github-hosted'),
        ('steps.ruby-version.outputs.version', 'other-version'),
        ('steps.ruby-version.outputs.abi', 'other-build'),
    ]:
        assert not any(render(key, {field: other}).startswith(prefix) for prefix in prefixes)
    # A changed lock can reuse only a compatible runtime cache; the rejected
    # pre-ABI cache from the merge-group log must never match a restore prefix.
    assert any(render(key, {'steps.gemfile-hash.outputs.hash': 'lock-b'}).startswith(prefix)
               for prefix in prefixes)
    legacy = 'macOS-ios-gems-ruby-3.1.7p261-7236275de00f433e3174f60973f80e2325ceef9f'
    assert not any(legacy.startswith(prefix) for prefix in prefixes)


def test_ruby_bundle_restore_clears_persistent_native_gems_only(tmp_path: Path) -> None:
    bundle = tmp_path / 'vendor/bundle/ruby/3.1.0/gems/date/lib'
    bundle.mkdir(parents=True)
    (bundle / 'date_core.bundle').write_text('incompatible cached native extension')
    retained = tmp_path / 'vendor/JovieKit/Package.swift'
    retained.parent.mkdir()
    retained.write_text('retained vendored package')
    result = subprocess.run(
        ['bash', '-e', '-c', _ruby_setup_body('Clear stale bundle before cache restore')],
        cwd=tmp_path, text=True, capture_output=True, check=False, pass_fds=_coverage_fds(),
    )
    assert result.returncode == 0, result.stderr
    assert not (tmp_path / 'vendor/bundle').exists()
    assert retained.read_text() == 'retained vendored package'
    action = (_REPO_ROOT / '.github/actions/setup-ruby-bundler/action.yml').read_text()
    assert action.index('Clear stale bundle before cache restore') < action.index('Cache Ruby dependencies')
    assert 'working-directory: ${{ inputs.working-directory }}' in _ruby_setup_step(
        'Clear stale bundle before cache restore')


def test_ruby_bundle_verification_rejects_unloadable_native_extensions(tmp_path: Path) -> None:
    fake_bundle = tmp_path / 'bundle'
    fake_bundle.write_text('''#!/usr/bin/env bash
if [[ "$1" == exec ]]; then
  [[ "$*" == *'require "date"'* && "$*" == *'require "psych"'* && "$*" == *'require "json"'* ]] || exit 99
  if [[ "$BROKEN_NATIVE_GEM" == true ]]; then
    echo 'LoadError: date_core.bundle: Symbol not found: _rb_cFalseClass' >&2
    exit 1
  fi
fi
''')
    fake_bundle.chmod(0o755)
    for broken in ['true', 'false']:
        result = subprocess.run(
            ['bash', '-e', '-o', 'pipefail', '-c', _ruby_setup_body('Verify Ruby setup')],
            env={**os.environ, 'PATH': f'{tmp_path}:{os.environ["PATH"]}', 'BROKEN_NATIVE_GEM': broken},
            text=True, capture_output=True, check=False, pass_fds=_coverage_fds(),
        )
        assert result.returncode == (1 if broken == 'true' else 0), result.stderr


_MAC_LANE_SCRIPT = _REPO_ROOT / ".github" / "scripts" / "mac-lane.sh"
_SELF_HOSTED_MAC = 'fromJSON(\'["self-hosted","macOS","ARM64","jovie-mac"]\')'
_MANUAL_QUALITY_DISPATCH = "github.event_name == 'workflow_dispatch' && startsWith(github.workflow_ref, format('{0}/.github/workflows/ios-quality.yml@', github.repository))"
_IOS_LANES = {"ios": ("ios-unit.yml", "unit"), "ios_quality": ("ios-quality.yml", "quality")}
# Unit gates merge groups; Launch Quality gates the PR head (.github/scripts/detect-changes.sh).
_IOS_LANE_OUTPUTS = {"ios": "ios_unit", "ios_quality": "ios_quality"}


def test_required_ios_jobs_try_an_idle_mac_and_never_hold_on_one() -> None:
    # Org rule (JovieInc/Jovie .claude/rules/infra.md "macOS runners"): an idle
    # Mac first, hosted otherwise; nothing waits on a busy, asleep or offline
    # Mac. A job queued straight on jovie-mac would wait 24h for a Mac that
    # disappears after routing, so Mac work runs only in a mac-lane.yml child
    # run that the route cancels when no Mac picks it up.
    workflow = (_WORKFLOWS / "ci.yml").read_text()
    assert "jovie-mac" not in workflow
    assert "heartbeat" not in workflow
    child = (_WORKFLOWS / "mac-lane.yml").read_text()
    assert "cancel-in-progress: true" in child
    for name, (reusable, work) in _IOS_LANES.items():
        job = _job_block("ci.yml", name)
        assert f"    uses: ./.github/workflows/{reusable}" in job.splitlines()
        # ios_quality stays hosted until its capture tests pass on the Macs.
        mac_first = "true" if name == "ios" else "false"
        assert f"      mac-first: {mac_first}" in job.splitlines()
        assert "    needs: detect-changes" in job.splitlines()
        assert f"if: needs.detect-changes.outputs.{_IOS_LANE_OUTPUTS[name]} == 'true'" in job
        assert f"uses: ./.github/workflows/{reusable}" in child
        lane = _job_block(reusable, work)
        manual_guard = f"!({_MANUAL_QUALITY_DISPATCH}) && " if name == "ios_quality" else ""
        assert f"runs-on: ${{{{ {manual_guard}inputs.mac-child && {_SELF_HOSTED_MAC} || 'macos-15' }}}}" in lane
        assert "needs.mac.outputs.run_hosted == 'true'" in lane
        assert "uses: ./.github/workflows/mac-lane-route.yml" in _job_block(reusable, "mac")
    assert child.count("group: ${{ inputs.join-group }}") == len(_IOS_LANES)
    for path in _WORKFLOWS.glob("*.yml"):
        for line in path.read_text().splitlines():
            if "runs-on:" in line and "jovie-mac" in line and path.name != "mac-runner-heartbeat.yml":
                assert "inputs.mac-child && fromJSON" in line, f"{path.name}: {line}"


def test_mac_route_uses_first_attempts_of_trusted_events_only() -> None:
    route = (_WORKFLOWS / "mac-lane-route.yml").read_text()
    assert (
        "      vars.JOVIE_MAC_RUNNER != 'off' &&\n"
        "      github.run_attempt == '1' &&\n"
    ) in route
    assert "group: ${{ needs.dispatch.outputs.join_group }}" in route
    assert (
        "value: ${{ jobs.dispatch.outputs.fallback != 'false' || jobs.join.outputs.infra != 'false' }}"
        in route
    )
    assert "secrets." not in route
    assert "schedule:" not in route


def test_hosted_ios_jobs_retain_existing_test_quality_and_summary_gates() -> None:
    assert 'bundle exec fastlane ci_ios' in _job_block('ios-unit.yml', 'unit')
    assert 'ci_test_unit' in _job_block('ios-unit.yml', 'unit')
    quality = _job_block('ios-quality.yml', 'quality')
    assert 'launch-quality-audit.sh' in quality
    assert 'performance-audit.sh' in quality
    assert 'timeout-minutes: 64' in quality
    assert 'timeout-minutes: 52' in quality
    summary = _job_block('ci.yml', 'ci-summary')
    assert 'assert_expected_result "iOS Launch Quality Gate"' in summary
    assert 'mac-runner-routing-tests' in summary
    assert 'setup-canary' not in summary
    assert 'heartbeat' not in summary


def test_unit_reuses_package_cache_without_archiving_test_builds() -> None:
    # Run 40648671494 passed Unit and coverage, then hit the 40m job cap
    # uploading 4.2 GB of DerivedData. Setup already owns the package cache.
    unit = _job_block('ios-unit.yml', 'unit')
    assert 'uses: ./.github/actions/setup-ios-build' in unit
    assert 'working-directory: apps/ios' in unit
    assert 'actions/cache' not in unit, 'reuse setup package cache; do not archive Unit build outputs'
    assert 'timeout-minutes: 40' in unit
    setup = (_REPO_ROOT / '.github/actions/setup-ios-build/action.yml').read_text()
    cache = setup.split('    - name: Cache Swift Package Manager\n', 1)[1].split('\n    - name:', 1)[0]
    assert "if: runner.environment == 'github-hosted'" in cache
    assert 'uses: actions/cache@' in cache
    paths = cache.split('        path: |\n', 1)[1].split('        key:', 1)[0]
    assert [line.strip() for line in paths.splitlines() if line.strip()] == [
        '${{ inputs.working-directory }}/SourcePackages',
        '~/Library/Developer/Xcode/DerivedData/**/SourcePackages',
    ]


def _run_manual_quality_guard(tmp_path: Path, **overrides: str) -> subprocess.CompletedProcess[str]:
    quality = _job_block("ios-quality.yml", "quality")
    guard_step = quality.split("      - name: Validate manual qualification source\n", 1)[1]
    guard = textwrap.dedent(guard_step.split("        run: |\n", 1)[1].split("\n      - uses:", 1)[0])
    _DISPATCH_GUARD_SCRIPT.parent.mkdir(parents=True, exist_ok=True)
    _DISPATCH_GUARD_SCRIPT.write_text(guard, encoding="utf-8")
    tmp_path.mkdir(parents=True, exist_ok=True)
    fake = tmp_path / "gh"
    fake.write_text(textwrap.dedent("""\
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$2" >> "$FAKE_GH_INVOCATION_MARKER"
        [[ "${FAKE_GH_ERROR:-}" != 'true' ]] || exit 1
        case "$2" in
          */collaborators/*/permission)
            payload="$FAKE_PERMISSION_JSON"
            [[ "$2" != */collaborators/reader/permission ]] || payload='{"permission":"read"}'
            ;;
          */branches-where-head) payload="$FAKE_BRANCHES_JSON" ;;
          *) exit 1 ;;
        esac
        printf '%s' "$payload" | jq -r "$4"
        """), encoding="utf-8")
    fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
    env = {**os.environ, "PATH": f"{tmp_path}:{os.environ['PATH']}",
           "GITHUB_REPOSITORY": "JovieInc/LogYourBody", "GITHUB_REF": "refs/heads/main",
           "GITHUB_ACTOR": "writer", "GITHUB_TRIGGERING_ACTOR": "writer", "CHECKOUT_REF": "a" * 40,
           "FAKE_PERMISSION_JSON": '{"permission":"write"}',
           "FAKE_BRANCHES_JSON": json.dumps([{"name": "codex/qualification", "commit": {"sha": "a" * 40}}]),
           "FAKE_GH_INVOCATION_MARKER": str(tmp_path / "api-calls"), **overrides}
    return subprocess.run(["bash", str(_DISPATCH_GUARD_SCRIPT)], cwd=_REPO_ROOT, env=env,
                          text=True, capture_output=True, check=False, pass_fds=_coverage_fds())


def test_manual_quality_dispatch_uses_trusted_workflow_and_same_hosted_audit() -> None:
    workflow = (_WORKFLOWS / "ios-quality.yml").read_text()
    dispatch = workflow.split("  workflow_dispatch:\n", 1)[1].split("  workflow_call:", 1)[0]
    assert "      checkout-ref:\n" in dispatch
    assert "        required: true\n        type: string" in dispatch
    assert "mac-first:" not in dispatch and "mac-child:" not in dispatch
    assert f"!({_MANUAL_QUALITY_DISPATCH}) && inputs.mac-first && !inputs.mac-child" in _job_block("ios-quality.yml", "mac")
    quality = _job_block("ios-quality.yml", "quality")
    assert quality.index("Validate manual qualification source") < quality.index("uses: actions/checkout@v4")
    assert "if: ${{ " + _MANUAL_QUALITY_DISPATCH + " }}" in quality
    assert "CHECKOUT_REF: ${{ inputs.checkout-ref }}" in quality
    assert "ref: ${{ inputs.checkout-ref || github.sha }}" in quality
    assert "persist-credentials: ${{ !(" + _MANUAL_QUALITY_DISPATCH + ") }}" in quality
    assert f"!({_MANUAL_QUALITY_DISPATCH}) && inputs.mac-child &&" in quality
    assert quality.count("run: bash scripts/ios/launch-quality-audit.sh") == 1
    assert "ARTIFACT_DIR: ${{ github.workspace }}/apps/ios/test_results/quality-gate/ci-${{ github.run_id }}/launch-quality" in quality
    assert "path: apps/ios/test_results/quality-gate/ci-${{ github.run_id }}" in quality
    assert "permissions:\n  contents: read\n" in workflow and "secrets." not in workflow


def test_manual_quality_checkout_retains_canonical_comparison_history(tmp_path: Path) -> None:
    import re

    quality = _job_block("ios-quality.yml", "quality")
    checkout = quality.split("      - uses: actions/checkout@v4\n", 1)[1].split("\n      - ", 1)[0]
    configured_depth = re.search(r"^          fetch-depth: (\d+)$", checkout, re.MULTILINE)
    depth = int(configured_depth.group(1)) if configured_depth else 1

    def git(directory: Path, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-c", "commit.gpgsign=false", "-c", "protocol.file.allow=always",
             "-C", str(directory), *arguments], text=True, capture_output=True, check=check,
        )

    origin = tmp_path / "origin"
    origin.mkdir()
    git(origin, "init", "-q", "-b", "main")
    git(origin, "config", "user.name", "Qualification fixture")
    git(origin, "config", "user.email", "fixture@example.invalid")
    (origin / "source").write_text("base")
    git(origin, "add", ".")
    git(origin, "commit", "-qm", "base")
    base = git(origin, "rev-parse", "HEAD").stdout.strip()
    (origin / "source").write_text("canonical")
    git(origin, "commit", "-qam", "canonical")
    canonical = git(origin, "rev-parse", "HEAD").stdout.strip()
    git(origin, "checkout", "-qb", "candidate")
    (origin / "source").write_text("candidate")
    git(origin, "commit", "-qam", "candidate")
    candidate = git(origin, "rev-parse", "HEAD").stdout.strip()

    def fetch_checkout(name: str, fetch_depth: int) -> Path:
        directory = tmp_path / name
        directory.mkdir()
        git(directory, "init", "-q")
        git(directory, "remote", "add", "origin", origin.as_uri())
        # Match checkout@v4: SHA-only uses no destination ref at positive depth;
        # depth0 fetches all branch refs before checking out the requested SHA.
        if fetch_depth > 0:
            git(directory, "fetch", "--no-tags", f"--depth={fetch_depth}", "origin", candidate)
        else:
            git(directory, "fetch", "--no-tags", "origin", "+refs/heads/*:refs/remotes/origin/*")
        git(directory, "checkout", "--detach", candidate)
        assert git(directory, "rev-parse", "HEAD").stdout.strip() == candidate
        return directory

    shallow = fetch_checkout("depth1-counterfactual", 1)
    assert git(shallow, "rev-parse", "--verify", "refs/remotes/origin/main^{commit}", check=False).returncode != 0
    assert git(shallow, "rev-parse", "--verify", canonical + "^{commit}", check=False).returncode != 0

    actual = fetch_checkout("workflow-configured", depth)
    assert git(actual, "rev-parse", "--verify", "refs/remotes/origin/main^{commit}").stdout.strip() == canonical
    assert git(actual, "rev-parse", "--verify", "refs/remotes/origin/main^").stdout.strip() == base
    assert git(actual, "rev-parse", "--verify", canonical + "^{commit}").stdout.strip() == canonical


def test_manual_quality_selection_preserves_reusable_dispatch_callers() -> None:
    import re
    from types import SimpleNamespace

    quality = _job_block("ios-quality.yml", "quality")
    mac = _job_block("ios-quality.yml", "mac")
    guard = quality.split("      - name: Validate manual qualification source\n", 1)[1]
    expressions = [next(line for line in block.splitlines() if line.strip().startswith(prefix))
                   for block, prefix in ((guard, "if:"), (mac, "if:"), (quality, "runs-on:"))]
    for event, caller, mac_first, mac_child, expected_guard, expected_mac, expected_runner in (
        ("workflow_dispatch", "ios-quality.yml", True, True, True, False, "macos-15"),
        ("workflow_dispatch", "mac-lane.yml", False, True, False, False, ["self-hosted", "macOS", "ARM64", "jovie-mac"]),
        ("workflow_dispatch", "ios-post-merge-quality.yml", True, False, False, True, "macos-15"),
        ("pull_request", "ci.yml", True, False, False, True, "macos-15"),
        ("merge_group", "ci.yml", False, False, False, False, "macos-15"),
    ):
        github = SimpleNamespace(event_name=event, repository="JovieInc/LogYourBody",
                                 workflow_ref=f"JovieInc/LogYourBody/.github/workflows/{caller}@refs/heads/main")
        actual = []
        for line in expressions:
            # Execute these actual boolean/runner expressions with their GitHub
            # operators and functions; the production expressions stay in YAML.
            expression = line.split("${{", 1)[1].split("}}", 1)[0].strip()
            expression = expression.replace("inputs.mac-first", "mac_first").replace("inputs.mac-child", "mac_child")
            expression = re.sub(r"!(?!=)", "not ", expression.replace("&&", " and ").replace("||", " or "))
            actual.append(eval(expression, {"__builtins__": {}}, {
                "github": github, "mac_first": mac_first, "mac_child": mac_child,
                "startsWith": lambda value, prefix: value.startswith(prefix),
                "format": lambda template, value: template.format(value), "fromJSON": json.loads}))
        assert actual == [expected_guard, expected_mac, expected_runner], caller


def test_manual_quality_guard_accepts_only_immutable_same_repository_branch_heads(tmp_path: Path) -> None:
    for index, permission in enumerate(("write", "admin")):
        result = _run_manual_quality_guard(tmp_path / str(index), FAKE_PERMISSION_JSON=json.dumps({"permission": permission}))
        assert result.returncode == 0, result.stderr
        assert f"Qualified source: JovieInc/LogYourBody@{'a' * 40}" in result.stdout
        calls = (tmp_path / str(index) / "api-calls").read_text().splitlines()
        assert calls[-1] == f"repos/JovieInc/LogYourBody/commits/{'a' * 40}/branches-where-head"


def test_manual_quality_guard_rejects_untrusted_refs_before_any_api_or_checkout(tmp_path: Path) -> None:
    cases = [{"CHECKOUT_REF": ref} for ref in ("", "main", "refs/heads/main", "a" * 39, "g" * 40, "A" * 40, "a" * 40 + "\n")]
    cases.extend(({"GITHUB_REPOSITORY": "attacker/fork"}, {"GITHUB_REF": "refs/heads/untrusted"}))
    for index, case in enumerate(cases):
        result = _run_manual_quality_guard(tmp_path / str(index), **case)
        assert result.returncode != 0
        assert "::error::" in result.stdout
        assert not (tmp_path / str(index) / "api-calls").exists()


def test_manual_quality_guard_fails_closed_on_permission_or_source_proof_failure(tmp_path: Path) -> None:
    cases = [{"FAKE_PERMISSION_JSON": json.dumps({"permission": permission})} for permission in ("read", "none", "", "owner")]
    cases.extend(({"GITHUB_TRIGGERING_ACTOR": "reader"}, {"FAKE_PERMISSION_JSON": "{}"},
                  {"FAKE_PERMISSION_JSON": "malformed"}, {"FAKE_GH_ERROR": "true"}))
    cases.extend({"FAKE_BRANCHES_JSON": json.dumps(branches)} for branches in (
        [], [{"name": "wrong-head", "commit": {"sha": "b" * 40}}],
        [{"commit": {"sha": "a" * 40}}], {"wrong-schema": {"name": "x", "commit": {"sha": "a" * 40}}}))
    cases.append({"FAKE_BRANCHES_JSON": "malformed"})
    for index, case in enumerate(cases):
        result = _run_manual_quality_guard(tmp_path / str(index), **case)
        assert result.returncode != 0
        assert "Qualified source:" not in result.stdout
        assert "::error::" in result.stdout


def test_onboarding_golden_path_is_selected_and_requires_exact_passed_evidence() -> None:
    import copy
    import importlib.util
    import pytest

    for workflow, job in (("ci.yml", "ios_quality"),
                          ("ios-post-merge-quality.yml", "quality")):
        assert "uses: ./.github/workflows/ios-quality.yml" in _job_block(workflow, job)
    assert "run: bash scripts/ios/launch-quality-audit.sh" in _job_block(
        "ios-quality.yml", "quality"
    )
    caller = _job_block("ci.yml", "ios")
    assert "      - name:" not in caller, "Reusable calls cannot contain inline steps"

    script = _REPO_ROOT / "scripts/ios/launch-quality-audit.sh"
    source = script.read_text()
    selection = "LAUNCH_QUALITY_UI_TESTS=(" + source.split(
        "LAUNCH_QUALITY_UI_TESTS=(", 1
    )[1].split("UI_RESULT_BUNDLE=", 1)[0]
    result = subprocess.run(
        ["bash", "-e", "-u", "-c", selection +
         '\nprintf "selector:%s\\n" "${UI_SELECTORS[@]}"\n' +
         'printf "evidence:%s\\n" "${UI_EVIDENCE_ARGS[@]}"\n'],
        text=True, capture_output=True, check=False, pass_fds=_coverage_fds(),
    )
    assert result.returncode == 0, result.stderr
    selectors = [line.removeprefix("selector:") for line in result.stdout.splitlines()
                 if line.startswith("selector:")]
    arguments = [line.removeprefix("evidence:") for line in result.stdout.splitlines()
                 if line.startswith("evidence:")]
    golden = "OnboardingGoldenPathUITests/testBodyScoreOnboardingGoldenPathReachesReveal"
    assert selectors.count(f"-only-testing:LogYourBodyUITests/{golden}") == 1
    assert arguments[::2] == ["--expected-test"] * len(selectors)
    expected = arguments[1::2]
    assert expected.count(golden + "()") == 1
    assert len(expected) == len(selectors)

    spec = importlib.util.spec_from_file_location(
        "onboarding_launch_evidence", script.with_name("launch-quality-evidence.py")
    )
    evidence = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(evidence)
    cases = [{"nodeType": "Test Case", "nodeIdentifier": identifier, "result": "Passed"}
             for identifier in expected]
    assert len(evidence.validate_cases({"testNodes": cases}, expected)) == len(expected)
    for state in ("Failed", "Skipped", "missing", "duplicate"):
        invalid = copy.deepcopy(cases)
        golden_case = next(case for case in invalid if case["nodeIdentifier"] == golden + "()")
        if state == "missing":
            invalid.remove(golden_case)
        elif state == "duplicate":
            invalid.append(copy.deepcopy(golden_case))
        else:
            golden_case["result"] = state
        with pytest.raises(ValueError):
            evidence.validate_cases({"testNodes": invalid}, expected)


_MAC_LANE_GH = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAKE_DIR/calls"
args="$*"
if [[ "$args" == *"/dispatches"* ]]; then
  [ -f "$FAKE_DIR/dispatch.json" ] || exit 1
  cat "$FAKE_DIR/dispatch.json"
elif [[ "$args" == *"/cancel"* ]]; then
  echo '{}'
elif [[ "$args" == *"/jobs"* ]]; then
  [ -f "$FAKE_DIR/jobs.json" ] || exit 1
  jq "$(sed -n 's/.*--jq //p' <<<"$args")" "$FAKE_DIR/jobs.json"
elif [[ "$args" == *"/actions/runs/"* ]]; then
  [ -f "$FAKE_DIR/run.json" ] || exit 1
  jq -r "$(sed -n 's/.*--jq //p' <<<"$args")" "$FAKE_DIR/run.json"
else
  exit 1
fi
"""


def _mac_job(status: str, conclusion: Optional[str] = None, failed_step: bool = False) -> dict[str, Any]:
    return {
        "status": status,
        "conclusion": conclusion,
        "runner_name": None if status == "queued" else "tw-mac-001",
        "labels": ["self-hosted", "macOS", "ARM64", "jovie-mac"],
        "steps": [{"name": "Test", "conclusion": "failure" if failed_step else "success"}],
    }


def _run_mac_lane(tmp_path: Path, command: str, env: dict[str, str], **fixtures: Any):
    tmp_path.mkdir(parents=True, exist_ok=True)
    gh = tmp_path / "bin" / "gh"
    gh.parent.mkdir(exist_ok=True)
    gh.write_text(_MAC_LANE_GH)
    gh.chmod(0o755)
    for name, value in fixtures.items():
        (tmp_path / f"{name}.json").write_text(json.dumps(value))
    output = tmp_path / "output"
    output.write_text("")
    (tmp_path / "calls").write_text("")
    result = subprocess.run(
        ["bash", str(_MAC_LANE_SCRIPT), command], text=True, capture_output=True,
        check=False, pass_fds=_coverage_fds(),
        env={**os.environ, "PATH": f"{gh.parent}:{os.environ['PATH']}", "FAKE_DIR": str(tmp_path),
             "GITHUB_OUTPUT": str(output), "GITHUB_SERVER_URL": "server",
             "GH_REPO": "JovieInc/LogYourBody", "LANE": "ios", "FIRST_POLL_SECONDS": "0",
             "POLL_SECONDS": "0", **env},
    )
    outputs = dict(line.split("=", 1) for line in output.read_text().splitlines() if line)
    return result, outputs, (tmp_path / "calls").read_text().splitlines()


_DISPATCH_ENV = {
    "GH_TOKEN": "token", "DISPATCH_REF": "main", "CHECKOUT_SHA": "abc",
    "JOIN_GROUP": "join", "SUPERSEDE_GROUP": "supersede", "PARENT_RUN": "parent",
}


def test_mac_lane_dispatch_joins_on_pickup_and_falls_back_otherwise(tmp_path: Path) -> None:
    result, outputs, calls = _run_mac_lane(
        tmp_path / "picked", "dispatch", _DISPATCH_ENV,
        dispatch={"workflow_run_id": 42}, jobs={"jobs": [_mac_job("in_progress")]},
    )
    assert result.returncode == 0, result.stderr
    assert outputs == {"join_group": "join", "child_run_id": "42", "fallback": "false"}
    assert not any("/cancel" in call for call in calls)

    result, outputs, calls = _run_mac_lane(
        tmp_path / "stuck", "dispatch", {**_DISPATCH_ENV, "MAC_PICKUP_SECONDS": "0"},
        dispatch={"workflow_run_id": 42}, jobs={"jobs": [_mac_job("queued")]},
    )
    assert result.returncode == 0, result.stderr
    assert outputs["fallback"] == "true"
    assert "actions/runs/42/cancel" in calls[-1]

    result, outputs, _ = _run_mac_lane(tmp_path / "no-dispatch", "dispatch", _DISPATCH_ENV)
    assert result.returncode == 0, result.stderr
    assert outputs["fallback"] == "true"
    assert "child_run_id" not in outputs

    result, _, _ = _run_mac_lane(tmp_path / "usage", "bogus", {})
    assert result.returncode == 2


def test_mac_lane_result_passes_fails_or_hands_back_to_hosted(tmp_path: Path) -> None:
    env = {"GH_TOKEN": "token", "CHILD_RUN_ID": "42", "CHECKOUT_SHA": "abc"}
    run = {"display_title": "Mac lane ios @ abc for parent"}
    result, outputs, _ = _run_mac_lane(
        tmp_path / "pass", "result", env, run=run, jobs={"jobs": [_mac_job("completed", "success")]}
    )
    assert (result.returncode, outputs["infra"]) == (0, "false")
    result, outputs, _ = _run_mac_lane(
        tmp_path / "fail", "result", env, run=run,
        jobs={"jobs": [_mac_job("completed", "failure", True)]},
    )
    assert (result.returncode, outputs["infra"]) == (1, "false")
    for index, jobs in enumerate([
        [_mac_job("completed", "failure")],
        [_mac_job("completed", "cancelled")],
        [_mac_job("completed", "timed_out")],
        [],
    ]):
        result, outputs, _ = _run_mac_lane(
            tmp_path / f"lost-{index}", "result", env, run=run, jobs={"jobs": jobs}
        )
        assert (result.returncode, outputs["infra"]) == (0, "true")
    # A child for another SHA, or an unreadable child, is never evidence.
    for index, fixtures in enumerate([
        {"run": {"display_title": "Mac lane ios @ other for parent"},
         "jobs": {"jobs": [_mac_job("completed", "success")]}},
        {"jobs": {"jobs": [_mac_job("completed", "success")]}},
        {"run": run},
    ]):
        result, outputs, _ = _run_mac_lane(tmp_path / f"untrusted-{index}", "result", env, **fixtures)
        assert (result.returncode, outputs["infra"]) == (0, "true")


def test_mac_lanes_route_only_trusted_events_and_carry_no_secrets() -> None:
    route = (_WORKFLOWS / "mac-lane-route.yml").read_text()
    child = (_WORKFLOWS / "mac-lane.yml").read_text()
    assert "contains(fromJSON('[\"merge_group\",\"push\",\"workflow_dispatch\"]'), github.event_name)" in route
    assert "github.event.pull_request.head.repo.full_name == github.repository" in route
    assert "pull_request_target" not in route.split("if: >-", 1)[1].split("runs-on:", 1)[0]
    assert "MAC_PICKUP_SECONDS: '45'" in route
    for text in (route, child):
        assert "secrets." not in text
        assert "secrets: inherit" not in text


def test_heartbeat_is_secretless_and_setup_canary_is_manual() -> None:
    workflow = (_WORKFLOWS / 'mac-runner-heartbeat.yml').read_text()
    heartbeat = _job_block('mac-runner-heartbeat.yml', 'heartbeat')
    canary = _job_block('mac-runner-heartbeat.yml', 'setup-canary')
    assert 'schedule:' not in workflow
    assert '  push:' not in workflow
    assert 'workflow_dispatch:' in workflow
    assert 'pull_request:' not in workflow
    assert 'secrets.' not in workflow
    assert 'checkout' not in heartbeat
    assert "if: github.event_name == 'workflow_dispatch' && inputs.verify-ios-setup" in canary
    assert 'uses: ./.github/actions/setup-ios-build' in canary
    assert 'bundle check' in canary
    assert "create-config-files: 'false'" in canary


def test_ruby_gem_cache_rejects_foreign_native_extensions_and_legacy_keys() -> None:
    step = _ruby_setup_step('Cache Ruby dependencies')
    key = step.split('        key: ', 1)[1].splitlines()[0]
    restores = textwrap.dedent(step.split('        restore-keys: |\n', 1)[1]).splitlines()
    context = {'runner.os': 'macOS', 'runner.arch': 'ARM64',
               'runner.environment': 'self-hosted', 'inputs.cache-key-prefix': 'ios-gems',
               'steps.ruby-version.outputs.version': '3.1.7p261',
               'steps.ruby-version.outputs.abi': 'a' * 64,
               'steps.gemfile-hash.outputs.hash': 'lock-a'}

    def render(template: str, **changes: str) -> str:
        values = {**context, **changes}
        return re.sub(r'\$\{\{\s*(.*?)\s*\}\}', lambda match: values[match[1]], template)

    def can_restore(candidate: str) -> bool:
        return candidate == render(key) or any(candidate.startswith(render(prefix)) for prefix in restores)

    assert can_restore(render(key))
    # A lockfile update may reuse native gems only from the same runtime.
    assert can_restore(render(key, **{'steps.gemfile-hash.outputs.hash': 'lock-b'}))
    assert not can_restore('macOS-ios-gems-ruby-3.1.7p261-lock-a')
    for field, value in [('runner.os', 'Linux'), ('runner.arch', 'X64'),
                         ('runner.environment', 'github-hosted'),
                         ('steps.ruby-version.outputs.version', '3.1.6p260'),
                         ('steps.ruby-version.outputs.abi', 'b' * 64)]:
        assert not can_restore(render(key, **{field: value})), field


def test_ruby_cache_identity_changes_with_runtime_build_and_native_library(tmp_path: Path) -> None:
    binary = tmp_path / 'ruby'
    library = tmp_path / 'libruby.so'
    binary.write_text('ruby build one')
    library.write_text('ruby library one')
    preload = tmp_path / 'rbconfig-fixture.rb'
    preload.write_text(textwrap.dedent('''\
        require 'rbconfig'
        require 'digest'
        RbConfig.define_singleton_method(:ruby) { ENV.fetch('FIXTURE_RUBY') }
        RbConfig::CONFIG['libdir'] = File.dirname(ENV.fetch('FIXTURE_RUBY'))
        RbConfig::CONFIG['LIBRUBY_SO'] = 'libruby.so'
        RbConfig::CONFIG['arch'] = ENV.fetch('FIXTURE_ARCH')
    '''))
    output = tmp_path / 'github-output'

    def probe(arch: str = 'arm64-darwin-25') -> str:
        output.write_text('')
        result = subprocess.run(['bash', '-e', '-c', _ruby_setup_body('Get Ruby version')],
                                env={**os.environ, 'GITHUB_OUTPUT': str(output),
                                     'RUBYOPT': f'-r{preload}', 'FIXTURE_RUBY': str(binary),
                                     'FIXTURE_ARCH': arch}, text=True, capture_output=True,
                                check=False, pass_fds=_coverage_fds())
        assert result.returncode == 0, result.stderr
        values = dict(line.split('=', 1) for line in output.read_text().splitlines())
        assert values['version']
        assert re.fullmatch('[0-9a-f]{64}', values['abi'])
        return values['abi']

    initial = probe()
    assert probe() == initial
    assert probe('x86_64-darwin-25') != initial
    binary.write_text('ruby build two')
    rebuilt = probe()
    assert rebuilt != initial
    library.write_text('ruby library two')
    assert probe() != rebuilt
    # Statically linked Ruby has no separate shared library to fingerprint.
    library.unlink()
    assert probe() == probe()


def test_ruby_setup_fails_when_cached_date_or_psych_cannot_load(tmp_path: Path) -> None:
    bundle = tmp_path / 'bundle'
    bundle.write_text(textwrap.dedent('''\
        #!/usr/bin/env bash
        if [[ "$1" == exec ]]; then
          printf '%s\\n' "$*" >> "$NATIVE_LOAD_CALLS"
          exit "$NATIVE_LOAD_STATUS"
        fi
        echo 'fixture bundle config'
    '''))
    bundle.chmod(0o755)
    marker = tmp_path / 'native-load-calls'
    for status in [0, 1]:
        result = subprocess.run(['bash', '-e', '-c', _ruby_setup_body('Verify Ruby setup')],
                                env={**os.environ, 'PATH': f'{tmp_path}:{os.environ["PATH"]}',
                                     'NATIVE_LOAD_CALLS': str(marker), 'NATIVE_LOAD_STATUS': str(status)},
                                text=True, capture_output=True, check=False, pass_fds=_coverage_fds())
        assert result.returncode == status, result.stderr
    assert len(marker.read_text().splitlines()) == 2
    assert all('exec ruby' in line and 'date' in line and 'psych' in line
               for line in marker.read_text().splitlines())


def test_ruby_setup_loads_locked_native_gems_after_bundler_setup(tmp_path: Path) -> None:
    ruby_api = subprocess.check_output(
        ['ruby', '-rrbconfig', '-e', 'print RbConfig::CONFIG.fetch("ruby_version")'], text=True,
    )
    cache = tmp_path / 'vendor/bundle/ruby' / ruby_api
    (cache / 'specifications').mkdir(parents=True)
    for name in ['date', 'psych', 'json', 'ffi']:
        library = cache / 'gems' / f'{name}-99.0.0' / 'lib'
        library.mkdir(parents=True)
        (cache / 'specifications' / f'{name}-99.0.0.gemspec').write_text(textwrap.dedent(f'''\
            Gem::Specification.new do |spec|
              spec.name = "{name}"
              spec.version = "99.0.0"
              spec.summary = "Offline bundled native dependency fixture"
              spec.authors = ["CI"]
            end
        '''))
        (library / f'{name}.rb').write_text(
            f'raise LoadError, "fixture {name} native load failed" if ENV["BROKEN_NATIVE_GEM"] == "{name}"\n'
            f'puts "Bundled {name} loaded"\n'
        )
    (tmp_path / 'Gemfile').write_text(
        'source "https://rubygems.org"\ngem "date", "99.0.0"\ngem "psych", "99.0.0"\ngem "json", "99.0.0"\ngem "ffi", "99.0.0"\n'
    )
    (tmp_path / 'Gemfile.lock').write_text(textwrap.dedent('''\
        GEM
          remote: https://rubygems.org/
          specs:
            date (99.0.0)
            ffi (99.0.0)
            json (99.0.0)
            psych (99.0.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          date (= 99.0.0)
          ffi (= 99.0.0)
          json (= 99.0.0)
          psych (= 99.0.0)
    '''))
    bundle = tmp_path / 'bundle'
    # Reproduce the failing runner's command-line -r loads before RUBYOPT's
    # bundler/setup on every host Ruby, using the real Bundler and gem loader.
    bundle.write_text(textwrap.dedent('''\
        #!/usr/bin/env bash
        set -euo pipefail
        if [[ "$1" == exec ]]; then
          shift
          command="$1"
          shift
          options=()
          while [[ "$1" != -e ]]; do
            options+=("$1")
            shift
          done
          exec "$command" "${options[@]}" -rbundler/setup "$@"
        fi
        echo 'fixture bundle config'
    '''))
    bundle.chmod(0o755)
    for broken in ['', 'date', 'psych', 'json', 'ffi']:
        result = subprocess.run(
            ['bash', '-e', '-c', _ruby_setup_body('Verify Ruby setup')], cwd=tmp_path,
            env={**os.environ, 'PATH': f'{tmp_path}:{os.environ["PATH"]}', 'RUBYOPT': '',
                 'BUNDLE_GEMFILE': str(tmp_path / 'Gemfile'), 'BUNDLE_PATH': str(tmp_path / 'vendor/bundle'),
                 'BUNDLE_IGNORE_CONFIG': 'true', 'BUNDLE_DEPLOYMENT': 'true', 'BUNDLE_FROZEN': 'true',
                 'BROKEN_NATIVE_GEM': broken},
            text=True, capture_output=True, check=False, pass_fds=_coverage_fds(),
        )
        if broken:
            assert result.returncode != 0
            assert f'fixture {broken} native load failed' in result.stderr
            assert 'Ruby native dependencies loaded' not in result.stdout
        else:
            assert result.returncode == 0, result.stderr
            assert 'Bundled date loaded\nBundled psych loaded\nBundled json loaded\nBundled ffi loaded\nRuby native dependencies loaded' in result.stdout


@pytest.fixture
def live_testmanager_socket(tmp_path: Path):
    import socket

    with socket.socket(socket.AF_UNIX) as live_socket:
        socket_path = tmp_path / 'testmanager.sock'
        live_socket.bind(str(socket_path))
        yield socket_path


def test_simulator_resolver_recovers_stale_testmanager_socket_before_admitting_destination(
    tmp_path: Path, live_testmanager_socket: Path,
) -> None:
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    native = binaries / 'native.py'
    native.write_text(textwrap.dedent('''\
        #!/usr/bin/python3
        import json, os, sys
        from pathlib import Path
        args = sys.argv[1:]
        command = Path(sys.argv[0]).name
        log = Path(os.environ['NATIVE_CALLS'])
        with log.open('a') as stream:
            stream.write(json.dumps([command, *args]) + '\\n')
        scenario = os.environ['NATIVE_SCENARIO']
        events = [json.loads(line) for line in log.read_text().splitlines()]
        restarted = any(e[1:3] == ['simctl', 'shutdown'] for e in events)
        if command == 'xcodebuild':
            assert '-showdestinations' in args
        elif args == ['simctl', 'list', '--json']:
            if scenario == 'inventory-failure':
                sys.exit(72)
            print(os.environ['SIMULATOR_INVENTORY'])
        elif args == ['simctl', 'list', 'runtimes', '--json']:
            print(json.dumps({'runtimes': [] if scenario == 'no-destination' else [
                {'identifier': 'runtime', 'platform': 'iOS', 'version': '26.2', 'isAvailable': True}]}))
        elif args == ['simctl', 'list', 'devicetypes', '--json']:
            print(json.dumps({'devicetypes': [] if scenario == 'no-destination' else [
                {'name': 'iPhone 16', 'identifier': 'iphone'}]}))
        elif args == ['simctl', 'create', 'LYB CI iPhone', 'iphone', 'runtime']:
            print('selected')
        elif args == ['simctl', 'boot', 'selected']:
            if scenario == 'already-booted' or (scenario == 'restart-boot-failure' and restarted):
                sys.exit(149)
        elif args == ['simctl', 'bootstatus', 'selected', '-b']:
            if scenario == 'bootstatus-failure' or (scenario == 'restart-status-failure' and restarted):
                sys.exit(71)
        elif args == ['simctl', 'getenv', 'selected', 'TESTMANAGERD_SIM_SOCK']:
            if scenario == 'getenv-failure':
                sys.exit(72)
            if scenario == 'empty-socket':
                sys.exit(0)
            if scenario == 'regular-file':
                print(os.environ['REGULAR_FILE'])
            elif scenario in ['healthy', 'already-booted', 'discovered', 'created'] or (scenario == 'stale-recovered' and restarted):
                print(os.environ['LIVE_SOCKET'])
            else:
                print(os.environ['LIVE_SOCKET'] + '.missing')
        elif args == ['simctl', 'shutdown', 'selected']:
            if scenario == 'shutdown-failure':
                sys.exit(73)
        else:
            sys.exit('Unexpected native invocation: ' + repr(args))
    '''))
    native.chmod(0o755)
    for name in ['xcrun', 'xcodebuild']:
        (binaries / name).symlink_to(native)
    regular = tmp_path / 'regular-file'
    regular.write_text('A regular file is not a testmanagerd socket.')
    scenarios = {'stale-persistent': 70, 'healthy': 0, 'already-booted': 0,
                 'stale-recovered': 0, 'empty-socket': 70, 'getenv-failure': 70,
                 'regular-file': 70, 'bootstatus-failure': 71, 'shutdown-failure': 73,
                 'restart-boot-failure': 149, 'restart-status-failure': 71,
                 'discovered': 0, 'created': 0, 'no-destination': 70,
                 'inventory-failure': 1, 'inventory-malformed': 1}
    runtime_prefix = 'com.apple.CoreSimulator.SimRuntime.'
    runtimes = [('iOS-26-9', '26.9', True), ('iOS-26-10', '26.10', True),
                ('iOS-27-0', '27.0', False), ('tvOS-26-10', '26.10', True)]
    inventory = {'runtimes': [
        {'identifier': runtime_prefix + name, 'version': version, 'isAvailable': available}
        for name, version, available in runtimes
    ], 'devices': {}}
    def device(name, udid, available=True, state='Shutdown'):
        return {'name': name, 'udid': udid, 'isAvailable': available, 'state': state}
    inventory['devices'] = {
        runtime_prefix + 'iOS-26-9': [device('iPhone 16', 'older')],
        runtime_prefix + 'iOS-26-10': [
            device('iPhone 16', 'unavailable', False), device('iPad Pro', 'ipad'),
            device('iPhone 17', 'newer-model'), device('iPhone 16 Pro', 'pro'),
            device('iPhone 16', 'cold'), device('iPhone 16', 'selected', state='Booted'),
        ],
        runtime_prefix + 'iOS-27-0': [device('iPhone 16', 'unavailable-runtime')],
        runtime_prefix + 'tvOS-26-10': [device('iPhone 16', 'wrong-platform')],
    }
    # A real socket distinguishes healthy launchd state from missing paths or regular files.
    for scenario, expected in scenarios.items():
        calls = tmp_path / f'{scenario}.calls'
        result = subprocess.run(
            ['bash', str(_REPO_ROOT / 'scripts/ios/resolve-simulator-destination.sh')],
            env={**os.environ, 'PATH': f'{binaries}:{os.environ["PATH"]}', 'IOS_DIR': str(tmp_path),
                 'NATIVE_CALLS': str(calls), 'NATIVE_SCENARIO': scenario,
                 'SIMULATOR_INVENTORY': (
                     'invalid-json' if scenario == 'inventory-malformed' else
                     '{"runtimes": [], "devices": {}}' if scenario in ['created', 'no-destination'] else
                     json.dumps(inventory)),
                 'LIVE_SOCKET': str(live_testmanager_socket), 'REGULAR_FILE': str(regular)},
            text=True, capture_output=True, check=False, pass_fds=_coverage_fds(), timeout=10)
        assert result.returncode == expected, (scenario, result.stdout, result.stderr)
        events = [json.loads(line) for line in calls.read_text().splitlines()]
        shutdowns = [e for e in events if e[1:3] == ['simctl', 'shutdown']]
        assert len(shutdowns) == (0 if scenario in ['healthy', 'already-booted', 'bootstatus-failure',
                                                  'discovered', 'created', 'no-destination',
                                                  'inventory-failure', 'inventory-malformed'] else 1)
        assert all(e[3] == 'selected' for e in events if e[0] == 'xcrun' and e[2] in [
            'boot', 'bootstatus', 'getenv', 'shutdown'])
        assert all(e[0] != 'xcodebuild' or '-showdestinations' in e for e in events)
        assert events[0] == ['xcrun', 'simctl', 'list', '--json']
        if scenario != 'no-destination':
            assert not any(e[0] == 'xcodebuild' for e in events), 'Discovery must not resolve Swift packages'
        assert sum(e[1:3] == ['simctl', 'create'] for e in events) == (1 if scenario == 'created' else 0)
        if expected == 0:
            assert result.stdout == 'platform=iOS Simulator,id=selected\n'
            assert events[-1] == ['xcrun', 'simctl', 'getenv', 'selected', 'TESTMANAGERD_SIM_SOCK']
            assert 'ready' in result.stderr
        else:
            assert result.stdout == '', 'An unhealthy simulator must never be admitted to native tests'
            assert 'ready' not in result.stderr


@pytest.mark.parametrize('scenario', [
    'success', 'build-failure', 'build-dirty', 'test-failure', 'skipped', 'duplicate',
    'coverage-failure', 'fourth-test-failure', 'fourth-coverage-failure', 'boot-failure', 'dirty',
])
def test_storekit_lifecycles_use_fresh_devices_and_preserve_failure_evidence(
    tmp_path: Path, live_testmanager_socket: Path, scenario: str,
) -> None:
    cases = ['testAnnualTrialPurchaseRestoreExpiration', 'testMonthlyTrialPurchaseRestoreExpiration',
             'testAnnualTrialPurchaseRestoreRefund', 'testMonthlyTrialPurchaseRestoreRefund']
    root = tmp_path / 'repo'
    (root / 'apps/ios').mkdir(parents=True)
    scripts = root / 'scripts/ios'
    scripts.mkdir(parents=True)
    for name in ['storekit-purchase-restore.sh', 'resolve-simulator-destination.sh', 'launch-quality-evidence.py']:
        (scripts / name).write_bytes((_REPO_ROOT / 'scripts/ios' / name).read_bytes())
    _diagnostic_git(root, 'init', '-q')
    _diagnostic_git(root, 'add', '.')
    _diagnostic_git(root, '-c', 'user.name=CI Test', '-c', 'user.email=ci@example.invalid',
                    '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'StoreKit runner fixture')
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    native = binaries / 'native.py'
    native.write_text(textwrap.dedent('''\
        #!/usr/bin/python3
        import json, os, sys
        from pathlib import Path
        args = sys.argv[1:]
        command = Path(sys.argv[0]).name
        log = Path(os.environ['NATIVE_CALLS'])
        with log.open('a') as stream:
            stream.write(json.dumps([command, *args]) + '\\n')
        scenario = os.environ['NATIVE_SCENARIO']
        if command == 'xcodebuild':
            if '-showdestinations' in args:
                print('{ platform:iOS Simulator, arch:arm64, id:seed, OS:26.2, name:iPhone 16 }')
            elif 'build-for-testing' in args:
                if scenario == 'build-failure':
                    sys.exit(65)
                if scenario == 'build-dirty':
                    Path('changed-source.swift').write_text('unreviewed build generation')
                    os.system('git add changed-source.swift')
            else:
                selector = next((a for a in args if a.startswith('-only-testing:')), '')
                case = selector.rsplit('/', 1)[-1]
                bundle = Path(args[args.index('-resultBundlePath') + 1])
                bundle.mkdir()
                (bundle / 'case').write_text(case)
                if scenario == 'dirty':
                    Path('changed-source.swift').write_text('unreviewed generation')
                    os.system('git add changed-source.swift')
                if scenario == 'test-failure' or (scenario == 'fourth-test-failure' and 'MonthlyTrialPurchaseRestoreRefund' in case):
                    print('No active subscriptions found', flush=True)
                    sys.exit(65)
        elif args == ['simctl', 'list', '--json']:
            print(json.dumps({'runtimes': [{'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-26-2',
                'version': '26.2', 'isAvailable': True}], 'devices': {
                'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [
                    {'name': 'iPhone 16', 'udid': 'seed', 'isAvailable': True}]}}))
        elif args[:4] == ['simctl', 'list', 'devices', 'available']:
            print(json.dumps({'devices': {'runtime': [{'udid': 'seed', 'deviceTypeIdentifier': 'iphone'}]}}))
        elif args[:2] == ['simctl', 'getenv']:
            print(os.environ['LIVE_SOCKET'])
        elif args[:2] == ['simctl', 'create']:
            count = sum('"create"' in line for line in log.read_text().splitlines())
            print(f'fresh-{count}')
        elif args[:2] == ['simctl', 'bootstatus']:
            if scenario == 'boot-failure' and args[2] != 'seed':
                sys.exit(70)
        elif args[:4] == ['xcresulttool', 'get', 'test-results', 'tests']:
            case = (Path(args[-1]) / 'case').read_text()
            result = 'Skipped' if scenario == 'skipped' else 'Passed'
            nodes = [{'nodeType': 'Test Case', 'nodeIdentifier': f'StoreKitPurchaseRestoreTests/{case}()',
                      'result': result}]
            print(json.dumps({'testNodes': nodes * (2 if scenario == 'duplicate' else 1)}))
        elif args[:2] == ['xccov', 'view']:
            case = (Path(args[-1]) / 'case').read_text()
            if scenario == 'coverage-failure' or (scenario == 'fourth-coverage-failure' and 'MonthlyTrialPurchaseRestoreRefund' in case):
                sys.exit(65)
            print('{"targets": []}')
    '''))
    native.chmod(0o755)
    for name in ['xcrun', 'xcodebuild']:
        (binaries / name).symlink_to(native)
    results = tmp_path / scenario
    calls = tmp_path / f'{scenario}.calls'
    result = subprocess.run(['bash', str(scripts / 'storekit-purchase-restore.sh')], cwd=root,
                                env={**os.environ, 'PATH': f'{binaries}:{os.environ["PATH"]}',
                                     'STOREKIT_RESULTS': str(results), 'NATIVE_CALLS': str(calls),
                                     'NATIVE_SCENARIO': scenario, 'LIVE_SOCKET': str(live_testmanager_socket),
                                     'GITHUB_STEP_SUMMARY': ''},
                                text=True, capture_output=True, check=False, pass_fds=_coverage_fds())
    events = [json.loads(line) for line in calls.read_text().splitlines()]
    invocations = [e for e in events if e[0] == 'xcodebuild' and '-showdestinations' not in e]
    builds = [e for e in invocations if 'build-for-testing' in e]
    executions = [e for e in invocations if 'build-for-testing' not in e]
    creates = [e for e in events if e[:3] == ['xcrun', 'simctl', 'create']]
    deletes = [e[-1] for e in events if e[:3] == ['xcrun', 'simctl', 'delete']]
    assert len(builds) == 1, 'Prepare StoreKit once instead of rebuilding every isolated lifecycle'
    assert not any('test' in e for e in executions), 'Lifecycle execution must reuse the reviewed build'
    for invocation in invocations:
        assert invocation[invocation.index('-testPlan') + 1] == 'StoreKit'
        assert invocation[invocation.index('-enableCodeCoverage') + 1] == 'YES'
        assert 'CODE_SIGNING_REQUIRED=NO' in invocation and 'CODE_SIGNING_ALLOWED=NO' in invocation
    assert builds[0][builds[0].index('-destination') + 1] == 'platform=iOS Simulator,id=seed'
    if creates:
        assert events.index(builds[0]) < events.index(creates[0]), 'Build failure must precede lifecycle creation'
    assert 'timeout-minutes: 60' in _job_block('ci.yml', 'ios_storekit')
    # Only devices created by this invocation may be deleted, including on failure.
    assert deletes == [f'fresh-{i + 1}' for i in range(len(creates))], result.stderr
    assert (results / 'source-working-tree.patch').exists()
    assert (results / 'storekit.log').exists()
    for i, (invocation, case) in enumerate(zip(executions, cases)):
        assert invocation[-1] == 'test-without-building'
        assert f'-only-testing:LogYourBodyTests/StoreKitPurchaseRestoreTests/{case}' in invocation
        assert invocation[invocation.index('-destination') + 1] == f'platform=iOS Simulator,id=fresh-{i + 1}'
    if scenario == 'success' or scenario.startswith('fourth-'):
        assert len(executions) == len(creates) == 4
        passed_cases = cases if scenario == 'success' else cases[:3]
        assert result.returncode == (0 if scenario == 'success' else 65), result.stderr + result.stdout
        assert len(list(results.glob('*.evidence.json'))) == len(passed_cases)
        for case in passed_cases:
            receipt = json.loads((results / f'{case}.evidence.json').read_text())
            assert receipt['tests'] == [{'identifier': f'StoreKitPurchaseRestoreTests/{case}()', 'result': 'Passed'}]
            assert receipt['sourceRevision'] == _diagnostic_git(root, 'rev-parse', 'HEAD')
            assert (results / f'{case}.coverage.json').is_file()
        if scenario.startswith('fourth-'):
            assert (results / f'{cases[-1]}.xcresult').is_dir(), 'Retain the failed final bundle without declaring success'
            assert not (results / f'{cases[-1]}.evidence.json').exists()
    else:
        assert result.returncode == (70 if scenario == 'boot-failure' else 65), scenario
        assert len(executions) <= 1, 'A failed lifecycle must not be retried or advance to the next case'
        assert not list(results.glob('*.evidence.json'))
        if scenario.startswith('build-'):
            assert not creates and not executions, 'A failed or source-dirty build must not admit any lifecycle'
        if scenario == 'test-failure':
            assert 'restore returned no active entitlement' in result.stdout


def test_invalid_awaiter_bounds_and_missing_helper_fall_back(tmp_path: Path) -> None:
    cases = [
        {'HEARTBEAT_POLL_ATTEMPTS': '0'},
        {'HEARTBEAT_POLL_INTERVAL_SECONDS': '0'},
        {'RUNNER_HEARTBEAT_QUERY_HELPER': str(tmp_path / 'absent')},
    ]
    for index, overrides in enumerate(cases):
        output = tmp_path / str(index)
        result = subprocess.run(
            ['bash', str(_AWAIT_SCRIPT)], text=True, capture_output=True,
            check=False, pass_fds=_coverage_fds(),
            env={**os.environ, 'GITHUB_OUTPUT': str(output), **overrides},
        )
        assert result.returncode == 0, result.stderr
        assert 'health=down' in output.read_text()
        assert 'probe_state=uncertain' in output.read_text()


def test_failed_query_and_unknown_state_select_hosted(tmp_path: Path) -> None:
    result, outputs, count = _run_await(
        tmp_path / 'unknown', [('down', 'unknown', 'unknown evidence')], attempts=2,
    )
    assert result.returncode == 0, result.stderr
    assert count == 1
    assert outputs['health'] == 'down'
    assert outputs['probe_state'] == 'uncertain'
    query = tmp_path / 'failed-query'
    query.write_text('#!/usr/bin/env bash\nexit 1\n')
    query.chmod(0o755)
    output = tmp_path / 'failed-output'
    result = subprocess.run(
        ['bash', str(_AWAIT_SCRIPT)], text=True, capture_output=True, check=False,
        pass_fds=_coverage_fds(), env={**os.environ, 'GITHUB_OUTPUT': str(output),
                                      'RUNNER_HEARTBEAT_QUERY_HELPER': str(query)},
    )
    assert result.returncode == 0, result.stderr
    assert 'health=down' in output.read_text()
    assert 'trusted heartbeat query failed' in output.read_text()



def test_chat_corpus_selects_public_turns_and_requires_exact_unit_and_ui_passes() -> None:
    import copy
    import importlib.util
    import pytest

    source = (_REPO_ROOT / "scripts/ios/launch-quality-audit.sh").read_text()
    unit = "CHAT_QUALIFICATION_UNIT_TESTS=(" + source.split("CHAT_QUALIFICATION_UNIT_TESTS=(", 1)[1].split("# Launch Quality gates the general unit target.", 1)[0]
    ui = "LAUNCH_QUALITY_UI_TESTS=(" + source.split("LAUNCH_QUALITY_UI_TESTS=(", 1)[1].split("UI_RESULT_BUNDLE=", 1)[0]
    result = subprocess.run(["bash", "-e", "-u", "-c", unit + ui +
        '\nprintf "selector:%s\\n" "${UI_SELECTORS[@]}"\n' +
        'printf "ui:%s\\n" "${UI_EVIDENCE_ARGS[@]}"\n' +
        'printf "unit:%s\\n" "${CHAT_UNIT_EVIDENCE_ARGS[@]}"\n'],
        text=True, capture_output=True, check=False, pass_fds=_coverage_fds())
    assert result.returncode == 0, result.stderr
    selectors = [line.removeprefix("selector:") for line in result.stdout.splitlines() if line.startswith("selector:")]
    expected_ui = [line.removeprefix("ui:") for line in result.stdout.splitlines() if line.startswith("ui:")][1::2]
    expected_unit = [line.removeprefix("unit:") for line in result.stdout.splitlines() if line.startswith("unit:")][1::2]
    required_ui = ["LogYourBodyUITests/" + name + "()" for name in [
        "testHomeV2AskSyntheticFullTurnRestoresAfterRelaunch",
        "testHomeV2AskSyntheticFailedTurnRetriesOriginalIdentity",
        "testHomeV2AskSyntheticCancelledTurnRecovers"]]
    required_unit = ["ChatServiceTests/" + name + "()" for name in [
        "testSyntheticChatCompletionRestoresThroughExistingHistoryPort",
        "testSyntheticChatRetryRetainsOriginalIdentity",
        "testSyntheticChatMissingDoneAndCancelledTurnNeverPersistComplete",
        "testTurnRejectsDelayedReplacementTokenBeforeOpeningStream",
        "testTurnDropsHeldMetadataDeltasCompletionAndFailureAfterReplacement",
        "testTurnSuppressesDelayedProviderErrorButPreservesCurrentErrors",
        "testHistoryLoadRejectsDelayedSuccessEmptyAndErrorAfterOwnershipOrLoadChanges",
        "testHistoryLoadRejectsTokenFromReplacementSessionBeforeSending",
        "testCurrentTurnAcceptsRotatedTokenEventsAndRequiresCompletion"]]
    for identifier in required_ui:
        assert selectors.count("-only-testing:LogYourBodyUITests/" + identifier.removesuffix("()")) == 1
        assert expected_ui.count(identifier) == 1
    assert expected_unit == required_unit
    native_ui = (_REPO_ROOT / 'apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift').read_text()
    completion = native_ui.split('private func assertSyntheticChatCompleted(', 1)[1].split('\n    }', 1)[0]
    # Nested remote queries can exhaust and interrupt the predicate's own waiter
    # even when Retry has already rendered the full answer (run 40752594817).
    assert 'NSPredicate {' not in completion, 'Completion predicates must not issue nested remote UI queries'
    assert '"LogYourBody: " + response' in completion
    assert 'Your fixture trend is stable. Open Timeline to inspect the selected day.' in completion
    rendered = completion.index('answer.waitForExistence(timeout: 8)')
    terminal = completion.index('NSPredicate(format: "label == %@", "Send message")')
    assert rendered < terminal, 'Observe the full answer before waiting for terminal success'
    assert 'object: app.buttons["chat_send_button"]' in completion
    assert re.search(r'XCTAssertTrue\(\s*rendered && completed && answer\.exists,', completion)
    for identifier in ['chat_thinking_indicator', 'chat_recovery_message', 'chat_retry_button']:
        assert re.search(r'XCTAssertFalse\([^\n]*\["' + identifier + r'"\]\.exists\)', completion)
    assert 'XCTAssertTrue(app.textFields["chat_composer"].isHittable)' in completion
    assert '--require-biometric-coverage "${CHAT_UNIT_EVIDENCE_ARGS[@]}"' in source
    spec = importlib.util.spec_from_file_location("chat_corpus_evidence", _REPO_ROOT / "scripts/ios/launch-quality-evidence.py")
    evidence = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(evidence)
    required = required_ui + required_unit
    passed = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": name, "result": "Passed"} for name in required]}
    assert len(evidence.validate_cases(passed, required)) == len(required)
    for index in range(len(required)):
        for status in [None, "Skipped", "Failed"]:
            negative = copy.deepcopy(passed)
            if status is None:
                negative["testNodes"].pop(index)
            else:
                negative["testNodes"][index]["result"] = status
            with pytest.raises(ValueError):
                evidence.validate_cases(negative, required)


def test_slow_chat_fixture_cannot_complete_before_explicit_cancellation() -> None:
    source = (_REPO_ROOT / 'apps/ios/LogYourBody/Services/ChatService.swift').read_text()
    fixture = source.split('struct FixtureChatService: ChatServicing {', 1)[1].split('\n#endif', 1)[0]
    # Both the ephemeral and replay fixture must outlive XCTest's 60s idle wait.
    slow_paths = [fixture.split('case .slow:', 1)[1].split('\n                }', 1)[0],
                  fixture.split('if mode == .slow && row.attempts == 1 && !replayed {', 1)[1]
                  .split('\n            }', 1)[0]]
    for path in slow_paths:
        assert 'try await waitForCancellation()' in path
        assert 'Task.sleep' not in path, 'One elapsed delay cannot end a cancellation fixture'
    wait = fixture.split('private func waitForCancellation() async throws {', 1)[1].split('\n    }', 1)[0]
    assert 'while true {' in wait
    assert 'try Task.checkCancellation()' in wait
    assert 'try await slowTick()' in wait
    assert 'try?' not in wait and 'break' not in wait and 'return' not in wait
    native = (_REPO_ROOT / 'apps/ios/LogYourBodyTests/ChatServiceTests.swift').read_text()
    assert 'elapsedSeconds == 61' in native
    assert 'Slow fixture must remain pending past XCTest quiescence' in native


def verify_coverage(report: Path) -> None:
    suites = json.loads(report.read_text())
    assert list(suites) == ['mac-runner-routing'], 'Unexpected or stale coverage suite'
    coverage = suites['mac-runner-routing']['coverage']
    for script in (_AWAIT_SCRIPT, _QUERY_SCRIPT, _MAC_LANE_SCRIPT, _DISPATCH_GUARD_SCRIPT):
        matches = [value for path, value in coverage.items() if Path(path).resolve() == script.resolve()]
        assert len(matches) == 1, f'Missing coverage for {script.name}'
        lines = matches[0]['lines']
        relevant = [hits for hits in lines if hits is not None]
        assert relevant, f'No executable lines measured in {script.name}'
        covered = sum(hits > 0 for hits in relevant)
        percent = covered / len(relevant) * 100
        assert percent >= 80, f'{script.name}: {percent:.2f}% is below 80%'
        print(f'{script.name}: {covered}/{len(relevant)} lines ({percent:.2f}%)')


def test_coverage_gate_rejects_missing_empty_and_low_coverage(tmp_path: Path) -> None:
    import pytest
    for coverage in [
        {},
        {str(_AWAIT_SCRIPT): {'lines': []}},
        {str(_AWAIT_SCRIPT): {'lines': [0, 0, 1]}},
    ]:
        report = tmp_path / 'report.json'
        report.write_text(json.dumps({'mac-runner-routing': {'coverage': coverage}}))
        with pytest.raises(AssertionError):
            verify_coverage(report)


if __name__ == '__main__':
    verify_coverage(_REPO_ROOT / 'coverage/mac-runner-routing/.resultset.json')


def test_failed_merge_group_cancels_its_mac_jobs_instead_of_holding_them() -> None:
    block = _job_block("ci.yml", "merge-group-fail-fast")
    assert "needs: [detect-changes, mac-runner-routing-tests, js]" in block
    assert "if: github.event_name == 'merge_group' && failure()" in block
    assert 'gh run cancel "$GITHUB_RUN_ID"' in block
    summary = _job_block("ci.yml", "ci-summary")
    # The required check must still conclude after the cancel.
    assert "if: always()" in summary

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


def test_focused_diagnostic_bound_actual_trusted_cli_accepts_only_reviewed_candidate_and_seven_pins(tmp_path: Path) -> None:
    import gzip
    import hashlib
    body = _diagnostic_step('Validate reviewed composed tooling before candidate execution')
    module = _diagnostic_python('DIAGNOSTIC_TOOLING_PY', body)
    expected = 'c4269ae0051375884a623b1b4d3eafd2afd93cc76f4fe1f61efb9fae23ec3928'
    assert module['REVIEWED_AUDIT_SHA256'] == expected
    dependencies = module['DEPENDENCIES']
    assert len(dependencies) == 7
    project_name = 'apps/ios/LogYourBody.xcodeproj/project.pbxproj'
    # Admission must exercise current source bytes, as the real main diagnostic does.
    # Refreshing the policy digest remains an explicit review of the project diff.
    reviewed_project = (_REPO_ROOT / project_name).read_bytes()
    assert hashlib.sha256(reviewed_project).hexdigest() == dependencies[project_name]
    # Routine resolver changes do not authorize new diagnostic tooling either.
    resolver_name = 'scripts/ios/resolve-simulator-destination.sh'
    reviewed_resolver = gzip.decompress(
        (_REPO_ROOT / 'scripts/tests/fixtures/reviewed-diagnostic-resolver.sh.gz').read_bytes())
    assert hashlib.sha256(reviewed_resolver).hexdigest() == dependencies[resolver_name]
    # Keep the prior reviewed project immutable as a refusal fixture in shallow CI.
    previous_project = gzip.decompress(
        (_REPO_ROOT / 'scripts/tests/fixtures/reviewed-diagnostic-project.pbxproj.gz').read_bytes())
    assert hashlib.sha256(previous_project).hexdigest() == '5c4f7e214a1e3e979f9f65a6cefdbd4f715b21c73503d70b3f30a1e78f162c2c'
    # The previous pin was the unlanded candidate. It stays a rejected fixture.
    unlanded = _reviewed_diagnostic_candidate_bytes()
    reviewed = (_REPO_ROOT / 'scripts/ios/launch-quality-audit.sh').read_bytes()
    assert hashlib.sha256(reviewed).hexdigest() == expected
    # Historical refusal fixtures must not be reconstructed from the changing candidate.
    frozen_main = gzip.decompress(
        (_REPO_ROOT / 'scripts/tests/fixtures/diagnostic-audit-ad4098afa11c.sh.gz').read_bytes())
    assert hashlib.sha256(frozen_main).hexdigest() == 'ad4098afa11c60dededb52592a74de1c3374d84f87da891f754b4b47f6aba2aa'
    frozen_branch = gzip.decompress(
        (_REPO_ROOT / 'scripts/tests/fixtures/diagnostic-audit-ffdea3b6fb51.sh.gz').read_bytes())
    assert hashlib.sha256(frozen_branch).hexdigest() == 'ffdea3b6fb517caf8e47ff9ffcc2d348840d59b57c150842b5253dfdb0f16fea'
    previous_main = frozen_main.replace(
        b'  "LogYourBodyUITests/testStatsTruthDrilldownKeepsHeadlineAndFocusWithObservationProvenance"\n',
        b'', 1)
    assert hashlib.sha256(previous_main).hexdigest() == 'd77acce04a7d6eff69ddadcf28e869a703ed3ae98b50921b3625878490c481a8'
    previous_branch = frozen_main.replace(
        b'  # Finish validator shell fixtures before simulator boot competes for host resources.\n'
        b'  python3 "$ROOT_DIR/scripts/ios/test_launch_quality_evidence.py"\n', b'', 1)
    previous_branch = previous_branch.replace(
        b'\nbuild_for_testing_once\n\nCHAT_QUALIFICATION_UNIT_TESTS=(',
        b'\npython3 "$ROOT_DIR/scripts/ios/test_launch_quality_evidence.py"\n'
        b'build_for_testing_once\n\nCHAT_QUALIFICATION_UNIT_TESTS=(', 1)
    assert hashlib.sha256(previous_branch).hexdigest() == '47d6ee6b7d56796527fa0154082f89a46c8a30be0ecfd5ce7e13866a600b633a'
    previous_preflight = previous_main.replace(
        b'  # Finish validator shell fixtures before simulator boot competes for host resources.\n'
        b'  python3 "$ROOT_DIR/scripts/ios/test_launch_quality_evidence.py"\n', b'', 1)
    previous_preflight = previous_preflight.replace(
        b'\nbuild_for_testing_once\n\nCHAT_QUALIFICATION_UNIT_TESTS=(',
        b'\npython3 "$ROOT_DIR/scripts/ios/test_launch_quality_evidence.py"\n'
        b'build_for_testing_once\n\nCHAT_QUALIFICATION_UNIT_TESTS=(', 1)
    assert hashlib.sha256(previous_preflight).hexdigest() == '21f66fca1c8bd7e7a296947f3374c693677bd6cc0e05012419e5f02ec999d459'
    previous_reviewed = previous_preflight.replace(
        b'# Bound the one cold build independently of XCTest execution. Run 40388372132\n'
        b'# missed every Swift package cache and was still compiling test targets at 600s.\n'
        b'# Allow 15m for compilation; keep test timeouts, retries and the outer step cap.\n'
        b'BUILD_FOR_TESTING_TIMEOUT_SECONDS="${BUILD_FOR_TESTING_TIMEOUT_SECONDS:-900}"',
        b'BUILD_FOR_TESTING_TIMEOUT_SECONDS="${BUILD_FOR_TESTING_TIMEOUT_SECONDS:-600}"', 1)
    assert hashlib.sha256(previous_reviewed).hexdigest() == '83b60c92ca78b43d598e37e0f4db68169644844f244b295bb69d54b4776b2ac3'
    # Recover exact old V16 only as inert bytes, to prove real CLI refusal of it.
    legacy = unlanded.decode()
    start = legacy.index('# An unknown mode must fail')
    end = legacy.index('ROOT_DIR=', start)
    legacy = legacy[:start] + legacy[end:]
    start = legacy.index('if [[ "$AUDIT_MODE" == diagnostic-seven ]]; then\n  PROJECT=')
    end = legacy.index('read -r -a XCODEBUILD_SETTINGS_ARRAY', start)
    legacy = legacy[:start] + legacy[end:]
    legacy = legacy.replace('if [[ "$AUDIT_MODE" == full ]]; then\n  bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"\nfi\n',
                            'bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"\n', 1)
    start = legacy.index('    # A diagnostic has one UI command')
    end = legacy.index('    if [[ "$attempt" -eq 1 ]]', start)
    legacy = legacy[:start] + legacy[end:]
    start = legacy.index('# A diagnostic subset never emits')
    end = legacy.index('cd "$IOS_DIR"\n', start)
    legacy = legacy[:start] + legacy[end:]
    legacy = legacy.replace('if [[ "$AUDIT_MODE" == diagnostic-seven ]]; then\n  run_diagnostic_seven\n  exit 0\nfi\n\n', '', 1)
    # Only the rejected frozen V16 fixture predates these 24 current unit witnesses.
    # The current audit's complete ordered list remains checked against Swift below.
    start = legacy.index('  "HomeV2ContextPolicyTests/testBodyFatEditorGateRequiresExplicitRolloutOrAuthenticatedExclusiveFixture"\n')
    end = legacy.index(')\n', start)
    legacy = legacy[:start] + legacy[end:]
    legacy_bytes = legacy.encode()
    assert hashlib.sha256(legacy_bytes).hexdigest() == 'afa2a0a00fbe402626c9b07e3ad0c4b96cffe0b5a3a4943104f2001b6e3c7487'

    sentinel_dir = tmp_path / 'sentinels'
    sentinel_dir.mkdir()
    marker = tmp_path / 'forbidden-helper-or-native-execution'
    # Bootstrap's pinned importer calls node; the pinned resolver calls xcodebuild.
    # No candidate helper or native tool should be reached by this trusted CLI.
    for name in ['node', 'xcodebuild', 'xcrun', 'ruby']:
        executable = sentinel_dir / name
        executable.write_text('#!/bin/bash\nprintf "%s\\n" "$0" >> "$FORBIDDEN_DIAGNOSTIC_EXECUTION"\nexit 99\n')
        executable.chmod(0o700)

    fixtures = ['positive', 'previous-reviewed-project', 'frozen-main-audit', 'frozen-branch-audit', 'previous-main-audit', 'previous-branch-audit', 'previous-preflight-audit', 'previous-reviewed-audit', 'unlanded-candidate', 'legacy-v16', 'marker-only', 'missing-audit', 'wrong-audit',
                'dirty', 'untracked', 'audit-symlink', 'wrong-dependency', 'missing-dependency',
                'dependency-symlink', 'changed-project', 'wrong-resolver', 'current-resolver']
    for scenario in fixtures:
        root = (tmp_path / scenario / 'repo').resolve()
        root.mkdir(parents=True)
        for name, digest in dependencies.items():
            source = _REPO_ROOT / name
            data = (reviewed_project if name == project_name else
                    reviewed_resolver if name == resolver_name else source.read_bytes())
            assert source.is_file() and not source.is_symlink()
            assert hashlib.sha256(data).hexdigest() == digest
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        audit = root / 'scripts/ios/launch-quality-audit.sh'
        audit.write_bytes(reviewed)
        helper = root / 'scripts/ios/bootstrap-local-config.sh'
        if scenario == 'frozen-main-audit':
            audit.write_bytes(frozen_main)
        elif scenario == 'frozen-branch-audit':
            audit.write_bytes(frozen_branch)
        elif scenario == 'previous-main-audit':
            audit.write_bytes(previous_main)
        elif scenario == 'previous-branch-audit':
            audit.write_bytes(previous_branch)
        elif scenario == 'previous-preflight-audit':
            audit.write_bytes(previous_preflight)
        elif scenario == 'previous-reviewed-audit':
            audit.write_bytes(previous_reviewed)
        elif scenario == 'unlanded-candidate':
            audit.write_bytes(unlanded)
        elif scenario == 'legacy-v16':
            audit.write_bytes(legacy_bytes)
        elif scenario == 'marker-only':
            audit.write_text('# diagnostic-seven capability marker is insufficient\n')
        elif scenario == 'missing-audit':
            audit.unlink()
        elif scenario == 'wrong-audit':
            audit.write_bytes(reviewed + b'\n')
        elif scenario == 'audit-symlink':
            audit.unlink()
            audit.symlink_to(helper)
        elif scenario == 'wrong-dependency':
            helper.write_bytes(helper.read_bytes() + b'\n')
        elif scenario == 'wrong-resolver':
            resolver = root / 'scripts/ios/resolve-simulator-destination.sh'
            resolver.write_bytes(resolver.read_bytes() + b'\n')
        elif scenario == 'current-resolver':
            (root / resolver_name).write_bytes((_REPO_ROOT / resolver_name).read_bytes())
        elif scenario == 'missing-dependency':
            helper.unlink()
        elif scenario == 'dependency-symlink':
            helper.unlink()
            helper.symlink_to(audit)
        elif scenario == 'changed-project':
            (root / project_name).write_bytes(reviewed_project + b'\n')
        elif scenario == 'previous-reviewed-project':
            (root / project_name).write_bytes(previous_project)
        _diagnostic_git(root, 'init', '-q')
        _diagnostic_git(root, 'add', '.')
        _diagnostic_git(root, '-c', 'user.name=Diagnostic Test', '-c', 'user.email=diagnostic@example.invalid',
                        '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Isolated reviewed-tooling CLI fixture')
        head = _diagnostic_git(root, 'rev-parse', 'HEAD')
        if scenario == 'dirty':
            helper.write_bytes(helper.read_bytes() + b'\n')
        elif scenario == 'untracked':
            (root / 'unreviewed-hook').write_text('must not execute')
        output_dir = root.parent / 'guard-output'
        output_dir.mkdir()
        output = output_dir / 'diagnostic-trusted-tooling.json'
        # A rejection must also remove any stale positive result.
        output.write_text('{"status":"stale"}')
        env = {**os.environ, 'GITHUB_WORKSPACE': str(root), 'CHECKOUT_REF': head,
               'RUNNER_TEMP': str(output_dir), 'GITHUB_WORKFLOW_SHA': 'b' * 40,
               'PATH': f"{sentinel_dir}:{os.environ['PATH']}",
               'FORBIDDEN_DIAGNOSTIC_EXECUTION': str(marker)}
        result = subprocess.run(['bash', '-c', body], cwd=root, env=env, text=True,
                                capture_output=True, check=False, pass_fds=_coverage_fds())
        assert not marker.exists(), scenario
        if scenario == 'positive':
            assert result.returncode == 0, result.stderr
            receipt = json.loads(output.read_text())
            assert receipt['sourceRevision'] == head
            assert receipt['sourceTree'] == _diagnostic_git(root, 'rev-parse', 'HEAD^{tree}')
            assert receipt['sha256'] == {'scripts/ios/launch-quality-audit.sh': expected, **dependencies}
            assert receipt['policyWorkflowSHA'] == 'b' * 40
            assert not _diagnostic_git(root, 'diff', 'HEAD', '--binary')
            assert not _diagnostic_git(root, 'ls-files', '--others', '--exclude-standard')
        else:
            assert result.returncode != 0 and not output.exists(), scenario
