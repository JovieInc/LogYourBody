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
    assert module['REVIEWED_AUDIT_SHA256'] == '31c530d232d92ab814be43ab6e1b549d6bdc40e003f894d9cbba2bc92360ce0d'  # exact reviewed candidate, never the main control audit
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
                      {'GITHUB_EVENT_NAME': 'push'}, {'CHECKOUT_REF': 'main'}, {'CHECKOUT_REF': 'A' * 40},
                      {'GITHUB_RUN_ATTEMPT': '2'}, {'GITHUB_WORKFLOW_SHA': 'c' * 40},
                      {'GITHUB_WORKFLOW_REF': 'candidate-workflow'}, {'PERMISSION': 'read'},
                      {'API_FAIL': 'true'}, {'HEAD_PROVEN': 'false'}]:
        assert run(overrides).returncode != 0
    # Distinct triggering actor gets its own permission check.
    assert run({'GITHUB_TRIGGERING_ACTOR': 'second-writer'}).returncode == 0
    calls = (tmp_path / 'calls').read_text()
    assert '/collaborators/second-writer/permission' in calls


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
    assert source.count('      checkout-ref:\n') == 1
    for forbidden in ['  push:', '  pull_request:', '  schedule:', '  workflow_call:', 'uses: ./', 'mac-lane', 'secrets.']:
        assert forbidden not in source
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
    )
    data = zlib.decompress(base64.b64decode(payload, validate=True))
    assert len(data) == 50980
    assert hashlib.sha256(data).hexdigest() == '31c530d232d92ab814be43ab6e1b549d6bdc40e003f894d9cbba2bc92360ce0d'
    return data


def test_focused_diagnostic_bound_actual_trusted_cli_accepts_only_reviewed_candidate_and_seven_pins(tmp_path: Path) -> None:
    import hashlib
    body = _diagnostic_step('Validate reviewed composed tooling before candidate execution')
    module = _diagnostic_python('DIAGNOSTIC_TOOLING_PY', body)
    expected = '31c530d232d92ab814be43ab6e1b549d6bdc40e003f894d9cbba2bc92360ce0d'
    assert module['REVIEWED_AUDIT_SHA256'] == expected
    dependencies = module['DEPENDENCIES']
    assert len(dependencies) == 7
    reviewed = _reviewed_diagnostic_candidate_bytes()
    # Recover exact old V16 only as inert bytes, to prove real CLI refusal of it.
    legacy = reviewed.decode()
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

    fixtures = ['positive', 'legacy-v16', 'marker-only', 'missing-audit', 'wrong-audit',
                'dirty', 'untracked', 'audit-symlink', 'wrong-dependency', 'missing-dependency',
                'dependency-symlink']
    for scenario in fixtures:
        root = (tmp_path / scenario / 'repo').resolve()
        root.mkdir(parents=True)
        for name, digest in dependencies.items():
            source = _REPO_ROOT / name
            data = source.read_bytes()
            assert source.is_file() and not source.is_symlink()
            assert hashlib.sha256(data).hexdigest() == digest
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        audit = root / 'scripts/ios/launch-quality-audit.sh'
        audit.write_bytes(reviewed)
        helper = root / 'scripts/ios/bootstrap-local-config.sh'
        if scenario == 'legacy-v16':
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
