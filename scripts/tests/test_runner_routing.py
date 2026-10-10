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


def _step_run_script(workflow: str, job_name: str, step_name: str) -> str:
    job = _job_block(workflow, job_name)
    marker = f"      - name: {step_name}\n"
    assert marker in job
    step = job.split(marker, 1)[1]
    run_marker = "        run: |\n"
    assert run_marker in step
    body = step.split(run_marker, 1)[1]
    lines: list[str] = []
    for line in body.splitlines():
        if line.startswith("      - "):
            break
        if not line:
            lines.append("")
            continue
        if not line.startswith("          "):
            break
        lines.append(line[10:])
    return "\n".join(lines) + "\n"


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


def test_route_selects_mac_only_from_healthy_evidence(tmp_path: Path) -> None:
    script = _step_run_script('ci.yml', 'mac-runner-route', 'Select Mac runner route')
    for health, expected in [('up', 'mac'), ('down', 'hosted'), ('', 'hosted'), ('unknown', 'hosted')]:
        output = tmp_path / f'output-{expected}-{health}'
        result = subprocess.run(
            ['bash', '-c', script], text=True, capture_output=True,
            env={**os.environ, 'GITHUB_OUTPUT': str(output), 'HEARTBEAT_HEALTH': health,
                 'HEARTBEAT_EVIDENCE': 'fixture evidence'}, check=False, pass_fds=_coverage_fds(),
        )
        assert result.returncode == 0, result.stderr
        assert output.read_text().strip() == f'runner_class={expected}'


def test_missing_trusted_helper_keeps_hosted_fallback(tmp_path: Path) -> None:
    script = _step_run_script('ci.yml', 'mac-runner-route', 'Query Mac runner heartbeat')
    result = subprocess.run(['bash', '-c', script], cwd=tmp_path,
                            text=True, capture_output=True, check=False, pass_fds=_coverage_fds())
    assert result.returncode == 0, result.stderr


def test_both_ios_jobs_use_opt_in_trusted_route_and_retain_quality_gates() -> None:
    route = _job_block('ci.yml', 'mac-runner-route')
    assert route.count("if: ${{ vars.MAC_RUNNER == 'on' }}") == 2
    assert 'ref: main' in route
    assert 'persist-credentials: false' in route
    assert 'actions: read' in route
    assert 'actions: write' not in route
    assert 'secrets.' not in route
    assert route.count('continue-on-error: true') == 2
    assert "HEARTBEAT_API_TIMEOUT_SECONDS: '5'" in route
    assert "HEARTBEAT_POLL_ATTEMPTS: '1'" in route
    assert 'timeout 60s "$helper"' in route
    for name in ['ios', 'ios_quality']:
        job = _job_block('ci.yml', name)
        assert 'needs: [detect-changes, mac-runner-route]' in job
        assert '''runs-on: ${{ needs.mac-runner-route.outputs.runner_class == 'mac' && fromJSON('["self-hosted","macOS","ARM64","jovie-mac"]') || 'macos-15' }}''' in job
        assert 'uses: ./.github/actions/setup-ios-build' in job
        assert "if: needs.detect-changes.outputs.ios == 'true'" in job
    assert 'bundle exec fastlane ci_ios' in _job_block('ci.yml', 'ios')
    assert 'ci_test_unit' in _job_block('ci.yml', 'ios')
    assert 'launch-quality-audit.sh' in _job_block('ci.yml', 'ios_quality')
    assert 'performance-audit.sh' in _job_block('ci.yml', 'ios_quality')
    summary = _job_block('ci.yml', 'ci-summary')
    assert 'assert_expected_result "iOS Launch Quality Gate"' in summary
    assert 'mac-runner-routing-tests' in summary


def test_heartbeat_is_secretless_and_setup_canary_is_manual() -> None:
    workflow = (_WORKFLOWS / 'mac-runner-heartbeat.yml').read_text()
    heartbeat = _job_block('mac-runner-heartbeat.yml', 'heartbeat')
    canary = _job_block('mac-runner-heartbeat.yml', 'setup-canary')
    assert 'schedule:' in workflow
    assert 'pull_request:' not in workflow
    assert 'secrets.' not in workflow
    assert 'checkout' not in heartbeat
    assert "if: github.event_name == 'workflow_dispatch' && inputs.verify-ios-setup" in canary
    assert 'uses: ./.github/actions/setup-ios-build' in canary
    assert 'bundle check' in canary
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


def verify_coverage(report: Path) -> None:
    suites = json.loads(report.read_text())
    assert list(suites) == ['mac-runner-routing'], 'Unexpected or stale coverage suite'
    coverage = suites['mac-runner-routing']['coverage']
    for script in (_AWAIT_SCRIPT, _QUERY_SCRIPT):
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
