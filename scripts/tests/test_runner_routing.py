"""Regression tests for exact, conservative per-run CI runner routing."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import textwrap
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

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
    unit = "CHAT_QUALIFICATION_UNIT_TESTS=(" + source.split("CHAT_QUALIFICATION_UNIT_TESTS=(", 1)[1].split("# The whole unit target", 1)[0]
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
        'test_launch_quality_evidence.py': 'print("Ordinary evidence tests")\n',
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
        '83b60c92ca78b43d598e37e0f4db68169644844f244b295bb69d54b4776b2ac3'
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
    assert "REVIEWED_AUDIT_SHA256 = '83b60c92ca78b43d598e37e0f4db68169644844f244b295bb69d54b4776b2ac3'" in source
    assert source.index('Validate manual diagnostic source') < source.index('- uses: actions/checkout@')
    assert source.index('Validate reviewed composed tooling') < source.index('Select hosted Xcode') < source.index('Run fixed seven-case diagnostic')
    assert 'persist-credentials: false' in source and 'python3 -I -' in source
    assert 'run: bash scripts/ios/launch-quality-audit.sh --diagnostic-seven' in source
    assert 'ios-ui-diagnostic-seven-${{ github.run_id }}-${{ github.run_attempt }}' in source
    assert 'retention-days: 14' in source and 'name: Focused UI Diagnostics (NONQUALIFYING)' in source
    import re
    uses = re.findall(r'uses: ([^\s]+)', source)
    assert len(uses) == 3 and all(re.fullmatch(r'[\w-]+/[\w-]+@[0-9a-f]{40}', value) for value in uses)


def _reviewed_diagnostic_candidate_bytes() -> bytes:
    # Exact reviewed source fixture, decoded only for byte comparison/copying.
    # It is never executed. Main's control audit has a distinct reviewed digest.
    import base64
    import hashlib
    import zlib
    payload = (
        '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'
        'o2h5jCFR5jYQtHr3i6nc9FbBfWCDTAkqZtrf+CksNmU2Lg5oi1N6JRMS16CLrpIope+H4P1L72q2UKBVApTZl32z6Q/M2v5g/PN1'
        '67x31ut2tI76TP9eO1NaLRojgV1E4hLiIy+bx6quGx2ANEan9ISDcL9VfNYX31bV19Ee7d4ej/FYnvGYggrj8dz1w/F4v7Ipd61z'
        'iomy0i7hA1F+9Awf+aG1lfj5O4vCm/4pffUNwsn/+vZdBeiLJTTfUYB8ZU7RKnuiUZQypKZYpJz5dEDbVYrpaJFU2pkMq35nw6+Z'
        'qt6NiXHH1UocHUWrEpsONqJS8mqm9SR3YFbmW09oY81yxpWfT/WurzHXpuOZOCvrRagSJ6/jzXuI9fQO7gIz1TLHy/HrwycaQa1R'
        '2YBUb/AWJPNeF61tTIwvO/E1UyCwv6bwQODE7pvqAS4j3Ox14jktuJfq77h/yXWm7z5+c/T5ifiKdxXgARwTLld76FCJBm8QeLIZ'
        'XS2H/CfhqO0PmMg/o/Mf6isOsDC+ujCOulj20huVrQsvvi3vOLFpNRpcD7Hvo37/HOueznrnXSJWaWFM4vKQV31VrTU4XOUb5Mtp'
        'iefzDZOPPz5jBVRrp/n/N+dVCLFh+761gX/l0UD5Tn7r7QM7+Tfv5d+wk/8Re/nX7eTPAW63bf/7o2234/PhQI2VHKXrJoHzV9ea'
        'MoOvEbJHPxR7Jle3QCH0Q1H4t7o2Zi2/Zz53bYujr55+e3QkVuweyeuOlgyq3UuXHvqC9sKA6MgVhdYfVQoaXbSGfOb1etqZ8qG1'
        'hDP1Kh5qXzpO0azeRx3EtUp/G3V/VDoPp3SaYHmfWA4NHOMpunKpoH9hMTRGeHTtaFUPmMZcr7yEa+0JhGuQb1fVnfmg0W4TPrNF'
        '+zh2YTc5RrbKMS/MeVIO7pit1pV90snbpUFuwEqj1lzCtbpUYoF2PEZq/Ikpqb/uieJj3o1eW03Sh7BVabx8SOMa2n4hohhPrAqc'
        '28T3UB4qX+EZDc7d02OhZmACvSe7SXgJ7qVK2KcwtV0EwZ6MEjTQKLxvDFWkqKvYnXDO2PX8TB2I2AWGT7EMbhHLRvPhqS5B/z+f'
        '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'
        'N1OEaJ1WIP8/nTHrNA=='
    )
    data = zlib.decompress(base64.b64decode(payload, validate=True))
    assert len(data) == 53348
    assert hashlib.sha256(data).hexdigest() == '63d78b82d9cffcce75fc7c329cdb3d9d4ceb14d2534574a6e1191dc1efe80392'
    return data


def test_focused_diagnostic_bound_actual_trusted_cli_accepts_only_reviewed_candidate_and_seven_pins(tmp_path: Path) -> None:
    import gzip
    import hashlib
    body = _diagnostic_step('Validate reviewed composed tooling before candidate execution')
    module = _diagnostic_python('DIAGNOSTIC_TOOLING_PY', body)
    expected = '83b60c92ca78b43d598e37e0f4db68169644844f244b295bb69d54b4776b2ac3'
    assert module['REVIEWED_AUDIT_SHA256'] == expected
    dependencies = module['DEPENDENCIES']
    assert len(dependencies) == 7
    project_name = 'apps/ios/LogYourBody.xcodeproj/project.pbxproj'
    # Frozen reviewed bytes from main at 40224a09e; the existing policy digest is unchanged.
    # Ordinary target additions may change the live project without authorizing new diagnostic tooling.
    # Keep this offline fixture so shallow CI checkouts can still exercise the real trusted CLI.
    reviewed_project = gzip.decompress(
        (_REPO_ROOT / 'scripts/tests/fixtures/reviewed-diagnostic-project.pbxproj.gz').read_bytes())
    assert hashlib.sha256(reviewed_project).hexdigest() == dependencies[project_name]
    # The previous pin was the unlanded candidate. It stays a rejected fixture.
    unlanded = _reviewed_diagnostic_candidate_bytes()
    reviewed = (_REPO_ROOT / 'scripts/ios/launch-quality-audit.sh').read_bytes()
    assert hashlib.sha256(reviewed).hexdigest() == expected
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

    fixtures = ['positive', 'unlanded-candidate', 'legacy-v16', 'marker-only', 'missing-audit', 'wrong-audit',
                'dirty', 'untracked', 'audit-symlink', 'wrong-dependency', 'missing-dependency',
                'dependency-symlink', 'changed-project']
    for scenario in fixtures:
        root = (tmp_path / scenario / 'repo').resolve()
        root.mkdir(parents=True)
        for name, digest in dependencies.items():
            source = _REPO_ROOT / name
            data = reviewed_project if name == project_name else source.read_bytes()
            assert source.is_file() and not source.is_symlink()
            assert hashlib.sha256(data).hexdigest() == digest
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        audit = root / 'scripts/ios/launch-quality-audit.sh'
        audit.write_bytes(reviewed)
        helper = root / 'scripts/ios/bootstrap-local-config.sh'
        if scenario == 'unlanded-candidate':
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
        elif scenario == 'missing-dependency':
            helper.unlink()
        elif scenario == 'dependency-symlink':
            helper.unlink()
            helper.symlink_to(audit)
        elif scenario == 'changed-project':
            (root / project_name).write_bytes(reviewed_project + b'\n')
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
