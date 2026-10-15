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


def test_current_home_diagnostic_cases_use_real_combined_selection_and_passed_evidence() -> None:
    import copy
    import importlib.util
    import re
    import pytest

    source = (_REPO_ROOT / "scripts/ios/launch-quality-audit.sh").read_text()
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
    expected = arguments[1::2]
    assert arguments[::2] == ["--expected-test"] * len(selectors)
    assert len(selectors) == len(set(selectors))
    assert len(expected) == len(set(expected))
    assert expected == [item.removeprefix("-only-testing:LogYourBodyUITests/") + "()"
                        for item in selectors]
    # Explicit acceptance identities are preserved; additional future cases may grow.
    required = [
        'LogYourBodyUITests/testHomeV2AskSyntheticFullTurnRestoresAfterRelaunch',
        'LogYourBodyUITests/testHomeV2AskSyntheticFailedTurnRetriesOriginalIdentity',
        'LogYourBodyUITests/testHomeV2AskSyntheticCancelledTurnRecovers',
        'LogYourBodyUITests/testLaunchQualityGateCapturesCriticalSurfaces',
        'LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFixedCTA',
        'LogYourBodyUITests/testLaunchQualityGateCapturesOnboardingFirstPhotoCTA',
        'LogYourBodyUITests/testLaunchQualityGateCapturesTimelineSurfaces',
        'LogYourBodyUITests/testProfileLogoutSignsOutFromPushedDetail',
        'OnboardingGoldenPathUITests/testBodyScoreOnboardingGoldenPathReachesReveal',
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
        'HomeV2LayoutUITests/testLogSheetHasOneHeadingAndKeepsEntryControls',
        'HomeV2LayoutUITests/testLogSheetEditsUnitsWithKeyboardAndCancelsWithoutChangingHome',
        'HomeV2LayoutUITests/testLogSheetAtLargestTextKeepsValueAndDetailsReachable',
        'HomeV2LayoutUITests/testEditorialDataHeroLabelsVisualEstimate',
        'HomeV2LayoutUITests/testEditorialSingleWeightDoesNotInventAHistory',
        'HomeV2LayoutUITests/testEditorialSingleReadingDoesNotClaimAWeightTrendBehindPhotoOrBodyFat',
        'HomeV2LayoutUITests/testCompositionHomeShowsBodyFatFirstAndHonestSupportingMetrics',
        'HomeV2LayoutUITests/testSupportingMetricTapsOpenTheirOwnProgressWorkspace',
        'HomeV2LayoutUITests/testBodyFatCheckInRefreshesDataHeroWithoutSavingWeight',
        'HomeV2LayoutUITests/testCompositionContextAtLargestTextKeepsEachSupportingMetricReachable',
        'HomeV2LayoutUITests/testBodyFatEditorAtLargestTextPreservesMethodUntilExplicitSelection',
        'HomeV2TimelineIntegrationUITests/testHorizontalPhotoDragPagesPixelsAndMetricsWithoutOpeningViewer',
        'HomeV2TimelineIntegrationUITests/testSelectedWeightOnlyDayNeverBorrowsTodaysBodyFat',
        'HomeV2TimelineIntegrationUITests/testBodyFatCheckInUpdatesSelectedHistoricalPhotoWithoutChangingWeight',
        'HomeV2TimelineIntegrationUITests/testSelectedDayStepsAtLargestTextFollowThePhotoAndRemainReachable',
        'LogYourBodyUITests/testHomeV2PhotoFirstKeepsTheNumberBelowThePhoto',
        'LogYourBodyUITests/testHomeV2ProgressIsOneMetricWorkspace',
        'LogYourBodyUITests/testHomeV2MetricFirstLogsWeightAndConfirmsInPlace',
        'LogYourBodyUITests/testHomeV2ProgressRefreshesAfterEditingAnExistingDay',
        'HomeV2TimelineIntegrationUITests/testVerticalRulerDragDoesNotSelectOrNavigateAndHorizontalScrubStillWorks',
        'HomeV2LayoutUITests/testEditorialWeightOnlyHeroShowsActualSparseReadings',
        'LogYourBodyUITests/testHomeV2ChangingLogDateDoesNotCreateATodayUndoReceipt',
        'ChaosEdgeCaseUITests/testBodyFatEntryRejectsOutOfRangeValues',
        'LogYourBodyUITests/testHomeV2SwipeMovesPhotoDateAndMetricsTogether',
        'LogYourBodyUITests/testHomeV2ScrubberJumpsThroughBodyHistory',
        'LogYourBodyUITests/testHomeV2TimelineCoachMarkDismissesPermanently',
        'HomeV2TimelineIntegrationUITests/testDiagnosticMountedCurrentPhotoCodeRejectsHistoricalIdentity',
        'HomeV2TimelineIntegrationUITests/testDiagnosticMountedHistoricalPhotoCodeRejectsCurrentIdentity',
        'HomeV2TimelineIntegrationUITests/testDiagnosticMountedDefaultGrayAndBlankRejectPhotoIdentity',
        'HomeV2TimelineIntegrationUITests/testSelectedMomentInfersBracketedBodyFatWithProvenance',
    ]
    for identifier in required:
        assert expected.count(identifier + "()") == 1
    for identifier in expected:
        suite, method = identifier.removesuffix("()").split("/")
        swift = (_REPO_ROOT / "apps/ios/LogYourBodyUITests" / (suite + ".swift")).read_text()
        assert len(re.findall(r"func " + re.escape(method) + r"\(", swift)) == 1, identifier
    spec = importlib.util.spec_from_file_location(
        "home_diagnostic_evidence", _REPO_ROOT / "scripts/ios/launch-quality-evidence.py"
    )
    evidence = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(evidence)
    cases = [{"nodeType": "Test Case", "nodeIdentifier": identifier, "result": "Passed"}
             for identifier in expected]
    assert len(evidence.validate_cases({"testNodes": cases}, expected)) == len(expected)
    for identifier in expected:
        for state in ("missing", "Skipped", "Failed", "duplicate"):
            invalid = copy.deepcopy(cases)
            target = next(case for case in invalid if case["nodeIdentifier"] == identifier)
            if state == "missing":
                invalid.remove(target)
            elif state == "duplicate":
                invalid.append(copy.deepcopy(target))
            else:
                target["result"] = state
            with pytest.raises(ValueError):
                evidence.validate_cases({"testNodes": invalid}, expected)
