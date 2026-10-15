#!/usr/bin/env bash
# Cancels unfinished merge-group CI runs whose gh-readonly-queue ref is gone.
# When the queue drops or rebuilds a group it deletes that ref, but the old CI
# run keeps queueing for macOS runners. Only a definitive 404 counts as gone;
# any other API error leaves the run alone.
set -uo pipefail

repo="${GITHUB_REPOSITORY:?}"
self="${GITHUB_RUN_ID:-}"

for run_status in queued in_progress waiting pending; do
  gh api "repos/$repo/actions/workflows/ci.yml/runs?event=merge_group&status=$run_status&per_page=100" \
    --jq '.workflow_runs[] | "\(.id) \(.head_branch)"'
done | sort -u | while read -r run_id branch; do
  [[ "$run_id" == "$self" || "$branch" != gh-readonly-queue/* ]] && continue
  ref_lookup=$(gh api "repos/$repo/git/ref/heads/$branch" --silent 2>&1) || true
  if grep -q 'HTTP 404' <<<"$ref_lookup"; then
    gh run cancel "$run_id" -R "$repo" && echo "Cancelled superseded run $run_id ($branch)"
  fi
done
exit 0
