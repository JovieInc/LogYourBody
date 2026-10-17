#!/usr/bin/env bash
# Reports post-merge Launch Quality for main (ios-post-merge-quality.yml "Report").
#
# Env: QUALITY_RESULT, RETRY_RESULT (job results), HEAD_SHA, RUN_URL, GITHUB_REPOSITORY, GH_TOKEN.
# Passed (first attempt or retry): close every open post-merge-lq-red issue. Failed twice: open
# the issue, or comment on the open one, and exit 1. A cancelled first attempt with a skipped
# retry is neutral only when live main has advanced: no issue change, no SHA verification.
# Anything else unfinished is unknown: no issue change, exit 1.
# The open issue is the hold: while it exists, iOS merge groups run Launch Quality again.
#
# CHECK_SUPERSEDED=1 classifies a cancel before Report runs. A newer run of this workflow
# (same concurrency group) or a newer commit on this ref means concurrency cancelled us;
# Report is then skipped. A real cancel of the newest commit stays unknown and fails.
# Listing runs needs actions:read, which this job does not have; a 403 falls through to the
# ref compare, which contents:read can do. Same-SHA dispatch with no newer commit still fails.
set -uo pipefail

label='post-merge-lq-red'
repo="$GITHUB_REPOSITORY"
short="${HEAD_SHA:0:12}"

if [[ "${CHECK_SUPERSEDED:-}" == 1 ]]; then
  superseded=false
  runs_known=false
  if [[ "$QUALITY_RESULT" == cancelled || "${RETRY_RESULT:-}" == cancelled ]]; then
    ref="${REF_NAME:-main}"
    run_id="${RUN_ID:-}"
    if [[ -n "$run_id" ]] && runs=$(gh api "repos/$repo/actions/workflows/ios-post-merge-quality.yml/runs?per_page=20" --jq '[.workflow_runs[] | {id, created_at}]' 2>/dev/null); then
      runs_known=true
      if printf '%s' "$runs" | jq -e --arg run "$run_id" '
        (map(select((.id | tostring) == $run)) | .[0].created_at) as $mine
        | if $mine == null then false
          else any(.[]; (.id | tostring) != $run and .created_at > $mine)
          end
      ' >/dev/null; then
        superseded=true
        echo "Superseded by a newer iOS Post-Merge Launch Quality run."
      fi
    fi
    if [[ "$superseded" == false ]]; then
      if compare=$(gh api "repos/$repo/compare/${HEAD_SHA}...${ref}" --jq '{status: .status, ahead_by: .ahead_by}' 2>/dev/null); then
        status=$(printf '%s' "$compare" | jq -r '.status // empty')
        ahead=$(printf '%s' "$compare" | jq -r '.ahead_by // 0')
        if [[ "$status" == ahead && "$ahead" -gt 0 ]]; then
          superseded=true
          echo "Superseded: $ref is $ahead commit(s) ahead of $short."
        fi
      elif [[ "$runs_known" == false ]]; then
        echo "::warning::Could not list workflow runs or compare $short to $ref; treating the cancel as real."
      fi
    fi
  fi
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "superseded=$superseded" >> "$GITHUB_OUTPUT"
  else
    echo "superseded=$superseded"
  fi
  exit 0
fi

open_issues() {
  gh api "repos/$repo/issues?labels=$label&state=open&per_page=20" --jq '.[].number'
}

if [[ "$QUALITY_RESULT" == 'success' || "${RETRY_RESULT:-}" == 'success' ]]; then
  if ! issues=$(open_issues); then
    echo '::warning::Could not list post-merge-lq-red issues; leaving the hold as it is.'
    exit 0
  fi
  for issue in $issues; do
    gh api -X POST "repos/$repo/issues/$issue/comments" \
      -f body="Launch Quality passed on main at \`$short\` ($RUN_URL). Closing; iOS merge groups are released from the hold." >/dev/null &&
      gh api -X PATCH "repos/$repo/issues/$issue" -f state=closed -f state_reason=completed >/dev/null &&
      echo "Closed #$issue"
  done
  echo "Launch Quality passed on $short."
  exit 0
fi

if [[ "$QUALITY_RESULT" == 'cancelled' && "${RETRY_RESULT:-}" == 'skipped' ]]; then
  # The checkout's origin/main can be stale. Read the live ref; uncertainty fails closed.
  # The cancelled quality job keeps the workflow cancelled, outside the verified-success base.
  if main_sha=$(gh api "repos/$repo/git/ref/heads/main" --jq '.object.sha') &&
    [[ "$main_sha" =~ ^[0-9a-f]{40}$ && "$main_sha" != "$HEAD_SHA" ]]; then
    echo "::notice::Launch Quality cancelled on superseded main SHA $short (main=${main_sha:0:12}); not recording $short as verified."
    exit 0
  fi
fi

if [[ "$QUALITY_RESULT" != 'failure' || "${RETRY_RESULT:-}" != 'failure' ]]; then
  echo "::warning::Launch Quality result unknown (first=$QUALITY_RESULT retry=${RETRY_RESULT:-none}); not recording $short as verified."
  exit 1
fi

if ! issues=$(open_issues); then
  echo '::error::Launch Quality failed twice and the post-merge-lq-red issue could not be listed.'
  exit 1
fi
issue=$(printf '%s\n' "$issues" | head -n 1)
if [[ -n "$issue" ]]; then
  gh api -X POST "repos/$repo/issues/$issue/comments" \
    -f body="Launch Quality failed again on main at \`$short\` after one retry: $RUN_URL" >/dev/null || true
  echo "::error::Launch Quality failed twice on $short; updated #$issue."
else
  gh label create "$label" --repo "$repo" --color B60205 \
    --description 'Post-merge Launch Quality is red on main; iOS merge groups run Launch Quality' >/dev/null 2>&1 || true
  gh api -X POST "repos/$repo/issues" \
    -f title='Post-merge Launch Quality is red on main' \
    -f "labels[]=$label" \
    -f body="Launch Quality failed twice (first attempt and one retry) on main at \`$short\`: $RUN_URL

While this issue is open, iOS merge groups run Launch Quality again, so only a change that passes it can land. The next main SHA that passes closes this issue and releases the hold." >/dev/null || true
  echo "::error::Launch Quality failed twice on $short; opened a post-merge-lq-red issue."
fi
exit 1
